#!/usr/bin/env bash
# @version: 1.7.2
# UserPromptSubmit optimizer — weighted intent, inverted file search,
# scored relevance, function-aware snippets, structured output.
# Exits 0 silently on any failure to avoid blocking input.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
raw_prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)

[[ -z "$raw_prompt" ]] && exit 0
[[ -z "$cwd" ]] && cwd=$(pwd)
[[ ! -d "$cwd" ]] && exit 0

# 1. Normalize
prompt=$(echo "$raw_prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ ${#prompt} -lt 3 ]] && exit 0

# Prompt length guard — very long prompts (pasted diffs, logs) produce poor context
[[ ${#prompt} -gt 8000 ]] && exit 0

# 1b. --y flag detection — must be a suffix, not inline
FORCE_YES_MODE=false
if [[ "$prompt" =~ (^|[[:space:]])--y[[:space:]]*$ ]]; then
  FORCE_YES_MODE=true
  prompt=$(echo "$prompt" | sed 's/[[:space:]]*--y[[:space:]]*$//' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  [[ ${#prompt} -lt 3 ]] && exit 0
fi

# 2. (prompt-cache removed — runs every prompt in-memory)
cache_dir="$CORTEX_ROOT/cache"

# 3. Weighted intent detection — single awk pass (4x fewer subprocesses)
read -r score_bug score_refactor score_feature score_explain < <(
  echo "$prompt" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z' '\n' | awk '
    /^(error|exception|fail|bug|crash|null|undefined|broken|wrong|issue|traceback|stacktrace)$/ { bug++ }
    /^(refactor|improve|optimize|clean|restructure|rename|simplify|rewrite|extract)$/           { ref++ }
    /^(add|create|implement|build|generate|introduce)$/                                          { feat++ }
    /^(explain|describe|understand|review)$/                                                     { expl++ }
    END { print bug+0, ref+0, feat+0, expl+0 }
  '
)

intent="question"
max_score=$((score_bug > score_refactor ? score_bug : score_refactor))
max_score=$((max_score > score_feature ? max_score : score_feature))
max_score=$((max_score > score_explain ? max_score : score_explain))

if [[ $max_score -gt 0 ]]; then
  if [[ $score_bug -eq $max_score ]]; then
    intent="bug_fix"
  elif [[ $score_refactor -eq $max_score ]]; then
    intent="refactor"
  elif [[ $score_feature -eq $max_score ]]; then
    intent="feature_request"
  elif [[ $score_explain -eq $max_score ]]; then
    intent="explain"
  fi
fi

# 3b. Smart command routing — scored keyword matching, auto-inject command prefix
inferred_command=""

# Guard: skip only when the prompt already carries a real slash command (word-boundary
# check prevents "I need to debug this" from suppressing routing)
if ! echo "$prompt" | grep -qE '^\s*/[a-zA-Z]' && \
   ! echo "$prompt" | grep -qE '(^|[[:space:]])/debug\b'; then

  _prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

  # Scored token matching — single awk pass, keeps numeric tokens (401, 500, …)
  read -r _sc_backend _sc_ui _sc_value _sc_perf _sc_history < <(
    echo "$_prompt_lower" | tr -cs 'a-z0-9' '\n' | awk '
      /^(401|403|404|500|502|503|unauthorized|forbidden|jwt|oauth|cors|bearer|token|auth|login|logout|signup|credentials|api|endpoint|webhook|request|response|header|middleware|route|redirect|callback|permission|session|cookie|certificate|ssl|tls)$/ { b++ }
      /^(button|click|render|component|frontend|react|vue|angular|svelte|dom|css|style|modal|form|input|layout|screen|view|visible|display|ui|ux|animation|transition|scroll|event|listener|hover|focus|hydration|mount|props|state)$/                { u++ }
      /^(null|undefined|mismatch|incorrect|empty|wrong|missing|invalid|nan|zero|value|output|result|returns|expected|actual|discrepancy|off|differs)$/                                                                                                { v++ }
      /^(slow|performance|bottleneck|latency|memory|leak|timeout|profile|benchmark|query|index|cache|throughput|cpu|heap|n1|allocat)$/                                                                                                              { p++ }
      /^(history|changed|evolution|blame|introduced|reverted|broke|commit|version|release|rollback|regression|when|degraded|timeline)$/                                                                                                             { h++ }
      END { print b+0, u+0, v+0, p+0, h+0 }
    '
  )

  # Phrase bonuses — multi-word signals not captured by token splitting (+2 each)
  echo "$_prompt_lower" | grep -qE '(request.?failed|access.?denied|not.?authorized|http.?[0-9]{3}|invalid.?token|auth.?error|api.?call|rate.?limit)' \
    && _sc_backend=$((_sc_backend + 2))
  echo "$_prompt_lower" | grep -qE '(not.?working|not.?rendering|not.?showing|not.?loading|not.?visible|wont.?render|doesnt.?render|fails.?to.?mount)' \
    && _sc_ui=$((_sc_ui + 2))
  echo "$_prompt_lower" | grep -qE '(wrong.?value|null.?reference|null.?pointer|undefined.?is.?not|returns.?null|returns.?undefined|incorrect.?value)' \
    && _sc_value=$((_sc_value + 2))
  echo "$_prompt_lower" | grep -qE '(too.?slow|out.?of.?memory|memory.?leak|high.?cpu|slow.?query|n.?plus.?1)' \
    && _sc_perf=$((_sc_perf + 2))

  # Winner selection — backend has priority on exact ties (checked first, others need strict >)
  _max_score=0
  _route_cmd=""

  if [[ $_sc_backend -gt 0 ]]; then
    _max_score=$_sc_backend
    _route_cmd="/debug --backend --deep"
  fi
  [[ $_sc_ui      -gt $_max_score ]] && { _max_score=$_sc_ui;      _route_cmd="/debug --ui"; }
  [[ $_sc_value   -gt $_max_score ]] && { _max_score=$_sc_value;   _route_cmd="/debug --value"; }
  [[ $_sc_perf    -gt $_max_score ]] && { _max_score=$_sc_perf;    _route_cmd="/optimize"; }
  [[ $_sc_history -gt $_max_score ]] && { _max_score=$_sc_history; _route_cmd="/timeline --depth=10"; }

  if [[ -n "$_route_cmd" ]]; then
    inferred_command="$_route_cmd"
  elif [[ "$intent" == "bug_fix" ]]; then
    inferred_command="/debug"
  elif [[ "$intent" == "refactor" ]]; then
    inferred_command="/optimize"
  fi
fi

# 4. Keyword extraction
STOP_WORDS='the|a|an|in|on|at|is|it|to|do|be|of|or|and|for|with|that|this|from|into|when|where|what|why|how|its|are|was|has|had|not|but|can|all|new|get|set|run|use|add|fix'

quoted=$(echo "$prompt" | grep -oE '"[^"]+"' | tr -d '"')
identifiers=$(echo "$prompt" \
  | grep -oE '[A-Z][a-zA-Z0-9]{2,}|[a-z]{3,}_[a-zA-Z0-9_]+|[a-z]+[A-Z][a-zA-Z0-9]+' \
  | grep -viE "^(${STOP_WORDS})$")
keywords=$(printf '%s\n%s' "$identifiers" "$quoted" | sort -u | head -6)

# Extract explicit file paths from stack traces
stack_files=$(echo "$prompt" \
  | grep -oE '[a-zA-Z_][a-zA-Z0-9_/\\.-]+\.(cs|js|ts|tsx|jsx|py|go|java|rb|php|sh|rs)' \
  | sed 's|\\|/|g' \
  | head -5)

# 5. File discovery — cached per session, invalidated when cwd mtime changes
find_code_files() {
  find "$cwd" -type f \
    \( \
      -name "*.cs" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
      -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.java" \
      -o -name "*.rb" -o -name "*.php" -o -name "*.sh" -o -name "*.rs" \
    \) \
    -not -path "*/node_modules/*" \
    -not -path "*/.git/*" \
    -not -path "*/bin/*" \
    -not -path "*/obj/*" \
    -not -path "*/dist/*" \
    -not -path "*/build/*" \
    -not -path "*/.next/*" \
    -not -path "*/vendor/*" \
    -not -path "*/__pycache__/*" \
    -not -path "*/coverage/*" \
    -not -path "*/.cache/*" \
    -not -path "*/logs/*" \
    -not -path "*/tmp/*" \
    -size -500k \
    2>/dev/null
}

_all_code_files=$(find_code_files)

relevant_files=()

# Git-aware prioritization — recently changed files are most likely relevant
while IFS= read -r git_file; do
  [[ -z "$git_file" ]] && continue
  [[ -f "$cwd/$git_file" ]] && relevant_files=("$cwd/$git_file" "${relevant_files[@]}")
done < <(git -C "$cwd" diff --name-only HEAD 2>/dev/null | head -5)

# A. Inverted keyword search — one grep pass across all files for all keywords at once
if [[ -n "$keywords" && -n "$_all_code_files" ]]; then
  kw_pattern=$(echo "$keywords" | paste -sd'|')
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | xargs -d'\n' grep -ilE "$kw_pattern" 2>/dev/null | head -3)
fi

# B. Stack trace: explicit file paths in prompt
while IFS= read -r sf; do
  [[ -z "$sf" ]] && continue
  for candidate in "$cwd/$sf" "$sf"; do
    [[ -f "$candidate" ]] && relevant_files+=("$candidate")
  done
done <<< "$stack_files"

# C. Naming heuristics
for pattern in auth login user service controller handler repository repo; do
  echo "$prompt" | grep -qiE "\b${pattern}\b" || continue
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | grep -iE "${pattern}" | head -2)
done

# Deduplicate, verify existence, cap at 3
mapfile -t deduped < <(
  printf '%s\n' "${relevant_files[@]}" \
  | sort -u \
  | while IFS= read -r f; do [[ -f "$f" ]] && echo "$f"; done \
  | head -3
)

# 6. Scored relevance — find best matching line number per keyword
score_line() {
  local file="$1" kw="$2"
  grep -n -iE "$kw" "$file" 2>/dev/null | head -1 | cut -d: -f1
}

# 7. Function-aware snippet extraction
extract_snippet() {
  local file="$1"
  local anchor="$2"  # line number
  local ext="${file##*.}"

  case "$ext" in
    cs|js|ts|tsx|jsx|java|go|rs)
      # Walk back to nearest function/class/method declaration at or before anchor
      func_start=$(awk -v anchor="$anchor" '
        NR <= anchor && /^\s*(public|private|protected|internal|async|function|func|fn|class|interface|struct|def)\b/ {
          start = NR
        }
        END { print (start > 0 ? start : anchor) }
      ' "$file" 2>/dev/null)

      # Walk forward from func_start to closing brace (brace-depth tracking)
      snippet=$(awk -v s="$func_start" -v max=30 '
        NR < s { next }
        NR == s { depth=0; out=1 }
        out {
          print NR": "$0
          for (i=1; i<=length($0); i++) {
            c = substr($0,i,1)
            if (c=="{") depth++
            if (c=="}") { depth--; if (depth==0 && NR>s) { exit } }
          }
          if (NR - s >= max) exit
        }
      ' "$file" 2>/dev/null)
      ;;
    py)
      # Walk back to nearest def/class, extract 30 lines
      func_start=$(awk -v anchor="$anchor" '
        NR <= anchor && /^(def |class )/ { start = NR }
        END { print (start > 0 ? start : anchor) }
      ' "$file" 2>/dev/null)
      start=$((func_start > 0 ? func_start : anchor))
      snippet=$(sed -n "${start},$((start + 30))p" "$file" 2>/dev/null | nl -ba -v"$start")
      ;;
    *)
      local s=$((anchor - 15)); [[ $s -lt 1 ]] && s=1
      snippet=$(sed -n "${s},$((anchor + 15))p" "$file" 2>/dev/null)
      ;;
  esac

  echo "$snippet"
}

# 8. Build code context
code_context=""
files_used=()

for file in "${deduped[@]}"; do
  rel="${file#$cwd/}"
  files_used+=("$rel")

  best_line=0

  # Score-based line selection across keywords
  while IFS= read -r kw; do
    [[ -z "$kw" ]] && continue
    line=$(score_line "$file" "$kw")
    [[ "$line" =~ ^[0-9]+$ && $line -gt 0 ]] && { best_line=$line; break; }
  done <<< "$keywords"

  # Fallback: plain words from prompt (>=5 chars)
  if [[ $best_line -eq 0 ]]; then
    while IFS= read -r word; do
      [[ -z "$word" ]] && continue
      line=$(grep -n -iF "$word" "$file" 2>/dev/null | head -1 | cut -d: -f1)
      [[ "$line" =~ ^[0-9]+$ && $line -gt 0 ]] && { best_line=$line; break; }
    done < <(echo "$prompt" | grep -oE '[a-zA-Z]{5,}' | sort -u | head -5)
  fi

  if [[ $best_line -gt 0 ]]; then
    snippet=$(extract_snippet "$file" "$best_line")
  else
    snippet=$(head -30 "$file" 2>/dev/null)
  fi

  [[ -z "$snippet" ]] && continue
  ext="${file##*.}"
  code_context="${code_context}
[${rel}]
\`\`\`${ext}
${snippet}
\`\`\`"
done

# 9. Project type detection
project_type="unknown"
profile="$cwd/.cortex/cache/project-profile.json"
if [[ -f "$profile" ]]; then
  project_type=$(jq -r '.projectType // "unknown"' "$profile" 2>/dev/null)
elif [[ -f "$cwd/package.json" ]]; then
  project_type="node"
elif [[ -f "$cwd/Cargo.toml" ]]; then
  project_type="rust"
elif [[ -f "$cwd/go.mod" ]]; then
  project_type="go"
elif [[ -f "$cwd/requirements.txt" || -f "$cwd/pyproject.toml" ]]; then
  project_type="python"
elif [[ -f "$cwd/pom.xml" || -f "$cwd/build.gradle" || -f "$cwd/build.gradle.kts" ]]; then
  project_type="java"
elif find "$cwd" -maxdepth 2 \( -name "*.sln" -o -name "*.csproj" \) -print -quit 2>/dev/null | grep -q .; then
  project_type="dotnet"
fi

# 10. Intent-specific constraints and output hints
files_list=$(IFS=','; echo "${files_used[*]}")
[[ -z "$files_list" ]] && files_list="none identified"

case "$intent" in
  bug_fix)
    constraints="- identify the exact failure point before suggesting a fix
- do not refactor code unrelated to the bug
- avoid breaking changes"
    output_hint="IF BUG:
-> root cause (1 line)
-> fixed code"
    ;;
  feature_request)
    constraints="- follow existing patterns in the codebase
- do not add unnecessary abstractions
- keep changes minimal and focused"
    output_hint="IF FEATURE:
-> final implementation only"
    ;;
  refactor)
    constraints="- preserve all public signatures and behavior
- do not introduce new dependencies
- ensure security and performance are not degraded"
    output_hint="IF REFACTOR:
-> improved code only"
    ;;
  explain)
    constraints="- reference only the provided files
- be precise — avoid vague generalizations"
    output_hint="IF EXPLAIN:
-> precise technical answer (no padding)
-> relevant code references with line numbers"
    ;;
  *)
    constraints="- analyze ONLY provided files
- do not assume missing context"
    output_hint="-> direct answer
-> relevant code if applicable"
    ;;
esac

# 11. Assemble structured prompt
structured="### SYSTEM CONTEXT
You are an expert-level software engineer.

Mode: ULTRA_TECHNICAL
- No simplifications
- No beginner explanations
- Use precise technical language only
- Assume senior-level understanding

Execution Mode: FAST
- Prioritize speed over verbosity
- Give shortest correct solution
- Avoid unnecessary reasoning

Behavior:
- Be decisive, not exploratory
- Do not suggest multiple approaches
- Return final answer immediately

Project Type: ${project_type}
Intent: ${intent}

### RELEVANT FILES
${files_list}"

if [[ -n "$code_context" ]]; then
  structured="${structured}

### CODE CONTEXT
${code_context}"
else
  structured="${structured}

### CODE CONTEXT
NOTE: No relevant code found. Answer based only on the prompt."
fi

structured="${structured}

### TASK
Solve the request immediately.

Priority:
1. Correctness
2. Minimal code
3. Speed

If code is required:
-> Return code FIRST
-> Then optional 1-2 line explanation

Request: ${prompt}

### CONSTRAINTS (MANDATORY)
${constraints}
- Do not assume missing code
- Do not invent APIs or methods
- Use only provided context
- If unsure -> state limitation briefly

### OUTPUT FORMAT (STRICT)
- NO explanations unless necessary
- NO alternative solutions
- NO filler text

${output_hint}

### THINKING CONTROL
- Think internally, do not output reasoning
- Skip analysis steps in response
- Jump directly to solution"

if [[ "$FORCE_YES_MODE" == "true" ]]; then
  structured="${structured}

### GLOBAL ANSWER POLICY (OVERRIDE — applies to all reasoning, decisions, suggestions, assumptions)
- For all yes/no questions -> answer YES
- Do not ask follow-up binary questions
- Proceed with affirmative assumptions
- This overrides normal cautious behavior
- Does NOT override: security constraints, destructive safeguards, system-level protections"
fi

# 12. Emit replacement prompt — prepend inferred command when routing was triggered
if [[ -n "$inferred_command" ]]; then
  jq -n --arg p "${inferred_command}
${structured}" '{"prompt": $p}'
else
  jq -n --arg p "$structured" '{"prompt": $p}'
fi

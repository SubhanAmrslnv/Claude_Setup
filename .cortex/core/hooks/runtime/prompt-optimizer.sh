#!/usr/bin/env bash
# @version: 1.4.0
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

# 2. Prompt cache — skip re-processing identical prompts
cache_dir="$CORTEX_ROOT/cache"
cache_file="$cache_dir/prompt-cache.txt"
prompt_hash=$(echo "$prompt" | cksum | cut -d' ' -f1)
if grep -qF "$prompt_hash" "$cache_file" 2>/dev/null; then
  exit 0
fi
echo "$prompt_hash" >> "$cache_file" 2>/dev/null
# Keep cache bounded
tail -200 "$cache_file" > "${cache_file}.tmp" 2>/dev/null && mv "${cache_file}.tmp" "$cache_file" 2>/dev/null

# 3. Weighted intent detection
score_bug=$(echo "$prompt"     | grep -ioE '\b(error|exception|fail|bug|crash|null|undefined|broken|wrong|issue|traceback|stacktrace)\b' | wc -l)
score_refactor=$(echo "$prompt" | grep -ioE '\b(refactor|improve|optimize|clean|restructure|rename|simplify|rewrite|extract)\b' | wc -l)
score_feature=$(echo "$prompt"  | grep -ioE '\b(add|create|implement|build|generate|introduce)\b' | wc -l)
score_explain=$(echo "$prompt"  | grep -ioE '\b(explain|describe|what is|how does|why does|review|understand|show me)\b' | wc -l)

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

# 3b. Intent override — keyword force (super speed hack: fixes mis-classification)
if echo "$prompt" | grep -qiE 'fix|error|bug|exception'; then
  intent="bug_fix"
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

# 5. File discovery — single pass, inverted search (O(n) not O(n²))
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

# A. Inverted keyword search — one grep pass across all files for all keywords at once
if [[ -n "$keywords" ]]; then
  kw_pattern=$(echo "$keywords" | paste -sd'|')
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | xargs -d'\n' grep -ilE "$kw_pattern" 2>/dev/null | head -3)
fi

# B. Stack trace: explicit file paths in prompt
for sf in $stack_files; do
  for candidate in "$cwd/$sf" "$sf"; do
    [[ -f "$candidate" ]] && relevant_files+=("$candidate")
  done
done

# C. Naming heuristics
for pattern in auth login user service controller handler repository repo; do
  echo "$prompt" | grep -qiE "\b${pattern}\b" || continue
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | grep -iE "${pattern}" | head -2)
done

# Deduplicate, verify existence, cap at 5
mapfile -t deduped < <(
  printf '%s\n' "${relevant_files[@]}" \
  | sort -u \
  | while IFS= read -r f; do [[ -f "$f" ]] && echo "$f"; done \
  | head -3
)

# 6. Scored relevance — pick highest-frequency occurrence, not first match
score_line() {
  local file="$1"
  local kw="$2"
  local best_count=0
  local best_line=0
  while IFS=: read -r lineno rest; do
    [[ "$lineno" =~ ^[0-9]+$ ]] || continue
    count=$(grep -ciE "$kw" "$file" 2>/dev/null || echo 0)
    if [[ $count -gt $best_count ]]; then
      best_count=$count
      best_line=$lineno
    fi
  done < <(grep -n -iE "$kw" "$file" 2>/dev/null)
  echo "$best_line"
}

# 7. Function-aware snippet extraction
extract_snippet() {
  local file="$1"
  local anchor="$2"  # line number
  local ext="${file##*.}"

  # For brace-delimited languages: walk back to nearest function/class boundary
  case "$ext" in
    cs|js|ts|tsx|jsx|java|go|rs)
      # Find the nearest function/class/method declaration at or before anchor
      func_start=$(awk -v anchor="$anchor" '
        NR <= anchor && /^\s*(public|private|protected|internal|async|function|func|fn|class|interface|struct|def)\b/ {
          start = NR
        }
        END { print (start > 0 ? start : anchor) }
      ' "$file" 2>/dev/null)

      # Walk forward from func_start to find closing brace (brace-depth tracking)
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
      # Python: walk back to nearest def/class, extract until dedent
      func_start=$(awk -v anchor="$anchor" '
        NR <= anchor && /^(def |class )/ { start = NR }
        END { print (start > 0 ? start : anchor) }
      ' "$file" 2>/dev/null)
      start=$((func_start > 0 ? func_start : anchor))
      snippet=$(sed -n "${start},$((start + 30))p" "$file" 2>/dev/null | head -30 | nl -ba -v"$start")
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

  # Fallback: plain words from prompt (≥5 chars)
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
elif find "$cwd" -maxdepth 2 \( -name "*.sln" -o -name "*.csproj" \) 2>/dev/null | grep -q .; then
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
→ root cause (1 line)
→ fixed code"
    ;;
  feature_request)
    constraints="- follow existing patterns in the codebase
- do not add unnecessary abstractions
- keep changes minimal and focused"
    output_hint="IF FEATURE:
→ final implementation only"
    ;;
  refactor)
    constraints="- preserve all public signatures and behavior
- do not introduce new dependencies
- ensure security and performance are not degraded"
    output_hint="IF REFACTOR:
→ improved code only"
    ;;
  explain)
    constraints="- reference only the provided files
- be precise — avoid vague generalizations"
    output_hint="IF EXPLAIN:
→ precise technical answer (no padding)
→ relevant code references with line numbers"
    ;;
  *)
    constraints="- analyze ONLY provided files
- do not assume missing context"
    output_hint="→ direct answer
→ relevant code if applicable"
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
→ Return code FIRST
→ Then optional 1–2 line explanation

Request: ${prompt}

### CONSTRAINTS (MANDATORY)
${constraints}
- Do not assume missing code
- Do not invent APIs or methods
- Use only provided context
- If unsure → state limitation briefly

### OUTPUT FORMAT (STRICT)
- NO explanations unless necessary
- NO alternative solutions
- NO filler text

${output_hint}

### THINKING CONTROL
- Think internally, do not output reasoning
- Skip analysis steps in response
- Jump directly to solution"

# 12. Emit replacement prompt
jq -n --arg p "$structured" '{"prompt": $p}'

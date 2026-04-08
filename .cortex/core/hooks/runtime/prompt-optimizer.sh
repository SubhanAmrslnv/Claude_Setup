#!/usr/bin/env bash
# @version: 1.2.0
# UserPromptSubmit optimizer — analyzes prompt, detects intent, finds relevant
# files (function-level snippets only), injects minimal context, outputs a
# structured prompt. Exits 0 silently on any failure to avoid blocking input.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

# UserPromptSubmit delivers payload via stdin, not $TOOL_INPUT
input=$(cat)
raw_prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)

[[ -z "$raw_prompt" ]] && exit 0
[[ -z "$cwd" ]] && cwd=$(pwd)
[[ ! -d "$cwd" ]] && exit 0

# 1. Normalize — trim whitespace
prompt=$(echo "$raw_prompt" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
[[ ${#prompt} -lt 3 ]] && exit 0

# 2. Detect intent
intent="question"
if echo "$prompt" | grep -qiE '\b(fix|error|bug|crash|fail|exception|null|undefined|broken|wrong|issue|traceback|stacktrace)\b'; then
  intent="bug_fix"
elif echo "$prompt" | grep -qiE '\b(add|create|implement|build|generate|new feature|introduce)\b'; then
  intent="feature_request"
elif echo "$prompt" | grep -qiE '\b(refactor|improve|optimize|clean|restructure|rename|simplify|rewrite|extract)\b'; then
  intent="refactor"
elif echo "$prompt" | grep -qiE '\b(explain|describe|what is|how does|why does|review|understand|show me)\b'; then
  intent="explain"
fi

# 3. Relevant file detection

# Common stop words to filter from keyword extraction
STOP_WORDS='the|a|an|in|on|at|is|it|to|do|be|of|or|and|for|with|that|this|from|into|when|where|what|why|how|its|are|was|has|had|not|but|can|all|new|get|set|run|use|add|fix'

# Extract CamelCase, snake_case, and quoted strings as keywords
quoted=$(echo "$prompt" | grep -oE '"[^"]+"' | tr -d '"')
identifiers=$(echo "$prompt" \
  | grep -oE '[A-Z][a-zA-Z0-9]{2,}|[a-z]{3,}_[a-zA-Z0-9_]+|[a-z]+[A-Z][a-zA-Z0-9]+' \
  | grep -viE "^(${STOP_WORDS})$")
keywords=$(printf '%s\n%s' "$identifiers" "$quoted" | sort -u | head -10)

# Extract explicit file paths from stack traces (Unix and Windows paths)
stack_files=$(echo "$prompt" \
  | grep -oE '[a-zA-Z_][a-zA-Z0-9_/\\.-]+\.(cs|js|ts|tsx|jsx|py|go|java|rb|php|sh|rs)' \
  | sed 's|\\|/|g' \
  | head -5)

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
    -size -500k \
    2>/dev/null
}

relevant_files=()

# Cache find output once — avoids repeated full-tree traversals
_all_code_files=$(find_code_files)

# A. Keyword-based: file name matches keyword
while IFS= read -r kw; do
  [[ -z "$kw" ]] && continue
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | grep -i "$kw" | head -2)
done <<< "$keywords"

# B. Stack trace: explicit file paths in prompt
for sf in $stack_files; do
  for candidate in "$cwd/$sf" "$sf"; do
    [[ -f "$candidate" ]] && relevant_files+=("$candidate")
  done
done

# C. Naming heuristics: auth/service/controller/handler
for pattern in auth login user service controller handler repository repo; do
  echo "$prompt" | grep -qiE "\b${pattern}\b" || continue
  while IFS= read -r f; do
    relevant_files+=("$f")
  done < <(echo "$_all_code_files" | grep -iE "${pattern}" | head -2)
done

# Deduplicate without associative arrays — sort unique, keep existing files, cap at 5
mapfile -t deduped < <(
  printf '%s\n' "${relevant_files[@]}" \
  | sort -u \
  | while IFS= read -r f; do [[ -f "$f" ]] && echo "$f"; done \
  | head -5
)

# 4. Extract function-level snippets (±20 lines around best match)
code_context=""
files_used=()

for file in "${deduped[@]}"; do
  rel="${file#$cwd/}"
  files_used+=("$rel")

  best_line=0

  # Try identifier keywords first
  while IFS= read -r kw; do
    [[ -z "$kw" ]] && continue
    line=$(grep -n -iE "$kw" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [[ "$line" =~ ^[0-9]+$ && $line -gt 0 ]] && { best_line=$line; break; }
  done <<< "$keywords"

  # Fallback: plain words from prompt (≥5 chars) when no keyword matched
  if [[ $best_line -eq 0 ]]; then
    while IFS= read -r word; do
      [[ -z "$word" ]] && continue
      line=$(grep -n -iF "$word" "$file" 2>/dev/null | head -1 | cut -d: -f1)
      [[ "$line" =~ ^[0-9]+$ && $line -gt 0 ]] && { best_line=$line; break; }
    done < <(echo "$prompt" | grep -oE '[a-zA-Z]{5,}' | sort -u | head -5)
  fi

  if [[ $best_line -gt 0 ]]; then
    start=$((best_line - 20)); [[ $start -lt 1 ]] && start=1
    snippet=$(sed -n "${start},$((best_line + 20))p" "$file" 2>/dev/null)
  else
    snippet=$(head -40 "$file" 2>/dev/null)
  fi

  [[ -z "$snippet" ]] && continue
  ext="${file##*.}"
  code_context="${code_context}
[${rel}]
\`\`\`${ext}
${snippet}
\`\`\`"
done

# 5. Project type detection — fast file checks before slow find
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

# 6. Build structured prompt — intent-specific constraints and output hints
files_list=$(IFS=','; echo "${files_used[*]}")
[[ -z "$files_list" ]] && files_list="none identified"

structured="Context:
- Project: ${project_type}
- Intent: ${intent}
- Relevant files: [${files_list}]"

[[ -n "$code_context" ]] && structured="${structured}

Code Context:${code_context}"

case "$intent" in
  bug_fix)
    constraints="- identify the exact failure point before suggesting a fix
- do not refactor code unrelated to the bug
- avoid breaking changes"
    output_hint="- root cause analysis
- minimal targeted fix with explanation
- updated code block"
    ;;
  feature_request)
    constraints="- follow existing patterns in the codebase
- do not add unnecessary abstractions
- keep changes minimal and focused"
    output_hint="- implementation plan (files to create/modify)
- updated or new code
- any required config or dependency changes"
    ;;
  refactor)
    constraints="- preserve all public signatures and behavior
- do not introduce new dependencies
- ensure security and performance are not degraded"
    output_hint="- before/after diff summary
- updated code
- confirmation that behavior is preserved"
    ;;
  explain)
    constraints="- reference only the provided files
- be precise — avoid vague generalizations"
    output_hint="- clear explanation of the code or concept
- relevant code references with line numbers
- any non-obvious design decisions"
    ;;
  *)
    constraints="- analyze ONLY provided files
- do not assume missing context"
    output_hint="- direct answer to the question
- relevant code if applicable"
    ;;
esac

structured="${structured}

Task:
${prompt}

Constraints:
${constraints}

Output:
${output_hint}"

# 7. Emit replacement prompt JSON for Claude Code UserPromptSubmit
jq -n --arg p "$structured" '{"prompt": $p}'

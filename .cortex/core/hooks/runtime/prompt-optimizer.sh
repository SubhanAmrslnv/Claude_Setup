#!/usr/bin/env bash
# @version: 1.1.1
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

# 2. Weak prompt expansion (<20 chars)
if [[ ${#prompt} -lt 20 ]]; then
  prompt="Clarify and resolve: $prompt"
fi

# 3. Detect intent
intent="question"
if echo "$prompt" | grep -qiE '\b(fix|error|bug|crash|fail|exception|null|undefined|broken|wrong|issue)\b'; then
  intent="bug_fix"
elif echo "$prompt" | grep -qiE '\b(add|create|implement|build|generate|new feature)\b'; then
  intent="feature_request"
elif echo "$prompt" | grep -qiE '\b(refactor|improve|optimize|clean|restructure|rename|simplify)\b'; then
  intent="refactor"
fi

# 4. Relevant file detection
# Extract CamelCase identifiers and long words from prompt
keywords=$(echo "$prompt" \
  | grep -oE '[A-Z][a-zA-Z0-9]{2,}|[a-z]+[A-Z][a-zA-Z0-9]+' \
  | sort -u | head -8)

# Extract explicit file paths from stack traces
stack_files=$(echo "$prompt" \
  | grep -oE '[a-zA-Z_][a-zA-Z0-9_/.-]+\.(cs|js|ts|tsx|jsx|py|go|java|rb|php|sh)' \
  | head -5)

EXCLUDE_DIRS='/(node_modules|\.git|bin|obj|dist|build|\.next|vendor|__pycache__)/'

find_code_files() {
  find "$cwd" -type f \( \
    -name "*.cs" -o -name "*.js" -o -name "*.ts" -o -name "*.tsx" \
    -o -name "*.jsx" -o -name "*.py" -o -name "*.go" -o -name "*.java" \
    -o -name "*.rb" -o -name "*.php" -o -name "*.sh" -o -name "*.rs" \
  \) 2>/dev/null | grep -viE "$EXCLUDE_DIRS"
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

# 5. Extract function-level snippets (±20 lines around best match)
code_context=""
files_used=()

for file in "${deduped[@]}"; do
  rel="${file#$cwd/}"
  files_used+=("$rel")

  best_line=0
  while IFS= read -r kw; do
    [[ -z "$kw" ]] && continue
    line=$(grep -n -iE "$kw" "$file" 2>/dev/null | head -1 | cut -d: -f1)
    [[ "$line" =~ ^[0-9]+$ && $line -gt 0 ]] && { best_line=$line; break; }
  done <<< "$keywords"

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

# 6. Project type detection
project_type="unknown"
profile="$cwd/.cortex/cache/project-profile.json"
if [[ -f "$profile" ]]; then
  project_type=$(jq -r '.projectType // "unknown"' "$profile" 2>/dev/null)
elif [[ -f "$cwd/package.json" ]]; then
  project_type="node"
elif find "$cwd" -maxdepth 2 \( -name "*.sln" -o -name "*.csproj" \) 2>/dev/null | grep -q .; then
  project_type="dotnet"
elif [[ -f "$cwd/go.mod" ]]; then
  project_type="go"
elif [[ -f "$cwd/requirements.txt" || -f "$cwd/pyproject.toml" ]]; then
  project_type="python"
fi

# 7. Build structured prompt
files_list=$(IFS=','; echo "${files_used[*]}")
[[ -z "$files_list" ]] && files_list="none identified"

structured="Context:
- Project: ${project_type}
- Relevant files: [${files_list}]"

[[ -n "$code_context" ]] && structured="${structured}

Code Context:${code_context}"

structured="${structured}

Task:
${prompt}

Intent:
${intent}

Constraints:
- analyze ONLY provided files
- do NOT assume missing files
- avoid breaking changes
- ensure security and performance

Output:
- root cause (if bug_fix)
- step-by-step fix or implementation
- updated code"

# 8. Emit replacement prompt JSON for Claude Code UserPromptSubmit
jq -n --arg p "$structured" '{"prompt": $p}'

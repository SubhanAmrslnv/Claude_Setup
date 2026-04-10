#!/usr/bin/env bash
# @version: 1.2.0
# PostToolUse code intelligence — analyzes modified files for complexity,
# duplication, naming, and structure issues. Read-only; never modifies files.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

# Supported extensions only
ext="${file##*.}"
case "$ext" in
  cs|js|ts|jsx|tsx) ;;
  *) exit 0 ;;
esac

# Skip files >1MB
size=$(wc -c < "$file" 2>/dev/null || echo 0)
[[ $size -gt 1048576 ]] && exit 0

# Accumulate issues in a temp file; jq -s slurps once at the end (O(1) array assembly)
issue_tmp=$(mktemp)
trap 'rm -f "$issue_tmp"' EXIT

add_issue() {
  jq -n --arg t "$1" --arg m "$2" --argjson l "$3" \
    '{"type":$t,"message":$m,"line":$l}' >> "$issue_tmp" 2>/dev/null
}

# ─── Combined pass: method length + nesting depth ────────────────────────────
# Braces counted once per line; method_depth tracks the current method boundary,
# global_depth tracks cumulative nesting for control-flow checks.

method_name=""
method_start=0
method_depth=0
has_opened=0
global_depth=0
last_reported_bucket=-1
lineno=0

while IFS= read -r line; do
  (( lineno++ ))

  # Count braces once — reused by both method-length and nesting-depth checks
  opens=$(grep -o '{' <<< "$line" | wc -l)
  closes=$(grep -o '}' <<< "$line" | wc -l)

  # --- Method length ---
  if [[ $method_start -eq 0 ]]; then
    if grep -qE \
      '^\s*(public|private|protected|internal|static|async|override|virtual)\b.*\w+\s*\([^)]*\)\s*(\{|$)' \
      <<< "$line" \
      || grep -qE \
      '^\s*(export\s+)?(async\s+)?function\s+\w+|^\s*(const|let|var)\s+\w+\s*=\s*(async\s+)?(\([^)]*\)|\w+)\s*=>|^\s*\w+\s*\([^)]*\)\s*\{' \
      <<< "$line"; then
      method_name=$(grep -oE \
        '(function\s+\w+|\b(public|private|protected)\s+[\w<>\[\]]+\s+\w+\s*\(|\bconst\s+\w+|\blet\s+\w+)' \
        <<< "$line" | head -1 | grep -oE '\w+$')
      [[ -z "$method_name" ]] && method_name="anonymous"
      method_start=$lineno
      method_depth=0
      has_opened=0
    fi
  fi

  if [[ $method_start -gt 0 ]]; then
    (( method_depth += opens - closes ))
    [[ $opens -gt 0 ]] && has_opened=1
    if [[ $has_opened -eq 1 && $method_depth -le 0 ]]; then
      len=$(( lineno - method_start + 1 ))
      if [[ $len -gt 50 ]]; then
        add_issue "complexity" \
          "Method '${method_name}' is ${len} lines — consider splitting into smaller functions" \
          "$method_start"
      fi
      method_start=0
    fi
  fi

  # --- Nesting depth ---
  (( global_depth += opens - closes ))
  [[ $global_depth -lt 0 ]] && global_depth=0

  if grep -qE '^\s*(if|else if|for|foreach|while|switch|catch)\s*[\(\{]' <<< "$line"; then
    if [[ $global_depth -gt 3 ]]; then
      bucket=$(( lineno / 10 ))
      if [[ $bucket -ne $last_reported_bucket ]]; then
        last_reported_bucket=$bucket
        add_issue "complexity" \
          "Nesting depth ${global_depth} exceeds 3 — consider early returns or extracting nested logic" \
          "$lineno"
      fi
    fi
  fi
done < "$file"

# ─── Duplication: repeated 6-line blocks (cksum-based) ──────────────────────

WINDOW=6
total_lines=$(wc -l < "$file")
dup_count=0

if [[ $total_lines -gt $(( WINDOW * 2 )) ]]; then
  declare -A seen_hashes
  i=1
  while [[ $(( i + WINDOW - 1 )) -le $total_lines && $dup_count -lt 2 ]]; do
    block=$(sed -n "${i},$((i + WINDOW - 1))p" "$file" \
      | sed 's/[[:space:]]//g' \
      | grep -v '^$' \
      | grep -v '^//' \
      | grep -v '^#')
    [[ ${#block} -lt 20 ]] && (( i++ )) && continue

    hash=$(echo "$block" | cksum | awk '{print $1}')
    if [[ -n "${seen_hashes[$hash]}" ]]; then
      first=${seen_hashes[$hash]}
      if [[ $(( i - first )) -ge $WINDOW ]]; then
        add_issue "duplication" \
          "Duplicate block detected — similar to lines ${first}–$(( first + WINDOW - 1 ))" \
          "$i"
        (( dup_count++ ))
      fi
    else
      seen_hashes[$hash]=$i
    fi
    (( i++ ))
  done
  unset seen_hashes
fi

# ─── Naming: non-descriptive variable names ──────────────────────────────────

DECL_PATTERN='(const|let|var|int|string|bool|double|float|var)\s+[a-z_]'
naming_count=0
lineno=0

while IFS= read -r line; do
  (( lineno++ ))
  [[ $naming_count -ge 3 ]] && break
  grep -qE '^\s*for\s*\(' <<< "$line" && continue
  if grep -qiE "$DECL_PATTERN" <<< "$line"; then
    name=$(grep -oiE '(const|let|var|int|string|bool|double|float)\s+([a-z_]\w*)' <<< "$line" \
      | awk '{print $NF}' | head -1)
    if grep -qiE '^(tmp|temp|data|obj|foo|bar|baz|val|res|ret|info|stuff|thing|item|elem|el)$' <<< "$name"; then
      add_issue "naming" \
        "Variable '${name}' is not descriptive — use a name that reflects its purpose" \
        "$lineno"
      (( naming_count++ ))
    fi
  fi
done < "$file"

# ─── Structure: file size + mixed concerns ───────────────────────────────────

line_count=$(wc -l < "$file")
if [[ $line_count -gt 500 ]]; then
  add_issue "structure" \
    "File is ${line_count} lines — consider splitting into focused modules" \
    "1"
fi

# Direct grep on file — no cat into memory, stops at first match each
has_ui=0; has_db=0
grep -qiE '(render|component|innerHTML|querySelector|getElementById|template|v-if|ng-if)' "$file" \
  2>/dev/null && has_ui=1
grep -qiE '(query|execute|sql|dbContext|repository|connection|transaction|INSERT|SELECT|UPDATE|DELETE)' "$file" \
  2>/dev/null && has_db=1

if [[ $has_ui -eq 1 && $has_db -eq 1 ]]; then
  add_issue "structure" \
    "File mixes UI rendering and data-access concerns — consider separating into distinct layers" \
    "1"
fi

# ─── Output ──────────────────────────────────────────────────────────────────

issues_json=$(jq -s '.' "$issue_tmp" 2>/dev/null || echo "[]")
issue_count=$(echo "$issues_json" | jq 'length' 2>/dev/null || echo 0)

if [[ $issue_count -gt 0 ]]; then
  rel="${file#$(pwd)/}"
  jq -n \
    --arg path "$rel" \
    --argjson issues "$issues_json" \
    '{"files":[{"path":$path,"issues":$issues}]}'
fi

exit 0

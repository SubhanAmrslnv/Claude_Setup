#!/usr/bin/env bash
# @version: 1.0.0
# PostToolUse code intelligence — analyzes modified files for complexity,
# duplication, naming, and structure issues. Read-only; never modifies files.

command -v jq &>/dev/null || exit 0

input=$(echo "$TOOL_INPUT")
file=$(echo "$input" | jq -r '.file_path // empty' 2>/dev/null)
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

issues_json="[]"

add_issue() {
  local type="$1" message="$2" line="$3"
  issues_json=$(echo "$issues_json" | jq \
    --arg t "$type" --arg m "$message" --argjson l "$line" \
    '. += [{"type":$t,"message":$m,"line":$l}]')
}

# ─── Complexity: method length (>50 lines) ───────────────────────────────────

method_name=""
method_start=0
depth=0
has_opened=0
lineno=0

while IFS= read -r line; do
  (( lineno++ ))

  # Detect method/function start when not already tracking one
  if [[ $method_start -eq 0 ]]; then
    if echo "$line" | grep -qE \
      '^\s*(public|private|protected|internal|static|async|override|virtual)\b.*\w+\s*\([^)]*\)\s*(\{|$)' \
      || echo "$line" | grep -qE \
      '^\s*(export\s+)?(async\s+)?function\s+\w+|^\s*(const|let|var)\s+\w+\s*=\s*(async\s+)?($$[^)]*$$|\w+)\s*=>|^\s*\w+\s*\([^)]*\)\s*\{'; then
      method_name=$(echo "$line" | grep -oE '(function\s+\w+|\b(public|private|protected)\s+[\w<>\[\]]+\s+\w+\s*\(|\bconst\s+\w+|\blet\s+\w+)' | head -1 | grep -oE '\w+$')
      [[ -z "$method_name" ]] && method_name="anonymous"
      method_start=$lineno
      depth=0
      has_opened=0
    fi
  fi

  if [[ $method_start -gt 0 ]]; then
    opens=$(echo "$line" | grep -o '{' | wc -l)
    closes=$(echo "$line" | grep -o '}' | wc -l)
    (( depth += opens - closes ))
    [[ $opens -gt 0 ]] && has_opened=1

    if [[ $has_opened -eq 1 && $depth -le 0 ]]; then
      len=$(( lineno - method_start + 1 ))
      if [[ $len -gt 50 ]]; then
        add_issue "complexity" \
          "Method '${method_name}' is ${len} lines — consider splitting into smaller functions" \
          "$method_start"
      fi
      method_start=0
    fi
  fi
done < "$file"

# ─── Complexity: nesting depth (>3) ─────────────────────────────────────────

depth=0
lineno=0
last_reported_bucket=-1

while IFS= read -r line; do
  (( lineno++ ))
  opens=$(echo "$line" | grep -o '{' | wc -l)
  closes=$(echo "$line" | grep -o '}' | wc -l)
  (( depth += opens - closes ))
  [[ $depth -lt 0 ]] && depth=0

  if echo "$line" | grep -qE '^\s*(if|else if|for|foreach|while|switch|catch)\s*[\(\{]'; then
    if [[ $depth -gt 3 ]]; then
      bucket=$(( lineno / 10 ))
      if [[ $bucket -ne $last_reported_bucket ]]; then
        last_reported_bucket=$bucket
        add_issue "complexity" \
          "Nesting depth ${depth} exceeds 3 — consider early returns or extracting nested logic" \
          "$lineno"
      fi
    fi
  fi
done < "$file"

# ─── Duplication: repeated 6-line blocks (cksum-based) ──────────────────────

WINDOW=6
tmpdir=$(mktemp -d)
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

rm -rf "$tmpdir"

# ─── Naming: non-descriptive variable names ──────────────────────────────────

BAD_NAMES='(^|[^a-zA-Z])(tmp|temp|data|obj|foo|bar|baz|val|res|ret|info|stuff|thing|item|elem|el)([^a-zA-Z]|$)'
DECL_PATTERN='(const|let|var|int|string|bool|double|float|var)\s+[a-z_]'

naming_count=0
lineno=0

while IFS= read -r line; do
  (( lineno++ ))
  [[ $naming_count -ge 3 ]] && break
  echo "$line" | grep -qE '^\s*for\s*\(' && continue
  if echo "$line" | grep -qiE "$DECL_PATTERN"; then
    name=$(echo "$line" | grep -oiE '(const|let|var|int|string|bool|double|float)\s+([a-z_]\w*)' \
      | awk '{print $NF}' | head -1)
    if echo "$name" | grep -qiE '^(tmp|temp|data|obj|foo|bar|baz|val|res|ret|info|stuff|thing|item|elem|el)$'; then
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

source_content=$(cat "$file")
has_ui=0
has_db=0
echo "$source_content" | grep -qiE '(render|component|innerHTML|querySelector|getElementById|template|v-if|ng-if)' && has_ui=1
echo "$source_content" | grep -qiE '(query|execute|sql|dbContext|repository|connection|transaction|INSERT|SELECT|UPDATE|DELETE)' && has_db=1

if [[ $has_ui -eq 1 && $has_db -eq 1 ]]; then
  add_issue "structure" \
    "File mixes UI rendering and data-access concerns — consider separating into distinct layers" \
    "1"
fi

# ─── Output ──────────────────────────────────────────────────────────────────

issue_count=$(echo "$issues_json" | jq 'length')
if [[ $issue_count -gt 0 ]]; then
  rel="${file#$(pwd)/}"
  jq -n \
    --arg path "$rel" \
    --argjson issues "$issues_json" \
    '{"files":[{"path":$path,"issues":$issues}]}'
fi

exit 0

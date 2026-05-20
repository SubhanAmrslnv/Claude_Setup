#!/usr/bin/env bash
# @version: 1.0.0
# Tails project logs (configurable globs), classifies recent ERROR lines.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

project_root="$(dirname "$CORTEX_ROOT")"
mapfile -t patterns < <(jq -r '.debug.logPaths[]? // empty' "$CORTEX_CONFIG" 2>/dev/null)
(( ${#patterns[@]} == 0 )) && patterns=("logs/*.log" "*.log" "npm-debug.log" "stdout_*.log")

shopt -s nullglob globstar
files=()
for pat in "${patterns[@]}"; do
  for f in "$project_root"/$pat "$project_root"/**/$pat; do
    [[ -f "$f" ]] && files+=("$f")
  done
done

errors="[]"
sampled="[]"
for f in "${files[@]:0:5}"; do
  tail_lines=$(tail -n 200 "$f" 2>/dev/null)
  sampled=$(jq -nc --argjson a "$sampled" --arg p "${f#$project_root/}" '$a + [$p]')
  while IFS= read -r line; do
    if grep -qiE '(error|exception|fatal|panic|traceback|fail)' <<<"$line"; then
      errors=$(jq -nc --argjson a "$errors" --arg src "${f#$project_root/}" --arg l "$line" '$a + [{source:$src, line:$l}]')
    fi
  done <<<"$tail_lines"
done

errors=$(jq -c 'if length > 20 then .[-20:] else . end' <<<"$errors")
jq -nc --argjson errors "$errors" --argjson sampled "$sampled" \
  '{kind:"logs", sampled:$sampled, errors:$errors}'

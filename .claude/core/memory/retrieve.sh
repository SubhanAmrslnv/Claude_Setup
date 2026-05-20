#!/usr/bin/env bash
# @version: 1.0.0
# Lazy retrieval — scores files against a query + intent, emits ≤5 paths with
# a single-line structural summary each.
#
# Usage:
#   retrieve.sh <intent> <query>
#
# Output (JSON on stdout):
#   { "intent": "...", "query": "...",
#     "files": [ { "path": "...", "score": N, "summary": "..." }, ... ] }

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

intent="${1:-question}"; shift || true
query="${*:-}"

[[ -z "$query" ]] && { echo '{"intent":"'"$intent"'","query":"","files":[]}'; exit 0; }

index=$(bash "$CORTEX_ROOT/core/memory/index.sh" ensure | tail -n 1)
[[ -f "$index" ]] || { echo '{"intent":"'"$intent"'","query":"'"$query"'","files":[]}'; exit 0; }

# Intent layer hints.
case "$intent" in
  bug_fix|debug)   layer_re='Controller|Service|Repository|Handler|Router' ;;
  feature)         layer_re='Controller|Service|Component|Page|View' ;;
  refactor)        layer_re='Service|Util|Helper|Lib' ;;
  *)               layer_re='' ;;
esac

# Git-changed file set (in the last 5 commits) — small set, used as a +4 boost.
changed=$(git diff --name-only HEAD~5..HEAD 2>/dev/null; git diff --name-only 2>/dev/null)

# Pre-lowercased query tokens (split on whitespace).
qlc=$(echo "$query" | tr '[:upper:]' '[:lower:]')
read -r -a toks <<< "$qlc"

# Score each candidate.
project_root="$(dirname "$CORTEX_ROOT")"
scored=$(awk -v toks="$qlc" -v layer="$layer_re" -v changed="$changed" '
BEGIN { n=split(toks, tk, /[[:space:]]+/) }
{
  path=$0; base=path; sub(/.*\//, "", base)
  plc=tolower(path); blc=tolower(base)
  s=0
  for (i=1;i<=n;i++) {
    if (length(tk[i])<2) continue
    if (index(plc, tk[i])) s+=3
    if (index(blc, tk[i])) s+=5
  }
  if (layer != "" && match(path, layer)) s+=2
  if (changed != "" && index(changed, substr(path,3))) s+=4
  if (s>0) print s "\t" path
}' "$index" | sort -rn | head -n 20)

# Build top-5 with structural summary on the fly.
files_json="[]"
count=0
while IFS=$'\t' read -r score rel; do
  [[ -z "$rel" ]] && continue
  abs="$project_root/${rel#./}"
  [[ -f "$abs" ]] || continue
  summary=$(grep -E '^[[:space:]]*(class|def|function|export|public|private|interface|struct|fn|type)[[:space:]]' "$abs" 2>/dev/null | head -n 3 | tr '\n' '|' | sed 's/|$//')
  files_json=$(jq -nc --argjson a "$files_json" --arg p "$rel" --argjson s "$score" --arg sum "$summary" \
    '$a + [{path:$p, score:$s, summary:$sum}]')
  count=$((count+1))
  (( count >= 5 )) && break
done <<< "$scored"

jq -nc --arg intent "$intent" --arg query "$query" --argjson files "$files_json" \
  '{intent:$intent, query:$query, files:$files}'

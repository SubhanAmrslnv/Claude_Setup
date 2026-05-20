#!/usr/bin/env bash
# @version: 1.0.0
# Merge worker outputs from a worker-pool run directory into one evidence bundle.
#
# Usage: merge-engine.sh <out-dir>
#
# Emits a single JSON object on stdout:
#   { "status": "OK|PARTIAL|FAIL",
#     "completed": ["id", ...],
#     "failed":    ["id", ...],
#     "results":   { "id": <parsed-json-or-string>, ... } }

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

out="${1:-}"
[[ -d "$out" ]] || { echo '{"status":"FAIL","error":"out-dir missing"}'; exit 0; }

done_arr="[]"
[[ -f "$out/_done.json" ]] && done_arr=$(cat "$out/_done.json")

failed_arr="[]"
shopt -s nullglob
for f in "$out"/*.failed; do
  id=$(basename "$f" .failed)
  failed_arr=$(jq -nc --argjson a "$failed_arr" --arg id "$id" '$a + [$id]')
done

results="{}"
for f in "$out"/*.json; do
  name=$(basename "$f" .json)
  [[ "$name" == "_done" ]] && continue
  if jq -e . "$f" >/dev/null 2>&1; then
    results=$(jq -c --slurpfile r "$f" --arg id "$name" '. + {($id): $r[0]}' <<<"$results")
  else
    txt=$(cat "$f" 2>/dev/null)
    results=$(jq -c --arg id "$name" --arg t "$txt" '. + {($id): $t}' <<<"$results")
  fi
done

failed_n=$(jq 'length' <<<"$failed_arr")
done_n=$(jq 'length' <<<"$done_arr")
status="OK"
if   (( failed_n > 0 && done_n > 0 )); then status="PARTIAL"
elif (( failed_n > 0 ));                then status="FAIL"
fi

jq -nc --arg s "$status" --argjson d "$done_arr" --argjson f "$failed_arr" --argjson r "$results" \
  '{status:$s, completed:$d, failed:$f, results:$r}'

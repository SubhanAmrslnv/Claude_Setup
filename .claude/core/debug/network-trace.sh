#!/usr/bin/env bash
# @version: 1.0.0
# Synthetic HTTP probe against the local dev server. Usage:
#   network-trace.sh [--endpoint=/path] [--host=http://localhost:PORT]

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

endpoint="/"
host=""
for arg in "$@"; do
  case "$arg" in
    --endpoint=*) endpoint="${arg#*=}" ;;
    --host=*)     host="${arg#*=}" ;;
  esac
done

# Auto-discover host from process-inspector listening ports if not provided.
if [[ -z "$host" ]]; then
  port=$(bash "$CORTEX_ROOT/core/debug/process-inspector.sh" 2>/dev/null | jq -r '.listening[0].port // empty')
  [[ -n "$port" ]] && host="http://localhost:$port"
fi

[[ -z "$host" ]] && { jq -nc '{kind:"network", status:"SKIP", reason:"no host detected"}'; exit 0; }

url="${host%/}$endpoint"
log="$CORTEX_TEMP/curl-$(date +%s).log"
status=$(curl -sS -o "$log" -w '%{http_code} %{time_total}' --max-time 10 "$url" 2>"$log.err")
code="${status%% *}"
time_s="${status##* }"
body_head=$(head -c 2000 "$log" 2>/dev/null | jq -Rs .)
err_head=$(head -c 500 "$log.err" 2>/dev/null | jq -Rs .)
rm -f "$log" "$log.err"

jq -nc --arg url "$url" --arg code "$code" --arg t "$time_s" --argjson body "${body_head:-\"\"}" --argjson err "${err_head:-\"\"}" \
  '{kind:"network", url:$url, status_code:$code, time_seconds:$t, body_preview:$body, stderr:$err}'

#!/usr/bin/env bash
# @version: 1.0.0
# Parses HAR files dropped under .claude/temp/har/ — surfaces failing requests.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

har_dir="$CORTEX_TEMP/har"
mkdir -p "$har_dir"
shopt -s nullglob
hars=( "$har_dir"/*.har )
(( ${#hars[@]} == 0 )) && { jq -nc '{kind:"browser", status:"SKIP", reason:"no HAR present"}'; exit 0; }

# Pick the most recent HAR.
har="${hars[-1]}"
failed=$(jq -c '[.log.entries[]
  | select(.response.status>=400 or .response.status<100)
  | {url:.request.url, method:.request.method, status:.response.status, time:.time}]' "$har" 2>/dev/null)
[[ -z "$failed" ]] && failed="[]"
count=$(jq 'length' <<<"$failed")

jq -nc --arg har "${har#$CORTEX_ROOT/}" --argjson failed "$failed" --argjson n "$count" \
  '{kind:"browser", har:$har, failed_count:$n, failed:$failed}'

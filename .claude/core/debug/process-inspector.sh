#!/usr/bin/env bash
# @version: 1.0.0
# Reports whether the project's dev server is up, on which port, and PID.
# Cross-platform best-effort: prefers ss → netstat → lsof; falls back to ps.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

project_root="$(dirname "$CORTEX_ROOT")"
mapfile -t ports < <(jq -r '.debug.expectedPorts[]? // empty' "$CORTEX_CONFIG" 2>/dev/null)
(( ${#ports[@]} == 0 )) && ports=(3000 3001 4200 5000 5173 8000 8080 8081 5500)

listening="[]"
for p in "${ports[@]}"; do
  hit=""
  if command -v ss >/dev/null 2>&1; then
    hit=$(ss -ltn 2>/dev/null | awk -v p=":$p$" '$4 ~ p {print $4; exit}')
  elif command -v netstat >/dev/null 2>&1; then
    hit=$(netstat -ano 2>/dev/null | awk -v p=":$p" 'index($2,p) && $1=="TCP" && $4=="LISTENING" {print $2; exit}')
    [[ -z "$hit" ]] && hit=$(netstat -an 2>/dev/null | awk -v p=":$p" 'index($4,p) && /LISTEN/ {print $4; exit}')
  fi
  if [[ -n "$hit" ]]; then
    listening=$(jq -nc --argjson a "$listening" --arg p "$p" --arg b "$hit" '$a + [{port:($p|tonumber), bind:$b}]')
  fi
done

procs=$(ps -ef 2>/dev/null | awk '/(node|npm|next|vite|dotnet|python|uvicorn|gunicorn|java|cargo)/ && !/awk|grep/' | head -n 5 | jq -R . | jq -sc .)
[[ -z "$procs" ]] && procs="[]"

jq -nc --argjson listening "$listening" --argjson procs "$procs" \
  '{kind:"process", listening:$listening, processes:$procs}'

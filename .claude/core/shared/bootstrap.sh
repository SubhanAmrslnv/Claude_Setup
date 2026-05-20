#!/usr/bin/env bash
# @version: 2.0.0
# Cortex shared bootstrap — sourced by every hook.
# Resolves CORTEX_ROOT (strictly project-local), validates the environment,
# defines common directory variables, exposes cortex_config() and publish_event().
#
# Usage in hooks:
#   source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

# ── CORTEX_ROOT: strictly project-local. No $HOME fallback. ──────────────────
if [ -z "${CORTEX_ROOT:-}" ]; then
  export CORTEX_ROOT="$(pwd)/.claude"
fi

if [ ! -d "$CORTEX_ROOT" ]; then
  echo "[cortex] .claude not found at $CORTEX_ROOT — hook disabled." >&2
  return 1 2>/dev/null || exit 0
fi

if ! command -v jq &>/dev/null; then
  echo "[cortex] jq not found — hook disabled." >&2
  return 1 2>/dev/null || exit 0
fi

export CORTEX_CACHE="${CORTEX_ROOT}/cache"
export CORTEX_LOGS="${CORTEX_ROOT}/logs"
export CORTEX_TEMP="${CORTEX_ROOT}/temp"
export CORTEX_STATE="${CORTEX_ROOT}/state"
export CORTEX_EVENTS="${CORTEX_TEMP}/events"
export CORTEX_CONFIG="${CORTEX_ROOT}/config/cortex.config.json"

mkdir -p "$CORTEX_CACHE" "$CORTEX_LOGS" "$CORTEX_TEMP" "$CORTEX_EVENTS" 2>/dev/null

cortex_config() {
  local expr="$1" default="${2:-}"
  if [[ -f "$CORTEX_CONFIG" ]]; then
    local val
    val=$(jq -r "${expr} // empty" "$CORTEX_CONFIG" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return
  fi
  echo "$default"
}

# publish_event <event-name> [<json-payload>]
# Writes one event JSON file to $CORTEX_EVENTS atomically. Returns the file path.
#
# IMPORTANT: large payloads are piped through stdin, never passed via --argjson.
# Earlier versions inlined the full event JSON (often multi-KB, containing file
# paths + source snippets) as a single command-line argument to jq.exe, which
# Windows Defender's ML heuristic flagged as Trojan:Win32/ClickFix.AAC!MTB (a
# pattern shared with malicious giant-command-line loaders). Reading from stdin
# keeps the jq command line short and avoids the false positive.
publish_event() {
  local name="$1" payload="${2:-{\}}"
  [[ -z "$name" ]] && return 1
  local ts ulid file
  ts=$(date -u +%s%3N 2>/dev/null || date -u +%s000)
  ulid="${ts}-$$-${RANDOM}"
  file="${CORTEX_EVENTS}/${ulid}-${name}.json"
  printf '%s' "$payload" | jq -c --arg name "$name" --arg ts "$ts" \
    '{name:$name, ts:$ts, payload:.}' > "${file}.tmp" 2>/dev/null && \
    mv "${file}.tmp" "$file"
  echo "$file"
}

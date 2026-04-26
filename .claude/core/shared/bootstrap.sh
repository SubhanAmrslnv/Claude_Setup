#!/usr/bin/env bash
# @version: 1.0.0
# Cortex shared bootstrap — sourced by every hook.
# Resolves CORTEX_ROOT (project-local only), validates the environment,
# defines common directory variables, and exposes cortex_config().
#
# Usage in hooks (replaces the 7-line CORTEX_ROOT block + jq check):
#   source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
#
# Returns 1 on fatal error so the caller's || exit 0 handles it gracefully.

# ── CORTEX_ROOT: strictly project-local, no global fallback ──────────────────
if [ -z "${CORTEX_ROOT:-}" ]; then
  export CORTEX_ROOT="$(pwd)/.claude"
fi

if [ ! -d "$CORTEX_ROOT" ]; then
  echo "[cortex] ERROR: .claude not found at $CORTEX_ROOT — hook disabled." >&2
  return 1 2>/dev/null || exit 0
fi

# ── Tool availability ─────────────────────────────────────────────────────────
if ! command -v jq &>/dev/null; then
  echo "[cortex] jq not found — hook disabled." >&2
  return 1 2>/dev/null || exit 0
fi

# ── Common directories (exported so subshells see them) ───────────────────────
export CORTEX_CACHE="${CORTEX_ROOT}/cache"
export CORTEX_LOGS="${CORTEX_ROOT}/logs"
export CORTEX_TEMP="${CORTEX_ROOT}/temp"
export CORTEX_STATE="${CORTEX_ROOT}/state"
export CORTEX_CONFIG="${CORTEX_ROOT}/config/cortex.config.json"

mkdir -p "$CORTEX_CACHE" "$CORTEX_LOGS" "$CORTEX_TEMP" 2>/dev/null

# ── cortex_config: reads a jq path from cortex.config.json with a fallback ───
# Usage: val=$(cortex_config '.cache.scanTtlDays' '30')
cortex_config() {
  local expr="$1" default="${2:-}"
  if [[ -f "$CORTEX_CONFIG" ]]; then
    local val
    val=$(jq -r "${expr} // empty" "$CORTEX_CONFIG" 2>/dev/null)
    [[ -n "$val" ]] && echo "$val" && return
  fi
  echo "$default"
}

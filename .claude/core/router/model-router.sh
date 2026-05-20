#!/usr/bin/env bash
# @version: 1.0.0
# Advisory model router — emits one of {haiku, sonnet, opus} for a given intent.
# Default is haiku. Policy read from cortex.config.json → modelPolicy.
#
# Usage:
#   model-router.sh                          # uses $CORTEX_INTENT
#   model-router.sh <intent>
#   model-router.sh escalate <current>       # next tier up; opus is terminal

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

if [[ "${1:-}" == "escalate" ]]; then
  case "${2:-haiku}" in
    haiku)  echo "sonnet" ;;
    sonnet) echo "opus" ;;
    opus)   echo "opus" ;;
    *)      echo "sonnet" ;;
  esac
  exit 0
fi

intent="${1:-${CORTEX_INTENT:-}}"
default=$(cortex_config '.modelPolicy.default' 'haiku')
[[ -z "$intent" ]] && { echo "$default"; exit 0; }

mapped=$(jq -r --arg i "$intent" '.modelPolicy.intents[$i] // empty' "$CORTEX_CONFIG" 2>/dev/null)
echo "${mapped:-$default}"

#!/usr/bin/env bash
# @version: 1.0.0
# Cortex event bus — publish/subscribe over a file-drop queue.
#
# Usage:
#   bus.sh publish <event-name> [<json-payload>]
#   bus.sh dispatch                              # drain the queue once
#
# Hooks invoke `bus.sh publish` and exit. The dispatcher fans out subscribers
# in parallel via worker-pool.sh. Subscribers are listed in subscriptions.json.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

cmd="${1:-}"; shift || true

case "$cmd" in
  publish)
    name="${1:-}"; payload="${2:-}"
    [[ -z "$name" ]] && exit 0
    # If no payload arg given, read stdin (Claude Code passes the tool event there).
    if [[ -z "$payload" && ! -t 0 ]]; then
      payload=$(cat)
    fi
    [[ -z "$payload" ]] && payload="{}"
    # Validate JSON; if not parseable, wrap as raw text. Pipe via stdin (not
    # --arg) so the command line stays small — large command-line blobs trigger
    # Defender's ClickFix heuristic on Windows.
    if ! printf '%s' "$payload" | jq -e . >/dev/null 2>&1; then
      payload=$(printf '%s' "$payload" | jq -Rcs '{raw:.}')
    fi
    publish_event "$name" "$payload" >/dev/null
    # Fire-and-forget dispatch (async; never blocks the hook caller).
    ( bash "$CORTEX_ROOT/core/events/dispatcher.sh" >/dev/null 2>&1 & ) &
    exit 0
    ;;
  dispatch)
    exec bash "$CORTEX_ROOT/core/events/dispatcher.sh"
    ;;
  *)
    echo "usage: bus.sh publish <event-name> [json-payload] | bus.sh dispatch" >&2
    exit 2
    ;;
esac

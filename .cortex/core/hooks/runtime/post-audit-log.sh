#!/usr/bin/env bash
# @version: 1.1.1
# PostToolUse audit logger — appends every tool use to ~/.claude/audit.log.
# Payload delivered via stdin by Claude Code.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
input=$(cat)
tool_name=$(echo "$input" | jq -r '.tool_name // "unknown"' 2>/dev/null || echo "unknown")
tool_input=$(echo "$input" | jq -c '.tool_input // {}' 2>/dev/null || echo "{}")
echo "[$(date '+%Y-%m-%d %H:%M:%S')] ${tool_name}: ${tool_input}" >> ~/.claude/audit.log

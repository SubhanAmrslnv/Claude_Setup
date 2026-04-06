#!/usr/bin/env bash
# @version: 1.2.0
# command-runner.sh — registry-driven command dispatcher.
# Usage: command-runner.sh <command-name>
#        command-runner.sh --list
# Validates the command exists in registry, resolves its path, and outputs it.
# Exit 0 on success (outputs resolved path). Exit 1 on error.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CORTEX_ROOT="${CORTEX_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
REGISTRY="$CORTEX_ROOT/registry/commands.json"
COMMANDS_DIR="$CORTEX_ROOT/commands"

command -v jq &>/dev/null || { echo "ERROR: jq not found — install jq to enable command registry"; exit 1; }

if [[ ! -f "$REGISTRY" ]]; then
  echo "ERROR: Registry not found: $REGISTRY" >&2
  exit 1
fi

if [[ "$1" == "--list" ]]; then
  echo "Available commands:"
  jq -r '.commands[]' "$REGISTRY" | while read -r cmd; do
    echo "  /$cmd"
  done
  exit 0
fi

if [[ -z "${1:-}" ]]; then
  echo "Usage: command-runner.sh <command-name>" >&2
  echo "       command-runner.sh --list" >&2
  exit 1
fi

cmd_name="$1"

# Validate command exists in registry
if ! jq -e --arg name "$cmd_name" '[.commands[]] | index($name) != null' "$REGISTRY" | grep -q true; then
  echo "ERROR: Command '$cmd_name' not found in registry" >&2
  echo "Run: command-runner.sh --list to see available commands" >&2
  exit 1
fi

# Resolve command path
cmd_path="$COMMANDS_DIR/${cmd_name}.md"

if [[ ! -f "$cmd_path" ]]; then
  echo "ERROR: Command file missing: $cmd_path" >&2
  echo "Command '$cmd_name' is registered but its definition file does not exist." >&2
  exit 1
fi

# Output the resolved path
echo "$cmd_path"
exit 0

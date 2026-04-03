#!/usr/bin/env bash
# @version: 1.0.0
# PostToolUse formatter — detects file type and dispatches to language-specific formatter.
# Reads CORTEX_ROOT from ~/.claude/cortex.env set by /init.

source ~/.claude/cortex.env 2>/dev/null || { echo "[cortex] cortex.env not found — run /init"; exit 0; }

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
[[ -z "$file" ]] && exit 0

SCANNERS="$CORTEX_ROOT/.claude/.cortex/core/scanners"

case "$file" in
  *.cs)
    bash "$SCANNERS/dotnet/format.sh" "$file"
    ;;
  *.ts|*.tsx|*.html|*.scss)
    bash "$SCANNERS/node/format.sh" "$file"
    ;;
esac

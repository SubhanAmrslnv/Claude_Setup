#!/usr/bin/env bash
# @version: 1.0.0
# PostToolUse scanner — detects file type and dispatches to all relevant scanners.
# Always runs generic secret scan; adds language-specific security scans on match.
# Reads CORTEX_ROOT from ~/.claude/cortex.env set by /init.

source ~/.claude/cortex.env 2>/dev/null || { echo "[cortex] cortex.env not found — run /init"; exit 0; }

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
[[ -z "$file" || ! -f "$file" ]] && exit 0

SCANNERS="$CORTEX_ROOT/.claude/.cortex/core/scanners"

# Always run generic secret scan
bash "$SCANNERS/generic/secret-scan.sh" "$file"

# Language-specific security scans
case "$file" in
  *.cs)
    bash "$SCANNERS/dotnet/security-scan.sh" "$file"
    ;;
  *.ts|*.tsx|*.js|*.jsx)
    bash "$SCANNERS/node/react-security-scan.sh" "$file"
    ;;
esac

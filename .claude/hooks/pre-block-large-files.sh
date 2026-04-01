#!/usr/bin/env bash
# Blocks git add/commit when staged files exceed 1MB.

if echo "$TOOL_INPUT" | grep -qE 'git (add|commit)'; then
  large=$(git diff --cached --name-only | xargs -I{} du -b {} 2>/dev/null | awk '$1 > 1048576 {print $2}')
  if [[ -n "$large" ]]; then
    echo "BLOCKED: large file(s) staged (>1MB): $large"
    exit 1
  fi
fi
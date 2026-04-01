#!/usr/bin/env bash
# Blocks destructive git operations — must be run manually if intentional.

if echo "$TOOL_INPUT" | grep -qE 'git (reset --hard|clean -f)'; then
  echo "BLOCKED: destructive git operation — run manually if intentional"
  exit 1
fi
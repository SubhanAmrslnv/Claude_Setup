#!/usr/bin/env bash
# Blocks force-pushes to main or master branches.

if echo "$TOOL_INPUT" | grep -qE 'push.*(--force|-f).*(main|master)|push.*(main|master).*(--force|-f)'; then
  echo "BLOCKED: force-push to protected branch"
  exit 1
fi
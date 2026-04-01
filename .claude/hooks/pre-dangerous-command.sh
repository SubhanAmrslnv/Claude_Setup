#!/usr/bin/env bash
# Blocks dangerous shell commands before execution.

if echo "$TOOL_INPUT" | grep -qiE 'drop table|rm -rf|--force|truncate'; then
  echo "BLOCKED: dangerous command detected"
  exit 1
fi
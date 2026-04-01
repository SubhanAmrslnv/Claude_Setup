#!/usr/bin/env bash
# Blocks staging of secrets, credentials, and certificate files.

if echo "$TOOL_INPUT" | grep -qE 'git add.*(\.env|secrets|credentials|\.pem|\.key|\.pfx)'; then
  echo "BLOCKED: staging a secrets or credential file"
  exit 1
fi
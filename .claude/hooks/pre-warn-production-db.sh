#!/usr/bin/env bash
# Blocks commands that appear to target a production database.

if echo "$TOOL_INPUT" | grep -qiE '(prod|production)[_-]?(db|sql|server|conn)'; then
  echo "WARNING: possible production DB target — confirm before proceeding"
  exit 1
fi
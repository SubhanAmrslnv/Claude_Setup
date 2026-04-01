#!/usr/bin/env bash
# Scans written/edited files for hardcoded secrets and credentials.

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

[[ -z "$file" || ! -f "$file" ]] && exit 0

if grep -qiE '(api_key|secret|password|token|private_key)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "WARNING: possible hardcoded secret in $file — review before committing"
fi

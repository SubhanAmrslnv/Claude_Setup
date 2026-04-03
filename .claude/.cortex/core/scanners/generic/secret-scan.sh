#!/usr/bin/env bash
# @version: 1.0.0
# Scans any file for hardcoded secrets and credentials.
# Usage: secret-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0

if grep -qiE '(api_key|secret|password|token|private_key)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "WARNING: possible hardcoded secret in $file — review before committing"
fi

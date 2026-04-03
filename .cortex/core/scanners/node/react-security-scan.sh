#!/usr/bin/env bash
# @version: 1.0.0
# Scans React/JS/TS files for XSS-prone and unsafe patterns:
# dangerouslySetInnerHTML, eval(), document.write, direct innerHTML assignment.
# Usage: react-security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.tsx && $file != *.ts && $file != *.jsx && $file != *.js ]] && exit 0

if grep -qiE '(dangerouslySetInnerHTML|eval\(|document\.write\(|innerHTML\s*=)' "$file"; then
  echo "WARNING: XSS-prone pattern detected in $file — verify intent"
fi

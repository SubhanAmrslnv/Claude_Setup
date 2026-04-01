#!/usr/bin/env bash
# Scans React/React Native/JS/TS files for XSS-prone and unsafe patterns:
# dangerouslySetInnerHTML, eval(), document.write, direct innerHTML assignment.

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.tsx && $file != *.ts && $file != *.jsx && $file != *.js ]] && exit 0

if grep -qiE '(dangerouslySetInnerHTML|eval\(|document\.write\(|innerHTML\s*=)' "$file"; then
  echo "WARNING: XSS-prone pattern detected in $file — verify intent"
fi

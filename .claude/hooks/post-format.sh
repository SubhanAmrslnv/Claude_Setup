#!/usr/bin/env bash
# Auto-formats files after Claude writes or edits them.
# - .cs  → dotnet format
# - .ts / .html / .scss → Prettier
# - .ts  → ESLint (runs after Prettier)

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

[[ -z "$file" ]] && exit 0

if [[ $file == *.cs ]]; then
  dotnet format --include "$file" 2>/dev/null
elif [[ $file == *.ts ]]; then
  npx prettier --write "$file" 2>/dev/null
  npx eslint --fix "$file" 2>/dev/null
elif [[ $file == *.html || $file == *.scss ]]; then
  npx prettier --write "$file" 2>/dev/null
fi
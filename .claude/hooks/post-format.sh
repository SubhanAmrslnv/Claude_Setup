#!/usr/bin/env bash
# Auto-formats .cs files after Claude writes or edits them.

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')

[[ -z "$file" ]] && exit 0

if [[ $file == *.cs ]]; then
  dotnet format --include "$file" 2>/dev/null
fi

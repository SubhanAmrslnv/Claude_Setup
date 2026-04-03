#!/usr/bin/env bash
# @version: 1.0.0
# Formats .ts/.html/.scss files using Prettier; lints .ts via ESLint.
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0

case "$file" in
  *.ts|*.html|*.scss) npx prettier --write "$file" 2>/dev/null ;;
esac

if [[ "$file" == *.ts ]]; then
  npx eslint --fix "$file" 2>/dev/null
fi

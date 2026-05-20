#!/usr/bin/env bash
# @version: 1.0.1
# Formats .sql files using sql-formatter (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.sql && $file != *.psql && $file != *.pgsql ]] && exit 0

if command -v sql-formatter &>/dev/null; then
  # sql-formatter may truncate the input file if --output points to the same path.
  # Stage the formatted result in a sibling temp file, then atomically replace.
  tmp="$file.cortex-fmt.$$"
  if sql-formatter --output "$tmp" "$file" 2>/dev/null && [[ -s "$tmp" ]]; then
    mv -f "$tmp" "$file"
  else
    rm -f "$tmp"
  fi
fi

exit 0

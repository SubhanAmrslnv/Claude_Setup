#!/usr/bin/env bash
# @version: 1.0.0
# Formats .cs files using dotnet format.
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.cs ]] && exit 0

dotnet format --include "$file" 2>/dev/null

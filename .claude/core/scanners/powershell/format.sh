#!/usr/bin/env bash
# @version: 1.0.1
# Formats .ps1 files using Invoke-Formatter via pwsh (if available).
# Usage: format.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.ps1 && $file != *.psm1 && $file != *.psd1 ]] && exit 0

# Pass the path through $args[0] so paths containing single quotes can't break
# out of the inline script. -File would be safer but Invoke-Formatter needs the
# raw content on stdin, so we keep -Command and use the args channel.
command -v pwsh &>/dev/null && \
  pwsh -NoProfile -Command \
    "Invoke-Formatter -ScriptDefinition (Get-Content -Raw -LiteralPath \$args[0]) | Set-Content -LiteralPath \$args[0]" \
    "$file" 2>/dev/null

exit 0

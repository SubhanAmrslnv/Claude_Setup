#!/usr/bin/env bash
# @version: 2.0.0
# PostToolUse scanner — pure dispatcher. All extension→scanner mappings live in
# .cortex/registry/scanners.json. No language-specific logic in this file.
# Reads CORTEX_ROOT from ~/.claude/cortex.env set by /init.

source ~/.claude/cortex.env 2>/dev/null || { echo "[cortex] cortex.env not found — run /init"; exit 0; }

file=$(echo "$TOOL_INPUT" | jq -r '.file_path // empty')
[[ -z "$file" || ! -f "$file" ]] && exit 0

ext=".${file##*.}"
REGISTRY="$CORTEX_ROOT/.cortex/registry/scanners.json"
SCANNERS_DIR="$CORTEX_ROOT/.cortex/core/scanners"

run_security_scanners() {
  local lookup_ext="$1"
  local scanner
  while IFS= read -r scanner; do
    [[ "$scanner" != */format.sh ]] && bash "$SCANNERS_DIR/$scanner" "$file"
  done < <(jq -r --arg e "$lookup_ext" '(.[$e] // []) | .[]' "$REGISTRY" 2>/dev/null)
}

# Always run generic scanners (wildcard entry)
run_security_scanners "*"
# Run extension-specific security scanners
run_security_scanners "$ext"

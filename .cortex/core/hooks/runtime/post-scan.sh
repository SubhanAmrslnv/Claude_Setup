#!/usr/bin/env bash
# @version: 2.3.0
# PostToolUse scanner — pure dispatcher. All extension→scanner mappings live in
# .cortex/registry/scanners.json. No language-specific logic in this file.
# Resolves CORTEX_ROOT: env var > project-local .cortex > global ~/.cortex.
# Payload delivered via stdin by Claude Code.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

ext=".${file##*.}"
REGISTRY="$CORTEX_ROOT/registry/scanners.json"
SCANNERS_DIR="$CORTEX_ROOT/core/scanners"

run_security_scanners() {
  local lookup_ext="$1"
  local scanner
  while IFS= read -r scanner; do
    [[ "$scanner" != */format.sh ]] && bash "$SCANNERS_DIR/$scanner" "$file"
  done < <(jq -r --arg e "$lookup_ext" '(.[$e] // []) | .[]' "$REGISTRY" 2>/dev/null | tr -d '\r')
}

# Always run generic scanners (wildcard entry)
run_security_scanners "*"
# Run extension-specific security scanners
run_security_scanners "$ext"

exit 0

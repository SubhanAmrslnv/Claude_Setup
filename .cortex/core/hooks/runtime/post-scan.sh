#!/usr/bin/env bash
# @version: 2.5.0
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

# File size guard — skip large files (generated assets, logs, etc.)
max_size=500000
filesize=$(wc -c <"$file" 2>/dev/null || echo 0)
(( filesize > max_size )) && exit 0

# Binary file guard — grep -Iq is more reliable than `file` command
if ! grep -Iq . "$file" 2>/dev/null; then
  exit 0
fi

# Extension detection — handle compound extensions (.tar.gz, .env.local)
filename=$(basename "$file")
case "$filename" in
  *.tar.gz|*.tar.bz2|*.tar.xz) ext=".${filename#*.}" ;;
  *.env.*) ext=".env" ;;
  *) ext=".${filename##*.}" ;;
esac

REGISTRY="$CORTEX_ROOT/registry/scanners.json"
SCANNERS_DIR="$CORTEX_ROOT/core/scanners"

# Registry validation
[[ ! -f "$REGISTRY" ]] && exit 0
jq empty "$REGISTRY" 2>/dev/null || { echo "[scan] Invalid scanners.json" >&2; exit 0; }

# Merge wildcard + extension-specific entries in one jq call, deduplicate, exclude format.sh
mapfile -t scanners < <(
  jq -r --arg e "$ext" '
    ((.["*"] // []) + (.[$e] // [])) | unique | .[]
  ' "$REGISTRY" 2>/dev/null \
  | tr -d '\r' \
  | grep -v '/format\.sh$'
)

[[ ${#scanners[@]} -eq 0 ]] && exit 0

# Hash-based scan cache — skip files already scanned without changes
cache_dir="$CORTEX_ROOT/cache/scans"
mkdir -p "$cache_dir"
file_hash=$(sha1sum "$file" 2>/dev/null | cut -d' ' -f1 || cksum "$file" 2>/dev/null | cut -d' ' -f1)
if [[ -n "$file_hash" && -f "$cache_dir/$file_hash" ]]; then
  [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Cache hit: $file" >&2
  exit 0
fi

# Concurrency limit — prevents CPU/IO exhaustion as registry grows
MAX_JOBS=${CORTEX_MAX_JOBS:-4}
running=0

for scanner in "${scanners[@]}"; do
  # Path traversal safety — reject paths that escape the scanners directory
  case "$scanner" in
    /*|*..*) echo "[scan] Invalid scanner path: $scanner" >&2; continue ;;
  esac

  if [[ ! -f "$SCANNERS_DIR/$scanner" ]]; then
    [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Missing scanner: $scanner" >&2
    continue
  fi

  [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Running: $scanner on $file" >&2

  # Isolate output via temp file — prevents stdout/stderr interleaving across parallel jobs
  tmp=$(mktemp)
  start_ts=$(date +%s%3N 2>/dev/null || echo 0)

  (
    timeout 10 bash "$SCANNERS_DIR/$scanner" "$file" >"$tmp" 2>&1
    rc=$?
    end_ts=$(date +%s%3N 2>/dev/null || echo 0)

    if [[ $rc -eq 124 ]]; then
      echo "[scan] Timeout (10s): $scanner" >&2
    elif [[ $rc -ne 0 ]]; then
      echo "[scan] Scanner failed (exit $rc): $scanner" >&2
    fi

    [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] $scanner took $(( end_ts - start_ts ))ms" >&2

    cat "$tmp"
    rm -f "$tmp"
  ) &

  (( running++ ))
  if (( running >= MAX_JOBS )); then
    wait -n 2>/dev/null || wait
    (( running-- ))
  fi
done

wait

# Mark file as scanned — future runs skip if content unchanged
[[ -n "$file_hash" ]] && touch "$cache_dir/$file_hash"

exit 0

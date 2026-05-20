#!/usr/bin/env bash
# @version: 2.7.1
# PostToolUse security scanner — sensitive-file-only, registry-driven.
# Skips regular source files; only scans config/secrets/credentials files.
# Hash-cached (skip unchanged). Concurrency-limited. Path-traversal-safe.

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

# Path-traversal safety: file must resolve within cwd
cwd=$(realpath "$(pwd)" 2>/dev/null || readlink -f "$(pwd)" 2>/dev/null || pwd)
realfile=$(realpath "$file" 2>/dev/null || readlink -f "$file" 2>/dev/null || echo "$file")
[[ "$realfile" != "$cwd" && "$realfile" != "$cwd"/* ]] && exit 0

# ── Sensitive-file-only filter ────────────────────────────────────────────────
# Only scan files that could plausibly contain secrets or config credentials.
# Regular source files (.ts .cs .py .go etc.) are skipped for max throughput.
_fname_lower=$(basename "$file" | tr '[:upper:]' '[:lower:]')
_is_sensitive=0
case "$_fname_lower" in
  *.env|*.env.*|.env|.env.*)                  _is_sensitive=1 ;;
  *.json|*.yaml|*.yml|*.toml|*.ini|*.cfg)     _is_sensitive=1 ;;
  *.config|*.conf|*.properties|*.xml)         _is_sensitive=1 ;;
  *.pem|*.key|*.pfx|*.p12|*.crt|*.cer|*.der)  _is_sensitive=1 ;;
  *.secret|*.secrets|*.credentials|*.htpasswd) _is_sensitive=1 ;;
  *secret*|*credential*|*password*|*apikey*)  _is_sensitive=1 ;;
  appsettings*|settings*|config*|secrets*)    _is_sensitive=1 ;;
esac
[[ $_is_sensitive -eq 0 ]] && exit 0

# File size guard (500KB)
max_size=500000
filesize=$(stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0)
(( filesize > max_size )) && exit 0

# Binary file guard
if command -v file &>/dev/null && file "$file" 2>/dev/null | grep -q "binary"; then
  exit 0
fi

# ── Hash cache: skip if file content unchanged (clean scan cache) ─────────
SCAN_CACHE="$CORTEX_CACHE/scans"
mkdir -p "$SCAN_CACHE" 2>/dev/null

file_hash=$(sha256sum "$file" 2>/dev/null | cut -d' ' -f1 \
         || md5sum   "$file" 2>/dev/null | cut -d' ' -f1 \
         || echo "")

if [[ -n "$file_hash" ]]; then
  cache_file="$SCAN_CACHE/${file_hash}.ok"
  [[ -f "$cache_file" ]] && exit 0
fi

# ── Extension detection ───────────────────────────────────────────────────
filename=$(basename "$file")
case "$filename" in
  *.tar.gz|*.tar.bz2|*.tar.xz) ext=".${filename#*.}" ;;
  *.env.*) ext=".env" ;;
  *) ext=".${filename##*.}" ;;
esac

REGISTRY="$CORTEX_ROOT/registry/scanners.json"
SCANNERS_DIR="$CORTEX_ROOT/core/scanners"

[[ ! -f "$REGISTRY" ]] && exit 0
jq empty "$REGISTRY" 2>/dev/null || { echo "[scan] Invalid scanners.json" >&2; exit 0; }

# Merge wildcard + extension-specific; keep only security/secret scanners
mapfile -t scanners < <(
  jq -r --arg e "$ext" '
    ((.["*"] // []) + (.[$e] // [])) | unique | .[]
  ' "$REGISTRY" 2>/dev/null \
  | tr -d '\r' \
  | grep -E '/(security-scan|secret-scan)\.sh$'
)

if [[ ${#scanners[@]} -eq 0 ]]; then
  [[ -n "$file_hash" ]] && touch "$SCAN_CACHE/${file_hash}.ok"
  exit 0
fi

# ── Concurrency-limited parallel execution ────────────────────────────────
MAX_JOBS="${CORTEX_MAX_JOBS:-4}"
tmp_dir=$(mktemp -d 2>/dev/null) || { exit 0; }
trap 'rm -rf "$tmp_dir"' EXIT

pids=()

for scanner in "${scanners[@]}"; do
  if [[ ! -f "$SCANNERS_DIR/$scanner" ]]; then
    [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Missing: $scanner" >&2
    continue
  fi

  # Concurrency throttle
  while [[ ${#pids[@]} -ge $MAX_JOBS ]]; do
    running=()
    for p in "${pids[@]}"; do
      kill -0 "$p" 2>/dev/null && running+=("$p")
    done
    pids=("${running[@]}")
    [[ ${#pids[@]} -ge $MAX_JOBS ]] && sleep 0.05
  done

  out_file="$tmp_dir/$(echo "$scanner" | tr '/' '_').out"
  [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Running: $scanner on $file" >&2

  (
    timeout 15 bash "$SCANNERS_DIR/$scanner" "$file" > "$out_file" 2>&1
    rc=$?
    [[ $rc -eq 124 ]] && echo "[scan] Timeout (15s): $scanner" >&2
    [[ $rc -ne 0 && $rc -ne 124 ]] && \
      [[ "${CORTEX_DEBUG:-0}" == "1" ]] && echo "[scan] Exit $rc: $scanner" >&2
  ) &
  pids+=($!)
done

for pid in "${pids[@]}"; do
  wait "$pid" 2>/dev/null || true
done

# ── Collect findings ──────────────────────────────────────────────────────
all_output=""
for out_file in "$tmp_dir"/*.out; do
  [[ -f "$out_file" ]] || continue
  content=$(cat "$out_file" 2>/dev/null)
  [[ -n "$content" ]] && all_output="${all_output}${content}"$'\n'
done

if [[ -n "$all_output" ]]; then
  jq -n --arg o "$all_output" --arg f "$file" \
    '{"security_output": $o, "security_warnings": [{"file": $f, "message": $o}]}'
else
  # Clean scan — cache the result
  [[ -n "$file_hash" ]] && touch "$SCAN_CACHE/${file_hash}.ok"
fi

exit 0

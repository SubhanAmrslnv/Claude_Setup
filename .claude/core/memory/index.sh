#!/usr/bin/env bash
# @version: 1.0.0
# Lazy file-index builder. Writes .claude/cache/file-index.txt atomically.
#
# Usage:
#   index.sh build            # builds (or rebuilds) the index
#   index.sh ensure           # builds only if missing/stale
#   index.sh path             # prints the index file path

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

index="$CORTEX_CACHE/file-index.txt"
project_root="$(dirname "$CORTEX_ROOT")"
max_age=$(cortex_config '.memory.indexMaxAgeSeconds' '3600')

build() {
  local tmp="$index.tmp"
  ( cd "$project_root" && \
    find . -type f \
      -not -path '*/.git/*' \
      -not -path '*/node_modules/*' \
      -not -path '*/dist/*' \
      -not -path '*/build/*' \
      -not -path '*/out/*' \
      -not -path '*/bin/*' \
      -not -path '*/obj/*' \
      -not -path '*/target/*' \
      -not -path '*/.next/*' \
      -not -path '*/.venv/*' \
      -not -path '*/__pycache__/*' \
      -not -path '*/.cortex/*' \
      -not -path '*/.claude/cache/*' \
      -not -path '*/.claude/temp/*' \
      -not -path '*/.claude/logs/*' \
      2>/dev/null \
  ) > "$tmp" 2>/dev/null
  mv "$tmp" "$index"
}

case "${1:-ensure}" in
  build) build ;;
  ensure)
    if [[ ! -s "$index" ]]; then build; else
      now=$(date +%s); mtime=$(stat -c %Y "$index" 2>/dev/null || stat -f %m "$index" 2>/dev/null || echo 0)
      (( now - mtime > max_age )) && build
    fi
    ;;
  path) echo "$index" ;;
  *) echo "usage: index.sh {build|ensure|path}" >&2; exit 2;;
esac

[[ -f "$index" ]] && echo "$index"

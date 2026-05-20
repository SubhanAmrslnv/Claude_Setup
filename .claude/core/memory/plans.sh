#!/usr/bin/env bash
# @version: 1.0.0
# Cortex plan memory — saves Claude Code plan files into project memory and
# exposes list/get/search across past sessions in this project.
#
# Usage:
#   plans.sh save <plan-file>          # capture a plan into project memory
#   plans.sh list                      # list saved plans (newest first)
#   plans.sh get <slug>                # print one saved plan
#   plans.sh search <query>            # keyword search across saved plans
#   plans.sh prune <days>              # delete plans older than N days

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

plans_dir="$CORTEX_ROOT/project/memory/plans"
index_file="$CORTEX_ROOT/project/memory/plans.json"
mkdir -p "$plans_dir"
[[ -f "$index_file" ]] || echo '{"schema":1,"plans":[]}' > "$index_file"

# Extract title from a plan markdown: first H1, fallback to slug.
_title() {
  local f="$1" t
  t=$(grep -m1 -E '^#[[:space:]]+' "$f" 2>/dev/null | sed -E 's/^#[[:space:]]+//' | tr -d '\r')
  [[ -n "$t" ]] && echo "$t" || basename "$f" .md
}

# Best-effort intent: inspect the H1 title + first 5 lines only — body text is
# too noisy ("bug" appears in plans that aren't bug fixes, etc.).
_intent() {
  local f="$1" head_lc
  head_lc=$(grep -m1 -E '^#[[:space:]]+' "$f" 2>/dev/null; head -n 5 "$f" 2>/dev/null)
  head_lc=$(echo "$head_lc" | tr '[:upper:]' '[:lower:]')
  case "$head_lc" in
    *redesign*|*refactor*|*rewrite*) echo "refactor" ;;
    *"bug fix"*|*"fix:"*|*hotfix*|*regression*) echo "bug_fix" ;;
    *migration*|*upgrade*|*"port to"*) echo "migration" ;;
    *"add "*|*implement*|*"new feature"*|*feature*) echo "feature" ;;
    *dashboard*|*status*|*ui*) echo "feature" ;;
    *) echo "general" ;;
  esac
}

cmd_save() {
  local src="$1"
  [[ -f "$src" ]] || { echo "plans: not a file: $src" >&2; exit 1; }
  local slug
  slug=$(basename "$src" .md)
  # Sanitize slug — alphanumerics + dashes/underscores only.
  slug=$(echo "$slug" | tr -c '[:alnum:]_-' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
  [[ -z "$slug" ]] && slug="plan-$(date +%s)"

  local dst="$plans_dir/$slug.md"
  local saved_at
  saved_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local title intent size
  title=$(_title "$src")
  intent=$(_intent "$src")
  size=$(wc -c < "$src" 2>/dev/null | tr -d ' ')

  # Write the saved plan with frontmatter. Only strip existing frontmatter when
  # the SOURCE actually starts with `---` (otherwise stray `---` inside the body
  # would eat content).
  {
    printf -- "---\nslug: %s\nsaved_at: %s\nsource: %s\ntitle: %s\nintent: %s\n---\n\n" \
      "$slug" "$saved_at" "$src" "$title" "$intent"
    if head -n 1 "$src" 2>/dev/null | grep -qE '^---[[:space:]]*$'; then
      awk 'BEGIN{seen=0} /^---[[:space:]]*$/{seen++; if(seen<=2) next} seen>=2{print}' "$src"
    else
      cat "$src"
    fi
  } > "$dst"

  # Upsert into index — newest first.
  jq --arg slug "$slug" --arg title "$title" --arg saved_at "$saved_at" \
     --arg intent "$intent" --arg src "$src" --argjson size "${size:-0}" '
    .plans = (
      (.plans // []) | map(select(.slug != $slug))
      | [{slug:$slug, title:$title, saved_at:$saved_at, source:$src, intent:$intent, size_bytes:$size}] + .
    )
  ' "$index_file" > "$index_file.tmp" && mv "$index_file.tmp" "$index_file"

  echo "$dst"
}

cmd_list() {
  jq -r '
    (.plans // [])
    | .[]
    | "\(.saved_at)  [\(.intent)]  \(.slug)  —  \(.title)"
  ' "$index_file" 2>/dev/null
}

cmd_get() {
  local slug="$1"
  [[ -z "$slug" ]] && { echo "plans: get <slug>" >&2; exit 2; }
  local f="$plans_dir/$slug.md"
  [[ -f "$f" ]] || { echo "plans: not found: $slug" >&2; exit 1; }
  cat "$f"
}

cmd_search() {
  local query="$*"
  [[ -z "$query" ]] && { echo "plans: search <query>" >&2; exit 2; }
  shopt -s nullglob
  for f in "$plans_dir"/*.md; do
    local hits
    hits=$(grep -c -iE "$query" "$f" 2>/dev/null)
    [[ -z "$hits" || "$hits" -eq 0 ]] && continue
    local slug title
    slug=$(basename "$f" .md)
    title=$(awk -F': ' '/^title:/{print $2; exit}' "$f" | tr -d '\r')
    printf "%3d  %s  —  %s\n" "$hits" "$slug" "$title"
  done | sort -rn -k1,1
}

cmd_prune() {
  local days="${1:-30}"
  [[ "$days" =~ ^[0-9]+$ ]] || { echo "plans: prune <days>" >&2; exit 2; }
  find "$plans_dir" -maxdepth 1 -name '*.md' -mtime "+$days" -print -delete 2>/dev/null
  # Rebuild index from disk.
  local tmp; tmp=$(mktemp)
  echo '{"schema":1,"plans":[]}' > "$tmp"
  shopt -s nullglob
  for f in "$plans_dir"/*.md; do
    local slug title intent saved_at size
    slug=$(basename "$f" .md)
    title=$(awk -F': ' '/^title:/{print $2; exit}' "$f" | tr -d '\r')
    intent=$(awk -F': ' '/^intent:/{print $2; exit}' "$f" | tr -d '\r')
    saved_at=$(awk -F': ' '/^saved_at:/{print $2; exit}' "$f" | tr -d '\r')
    size=$(wc -c < "$f")
    jq --arg slug "$slug" --arg title "$title" --arg saved_at "$saved_at" \
       --arg intent "$intent" --argjson size "${size:-0}" '
      .plans += [{slug:$slug, title:$title, saved_at:$saved_at, intent:$intent, size_bytes:$size}]
    ' "$tmp" > "$tmp.2" && mv "$tmp.2" "$tmp"
  done
  jq '.plans |= sort_by(.saved_at) | .plans |= reverse' "$tmp" > "$index_file"
  rm -f "$tmp"
}

case "${1:-}" in
  save)   shift; cmd_save   "${1:-}" ;;
  list)   cmd_list ;;
  get)    shift; cmd_get    "${1:-}" ;;
  search) shift; cmd_search "$@" ;;
  prune)  shift; cmd_prune  "${1:-30}" ;;
  *) echo "usage: plans.sh {save <file>|list|get <slug>|search <query>|prune <days>}" >&2; exit 2 ;;
esac

#!/usr/bin/env bash
# Shared installer core — used by scripts/install.sh and bin/cortex (init).
#
# Strategy: shallow + sparse `git clone` of the Cortex repo, then copy `.claude/`
# into the target project. Overlay semantics — user-local state preserved.
#
# Env:
#   CORTEX_TARGET     destination project root (defaults to $PWD)
#   CORTEX_REPO_URL   full clone URL (default https://github.com/SubhanAmrslnv/Cortex.git)
#   CORTEX_REPO_ORG   org slug (used only if CORTEX_REPO_URL unset; default SubhanAmrslnv)
#   CORTEX_REPO_NAME  repo slug (used only if CORTEX_REPO_URL unset; default Cortex)
#   CORTEX_REF        branch/tag/sha to clone (default main)

set -eu

target="${CORTEX_TARGET:-$PWD}"
ref="${CORTEX_REF:-main}"
repo_url="${CORTEX_REPO_URL:-https://github.com/${CORTEX_REPO_ORG:-SubhanAmrslnv}/${CORTEX_REPO_NAME:-Cortex}.git}"

say()  { printf "[cortex] %s\n" "$*"; }
fail() { printf "[cortex] error: %s\n" "$*" >&2; exit 1; }

command -v git >/dev/null 2>&1 || fail "git is required (install Git for Windows, Xcode CLT, or your distro's git package)."

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

say "cloning $repo_url@$ref (sparse: .claude/)"
git clone --depth 1 --filter=blob:none --sparse --branch "$ref" "$repo_url" "$tmp" >/dev/null 2>&1 \
  || fail "git clone failed (repo=$repo_url ref=$ref)."
git -C "$tmp" sparse-checkout set .claude >/dev/null 2>&1 \
  || fail "sparse-checkout set .claude failed."

[ -d "$tmp/.claude" ] || fail "$repo_url@$ref does not contain a .claude/ directory."

mkdir -p "$target/.claude"

# Overlay copy. Preserve user-local subtrees if they already exist in the target.
preserve=(project/memory cache logs temp state)
is_preserved() {
  local rel="$1"
  for p in "${preserve[@]}"; do
    [ "$rel" = "$p" ] && return 0
  done
  return 1
}

shopt -s dotglob nullglob

copy_tree() {
  local src="$1" dst="$2" rel="$3"
  if is_preserved "$rel" && [ -e "$dst" ]; then
    return 0
  fi
  if [ -d "$src" ]; then
    mkdir -p "$dst"
    for entry in "$src"/*; do
      local name; name="$(basename "$entry")"
      copy_tree "$entry" "$dst/$name" "${rel:+$rel/}$name"
    done
  else
    cp -f "$src" "$dst"
  fi
}

for entry in "$tmp/.claude"/*; do
  name="$(basename "$entry")"
  copy_tree "$entry" "$target/.claude/$name" "$name"
done

shopt -u dotglob nullglob

# Local-only state dirs (ensure they exist even on fresh installs).
mkdir -p "$target/.claude"/{cache,logs,temp/events,state,project/memory/plans}

# Make hooks/scanners executable on POSIX systems.
find "$target/.claude/core" -type f -name '*.sh' -exec chmod +x {} + 2>/dev/null || true

say "Cortex installed at $target/.claude (ref=$ref)"
say "Next: open Claude Code in this project."

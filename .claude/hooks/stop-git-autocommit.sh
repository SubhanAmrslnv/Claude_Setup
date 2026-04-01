#!/usr/bin/env bash
# Automatically commits Claude's changes after each session.
# - Stages modified tracked files only (respects .gitignore, skips untracked)
# - Generates a conventional commit message from diff stats
# - Skips if on main/master (force branch workflow)

set -uo pipefail

git rev-parse --git-dir > /dev/null 2>&1 || exit 0

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "[autocommit] Skipped: on protected branch '$branch'"
  exit 0
fi

git add -u

git diff --cached --quiet && exit 0

# Cache once — reused for stat, body, file list
cached_files=$(git diff --cached --name-only)
diff_stat=$(git diff --cached --stat)
changed_files=$(echo "$cached_files" | sed 's/^/  - /')

first_file=$(echo "$cached_files" | head -1)
file_count=$(echo "$cached_files" | wc -l | tr -d ' ')

# Derive conventional commit type from changed file extensions
ext="${first_file##*.}"
case "$ext" in
  md|txt)        type="docs" ;;
  sh)            type="chore" ;;
  cs)            type="feat" ;;
  ts|tsx|js|jsx) type="feat" ;;
  json|yaml|yml) type="chore" ;;
  scss|css|html) type="style" ;;
  *)             type="chore" ;;
esac

subject="$type: update $first_file"
[[ "$file_count" -gt 1 ]] && subject="$type: update $first_file and $((file_count - 1)) other file(s)"

commit_msg="$subject

Files changed:
$changed_files

$diff_stat"

git commit -m "$commit_msg"
echo "[autocommit] Committed on '$branch': $(echo "$commit_msg" | head -1)"

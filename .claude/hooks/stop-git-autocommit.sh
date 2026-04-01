#!/usr/bin/env bash
# Automatically commits Claude's changes after each session.
# - Stages modified tracked files only (respects .gitignore, skips untracked)
# - Calls Claude API (Haiku) to generate a conventional commit message from the diff
# - Falls back to a stats-based message if the API key is missing or the call fails
# - Skips if on main/master (force branch workflow)

set -euo pipefail

# Must be inside a git repo
git rev-parse --git-dir > /dev/null 2>&1 || exit 0

# Skip on protected branches
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
if [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "[autocommit] Skipped: on protected branch '$branch'"
  exit 0
fi

# Stage modified tracked files only
git add -u

# Nothing staged — nothing to commit
git diff --cached --quiet && exit 0

# Gather diff info for the prompt
diff_stat=$(git diff --cached --stat)
diff_body=$(git diff --cached | head -200)
changed_files=$(git diff --cached --name-only | sed 's/^/  - /')

# --- AI-generated message via Claude API ---
commit_msg=""

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  prompt=$(jq -rn \
    --arg stat "$diff_stat" \
    --arg diff "$diff_body" \
    --arg files "$changed_files" \
    '"Generate a git commit message for these changes.\n\nRules:\n- First line: conventional commit format — type(scope): subject (max 72 chars)\n- Valid types: feat, fix, chore, refactor, docs, test, ci, build, perf, style\n- Blank line after subject\n- Then 2–5 bullet points describing what specifically changed\n- Be concrete — use file names and actual change details\n- Return only the commit message, no extra text\n\nDiff stat:\n\($stat)\n\nChanged files:\n\($files)\n\nDiff (first 200 lines):\n\($diff)"'
  )

  response=$(curl -s https://api.anthropic.com/v1/messages \
    -H "x-api-key: $ANTHROPIC_API_KEY" \
    -H "anthropic-version: 2023-06-01" \
    -H "content-type: application/json" \
    -d "$(jq -n \
      --arg model "claude-haiku-4-5-20251001" \
      --arg content "$prompt" \
      '{model: $model, max_tokens: 300, messages: [{role: "user", content: $content}]}'
    )" 2>/dev/null)

  commit_msg=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null || true)
fi

# --- Fallback: stats-based message ---
if [[ -z "$commit_msg" ]]; then
  first_file=$(git diff --cached --name-only | head -1)
  file_count=$(git diff --cached --name-only | wc -l | tr -d ' ')
  subject="chore: update $first_file"
  [[ "$file_count" -gt 1 ]] && subject="chore: update $first_file and $((file_count - 1)) other file(s)"

  commit_msg="$subject

Files changed:
$changed_files

$diff_stat"
fi

# Commit
git commit -m "$commit_msg"
echo "[autocommit] Committed on '$branch': $(echo "$commit_msg" | head -1)"
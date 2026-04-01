#!/usr/bin/env bash
# Blocks direct commits to main or master — enforces feature branch workflow.

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

if echo "$TOOL_INPUT" | grep -qE 'git commit' && [[ "$branch" == "main" || "$branch" == "master" ]]; then
  echo "BLOCKED: direct commit to $branch — use a feature branch"
  exit 1
fi
#!/usr/bin/env bash
# Enforces conventional commit format: type(scope): subject

if echo "$TOOL_INPUT" | grep -qE 'git commit.*-m'; then
  msg=$(echo "$TOOL_INPUT" | grep -oP '(?<=-m [\x27"])[^\x27"]+')
  if ! echo "$msg" | grep -qE '^(feat|fix|chore|docs|refactor|test|ci|build|perf|style)(\(.+\))?: .+'; then
    echo "BLOCKED: commit message must follow conventional commits — e.g. feat(auth): add JWT refresh"
    exit 1
  fi
fi
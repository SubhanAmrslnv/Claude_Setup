#!/usr/bin/env bash
# @version: 1.0.0
# FileChanged subscriber — mirrors Claude Code plan files into project memory.
#
# Triggered by the event bus on every Write/Edit. Inspects the tool payload's
# file_path. If the file is a Claude Code plan markdown (under any *.claude/plans*
# directory), it's saved via plans.sh into .claude/project/memory/plans/.
# Same-project writes only: skips files outside the current project unless they
# come from ~/.claude/plans (Claude Code's user-global plan store).

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

payload=$(cat)
file=$(echo "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null | tr -d '\r')
[[ -z "$file" || ! -f "$file" ]] && exit 0

# Plan file recognition:
#  - ends with .md
#  - lives under a "plans" directory (Claude Code's plan mode writes to
#    ~/.claude/plans/<slug>.md by default)
case "$file" in
  *"/plans/"*.md|*"\\plans\\"*.md|*".claude/plans/"*.md|*".claude\\plans\\"*.md) ;;
  *) exit 0 ;;
esac

bash "$CORTEX_ROOT/core/memory/plans.sh" save "$file" >/dev/null 2>&1 || true

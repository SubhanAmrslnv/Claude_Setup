#!/usr/bin/env bash
# @version: 1.0.0
# UserPromptSubmit — minimal intent router. Replaces prompt-optimizer.sh.
#
# Reads the raw prompt from stdin, detects an intent label via a tiny keyword
# table, exports CORTEX_INTENT into the hook's structured response, and passes
# the prompt through unchanged.
#
# Honours the legacy `--y` suffix: strips it and appends a YES-default policy.
# Target latency: <30ms. No file IO beyond optional config read.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

stdin=$(cat)
prompt=$(jq -r '.prompt // .text // ""' <<<"$stdin" 2>/dev/null)
[[ -z "$prompt" ]] && exit 0

yes_policy=0
if [[ "$prompt" == *"--y"* ]]; then
  prompt="${prompt//--y/}"
  prompt="${prompt%[[:space:]]}"
  yes_policy=1
fi

plc=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
intent="question"
case "$plc" in
  *"/debug"*|*"debug"*|*"trace"*|*"crash"*|*"stack trace"*)        intent="debug" ;;
  *"/commit"*|*"commit message"*|*"conventional commit"*)          intent="commit" ;;
  *"fix"*|*"bug"*|*"error"*|*"broken"*|*"fail"*|*"throw"*)         intent="bug_fix" ;;
  *"refactor"*|*"rename"*|*"extract"*|*"simplify"*|*"cleanup"*)    intent="refactor" ;;
  *"add"*|*"implement"*|*"create"*|*"build"*|*"new feature"*|*"feature"*) intent="feature" ;;
  *"migrate"*|*"migration"*|*"upgrade"*|*"port to"*)               intent="migration" ;;
esac

extra=""
if (( yes_policy )); then
  extra=$'\n\nGLOBAL ANSWER POLICY: Default all binary decisions to YES, except destructive or security-sensitive ones.'
fi

jq -nc --arg p "$prompt$extra" --arg i "$intent" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:""}, env:{CORTEX_INTENT:$i}, prompt:$p}'

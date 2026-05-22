#!/usr/bin/env bash
# @version: 1.1.1
# UserPromptSubmit — intent router. Replaces prompt-optimizer.sh.
#
# Reads the raw prompt from stdin, classifies it into one of 32 intent labels
# (see cortex.config.json → modelPolicy.intents), exports CORTEX_INTENT into the
# hook's structured response, and passes the prompt through unchanged.
#
# Honours the legacy `--y` suffix: strips it and appends a YES-default policy.
# Target latency: <30ms. No file IO beyond an optional jq config read upstream.

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

# Priority-ordered classification — first match wins. Opus-tier intents are
# tested before Sonnet-tier so ambiguous prompts escalate, not the reverse.
# Haiku-tier intents require explicit "trivial / simple / pure / typo / rename"
# keywords; otherwise we fall back to the Sonnet default.
intent="question"
case "$plc" in
  # ── opus tier ──────────────────────────────────────────────────────────────
  *"security review"*|*"auth flow"*|*" crypto"*|*"owasp"*|*"input validation"*|*"penetration test"*)
    intent="security_review" ;;
  *"incident"*|*"outage"*|*"production rca"*|*"root cause analysis"*|*"postmortem"*|*"post-mortem"*)
    intent="incident_rca" ;;
  *"performance audit"*|*"profile "*|*"profiling"*|*"bottleneck"*|*"system-wide tuning"*|*"flame graph"*)
    intent="performance_audit" ;;
  *"architecture"*|*"system design"*|*"service boundaries"*|*"pattern selection"*|*"design doc"*)
    intent="architecture" ;;
  *"schema migration"*|*"migrate the database"*|*"data migration"*|*"rollback strategy"*|*"backfill"*)
    intent="migration_schema" ;;
  *"framework upgrade"*|*"runtime upgrade"*|*".net 6 to .net 8"*|*"angular 15 to 18"*|*"major upgrade"*)
    intent="migration_framework" ;;
  *"legacy modernization"*|*"strangler fig"*|*"gradual rewrite"*|*"acl design"*|*"anti-corruption layer"*)
    intent="legacy_modernization" ;;
  *"multi-repo"*|*"multi repo"*|*"across repositories"*|*"cross-repo"*)
    intent="multi_repo_change" ;;
  *"deep review"*|*"architectural review"*|*"review large pr"*|*"review the new module"*)
    intent="code_review_deep" ;;
  *"cross-cutting feature"*|*"feature touching multiple services"*|*"large feature"*|*"cross-service feature"*)
    intent="feature_large" ;;

  # ── sonnet tier ────────────────────────────────────────────────────────────
  *"code review"*|*"review this pr"*|*"pr review"*|*"review the pr"*)
    intent="code_review_light" ;;
  *"integration test"*)
    intent="integration_test" ;;
  *"api design"*|*"endpoint design"*|*"rest design"*|*"graphql design"*|*"design a new api"*|*"design a new rest"*)
    intent="api_design" ;;
  *"sql tuning"*|*"query optimization"*|*"index strategy"*|*"explain plan"*|*"optimize this query"*)
    intent="query_optimization" ;;
  *"dependency upgrade"*|*"bump dependency"*|*"bump package"*|*"patch bump"*|*"minor bump"*|*"update dependency"*)
    intent="dependency_upgrade" ;;
  *"write documentation"*|*"write docs"*|*"draft a readme"*|*"draft readme"*|*"update the readme"*|*"create readme"*|*"add adr"*|*"new adr"*|*"technical writeup"*|*"draft an adr"*)
    intent="documentation" ;;
  *"config migration"*|*"package rename migration"*|*"rename package"*)
    intent="migration_trivial" ;;
  *"complex test"*|*"async test"*|*"mock "*|*"mocking"*|*"edge case test"*)
    intent="unit_test_complex" ;;
  *"/debug"*|*"debug "*|*"trace "*|*"stack trace"*|*"crash"*|*"stacktrace"*)
    intent="debug" ;;
  *"refactor"*|*"restructure"*|*"extract function"*|*"extract method"*|*"simplify"*|*"cleanup"*)
    intent="refactor" ;;

  # ── haiku tier (require explicit "small" / "trivial" / "simple" markers) ──
  *"trivial bug"*|*"off-by-one"*|*"null check"*|*"tiny fix"*|*"one-liner fix"*|*"trivial fix"*)
    intent="bug_fix_trivial" ;;
  *"rename "*|*"rename the "*|*"rename across files"*)
    intent="rename" ;;
  *"typo"*|*"fix typo"*)
    intent="typo_fix" ;;
  *"boilerplate"*|*"dto"*|*"scaffold"*|*"crud scaffold"*)
    intent="boilerplate" ;;
  *"docstring"*|*"doc comment"*|*"jsdoc"*|*"xml doc"*)
    intent="docstring" ;;
  *"format "*|*"lint "*|*"sort imports"*|*"prettier"*|*"eslint --fix"*)
    intent="format_code" ;;
  *"/commit"*|*"commit message"*|*"conventional commit"*)
    intent="commit_message" ;;
  *"simple test"*|*"unit test for pure"*|*"test pure function"*|*"trivial test"*)
    intent="unit_test_simple" ;;
  *"explain"*|*"what does this"*|*"summarize this code"*|*"read this code"*|*"walk me through"*)
    intent="explain_code" ;;

  # ── sonnet defaults for bug / feature (must come AFTER haiku-tier "trivial") ─
  *"small feature"*|*"add feature"*|*"implement"*|*"new feature"*|*" feature "*|*"feature."*|*"feature,"*)
    intent="feature_small" ;;
  *"bug"*|*"fix "*|*"error"*|*"broken"*|*"fail"*|*"throw"*|*"exception"*)
    intent="bug_fix" ;;
esac

extra=""
if (( yes_policy )); then
  extra=$'\n\nGLOBAL ANSWER POLICY: Default all binary decisions to YES, except destructive or security-sensitive ones.'
fi

printf '%s' "$prompt$extra" | jq -Rsc --arg i "$intent" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit", additionalContext:""}, env:{CORTEX_INTENT:$i}, prompt:.}'

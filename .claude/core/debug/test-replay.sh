#!/usr/bin/env bash
# @version: 1.0.0
# Re-runs the project's test suite (or a single test if $1 given).
# Reused as the TestFailed event subscriber.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

project_root="$(dirname "$CORTEX_ROOT")"
filter="${1:-}"
cmd=""
if [[ -f "$project_root/package.json" ]]; then
  cmd="npm test --silent --"
  [[ -n "$filter" ]] && cmd="$cmd -t \"$filter\""
elif compgen -G "$project_root/*.csproj" >/dev/null || compgen -G "$project_root/*.sln" >/dev/null; then
  cmd="dotnet test --nologo -v quiet"
  [[ -n "$filter" ]] && cmd="$cmd --filter \"$filter\""
elif [[ -f "$project_root/Cargo.toml" ]]; then
  cmd="cargo test --quiet"
  [[ -n "$filter" ]] && cmd="$cmd $filter"
elif [[ -f "$project_root/pyproject.toml" || -f "$project_root/pytest.ini" ]]; then
  cmd="pytest -q"
  [[ -n "$filter" ]] && cmd="$cmd -k \"$filter\""
elif [[ -f "$project_root/go.mod" ]]; then
  cmd="go test ./..."
  [[ -n "$filter" ]] && cmd="$cmd -run $filter"
fi

[[ -z "$cmd" ]] && { jq -nc '{kind:"tests", status:"SKIP", reason:"no test runner detected"}'; exit 0; }

log="$CORTEX_TEMP/tests-$(date +%s).log"
( cd "$project_root" && timeout 120 bash -c "$cmd" ) > "$log" 2>&1
rc=$?

fails=$(grep -iE '(FAIL|✗|failed)' "$log" 2>/dev/null | head -n 20 | jq -R . | jq -sc .)
[[ -z "$fails" ]] && fails="[]"

jq -nc --arg cmd "$cmd" --argjson rc "$rc" --argjson fails "$fails" \
  '{kind:"tests", command:$cmd, exit:$rc, status:(if $rc==0 then "OK" else "FAIL" end), failures:$fails}'

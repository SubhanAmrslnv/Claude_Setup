#!/usr/bin/env bash
# Cortex smoke test runner
# Usage: bash .cortex/test/run.sh [filter]
# Filter: optional substring to run only matching test names

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi

HOOKS="$CORTEX_ROOT/core/hooks"
FIXTURES="$CORTEX_ROOT/test/fixtures"
FILTER="${1:-}"

pass=0
fail=0
skip=0

run_test() {
  local name="$1"
  local hook="$2"
  local fixture="$3"
  local expect_exit="$4"     # expected exit code
  local expect_pattern="$5"  # optional: grep pattern that output must match

  if [[ -n "$FILTER" ]] && [[ "$name" != *"$FILTER"* ]]; then
    (( skip++ ))
    return
  fi

  if [[ ! -f "$HOOKS/$hook" ]]; then
    echo "SKIP  $name — hook not found: $hook"
    (( skip++ ))
    return
  fi

  if [[ ! -f "$FIXTURES/$fixture" ]]; then
    echo "SKIP  $name — fixture not found: $fixture"
    (( skip++ ))
    return
  fi

  output=$(bash "$HOOKS/$hook" < "$FIXTURES/$fixture" 2>&1)
  actual_exit=$?

  if [[ $actual_exit -ne $expect_exit ]]; then
    echo "FAIL  $name — expected exit $expect_exit, got $actual_exit"
    [[ -n "$output" ]] && echo "      output: ${output:0:200}"
    (( fail++ ))
    return
  fi

  if [[ -n "$expect_pattern" ]] && ! echo "$output" | grep -qE "$expect_pattern"; then
    echo "FAIL  $name — output did not match: $expect_pattern"
    [[ -n "$output" ]] && echo "      output: ${output:0:200}"
    (( fail++ ))
    return
  fi

  echo "PASS  $name"
  (( pass++ ))
}

# ─── pre-guard tests ─────────────────────────────────────────────────────────
run_test "pre-guard: rm -rf blocks"          "guards/pre-guard.sh"   "pre-guard/rm-rf.json"     1  "blocked"
run_test "pre-guard: rm -r -f blocks"        "guards/pre-guard.sh"   "pre-guard/rm-r-f.json"    1  "blocked"
run_test "pre-guard: git pull allows"        "guards/pre-guard.sh"   "pre-guard/git-pull.json"  0  ""
run_test "pre-guard: curl|sh blocks"         "guards/pre-guard.sh"   "pre-guard/curl-pipe.json" 1  "blocked"
run_test "pre-guard: sudo warns"             "guards/pre-guard.sh"   "pre-guard/sudo.json"      0  "warning"

# ─── post-error-analyzer tests ───────────────────────────────────────────────
run_test "error-analyzer: null ref"          "runtime/post-error-analyzer.sh"  "post-error/null-ref.json"     0  "runtime_error"
run_test "error-analyzer: module not found"  "runtime/post-error-analyzer.sh"  "post-error/module-missing.json" 0 "dependency_error"
run_test "error-analyzer: permission denied" "runtime/post-error-analyzer.sh"  "post-error/permission.json"   0  "permission_error"
run_test "error-analyzer: syntax error"      "runtime/post-error-analyzer.sh"  "post-error/syntax.json"       0  "syntax_error"
run_test "error-analyzer: build error ts"    "runtime/post-error-analyzer.sh"  "post-error/ts-build.json"     0  "build_error"
run_test "error-analyzer: network refused"   "runtime/post-error-analyzer.sh"  "post-error/econnrefused.json" 0  "network_error"
run_test "error-analyzer: timeout"           "runtime/post-error-analyzer.sh"  "post-error/timeout.json"      0  "timeout_error"

# ─── post-scan tests ─────────────────────────────────────────────────────────
# Note: these require real files on disk; skipped if test file absent
run_test "post-scan: missing file exits 0"   "runtime/post-scan.sh"  "post-scan/no-file.json"   0  ""

# ─── Summary ─────────────────────────────────────────────────────────────────
total=$(( pass + fail + skip ))
echo ""
echo "Results: $pass passed, $fail failed, $skip skipped / $total total"
[[ $fail -gt 0 ]] && exit 1 || exit 0

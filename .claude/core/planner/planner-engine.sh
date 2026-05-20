#!/usr/bin/env bash
# @version: 1.0.0
# Planner — builds a task DAG from a high-level intent and executes it.
#
# Usage:
#   planner-engine.sh build  <intent>      # prints DAG JSON
#   planner-engine.sh run    <dag.json>    # runs via worker-pool, prints merged bundle
#   planner-engine.sh plan-and-run <intent>
#
# Intents understood today:
#   debug          → 5-probe runtime-monitor DAG (process, logs, build, tests, network)
#   feature        → 2-task DAG (architecture memory retrieve, then handler placeholder)
#
# This is a deliberately small surface — callers (currently /debug) pass concrete
# intents. Unknown intents return a single-node identity DAG so worker-pool is a no-op.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

build_dag() {
  local intent="$1"
  case "$intent" in
    debug)
      cat <<'JSON'
{
  "tasks": {
    "inspect-process": { "handler": "debug/process-inspector.sh", "args": "",         "depends_on": [] },
    "tail-logs":       { "handler": "debug/log-stream.sh",        "args": "",         "depends_on": [] },
    "run-build":       { "handler": "debug/build-watcher.sh",     "args": "",         "depends_on": [] },
    "replay-tests":    { "handler": "debug/test-replay.sh",       "args": "",         "depends_on": [] },
    "curl-endpoint":   { "handler": "debug/network-trace.sh",     "args": "",         "depends_on": [] }
  }
}
JSON
      ;;
    *)
      echo '{"tasks":{}}'
      ;;
  esac
}

cmd="${1:-}"; arg="${2:-}"
case "$cmd" in
  build)
    build_dag "$arg"
    ;;
  run)
    [[ -f "$arg" ]] || { echo '{"status":"FAIL","error":"dag missing"}'; exit 0; }
    out="$CORTEX_TEMP/planner-$(date +%s%N)"
    mkdir -p "$out"
    bash "$CORTEX_ROOT/core/planner/worker-pool.sh" run "$arg" "$out" >/dev/null
    bash "$CORTEX_ROOT/core/planner/merge-engine.sh" "$out"
    rm -rf "$out"
    ;;
  plan-and-run)
    dag_file="$CORTEX_TEMP/dag-$(date +%s%N).json"
    build_dag "$arg" > "$dag_file"
    out="$CORTEX_TEMP/planner-$(date +%s%N)"
    mkdir -p "$out"
    bash "$CORTEX_ROOT/core/planner/worker-pool.sh" run "$dag_file" "$out" >/dev/null
    bash "$CORTEX_ROOT/core/planner/merge-engine.sh" "$out"
    rm -rf "$out" "$dag_file"
    ;;
  *)
    echo "usage: planner-engine.sh {build|run|plan-and-run} <arg>" >&2; exit 2;;
esac

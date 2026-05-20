#!/usr/bin/env bash
# @version: 1.0.0
# Orchestrator: runs the 5-probe debug DAG in parallel via the planner.
# Emits one merged evidence bundle on stdout.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

exec bash "$CORTEX_ROOT/core/planner/planner-engine.sh" plan-and-run debug

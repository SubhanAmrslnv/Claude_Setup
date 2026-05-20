#!/usr/bin/env bash
# @version: 1.0.0
# Bounded parallel worker pool — runs a task DAG to completion.
#
# Usage:
#   worker-pool.sh run <dag.json> <out-dir>
#
# - Reads tasks from <dag.json>.
# - For each frontier task, spawns `bash <handler> <args>` in background, capping
#   concurrency at $CORTEX_MAX_JOBS (config: planner.maxJobs; default 4).
# - Captures stdout to <out-dir>/<task-id>.json (raw text; JSON-shaped if the
#   handler emits JSON).
# - Captures exit code to <out-dir>/<task-id>.exit.
# - Retries failed tasks once. After second failure, marks <task-id>.failed.
# - Records completed task ids in <out-dir>/_done.json.
# - Exits 0 if all tasks succeeded; 1 if any task ultimately failed.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

[[ "${1:-}" == "run" ]] || { echo "usage: worker-pool.sh run <dag.json> <out-dir>" >&2; exit 2; }
dag="$2"; out="$3"
[[ -f "$dag" && -n "$out" ]] || { echo "worker-pool: bad args" >&2; exit 2; }
mkdir -p "$out"
echo '[]' > "$out/_done.json"
graph="$CORTEX_ROOT/core/planner/task-graph.sh"

max_jobs=$(cortex_config '.planner.maxJobs' "${CORTEX_MAX_JOBS:-4}")
[[ "$max_jobs" =~ ^[0-9]+$ ]] || max_jobs=4
declare -A attempts=()
overall=0

run_task() {
  local id="$1"
  local handler args
  handler=$(bash "$graph" handler "$dag" "$id")
  args=$(bash "$graph" args "$dag" "$id")
  [[ -z "$handler" ]] && { echo '{"error":"no_handler"}' > "$out/$id.json"; echo 127 > "$out/$id.exit"; return 127; }
  local hp="$CORTEX_ROOT/core/$handler"
  [[ -f "$hp" ]] || { echo '{"error":"handler_missing"}' > "$out/$id.json"; echo 127 > "$out/$id.exit"; return 127; }
  bash "$hp" $args > "$out/$id.json" 2>"$out/$id.err"
  local rc=$?
  echo "$rc" > "$out/$id.exit"
  return $rc
}

while :; do
  mapfile -t frontier < <(bash "$graph" frontier "$dag" "$out/_done.json")
  (( ${#frontier[@]} == 0 )) && break

  # Filter out already-failed tasks.
  next=()
  for id in "${frontier[@]}"; do
    [[ -f "$out/$id.failed" ]] || next+=("$id")
  done
  (( ${#next[@]} == 0 )) && break

  pids=()
  for id in "${next[@]}"; do
    ( run_task "$id" ) &
    pids+=("$!:$id")
    while (( $(jobs -r | wc -l) >= max_jobs )); do wait -n 2>/dev/null || break; done
  done
  wait

  progressed=0
  for entry in "${pids[@]}"; do
    id="${entry#*:}"
    rc=$(cat "$out/$id.exit" 2>/dev/null || echo 1)
    if [[ "$rc" -eq 0 ]]; then
      jq --arg id "$id" '. + [$id]' "$out/_done.json" > "$out/_done.json.tmp" && mv "$out/_done.json.tmp" "$out/_done.json"
      progressed=1
    else
      a=${attempts[$id]:-0}; a=$((a+1)); attempts[$id]=$a
      if (( a >= 2 )); then
        touch "$out/$id.failed"
        overall=1
        progressed=1
      fi
    fi
  done

  (( progressed == 0 )) && break
done

exit $overall

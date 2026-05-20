#!/usr/bin/env bash
# @version: 1.0.0
# Task DAG operations — topological frontier extraction.
#
# A DAG is a JSON object:
#   { "tasks": { "id": { "handler": "path/to/script.sh", "args": "...",
#                        "depends_on": ["id"] } } }
#
# Usage:
#   task-graph.sh frontier <dag.json> <done.json>    # next runnable task ids
#   task-graph.sh validate <dag.json>                # exit 0 if acyclic
#   task-graph.sh handler  <dag.json> <task-id>      # handler path
#   task-graph.sh args     <dag.json> <task-id>      # args string

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

cmd="${1:-}"; dag="${2:-}"
[[ -z "$cmd" || -z "$dag" || ! -f "$dag" ]] && { echo "usage: task-graph.sh <cmd> <dag.json> [...]" >&2; exit 2; }

case "$cmd" in
  frontier)
    done_file="${3:-}"
    if [[ -f "$done_file" ]]; then
      jq -r --slurpfile d "$done_file" '
        .tasks
        | to_entries
        | map(select(([.value.depends_on // []] | flatten | (. - ($d[0] // []))) | length == 0))
        | map(select(.key as $k | ($d[0] // []) | index($k) | not))
        | .[].key
      ' "$dag"
    else
      jq -r '.tasks | to_entries | map(select((.value.depends_on // []) | length == 0)) | .[].key' "$dag"
    fi
    ;;
  validate)
    # Detect cycles via repeated frontier elimination.
    nodes=$(jq -r '.tasks | keys | length' "$dag")
    visited=0
    done_arr='[]'
    while :; do
      front=$(jq -r --argjson d "$done_arr" '
        .tasks | to_entries
        | map(select(([.value.depends_on // []] | flatten | (. - $d)) | length == 0))
        | map(select(.key as $k | $d | index($k) | not))
        | .[].key' "$dag")
      [[ -z "$front" ]] && break
      for k in $front; do
        done_arr=$(jq -nc --argjson a "$done_arr" --arg k "$k" '$a + [$k]')
        visited=$((visited+1))
      done
    done
    [[ "$visited" -eq "$nodes" ]] || { echo "cycle detected: visited=$visited/$nodes" >&2; exit 1; }
    ;;
  handler)
    jq -r --arg id "${3:-}" '.tasks[$id].handler // empty' "$dag"
    ;;
  args)
    jq -r --arg id "${3:-}" '.tasks[$id].args // ""' "$dag"
    ;;
  *)
    echo "unknown subcommand: $cmd" >&2; exit 2;;
esac

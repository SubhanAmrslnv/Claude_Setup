#!/usr/bin/env bash
# @version: 1.0.0
# Cortex event dispatcher — drains $CORTEX_EVENTS, fans out subscribers in parallel.
#
# Picks up one batch of event files, looks each event name up in
# subscriptions.json, fires each subscriber as a background bash job (with the
# event JSON on stdin), waits for the cohort, then deletes the events.

set -u
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

subs_file="$CORTEX_ROOT/core/events/subscriptions.json"
[[ -f "$subs_file" ]] || exit 0

# Serialize dispatch with a non-blocking lock so concurrent publishers don't pile up.
lock="$CORTEX_TEMP/.dispatcher.lock"
exec 9>"$lock"
flock -n 9 || exit 0

max_jobs=$(cortex_config '.eventBus.maxJobs' '4')
[[ "$max_jobs" =~ ^[0-9]+$ ]] || max_jobs=4

shopt -s nullglob
events=( "$CORTEX_EVENTS"/*.json )
(( ${#events[@]} == 0 )) && exit 0

for event_file in "${events[@]}"; do
  [[ -s "$event_file" ]] || { rm -f "$event_file"; continue; }
  name=$(jq -r '.name // empty' "$event_file" 2>/dev/null)
  [[ -z "$name" ]] && { rm -f "$event_file"; continue; }

  mapfile -t handlers < <(jq -r --arg n "$name" '.[$n][]? // empty' "$subs_file" 2>/dev/null)
  (( ${#handlers[@]} == 0 )) && { rm -f "$event_file"; continue; }

  # Subscribers expect the raw payload, not the {name,ts,payload} envelope.
  payload_file="$event_file.payload"
  jq -c '.payload // {}' "$event_file" > "$payload_file" 2>/dev/null
  for h in "${handlers[@]}"; do
    handler="$CORTEX_ROOT/core/$h"
    [[ -f "$handler" ]] || continue
    ( bash "$handler" < "$payload_file" >/dev/null 2>&1 ) &
    while (( $(jobs -r | wc -l) >= max_jobs )); do wait -n 2>/dev/null || break; done
  done
  wait
  rm -f "$event_file" "$payload_file"
done

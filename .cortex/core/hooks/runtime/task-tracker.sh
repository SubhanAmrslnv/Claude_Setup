#!/usr/bin/env bash
# @version: 1.0.2
# TaskCreated / TaskCompleted hook — persists tasks to .cortex/cache/tasks.json.
# Reads payload from stdin. Always exits 0.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

event="${HOOK_EVENT:-}"

# ─── Single-pass input extraction (7 jq spawns → 2) ─────────────────────────
mapfile -t _f < <(echo "$input" | jq -r '
  (.hook_event // .event // ""),
  (.cwd // ""),
  (.task.id // .id // ""),
  (.task.title // .title // "Untitled task"),
  (.task.status // .status // ""),
  (.task.priority // .priority // "normal"),
  (.task.agent // .agent_source // "")
' 2>/dev/null)
[[ -z "$event" ]] && event="${_f[0]:-}"
cwd="${_f[1]:-}"; task_id="${_f[2]:-}"; title="${_f[3]:-Untitled task}"
status="${_f[4]:-}"; priority="${_f[5]:-normal}"; agent="${_f[6]:-}"
files=$(echo "$input" | jq -c '.task.related_files // .related_files // []' 2>/dev/null)

# Resolve tasks file relative to cwd or CORTEX_ROOT
[[ -z "$cwd" || ! -d "$cwd" ]] && cwd=$(pwd)
TASKS_FILE="$cwd/.cortex/cache/tasks.json"
mkdir -p "$(dirname "$TASKS_FILE")"

# ─── Init file if missing ────────────────────────────────────────────────────
if [[ ! -f "$TASKS_FILE" ]]; then
  echo '{"tasks":[]}' > "$TASKS_FILE"
fi

# Validate JSON integrity; reset if corrupt
if ! jq empty "$TASKS_FILE" 2>/dev/null; then
  echo '{"tasks":[]}' > "$TASKS_FILE"
fi

# ─── Atomic write helper ─────────────────────────────────────────────────────
write_tasks() {
  local new_json="$1"
  local tmp="${TASKS_FILE}.tmp.$$"
  echo "$new_json" > "$tmp" && mv "$tmp" "$TASKS_FILE"
}

now=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)

# ─── TaskCreated ─────────────────────────────────────────────────────────────
if [[ "$event" == "TaskCreated" || "$event" == "task_created" ]]; then
  [[ -z "$status" ]] && status="pending"
  [[ -z "$title"  ]] && title="Untitled task"

  # Generate ID if missing
  if [[ -z "$task_id" ]]; then
    task_id="task-$(date -u +%s)-$$"
  fi

  # Prevent duplicate ID
  exists=$(jq --arg id "$task_id" '[.tasks[] | select(.id == $id)] | length' "$TASKS_FILE")
  if [[ "$exists" -gt 0 ]]; then
    jq -n --arg id "$task_id" \
      '{"success":false,"error":"Task with this ID already exists","id":$id}'
    exit 0
  fi

  # Build metadata object
  meta=$(jq -n \
    --arg priority "$priority" \
    --arg agent    "$agent" \
    --argjson files "$files" \
    '{priority:$priority} +
     (if $agent != "" then {agent:$agent} else {} end) +
     (if ($files | length) > 0 then {related_files:$files} else {} end)')

  # Append task
  new_state=$(jq \
    --arg id     "$task_id" \
    --arg title  "$title" \
    --arg status "$status" \
    --arg now    "$now" \
    --argjson meta "$meta" \
    '.tasks += [{
      id:        $id,
      title:     $title,
      status:    $status,
      createdAt: $now,
      updatedAt: $now,
      metadata:  $meta
    }]' "$TASKS_FILE")

  write_tasks "$new_state"

  jq -n \
    --arg id     "$task_id" \
    --arg status "$status" \
    --arg now    "$now" \
    '{"success":true,"task":{"id":$id,"status":$status,"updatedAt":$now}}'

  exit 0
fi

# ─── TaskCompleted ────────────────────────────────────────────────────────────
if [[ "$event" == "TaskCompleted" || "$event" == "task_completed" ]]; then
  if [[ -z "$task_id" ]]; then
    jq -n '{"success":false,"error":"Missing task id"}'
    exit 0
  fi

  # Check task exists
  exists=$(jq --arg id "$task_id" '[.tasks[] | select(.id == $id)] | length' "$TASKS_FILE")
  if [[ "$exists" -eq 0 ]]; then
    jq -n --arg id "$task_id" '{"success":false,"error":"Task not found","id":$id}'
    exit 0
  fi

  new_state=$(jq \
    --arg id  "$task_id" \
    --arg now "$now" \
    '(.tasks[] | select(.id == $id)) |= (.status = "completed" | .updatedAt = $now)' \
    "$TASKS_FILE")

  write_tasks "$new_state"

  jq -n \
    --arg id  "$task_id" \
    --arg now "$now" \
    '{"success":true,"task":{"id":$id,"status":"completed","updatedAt":$now}}'

  exit 0
fi

# ─── TaskUpdated (status change mid-lifecycle) ────────────────────────────────
if [[ "$event" == "TaskUpdated" || "$event" == "task_updated" ]]; then
  new_status="$status"   # already extracted in single-pass above

  if [[ -z "$task_id" || -z "$new_status" ]]; then
    jq -n '{"success":false,"error":"Missing task id or status"}'
    exit 0
  fi

  exists=$(jq --arg id "$task_id" '[.tasks[] | select(.id == $id)] | length' "$TASKS_FILE")
  if [[ "$exists" -eq 0 ]]; then
    jq -n --arg id "$task_id" '{"success":false,"error":"Task not found","id":$id}'
    exit 0
  fi

  new_state=$(jq \
    --arg id     "$task_id" \
    --arg status "$new_status" \
    --arg now    "$now" \
    '(.tasks[] | select(.id == $id)) |= (.status = $status | .updatedAt = $now)' \
    "$TASKS_FILE")

  write_tasks "$new_state"

  jq -n \
    --arg id     "$task_id" \
    --arg status "$new_status" \
    --arg now    "$now" \
    '{"success":true,"task":{"id":$id,"status":$status,"updatedAt":$now}}'

  exit 0
fi

# Unknown event — exit silently
exit 0

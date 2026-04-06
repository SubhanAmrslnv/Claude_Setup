#!/usr/bin/env bash
# @version: 1.0.1
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

# Determine which event fired via HOOK_EVENT or payload field
event="${HOOK_EVENT:-}"
[[ -z "$event" ]] && event=$(echo "$input" | jq -r '.hook_event // .event // empty' 2>/dev/null)

# Resolve tasks file relative to cwd or CORTEX_ROOT
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
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
  task_id=$(echo "$input"    | jq -r '.task.id    // .id    // empty' 2>/dev/null)
  title=$(echo "$input"      | jq -r '.task.title // .title // empty' 2>/dev/null)
  status=$(echo "$input"     | jq -r '.task.status // "pending"'      2>/dev/null)
  priority=$(echo "$input"   | jq -r '.task.priority // .priority // "normal"' 2>/dev/null)
  agent=$(echo "$input"      | jq -r '.task.agent // .agent_source // empty'   2>/dev/null)
  files=$(echo "$input"      | jq -c '.task.related_files // .related_files // []' 2>/dev/null)

  # Generate ID if missing
  if [[ -z "$task_id" ]]; then
    task_id="task-$(date -u +%s)-$$"
  fi

  # Title fallback
  [[ -z "$title" ]] && title="Untitled task"

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
  task_id=$(echo "$input" | jq -r '.task.id // .id // empty' 2>/dev/null)

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
  task_id=$(echo "$input" | jq -r '.task.id // .id // empty' 2>/dev/null)
  new_status=$(echo "$input" | jq -r '.task.status // .status // empty' 2>/dev/null)

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

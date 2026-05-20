#!/usr/bin/env bash
# @version: 2.0.0
# Cortex status line — Cortex-native project dashboard.
# Reads Claude Code's session JSON from stdin and emits real-time metrics on
# stdout. Never fails loudly: any error renders a one-line fallback and exits 0.

set -u
trap 'echo "│ Cortex │ —"; exit 0' EXIT

if ! source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" 2>/dev/null; then
  trap - EXIT
  echo "│ Cortex │ —"
  exit 0
fi

stdin=$(cat 2>/dev/null || echo "{}")

# Strip CR — jq emits CRLF on some Windows shells and breaks downstream tests.
j() { jq -r "$1" <<<"$stdin" 2>/dev/null | tr -d '\r'; }
g() { jq -r "$1" "$2" 2>/dev/null | tr -d '\r'; }

human_size() {
  local bytes="${1:-0}"
  if   (( bytes >= 1048576 )); then printf "%dMB" $(( bytes / 1048576 ))
  else                              printf "%dKB" $(( bytes / 1024 ))
  fi
}
du_bytes() {
  local p="$1"
  [[ -e "$p" ]] || { echo 0; return; }
  du -sk "$p" 2>/dev/null | awk '{print $1*1024}'
}
elapsed() {
  local ms="${1:-0}"
  [[ "$ms" =~ ^[0-9]+$ ]] || { echo "0s"; return; }
  local s=$(( ms / 1000 ))
  if   (( s < 60 ));   then printf "%ds" "$s"
  elif (( s < 3600 )); then printf "%dm%ds" $(( s/60 )) $(( s%60 ))
  else                       printf "%dh%dm" $(( s/3600 )) $(( (s%3600)/60 ))
  fi
}

# ── session (stdin) ──────────────────────────────────────────────────────────
model=$(j '.model.display_name // .model.id // "Claude"')
[[ -z "$model" || "$model" == "null" ]] && model="Claude"
duration_ms=$(j '.cost.total_duration_ms // 0')
elapsed_str=$(elapsed "$duration_ms")
mode=$(j '.permission_mode // ""')
# Context % — derived from the transcript's most recent usage entry.
# Claude Code passes `transcript_path` in the session JSON; the JSONL contains
# `{"message":{"usage":{...}}}` lines whose token totals we sum, divided by the
# model's context window (200k for current Claude 4.x).
context_disp="—"
context_used_tokens=0
transcript_path=$(j '.transcript_path // empty')
if [[ -n "$transcript_path" && -f "$transcript_path" ]]; then
  used=$(tail -n 200 "$transcript_path" 2>/dev/null \
    | jq -rs '
        map(select(.message.usage != null))
        | last
        | .message.usage
        | ( (.input_tokens // 0)
          + (.cache_read_input_tokens // 0)
          + (.cache_creation_input_tokens // 0) )
      ' 2>/dev/null | tr -d '\r')
  if [[ "$used" =~ ^[0-9]+$ && "$used" -gt 0 ]]; then
    context_used_tokens=$used
    # Model-aware context window: Opus runs on a 1M-token window, Sonnet/Haiku
    # on 200k. Override per-project via cortex.config.json → statusLine.contextWindow.
    ctx_window=$(cortex_config '.statusLine.contextWindow' '')
    if ! [[ "$ctx_window" =~ ^[0-9]+$ ]]; then
      model_lc=$(echo "$model" | tr '[:upper:]' '[:lower:]')
      case "$model_lc" in
        *opus*)   ctx_window=1000000 ;;
        *sonnet*) ctx_window=200000 ;;
        *haiku*)  ctx_window=200000 ;;
        *)        # Unknown model — fall back to usage-driven auto-detect.
                  if (( used > 200000 )); then ctx_window=1000000; else ctx_window=200000; fi ;;
      esac
    fi
    pct=$(( used * 100 / ctx_window ))
    (( pct > 100 )) && pct=100
    context_disp="${pct}%"
  fi
fi

# ── Cortex version ───────────────────────────────────────────────────────────
cortex_version=$(g '.version // "?"' "$CORTEX_CONFIG")
[[ -z "$cortex_version" || "$cortex_version" == "null" ]] && cortex_version="?"

# ── hooks: real deployed/total from registry vs. filesystem ──────────────────
hooks_total=0; hooks_deployed=0
if [[ -f "$CORTEX_ROOT/registry/hooks.json" ]]; then
  mapfile -t _srcs < <(g '.[].source' "$CORTEX_ROOT/registry/hooks.json")
  hooks_total=${#_srcs[@]}
  for s in "${_srcs[@]}"; do
    [[ -n "$s" && -f "$CORTEX_ROOT/$s" ]] && hooks_deployed=$(( hooks_deployed + 1 ))
  done
fi

# ── commands ─────────────────────────────────────────────────────────────────
cmd_total=0; cmd_deployed=0
if [[ -f "$CORTEX_ROOT/registry/commands.json" ]]; then
  mapfile -t _cmds < <(g '.commands[]?' "$CORTEX_ROOT/registry/commands.json")
  cmd_total=${#_cmds[@]}
  for c in "${_cmds[@]}"; do
    [[ -n "$c" && -f "$CORTEX_ROOT/commands/$c.md" ]] && cmd_deployed=$(( cmd_deployed + 1 ))
  done
fi

# ── scanners: count unique script paths in the registry ──────────────────────
scanner_count=0
if [[ -f "$CORTEX_ROOT/registry/scanners.json" ]]; then
  scanner_count=$(g '[.[][]] | unique | length' "$CORTEX_ROOT/registry/scanners.json")
  [[ "$scanner_count" =~ ^[0-9]+$ ]] || scanner_count=0
fi

# ── risk thresholds from config ──────────────────────────────────────────────
risk_warn=$(cortex_config  '.riskThresholds.warn'  '30')
risk_block=$(cortex_config '.riskThresholds.block' '70')

# ── memory size (Cortex project memory) ──────────────────────────────────────
mem_bytes=$(du_bytes "$CORTEX_ROOT/project/memory")
mem_human=$(human_size "$mem_bytes")

# ── saved plans count ────────────────────────────────────────────────────────
plans_count=0
if [[ -f "$CORTEX_ROOT/project/memory/plans.json" ]]; then
  plans_count=$(g '.plans | length' "$CORTEX_ROOT/project/memory/plans.json")
  [[ "$plans_count" =~ ^[0-9]+$ ]] || plans_count=0
fi

# ── events queue depth ───────────────────────────────────────────────────────
events_pending=0
if [[ -d "$CORTEX_EVENTS" ]]; then
  events_pending=$(find "$CORTEX_EVENTS" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
fi

# ── indexed files (lazy memory cache) ────────────────────────────────────────
indexed=0
[[ -f "$CORTEX_CACHE/file-index.txt" ]] && indexed=$(wc -l < "$CORTEX_CACHE/file-index.txt" 2>/dev/null | tr -d ' ')
[[ -z "$indexed" ]] && indexed=0

# ── audit log line count ─────────────────────────────────────────────────────
audit_lines=0
[[ -f "$CORTEX_LOGS/audit.log" ]] && audit_lines=$(wc -l < "$CORTEX_LOGS/audit.log" 2>/dev/null | tr -d ' ')
[[ -z "$audit_lines" ]] && audit_lines=0

# ── tests: real file count + real test-case grep ─────────────────────────────
project_root="$(dirname "$CORTEX_ROOT")"
mapfile -t test_files < <(
  find "$project_root" -maxdepth 4 -type f \
    \( -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' \
       -o -name '*.spec.ts' -o -name '*.spec.js' \
       -o -name 'test_*.py' -o -name '*_test.go' -o -name '*Tests.cs' \) \
    -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null | head -n 200
)
tests_count="${#test_files[@]}"
tests_cases=0
if (( tests_count > 0 )); then
  tests_cases=$(grep -hcE '\b(it|test|describe)\(|^[[:space:]]*def[[:space:]]+test_|^func[[:space:]]+Test|\[(Fact|Theory|Test|TestMethod)\]' \
    "${test_files[@]}" 2>/dev/null | awk '{s+=$1} END{print s+0}')
fi
[[ "$tests_cases" =~ ^[0-9]+$ ]] || tests_cases=0

# ── git: branch + dirty count ────────────────────────────────────────────────
branch=""; dirty_add=0; dirty_mod=0
if command -v git >/dev/null 2>&1 && [[ -d "$project_root/.git" ]]; then
  branch=$(git -C "$project_root" rev-parse --abbrev-ref HEAD 2>/dev/null | tr -d '\r')
  status_lines=$(git -C "$project_root" status --porcelain 2>/dev/null)
  if [[ -n "$status_lines" ]]; then
    dirty_add=$(echo "$status_lines" | grep -cE '^\?\?|^A')
    dirty_mod=$(echo "$status_lines" | grep -cE '^.M|^M|^.D|^D')
  fi
fi

# ── palette ──────────────────────────────────────────────────────────────────
# Semantic roles:
#   LABEL  — section names (Hooks, Commands, …)         → bold cyan
#   VAL    — neutral numeric value (counts that have no health signal) → bright white
#   GOOD   — green (healthy / deployed)
#   WARN   — yellow (partial / pending)
#   BAD    — red   (failure / over threshold)
#   ACCENT — magenta (version, branch)
#   TIME   — yellow (elapsed time)
#   FRAME  — dim cyan (separators, pipes)
if [[ -z "${NO_COLOR:-}" ]]; then
  C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
  # Cyberpunk-HUD palette — true-color (24-bit RGB) for full neon saturation.
  C_LABEL=$'\e[1;38;2;0;255;255m'      # #00FFFF  electric cyan   — labels
  C_VAL=$'\e[1;38;2;255;165;0m'        # #FFA500  HUD orange      — neutral values
  C_GOOD=$'\e[1;38;2;57;255;20m'       # #39FF14  neon green      — healthy
  C_WARN=$'\e[1;38;2;255;255;0m'       # #FFFF00  acid yellow     — partial / pending
  C_BAD=$'\e[1;38;2;255;45;0m'         # #FF2D00  lava red        — failure
  C_ACCENT=$'\e[1;38;2;191;0;255m'     # #BF00FF  neon purple     — version, branch
  C_TIME=$'\e[1;38;2;176;255;0m'       # #B0FF00  acid lime       — elapsed time
  C_FRAME=$'\e[38;2;0;139;139m'        # #008B8B  dark cyan       — separators, pipes
  C_MODE=$'\e[1;38;2;255;20;147m'      # #FF1493  hot pink        — mode hint
else
  C_RESET=""; C_BOLD=""; C_DIM=""
  C_LABEL=""; C_VAL=""; C_GOOD=""; C_WARN=""; C_BAD=""
  C_ACCENT=""; C_TIME=""; C_FRAME=""; C_MODE=""
fi

# Health-aware coloring helper.
# Usage: hue=$(health <num> <full> [reverse])
#   <full>    target for "all good"
#   reverse=1 means lower-is-better (used for context %, events queue)
health() {
  local n="$1" full="$2" rev="${3:-0}"
  [[ "$n" =~ ^[0-9]+$ ]] || { echo "$C_WARN"; return; }
  if (( rev == 1 )); then
    local pct=$(( full > 0 ? n * 100 / full : 0 ))
    if   (( pct >= 90 )); then echo "$C_BAD"
    elif (( pct >= 70 )); then echo "$C_WARN"
    else                       echo "$C_GOOD"; fi
  else
    if   (( n >= full )); then echo "$C_GOOD"
    elif (( n == 0 ));    then echo "$C_DIM"
    else                       echo "$C_WARN"; fi
  fi
}

# Pre-color every value.
HOOK_HUE=$(health "$hooks_deployed" "$hooks_total")
CMD_HUE=$(health  "$cmd_deployed"   "$cmd_total")
SCAN_HUE=$(health "$scanner_count"  "$scanner_count")
RISK_HUE=$C_WARN

MEM_HUE=$C_VAL
EVT_HUE=$C_GOOD; (( events_pending > 0 )) && EVT_HUE=$C_WARN
IDX_HUE=$C_VAL;  (( indexed == 0 ))       && IDX_HUE=$C_DIM
AUD_HUE=$C_VAL

# Context % — lower is better; tinted by occupancy.
CTX_HUE=$C_DIM
if [[ "$context_disp" != "—" ]]; then
  ctx_n="${context_disp%\%}"
  if   (( ctx_n >= 80 )); then CTX_HUE=$C_BAD
  elif (( ctx_n >= 50 )); then CTX_HUE=$C_WARN
  else                          CTX_HUE=$C_GOOD; fi
fi

TESTS_HUE=$C_DIM; (( tests_count > 0 )) && TESTS_HUE=$C_GOOD
CASE_HUE=$C_DIM;  (( tests_cases > 0 )) && CASE_HUE=$C_GOOD
PLANS_HUE=$C_DIM; (( plans_count > 0 )) && PLANS_HUE=$C_ACCENT

# Status dots use the same hue as their counter for visual cohesion.
hooks_dot="${HOOK_HUE}●${C_RESET}"
cmds_dot="${CMD_HUE}●${C_RESET}"
events_dot="${EVT_HUE}●${C_RESET}"
tests_dot="${TESTS_HUE}●${C_RESET}"
(( tests_count == 0 )) && tests_dot="${C_DIM}○${C_RESET}"
(( events_pending == 0 )) && events_dot="${C_DIM}○${C_RESET}"

mode_line=""
case "$mode" in
  plan)              mode_line="${C_MODE}⏸ plan mode on${C_RESET} ${C_DIM}(shift+tab to cycle)${C_RESET}" ;;
  acceptEdits)       mode_line="${C_GOOD}▶ accept-edits mode${C_RESET}" ;;
  bypassPermissions) mode_line="${C_BAD}⚡ bypass-permissions mode${C_RESET}" ;;
esac

git_line=""
if [[ -n "$branch" ]]; then
  if (( dirty_add + dirty_mod > 0 )); then
    git_line="${C_ACCENT}${branch}${C_RESET} ${C_GOOD}+${dirty_add}${C_RESET} ${C_WARN}~${dirty_mod}${C_RESET}"
  else
    git_line="${C_ACCENT}${branch}${C_RESET} ${C_GOOD}clean${C_RESET}"
  fi
fi

# ── render ───────────────────────────────────────────────────────────────────
sep="${C_FRAME}  ─────────────────────────────────────────────────────${C_RESET}"
PIPE="${C_FRAME}│${C_RESET}"

printf "${C_ACCENT}Cortex v%s${C_RESET} %s ${C_BOLD}${C_LABEL}%s${C_RESET} %s ${C_TIME}⏱ %s${C_RESET}\n" \
  "$cortex_version" "$PIPE" "$model" "$PIPE" "$elapsed_str"
printf "%s\n" "$sep"
printf "  ${C_LABEL}🪝 Hooks${C_RESET} %s${HOOK_HUE}%d/%d${C_RESET}    ${C_LABEL}📜 Commands${C_RESET} %s${CMD_HUE}%d/%d${C_RESET}    ${C_LABEL}🔎 Scanners${C_RESET} ${SCAN_HUE}%d${C_RESET}    ${C_LABEL}🛡️ Risk${C_RESET} ${C_GOOD}%d${C_RESET}${C_DIM}/${C_RESET}${C_BAD}%d${C_RESET}\n" \
  "$hooks_dot" "$hooks_deployed" "$hooks_total" \
  "$cmds_dot"  "$cmd_deployed"   "$cmd_total" \
  "$scanner_count" "$risk_warn" "$risk_block"
printf "  ${C_LABEL}💾 Memory${C_RESET} ${MEM_HUE}%s${C_RESET}    ${C_LABEL}📨 Events${C_RESET} %s${EVT_HUE}%d${C_RESET}    ${C_LABEL}📂 Indexed${C_RESET} ${IDX_HUE}%d${C_RESET}    ${C_LABEL}📑 Audit${C_RESET} ${AUD_HUE}%d${C_RESET}    ${C_LABEL}🧠 Context${C_RESET} ${CTX_HUE}%s${C_RESET}\n" \
  "$mem_human" "$events_dot" "$events_pending" "$indexed" "$audit_lines" "$context_disp"
printf "  ${C_LABEL}📊 Tests${C_RESET} %s${TESTS_HUE}%d${C_RESET} ${C_DIM}(${C_RESET}${CASE_HUE}~%d cases${C_RESET}${C_DIM})${C_RESET}    ${C_LABEL}🗂️ Plans${C_RESET} ${PLANS_HUE}%d${C_RESET}" \
  "$tests_dot" "$tests_count" "$tests_cases" "$plans_count"
[[ -n "$git_line" ]] && printf "    ${C_LABEL}🌿${C_RESET} %s" "$git_line"
printf "\n"
[[ -n "$mode_line" ]] && printf "  %s\n" "$mode_line"

trap - EXIT

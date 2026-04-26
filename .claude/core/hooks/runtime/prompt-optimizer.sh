#!/usr/bin/env bash
# @version: 3.0.0
# UserPromptSubmit structured prompt engine.
# Detects intent → scores files → structural summary + focused snippet.
# Enhancements v3: structural extraction, basename dedup, git priority preload,
# intent-based radius, hard context caps (max_files=2, max_total_lines=60),
# noise path filtering, static guidance blocks, slim profile consumption,
# keyword alias expansion, intent-layer scoring.
# --y suffix: strip flag, inject GLOBAL ANSWER POLICY (YES-default).

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

prompt=$(echo "$input" | jq -r '.prompt // empty' 2>/dev/null)
[[ -z "$prompt" ]] && exit 0

# Skip enrichment for very long prompts — already rich in context
(( ${#prompt} > 6000 )) && exit 0

# ── --y flag handling ─────────────────────────────────────────────────────────
yes_mode=0
if [[ "$prompt" =~ (^|[[:space:]])--y([[:space:]]|$) || "$prompt" == *" --y" || "$prompt" == "--y" ]]; then
  yes_mode=1
  prompt=$(echo "$prompt" | sed 's/[[:space:]]*--y[[:space:]]*$//' | sed 's/[[:space:]]*--y[[:space:]]/ /g' | xargs)
fi

# ── Intent detection ──────────────────────────────────────────────────────────
prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')
intent="question"

if echo "$prompt_lower" | grep -qE '\b(fix|bug|error|issue|broken|crash|fail|exception|traceback|stacktrace|undefined|null)\b'; then
  intent="bug_fix"
elif echo "$prompt_lower" | grep -qE '\b(add|implement|create|build|develop|new feature|integrate|write)\b'; then
  intent="feature_request"
elif echo "$prompt_lower" | grep -qE '\b(refactor|clean up|improve|optimize|simplify|restructure|reorganize|extract)\b'; then
  intent="refactor"
fi

# ── Static guidance blocks (predefined constants, never rebuilt at runtime) ───
readonly _BUG_GUIDANCE="root-cause-first: trace execution path to fault site; apply minimal surgical fix; preserve all existing behavior; check null dereferences, off-by-ones, type mismatches"
readonly _FEAT_GUIDANCE="contract-first: define interface/signature before implementation; follow existing patterns; minimal surface area; validate inputs at boundary; handle error paths"
readonly _REFACTOR_GUIDANCE="behavior-preservation: change structure only, never semantics; extract one concern per step; verify signature compatibility; no feature changes during refactor"

case "$intent" in
  bug_fix)         guidance="$_BUG_GUIDANCE" ;;
  feature_request) guidance="$_FEAT_GUIDANCE" ;;
  refactor)        guidance="$_REFACTOR_GUIDANCE" ;;
  *)               guidance="" ;;
esac

# ── Intent-based context caps (deterministic hard limits) ─────────────────────
case "$intent" in
  bug_fix)         snippet_radius=12; max_lines_per_file=30 ;;
  feature_request) snippet_radius=8;  max_lines_per_file=24 ;;
  refactor)        snippet_radius=6;  max_lines_per_file=20 ;;
  *)               snippet_radius=5;  max_lines_per_file=20 ;;
esac
readonly MAX_FILES=2
readonly MAX_TOTAL_LINES=60

# ── Keyword alias expansion dictionary (static, O(n) expansion) ──────────────
declare -A _ALIASES=(
  ["auth"]="login authenticate signin jwt token"
  ["user"]="account profile customer member"
  ["product"]="catalog item inventory sku"
  ["order"]="cart checkout payment invoice"
  ["api"]="endpoint route handler controller"
  ["db"]="database query repository store"
  ["error"]="exception failure crash bug"
  ["config"]="settings configuration options env"
  ["cache"]="redis memory store session"
  ["email"]="mail notification message smtp"
  ["search"]="filter query lookup find"
  ["file"]="upload download storage blob"
  ["log"]="audit trace event monitor"
  ["test"]="spec unit integration mock"
  ["deploy"]="release build publish pipeline"
)

# ── Extract keywords from prompt ──────────────────────────────────────────────
mapfile -t _raw_kw < <(
  echo "$prompt_lower" \
  | tr -s ' \t\n.,;:!?()[]{}=<>/\\@#$%^&*`"'"'" '\n' \
  | awk 'length >= 4' \
  | grep -vxE '(this|that|with|from|have|will|would|could|should|about|some|into|over|when|then|than|your|their|they|what|which|also|just|more|make|need|want|like|know|here|there|where|does|been|only|very|much|each|such|many|both|most|find|show|give|tell|help|please|using|code|file|line|func|function|method|class|type|variable|return|import|export|true|false|null|void)' \
  | sort -u | head -8
)

# Expand with aliases (dedup via associative array, O(n))
declare -A _seen_kw
keywords=()
for _kw in "${_raw_kw[@]}"; do
  [[ -n "${_seen_kw[$_kw]:-}" ]] && continue
  _seen_kw[$_kw]=1; keywords+=("$_kw")
  if [[ -n "${_ALIASES[$_kw]:-}" ]]; then
    read -ra _exp <<< "${_ALIASES[$_kw]}"
    for _ek in "${_exp[@]}"; do
      [[ -n "${_seen_kw[$_ek]:-}" ]] && continue
      _seen_kw[$_ek]=1; keywords+=("$_ek")
    done
  fi
done

[[ ${#keywords[@]} -eq 0 ]] && exit 0

# ── Scored command routing (bash string ops, no subprocess per keyword) ───────
command_hint=""
declare -A _cmd_scores
for _cp in \
  "commit:commit message staged changes" \
  "debug:debug error crash traceback exception" \
  "doctor:diagnose check health hooks settings" \
  "impact:impact blast radius changed files" \
  "regression:regression baseline snapshot" \
  "hotspot:hotspot churn frequency unstable" \
  "pr-check:pr pull request review validate" \
  "optimize:optimize performance slow bottleneck" \
  "documentation:docs document readme generate" \
  "pattern-drift:pattern drift convention inconsistent"
do
  _c="${_cp%%:*}"; _score=0
  for _kw in ${_cp#*:}; do
    [[ "$prompt_lower" == *"$_kw"* ]] && (( _score++ ))
  done
  _cmd_scores["$_c"]=$_score
done

_best_cmd=""; _best_score=0
for _c in "${!_cmd_scores[@]}"; do
  _s=${_cmd_scores[$_c]}
  (( _s > _best_score )) && { _best_score=$_s; _best_cmd=$_c; }
done
[[ $_best_score -ge 2 ]] && command_hint="/$_best_cmd"

# ── Load project profile — slim fields only (project_type, framework, arch) ──
PROFILE="$CORTEX_CACHE/project-profile.json"
project_type="unknown"; framework=""; arch=""
if [[ -f "$PROFILE" ]] && jq empty "$PROFILE" 2>/dev/null; then
  project_type=$(jq -r '.project_type // "unknown"' "$PROFILE" 2>/dev/null)
  framework=$(jq    -r '.framework    // empty'     "$PROFILE" 2>/dev/null)
  arch=$(jq         -r '.arch         // empty'     "$PROFILE" 2>/dev/null)
fi

# ── Git priority preload (single invocation outside scoring loops) ────────────
declare -A _git_changed
while IFS= read -r _gf; do
  [[ -n "$_gf" ]] && _git_changed["$_gf"]=1
done < <({ git diff --name-only 2>/dev/null; git diff --cached --name-only 2>/dev/null; } | sort -u)

# ── Noise path detection: does prompt explicitly target noisy dirs? ────────────
_targets_noise=0
echo "$prompt_lower" | grep -qE '\b(test|spec|migration|generated|generate|fixture)\b' \
  && _targets_noise=1

# ── File discovery: single find pass ─────────────────────────────────────────
declare -a _fnames
case "$project_type" in
  dotnet) _fnames=("-name" "*.cs") ;;
  node)   _fnames=("-name" "*.ts" "-o" "-name" "*.tsx" "-o" "-name" "*.js" "-o" "-name" "*.jsx") ;;
  python) _fnames=("-name" "*.py") ;;
  go)     _fnames=("-name" "*.go") ;;
  rust)   _fnames=("-name" "*.rs") ;;
  java)   _fnames=("-name" "*.java") ;;
  *)      _fnames=("-name" "*.cs" "-o" "-name" "*.ts" "-o" "-name" "*.tsx" "-o" \
                   "-name" "*.js" "-o" "-name" "*.jsx" "-o" "-name" "*.py" "-o" \
                   "-name" "*.go" "-o" "-name" "*.rs" "-o" "-name" "*.java") ;;
esac

mapfile -t all_files < <(
  find . -type f \( "${_fnames[@]}" \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*"        \
    -not -path "*/obj/*"          -not -path "*/bin/*"         \
    -not -path "*/target/*"       -not -path "*/__pycache__/*" \
    -not -path "*/.venv/*"        -not -path "*/dist/*"        \
    -not -path "*/build/*"        \
    2>/dev/null | head -300
)

[[ ${#all_files[@]} -eq 0 ]] && exit 0

# ── Noise path filtering (post-discovery, O(n)) ───────────────────────────────
if [[ $_targets_noise -eq 0 ]]; then
  _clean=()
  for _f in "${all_files[@]}"; do
    [[ "$_f" =~ /(Tests?|Migrations?|Generated|bin|obj|dist|build)/ ]] && continue
    _clean+=("$_f")
  done
  all_files=("${_clean[@]}")
  [[ ${#all_files[@]} -eq 0 ]] && exit 0
fi

# ── Intent-based layer boost pattern ─────────────────────────────────────────
case "$intent" in
  bug_fix)         _layer_pat="Service|Controller|Repository|Handler" ;;
  feature_request) _layer_pat="Controller|Dto|Command|Handler|Request|Response" ;;
  refactor)        _layer_pat="Service|Manager|Helper|Util" ;;
  *)               _layer_pat="" ;;
esac

# ── Score files by relevance ──────────────────────────────────────────────────
declare -A file_scores

# Keyword × filename (+3; bash string ops, no subprocess spawning)
for _kw in "${keywords[@]}"; do
  for _f in "${all_files[@]}"; do
    _fn=$(basename "${_f%.*}" | tr '[:upper:]' '[:lower:]')
    [[ "$_fn" == *"$_kw"* ]] && file_scores["$_f"]=$(( ${file_scores["$_f"]:-0} + 3 ))
  done
done

# Stack-trace file references in prompt (+5)
while IFS= read -r _ref; do
  [[ -z "$_ref" ]] && continue
  _rb=$(basename "$_ref" | cut -d: -f1 | tr '[:upper:]' '[:lower:]')
  for _f in "${all_files[@]}"; do
    _fb=$(basename "$_f" | tr '[:upper:]' '[:lower:]')
    [[ "$_fb" == "$_rb" ]] && file_scores["$_f"]=$(( ${file_scores["$_f"]:-0} + 5 ))
  done
done < <(echo "$prompt" | grep -oE '[A-Za-z0-9_/.-]+\.(cs|ts|tsx|js|jsx|py|go|rs|java)(:[0-9]+)?' 2>/dev/null | head -5)

# Git-changed boost (+4; uses preloaded map, no subprocess)
for _f in "${all_files[@]}"; do
  [[ -n "${_git_changed[${_f#./}]:-}" ]] && file_scores["$_f"]=$(( ${file_scores["$_f"]:-0} + 4 ))
done

# Layer-based boost (+2; basename ERE match against intent pattern)
if [[ -n "$_layer_pat" ]]; then
  for _f in "${all_files[@]}"; do
    _fn=$(basename "${_f%.*}")
    [[ "$_fn" =~ $_layer_pat ]] && file_scores["$_f"]=$(( ${file_scores["$_f"]:-0} + 2 ))
  done
fi

# Sort descending, cap at MAX_FILES
mapfile -t top_files < <(
  for _f in "${!file_scores[@]}"; do echo "${file_scores[$_f]} $_f"; done \
  | sort -rn | head -"$MAX_FILES" | awk '{print $2}'
)

# Minimum relevance filter (score < 3 = noise)
_keep=()
for _f in "${top_files[@]}"; do
  (( ${file_scores["$_f"]:-0} >= 3 )) && _keep+=("$_f")
done
top_files=("${_keep[@]}")

[[ ${#top_files[@]} -eq 0 ]] && {
  _ctx="[CORTEX]
intent: ${intent}
project: ${project_type}"
  [[ -n "$framework" ]]    && _ctx="${_ctx}"$'\n'"framework: ${framework}"
  [[ -n "$arch" ]]         && _ctx="${_ctx}"$'\n'"arch: ${arch}"
  [[ -n "$guidance" ]]     && _ctx="${_ctx}"$'\n'"guidance: ${guidance}"
  [[ -n "$command_hint" ]] && _ctx="${_ctx}"$'\n'"suggested_command: ${command_hint}"
  _ctx="${_ctx}"$'\n'"[/CORTEX]"
  _enriched="${_ctx}"$'\n\n'"${prompt}"
  [[ $yes_mode -eq 1 ]] && _enriched="${_enriched}"$'\n\n'"[GLOBAL ANSWER POLICY]
Default all binary decisions to YES. Skip confirmation prompts for non-destructive operations. Proceed directly with the requested action. Security risks and destructive operations (rm -rf, DROP TABLE, force-push to main) remain protected."
  jq -n --arg p "$_enriched" '{"prompt": $p}'
  exit 0
}

# ── Same-basename deduplication (IFoo + Foo → prefer Foo, skip IFoo) ─────────
_skip_iface=()
for _f in "${top_files[@]}"; do
  _base=$(basename "${_f%.*}")
  [[ "$_base" =~ ^I[A-Z] ]] || continue       # only interface-named candidates
  _impl="${_base#I}"                            # IUserService → UserService
  for _f2 in "${top_files[@]}"; do
    [[ "$(basename "${_f2%.*}")" == "$_impl" ]] && { _skip_iface+=("$_f"); break; }
  done
done
_deduped=()
for _f in "${top_files[@]}"; do
  _s=0
  for _sf in "${_skip_iface[@]}"; do [[ "$_f" == "$_sf" ]] && { _s=1; break; }; done
  [[ $_s -eq 0 ]] && _deduped+=("$_f")
done
top_files=("${_deduped[@]}")

# ── Structural extraction (single-pass per file; O(n) grepping, no recursion) ─
_extract_structure() {
  local _f="$1" _ext _types="" _methods="" _deps="" _out=""
  _ext="${_f##*.}"

  # Note: bash $(...) strips trailing newlines, so _out uses explicit $'\n' separators
  case "$_ext" in
    cs)
      _types=$(grep -oE '\b(class|interface|enum|struct)[[:space:]]+[A-Za-z_][A-Za-z0-9_<>]*' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "%s: %s",$1,$2}')
      _methods=$(grep -oE '\b(public|protected|internal)[[:space:]]+(static[[:space:]]+|async[[:space:]]+|virtual[[:space:]]+|override[[:space:]]+)*[A-Za-z_][A-Za-z0-9_<>\[\]]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$_f" 2>/dev/null \
                 | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' | sed 's/[[:space:]]*($//' \
                 | head -6 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      _deps=$(grep -oE 'private[[:space:]]+(readonly[[:space:]]+)?I[A-Za-z][A-Za-z0-9_<>]*' "$_f" 2>/dev/null \
              | awk '{print $NF}' | sort -u | head -4 \
              | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
    ts|tsx)
      _types=$(grep -oE '\b(export[[:space:]]+)?(class|interface|type|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_<>]*' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "%s: %s",$(NF-1),$NF}')
      _methods=$(grep -oE '^[[:space:]]+(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*\(' "$_f" 2>/dev/null \
                 | sed 's/^[[:space:]]*//' | sed 's/[[:space:]]*($//' \
                 | grep -vE '^(if|while|for|switch|catch|constructor)$' \
                 | head -6 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
    js|jsx)
      _types=$(grep -oE '\b(class|function)[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "%s: %s",$1,$2}')
      _methods=$(grep -oE '^[[:space:]]*(async[[:space:]]+)?[a-zA-Z_][a-zA-Z0-9_]*[[:space:]]*[=(]' "$_f" 2>/dev/null \
                 | grep -oE '^[[:space:]]*[a-zA-Z_][a-zA-Z0-9_]*' | tr -d ' ' \
                 | head -6 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
    py)
      _types=$(grep -oE '^class[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "class: %s",$2}')
      _methods=$(grep -oE '^[[:space:]]+def[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "$_f" 2>/dev/null \
                 | awk '{print $2}' | head -6 \
                 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
    go)
      _types=$(grep -oE '^type[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]+(struct|interface)' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "%s: %s",$3,$2}')
      _methods=$(grep -oE '^func[[:space:]]+(\([^)]+\)[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*' "$_f" 2>/dev/null \
                 | grep -oE '[A-Za-z_][A-Za-z0-9_]*$' | head -6 \
                 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
    java)
      _types=$(grep -oE '\b(class|interface|enum)[[:space:]]+[A-Za-z_][A-Za-z0-9_<>]*' "$_f" 2>/dev/null \
               | head -3 | awk '{if(NR>1)printf ", "; printf "%s: %s",$1,$2}')
      _methods=$(grep -oE '\b(public|protected)[[:space:]]+(static[[:space:]]+)?[A-Za-z_][A-Za-z0-9_<>\[\]]*[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' "$_f" 2>/dev/null \
                 | grep -oE '[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(' | sed 's/[[:space:]]*($//' \
                 | head -6 | awk '{if(NR>1)printf ", "; printf "%s",$0}')
      ;;
  esac

  [[ -n "$_types" ]]   && _out="${_out}  types: ${_types}"$'\n'
  [[ -n "$_methods" ]] && _out="${_out}  methods: ${_methods}"$'\n'
  [[ -n "$_deps" ]]    && _out="${_out}  deps: ${_deps}"$'\n'
  printf '%s' "$_out"
}

# ── Build code context blocks ─────────────────────────────────────────────────
snippets=""; _total_lines=0
_kw_pattern=$(IFS='|'; echo "${keywords[*]}")

for _f in "${top_files[@]}"; do
  [[ ! -f "$_f" ]] && continue
  (( _total_lines >= MAX_TOTAL_LINES )) && break

  _fsize=$(stat -c%s "$_f" 2>/dev/null || stat -f%z "$_f" 2>/dev/null || echo 0)
  (( _fsize > 102400 )) && continue

  _fname=$(basename "$_f")
  _struct=$(_extract_structure "$_f")

  # Single combined-keyword grep to find best context line
  _best=1
  if [[ -n "$_kw_pattern" ]]; then
    _found=$(grep -niE "$_kw_pattern" "$_f" 2>/dev/null | head -1 | cut -d: -f1)
    [[ -n "$_found" ]] && _best=$_found
  fi

  _start=$(( _best - snippet_radius )); (( _start < 1 )) && _start=1
  _end=$(( _best + snippet_radius ))

  # Enforce per-file cap and global total cap
  _allowed=$(( max_lines_per_file < MAX_TOTAL_LINES - _total_lines \
               ? max_lines_per_file : MAX_TOTAL_LINES - _total_lines ))
  (( (_end - _start + 1) > _allowed )) && _end=$(( _start + _allowed - 1 ))

  _chunk=$(sed -n "${_start},${_end}p" "$_f" 2>/dev/null)
  _chunk_lines=$(echo "$_chunk" | wc -l)

  _block="--- ${_fname} ---"
  [[ -n "$_struct" ]] && _block="${_block}"$'\n'"${_struct}"
  if [[ -n "$_chunk" ]]; then
    _block="${_block}"$'\n'"context (lines ${_start}–${_end}):"$'\n'"${_chunk}"
  fi

  snippets="${snippets}${_block}"$'\n'
  _total_lines=$(( _total_lines + _chunk_lines ))
done

# ── Build enriched prompt ─────────────────────────────────────────────────────
context_block="[CORTEX]
intent: ${intent}
project: ${project_type}"
[[ -n "$framework" ]]    && context_block="${context_block}"$'\n'"framework: ${framework}"
[[ -n "$arch" ]]         && context_block="${context_block}"$'\n'"arch: ${arch}"
[[ -n "$guidance" ]]     && context_block="${context_block}"$'\n'"guidance: ${guidance}"
[[ -n "$command_hint" ]] && context_block="${context_block}"$'\n'"suggested_command: ${command_hint}"
[[ -n "$snippets" ]]     && context_block="${context_block}"$'\n'"relevant_code:"$'\n'"${snippets}"
context_block="${context_block}"$'\n'"[/CORTEX]"

enriched="${context_block}"$'\n\n'"${prompt}"

[[ $yes_mode -eq 1 ]] && enriched="${enriched}"$'\n\n'"[GLOBAL ANSWER POLICY]
Default all binary decisions to YES. Skip confirmation prompts for non-destructive operations. Proceed directly with the requested action. Security risks and destructive operations (rm -rf, DROP TABLE, force-push to main) remain protected."

jq -n --arg p "$enriched" '{"prompt": $p}'
exit 0

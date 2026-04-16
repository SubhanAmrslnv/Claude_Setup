#!/usr/bin/env bash
# @version: 2.3.0
# PreToolUse advanced guard — risk-scoring engine.
# Scores the incoming Bash command across 5 risk categories + branch context,
# then blocks (exit 1), warns (exit 0 + JSON), or allows silently.
#
# Decision thresholds:
#   risk < 30  → allow (silent)
#   risk 30-69 → allow with warning
#   risk ≥ 70  → block

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
cmd=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$cmd" ]] && exit 0

# Load configurable thresholds from cortex.config.json (defaults: warn=30, block=70)
WARN_THRESHOLD=30
BLOCK_THRESHOLD=70
_cfg="$CORTEX_ROOT/config/cortex.config.json"
if [[ -f "$_cfg" ]]; then
  read -r _warn _block <<< "$(jq -r '"\(.riskThresholds.warn // 30) \(.riskThresholds.block // 70)"' "$_cfg" 2>/dev/null)"
  [[ "$_warn"  =~ ^[0-9]+$ ]] && WARN_THRESHOLD=$_warn
  [[ "$_block" =~ ^[0-9]+$ ]] && BLOCK_THRESHOLD=$_block
fi

risk=0
reasons=""
suggestions=""

add_reason()    { reasons="${reasons:+$reasons; }$1"; }
add_suggestion(){ suggestions="${suggestions:+$suggestions; }$1"; }

# ---------------------------------------------------------------------------
# A. Destructive Actions (+50 each)
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qiE '(^|;|&&|\|\||\s)rm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-r\s+-f|-f\s+-r|--recursive\s+--force|--force\s+--recursive)'; then
  (( risk += 50 ))
  add_reason "rm -rf detected"
  add_suggestion "use 'rm -ri' for interactive confirmation"
fi

if echo "$cmd" | grep -qiE '\b(drop\s+table|truncate\s+table)\b'; then
  (( risk += 50 ))
  add_reason "destructive SQL operation"
  add_suggestion "back up the table first; use a WHERE clause or soft-delete"
fi

if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git\s+reset\s+--hard'; then
  (( risk += 50 ))
  add_reason "git reset --hard discards uncommitted changes"
  add_suggestion "use 'git stash' to preserve changes before reset"
fi

if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git\s+clean\s+-[a-z]*f'; then
  (( risk += 50 ))
  add_reason "git clean -f permanently removes untracked files"
  add_suggestion "use 'git clean -n' to preview what would be removed"
fi

# ---------------------------------------------------------------------------
# B. Privileged Operations (+30 each)
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*sudo\s'; then
  (( risk += 30 ))
  add_reason "sudo usage"
  add_suggestion "use scoped permissions or a dedicated service account"
fi

if echo "$cmd" | grep -qiE '(>|>>|tee|cp|mv|install)\s+(/etc/|/usr/|/bin/|/sbin/|/sys/|/proc/)'; then
  (( risk += 30 ))
  add_reason "write to system directory"
  add_suggestion "use a user-writable path or a package manager instead"
fi

# ---------------------------------------------------------------------------
# C. Dangerous Flags (+20 each)
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qE '\s--force(\s|$)'; then
  (( risk += 20 ))
  add_reason "--force flag"
  if echo "$cmd" | grep -qE 'git\s+push'; then
    add_suggestion "use 'git push --force-with-lease' to avoid clobbering remote changes"
  else
    add_suggestion "remove --force and confirm the operation manually"
  fi
fi

if echo "$cmd" | grep -qE '\s--no-verify(\s|$)'; then
  (( risk += 20 ))
  add_reason "--no-verify bypasses hooks"
  add_suggestion "fix the underlying hook failure instead of skipping verification"
fi

# ---------------------------------------------------------------------------
# D. Security Threats (+40 each)
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qiE '(curl|wget)(\s+\S+)*\s*\|\s*(bash|sh|zsh|python|node|ruby|perl)'; then
  (( risk += 40 ))
  add_reason "remote code execution via pipe-to-shell"
  add_suggestion "download the script first, inspect it, then execute: curl -O url && cat script.sh && bash script.sh"
fi

if echo "$cmd" | grep -qiE '(base64\s+-d|base64\s+--decode).*\|\s*(bash|sh|python|node)|echo\s+[A-Za-z0-9+/]{20,}.*\|\s*(bash|sh)'; then
  (( risk += 40 ))
  add_reason "base64-encoded command execution (obfuscation)"
  add_suggestion "decode and inspect the payload before executing"
fi

if echo "$cmd" | grep -qiE '(bash|sh|zsh)\s+-i.*(&>|>).*(/dev/tcp|/dev/udp)|nc\s+.*-e\s*(bash|sh)|mkfifo.*nc'; then
  (( risk += 40 ))
  add_reason "reverse shell pattern"
  add_suggestion "do not execute reverse shells; use authorized remote access tools"
fi

if echo "$cmd" | grep -qiE '(^|;|&&|\|\||\s)(metasploit|msfconsole|sqlmap|masscan|hydra|john\s|hashcat|aircrack|nikto|burpsuite)(\s|$)'; then
  (( risk += 40 ))
  add_reason "known exploit/pentest tool"
  add_suggestion "run pentest tools only in authorized, isolated environments"
fi

# ---------------------------------------------------------------------------
# E. Sensitive File Access (+25)
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qiE '(^|\s)(cat|cp|mv|curl|scp|rsync|git\s+add).*\.(env|pem|key|pfx|p12|cer|crt|pkcs12)(\s|$|")'; then
  (( risk += 25 ))
  add_reason "sensitive credential file access"
  add_suggestion "use a secrets manager (Vault, AWS Secrets Manager) instead of file-based secrets"
fi

# ---------------------------------------------------------------------------
# F. Branch Context (+20) — only checked when git is in the command
# ---------------------------------------------------------------------------
if echo "$cmd" | grep -qE '\bgit\b'; then
  branch=$(git -C "$(pwd)" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [[ "$branch" == "main" || "$branch" == "master" || "$branch" == "develop" ]]; then
    (( risk += 20 ))
    add_reason "operating on protected branch '$branch'"
    add_suggestion "create a feature branch: 'git checkout -b feat/<name>'"
  fi
fi

# ---------------------------------------------------------------------------
# Decision + structured JSON output
# ---------------------------------------------------------------------------
if [[ $risk -ge $BLOCK_THRESHOLD ]]; then
  jq -n \
    --argjson risk    "$risk" \
    --arg     reason  "${reasons:-high-risk operation}" \
    --arg     suggestion "${suggestions:-review command before executing}" \
    '{"blocked": true, "risk": $risk, "reason": $reason, "suggestion": $suggestion}'
  exit 1
fi

if [[ $risk -ge $WARN_THRESHOLD ]]; then
  jq -n \
    --argjson risk    "$risk" \
    --arg     warning "${reasons}" \
    '{"blocked": false, "risk": $risk, "warning": $warning}'
  exit 0
fi

# risk < 30 — silent allow
exit 0

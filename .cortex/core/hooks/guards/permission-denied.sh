#!/usr/bin/env bash
# @version: 1.1.1
# PermissionDenied hook — analyzes a denied command, infers the denial reason,
# generates a safe alternative, and decides whether a retry is appropriate.
# Always exits 0; never executes anything.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
cmd=$(echo "$input"             | jq -r '.command // empty' 2>/dev/null)
provided_reason=$(echo "$input" | jq -r '.reason // empty'  2>/dev/null)

[[ -z "$cmd" ]] && exit 0

reason=""
safe_cmd=""
retry=false
message=""

# ---------------------------------------------------------------------------
# Helper — apply a sed transform only if the pattern matches
# Returns 0 and sets safe_cmd if transformation was made, 1 otherwise
# ---------------------------------------------------------------------------
try_transform() {
  local pattern="$1" replacement="$2"
  if echo "$cmd" | grep -qE "$pattern"; then
    safe_cmd=$(echo "$cmd" | sed -E "s|$pattern|$replacement|g")
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# Transformation table — evaluated in priority order
# Each block: sets reason, attempts transform, sets retry + message
# ---------------------------------------------------------------------------

# 1. rm -rf / rm -fr
if echo "$cmd" | grep -qiE 'rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r'; then
  reason="destructive operation: recursive force-delete with no confirmation"
  safe_cmd=$(echo "$cmd" \
    | sed -E 's/rm[[:space:]]+-[a-z]*r[a-z]*f[a-z]*/rm -ri/g' \
    | sed -E 's/rm[[:space:]]+-[a-z]*f[a-z]*r[a-z]*/rm -ri/g')
  retry=true
  message="Replaced 'rm -rf' with 'rm -ri' — prompts before deleting each item."

# 2. git push --force / -f (not --force-with-lease)
elif echo "$cmd" | grep -qE 'git\s+push' && \
     echo "$cmd" | grep -qE '(\s--force\b|\s-f\b)' && \
     ! echo "$cmd" | grep -q 'force-with-lease'; then
  reason="unsafe flag: --force can silently overwrite remote commits"
  safe_cmd=$(echo "$cmd" \
    | sed -E 's/[[:space:]]--force\b/ --force-with-lease/g' \
    | sed -E 's/[[:space:]]-f\b/ --force-with-lease/g')
  retry=true
  message="Replaced '--force' with '--force-with-lease' — aborts if remote has new commits."

# 3. git reset --hard
elif echo "$cmd" | grep -qE 'git\s+reset\s+--hard'; then
  reason="destructive operation: discards all uncommitted changes permanently"
  target=$(echo "$cmd" | grep -oE '[a-f0-9]{5,40}|HEAD[~^][0-9]*|HEAD' | tail -1)
  if [[ -n "$target" ]]; then
    safe_cmd="git stash && git reset --soft $target"
  else
    safe_cmd="git stash"
  fi
  retry=true
  message="Stash changes first, then reset softly — preserves work in the stash stack."

# 4. git clean -f / -fd / -fx
elif echo "$cmd" | grep -qE 'git\s+clean\s+-[a-z]*f'; then
  reason="destructive operation: permanently deletes untracked files"
  safe_cmd=$(echo "$cmd" | sed -E 's/git[[:space:]]+clean[[:space:]]+-[a-z]*/git clean -n/g')
  retry=true
  message="Replaced with 'git clean -n' (dry-run) — preview what would be deleted before committing."

# 5. curl/wget piped to interpreter
elif echo "$cmd" | grep -qiE '(curl|wget)(\s+\S+)*\s*\|\s*(bash|sh|zsh|python[23]?|node|ruby|perl)'; then
  reason="remote execution: pipe-to-shell runs untrusted internet content without inspection"
  dl_tool=$(echo "$cmd" | grep -oiE '(curl|wget)' | head -1)
  url=$(echo "$cmd" | grep -oE 'https?://[^ |]+' | head -1)
  if [[ "$dl_tool" == "wget" ]]; then
    safe_cmd="wget -O /tmp/remote_script.sh '${url}' && cat /tmp/remote_script.sh"
  else
    safe_cmd="curl -fsSL '${url}' -o /tmp/remote_script.sh && cat /tmp/remote_script.sh"
  fi
  retry=false
  message="Download and inspect the script manually before deciding to execute it."

# 6. sudo
elif echo "$cmd" | grep -qE '(^|\s)sudo\s'; then
  reason="privilege escalation: sudo grants unrestricted root access"
  safe_cmd=$(echo "$cmd" | sed -E 's/(^|[;&|]+[[:space:]]*)sudo[[:space:]]+/\1/g')
  # If desudo'd command is empty or same, don't retry
  if [[ "$safe_cmd" == "$cmd" || -z "$(echo "$safe_cmd" | tr -d '[:space:]')" ]]; then
    safe_cmd=""
    retry=false
    message="This operation inherently requires elevated privileges. Evaluate whether it is truly necessary."
  else
    retry=true
    message="Removed 'sudo' — attempt without elevated privileges first."
  fi

# 7. --no-verify
elif echo "$cmd" | grep -qE '\s--no-verify\b'; then
  reason="integrity bypass: --no-verify skips pre-commit hooks and validation checks"
  safe_cmd=$(echo "$cmd" | sed -E 's/[[:space:]]--no-verify\b//g')
  retry=true
  message="Removed '--no-verify' — fix the underlying hook failure instead of bypassing it."

# 8. base64-encoded execution
elif echo "$cmd" | grep -qiE '(base64\s+-d|base64\s+--decode).*\|\s*(bash|sh)|echo\s+[A-Za-z0-9+/]{20,}.*\|\s*(bash|sh)'; then
  reason="remote execution: decoding and running obfuscated payload"
  safe_cmd=$(echo "$cmd" | sed -E 's/\|\s*(bash|sh|zsh)\b/| cat/g')
  retry=false
  message="Decode and inspect the payload with 'base64 -d | cat' before executing."

# 9. Sensitive file access
elif echo "$cmd" | grep -qiE '\.(env|pem|key|pfx|p12|pkcs12)(\s|"|$)'; then
  reason="sensitive data access: credential or private key files should not be read or transmitted"
  safe_cmd=""
  retry=false
  message="Use a secrets manager (Vault, AWS Secrets Manager, env injection at runtime) instead of file-based secrets."

# 10. Exploit / pentest tools
elif echo "$cmd" | grep -qiE '(^|\s)(sqlmap|msfconsole|metasploit|masscan|hydra|john\s|hashcat|aircrack|nikto|burpsuite)\b'; then
  reason="security threat: known exploit or penetration testing tool"
  safe_cmd=""
  retry=false
  message="Pentest tools must only run in authorized, isolated environments with explicit written approval."

# 11. Reverse shells
elif echo "$cmd" | grep -qiE '(bash|sh)\s+-i.*(/dev/tcp|/dev/udp)|nc\s+.*-e\s*(bash|sh)|mkfifo.*nc'; then
  reason="security threat: reverse shell establishes unauthorized remote control"
  safe_cmd=""
  retry=false
  message="Reverse shells are not permitted. Use authorized remote access methods (SSH, approved VPN)."

# 12. Unknown / fallback
else
  reason="${provided_reason:-permission denied by policy}"
  safe_cmd=""
  retry=false
  message="No safe alternative could be determined automatically. Review the command and retry manually."
fi

# Use provided_reason if it was supplied, but keep inferred reason as fallback
[[ -n "$provided_reason" && -z "$reason" ]] && reason="$provided_reason"

# ---------------------------------------------------------------------------
# Build output JSON
# ---------------------------------------------------------------------------
safe_cmd_json="null"
[[ -n "$safe_cmd" ]] && safe_cmd_json=$(jq -n --arg s "$safe_cmd" '$s')

jq -n \
  --argjson retry         "$retry" \
  --arg     originalCommand "$cmd" \
  --argjson safeCommand   "$safe_cmd_json" \
  --arg     reason        "$reason" \
  --arg     message       "$message" \
  '{
    retry:           $retry,
    originalCommand: $originalCommand,
    safeCommand:     $safeCommand,
    reason:          $reason,
    message:         $message
  }'

exit 0

#!/usr/bin/env bash
# @version: 1.1.1
# PermissionRequest hook — analyzes a pending tool execution and outputs a
# structured explanation so the user can make an informed approval decision.
# Never blocks (always exits 0); only enriches the approval prompt.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null)
cmd=$(echo "$input"  | jq -r '.command // empty'   2>/dev/null)

# Fallback: TOOL_NAME env var set by Claude Code
[[ -z "$tool" ]] && tool="${TOOL_NAME:-Bash}"
[[ -z "$cmd"  ]] && exit 0

# ---------------------------------------------------------------------------
# 1. Intent classification
# ---------------------------------------------------------------------------
intent="unknown"

if echo "$cmd" | grep -qiE '(^|\s)(rm|mkdir|cp|mv|touch|cat|ls|find|chmod|chown|ln|tar|zip|unzip|rsync|scp)(\s|$)'; then
  intent="file_operation"
fi
if echo "$cmd" | grep -qE '(^|\s)git(\s|$)'; then
  intent="git_operation"
fi
if echo "$cmd" | grep -qiE '(^|\s)(curl|wget|ssh|nc|ncat|ping|nmap|ftp|sftp|telnet|openssl\s+s_client)(\s|$)'; then
  intent="network_operation"
fi
if echo "$cmd" | grep -qiE '(^|\s)(sudo|su\s|chmod|chown|systemctl|service|mount|umount|iptables|useradd|groupadd|passwd)(\s|$)|(/etc/|/sys/|/proc/|/dev/)'; then
  intent="system_operation"
fi
# git and system can overlap; system_operation takes precedence over git
if echo "$cmd" | grep -qiE '(^|\s)sudo(\s|$)'; then
  intent="system_operation"
fi

# ---------------------------------------------------------------------------
# 2. Explanation
# ---------------------------------------------------------------------------
explanation=""
case "$intent" in
  file_operation)
    if echo "$cmd" | grep -qiE '(^|\s)rm(\s|$)'; then
      explanation="This command removes files or directories from the filesystem."
    elif echo "$cmd" | grep -qiE '(^|\s)(cp|mv)(\s|$)'; then
      explanation="This command copies or moves files, potentially overwriting existing data."
    elif echo "$cmd" | grep -qiE '(^|\s)chmod(\s|$)'; then
      explanation="This command changes file permissions."
    else
      explanation="This command performs a file system operation (read, write, or modify files)."
    fi
    ;;
  git_operation)
    if echo "$cmd" | grep -qE 'git\s+push'; then
      explanation="This command pushes local commits to a remote repository."
    elif echo "$cmd" | grep -qE 'git\s+(reset|revert|clean)'; then
      explanation="This command modifies or discards git history and working tree state."
    elif echo "$cmd" | grep -qE 'git\s+(merge|rebase)'; then
      explanation="This command integrates changes from one branch into another."
    else
      explanation="This command performs a git version-control operation."
    fi
    ;;
  network_operation)
    if echo "$cmd" | grep -qiE '(curl|wget).*\|\s*(bash|sh|python|node)'; then
      explanation="This command downloads a remote script and executes it immediately."
    elif echo "$cmd" | grep -qiE '(^|\s)(curl|wget)(\s|$)'; then
      explanation="This command fetches data from a remote URL."
    elif echo "$cmd" | grep -qiE '(^|\s)ssh(\s|$)'; then
      explanation="This command opens a remote shell session on another machine."
    else
      explanation="This command initiates network communication with an external host."
    fi
    ;;
  system_operation)
    if echo "$cmd" | grep -qiE '(^|\s)sudo(\s|$)'; then
      explanation="This command runs an operation with elevated (administrator) privileges."
    elif echo "$cmd" | grep -qiE '(^|\s)systemctl(\s|$)'; then
      explanation="This command controls a system service (start, stop, restart, or enable)."
    else
      explanation="This command modifies system-level configuration or permissions."
    fi
    ;;
  *)
    explanation="This command performs an operation whose full effect could not be determined automatically."
    ;;
esac

# ---------------------------------------------------------------------------
# 3. Risk detection — build a JSON array of risk strings
# ---------------------------------------------------------------------------
risks=()

# Destructive
echo "$cmd" | grep -qiE '(^|\s)rm\s+-[a-z]*r[a-z]*f|rm\s+-[a-z]*f[a-z]*r' && \
  risks+=("destructive: permanently removes files without confirmation")
echo "$cmd" | grep -qE 'git\s+reset\s+--hard' && \
  risks+=("destructive: discards uncommitted changes and rewrites HEAD")
echo "$cmd" | grep -qE 'git\s+clean\s+-[a-z]*f' && \
  risks+=("destructive: permanently deletes untracked files")
echo "$cmd" | grep -qiE '\b(drop\s+table|truncate\s+table)\b' && \
  risks+=("destructive: removes all rows or an entire database table")

# Privilege escalation
echo "$cmd" | grep -qiE '(^|\s)sudo(\s|$)' && \
  risks+=("privilege escalation: executes with root-level permissions")
echo "$cmd" | grep -qiE '(^|\s)su(\s|$)' && \
  risks+=("privilege escalation: switches to another user account")

# Remote execution
echo "$cmd" | grep -qiE '(curl|wget).*\|\s*(bash|sh|zsh|python|node|ruby|perl)' && \
  risks+=("remote execution: runs untrusted code fetched from the internet")
echo "$cmd" | grep -qiE '(base64\s+-d|base64\s+--decode).*\|\s*(bash|sh)' && \
  risks+=("remote execution: decodes and runs obfuscated command payload")

# Sensitive data
echo "$cmd" | grep -qiE '\.(env|pem|key|pfx|p12|cer|pkcs12)(\s|"|$)' && \
  risks+=("sensitive data: accesses credential or private key files")
echo "$cmd" | grep -qiE '\$(AWS_|GITHUB_TOKEN|PASSWORD|SECRET|TOKEN|API_KEY)' && \
  risks+=("sensitive data: references secrets or API tokens")

# Force flags
echo "$cmd" | grep -qE '\s--force(\s|$)' && \
  risks+=("data loss: --force may overwrite or destroy remote state")
echo "$cmd" | grep -qE '\s--no-verify(\s|$)' && \
  risks+=("integrity: --no-verify skips safety hooks and pre-commit checks")

# Build risks JSON array
risks_json=$(printf '%s\n' "${risks[@]}" | jq -R . | jq -s . 2>/dev/null)
[[ -z "$risks_json" || "$risks_json" == "null" ]] && risks_json='[]'

# ---------------------------------------------------------------------------
# 4. Safer alternatives
# ---------------------------------------------------------------------------
suggestion=""

echo "$cmd" | grep -qiE 'rm\s+-[a-z]*r[a-z]*f' && \
  suggestion="Replace 'rm -rf' with 'rm -ri' to confirm each deletion interactively"

echo "$cmd" | grep -qE 'git\s+push.*--force(\s|$)' && \
  suggestion="Use 'git push --force-with-lease' to avoid overwriting commits others have pushed"

echo "$cmd" | grep -qE 'git\s+reset\s+--hard' && \
  suggestion="Use 'git stash' to save changes before resetting, or 'git reset --soft' to preserve them staged"

echo "$cmd" | grep -qE 'git\s+clean\s+-[a-z]*f' && \
  suggestion="Run 'git clean -n' first to preview which files would be removed"

echo "$cmd" | grep -qiE '(curl|wget).*\|\s*(bash|sh|zsh|python|node)' && \
  suggestion="Download the script first ('curl -O url'), inspect its contents, then execute it"

echo "$cmd" | grep -qiE '(^|\s)sudo(\s|$)' && \
  suggestion="Verify whether elevated privileges are truly required; prefer scoped tools or user-space alternatives"

echo "$cmd" | grep -qE '\s--no-verify(\s|$)' && \
  suggestion="Fix the failing hook instead of bypassing it with --no-verify"

[[ -z "$suggestion" ]] && suggestion="null"

# ---------------------------------------------------------------------------
# 5. Requires confirmation — always true (this hook informs, never auto-approves)
# ---------------------------------------------------------------------------
jq -n \
  --arg  intent               "$intent" \
  --arg  explanation          "$explanation" \
  --argjson risks             "$risks_json" \
  --argjson suggestion        "$([[ $suggestion == null ]] && echo null || echo "\"$suggestion\"")" \
  --argjson requiresConfirmation true \
  '{
    intent:               $intent,
    explanation:          $explanation,
    risks:                $risks,
    suggestion:           $suggestion,
    requiresConfirmation: $requiresConfirmation
  }'

exit 0

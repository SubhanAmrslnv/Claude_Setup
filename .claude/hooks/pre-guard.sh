#!/usr/bin/env bash
# Single PreToolUse guard — one process, one jq parse, all checks in sequence.
# Replaces 8 separate hook scripts.

cmd=$(echo "$TOOL_INPUT" | jq -r '.command // empty')
[[ -z "$cmd" ]] && exit 0

# 1. Dangerous commands
if echo "$cmd" | grep -qiE '(^|;|&&|\|\|)\s*(drop table|rm -rf|truncate)|--force'; then
  echo "BLOCKED: dangerous command detected"
  exit 1
fi

# 2. Force-push to protected branch
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git push.*(--force|-f).*(main|master)|(^|;|&&|\|\|)\s*git push.*(main|master).*(--force|-f)'; then
  echo "BLOCKED: force-push to protected branch"
  exit 1
fi

# 3. Production DB target
if echo "$cmd" | grep -qiE '(^|;|&&|\|\|)\s*[^#]*(prod|production)[_-]?(db|sql|server|conn)'; then
  echo "WARNING: possible production DB target — confirm before proceeding"
  exit 1
fi

# 4. Destructive git operations
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git (reset --hard|clean -f)'; then
  echo "BLOCKED: destructive git operation — run manually if intentional"
  exit 1
fi

# 5. Staging secrets / credentials
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git add.*(\.env|secrets|credentials|\.pem|\.key|\.pfx)'; then
  echo "BLOCKED: staging a secrets or credential file"
  exit 1
fi

# 6 & 7. Git commit checks — only pay the cost of git rev-parse when needed
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git commit'; then
  branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

  # 6. Block direct commit to main/master
  if [[ "$branch" == "main" || "$branch" == "master" ]]; then
    git diff --cached --quiet || { echo "BLOCKED: direct commit to $branch — use a feature branch"; exit 1; }
  fi

  # 7. Enforce conventional commit format
  if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git commit.*-m'; then
    msg=$(echo "$cmd" | grep -oP '(?<=-m ["'"'"'])[^"'"'"']+' | head -1)
    if [[ -n "$msg" ]] && ! echo "$msg" | grep -qE '^(feat|fix|chore|docs|refactor|test|ci|build|perf|style)(\(.+\))?: .+'; then
      echo "BLOCKED: commit message must follow conventional commits — e.g. feat(auth): add JWT refresh"
      exit 1
    fi
  fi
fi

# 9. Reverse shell patterns
if echo "$cmd" | grep -qiE '(bash|sh|zsh)\s+-i.*(&>|>).*(/dev/tcp|/dev/udp)|nc\s+.*-e\s*(bash|sh)|ncat|mkfifo'; then
  echo "BLOCKED: possible reverse shell detected"
  exit 1
fi

# 10. Base64-encoded command execution (obfuscation)
if echo "$cmd" | grep -qiE '(base64\s+-d|base64\s+--decode).*\|\s*(bash|sh|python|node)|echo\s+[A-Za-z0-9+/]{20,}.*\|\s*(bash|sh)'; then
  echo "BLOCKED: encoded command execution detected"
  exit 1
fi

# 11. Writing to cron / shell startup files (persistence)
if echo "$cmd" | grep -qiE '(crontab\s+-|/etc/cron|/etc/init\.d|~/\.bashrc|~/\.zshrc|~/\.profile|~/\.bash_profile).*>>?'; then
  echo "BLOCKED: writing to startup or cron location"
  exit 1
fi

# 12. curl/wget piped directly to interpreter (supply chain)
if echo "$cmd" | grep -qiE '(curl|wget).*\|\s*(bash|sh|python|node|ruby|perl)'; then
  echo "BLOCKED: piping remote content directly to interpreter"
  exit 1
fi

# 13. Credential exfiltration via network tools
if echo "$cmd" | grep -qiE '(curl|wget|nc|ncat).*\$\{?(ANTHROPIC_API_KEY|AWS_|GITHUB_TOKEN|PASSWORD|SECRET|TOKEN)'; then
  echo "BLOCKED: possible credential exfiltration detected"
  exit 1
fi

# 8. Large files >1MB — skip known binary/asset extensions
if echo "$cmd" | grep -qE '(^|;|&&|\|\|)\s*git (add|commit)'; then
  if ! git diff --cached --quiet 2>/dev/null; then
    IGNORED_EXT='(\.dll|\.pdb|\.exe|\.nupkg|\.zip|\.tar\.gz|\.png|\.jpg|\.jpeg|\.gif|\.webp|\.ico|\.svg|\.woff|\.woff2|\.ttf|\.otf|\.eot|\.map|\.mp4|\.mov|\.avi|\.mp3|\.apk|\.ipa|\.aab)$'
    large=$(git diff --cached --name-only \
      | grep -viE "$IGNORED_EXT" \
      | xargs -I{} du -b {} 2>/dev/null \
      | awk '$1 > 1048576 {print $2}')
    [[ -n "$large" ]] && echo "BLOCKED: large file(s) staged (>1MB): $large" && exit 1
  fi
fi
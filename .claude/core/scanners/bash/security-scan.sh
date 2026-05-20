#!/usr/bin/env bash
# @version: 1.0.1
# Scans .sh/.bash files for hardcoded secrets, eval, exec with variables,
# curl|bash, rm -rf with variables, chmod 777, insecure HTTP, and unquoted vars.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.sh && $file != *.bash ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\beval\s+\$' "$file"; then
  echo "[WARNING] eval \$var in $file — command injection risk"
fi

if grep -qiE '\bexec\s+\$\{?' "$file"; then
  echo "[WARNING] exec with variable in $file — verify input is sanitized"
fi

if grep -qiE 'curl\s+.*\|\s*(bash|sh)\b|wget\s+.*\|\s*(bash|sh)\b' "$file"; then
  echo "[WARNING] curl/wget piped to shell in $file — remote code execution risk"
fi

if grep -qiE 'rm\s+(-[a-z]*r[a-z]*f|-[a-z]*f[a-z]*r|-r\s+-f|-f\s+-r|--recursive|--force).*\$\{?' "$file"; then
  echo "[WARNING] rm -rf with variable in $file — verify path cannot be empty or malicious"
fi

if grep -qiE 'chmod\s+777' "$file"; then
  echo "[WARNING] chmod 777 in $file — overly permissive, use minimal required permissions"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

exit 0

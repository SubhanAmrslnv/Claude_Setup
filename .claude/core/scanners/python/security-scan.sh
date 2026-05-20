#!/usr/bin/env bash
# @version: 1.0.1
# Scans .py files for hardcoded secrets, dangerous builtins, unsafe subprocess,
# insecure HTTP, SQL string concatenation, and other common vulnerability patterns.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.py ]] && exit 0

if grep -qiE '(api_key|token|secret|password)\s*=\s*["'"'"'][A-Za-z0-9+/]{8,}' "$file"; then
  echo "[WARNING] possible hardcoded secret in $file — review before committing"
fi

if grep -qiE '\beval\s*\(' "$file"; then
  echo "[WARNING] eval() detected in $file — potential code injection risk"
fi

if grep -qiE '\bexec\s*\(' "$file"; then
  echo "[WARNING] exec() detected in $file — potential code injection risk"
fi

if grep -qiE 'pickle\.loads\s*\(' "$file"; then
  echo "[WARNING] pickle.loads() in $file — unsafe deserialization, never use with untrusted data"
fi

if grep -qiE 'subprocess\.(call|run|Popen).*shell\s*=\s*True' "$file"; then
  echo "[WARNING] subprocess with shell=True in $file — command injection risk"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

# Catch the common SQLi shapes: string concatenation, %-formatting, and
# f-strings inside an execute() call. Previous pattern required two `%` chars
# and never fired on the common single-`%`-format case.
if grep -qiE '\bexecute\s*\(\s*([fbru]*["'"'"'][^"'"'"']*["'"'"']\s*[%+]|f["'"'"'][^"'"'"']*\{|.*\+\s*[a-zA-Z_])' "$file"; then
  echo "[WARNING] possible SQL string interpolation in $file — use parameterized queries"
fi

if grep -qiE '__import__\s*\(' "$file"; then
  echo "[WARNING] __import__() in $file — dynamic import may hide malicious code"
fi

exit 0

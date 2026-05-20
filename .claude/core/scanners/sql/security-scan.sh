#!/usr/bin/env bash
# @version: 1.0.1
# Scans .sql files for SELECT *, unsafe DROP/TRUNCATE, UPDATE/DELETE without WHERE,
# GRANT ALL, hardcoded credentials in connection strings, and insecure HTTP.
# Usage: security-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0
[[ $file != *.sql && $file != *.psql && $file != *.pgsql ]] && exit 0

if grep -qiE '\bSELECT\s+\*\b' "$file"; then
  echo "[WARNING] SELECT * in $file — enumerate columns explicitly for clarity and performance"
fi

if grep -qiE '\bDROP\s+TABLE\b' "$file"; then
  echo "[WARNING] DROP TABLE in $file — ensure this is wrapped in a transaction and intentional"
fi

if grep -qiE '\bTRUNCATE\b' "$file"; then
  echo "[WARNING] TRUNCATE in $file — destructive operation, verify intent"
fi

# Single-statement UPDATE/DELETE that reaches `;` without a WHERE clause.
# Conservative: doesn't try to span multi-line statements (grep can't reliably
# do that without a real parser); over-warns less and avoids the prior false
# positive that fired whenever WHERE was present.
if grep -qiE '^\s*(UPDATE\s+\w+\s+SET\s+[^;]*;|DELETE\s+FROM\s+\w+\s*;)' "$file" && \
   ! grep -qiE '^\s*(UPDATE|DELETE)\b[^;]*\bWHERE\b' "$file"; then
  echo "[WARNING] UPDATE or DELETE without WHERE clause in $file — may affect all rows"
fi

if grep -qiE '\bGRANT\s+ALL\b' "$file"; then
  echo "[WARNING] GRANT ALL in $file — use least-privilege permissions"
fi

if grep -qiE '(password|pwd)\s*=\s*["'"'"'][^"'"'"']{4,}' "$file"; then
  echo "[WARNING] possible hardcoded password in $file — use environment variables or secrets manager"
fi

if grep -qiE 'http://[a-zA-Z]' "$file"; then
  echo "[WARNING] insecure http:// URL in $file — use https://"
fi

exit 0

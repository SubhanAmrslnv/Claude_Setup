#!/usr/bin/env bash
# @version: 1.1.0
# Scans any file for hardcoded secrets and credentials.
# Usage: secret-scan.sh <file_path>

file="$1"
[[ -z "$file" || ! -f "$file" ]] && exit 0

# Generic key=value with a quoted secret-shaped value.
if grep -qiE '(api[_-]?key|secret|password|passwd|token|private[_-]?key|access[_-]?token|client[_-]?secret)\s*[:=]\s*["'"'"'][A-Za-z0-9+/_=.-]{8,}["'"'"']' "$file"; then
  echo "WARNING: possible hardcoded credential in $file — use a secrets manager or env var"
fi

# Vendor-specific high-confidence prefixes (no key=value needed).
if grep -qE '\bAKIA[0-9A-Z]{16}\b' "$file"; then
  echo "WARNING: AWS access key id (AKIA...) found in $file"
fi
if grep -qE '\b(ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{36,}\b' "$file"; then
  echo "WARNING: GitHub personal/OAuth token (gh*_...) found in $file"
fi
if grep -qE '\bxox[abprs]-[A-Za-z0-9-]{10,}\b' "$file"; then
  echo "WARNING: Slack token (xox*-...) found in $file"
fi
if grep -qE '\bsk-[A-Za-z0-9]{20,}\b' "$file"; then
  echo "WARNING: OpenAI/Stripe-style secret key (sk-...) found in $file"
fi
if grep -qE '\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b' "$file"; then
  echo "WARNING: JWT-shaped token found in $file"
fi
if grep -qE -- '-----BEGIN (RSA |EC |OPENSSH |DSA |PGP )?PRIVATE KEY-----' "$file"; then
  echo "WARNING: PEM private key block found in $file"
fi
if grep -qiE 'Authorization\s*:\s*Bearer\s+[A-Za-z0-9._-]{12,}' "$file"; then
  echo "WARNING: hardcoded Authorization: Bearer header in $file"
fi

exit 0

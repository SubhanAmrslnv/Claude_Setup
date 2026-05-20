#!/usr/bin/env bash
# Cortex curl installer.
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/<org>/cortex/main/scripts/install.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/<org>/cortex/main/scripts/install.sh | bash -s -- --ref=branch

set -eu

ref="main"
for arg in "$@"; do
  case "$arg" in
    --ref=*) ref="${arg#*=}" ;;
  esac
done

org="${CORTEX_REPO_ORG:-SubhanAmrslnv}"
repo="${CORTEX_REPO_NAME:-Cortex}"
export CORTEX_REPO_RAW="https://raw.githubusercontent.com/$org/$repo/$ref"
export CORTEX_TARGET="${PWD}"

# Pull the shared core and execute it.
tmp="$(mktemp)"
curl -fsSL "$CORTEX_REPO_RAW/scripts/lib/install-core.sh" -o "$tmp"
bash "$tmp"
rm -f "$tmp"

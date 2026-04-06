#!/usr/bin/env bash
# @version: 1.1.1
# Stop hook — detects project type, runs the build, and reports failures.
# Does NOT auto-fix. On failure: print errors, suggest manual review, exit 1.

set -uo pipefail

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi

detect_build_cmd() {
  if compgen -G "*.sln" > /dev/null 2>&1; then
    echo "dotnet build --nologo -v q"
    return
  fi
  if find . -name "*.csproj" -not -path "*/obj/*" -not -path "*/bin/*" | grep -q .; then
    echo "dotnet build --nologo -v q"
    return
  fi
  if [[ -f package.json ]] && jq -e '.dependencies["react-native"] // .devDependencies["react-native"]' package.json > /dev/null 2>&1; then
    echo "npx react-native build-android"
    return
  fi
  if [[ -f package.json ]] && jq -e '.scripts.build' package.json > /dev/null 2>&1; then
    echo "npm run build"
    return
  fi
}

build_cmd=$(detect_build_cmd)

if [[ -z "${build_cmd:-}" ]]; then
  echo "[build] No recognized project — skipping"
  exit 0
fi

echo "[build] Running: $build_cmd"
build_output=$(bash -c "$build_cmd" 2>&1)
build_exit=$?

if [[ $build_exit -eq 0 ]]; then
  echo "[build] Build succeeded"
  exit 0
fi

echo "[build] Build FAILED — review errors below and fix manually:"
echo "---"
echo "$build_output"
echo "---"
exit 1

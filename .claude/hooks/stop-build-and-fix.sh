#!/usr/bin/env bash
# After Claude finishes, detects the project type and runs the build.
# On failure, prints the error output for manual review.

set -uo pipefail

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
build_output=$(eval "$build_cmd" 2>&1)
build_exit=$?

if [[ $build_exit -eq 0 ]]; then
  echo "[build] Build succeeded"
  exit 0
fi

echo "[build] Build failed — review errors below:"
echo "$build_output"
exit 1

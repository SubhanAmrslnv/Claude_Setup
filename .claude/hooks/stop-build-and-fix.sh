#!/usr/bin/env bash
# After Claude finishes, detects the project type, runs the build,
# and if it fails — calls Claude API (Haiku) to diagnose the error,
# applies the suggested fix commands, then retries the build once.

set -uo pipefail

ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-}"

detect_build_cmd() {
  # .NET — solution file takes priority, then any .csproj (excluding obj/bin)
  if compgen -G "*.sln" > /dev/null 2>&1; then
    echo "dotnet build --nologo -v q"
    return
  fi
  if find . -name "*.csproj" -not -path "*/obj/*" -not -path "*/bin/*" | grep -q .; then
    echo "dotnet build --nologo -v q"
    return
  fi
  # React Native
  if [[ -f package.json ]] && jq -e '.dependencies["react-native"] // .devDependencies["react-native"]' package.json > /dev/null 2>&1; then
    echo "npx react-native build-android"
    return
  fi
  # React / Node — must have a build script
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

echo "[build] Build failed — analyzing error..."

if [[ -z "$ANTHROPIC_API_KEY" ]]; then
  echo "[build] Set ANTHROPIC_API_KEY to enable auto-fix"
  echo "$build_output"
  exit 1
fi

# Gather context: recently changed files (first 100 lines each)
changed_files_content=""
while IFS= read -r file; do
  [[ -f "$file" ]] && changed_files_content+="=== $file ===\n$(head -100 "$file")\n\n"
done < <(git diff --name-only HEAD 2>/dev/null | head -8)

prompt=$(jq -rn \
  --arg cmd "$build_cmd" \
  --arg err "$build_output" \
  --arg files "$changed_files_content" \
  '"You are a build error fixer for .NET (C#) and React / React-Native projects.\n\nA build failed. Output ONLY a JSON array of shell commands that will fix the error.\nRules:\n- No explanation, no markdown, no code fences — raw JSON array only\n- Each element is a single shell command string\n- Prefer safe commands: dotnet restore, npm install <pkg>, sed edits\n- Do NOT include rm -rf, force flags, or commands unrelated to the build error\n\nExample: [\"dotnet restore\", \"npm install missing-package\"]\n\nBuild command: \($cmd)\n\nBuild error:\n\($err)\n\nChanged files (first 100 lines each):\n\($files)"'
)

response=$(curl -s https://api.anthropic.com/v1/messages \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "content-type: application/json" \
  -d "$(jq -n \
    --arg content "$prompt" \
    '{model: "claude-haiku-4-5-20251001", max_tokens: 512, messages: [{role: "user", content: $content}]}'
  )" 2>/dev/null)

fix_json=$(echo "$response" | jq -r '.content[0].text // empty' 2>/dev/null | tr -d '\n' || true)

if [[ -z "$fix_json" ]]; then
  echo "[build] Claude API returned no fix — manual intervention needed"
  echo "$build_output"
  exit 1
fi

BLOCKED_PATTERN='rm -rf|--force|-f |drop |truncate|format [A-Z]:'

echo "[build] Applying fix..."
while IFS= read -r fix_cmd; do
  if echo "$fix_cmd" | grep -qiE "$BLOCKED_PATTERN"; then
    echo "[build] Skipped unsafe command: $fix_cmd"
    continue
  fi
  echo "[build] Fix: $fix_cmd"
  eval "$fix_cmd" 2>&1 || echo "[build] Fix command failed (continuing): $fix_cmd"
done < <(echo "$fix_json" | jq -r '.[]' 2>/dev/null)

echo "[build] Retrying build..."
retry_output=$(eval "$build_cmd" 2>&1)

if [[ $? -eq 0 ]]; then
  echo "[build] Build succeeded after fix"
  exit 0
else
  echo "[build] Build still failing — manual intervention needed:"
  echo "$retry_output"
  exit 1
fi
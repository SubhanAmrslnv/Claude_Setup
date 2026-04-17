#!/usr/bin/env bash
# @version: 1.4.0
# Stop hook — detects project type, runs the build, streams output, reports failures.
# Skips build if project is already running (debug/dev session active).
# Retries up to 3 times before giving up. Does NOT auto-fix.

set -uo pipefail

if [ -z "${CORTEX_ROOT:-}" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi

# Cache csproj discovery — avoids repeated find traversals
_csproj_files=$(find . -name "*.csproj" -not -path "*/obj/*" -not -path "*/bin/*" 2>/dev/null)

detect_build_cmd() {
  # .NET Framework (v4.x): requires VS MSBuild, dotnet CLI lacks WebApplication targets
  if echo "$_csproj_files" | xargs grep -l "<TargetFrameworkVersion>v4" 2>/dev/null | grep -q .; then
    echo "skip:net-framework-project-requires-vs-msbuild"
    return
  fi

  # .NET — solution file takes priority over loose csproj
  if compgen -G "*.sln" > /dev/null 2>&1; then
    echo "dotnet build --nologo -v q"
    return
  fi
  if echo "$_csproj_files" | grep -q .; then
    echo "dotnet build --nologo -v q"
    return
  fi

  # Node — react-native before generic build script
  if [[ -f package.json ]] && jq -e '.dependencies["react-native"] // .devDependencies["react-native"]' package.json > /dev/null 2>&1; then
    echo "npx react-native build-android"
    return
  fi
  if [[ -f package.json ]] && jq -e '.scripts.build' package.json > /dev/null 2>&1; then
    echo "npm run build"
    return
  fi

  # Go
  if [[ -f go.mod ]]; then
    echo "go build ./..."
    return
  fi

  # Rust
  if [[ -f Cargo.toml ]]; then
    echo "cargo build --quiet"
    return
  fi

  # Python — syntax-check all .py files
  if [[ -f requirements.txt || -f pyproject.toml || -f setup.py ]]; then
    py_files=$(find . -name "*.py" -not -path "*/__pycache__/*" -not -path "*/venv/*" -not -path "*/.venv/*" 2>/dev/null | tr '\n' ' ')
    [[ -n "$py_files" ]] && echo "python -m py_compile $py_files" && return
  fi

  # Java — Maven
  if [[ -f pom.xml ]]; then
    echo "mvn -q -DskipTests package"
    return
  fi

  # Java — Gradle
  if [[ -f build.gradle || -f build.gradle.kts ]]; then
    echo "./gradlew build -x test -q"
    return
  fi
}

# Checks if the project's runtime process is already active (debug / dev server running).
# Uses pgrep when available; falls back to ps for Git Bash on Windows.
_proc_match() {
  if command -v pgrep &>/dev/null; then
    pgrep -fi "$1" &>/dev/null
  else
    ps aux 2>/dev/null | grep -i "$1" | grep -qv "grep"
  fi
}

is_project_running() {
  local project_name
  project_name=$(basename "$(pwd)")

  # .NET — dotnet run / watch, or the compiled binary executing
  if echo "$_csproj_files" | grep -q .; then
    _proc_match "dotnet.*(run|watch)" && return 0
    _proc_match "${project_name}\.(exe|dll)" && return 0
  fi

  # Node — dev servers, watchers, or node running a project script
  if [[ -f package.json ]]; then
    _proc_match "nodemon|webpack-dev-server|vite|next dev|expo start|ts-node" && return 0
    _proc_match "node.*${project_name}" && return 0
  fi

  # Go — compiled binary running from this directory
  if [[ -f go.mod ]]; then
    _proc_match "(^|/)${project_name}( |$)" && return 0
  fi

  # Rust — compiled binary running from this directory
  if [[ -f Cargo.toml ]]; then
    _proc_match "(^|/)${project_name}( |$)" && return 0
  fi

  # Python — common WSGI/ASGI servers or dev server
  if [[ -f requirements.txt || -f pyproject.toml || -f setup.py ]]; then
    _proc_match "uvicorn|gunicorn|flask.*run|manage\.py.*runserver|hypercorn" && return 0
  fi

  # Java — jar running or Spring Boot dev server
  if [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]; then
    _proc_match "java.*(${project_name}|spring-boot)" && return 0
  fi

  return 1
}

build_cmd=$(detect_build_cmd)

if [[ -z "${build_cmd:-}" ]]; then
  echo "[build] No recognized project — skipping"
  exit 0
fi

if [[ "$build_cmd" == skip:* ]]; then
  echo "[build] Skipping: ${build_cmd#skip:}"
  exit 0
fi

# Skip build if a dev/debug session is already running
if is_project_running; then
  echo "[build] Project is currently running — skipping build"
  exit 0
fi

# Tool availability check before attempting build
case "$build_cmd" in
  dotnet*)
    if ! command -v dotnet &>/dev/null; then
      echo "[build] dotnet CLI not found — skipping"
      exit 0
    fi
    ;;
  npm*|npx*)
    if ! command -v npm &>/dev/null; then
      echo "[build] npm not found — skipping"
      exit 0
    fi
    ;;
  go\ *)
    if ! command -v go &>/dev/null; then
      echo "[build] go not found — skipping"
      exit 0
    fi
    ;;
  cargo*)
    if ! command -v cargo &>/dev/null; then
      echo "[build] cargo not found — skipping"
      exit 0
    fi
    ;;
  python*)
    if ! command -v python &>/dev/null && ! command -v python3 &>/dev/null; then
      echo "[build] python not found — skipping"
      exit 0
    fi
    ;;
  mvn*)
    if ! command -v mvn &>/dev/null; then
      echo "[build] mvn not found — skipping"
      exit 0
    fi
    ;;
  ./gradlew*)
    if [[ ! -f ./gradlew ]]; then
      echo "[build] gradlew not found — skipping"
      exit 0
    fi
    ;;
esac

# Apply fast-build flag if requested (skips restore/download steps where supported)
if [[ "${CORTEX_FAST_BUILD:-0}" == "1" ]]; then
  case "$build_cmd" in
    dotnet*) build_cmd="$build_cmd --no-restore" ;;
    mvn*)    build_cmd="$build_cmd -o" ;;
  esac
fi

echo "[build] Running:"
echo "--------------------------------"
echo "$build_cmd"
echo "--------------------------------"

tmp_log=$(mktemp)
trap 'rm -f "$tmp_log"' EXIT

MAX_ATTEMPTS=3
attempt=0
build_exit=1

while [[ $attempt -lt $MAX_ATTEMPTS ]]; do
  attempt=$(( attempt + 1 ))
  echo "[build] Attempt $attempt of $MAX_ATTEMPTS"

  set +e
  timeout 120 bash -c "$build_cmd" 2>&1 | tee "$tmp_log"
  build_exit=${PIPESTATUS[0]}
  set -e

  # Timeout
  if [[ $build_exit -eq 124 ]]; then
    echo "[build] Build TIMEOUT after 120s on attempt $attempt" >&2
    [[ $attempt -lt $MAX_ATTEMPTS ]] && echo "[build] Retrying..." && continue
    echo "[build] All $MAX_ATTEMPTS attempts timed out — stopping" >&2
    exit 1
  fi

  if [[ $build_exit -eq 0 ]]; then
    echo "[build] Build succeeded on attempt $attempt"
    exit 0
  fi

  echo "[build] Attempt $attempt failed" >&2
  [[ $attempt -lt $MAX_ATTEMPTS ]] && echo "[build] Retrying..."
done

# All attempts exhausted — summarize errors
build_output=$(cat "$tmp_log")
echo "[build] Build FAILED after $MAX_ATTEMPTS attempts — fix manually, do not auto-patch:" >&2
echo "---" >&2
errors=$(grep -iE "^\s*(error|fail|exception|fatal)" "$tmp_log" 2>/dev/null | head -20)
if [[ -n "$errors" ]]; then
  echo "[build] Key errors:" >&2
  echo "$errors" >&2
  echo "---" >&2
fi
echo "[build] Full output (last attempt):" >&2
echo "$build_output" >&2
echo "---" >&2
exit 1

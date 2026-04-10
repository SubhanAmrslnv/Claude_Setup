#!/usr/bin/env bash
# @version: 1.2.0
# SessionStart initializer — detects project type, extracts metadata,
# writes .cortex/cache/project-profile.json. Idempotent via fingerprint.
# Target: <200ms on typical repos.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null)
[[ -z "$cwd" || ! -d "$cwd" ]] && cwd=$(pwd)

CACHE_DIR="$cwd/.cortex/cache"
PROFILE="$CACHE_DIR/project-profile.json"
mkdir -p "$CACHE_DIR"

# ---------------------------------------------------------------------------
# 1. Single find pass — all project indicator files in one shot
# ---------------------------------------------------------------------------
csproj=""; pkgjson=""; reqstxt=""; pyproject=""
gomod=""; cargotoml=""; pomxml=""; buildgradle=""

while IFS= read -r f; do
  case "${f##*/}" in
    *.csproj)                         [[ -z "$csproj" ]]       && csproj="$f" ;;
    package.json)                     [[ -z "$pkgjson" ]]      && pkgjson="$f" ;;
    requirements.txt)                 [[ -z "$reqstxt" ]]      && reqstxt="$f" ;;
    pyproject.toml)                   [[ -z "$pyproject" ]]    && pyproject="$f" ;;
    go.mod)                           [[ -z "$gomod" ]]        && gomod="$f" ;;
    Cargo.toml)                       [[ -z "$cargotoml" ]]    && cargotoml="$f" ;;
    pom.xml)                          [[ -z "$pomxml" ]]       && pomxml="$f" ;;
    build.gradle|build.gradle.kts)    [[ -z "$buildgradle" ]]  && buildgradle="$f" ;;
  esac
done < <(find "$cwd" -maxdepth 2 \( \
    -name "*.csproj"          -o \
    -name "package.json"      -o \
    -name "requirements.txt"  -o \
    -name "pyproject.toml"    -o \
    -name "go.mod"            -o \
    -name "Cargo.toml"        -o \
    -name "pom.xml"           -o \
    -name "build.gradle"      -o \
    -name "build.gradle.kts"  \
  \) ! -path "*/node_modules/*" 2>/dev/null)

# ---------------------------------------------------------------------------
# 2. Project type detection (last match = highest priority: dotnet > rust > java > node > go > python)
# ---------------------------------------------------------------------------
project_type="unknown"
[[ -n "$reqstxt" || -n "$pyproject" ]]  && project_type="python"
[[ -n "$gomod" ]]                        && project_type="go"
[[ -n "$pkgjson" ]]                      && project_type="node"
[[ -n "$pomxml" || -n "$buildgradle" ]]  && project_type="java"
[[ -n "$cargotoml" ]]                    && project_type="rust"
[[ -n "$csproj" ]]                       && project_type="dotnet"

# ---------------------------------------------------------------------------
# 3. Fingerprint — mtime of all indicator files; skip rewrite if unchanged
# ---------------------------------------------------------------------------
fingerprint_sources=""
for f in "$csproj" "$pkgjson" "$reqstxt" "$pyproject" "$gomod" "$cargotoml" "$pomxml" "$buildgradle"; do
  [[ -f "$f" ]] && fingerprint_sources+=$(stat -c "%Y" "$f" 2>/dev/null || \
    stat -f "%m" "$f" 2>/dev/null)"$f"
done
fingerprint=$(echo "$fingerprint_sources" | cksum | awk '{print $1}')

if [[ -f "$PROFILE" ]]; then
  stored=$(jq -r '.fingerprint // empty' "$PROFILE" 2>/dev/null)
  [[ "$stored" == "$fingerprint" ]] && exit 0
fi

# ---------------------------------------------------------------------------
# 4. Extract metadata per project type
# ---------------------------------------------------------------------------
dependencies_json="[]"
entry_points_json="[]"

case "$project_type" in

  dotnet)
    mapfile -t deps < <(find "$cwd" -maxdepth 3 -name "*.csproj" 2>/dev/null \
      | xargs grep -h 'PackageReference' 2>/dev/null \
      | grep -oP 'Include="\K[^"]+' \
      | sort -u | head -30)
    dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)

    mapfile -t eps < <(find "$cwd" -maxdepth 4 \
      \( -name "Program.cs" -o -name "Startup.cs" -o -name "*Host*.cs" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  node)
    if [[ -f "$pkgjson" ]]; then
      dependencies_json=$(jq -r '
        [(.dependencies // {}), (.devDependencies // {})]
        | add // {}
        | keys
        | .[:30]
      ' "$pkgjson" 2>/dev/null || echo "[]")
    fi

    main_field=$(jq -r '.main // empty' "$pkgjson" 2>/dev/null)
    mapfile -t eps < <(
      { [[ -n "$main_field" ]] && echo "$main_field"; }
      find "$cwd" -maxdepth 2 \
        \( -name "index.js" -o -name "index.ts" -o -name "app.js" \
           -o -name "app.ts" -o -name "server.js" -o -name "server.ts" \
           -o -name "main.ts" -o -name "main.js" \) \
        ! -path "*/node_modules/*" 2>/dev/null \
      | sed "s|$cwd/||"
    )
    mapfile -t eps < <(printf '%s\n' "${eps[@]}" | sort -u | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  python)
    if [[ -f "$reqstxt" ]]; then
      mapfile -t deps < <(grep -v '^\s*#' "$reqstxt" 2>/dev/null \
        | grep -v '^\s*$' \
        | sed 's/[>=<!].*//' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    elif [[ -f "$pyproject" ]]; then
      mapfile -t deps < <(grep -A50 '^\[tool.poetry.dependencies\]\|^\[project\]' \
        "$pyproject" 2>/dev/null \
        | grep -oP '^[a-zA-Z][a-zA-Z0-9_-]+(?=\s*[=<>!])' \
        | grep -iv 'python' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    fi

    mapfile -t eps < <(find "$cwd" -maxdepth 3 \
      \( -name "main.py" -o -name "app.py" -o -name "manage.py" \
         -o -name "wsgi.py" -o -name "asgi.py" -o -name "__main__.py" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  go)
    if [[ -f "$gomod" ]]; then
      mapfile -t deps < <(grep -E '^\s+\S+/\S+\s+v' "$gomod" 2>/dev/null \
        | awk '{print $1}' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    fi

    mapfile -t eps < <(find "$cwd" -maxdepth 4 -name "main.go" 2>/dev/null \
      | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  rust)
    if [[ -f "$cargotoml" ]]; then
      mapfile -t deps < <(sed -n '/^\[dependencies\]/,/^\[/p' "$cargotoml" 2>/dev/null \
        | grep -oE '^[a-zA-Z][a-zA-Z0-9_-]+\s*=' | sed 's/\s*=//' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    fi

    mapfile -t eps < <(find "$cwd" -maxdepth 3 \( -name "main.rs" -o -name "lib.rs" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  java)
    if [[ -f "$pomxml" ]]; then
      mapfile -t deps < <(grep -A3 '<dependency>' "$pomxml" 2>/dev/null \
        | grep '<artifactId>' | grep -oP '<artifactId>\K[^<]+' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    elif [[ -f "$buildgradle" ]]; then
      mapfile -t deps < <(grep -oE \
        "(implementation|api|compile|testImplementation)[[:space:]]*['\"]([^'\"]+)['\"]" \
        "$buildgradle" 2>/dev/null \
        | grep -oE "['\"][^'\"]+['\"]" | tr -d "'\"\(" | grep ':' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    fi

    mapfile -t eps < <(find "$cwd" -maxdepth 5 \
      \( -name "*Application.java" -o -name "Main.java" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

esac

# ---------------------------------------------------------------------------
# 5. Solution structure — notable directories
# ---------------------------------------------------------------------------
KNOWN_DIRS='src|api|app|lib|services|modules|controllers|handlers|middleware'
KNOWN_DIRS+='|tests|test|spec|__tests__|e2e|integration'
KNOWN_DIRS+='|config|configs|settings|scripts|tools|infra|deploy|k8s|docker'

mapfile -t structure < <(
  find "$cwd" -maxdepth 2 -type d \
    ! -path "*/.git/*" ! -path "*/node_modules/*" \
    ! -path "*/bin/*"  ! -path "*/obj/*" \
    ! -path "*/__pycache__/*" ! -path "*/.next/*" \
    ! -path "*/dist/*" ! -path "*/build/*" \
    2>/dev/null \
  | sed "s|$cwd/||" \
  | grep -E "^($KNOWN_DIRS)|/($KNOWN_DIRS)$" \
  | sort -u | head -20
)
structure_json=$(printf '%s\n' "${structure[@]}" | jq -R . | jq -s .)

# ---------------------------------------------------------------------------
# 6. Write profile (atomic: write tmp then move)
# ---------------------------------------------------------------------------
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
tmp_file="$CACHE_DIR/.profile.tmp.$$"

jq -n \
  --arg projectType    "$project_type" \
  --argjson dependencies "$dependencies_json" \
  --argjson entryPoints  "$entry_points_json" \
  --argjson structure    "$structure_json" \
  --arg detectedAt     "$timestamp" \
  --arg fingerprint    "$fingerprint" \
  '{
    projectType:   $projectType,
    dependencies:  $dependencies,
    entryPoints:   $entryPoints,
    structure:     $structure,
    detectedAt:    $detectedAt,
    fingerprint:   $fingerprint
  }' > "$tmp_file" && mv "$tmp_file" "$PROFILE"

# ---------------------------------------------------------------------------
# 7. Prune stale scan caches older than 7 days
# ---------------------------------------------------------------------------
find "$CORTEX_ROOT/cache/scans" -maxdepth 1 -type f -mtime +7 -delete 2>/dev/null

exit 0

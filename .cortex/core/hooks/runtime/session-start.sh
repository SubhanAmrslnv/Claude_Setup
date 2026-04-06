#!/usr/bin/env bash
# @version: 1.1.1
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
# 1. Detect project type (maxdepth 2 for speed; priority: dotnet > node > python)
# ---------------------------------------------------------------------------
csproj=$(find "$cwd" -maxdepth 2 -name "*.csproj" 2>/dev/null | head -1)
pkgjson=$(find "$cwd" -maxdepth 2 -name "package.json" \
  ! -path "*/node_modules/*" 2>/dev/null | head -1)
reqstxt=$(find "$cwd" -maxdepth 2 -name "requirements.txt" 2>/dev/null | head -1)
pyproject=$(find "$cwd" -maxdepth 2 -name "pyproject.toml" 2>/dev/null | head -1)

project_type="unknown"
[[ -n "$reqstxt" || -n "$pyproject" ]] && project_type="python"
[[ -n "$pkgjson" ]]                     && project_type="node"
[[ -n "$csproj" ]]                      && project_type="dotnet"

# ---------------------------------------------------------------------------
# 2. Fingerprint — mtime of indicator files; skip rewrite if unchanged
# ---------------------------------------------------------------------------
fingerprint_sources=""
for f in "$csproj" "$pkgjson" "$reqstxt" "$pyproject"; do
  [[ -f "$f" ]] && fingerprint_sources+=$(stat -c "%Y" "$f" 2>/dev/null || \
    stat -f "%m" "$f" 2>/dev/null)"$f"
done
fingerprint=$(echo "$fingerprint_sources" | cksum | awk '{print $1}')

if [[ -f "$PROFILE" ]]; then
  stored=$(jq -r '.fingerprint // empty' "$PROFILE" 2>/dev/null)
  [[ "$stored" == "$fingerprint" ]] && exit 0
fi

# ---------------------------------------------------------------------------
# 3. Extract metadata per project type
# ---------------------------------------------------------------------------
dependencies_json="[]"
entry_points_json="[]"

case "$project_type" in

  dotnet)
    # Dependencies: <PackageReference Include="Pkg" from all .csproj files
    mapfile -t deps < <(find "$cwd" -maxdepth 3 -name "*.csproj" 2>/dev/null \
      | xargs grep -h 'PackageReference' 2>/dev/null \
      | grep -oP 'Include="\K[^"]+' \
      | sort -u | head -30)
    dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)

    # Entry points: Program.cs, Startup.cs, any *Host*.cs
    mapfile -t eps < <(find "$cwd" -maxdepth 4 \
      \( -name "Program.cs" -o -name "Startup.cs" -o -name "*Host*.cs" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  node)
    # Dependencies: merge dependencies + devDependencies keys
    if [[ -f "$pkgjson" ]]; then
      dependencies_json=$(jq -r '
        [(.dependencies // {}), (.devDependencies // {})]
        | add // {}
        | keys
        | .[:30]
      ' "$pkgjson" 2>/dev/null || echo "[]")
    fi

    # Entry point from package.json "main", then common filenames
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
    # Deduplicate, cap
    mapfile -t eps < <(printf '%s\n' "${eps[@]}" | sort -u | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

  python)
    # Dependencies from requirements.txt
    if [[ -f "$reqstxt" ]]; then
      mapfile -t deps < <(grep -v '^\s*#' "$reqstxt" 2>/dev/null \
        | grep -v '^\s*$' \
        | sed 's/[>=<!].*//' \
        | tr '[:upper:]' '[:lower:]' \
        | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    elif [[ -f "$pyproject" ]]; then
      # pyproject.toml: extract [tool.poetry.dependencies] or [project] dependencies
      mapfile -t deps < <(grep -A50 '^\[tool.poetry.dependencies\]\|^\[project\]' \
        "$pyproject" 2>/dev/null \
        | grep -oP '^[a-zA-Z][a-zA-Z0-9_-]+(?=\s*[=<>!])' \
        | grep -iv 'python' | sort -u | head -30)
      dependencies_json=$(printf '%s\n' "${deps[@]}" | jq -R . | jq -s .)
    fi

    # Entry points: main.py, app.py, manage.py, wsgi.py, asgi.py, __main__.py
    mapfile -t eps < <(find "$cwd" -maxdepth 3 \
      \( -name "main.py" -o -name "app.py" -o -name "manage.py" \
         -o -name "wsgi.py" -o -name "asgi.py" -o -name "__main__.py" \) \
      2>/dev/null | sed "s|$cwd/||" | head -10)
    entry_points_json=$(printf '%s\n' "${eps[@]}" | jq -R . | jq -s .)
    ;;

esac

# ---------------------------------------------------------------------------
# 4. Solution structure — notable top-level and second-level directories
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
# 5. Write profile (atomic: write tmp then move)
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

exit 0

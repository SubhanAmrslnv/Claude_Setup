#!/usr/bin/env bash
# Shared installer core — used by scripts/install.sh and bin/cortex (init).
#
# Required env:
#   CORTEX_REPO_RAW   e.g. https://raw.githubusercontent.com/<org>/cortex/main
#   CORTEX_TARGET     destination project root (defaults to $PWD)
#
# Detects languages in the target, downloads:
#   - skeleton (.claude/{settings.json,registry/*,config/*,core/shared,core/events,
#                        core/hooks,core/planner,core/router,core/memory,
#                        core/debug,project/memory/*})
#   - scanners only for detected languages + generic
# Idempotent: re-running upgrades in place.

set -eu

: "${CORTEX_REPO_RAW:?CORTEX_REPO_RAW is required}"
target="${CORTEX_TARGET:-$PWD}"
mkdir -p "$target/.claude"

say() { printf "[cortex] %s\n" "$*"; }

fetch() {
  local rel="$1" dst="$target/.claude/$1"
  mkdir -p "$(dirname "$dst")"
  curl -fsSL "$CORTEX_REPO_RAW/.claude/$rel" -o "$dst"
}

# ── Language detection ──────────────────────────────────────────────────────
langs=("generic")
[[ -f "$target/package.json" ]]                                            && langs+=("node")
compgen -G "$target/*.csproj" >/dev/null 2>&1                              && langs+=("dotnet")
compgen -G "$target/*.sln" >/dev/null 2>&1                                 && langs+=("dotnet")
[[ -f "$target/go.mod" ]]                                                  && langs+=("go")
[[ -f "$target/Cargo.toml" ]]                                              && langs+=("rust")
[[ -f "$target/pyproject.toml" || -f "$target/requirements.txt" || -f "$target/setup.py" ]] && langs+=("python")
[[ -f "$target/pom.xml" || -f "$target/build.gradle" || -f "$target/build.gradle.kts" ]]   && langs+=("java")
compgen -G "$target/Dockerfile*" >/dev/null 2>&1                           && langs+=("docker")
compgen -G "$target/*.tf" >/dev/null 2>&1                                  && langs+=("terraform")
compgen -G "$target/*.sh" >/dev/null 2>&1                                  && langs+=("bash")

# dedupe
langs=( $(printf "%s\n" "${langs[@]}" | awk '!seen[$0]++') )
say "detected languages: ${langs[*]}"

# ── Skeleton fetch ──────────────────────────────────────────────────────────
skeleton=(
  "settings.json"
  "registry/hooks.json"
  "registry/commands.json"
  "registry/scanners.json"
  "config/cortex.config.json"
  "core/shared/bootstrap.sh"
  "core/events/bus.sh"
  "core/events/dispatcher.sh"
  "core/events/subscriptions.json"
  "core/hooks/guards/pre-guard.sh"
  "core/hooks/guards/permission-request.sh"
  "core/hooks/guards/permission-denied.sh"
  "core/hooks/runtime/prompt-router.sh"
  "core/hooks/runtime/post-format.sh"
  "core/hooks/runtime/post-scan.sh"
  "core/hooks/runtime/post-error-analyzer.sh"
  "core/hooks/runtime/stop-build.sh"
  "core/planner/planner-engine.sh"
  "core/planner/task-graph.sh"
  "core/planner/worker-pool.sh"
  "core/planner/merge-engine.sh"
  "core/router/model-router.sh"
  "core/memory/index.sh"
  "core/memory/retrieve.sh"
  "core/debug/runtime-monitor.sh"
  "core/debug/process-inspector.sh"
  "core/debug/log-stream.sh"
  "core/debug/build-watcher.sh"
  "core/debug/test-replay.sh"
  "core/debug/network-trace.sh"
  "core/debug/browser-trace.sh"
  "core/statusline/render.sh"
  "commands/debug.md"
  "commands/commit.md"
  "project/memory/session.json"
  "project/memory/architecture.json"
  "project/memory/debug.json"
  "project/memory/workflow.json"
)
for f in "${skeleton[@]}"; do
  fetch "$f"
done

# ── Scanners (language-aware) ───────────────────────────────────────────────
# scanners.json maps extensions → scripts. We fetch only the directories whose
# names appear in $langs.
say "fetching scanners: ${langs[*]}"
tmp_scan="$(mktemp)"; trap 'rm -f "$tmp_scan"' EXIT
curl -fsSL "$CORTEX_REPO_RAW/.claude/registry/scanners.json" -o "$tmp_scan"
mapfile -t scripts < <(jq -r '[.[][]] | unique[]' "$tmp_scan" 2>/dev/null)
for s in "${scripts[@]}"; do
  lang="${s%%/*}"
  for keep in "${langs[@]}"; do
    if [[ "$lang" == "$keep" ]]; then
      fetch "core/scanners/$s"
      break
    fi
  done
done

# ── Make hooks executable (POSIX systems) ───────────────────────────────────
chmod +x "$target/.claude"/core/{shared,events,hooks/guards,hooks/runtime,planner,router,memory,debug}/*.sh 2>/dev/null || true
chmod +x "$target/.claude"/core/scanners/**/*.sh 2>/dev/null || true

# ── Local-only state dirs ───────────────────────────────────────────────────
mkdir -p "$target/.claude"/{cache,logs,temp/events,state}

say "Cortex installed at $target/.claude (languages: ${langs[*]})"
say "Next: open Claude Code in this project and run /init-cortex"

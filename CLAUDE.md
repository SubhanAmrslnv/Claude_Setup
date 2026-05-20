# CLAUDE.md

Guidance for Claude Code working in this repository.

This repo is **Cortex** — an event-driven, project-local AI runtime framework for Claude Code. No application code; everything is shell scripts, JSON config, and this file. Cortex runs exclusively from each project's own `.claude/` directory. There is **no global install**.

---

## Repository Layout

```
CLAUDE.md
README.md
INSTALL.md
package.json                                ← npm CLI metadata
bin/cortex                                  ← Node CLI (init / update / doctor)
scripts/
  install.sh                                ← curl installer (Linux/macOS/Git Bash)
  install.ps1                               ← curl installer (Windows)
  lib/install-core.sh                       ← shared installer core
.claude/
  settings.json                             ← thin hook wirings
  commands/
    init-cortex.md
    update-cortex.md
    debug.md                                ← runtime-aware
    commit.md
  core/
    shared/bootstrap.sh                     ← CORTEX_ROOT, publish_event(), config
    hooks/
      guards/
        pre-guard.sh                        ← PreToolUse risk score (v2.4.0)
        permission-request.sh               ← PermissionRequest enricher (v1.3.0)
        permission-denied.sh                ← PermissionDenied recovery   (v1.3.0)
      runtime/
        prompt-router.sh                    ← UserPromptSubmit (v1.0.0) — intent only
        post-format.sh                      ← FileChanged subscriber       (v2.5.0)
        post-scan.sh                        ← FileChanged subscriber       (v2.7.0)
        post-error-analyzer.sh              ← PostToolUseFailure           (v1.2.0)
        stop-build.sh                       ← Stop                         (v1.5.0)
    events/
      bus.sh                                ← publish / dispatch entrypoint
      dispatcher.sh                         ← drains queue, parallel fanout
      subscriptions.json                    ← event-name → handler[]
    planner/
      planner-engine.sh                     ← build + run intent DAGs
      task-graph.sh                         ← topo frontier + cycle check
      worker-pool.sh                        ← bounded parallel runner
      merge-engine.sh                       ← merges worker outputs
    router/model-router.sh                  ← intent → haiku|sonnet|opus
    memory/
      index.sh                              ← lazy file index
      retrieve.sh                           ← grep-scored top-N retrieval
    debug/
      runtime-monitor.sh                    ← orchestrates the debug DAG
      process-inspector.sh                  ← listening ports + processes
      log-stream.sh                         ← tail + classify project logs
      build-watcher.sh                      ← run build, classify output
      test-replay.sh                        ← run tests, classify failures
      network-trace.sh                      ← synthetic HTTP probe
      browser-trace.sh                      ← HAR parse (if dropped under temp/har)
    scanners/<language>/                    ← installed selectively at install time
  project/memory/                           ← lazy retrieval state (4 JSON stubs)
  registry/
    hooks.json   commands.json   scanners.json
  config/cortex.config.json                 ← v4.0.0
  cache/    logs/    state/    temp/events/
```

**Separation of concerns:**
- `hooks/guards/` — pre/permission events; never mutate, may block
- `hooks/runtime/` — post-event execution; the file-write hook publishes one event and exits
- `events/` — pub/sub plumbing
- `planner/` — DAG construction + parallel execution
- `router/` — advisory model selection
- `memory/` — lazy retrieval
- `debug/` — runtime probes (also act as event subscribers)
- `scanners/` — registry-driven analysis
- `commands/` — orchestration only

---

## CORTEX_ROOT Resolution

Strictly project-local. Resolution:
1. `$CORTEX_ROOT` (CI/Docker override)
2. `$(pwd)/.claude`

If `.claude/` is missing at the project root, every hook exits 0 with a single-line diagnostic. There is **no `$HOME` fallback**.

Every hook sources the shared bootstrap:
```bash
source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```
`bootstrap.sh` exports `CORTEX_CACHE`, `CORTEX_LOGS`, `CORTEX_TEMP`, `CORTEX_STATE`, `CORTEX_EVENTS`, `CORTEX_CONFIG`, defines `cortex_config()`, and exposes `publish_event()`.

---

## Status Line

`.claude/core/statusline/render.sh` is wired to Claude Code's `statusLine`. Every turn, Claude Code pipes the session JSON to the script and renders its stdout under the chatbox. The dashboard is Cortex-native — every value is a live read against on-disk state, no fabricated defaults:

- **Model + elapsed + context % + permission mode** — from the session JSON on stdin
- **Cortex version** — `.claude/config/cortex.config.json → version`
- **Hooks deployed/total** — for each `source` in `.claude/registry/hooks.json`, an `[[ -f ]]` existence check
- **Commands deployed/total** — for each name in `.claude/registry/commands.json`, checks `.claude/commands/<name>.md`
- **Scanners** — count of unique scripts in `.claude/registry/scanners.json`
- **Risk** — `riskThresholds.warn / riskThresholds.block` from `cortex.config.json`
- **Memory** — `du -sk .claude/project/memory`
- **Events pending** — `find .claude/temp/events -name '*.json'` (queue depth)
- **Indexed** — line count of `.claude/cache/file-index.txt`
- **Audit** — line count of `.claude/logs/audit.log`
- **Tests** — `find` matching `*.test.*`, `*.spec.*`, `test_*.py`, `*_test.go`, `*Tests.cs`; cases via `grep -cE` for `it(`, `test(`, `describe(`, `def test_`, `func Test`, `[Fact]`, etc.
- **Git** — current branch, `+N` untracked, `~N` modified

Hard rules: never fail loudly (a single-line fallback is emitted on any error), exit 0 always, no writes to disk. Bootstraps via the shared `bootstrap.sh`.

---

## Hook Surface

| Event                          | Wired to                                            | Notes                                          |
|--------------------------------|-----------------------------------------------------|------------------------------------------------|
| `PreToolUse` (Bash)            | `guards/pre-guard.sh`                               | 6-category risk score; warn/block thresholds   |
| `PermissionRequest`            | `guards/permission-request.sh`                      | Intent + risks + alternative                   |
| `PermissionDenied`             | `guards/permission-denied.sh`                       | Safe-alternative generator                     |
| `UserPromptSubmit`             | `runtime/prompt-router.sh`                          | Intent label only; passes prompt through       |
| `PostToolUse` (Write\|Edit)    | `events/bus.sh publish FileChanged`                 | Async fanout via dispatcher                    |
| `PostToolUseFailure`           | `runtime/post-error-analyzer.sh`                    | Error classification                           |
| `Stop`                         | `runtime/stop-build.sh`                             | Build retry                                    |

**No `SessionStart` hook exists.** The previous session-start.sh and prompt-optimizer.sh are removed. Cortex does not preload project context.

---

## Event Bus

Events are JSON files dropped under `.claude/temp/events/`. `bus.sh publish <event-name> [json-payload]` writes one and kicks `dispatcher.sh` asynchronously. The dispatcher uses a non-blocking `flock`, reads `core/events/subscriptions.json`, and fans subscribers out in parallel (cap: `eventBus.maxJobs`, default 4). Consumed events are deleted.

Defined events: `FileChanged`, `BuildFailed`, `TestFailed`, `DebugStarted`, `SessionStopped`, `TaskCompleted`.

---

## Planner + Parallelism

`planner-engine.sh build <intent>` emits a DAG JSON:
```json
{ "tasks": { "id": { "handler": "debug/probe.sh", "args": "", "depends_on": [] } } }
```
`worker-pool.sh run <dag> <out>` runs the topological frontier in parallel (cap: `planner.maxJobs`), retries failed tasks once, writes one stdout per task, and exits non-zero on permanent failures. `merge-engine.sh <out>` produces a final bundle:
```json
{ "status": "OK|PARTIAL|FAIL", "completed": [...], "failed": [...], "results": { "<id>": ... } }
```

`/debug` uses the `debug` intent: a 5-probe DAG (`inspect-process`, `tail-logs`, `run-build`, `replay-tests`, `curl-endpoint`) with no dependencies — full parallelism.

---

## Memory (Lazy, Retrieval-Based)

`core/memory/retrieve.sh <intent> <query>` is the only entrypoint. It:
1. Calls `index.sh ensure` (builds the index only if missing or older than `memory.indexMaxAgeSeconds`).
2. Scores files: path keyword (+3), basename keyword (+5), intent-layer match (+2), git-changed in last 5 commits (+4).
3. Emits ≤5 files with a 3-line structural summary each.

No embeddings, no API calls, no preload. Project memory lives in `.claude/project/memory/`: `session.json`, `architecture.json`, `debug.json`, `workflow.json`, plus a `plans/` directory and `plans.json` index.

**Plan memory.** Every time Claude Code writes a plan file (under any `*/plans/*.md` path — including the user-global `~/.claude/plans/`), the `FileChanged` event fires `core/memory/plans-watcher.sh`, which calls `core/memory/plans.sh save <file>`. The plan is copied into `.claude/project/memory/plans/<slug>.md` with frontmatter (slug, saved_at, source, title, intent) and the index file `plans.json` is upserted. Plans persist across Claude Code sessions in the same project.

Available subcommands:
- `bash core/memory/plans.sh save <file>` — manual capture
- `bash core/memory/plans.sh list` — list saved plans (newest first)
- `bash core/memory/plans.sh get <slug>` — print one saved plan
- `bash core/memory/plans.sh search <query>` — keyword search across saved plans
- `bash core/memory/plans.sh prune <days>` — drop plans older than N days

`debug.json` is auto-appended by `/debug` on RESOLVED.

---

## Model Router (Advisory)

`core/router/model-router.sh [intent]` reads `cortex.config.json → modelPolicy`. Defaults:

| Intent      | Tier   |
|-------------|--------|
| question    | haiku  |
| commit      | haiku  |
| bug_fix     | sonnet |
| refactor    | sonnet |
| debug       | sonnet |
| feature     | sonnet |
| migration   | opus   |
| _(default)_ | haiku  |

`model-router.sh escalate <tier>` returns the next tier. Opus is terminal. The router is advisory; Claude Code's actual model is set by the user.

---

## Commands

In-Claude slash commands (kept minimal):

| Command   | Purpose                                                                            |
|-----------|-------------------------------------------------------------------------------------|
| `/debug`  | Runtime-aware self-healing debugger (5 parallel probes + retrieve + patch loop).    |
| `/commit` | Conventional commit; branch routing; no Claude attribution.                         |

**Install / update / validate is handled by `npx @cortex/cli`** — not by slash commands. The previous `/init-cortex` and `/update-cortex` slash commands have been removed. Use:

```bash
npx @cortex/cli init      # install + validate .claude/ in the current project
npx @cortex/cli update    # re-fetch + re-validate
npx @cortex/cli doctor    # local sanity check (no network)
```

The analyzer commands (`/doctor`, `/hotspot`, `/impact`, `/timeline`, `/optimize`, `/overengineering-check`, `/pr-check`, `/regression`, `/pattern-drift`, `/documentation`) were removed in the vNext redesign.

---

## Working in This Repo

### Editing a hook
1. Edit the source file under `.claude/core/hooks/` or `.claude/core/`.
2. Bump `# @version: X.Y.Z` (line 2) and the matching entry in `.claude/registry/hooks.json`.
3. Test by piping a sample JSON payload to the script via stdin.

### Adding a subscriber
1. Drop the script under `.claude/core/<area>/`.
2. Add it to `.claude/core/events/subscriptions.json` under the relevant event name.
3. No `settings.json` change needed.

### Adding a planner-runnable task
1. Drop the script under `.claude/core/<area>/`; it must emit JSON on stdout, exit 0 on success, non-zero on failure.
2. Reference it from `planner-engine.sh` (a new intent's DAG, or by extending an existing one).

### Adding a scanner
1. Drop the script under `.claude/core/scanners/<language>/`.
2. Add the extension → script mapping to `.claude/registry/scanners.json`.
3. Update the installer's language detection (if it's a new language).

### Adding a command
1. Create `<name>.md` under `.claude/commands/`.
2. Append the name to `.claude/registry/commands.json`.

### Conventional commits (enforced by `pre-guard.sh`)
Format: `type(scope): message`. Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `style`, `perf`. No Claude/Anthropic attribution. No `🤖` emoji.

### Branch protection
Never commit or push directly to `main`, `master`, or `develop`. Always work on a feature branch and open a PR.

---

## Efficiency Rules

- Read only files directly relevant to the task; lean on `core/memory/retrieve.sh` instead of broad reads.
- Batch independent tool calls in one message.
- Use `Grep`/`Glob` over `ls`/`find`.
- Prefer `Edit` over `Write` for existing files.
- Lead with the action — no preamble, no trailing summaries.

---

## Response Format & Tone

- Direct and concise — one sentence beats three.
- Technical depth expected; do not over-explain basics.
- Call out security or correctness risks when present.
- No boilerplate filler.

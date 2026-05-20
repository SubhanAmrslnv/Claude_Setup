# Cortex

An ultra-fast, event-driven, project-local AI runtime framework for [Claude Code](https://claude.ai/code).

Cortex is hook-driven, registry-extensible, and strictly local: it lives entirely under each project's `.claude/` directory — no global install, no startup profiling, no automatic prompt injection. Heavy work runs on demand, in parallel.

---

## Installation

### One-liner (curl)
```bash
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash
```

### Windows (PowerShell)
```powershell
iwr -useb https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.ps1 | iex
```

### npm / npx
```bash
npx @cortex/cli init
```

All three paths run the same installer core. They detect the project's language(s), fetch only the matching scanners + `generic`, and write a complete `.claude/` skeleton into the current directory.

**Prerequisites:** `bash 4+`, `jq`, `git`, Node 18+ (npm path only).

---

## Architecture

```
.claude/
  settings.json                       hook wirings — minimal, event-driven
  commands/                           init-cortex, update-cortex, debug, commit
  core/
    shared/bootstrap.sh               CORTEX_ROOT resolution, publish_event()
    hooks/
      guards/{pre-guard,permission-request,permission-denied}.sh
      runtime/{prompt-router,post-format,post-scan,post-error-analyzer,stop-build}.sh
    events/{bus,dispatcher,subscriptions.json}     publish/subscribe over file queue
    planner/{planner-engine,task-graph,worker-pool,merge-engine}.sh   parallel DAGs
    router/model-router.sh            advisory haiku/sonnet/opus selection
    memory/{index,retrieve}.sh        lazy, grep-based retrieval (no embeddings)
    debug/{runtime-monitor,process-inspector,log-stream,build-watcher,
           test-replay,network-trace,browser-trace}.sh                runtime probes
    scanners/<language>/              language-aware, installed selectively
  project/memory/                     session, architecture, debug, workflow
  registry/{hooks,commands,scanners}.json
  config/cortex.config.json
  cache/   logs/   state/   temp/events/
```

**Strictly project-local.** Bootstrap resolves `CORTEX_ROOT` to `$(pwd)/.claude` only — no `$HOME` fallback.

---

## Status Line

A multi-line project dashboard renders under the chatbox every turn (`core/statusline/render.sh`). Shows model + elapsed time, DDD domains, swarm agents, hook count, CVEs, memory size, context %, ADRs, AgentDB vectors, MCP server health, and the current permission mode. Safe-fail: never crashes Claude Code's render loop.

---

## Hooks

| Event                          | Hook                                          |
|--------------------------------|-----------------------------------------------|
| `statusLine`                   | `core/statusline/render.sh` — project dashboard rendered under the chatbox |
| `PreToolUse` (Bash)            | `guards/pre-guard.sh` — 6-category risk score |
| `PermissionRequest`            | `guards/permission-request.sh`                |
| `PermissionDenied`             | `guards/permission-denied.sh`                 |
| `UserPromptSubmit`             | `runtime/prompt-router.sh` — intent only      |
| `PostToolUse` (Write\|Edit)    | `events/bus.sh publish FileChanged`           |
| `PostToolUseFailure`           | `runtime/post-error-analyzer.sh`              |
| `Stop`                         | `runtime/stop-build.sh`                       |

**There is no `SessionStart` hook.** Cortex does not profile the project at startup. The previous prompt-optimizer is gone — `prompt-router.sh` only labels the intent and passes the prompt through.

---

## Event Bus

The `FileChanged` hook does **not** run formatters and scanners synchronously. It publishes one event to `.claude/temp/events/` and exits. `dispatcher.sh` fans subscribers (`post-format.sh`, `post-scan.sh`) out in parallel, capped by `eventBus.maxJobs` in config.

Add a new subscription by editing `.claude/core/events/subscriptions.json`:
```json
{ "FileChanged": ["hooks/runtime/post-format.sh", "hooks/runtime/post-scan.sh"] }
```

Defined events: `FileChanged`, `BuildFailed`, `TestFailed`, `DebugStarted`, `SessionStopped`, `TaskCompleted`.

---

## Planner

`planner-engine.sh build <intent>` emits a JSON DAG. `worker-pool.sh run <dag> <out-dir>` executes the frontier in parallel (cap: `planner.maxJobs`), retries failed tasks once, and writes one result file per task. `merge-engine.sh <out-dir>` produces a single bundle:
```json
{ "status": "OK|PARTIAL|FAIL", "completed": [...], "failed": [...], "results": { ... } }
```

The `/debug` flow uses `planner-engine.sh plan-and-run debug` to fan five runtime probes out at once.

---

## Memory

`core/memory/retrieve.sh <intent> <query>` scores files against the query (path / basename keyword hits, intent-layer match, git-recency boost) and returns at most 5 paths with a one-line structural summary each.

The file index is built lazily by `core/memory/index.sh ensure` — never on session start, only when memory is queried for the first time (or the index is older than `memory.indexMaxAgeSeconds`).

Memory files (`.claude/project/memory/`):
- `session.json` — turn-scoped state
- `architecture.json` — lazy module summaries
- `debug.json` — known/resolved failures, appended by `/debug`
- `workflow.json` — commit-style vocabulary

No embeddings, no API calls, no preload.

---

## Model Router

`core/router/model-router.sh [intent]` reads `cortex.config.json → modelPolicy` and emits `haiku | sonnet | opus`. The router is advisory; Claude Code's active model is set by the user.

**32-intent taxonomy** — full table in `cortex.config.json → modelPolicy.intents`:

| Tier   | Count | Examples |
|--------|-------|----------|
| haiku  | 10    | `question`, `explain_code`, `commit_message`, `format_code`, `rename`, `typo_fix`, `docstring`, `boilerplate`, `unit_test_simple`, `bug_fix_trivial` |
| sonnet | 12    | `code_review_light`, `bug_fix`, `refactor`, `debug`, `feature_small`, `unit_test_complex`, `integration_test`, `api_design`, `query_optimization`, `dependency_upgrade`, `documentation`, `migration_trivial` |
| opus   | 10    | `feature_large`, `architecture`, `migration_schema`, `migration_framework`, `security_review`, `performance_audit`, `incident_rca`, `code_review_deep`, `multi_repo_change`, `legacy_modernization` |

**Default tier is `sonnet`** — under-tiering is the bigger risk than over-tiering for real dev work. Haiku-tier intents only trigger when the prompt explicitly signals triviality (`typo`, `trivial`, `pure function`, etc.). Opus-tier intents need explicit signals (`security review`, `architecture`, `incident`, `schema migration`, `framework upgrade`, `deep review`, `cross-cutting feature`, `multi-repo`).

Escalation: `model-router.sh escalate <tier>` returns the next tier (haiku → sonnet → opus; opus is terminal). Invoked only when a lower tier returns `STATUS=INSUFFICIENT`.

---

## Commands

In-Claude slash commands:

| Command   | Purpose                                                          |
|-----------|------------------------------------------------------------------|
| `/debug`  | Runtime-aware debugging: 5 parallel probes + self-healing loop.  |
| `/commit` | Conventional commit with branch routing.                         |

Install / update / validate live in the **npx CLI** rather than as slash commands:
```bash
npx @cortex/cli init      # install + validate
npx @cortex/cli update    # re-fetch + re-validate
npx @cortex/cli doctor    # local sanity check
```

The earlier analyzer commands and the `/init-cortex` / `/update-cortex` slash commands were removed in the vNext redesign. Their work folds into `/debug` evidence, the npx CLI, or is performed ad-hoc by the model.

---

## CLI

The CLI is the **canonical bootstrap** — there are no in-Claude `init` or `update` commands.

```bash
npx @cortex/cli init       # install + validate .claude/ in the current project
npx @cortex/cli update     # re-fetch + re-validate (idempotent)
npx @cortex/cli doctor     # local sanity check (no network)
npx @cortex/cli --version
```

`init` and `update` both:
1. Detect the project's languages.
2. Download the matching skeleton + scanners from GitHub raw.
3. Validate the registry against the filesystem (hooks present, commands present, settings wired).
4. Prune stale scanner directories that aren't in the active language set.
5. Create local-only directories (`cache/`, `logs/`, `temp/events/`, `state/`, `project/memory/`).

`doctor` runs steps 3–5 in **check-only** mode (no scanner deletion, no installer).

---

## Configuration

`.claude/config/cortex.config.json`:
```json
{
  "version": "4.0.0",
  "riskThresholds":  { "warn": 30, "block": 70 },
  "modelPolicy":     { "default": "sonnet", "intents": { ... 32 keys ... }, "escalation": ["haiku","sonnet","opus"] },
  "eventBus":        { "maxJobs": 4 },
  "planner":         { "maxJobs": 4 },
  "memory":          { "indexMaxAgeSeconds": 3600 },
  "debug":           { "expectedPorts": [...], "logPaths": [...] },
  "cache":           { "scanTtlDays": 30 }
}
```

---

## Performance Targets

| Metric                        | Target            |
|-------------------------------|-------------------|
| Hook overhead (UserPromptSubmit) | < 50 ms        |
| `bus.sh publish` latency       | < 30 ms          |
| Startup cost                   | 0 ms (no SessionStart) |
| Parallel debug probes          | ≤ planner.maxJobs |
| Memory retrieval (5 files)     | < 200 ms          |

---

## Branch Protection

Never commit or push directly to `main`, `master`, or `develop`. Always work on a feature branch and open a PR.

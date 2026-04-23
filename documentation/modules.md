# Modules

## Top-level structure

| Path | Type | Responsibility |
|---|---|---|
| `.claude/` | Directory | Framework root — all hook scripts, scanners, commands, registry, state, and Claude Code adapter |
| `CLAUDE.md` | File | Authoritative architecture guide; loaded every Claude Code session |
| `README.md` | File | Public-facing project description and quick-start |
| `INSTALL.md` | File | Step-by-step installation guide |
| `documentation/` | Directory | Generated documentation (this folder) |

---

## Module deep-dives

### `.claude/core/hooks/guards/`

**What lives here:** Three guard hook scripts: `pre-guard.sh`, `permission-request.sh`, `permission-denied.sh`.

**Responsible for:** Gate logic only. `pre-guard.sh` scores every Bash command and blocks or warns based on risk threshold. `permission-request.sh` enriches approval prompts with intent classification and risk list. `permission-denied.sh` generates safe alternatives after a denial.

**Not responsible for:** Scanning file contents, logging, formatting, or any post-execution analysis.

**Files of note:** `pre-guard.sh` (v2.3.0) — the primary risk-scoring engine; every change here directly affects what Claude is allowed to execute.

---

### `.claude/core/hooks/runtime/`

**What lives here:** Ten runtime hook scripts fired after tool invocations.

**Responsible for:** Post-execution analysis and side effects: formatting dispatched files, running security scanners, writing audit log entries, analyzing code quality, classifying errors, aggregating notifications, persisting task events, building session profiles, and injecting context into prompts.

**Not responsible for:** Blocking tool execution (that is the guard layer's job) or modifying the files they analyze (read-only except for the audit log).

**Files of note:**
- `post-format.sh` (v2.4.0) — registry-driven; reads `scanners.json` to dispatch format scripts
- `post-scan.sh` (v2.5.0) — registry-driven; always runs `generic/secret-scan.sh`, then extension-specific scanners; concurrency-limited via `CORTEX_MAX_JOBS` (default 4)
- `post-code-intel.sh` (v1.2.0) — four checks: complexity, duplication, naming, structure; outputs structured JSON
- `session-start.sh` (v1.2.0) — builds `project-profile.json`; idempotent via fingerprint; prunes scan cache entries older than 7 days
- `prompt-optimizer.sh` (v1.6.0) — replaces every user prompt with a context-enriched structured version; supports `--y` flag to default all binary decisions to YES
- `stop-build.sh` (v1.4.0) — skips if project already running; retries build up to 3×; reports failures without auto-fixing
- `task-tracker.sh` (v1.0.2) — persists TaskCreated/TaskCompleted events to `.claude/cache/tasks.json`

---

### `.claude/core/scanners/`

**What lives here:** 25 language directories, each containing `security-scan.sh` and/or `format.sh`.

**Responsible for:** Language-specific security pattern detection and formatting. Called exclusively by `post-scan.sh` and `post-format.sh` via registry dispatch — never invoked directly.

**Not responsible for:** Deciding which files to scan (that is `post-scan.sh`'s job based on `scanners.json`).

**Files of note:**
- `generic/secret-scan.sh` — wildcard scanner; runs on every file type including JSON, YAML, TOML, and `.env` files
- `node/react-security-scan.sh` — covers `.ts`, `.tsx`, `.js`, `.jsx`, `.vue`, `.svelte`
- `dotnet/security-scan.sh` — covers `.cs` files

---

### `.claude/commands/`

**What lives here:** 14 Markdown files — one per slash command — containing the full implementation instructions for each command.

**Responsible for:** Orchestrating analysis workflows. Commands read from the project and registry, invoke Bash tools, and produce structured output. They must not modify hook or registry files directly.

**Not responsible for:** Containing business logic inline. Complex logic belongs in hooks or scanners, not here.

**Files of note:** `commit.md`, `doctor.md`, `init-cortex.md` — the three most frequently used commands; touch these carefully as they affect every project using Cortex.

---

### `.claude/registry/`

**What lives here:** Three JSON files: `hooks.json`, `commands.json`, `scanners.json`.

**Responsible for:** Central configuration — declaring what hooks exist and their versions, what commands are available, and which scanners handle which file extensions.

**Not responsible for:** Containing any executable code or business logic.

**Files of note:**
- `scanners.json` — flat `extension → [scanner-array]` format; the `*` wildcard entry ensures the secret scanner runs on every file regardless of extension
- `hooks.json` — `version` field per hook is compared by `/init-cortex` to determine whether redeployment is needed

---

### `.claude/config/`

**What lives here:** `cortex.config.json` — framework version (`3.1.0`) and default runtime path configuration.

**Responsible for:** Storing framework-level configuration that does not change per-project. Risk thresholds (`warn=30`, `block=70`) are overridable here per-project.

**Not responsible for:** Project-specific settings (those go in `.claude/local/`).

---

### `.claude/cache/`

**What lives here:** `project-profile.json` — generated by `session-start.sh` at the start of each Claude Code session. Also `scans/` — a hash-keyed cache of security scan results.

**Responsible for:** Caching the detected project type, dependencies, entry points, and folder structure so `prompt-optimizer.sh` can inject this context without re-running discovery on every prompt. Scan cache avoids re-scanning unchanged files.

**Not responsible for:** Persistent state across framework versions. These files are regenerated automatically and can be safely deleted.

---

### `.claude/state/`

**What lives here:** `snapshot.json` (regression baseline) and `index.json` (snapshot history).

**Responsible for:** Persisting regression baselines written by `/regression --save` and read by subsequent `/regression` runs.

**Not responsible for:** Real-time state. These files are only written explicitly by the `/regression` command.

---

### `.claude/base/`

**What lives here:** Remote framework snapshot — a copy of the upstream Cortex content fetched by `/update-cortex`.

**Responsible for:** Providing a clean reference for framework updates that can be diffed and merged without touching local overrides.

**Not responsible for:** Active execution. Hooks and scanners always run from the path resolved by `CORTEX_ROOT`, not from `base/`.

---

### `.claude/local/`

**What lives here:** Project-specific overrides (user-managed).

**Responsible for:** Allowing per-project customization of Cortex behavior without modifying the base framework.

**Not responsible for:** Anything by default — this directory starts empty. Files placed here mirror the path structure of `.claude/core/` and override the corresponding base file.

**Critical constraint:** This directory is never modified by `/update-cortex` or `/init-cortex`. Safe to customize freely.

---

### `.claude/` (adapter layer)

**What lives here:** `settings.json` (hook event wiring), `settings.local.json` (local permission overrides), `keybindings.json` (key bindings), and `commands/` (command implementations).

**Responsible for:** Adapter layer — connecting Claude Code events to hook script paths using `${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/...` format.

**Not responsible for:** Hook logic, scanner logic, or command implementation detail changes. If a behavior needs to change, change it in `core/`, not in `settings.json`.

**Files of note:** `settings.json` — editing this file incorrectly will disconnect hooks from Claude Code events entirely; always validate with `/doctor` after changes.

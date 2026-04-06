# Install Guide

---

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Yes | Runs the hooks and commands |
| `bash` 4.0+ | Yes | All hook scripts |
| `jq` | Yes | JSON parsing in every hook |
| `node` 16+ | Yes | `post-code-intel.sh` code intelligence hook |
| `git` | Yes | Branch detection in pre-guard, commit command |

Install `jq` if missing:
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows — Scoop (recommended)
scoop install jq

# Windows — winget
winget install jqlang.jq

# Windows — Chocolatey
choco install jq
```

Verify: `jq --version` — expected output: `jq-1.7.x` or later.

> **Note:** `jq` is required by every hook. Without it all security scanning, formatting, and guard logic silently no-ops on every tool invocation.

---

## 1. Clone the Cortex repository

```bash
git clone https://github.com/SubhanAmrslnv/Cortex.git ~/cortex
```

Or copy it to any stable location on your machine.

---

## 2. Make Cortex available at runtime

Cortex resolves its runtime path dynamically via `CORTEX_ROOT`. Three options — pick one:

### Option A — Global install (recommended for single-machine use)

```bash
cp -r ~/cortex/.cortex ~/.cortex
```

Or use a symlink to keep it in sync with the repo without copying:

```bash
ln -s ~/cortex/.cortex ~/.cortex
```

With this option, hooks fall back to `$HOME/.cortex` automatically — no environment variable needed.

### Option B — Project-local install

Copy `.cortex/` into the project root alongside `.claude/`:

```bash
cp -r ~/cortex/.cortex /path/to/your/project/.cortex
```

When Claude Code opens in that project directory, hooks detect `$(pwd)/.cortex` and use it automatically.

### Option C — Environment variable (CI/CD, Docker, custom paths)

Set `CORTEX_ROOT` to the absolute path of the `.cortex/` directory:

```bash
export CORTEX_ROOT="/custom/path/to/.cortex"
```

Add this to your shell profile (`~/.bashrc`, `~/.zshrc`) or CI environment for persistent use.

**Resolution priority:** `$CORTEX_ROOT` env var → `$(pwd)/.cortex` → `$HOME/.cortex`

---

## 3. Copy `.claude/` into your project

Copy the adapter layer into the root of each project where you want Cortex active:

```bash
cp -r ~/cortex/.claude /path/to/your/project/
```

This folder contains only the hook wiring (`settings.json`) and thin command wrappers. It contains no framework logic — everything runs from the path resolved by CORTEX_ROOT.

---

## 4. Run `/init-cortex`

Open Claude Code in your project directory and run:

```
/init-cortex
```

`/init-cortex` will:
- Version-compare each hook source vs runtime, deploy only what changed
- Validate `settings.json` wiring against the registry
- Validate all command and scanner registries
- Print a structured report with status per hook, command, and scanner

Run `/init-cortex` after setup and again after any hook update.

---

## 5. Verify the install

Run the diagnostics command:

```
/doctor
```

This checks:
- All hooks are deployed and match the registry versions
- `settings.json` wires every hook correctly
- All scanner scripts exist
- `jq` and `node` are available on `$PATH`

Available flags: `--fix` (auto-apply safe fixes), `--deep` (run extended architecture checks), `--dry-run` (simulate without applying).

---

## 6. Keep Cortex up to date

Pull the latest framework updates from the remote repository:

```
/update-cortex
```

This command:
1. Fetches changes from the remote repository
2. Shows a diff of what changed
3. Asks for confirmation before applying anything
4. Updates only `.cortex/base/` — your overrides in `.cortex/local/` are never touched
5. Re-runs `/init-cortex` to redeploy any updated hooks

**No destructive updates.** You always see the diff before anything is applied.

---

## 7. Local overrides

To customize Cortex behavior for a specific project without modifying the base framework:

Place your overrides in `.cortex/local/`. These files are never modified by `/update-cortex` or `/init-cortex`.

---

## 8. Available commands

### Core

| Command | Flags | Description |
|---|---|---|
| `/init-cortex` | — | Deploy hooks, validate registry and settings |
| `/doctor` | `--fix` `--deep` `--dry-run` | Full system diagnostics |
| `/update-cortex` | — | Fetch and apply framework updates |
| `/commit` | — | Interactive conventional commit with auto-generated message |

### Analysis

| Command | Flags | Description |
|---|---|---|
| `/impact` | `--staged` `--deep` `--since=<ref>` | Trace changed files through the dependency graph; assign risk level |
| `/regression` | `--save` `--reset` `--since=<ref>` `--deep` | Compare current state against a saved diagnostic baseline |
| `/hotspot` | `--since=<ref>` `--top=<n>` `--deep` | Score files by change frequency, size, and deps; surface risk areas |
| `/pr-check` | `--branch=<name>` `--staged` `--skip-build` `--skip-tests` | Simulate full PR validation before submitting |
| `/pattern-drift` | `--since=<ref>` `--deep` `--layer=<name>` | Detect deviations from dominant project coding patterns |
| `/optimize` | `--file=<path>` `--lang=<lang>` `--focus=perf\|clarity` | Optimize code for performance and readability |
| `/overengineering-check` | `--file=<path>` `--since=<ref>` `--deep` | Detect unnecessary abstractions and complexity |
| `/timeline` | `--file=<path>` `--module=<dir>` `--depth=<n>` `--since=<date>` | Analyze a file's evolution and classify its stability |

See `README.md` for full flag reference, output format, and risk level tables.

---

## Architecture

```
$CORTEX_ROOT/core/hooks/guards/    ← PreToolUse, PermissionRequest, PermissionDenied hooks
$CORTEX_ROOT/core/hooks/runtime/   ← PostToolUse, PostToolUseFailure, Notification, TaskCreated/Completed, Stop, SessionStart, UserPromptSubmit hooks
$CORTEX_ROOT/core/scanners/        ← 25 language directories; mappings in registry/scanners.json
$CORTEX_ROOT/registry/             ← hooks.json, scanners.json, commands.json
$CORTEX_ROOT/commands/             ← full command implementations
$CORTEX_ROOT/cache/                ← generated project-profile.json (written by session-start)
$CORTEX_ROOT/base/                 ← remote framework snapshot (auto-updated)
$CORTEX_ROOT/local/                ← your project overrides (never auto-updated)

<project>/.claude/settings.json   ← wires ${CORTEX_ROOT:-$HOME/.cortex}/core/hooks/* to Claude Code events
<project>/.claude/commands/        ← thin wrappers; delegate to $CORTEX_ROOT/commands/
```

CORTEX_ROOT defaults to `~/.cortex` when no env var or project-local `.cortex/` is present.

---

## Hook Event Map

| Claude Code Event | Hook file | Trigger |
|---|---|---|
| `PreToolUse (Bash)` | `guards/pre-guard.sh` | Before any Bash command |
| `PermissionRequest` | `guards/permission-request.sh` | When a tool needs user approval |
| `PermissionDenied` | `guards/permission-denied.sh` | After a permission is denied |
| `SessionStart` | `runtime/session-start.sh` | When a Claude Code session begins |
| `UserPromptSubmit` | `runtime/prompt-optimizer.sh` | Before every user message is processed |
| `PostToolUse (Write\|Edit)` | `runtime/post-format.sh` | After any file write or edit |
| `PostToolUse (Write\|Edit)` | `runtime/post-scan.sh` | After any file write or edit |
| `PostToolUse (Write\|Edit)` | `runtime/post-code-intel.sh` | After any file write or edit |
| `PostToolUse (Write\|Edit\|Bash)` | `runtime/post-audit-log.sh` | After any tool use |
| `PostToolUseFailure` | `runtime/post-error-analyzer.sh` | When a tool invocation fails |
| `Notification` | `runtime/notification.sh` | On any Claude Code notification event |
| `TaskCreated` | `runtime/task-tracker.sh` | When a task is created |
| `TaskCompleted` | `runtime/task-tracker.sh` | When a task is completed |
| `Stop` | `runtime/stop-build.sh` | When Claude finishes a response |

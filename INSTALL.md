# Install Guide

---

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Yes | Runs the hooks and commands |
| `bash` 4.0+ | Yes | All hook scripts |
| `jq` | Yes | JSON parsing in every hook |
| `node` 16+ | Yes | `post-code-intel.js` code intelligence hook |
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

## 2. Install to `~/.cortex/`

Cortex hooks run directly from `~/.cortex/core/hooks/`. Copy the framework there:

```bash
cp -r ~/cortex/.cortex ~/.cortex
```

Or use a symlink to keep it in sync with the repo:

```bash
ln -s ~/cortex/.cortex ~/.cortex
```

> **Why `~/.cortex/`?** All hook paths in `settings.json` point to `~/.cortex/core/hooks/`. This keeps hooks accessible globally regardless of which project you open Claude Code in.

---

## 3. Copy `.claude/` into your project

Copy the adapter layer into the root of each project where you want Cortex active:

```bash
cp -r ~/cortex/.claude /path/to/your/project/
```

This folder contains only the hook wiring (`settings.json`) and thin command wrappers. It contains no framework logic — everything runs from `~/.cortex/`.

---

## 4. Run `/init-cortex`

Open Claude Code in your project directory and run:

```
/init-cortex
```

`/init-cortex` will:
- Write `~/.claude/cortex.env` with the resolved `CORTEX_ROOT` path (required by all hooks and commands)
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

## 8. Additional commands

**Impact analysis** — trace changed files through the dependency graph and assign a risk level before merging:

```
/impact
/impact --staged
/impact --since=main --deep
```

**Regression detection** — save a baseline and compare future states against it:

```
/regression --save        # capture current state as baseline
/regression               # compare current state against baseline
/regression --reset       # start fresh
```

See `README.md` for full flag reference and output format.

---

## 7. Local overrides

To customize Cortex behavior for a specific project without modifying the base framework:

Place your overrides in `.cortex/local/`. These files are never modified by `/update-cortex` or `/init-cortex`.

---

## Architecture

```
~/.cortex/core/hooks/guards/    ← PreToolUse, PermissionRequest, PermissionDenied hooks
~/.cortex/core/hooks/runtime/   ← PostToolUse, PostToolUseFailure, Notification, TaskCreated/Completed, Stop, SessionStart, UserPromptSubmit hooks
~/.cortex/core/scanners/        ← 25 language directories; mappings in registry/scanners.json
~/.cortex/registry/             ← hooks.json, scanners.json, commands.json
~/.cortex/commands/             ← full command implementations
~/.cortex/cache/                ← generated project-profile.json (written by session-start)
~/.cortex/base/                 ← remote framework snapshot (auto-updated)
~/.cortex/local/                ← your project overrides (never auto-updated)

<project>/.claude/settings.json ← wires ~/.cortex/core/hooks/* to Claude Code events
<project>/.claude/commands/     ← thin wrappers; delegate to ~/.cortex/commands/
```

The `.claude/` folder in your project contains no business logic. All logic runs from `~/.cortex/`.

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

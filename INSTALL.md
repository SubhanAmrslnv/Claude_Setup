# Cortex Install Guide

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Yes | Runs hooks and commands |
| `bash` 4.0+ | Yes | All hook scripts |
| `jq` | Yes | JSON parsing in every hook |
| `git` | Yes | Branch detection, commit command |

Install `jq` on Windows:

```bash
# Scoop (recommended)
scoop install jq

# winget
winget install jqlang.jq

# Chocolatey
choco install jq
```

Verify: `jq --version` — expected: `jq-1.7.x` or later.

---

## Installation

Copy two folders into your Windows user directory. That's it.

**1. Copy `.cortex` to your user directory:**

```
C:\Users\<your-username>\.cortex\
```

**2. Copy `.claude` to your user directory:**

```
C:\Users\<your-username>\.claude\
```

Both folders sit directly under `C:\Users\<your-username>\` — not inside any project, not inside any subfolder.

**3. Add `.claude` and `.cortex` to your project root:**

Each project that uses Cortex needs both a `.claude` and a `.cortex` folder in its root directory. Copy both folders from this repo into the root of your project:

```
<your-project>/
  .claude/
    settings.json
    commands/
  .cortex/
    core/
    commands/
    registry/
    config/
    cache/
    state/
```

- `.claude/` wires the hook bindings and slash commands into Claude Code for the project.
- `.cortex/` is the local framework install. When present, Cortex uses it instead of the global `~/.cortex/` fallback — giving you per-project control over hook versions, scanner config, and registry settings.

Without both folders, Cortex hooks and commands will not be available in the project.

> **Note:** The `.claude/` and `.cortex/` folders copied to `C:\Users\<username>\` in steps 1–2 act as the global fallback for machines or projects that don't carry their own copies. The per-project folders always take precedence.

**4. Open the project in Claude Code and run:**

```
/init-cortex
```

This deploys hooks, validates the registry, and confirms the setup is wired correctly. Run it once per project on first use.

**5. Verify the install:**

```
/doctor
```

All hooks, commands, and scanners should report as active.

**6. (Optional) Run smoke tests:**

```bash
bash .cortex/test/run.sh
```

Runs 13 fixture-based tests covering pre-guard, post-error-analyzer, and post-scan. All should pass.

---

## How it works

Cortex resolves its runtime path automatically. When no project-local `.cortex/` folder is present, it falls back to `$HOME/.cortex` — which on Windows maps to `C:\Users\<username>\.cortex`.

No environment variables. No configuration. No per-project copies of the framework.

The `.claude/` folder wires Cortex into Claude Code by providing `settings.json` (hook bindings) and thin command wrappers. It contains no framework logic — everything runs from `.cortex`.

---

## Summary

1. Copy `.cortex` and `.claude` into `C:\Users\<your-username>\`
2. Copy both `.claude` and `.cortex` into the root of each project you want Cortex active in
3. Run `/init-cortex` once per project
4. Optionally run `bash .cortex/test/run.sh` to verify the installation

The global `.cortex/` install acts as a fallback for machines or projects without a local copy. The per-project `.claude/` and `.cortex/` folders take precedence and give you version-pinned, project-isolated control over the full framework.

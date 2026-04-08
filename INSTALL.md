# Cortex Install Guide

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| [Claude Code](https://claude.ai/code) | Yes | Runs hooks and commands |
| `bash` 4.0+ | Yes | All hook scripts |
| `jq` | Yes | JSON parsing in every hook |
| `node` 16+ | Yes | `post-code-intel.sh` code intelligence hook |
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
C:\Users\subhan.amiraslanov\.cortex\
```

**2. Copy `.claude` to your user directory:**

```
C:\Users\subhan.amiraslanov\.claude\
```

Both folders sit directly under `C:\Users\<your-username>\` — not inside any project, not inside any subfolder.

**3. Add `.claude` to your project root:**

Each project that uses Cortex needs a `.claude` folder in its root directory. Copy the `.claude` folder from this repo into the root of your project:

```
<your-project>/
  .claude/
    settings.json
    commands/
```

This is what activates Cortex for that project — it wires the hook bindings and slash commands into Claude Code. Without this folder, Cortex hooks and commands will not be available in the project.

> **Note:** The `.claude/` folder you copied to `C:\Users\<username>\` in step 2 covers global settings. The per-project `.claude/` folder activates Cortex commands and hooks for that specific project.

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

---

## How it works

Cortex resolves its runtime path automatically. When no project-local `.cortex/` folder is present, it falls back to `$HOME/.cortex` — which on Windows maps to `C:\Users\<username>\.cortex`.

No environment variables. No configuration. No per-project copies of the framework.

The `.claude/` folder wires Cortex into Claude Code by providing `settings.json` (hook bindings) and thin command wrappers. It contains no framework logic — everything runs from `.cortex`.

---

## Summary

1. Copy `.cortex` and `.claude` into `C:\Users\<username>\`
2. Copy `.claude` into the root of each project you want Cortex active in
3. Run `/init-cortex` once per project

The global `.cortex/` install covers all projects on the machine. The per-project `.claude/` folder is what tells Claude Code to load Cortex hooks and commands for that project.

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

Cortex lives entirely inside `.claude/`. Copy this single folder to activate the framework globally and per-project.

**1. Copy `.claude` to your user directory:**

```
C:\Users\<your-username>\.claude\
```

This installs Cortex globally. Claude Code already reads `~/.claude/settings.json` for global configuration, so this is the natural home for the framework. The global install acts as a fallback for any machine or project that does not carry its own per-project copy.

**2. Add `.claude` to your project root:**

Each project that uses Cortex needs a `.claude/` folder in its root directory. Copy the folder from this repo into the root of your project:

```
<your-project>/
  .claude/
    settings.json
    settings.local.json
    keybindings.json
    commands/
    core/
    registry/
    config/
    cache/
    state/
    test/
    base/
    local/
```

- `settings.json` wires the hook bindings and slash commands into Claude Code for the project.
- `core/`, `registry/`, and `config/` contain the full framework logic. When present in the project root, Cortex uses the project-local copy instead of the global `~/.claude/` fallback — giving you per-project control over hook versions, scanner config, and registry settings.

> **Note:** The `.claude/` folder copied to `C:\Users\<username>\` in step 1 acts as the global fallback for machines or projects that don't carry their own copy. The per-project folder always takes precedence.

**3. Open the project in Claude Code and run:**

```
/init-cortex
```

This deploys hooks, validates the registry, and confirms the setup is wired correctly. Run it once per project on first use.

**4. Verify the install:**

```
/doctor
```

All hooks, commands, and scanners should report as active.

**5. (Optional) Run smoke tests:**

```bash
bash .claude/test/run.sh
```

Runs 13 fixture-based tests covering pre-guard, post-error-analyzer, and post-scan. All should pass.

---

## How it works

Cortex resolves its runtime path automatically. `settings.json` uses `${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/...` for every hook path. This means:

- If `CORTEX_ROOT` is set (CI/CD, Docker, custom installs) → use it
- Otherwise → use the project-local `.claude/` directory

When no project-local `.claude/` folder contains a framework install, the global `~/.claude/` copy acts as the fallback — which on Windows maps to `C:\Users\<username>\.claude`.

No environment variables required. No configuration. Just copy `.claude/` where needed.

---

## CORTEX_ROOT (advanced)

Set `CORTEX_ROOT` to override the resolved framework path:

```bash
export CORTEX_ROOT="/custom/path/to/.claude"
```

Resolution priority: `$CORTEX_ROOT` → `$(pwd)/.claude` → `$HOME/.claude`

Add to `~/.bashrc`, `~/.zshrc`, or your CI environment for persistent use.

---

## Summary

1. Copy `.claude` into `C:\Users\<your-username>\` (global fallback)
2. Copy `.claude` into the root of each project you want Cortex active in
3. Run `/init-cortex` once per project
4. Optionally run `bash .claude/test/run.sh` to verify the installation

The per-project `.claude/` folder takes precedence over the global `~/.claude/` copy and gives you version-pinned, project-isolated control over the full framework.

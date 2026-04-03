# Cortex — Claude Code Global Configuration

Version-controlled global configuration for [Claude Code](https://claude.ai/code).
Covers security guards, auto-formatting, audit logging, and behavior rules for .NET (C#) and Node/React projects.

---

## Repository Layout

```
.cortex/                              ← framework root (all logic lives here)
  core/
    hooks/
      guards/pre-guard.sh             ← PreToolUse guard
      runtime/post-format.sh          ← registry-driven formatter dispatcher
      runtime/post-scan.sh            ← registry-driven security scanner dispatcher
      runtime/post-audit-log.sh       ← audit logger
      runtime/stop-build.sh           ← build failure reporter
    runtime/
      command-runner.sh               ← registry-driven command validator/dispatcher
    scanners/
      dotnet/security-scan.sh         ← unsafe .NET API detection
      dotnet/format.sh                ← dotnet format wrapper
      node/react-security-scan.sh     ← XSS pattern detection
      node/format.sh                  ← Prettier + ESLint wrapper
      generic/secret-scan.sh          ← hardcoded secret detection
  commands/
    commit.md                         ← full commit command implementation
    doctor.md                         ← full doctor command implementation
    init.md                           ← full init command implementation
    update-cortex.md                  ← full update-cortex command implementation
  registry/
    hooks.json                        ← hook names, versions, source paths
    commands.json                     ← discoverable command list
    scanners.json                     ← extension→scanner mapping
  config/
    cortex.config.json                ← framework configuration
  base/                               ← remote Cortex content (updated by /update-cortex)
  local/                              ← project-local overrides (never overwritten)
.claude/
  settings.json                       ← adapter only: wires ~/.claude/hooks/* to Claude Code
  commands/                           ← thin wrappers; delegate to .cortex/commands/
CLAUDE.md
README.md
INSTALL.md
```

---

## Setup

Copy this repo to your machine. Open Claude Code in any project directory and run `/init`.

---

## What's Inside

### Hooks

| Event | Script | What it does |
|---|---|---|
| PreToolUse (Bash) | `pre-guard.sh` | Blocks dangerous commands before they run |
| PostToolUse (Write\|Edit) | `post-format.sh` | Registry-driven: dispatches to formatters based on file extension |
| PostToolUse (Write\|Edit) | `post-scan.sh` | Registry-driven: dispatches to security scanners based on file extension |
| PostToolUse (Write\|Edit\|Bash) | `post-audit-log.sh` | Appends every tool use to `~/.claude/audit.log` |
| Stop | `stop-build.sh` | Builds project; on failure prints errors for manual review |

Hooks live in `.cortex/core/hooks/`. The first four are deployed to `~/.claude/hooks/` by `/init`. The Stop hook runs directly from `.cortex/core/hooks/runtime/stop-build.sh`.

### Registry-Driven Dispatch

`post-format.sh` and `post-scan.sh` contain no language-specific logic. All extension→scanner mappings live in `.cortex/registry/scanners.json`:

```json
{
  ".cs": ["dotnet/security-scan.sh", "dotnet/format.sh"],
  ".ts": ["node/react-security-scan.sh", "node/format.sh"],
  "*": ["generic/secret-scan.sh"]
}
```

To add support for a new language: add an entry to `scanners.json` and create the scanner scripts. No hook changes required.

### Security Guards (`pre-guard.sh`)

- Dangerous commands: `rm -rf`, `drop table`, `truncate`, `--force`
- Force-push or direct commit to `main`/`master`/`develop`
- Non-conventional commit message format
- Staging secret files (`.env`, `.key`, `.pem`, `.pfx`)
- Destructive git ops (`reset --hard`, `clean -f`)
- Files >1MB staged (excludes binaries/assets)
- SQL injection patterns in CLI args
- Writes to system directories (`/etc`, `/usr`, `/bin`)
- `sudo` usage
- Known exploit tools (`sqlmap`, `nmap`, `hydra`, `hashcat`, etc.)
- Reverse shells, base64 execution, cron persistence, curl-pipe-to-shell

---

## Safe Update System

Cortex uses a two-layer update model:

- **`base/`** — canonical framework files from the remote Cortex repo. Updated by `/update-cortex`.
- **`local/`** — project-specific overrides. Never touched by any automated process.

### Running `/update-cortex`

1. Fetches latest changes from the remote Cortex repository
2. Shows a diff of what changed (added, modified, removed files)
3. Asks for confirmation before applying anything
4. Updates **only** `base/` — `local/` is never modified
5. Runs `/init` to redeploy any updated hooks

If conflicts arise, they are surfaced for manual resolution. No auto-resolution.

---

## Deploying Hook Changes

1. Edit the source hook in `.cortex/core/hooks/`
2. Increment the `# @version: X.Y.Z` tag on line 2
3. Update the version in `.cortex/registry/hooks.json`
4. Run `/init` — it version-compares and deploys only outdated hooks

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Version-aware hook deployment, registry validation, settings check |
| `/commit` | Interactive conventional commit with branch routing |
| `/doctor` | Full system diagnostics — checks hooks, settings, registry, scanners |
| `/update-cortex` | Safely update `.cortex/base/` from remote with diff preview |

Command wrappers in `.claude/commands/` are thin delegates. All logic lives in `.cortex/commands/`.

# Cortex — Claude Code Global Configuration

Version-controlled global configuration for [Claude Code](https://claude.ai/code).
Covers security guards, auto-formatting, audit logging, and behavior rules for .NET (C#) and Node/React projects.

---

## Setup

Copy the `.claude` folder into the root of your target project:

```bash
cp -r .claude /path/to/your/project/
```

Open Claude Code in your project and run `/init` to verify hooks and settings are wired correctly.

---

## What's Inside

### Hooks

| Event | Script | What it does |
|---|---|---|
| PreToolUse (Bash) | `pre-guard.sh` | Blocks dangerous commands before they run |
| PostToolUse (Write\|Edit) | `post-format.sh` | Dispatches formatting to language scanners (dotnet/node) |
| PostToolUse (Write\|Edit) | `post-scan.sh` | Runs secret scan on all files; dispatches security scans by language |
| PostToolUse (Write\|Edit\|Bash) | `post-audit-log.sh` | Appends every tool use to `~/.claude/audit.log` |
| Stop | `stop-build.sh` | Builds project; on failure prints errors for manual review |

Hooks live in `.claude/.cortex/core/hooks/`. The first four are deployed to `~/.claude/hooks/` by `/init`. The Stop hook runs directly from `.claude/.cortex/core/hooks/runtime/stop-build.sh`.

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

## Deploying Hook Changes

Hook scripts live in `.claude/.cortex/core/hooks/` (source). Run `/init` after any hook edit — it version-compares and deploys only outdated hooks to `~/.claude/hooks/`.

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Version-aware hook deployment, registry validation, settings check |
| `/commit` | Interactive conventional commit with branch routing |
| `/doctor` | Full system diagnostics — checks hooks, settings, registry, scanners |
| `/update-cortex` | Safely update `.claude/.cortex/base/` from remote with diff preview |

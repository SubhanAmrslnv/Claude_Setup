# Cortex — Claude Code Global Configuration

Version-controlled global configuration for [Claude Code](https://claude.ai/code).
Covers security guards, auto-formatting, audit logging, and behavior rules for .NET (C#) projects.

---

## Setup

Copy the `.claude` folder into the root of your target project:

```bash
cp -r .claude /path/to/your/project/
```

That is the only required step. No installation, no configuration, no additional dependencies.

Open Claude Code in your project and run `/init` to verify hooks and settings are wired correctly.

---

## What's Inside

### Hooks

| Event | Script | What it does |
|---|---|---|
| PreToolUse (Bash) | `pre-guard.sh` | Blocks dangerous commands before they run |
| PostToolUse (Write\|Edit) | `post-format.sh` | Auto-formats `.cs` via dotnet format; `.ts/.html/.scss` via Prettier; `.ts` via ESLint |
| PostToolUse (Write\|Edit) | `post-secret-scan.sh` | Warns on hardcoded secrets in any file |
| PostToolUse (Write\|Edit) | `post-dotnet-security-scan.sh` | Warns on unsafe .NET APIs in `.cs` files |
| PostToolUse (Write\|Edit) | `post-react-security-scan.sh` | Warns on XSS patterns in React/TS files |
| PostToolUse (Write\|Edit\|Bash) | `post-audit-log.sh` | Appends every tool use to `~/.claude/audit.log` |
| Stop | `stop-build-and-fix.sh` | Builds project; on failure calls Claude Haiku to fix and retries |

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

Hook scripts live in `.claude/hooks/` (source) and must be synced to `~/.claude/hooks/` (runtime):

```bash
cp .claude/hooks/*.sh ~/.claude/hooks/
```

Run this after any hook edit, or run `/init` to do it automatically.

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Verify and restore all hooks, scripts, and settings |
| `/commit` | Interactive conventional commit with branch routing |
| `/update-cortex` | Sync the `.claude` folder with the latest Cortex remote |

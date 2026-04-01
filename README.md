# Claude Code Global Configuration

A version-controlled global configuration for [Claude Code](https://claude.ai/code) covering code standards, architecture principles, security guards, and automated hooks for .NET (C#), React, and React Native projects.

---

## Quick Setup

1. Drag and drop the `.claude` folder into your project or home directory
2. Open Claude Code and type `/init`

See [INSTALL.md](./INSTALL.md) for full machine setup (Git, jq, Node.js, .NET SDK, API key).

---

## What's Inside

### Hooks

| Event | Script | Purpose |
|---|---|---|
| PreToolUse | `pre-guard.sh` | 18 security checks before any Bash command runs |
| PostToolUse | `post-format.sh` | Auto-format `.cs`, `.ts`, `.html`, `.scss` on save |
| PostToolUse | `post-secret-scan.sh` | Warn on hardcoded secrets in any file |
| PostToolUse | `post-dotnet-security-scan.sh` | Warn on unsafe .NET APIs in `.cs` files |
| PostToolUse | `post-react-security-scan.sh` | Warn on XSS patterns in `.ts/.tsx/.js/.jsx` |
| PostToolUse | `post-audit-log.sh` | Append every tool use to `audit.log` |
| Stop | `stop-build-and-fix.sh` | Build project; prints errors for manual review on failure |
| Stop | `stop-git-autocommit.sh` | Auto-generates conventional commit message from diff stats |
| Stop | `stop-notify.sh` | Windows desktop notification when Claude finishes |

### Security Guards (`pre-guard.sh`)

- Dangerous commands: `rm -rf`, `drop table`, `truncate`, `--force`
- Force-push to `main`/`master`
- Direct commits to `main`/`master`
- Production DB connection strings
- Staging secret files (`.env`, `.key`, `.pem`, `.pfx`)
- Destructive git ops (`reset --hard`, `clean -f`)
- Files >1MB staged (excludes binaries and assets)
- SQL injection patterns in CLI args
- Writes to system directories (`/etc`, `/usr`, `/bin`)
- `sudo` usage
- Known exploit tools (`sqlmap`, `nmap`, `hydra`, `hashcat`, etc.)
- Reverse shells, base64 execution, cron persistence
- `curl`/`wget` piped to interpreter
- Credential exfiltration via network tools

### Global Claude Instructions

Defined in `CLAUDE.md` and loaded automatically every session:

- **Stack:** .NET (C#), Node.js (TypeScript), React, React Native, PostgreSQL, SQL Server
- **Patterns:** Clean Architecture, CQRS, DDD
- **Code standards:** async/await, meaningful names, no magic strings, early returns, explicit error handling
- **Architecture:** separation of concerns, thin controllers, depend on abstractions, SOLID/DRY/YAGNI
- **Efficiency rules:** parallel tool calls, surgical edits, no preamble, lead with action

---

## Requirements

| Tool | Purpose |
|---|---|
| [Git](https://git-scm.com/download/win) | Version control |
| [jq](https://jqlang.github.io/jq/download/) | JSON parsing in hook scripts |
| [Node.js](https://nodejs.org) | Prettier, ESLint |
| [.NET SDK](https://dotnet.microsoft.com/download) | `dotnet format`, `dotnet build` |
| [Claude Code](https://claude.ai/code) | `npm install -g @anthropic-ai/claude-code` |

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Verify and restore all hooks, scripts, and settings on a new machine |

# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

This repo is the **Claude Code global configuration** workspace — no application code lives here. Everything is shell scripts, JSON config, and this file. Changes here affect Claude's behavior across all projects on this machine.

---

## Repository Layout

```
CLAUDE.md                  ← this file; loaded every session
.claude/
  settings.json            ← hook wiring for Claude Code
  hooks/                   ← source hook scripts (deploy to ~/.claude/hooks/)
  commands/                ← custom slash commands
README.md                  ← project overview and quick setup
INSTALL.md                 ← full machine setup guide
```

> After changing any hook in `.claude/hooks/`, sync it:
> `cp .claude/hooks/<file>.sh ~/.claude/hooks/`

---

## Active Hooks

**PreToolUse (`Bash`)** — `pre-guard.sh`
Blocks dangerous Bash commands before they run. Checks:
- `rm -rf`, `drop table`, `truncate`, `--force`
- Force-push or direct commit to `main`/`master`/`develop`
- Non-conventional commit messages
- Staging secret files (`.env`, `.key`, `.pem`, `.pfx`)
- `git reset --hard`, `git clean -f`
- Files >1MB staged (excludes binaries/assets)
- SQL injection patterns in CLI args
- Writes to system directories (`/etc`, `/usr`, `/bin`, `/sys`, `/proc`)
- `sudo` usage
- Exploit tools (`sqlmap`, `nmap`, `hydra`, `hashcat`, etc.)
- Reverse shells, base64 execution, cron persistence, curl-pipe-to-shell

**PostToolUse (`Write|Edit`)** — `post-format.sh`
Auto-formats on save: `.cs` via `dotnet format`; `.ts/.html/.scss` via Prettier; `.ts` via ESLint.

**PostToolUse (`Write|Edit`)** — `post-secret-scan.sh`, `post-dotnet-security-scan.sh`, `post-react-security-scan.sh`
Scans written files for hardcoded secrets, unsafe .NET APIs, and XSS patterns.

**PostToolUse (`Write|Edit|Bash`)** — `post-audit-log.sh`
Appends every tool use to `~/.claude/audit.log`.

**Stop** — `stop-build-and-fix.sh`
Runs the project build (`dotnet build` / `npm run build`). On failure, calls Claude Haiku to fix and retries once.

---

## Working in This Repo

### Editing hooks
- Source of truth: `.claude/hooks/`
- Always sync to `~/.claude/hooks/` after editing — they are not symlinked
- Test hooks manually: `bash .claude/hooks/<hook>.sh` with a sample JSON payload on stdin

### Editing settings.json
- Hook paths use `~/.claude/hooks/` (global, not project-relative)
- After adding a new hook entry, ensure the script exists in both `.claude/hooks/` and `~/.claude/hooks/`

### Conventional commits (enforced by pre-guard.sh)
Format: `type(scope): message`
Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `style`, `perf`

Never include `Co-Authored-By: Claude` or any Claude/Anthropic attribution in commit messages. No `🤖` emoji, no Claude profile links.

---

## Efficiency Rules

- Read only files directly relevant to the task
- Batch all independent tool calls in one message
- Use `Grep` to locate symbols before reading full files
- Use `Glob` for file discovery, not `ls` or `find`
- Prefer `Edit` over `Write` — only send the diff
- Lead with the action — no preamble, no trailing summaries
- Make reasonable assumptions; state them in one line

---

## Branch Protection

Never commit or push directly to `main`, `master`, or `develop` branches. Always work on a feature branch and open a pull request instead.

---

## Response Format & Tone

- Direct and concise — one sentence beats three
- Technical depth expected; don't over-explain basics
- If something is a bad practice, say so clearly
- No boilerplate filler, no restating the question
- Highlight security or correctness risks when present

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository is a **Claude Code global configuration** workspace. It contains shared standards and behavior rules that apply across all projects opened under this Claude Code installation. There is no application code here — the repo exists solely to version-control Claude's working preferences.

## Repository Layout

- `CLAUDE.md` — this file; loaded automatically by Claude Code in every session
- `settings.json` — hook wiring and Claude Code harness configuration
- `hooks/` — shell scripts executed by Claude Code on tool events (see below)

## Active Hooks

**PreToolUse (Bash)** — `pre-guard.sh` (18 checks, single process)
- Dangerous commands: `rm -rf`, `drop table`, `--force`, `truncate`
- Force-push to `main`/`master`
- Production DB connection strings
- Direct `git commit` on `main`/`master`
- Conventional commit format enforcement
- Staging secret/credential files (`.env`, `.key`, `.pem`, `.pfx`)
- `git reset --hard`, `git clean -f`
- Files >1MB (excludes binaries and assets)
- SQL injection patterns in CLI args
- Writes to system directories (`/etc`, `/usr`, `/bin`, `/sys`, `/proc`)
- `sudo` usage
- Known exploit tools (`sqlmap`, `nmap`, `hydra`, `hashcat`, etc.)
- Reverse shells, base64 execution, cron persistence, curl-pipe-to-shell, credential exfiltration

**PostToolUse (Write|Edit)**
- Auto-formats `.cs` via `dotnet format`, `.ts/.html/.scss` via Prettier, `.ts` via ESLint
- Scans all files for hardcoded secrets (`api_key`, `password`, `token`)
- Scans `.cs` for unsafe .NET APIs (`BinaryFormatter`, `Process.Start`, etc.)
- Scans `.ts/.tsx/.js/.jsx` for XSS patterns (`dangerouslySetInnerHTML`, `eval()`, `innerHTML=`)

**PostToolUse (Write|Edit|Bash)**
- Appends every tool use to `~/.claude/audit.log`

**Stop**
- Runs project build (`dotnet build` / `npm run build` / React Native); on failure calls Claude Haiku to fix and retries once
- Auto-commits staged changes with an AI-generated conventional commit message (requires `ANTHROPIC_API_KEY`)
- Shows a Windows desktop notification when Claude finishes

---

# Global Claude Instructions

## Efficiency Rules

### Context & Reading
- Read only the files directly relevant to the task — never speculatively read entire directories
- Use `Grep` to locate symbols before reading full files
- If a file was already read in this session, do not re-read it unless it has changed
- Use `Glob` for file discovery, not `Bash ls` or `find`

### Tool Use
- Batch all independent tool calls in a single message — never serialize calls that can run in parallel
- Prefer `Edit` over `Write` for modifying existing files — only send the diff
- Use `Grep` instead of reading entire files to check if something exists

### Responses
- Lead with the action or answer — no preamble, no restatement of the question
- No trailing summaries of what was just done — the diff speaks for itself
- If a task is clear, do it — do not ask for confirmation on obvious next steps
- One sentence is better than three when both convey the same information

### Decision Making
- Make reasonable assumptions and state them briefly rather than asking clarifying questions for every detail
- When multiple valid approaches exist, pick the most appropriate one for the stack and explain the choice in one line
- Never retry a failed tool call with identical parameters — diagnose first

### Code Changes
- Surgical edits only — do not reformat, rename, or refactor code outside the scope of the task
- Do not add comments, docstrings, or type annotations to code that was not changed
- Do not introduce abstractions for one-time use cases

---

## Code Standards
- Always use async/await — no blocking calls
- Meaningful names: no `data`, `res`, `temp`, `obj`
- No magic strings/numbers — use constants or enums
- Early returns over deeply nested conditionals
- Explicit error handling — never swallow exceptions silently

## Architecture Principles
- Separation of concerns: domain logic never leaks into controllers or UI
- Thin controllers/handlers — orchestrate, don't implement
- Depend on abstractions (interfaces), not concrete implementations
- SOLID, DRY, YAGNI — always

## Response Format
- Production-ready code, not toy examples
- Explain *why*, not just *what*
- Highlight trade-offs when multiple approaches exist
- Point out security or performance risks if present
- No unnecessary boilerplate or filler comments

## Stack
- Backend: .NET (C#), Node.js (TypeScript)
- Frontend: Angular, React
- DB: PostgreSQL, SQL Server
- Patterns: Clean Architecture, CQRS, DDD where applicable

## Tone
- Direct and concise
- Technical depth expected — don't over-explain basics
- If something is a bad practice, say so clearly

## Ignore
- `**/node_modules/**`
- `**/.nuget/**`
- `**/packages/**`
- `**/*.nupkg`
- `**/bin/**`
- `**/obj/**`
# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This repository is a **Claude Code global configuration** workspace. It contains shared standards and behavior rules that apply across all projects opened under this Claude Code installation. There is no application code here — the repo exists solely to version-control Claude's working preferences.

## Repository Layout

- `CLAUDE.md` — this file; loaded automatically by Claude Code in every session
- `settings.json` — hook wiring and Claude Code harness configuration
- `hooks/` — shell scripts executed by Claude Code on tool events (see below)

## Active Hooks

**PreToolUse (Bash)**
- Blocks dangerous commands: `rm -rf`, `drop table`, `--force`, `truncate`
- Blocks force-push to `main`/`master`
- Blocks commands targeting production DB connection strings
- Blocks direct `git commit` on `main`/`master`
- Enforces conventional commit format: `type(scope): subject`
- Blocks staging of secret/credential files (`.env`, `.key`, `.pem`, `.pfx`)
- Blocks `git reset --hard` and `git clean -f`
- Blocks staging files larger than 1MB

**PostToolUse (Write|Edit)**
- Auto-formats `.cs` via `dotnet format`, `.ts/.html/.scss` via Prettier, `.ts` via ESLint

**PostToolUse (Write|Edit|Bash)**
- Appends every tool use to `~/.claude/audit.log`

**Stop**
- Auto-commits staged changes with an AI-generated conventional commit message (requires `ANTHROPIC_API_KEY`)
- Shows a Windows desktop notification when Claude finishes

---

# Global Claude Instructions

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
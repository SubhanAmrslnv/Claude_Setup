# CLAUDE.md

This file provides guidance to Claude Code when working in this repository.

This repo is the **Cortex framework** — a modular Claude DevOps configuration system. No application code lives here. Everything is shell scripts, JSON config, and this file. Changes here affect Claude's behavior across all projects on this machine.

---

## Repository Layout

```
CLAUDE.md                             ← this file; loaded every session
.cortex/                              ← framework root (all logic lives here)
  core/
    hooks/
      guards/
        pre-guard.sh                  ← PreToolUse guard (blocks dangerous commands)
      runtime/
        post-format.sh                ← registry-driven formatter dispatcher (v2.0.0)
        post-scan.sh                  ← registry-driven security scanner dispatcher (v2.0.0)
        post-audit-log.sh             ← appends every tool use to audit.log
        stop-build.sh                 ← runs build, reports failures (no auto-fix)
    runtime/
      command-runner.sh               ← registry-driven command validator/dispatcher
    scanners/
      dotnet/
        security-scan.sh              ← unsafe .NET API detection
        format.sh                     ← dotnet format wrapper
      node/
        react-security-scan.sh        ← XSS pattern detection for JS/TS/JSX/TSX
        format.sh                     ← Prettier + ESLint wrapper
      generic/
        secret-scan.sh                ← hardcoded secret detection (all file types)
  commands/
    commit.md                         ← full commit command implementation
    doctor.md                         ← full doctor command implementation
    init.md                           ← full init command implementation
    update-cortex.md                  ← full update-cortex command implementation
  registry/
    hooks.json                        ← hook names, versions, source paths
    commands.json                     ← discoverable command list
    scanners.json                     ← extension→scanner mapping (flat format)
  config/
    cortex.config.json                ← framework configuration
  base/                               ← remote Cortex content (updated by /update-cortex)
  local/                              ← project-local overrides (never overwritten)
.claude/
  settings.json                       ← adapter only: wires ~/.claude/hooks/* to Claude Code
  commands/                           ← thin wrappers; delegate to .cortex/commands/
README.md
INSTALL.md
```

**Separation of concerns:**
- `hooks/` — execution only; no analysis logic
- `scanners/` — analysis only; called by hooks
- `commands/` — orchestration only; no inline business logic
- `registry/` — configuration only; no executable code
- `.claude/` — adapter layer only; no business logic

---

## Active Hooks

**PreToolUse (`Bash`)** — `pre-guard.sh`
Blocks dangerous Bash commands. Checks:
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

**PostToolUse (`Write|Edit`)** — `post-format.sh` (v2.0.0)
Registry-driven: reads `.cortex/registry/scanners.json`, dispatches to all `format.sh` entries matching the file extension. No language-specific logic in the hook itself.

**PostToolUse (`Write|Edit`)** — `post-scan.sh` (v2.0.0)
Registry-driven: always runs the `*` wildcard scanners (generic secret scan), then dispatches to extension-specific security scanners from `.cortex/registry/scanners.json`. No language-specific logic in the hook itself.

**PostToolUse (`Write|Edit|Bash`)** — `post-audit-log.sh`
Appends every tool use to `~/.claude/audit.log`.

**Stop** — `stop-build.sh`
Runs directly from `.cortex/core/hooks/runtime/stop-build.sh` (not deployed to `~/.claude/hooks/`). Detects project type, runs the build, prints errors on failure. Does NOT auto-fix.

---

## Working in This Repo

### Editing hooks

- Source of truth: `.cortex/core/hooks/`
- Scanners: `.cortex/core/scanners/`
- `pre-guard.sh`, `post-format.sh`, `post-scan.sh`, `post-audit-log.sh` — deployed to `~/.claude/hooks/` by `/init`; run there at runtime
- `stop-build.sh` — runs directly from `.cortex/core/hooks/runtime/`; not deployed anywhere; not in the hooks registry
- After editing any deployed hook or scanner, run `/init` — it version-compares and redeploys only outdated files
- Test hooks manually: `bash .cortex/core/hooks/<subpath>/<hook>.sh` with a sample JSON payload on stdin
- All deployed hooks carry a `# @version: X.Y.Z` tag on line 2 — increment when changing

### Hook versioning

Hooks carry `# @version: X.Y.Z` in line 2. The registry at `.cortex/registry/hooks.json` tracks the expected version per hook. `/init` compares source vs runtime and updates only if source is newer.

To release a hook update:
1. Increment `# @version:` in the source file under `.cortex/core/hooks/`
2. Update the matching version in `.cortex/registry/hooks.json`
3. Run `/init`

### Adding a new scanner

1. Create the script under `.cortex/core/scanners/<language>/`
2. Add it to `.cortex/registry/scanners.json` (flat extension→scanner-array format)
3. No hook changes required — `post-scan.sh` and `post-format.sh` are registry-driven

### Adding a new command

1. Create `<command>.md` in `.cortex/commands/` with the full implementation
2. Create a thin wrapper `<command>.md` in `.claude/commands/` delegating to the command-runner
3. Add the command name to `.cortex/registry/commands.json`

No other changes required — registry is the single source of truth.

### Editing settings.json

- `.claude/settings.json` is the adapter layer only — it wires `~/.claude/hooks/*` to Claude Code events
- After adding a new hook to the registry, add its wiring entry here
- Hook paths always use `~/.claude/hooks/` (global runtime, not project-relative)
- The Stop hook path points directly to `.cortex/core/hooks/runtime/stop-build.sh` (absolute path)

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

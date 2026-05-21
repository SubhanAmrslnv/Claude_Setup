# CLAUDE.md

Operating guidance for Claude Code working inside Cortex. **Read this first, every session.**

Cortex is an event-driven, project-local AI runtime that lives entirely under `.claude/`. For *what it is and how the pieces fit together*, read `README.md`. This file tells you **what to do**.

---

## Invariants (hard rules — do not violate)

1. **Project-local only.** `CORTEX_ROOT` resolves to `$CORTEX_ROOT` or `$(pwd)/.claude`. Never fall back to `$HOME`.
2. **Hooks exit 0 unless the Claude Code contract requires otherwise.** Status-line and event subscribers always exit 0 — a non-zero exit crashes Claude Code's render loop. Guards (`PreToolUse`) exit 1 only to block the tool call per Claude Code's contract; on internal errors they still emit a diagnostic and `exit 0`.
3. **Source bootstrap defensively** in every shell script under `core/`: `source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0`.
4. **No SessionStart hook ever.** Cortex is lazy by design. Do not propose preloading project context.
5. **`prompt-router.sh` labels intent only.** Never inject content into the user prompt.
6. **Version bump + registry sync are one change.** Editing a versioned script (`# @version: X.Y.Z` on line 2) requires bumping that line *and* the matching entry in `.claude/registry/hooks.json` in the same edit pass. The status line counts drift between disk and registry.
7. **Never commit unless the user uses an explicit trigger phrase:** `commit`, `commit this`, `commit changes`, `/commit`, or `commit and push`. `"looks good"`, `"ship it"`, `"finalize"` do not authorize a commit. End-of-task pauses do not authorize a commit.
8. **Never `git checkout -b` without explicit instruction.** Stay on the current branch. The user manages branching.
9. **No Claude/Anthropic attribution in commits. No 🤖 emoji.** `pre-guard.sh` enforces conventional-commit format: `type(scope): message`.
10. **Do not work around `pre-guard.sh` blocks.** If risk ≥ block threshold (default 70), surface to the user — do not retry with an alternative tool.

---

## Operating Loop (read → plan → edit → verify)

For every non-trivial change, run this loop:

1. **Locate before reading.** For "find files relevant to X" tasks, call `bash .claude/core/memory/retrieve.sh <intent> "<query>"` first. Use `Grep` only when you know the literal string. Use `Glob` for path patterns. Never `find` / `ls`.
2. **Plan when scope is multi-file or architectural.** Write a plan to `*/plans/<slug>.md`. The `FileChanged` event auto-persists it via `core/memory/plans-watcher.sh` — no manual save needed. Inspect saved plans with `bash .claude/core/memory/plans.sh list`.
3. **Edit on the current branch.** Prefer `Edit` over `Write` for existing files. Batch independent reads in one parallel tool message.
4. **Sync invariants in the same edit pass.** If you touched a versioned script, the same edit must also bump `registry/hooks.json`. If you touched a subscriber, the same edit must also update `core/events/subscriptions.json`. If you added a scanner, the same edit must also update `registry/scanners.json` *and* the installer's language detection in `scripts/lib/install-core.sh`.
5. **Smoke-test before declaring done.**
   - All hooks: `bash .claude/test/run.sh`
   - One hook in isolation: `echo '<json>' | bash .claude/core/hooks/.../<hook>.sh`
   - Status line: `bash .claude/core/statusline/render.sh < /dev/null`
6. **Wait for async work.** `FileChanged` subscribers (`post-format.sh`, `post-scan.sh`) run async via the dispatcher. Confirm `📨 Events 0` on the status line before claiming the change is settled.
7. **On Windows, preserve the executable bit** if you `Write` a fresh script: `chmod +x` after writing. POSIX-only repos break without it.

---

## Decision Tables

### When `post-scan.sh` flags a finding in code you just wrote
| Step | Action |
|---|---|
| 1 | Read the scanner output (in the FileChanged subscriber result). |
| 2 | Fix the finding at the source. Never suppress, never disable the scanner. |
| 3 | Re-edit the file to re-trigger the scan. |
| 4 | Do not commit until the next scan returns clean. |

### When editing a hook — what version bump?
| Change | Bump |
|---|---|
| Behavior-preserving fix, internal cleanup | patch (`2.4.1 → 2.4.2`) |
| New branch, new flag, new exit code, behavior-preserving extension | minor (`2.4.1 → 2.5.0`) |
| Breaking JSON contract, removed flag, changed input/output shape | major (`2.4.1 → 3.0.0`) |
| Update `.claude/registry/hooks.json` in the *same* edit | every change |

### Adding a scanner for `.<ext>`
| Step | Action |
|---|---|
| 1 | Drop the script under `.claude/core/scanners/<language>/`. Make it emit JSON on stdout, exit 0 always. |
| 2 | Add `.<ext> → [<language>/<script>]` to `.claude/registry/scanners.json`. |
| 3 | If `<language>` is new, update language detection in `scripts/lib/install-core.sh`. |
| 4 | Smoke-test: `echo '{"file":"sample.<ext>"}' \| bash .claude/core/hooks/runtime/post-scan.sh`. |

### Hook fails in CI but works locally
| Check | Why |
|---|---|
| `jq --version` available on PATH | Every hook parses JSON via `jq`. Missing `jq` ⇒ silent no-op. |
| CRLF line endings | Windows-checkout into Linux CI breaks shebangs. Run `dos2unix` or set `.gitattributes`. |
| `$CORTEX_ROOT` is correct | CI may run from a different cwd. Pass it explicitly. |
| Executable bit on `core/**/*.sh` | Lost on Windows checkout. Installer applies `chmod +x`; raw clones may not. |

### User asks to "make Cortex faster"
Measure first. Do not refactor without a baseline.
1. Run `time bash .claude/core/statusline/render.sh < sample.json` and `time bash .claude/core/hooks/runtime/prompt-router.sh < sample.json` to identify the slow hook.
2. Inspect `.claude/logs/` for dispatcher fan-out timing.
3. Refactor the specific slow path. Re-measure. Report delta.

---

## Failure-Mode Playbook

| Symptom | Response |
|---|---|
| `pre-guard.sh` blocks a command (risk ≥ block threshold) | Surface to user. Do **not** route around with a different tool. |
| `post-scan.sh` finds a CVE in your edit | Fix at source, re-edit to re-trigger. Never suppress. |
| `post-error-analyzer.sh` produced classification output | Read it *before* proposing the fix. The classifier names the failure category. |
| `stop-build.sh` retried and failed | Surface to user. Do not silently retry again. |
| A hook script itself errors | Check `.claude/logs/`. Never disable a hook in `settings.json`. Investigate, fix, version-bump. |
| Status line shows `🪝 Hooks 12/28` | Registry/disk drift. Re-run the installer or sync `registry/hooks.json` to the on-disk scripts. |
| Status line shows `│ Cortex │ —` fallback | Bootstrap failed — usually missing `jq` or wrong `CORTEX_ROOT`. Inspect: `bash .claude/core/statusline/render.sh < /dev/null`. |
| `📨 Events 5+` persisting between turns | Dispatcher is failing silently. Inspect `.claude/logs/`, then `rm .claude/temp/events/*.json` once root cause is fixed. |

---

## Hook Surface (events wired to Claude Code)

| Event                          | Wired to                                            | Current version |
|--------------------------------|-----------------------------------------------------|-----------------|
| `statusLine`                   | `core/statusline/render.sh`                         | —               |
| `PreToolUse` (Bash)            | `guards/pre-guard.sh`                               | 2.5.0           |
| `PermissionRequest`            | `guards/permission-request.sh`                      | 1.3.0           |
| `PermissionDenied`             | `guards/permission-denied.sh`                       | 1.3.0           |
| `UserPromptSubmit`             | `runtime/prompt-router.sh`                          | 1.1.0           |
| `PostToolUse` (Write\|Edit)    | `events/bus.sh publish FileChanged`                 | —               |
| `PostToolUseFailure`           | `runtime/post-error-analyzer.sh`                    | 1.2.0           |
| `Stop`                         | `runtime/stop-build.sh`                             | 1.5.1           |

**Why `🪝 Hooks 28/28` and not `8/8`.** `settings.json` wires the 8 entries above to Claude Code events. `.claude/registry/hooks.json` tracks all 28 framework scripts (event hooks + dispatcher + planner + router + memory + debug + statusline) — the status-line metric counts *registered scripts that exist on disk*, not Claude Code events. The gap means the installer also verifies internal utilities, not just event handlers.

Subscribers for the async `FileChanged` event live in `.claude/core/events/subscriptions.json`: `post-format.sh`, `post-scan.sh`, `memory/plans-watcher.sh`. To add one, edit that JSON — no `settings.json` change needed.

---

## Status Line — diagnostic surface

What you see under the chatbox is live state, not cached. Read it when something feels off:

- `🪝 Hooks X/28` where `X < 28` ⇒ registry/disk drift. Re-run installer.
- `📜 Commands X/2` where `X < 2` ⇒ a command markdown file is missing from `.claude/commands/`.
- `📨 Events N` non-zero between turns ⇒ dispatcher stuck.
- `📂 Indexed 0` after a memory retrieve ⇒ the lazy index failed to build. Inspect `.claude/cache/file-index.txt` and `.claude/logs/`.
- `│ Cortex │ —` (single-line fallback) ⇒ bootstrap failed. Almost always missing `jq` or wrong `CORTEX_ROOT`.

The status line never writes to disk and always exits 0 — bugs surface as anomalies in the rendered values, never as crashes.

---

## Tooling & Efficiency

- **Use `retrieve.sh` for semantic discovery** — "find files relevant to <intent>". Use `Grep` only when you know the literal string. Use `Glob` for path patterns. Never `find` / `ls` from `Bash`.
- **Batch independent tool calls in one message.** After a `retrieve.sh` call returns 5 candidates, parallel-read all 5 in a single tool message.
- **For conceptual questions**, retrieve's 3-line summaries may suffice. Open the file only when you need to change it.
- **Prefer `Edit` over `Write`** for existing files. `Write` overwrites; `Edit` produces a reviewable diff.
- **Lead with the action.** No preamble. No trailing summary unless the user explicitly asks.

---

## Install / Update / Validate

Four supported paths, all idempotent and identical in effect. Pick what's available:

```bash
# 1. curl (Linux / macOS / Git Bash)
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash

# 2. PowerShell (Windows)
iwr -useb https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.ps1 | iex

# 3. Manual sparse clone (no installer)
git clone --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp \
  && git -C .cortex-tmp sparse-checkout set .claude \
  && cp -R .cortex-tmp/.claude . && rm -rf .cortex-tmp

# 4. npx (wraps the curl flow; requires Node 18+, bash, git)
npx @subhanamrslnv/cortex-cli init
npx @subhanamrslnv/cortex-cli update
npx @subhanamrslnv/cortex-cli doctor
```

Full details, prerequisites, and troubleshooting are in `INSTALL.md`. The in-Claude `/init-cortex` and `/update-cortex` slash commands were removed in vNext.

---

## Working in This Repo

### Edit a hook
1. Bump `# @version: X.Y.Z` on line 2 (see version-bump table above).
2. Bump the matching `version` field in `.claude/registry/hooks.json` in the same edit.
3. Smoke-test: `bash .claude/test/run.sh` or pipe a sample JSON to the hook directly.

### Add a subscriber
1. Drop the script under `.claude/core/<area>/`.
2. Add it to the relevant event array in `.claude/core/events/subscriptions.json`.
3. No `settings.json` change.

### Add a planner-runnable task
1. Drop the script under `.claude/core/<area>/`. It must emit JSON on stdout, exit 0 on success, non-zero on failure.
2. Reference it from `planner-engine.sh` (a new intent's DAG, or by extending an existing one).

### Add a scanner
See the Decision Table above.

### Add a command
1. Create `<name>.md` under `.claude/commands/`.
2. Append the name to `.claude/registry/commands.json`.

### Slash commands (live in-Claude)
| Command   | Purpose                                                          |
|-----------|------------------------------------------------------------------|
| `/debug`  | Runtime-aware self-healing debugger (5 parallel probes).         |
| `/commit` | Conventional commit with branch warning for `main`/`master`/`develop`. |

---

## Git Policy

- **Edit on the current branch.** Never `git checkout -b` without an explicit instruction.
- **Never commit unless the user uses a trigger phrase** (see Invariant #7).
- When the user does ask: `/commit` warns on `main`/`master`/`develop` and asks `y/n` before proceeding. `pre-guard.sh` adds +20 risk to pushes on those branches.
- Conventional commits only: `type(scope): message`. Types: `feat`, `fix`, `refactor`, `docs`, `chore`, `test`, `style`, `perf`. No Claude attribution.

---

## Response Format & Tone

- Direct and concise — one sentence beats three.
- Technical depth expected; do not over-explain basics.
- Call out security or correctness risks when present.
- No boilerplate filler. No trailing summaries.

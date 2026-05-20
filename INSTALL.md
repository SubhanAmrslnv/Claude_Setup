# Installing Cortex

Cortex is an event-driven, project-local AI runtime framework for [Claude Code](https://claude.ai/code). It lives entirely inside each project's `.claude/` directory — **no global install, no shared state, no startup profiling.** Every project gets its own pinned copy and its own hook, planner, memory, router, and status-line setup.

---

## Prerequisites

| Tool | Required | Why |
|---|---|---|
| `bash` 4+ | yes | All hook scripts and core logic |
| `jq` | yes | Every hook parses JSON via `jq`; without it hooks silently no-op |
| `git` | yes | Branch protection + status-line metrics |
| `curl` | yes (curl/PowerShell paths) | Fetches the skeleton + scanners |
| Node 18+ | yes (npx path only) | Powers the `cortex` CLI |
| [Claude Code](https://claude.ai/code) | yes | Hook + command runtime |

**Install `jq`:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows — Scoop
scoop install jq

# Windows — winget
winget install jqlang.jq
```

Verify: `jq --version`.

On Windows, use **Git Bash** (ships with [Git for Windows](https://git-scm.com/)) or WSL. PowerShell users still need bash available — the PowerShell installer wraps a bash core.

---

## Install

Pick one. All three paths run the same installer core and produce identical output.

### 1. curl (Linux / macOS / Git Bash)
```bash
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash
```

### 2. PowerShell (Windows)
```powershell
iwr -useb https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.ps1 | iex
```
Requires bash on PATH (`Git for Windows` is enough).

### 3. npx (any OS with Node 18+)
```bash
npx @subhanamrslnv/cortex-cli init
```

### Override the branch
```bash
curl -fsSL .../install.sh | bash -s -- --ref=feat/vnext
```

---

## What the installer does

1. **Language detection** — scans the current directory for: `package.json`, `*.csproj`/`*.sln`, `go.mod`, `Cargo.toml`, `pyproject.toml`/`requirements.txt`/`setup.py`, `pom.xml`/`build.gradle`, `Dockerfile*`, `*.tf`, `*.sh`. Each match adds one language to the keep-set.
2. **Skeleton fetch** — pulls `settings.json`, all registry files, the shared bootstrap, every guard, the runtime hooks (prompt-router, post-format, post-scan, post-error-analyzer, stop-build), the event bus + dispatcher, the planner, the model router, memory, the seven debug probes, the status-line renderer, the four commands (`init-cortex`, `update-cortex`, `debug`, `commit`), and the four project memory stubs.
3. **Language-aware scanners** — fetches only `core/scanners/<lang>/` for detected languages plus `generic/`. The current shipped set is: `bash`, `docker`, `dotnet`, `generic`, `node` (covers JS/TS/JSX/TSX/Vue/Svelte/HTML/CSS/SCSS), `powershell`, `python`, `sql`.
4. **Local-only directories** — creates `cache/`, `logs/`, `temp/events/`, `state/` under `.claude/`.
5. **Executable bits** — `chmod +x` on every shell script (POSIX systems).

Idempotent: re-running upgrades in place. `cache/`, `logs/`, `temp/`, `state/`, and `project/memory/` are never overwritten by the installer.

---

## Activate

`npx @subhanamrslnv/cortex-cli init` already validates and prunes — open Claude Code and you're ready. There is no in-Claude activation step.

What `init` checks at the end of an install:
- Every hook listed in `.claude/registry/hooks.json` exists on disk.
- Every command listed in `.claude/registry/commands.json` has a matching `.claude/commands/<name>.md`.
- `.claude/settings.json` has a `hooks` block wiring real scripts.
- Scanner directories for languages not in the active set are pruned.
- Local-only directories (`cache/`, `logs/`, `temp/events/`, `state/`, `project/memory/plans/`) exist.

If validation surfaces issues (e.g. a hook from the registry didn't land on disk), `init` exits non-zero and tells you to re-run `cortex update`.

---

## Verify

**Quick local check (no network):**
```bash
npx @subhanamrslnv/cortex-cli doctor
```

**Status-line check** — open Claude Code in the project. You should see a five-line block under the chatbox:
```
Cortex v4.0.0 │ Opus 4.7 │ ⏱ 0s
  ─────────────────────────────────────────────────────
  🪝 Hooks 28/28    📜 Commands 4/4    🔎 Scanners 14    🛡️ Risk 30/70
  💾 Memory 17KB    📨 Events 0    📂 Indexed 0    📑 Audit 0    🧠 Context 0%
  📊 Tests 0 (~0 cases)    🗂️ Plans 0    🌿 main clean
```
If you only see a single `│ Cortex │ —` fallback line, something failed bootstrap — most often a missing `jq` or a wrong `CORTEX_ROOT`. Inspect with:
```bash
bash .claude/core/statusline/render.sh < /dev/null
```

**Hook smoke test:**
```bash
bash .claude/test/run.sh
```

---

## Update

```bash
# npx (recommended)
npx @subhanamrslnv/cortex-cli update

# curl re-run (same as install — installer is idempotent)
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash
```

Updates touch only the skeleton files. Anything under `.claude/cache/`, `.claude/logs/`, `.claude/temp/`, `.claude/state/`, and `.claude/project/memory/` is preserved. There is no in-Claude `/update-cortex` slash command — npx is the single source of truth.

---

## Uninstall

```bash
rm -rf .claude
```

There is no other state to clean. Cortex never writes outside the project directory.

---

## Configuration

`.claude/config/cortex.config.json` (v4.0.0):
```json
{
  "riskThresholds":  { "warn": 30, "block": 70 },
  "modelPolicy":     { "default": "sonnet", "intents": { ... 32 keys ... } },
  "eventBus":        { "maxJobs": 4 },
  "planner":         { "maxJobs": 4 },
  "memory":          { "indexMaxAgeSeconds": 3600 },
  "debug":           { "expectedPorts": [...], "logPaths": [...] },
  "statusLine":      { "contextWindow": 200000 }
}
```

| Key | Effect |
|---|---|
| `riskThresholds.warn/block` | Pre-tool risk score thresholds (used by `pre-guard.sh`) |
| `modelPolicy.intents` | Per-intent model choice for the router |
| `eventBus.maxJobs` | Max parallel subscribers per event |
| `planner.maxJobs` | Worker-pool concurrency cap |
| `memory.indexMaxAgeSeconds` | Lazy index rebuild interval |
| `debug.expectedPorts` | Ports that `process-inspector.sh` checks |
| `debug.logPaths` | Glob patterns for `log-stream.sh` |
| `statusLine.contextWindow` | Override the 200k/1M auto-detect for context % |

---

## Troubleshooting

**Status line shows `│ Cortex │ —`** — bootstrap failed. Run `cortex doctor` to find the missing file. Most common causes: `jq` not on PATH, or the project moved and `.claude/` wasn't carried over.

**Hooks count low** (e.g. `🪝 Hooks 12/28`) — some script files in the registry don't exist on disk. Run `npx @subhanamrslnv/cortex-cli update` to re-fetch.

**Context % stuck at `—`** — Claude Code didn't pass `transcript_path` in the session JSON. This happens during synthetic tests; in a real session it always populates.

**Events count keeps growing** — the dispatcher's subscribers are erroring and never deleting consumed events. Clear with `rm .claude/temp/events/*.json` and check `dispatcher.sh` stderr (write to a file in `.claude/logs/`).

**MSYS / Git Bash CRLF issue** — handled by the renderer (`tr -d '\r'`), but if you write your own hook that reads `jq` output on Windows, strip CR yourself.

**Strict project-local** — Cortex never falls back to `$HOME/.claude/`. If `.claude/` is missing at `$(pwd)`, every hook exits 0 silently. Don't symlink — copy or re-install.

---

## Branch Protection

Cortex's `pre-guard.sh` adds +20 risk for `git push`/`commit` against `main`, `master`, or `develop`. Combined with the default threshold of 70, this won't block a single commit, but it will warn. **Always work on a feature branch and open a PR.**

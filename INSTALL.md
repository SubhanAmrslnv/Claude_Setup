# Installing Cortex

Cortex is an event-driven, project-local AI runtime framework for [Claude Code](https://claude.ai/code). It lives entirely inside each project's `.claude/` directory — **no global install, no shared state, no startup profiling.** Every project gets its own pinned copy and its own hook, planner, memory, router, and status-line setup.

---

## Prerequisites

| Tool | Required | Why |
|---|---|---|
| `bash` 4+ | yes | All hook scripts and core logic |
| `git` | yes | Installer clones the repo; branch protection + status-line metrics |
| `jq` | yes | Every hook parses JSON via `jq`; without it hooks silently no-op at runtime |
| `curl` | yes (curl/PowerShell paths) | Fetches `install-core.sh` |
| [Claude Code](https://claude.ai/code) | yes | Hook + command runtime |

**Install `jq`** (runtime requirement for hooks, not the installer):
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

Verify: `jq --version` and `git --version`.

On Windows, use **Git Bash** (ships with [Git for Windows](https://git-scm.com/)) or WSL. PowerShell users still need bash available — the PowerShell installer wraps a bash core.

---

## Install

Pick one. All paths produce an identical `.claude/` under the current directory.

### 1. curl (Linux / macOS / Git Bash)
```bash
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash
```

### 2. PowerShell (Windows)
```powershell
iwr -useb https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.ps1 | iex
```
Requires bash on PATH (`Git for Windows` is enough).

### 3. Manual git sparse clone (no installer)

Run from the root of the project where you want `.claude/` to land.

**Bash (Linux / macOS / Git Bash), requires git 2.27+:**
```bash
git clone --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
cp -R .cortex-tmp/.claude .
rm -rf .cortex-tmp
```

One-liner:
```bash
git clone --depth 1 --filter=blob:none --sparse --branch main https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp && git -C .cortex-tmp sparse-checkout set .claude && cp -R .cortex-tmp/.claude . && rm -rf .cortex-tmp
```

**PowerShell (Windows):**
```powershell
git clone --depth 1 --filter=blob:none --sparse --branch main https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
Copy-Item .cortex-tmp/.claude . -Recurse -Force
Remove-Item .cortex-tmp -Recurse -Force
```

**No-git fallback (tarball, any POSIX shell):**
```bash
curl -fsSL https://codeload.github.com/SubhanAmrslnv/Cortex/tar.gz/refs/heads/main \
  | tar -xz --strip-components=1 Cortex-main/.claude
```

### Override the branch
```bash
curl -fsSL .../install.sh | bash -s -- --ref=feat/vnext
```
Or, for the manual clone, change `--branch main` to your target ref.

---

## What the installer does

1. **Sparse clone** — `git clone --depth 1 --filter=blob:none --sparse --branch main https://github.com/SubhanAmrslnv/Cortex.git` into a temp dir, then `git sparse-checkout set .claude` so only `.claude/` is materialised.
2. **Overlay copy** — copies `.claude/` from the clone into the target project. User-local subtrees (`project/memory/`, `cache/`, `logs/`, `temp/`, `state/`) are preserved untouched if they already exist.
3. **Local-only directories** — ensures `cache/`, `logs/`, `temp/events/`, `state/`, and `project/memory/plans/` exist under `.claude/`.
4. **Executable bits** — `chmod +x` on every shell script under `core/` (POSIX systems).

Idempotent: re-running upgrades in place. `cache/`, `logs/`, `temp/`, `state/`, and `project/memory/` are never overwritten by the installer.

Override the source with `CORTEX_REPO_URL=https://github.com/<fork>/Cortex.git` or `CORTEX_REF=<branch|tag|sha>`.

---

## Activate

Once `.claude/` is in place, open Claude Code in the project — there is no separate activation step.

---

## Verify

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

Re-run any of the install paths — they are idempotent.

```bash
# curl
curl -fsSL https://raw.githubusercontent.com/SubhanAmrslnv/Cortex/main/scripts/install.sh | bash

# Manual sparse clone (overwrite in place)
git clone --depth 1 --filter=blob:none --sparse --branch main \
  https://github.com/SubhanAmrslnv/Cortex.git .cortex-tmp
git -C .cortex-tmp sparse-checkout set .claude
cp -R .cortex-tmp/.claude .
rm -rf .cortex-tmp
```

Updates via the scripted installers touch only the framework files. Anything under `.claude/cache/`, `.claude/logs/`, `.claude/temp/`, `.claude/state/`, and `.claude/project/memory/` is preserved. The raw manual clone overwrites `.claude/` wholesale — back up user-local state first if you go that route.

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

**Status line shows `│ Cortex │ —`** — bootstrap failed. Most common causes: `jq` not on PATH (runtime requirement for hooks), or the project moved and `.claude/` wasn't carried over. Inspect with `bash .claude/core/statusline/render.sh < /dev/null`.

**Hooks count low** (e.g. `🪝 Hooks 12/28`) — some script files in the registry don't exist on disk. Re-run the installer to re-fetch.

**Context % stuck at `—`** — Claude Code didn't pass `transcript_path` in the session JSON. This happens during synthetic tests; in a real session it always populates.

**Events count keeps growing** — the dispatcher's subscribers are erroring and never deleting consumed events. Clear with `rm .claude/temp/events/*.json` and check `dispatcher.sh` stderr (write to a file in `.claude/logs/`).

**MSYS / Git Bash CRLF issue** — handled by the renderer (`tr -d '\r'`), but if you write your own hook that reads `jq` output on Windows, strip CR yourself.

**Strict project-local** — Cortex never falls back to `$HOME/.claude/`. If `.claude/` is missing at `$(pwd)`, every hook exits 0 silently. Don't symlink — copy or re-install.

---

## Branch Protection

Cortex's `pre-guard.sh` adds +20 risk for `git push`/`commit` against `main`, `master`, or `develop`. Combined with the default threshold of 70, this won't block a single commit, but it will warn. **Always work on a feature branch and open a PR.**

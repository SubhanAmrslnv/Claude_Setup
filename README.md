# Cortex — Claude Code Global Configuration

A modular, registry-driven DevOps framework for [Claude Code](https://claude.ai/code).
Covers intelligent prompt optimization, session profiling, risk-scored security guards, permission recovery, auto-formatting, code intelligence, audit logging, and behavior rules for .NET (C#) and Node/React projects.

---

## Prerequisites

| Tool | Required | Purpose |
|---|---|---|
| `jq` | **Yes** | JSON parsing in every hook — without it all hooks silently no-op |
| `bash` 4.0+ | Yes | All hook scripts |
| `node` 16+ | Yes | `post-code-intel.sh` code intelligence |
| `git` | Yes | Branch detection, commit guard |
| [Claude Code](https://claude.ai/code) | Yes | Hook and command runtime |

**Install `jq`:**
```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt install jq

# Windows — Scoop (recommended)
scoop install jq

# Windows — winget
winget install jqlang.jq
```

Verify: `jq --version`

---

## Repository Layout

```
.cortex/                              ← framework root (all logic lives here)
  core/
    hooks/
      guards/
        pre-guard.sh                  ← PreToolUse risk-scoring engine (v2.0.0)
        permission-request.sh         ← PermissionRequest enricher
        permission-denied.sh          ← PermissionDenied safe-recovery engine
      runtime/
        post-format.sh                ← registry-driven formatter dispatcher (v2.1.0)
        post-scan.sh                  ← registry-driven security scanner dispatcher (v2.1.0)
        post-audit-log.sh             ← audit logger
        post-code-intel.sh            ← code intelligence analyzer (Node.js)
        stop-build.sh                 ← build failure reporter
        session-start.sh              ← SessionStart project profiler
        prompt-optimizer.sh           ← UserPromptSubmit structured prompt engine
    runtime/
      command-runner.sh               ← registry-driven command validator/dispatcher
    scanners/
      dotnet/security-scan.sh         ← unsafe .NET API detection
      dotnet/format.sh                ← dotnet format wrapper
      node/react-security-scan.sh     ← XSS pattern detection for JS/TS/JSX/TSX
      node/format.sh                  ← Prettier + ESLint wrapper
      generic/secret-scan.sh          ← hardcoded secret detection (all file types)
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
  cache/
    project-profile.json              ← generated at session start; consumed by prompt optimizer
  base/                               ← remote Cortex content (updated by /update-cortex)
  local/                              ← project-local overrides (never overwritten)
.claude/
  settings.json                       ← adapter only: wires ~/.cortex/core/hooks/* to Claude Code
  commands/                           ← thin wrappers; delegate to .cortex/commands/
CLAUDE.md
README.md
INSTALL.md
```

---

## Hooks

All hooks run directly from `~/.cortex/core/hooks/`. Hook paths in `settings.json` follow `~/.cortex/core/hooks/<subdir>/<filename>`.

| Event | Hook | What it does |
|---|---|---|
| `PreToolUse (Bash)` | `guards/pre-guard.sh` | Risk-scoring engine — scores command across 6 categories, warns or blocks |
| `PermissionRequest` | `guards/permission-request.sh` | Enriches approval prompts with intent, risks, and safer alternatives |
| `PermissionDenied` | `guards/permission-denied.sh` | Generates a safe alternative command and decides whether retry is possible |
| `SessionStart` | `runtime/session-start.sh` | Detects project type, extracts metadata, writes `.cortex/cache/project-profile.json` |
| `UserPromptSubmit` | `runtime/prompt-optimizer.sh` | Detects intent, finds relevant files, extracts code snippets, outputs structured prompt |
| `PostToolUse (Write\|Edit)` | `runtime/post-format.sh` | Registry-driven: dispatches to formatters by file extension |
| `PostToolUse (Write\|Edit)` | `runtime/post-scan.sh` | Registry-driven: dispatches to security scanners by file extension |
| `PostToolUse (Write\|Edit)` | `runtime/post-code-intel.sh` | Analyzes modified files for complexity, duplication, naming, and structure issues |
| `PostToolUse (Write\|Edit\|Bash)` | `runtime/post-audit-log.sh` | Appends every tool use to `~/.claude/audit.log` |
| `Stop` | `runtime/stop-build.sh` | Builds project; prints errors on failure — does NOT auto-fix |

---

## Hook Details

### Risk-Scored Security Guard (`pre-guard.sh` v2.0.0)

Replaces flat pattern-blocking with a numeric risk engine. Accumulates a score across 6 categories:

| Category | Examples | Points |
|---|---|---|
| Destructive | `rm -rf`, `DROP TABLE`, `git reset --hard`, `git clean -f` | +50 each |
| Privileged | `sudo`, write to `/etc /usr /bin /sys` | +30 each |
| Dangerous flags | `--force`, `--no-verify` | +20 each |
| Security threats | curl\|sh, base64 exec, reverse shell, exploit tools | +40 each |
| Sensitive files | `.env .pem .key .pfx` | +25 |
| Protected branch | `main / master / develop` (git commands only) | +20 |

**Thresholds:** `risk < 30` → allow silently · `30–69` → allow with JSON warning · `≥ 70` → block with reason + suggestion.

---

### Permission System (`permission-request.sh` + `permission-denied.sh`)

**PermissionRequest** — fires before the user sees an approval dialog. Outputs structured JSON:
```json
{
  "intent": "git_operation",
  "explanation": "This command pushes local commits to a remote repository.",
  "risks": ["data loss: --force may overwrite or destroy remote state"],
  "suggestion": "Use 'git push --force-with-lease' instead",
  "requiresConfirmation": true
}
```

**PermissionDenied** — fires after denial. Transforms the unsafe command into a safe alternative and signals whether a retry is appropriate:
```json
{
  "retry": true,
  "originalCommand": "git push --force origin main",
  "safeCommand": "git push --force-with-lease origin main",
  "reason": "unsafe flag: --force can silently overwrite remote commits",
  "message": "Replaced '--force' with '--force-with-lease'."
}
```

Safe transformations include: `rm -rf` → `rm -ri`, `git reset --hard` → `git stash`, `curl|sh` → download + inspect, `--no-verify` removed, `sudo` stripped. Exploit tools and reverse shells are never retried.

---

### Session Profiler (`session-start.sh`)

Runs automatically when a session begins. Detects project type (dotnet > node > python priority), extracts:
- **Dependencies** — `PackageReference` from `.csproj`, keys from `package.json`, lines from `requirements.txt`
- **Entry points** — `Program.cs`, `index.ts`, `main.py`, etc.
- **Structure** — notable directories (`src`, `api`, `services`, `tests`, `config`, etc.)

Writes `.cortex/cache/project-profile.json`. Idempotent — skips rewrite if project files are unchanged (fingerprinted via mtime checksum). Output consumed by the prompt optimizer.

---

### Prompt Optimizer (`prompt-optimizer.sh`)

Intercepts every user prompt via the `UserPromptSubmit` hook (reads from stdin). Pipeline:

1. **Normalize** — trim whitespace; expand prompts under 20 chars with `"Clarify and resolve: ..."`
2. **Detect intent** — `bug_fix` / `feature_request` / `refactor` / `question`
3. **Find relevant files** — keyword matching on CamelCase identifiers, stack-trace path extraction, naming heuristics (`auth`, `service`, `controller`, `handler`, etc.)
4. **Extract snippets** — ±20 lines around the best keyword match per file (max 5 files)
5. **Load project profile** — reads `.cortex/cache/project-profile.json` for project type
6. **Output structured prompt** — replaces the raw prompt with context + code snippets + intent + constraints

---

### Code Intelligence (`post-code-intel.sh`)

Runs after every `Write` or `Edit` on `.cs .js .ts .jsx .tsx` files ≤ 1MB. Four lightweight regex-based checks:

| Check | Mechanism | Threshold |
|---|---|---|
| Method length | Brace-depth tracking from declaration | > 50 lines |
| Nesting depth | Live `{}` counter at conditional keywords | depth > 3 |
| Duplication | MD5 of 8-line sliding window (normalized) | Same hash ≥ 8 lines apart |
| Naming | Declaration regex vs. set of non-descriptive names | Capped at 3 per file |
| Structure | Line count + UI×DB keyword cross-detection | > 500 lines or mixed concerns |

Outputs structured JSON to stdout. Never modifies files.

---

### Registry-Driven Dispatch (`post-format.sh` + `post-scan.sh`)

Both hooks contain zero language-specific logic. All extension→scanner mappings live in `.cortex/registry/scanners.json`:

```json
{
  ".cs":   ["dotnet/security-scan.sh", "dotnet/format.sh"],
  ".ts":   ["node/react-security-scan.sh", "node/format.sh"],
  ".tsx":  ["node/react-security-scan.sh"],
  ".js":   ["node/react-security-scan.sh"],
  ".jsx":  ["node/react-security-scan.sh"],
  ".html": ["node/format.sh"],
  ".scss": ["node/format.sh"],
  "*":     ["generic/secret-scan.sh"]
}
```

To add a new language: add an entry to `scanners.json` and create the scanner script. No hook changes required.

---

## Custom Commands

| Command | Description |
|---|---|
| `/init` | Version-aware hook deployment, registry validation, settings check |
| `/commit` | Interactive conventional commit with branch routing |
| `/doctor` | Full system diagnostics — checks hooks, settings, registry, scanners |
| `/update-cortex` | Safely update `.cortex/base/` from remote with diff preview |

Command wrappers in `.claude/commands/` are thin delegates. All logic lives in `.cortex/commands/`.

---

## Safe Update System

- **`base/`** — canonical framework files from the remote Cortex repo. Updated by `/update-cortex`.
- **`local/`** — project-specific overrides. Never touched by any automated process.

`/update-cortex` fetches changes, shows a diff, asks for confirmation, updates only `base/`, then re-runs `/init` to redeploy updated hooks.

---

## Deploying Hook Changes

1. Edit the source hook in `.cortex/core/hooks/`
2. Increment `# @version: X.Y.Z` on line 2
3. Update the version in `.cortex/registry/hooks.json`
4. Copy `.cortex/` to `~/.cortex/` (or run `/init`)

`/init` version-compares source vs runtime and deploys only what changed.

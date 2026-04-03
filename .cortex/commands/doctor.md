You are acting as a senior code auditor. Run TWO diagnostic passes: Cortex system diagnostics, then project code diagnostics. DO NOT fix anything automatically. Report all issues, then ask the user for permission before touching any file.

---

# PHASE 1 — CORTEX SYSTEM DIAGNOSTICS

## Step 1 — Locate Cortex root

Read `~/.claude/cortex.env`.

- Missing: record ERROR "[CORTEX] cortex.env not found — run /init" and skip to Phase 1 Output.
- Found: extract `CORTEX_ROOT`. Use it as the base for all Phase 1 paths.

Define these base paths for all checks below:
- `CORTEX_DIR` = `$CORTEX_ROOT/.cortex`
- `HOOKS_SRC` = `$CORTEX_DIR/core/hooks`
- `SCANNERS_SRC` = `$CORTEX_DIR/core/scanners`
- `REGISTRY` = `$CORTEX_DIR/registry`
- `CONFIG` = `$CORTEX_DIR/config`
- `COMMANDS_DIR` = `$CORTEX_ROOT/.claude/commands`
- `RUNTIME_HOOKS` = `~/.claude/hooks`

## Step 2 — Folder structure check

Verify the following paths exist:

| Path | Required |
|---|---|
| `$CORTEX_DIR/core/` | YES |
| `$CORTEX_DIR/core/hooks/` | YES |
| `$CORTEX_DIR/core/scanners/` | YES |
| `$CORTEX_DIR/registry/` | YES |
| `$CORTEX_DIR/config/` | YES |
| `$CORTEX_ROOT/.claude/commands/` | YES |

Missing path → ERROR "[CORTEX] Required folder missing: <path>"

## Step 3 — Registry validation

Read and validate all three registry files.

### commands.json (`$REGISTRY/commands.json`)

- File missing → ERROR "[CORTEX] commands.json not found"
- For each command name in the `commands` array: check `$COMMANDS_DIR/<name>.md` exists
  - Missing → ERROR "[CORTEX] Command '<name>' in registry but .claude/commands/<name>.md not found"

### hooks.json (`$REGISTRY/hooks.json`)

- File missing → ERROR "[CORTEX] hooks.json not found"
- For each entry: check `$CORTEX_DIR/<source>` exists
  - Missing → ERROR "[CORTEX] Hook source file missing: <source>"
- Malformed entry (missing `version` or `source` field) → ERROR "[CORTEX] Malformed hooks.json entry: <key>"

### scanners.json (`$REGISTRY/scanners.json`)

- File missing → ERROR "[CORTEX] scanners.json not found"
- For each extension key and each scanner path in its array: check `$CORTEX_ROOT/.cortex/core/scanners/<path>` exists
  - Missing → WARNING "[CORTEX] Scanner file missing: <path>"

## Step 4 — Hook validation

For each hook in hooks.json:

a. Source exists at `$CORTEX_DIR/<source>`:
   - Missing → ERROR "[CORTEX] Hook source not found: <source>"

b. Deployed at `$RUNTIME_HOOKS/<hook-name>`:
   - Missing → ERROR "[CORTEX] Hook not deployed: <hook-name> — run /init"

c. Version tag `# @version: X.Y.Z` present in source (line 1 or 2):
   - Missing → WARNING "[CORTEX] Hook has no version tag: <hook-name>"

d. Version comparison (source vs runtime, semantic — compare major.minor.patch as integers):
   - source == runtime → OK
   - source > runtime → WARNING "[CORTEX] Hook outdated in runtime: <hook-name> (source: X, runtime: Y) — run /init"
   - source < runtime → WARNING "[CORTEX] Runtime hook is ahead of source: <hook-name> (runtime: X, source: Y) — investigate"

Note: `stop-build.sh` is NOT in hooks.json and does NOT deploy to `~/.claude/hooks/` — it runs directly from `$HOOKS_SRC/runtime/stop-build.sh`. Verify it exists there; if missing, record ERROR "[CORTEX] stop-build.sh missing from .cortex/core/hooks/runtime/"

## Step 5 — settings.json validation

Read `~/.claude/settings.json`.

- File missing → ERROR "[CORTEX] ~/.claude/settings.json not found"

For each hook name in hooks.json, verify a `command` entry referencing `~/.claude/hooks/<hook-name>` exists in the settings hooks block:
- Present → OK
- Missing → ERROR "[CORTEX] Hook not wired in settings.json: <hook-name>"

Verify the Stop hook entry points to `$HOOKS_SRC/runtime/stop-build.sh` (full absolute path):
- Correct → OK
- Pointing to `~/.claude/hooks/stop-build.sh` → ERROR "[CORTEX] Stop hook misconfigured — must point directly to .cortex path, not ~/.claude/hooks/"
- Missing entirely → ERROR "[CORTEX] Stop hook missing from settings.json"

For every `command` path in settings.json that references a file on disk, verify the file exists:
- Missing → ERROR "[CORTEX] settings.json references missing file: <path>"

Check for stale `.claude/.cortex/` references (old path pattern pointing into .claude directory):
- Found → WARNING "[CORTEX] settings.json has stale .claude/.cortex/ reference — hooks now live in .cortex/"

## Phase 1 Output

Print:

```
=== PHASE 1: CORTEX SYSTEM DIAGNOSTICS ===
Generated: <timestamp>

[FOLDER STRUCTURE]
  .cortex/core/          OK | ERROR
  .cortex/core/hooks/    OK | ERROR
  .cortex/core/scanners/ OK | ERROR
  .cortex/registry/      OK | ERROR
  .cortex/config/        OK | ERROR
  .claude/commands/      OK | ERROR

[REGISTRY]
  commands.json    OK | ERROR    <detail>
  hooks.json       OK | ERROR    <detail>
  scanners.json    OK | WARNING  <detail>

[HOOKS]
  <hook-name>    OK | WARNING | ERROR    source: <ver> | runtime: <ver>
  stop-build.sh  OK | ERROR              (direct, not deployed)
  ...

[SETTINGS]
  <hook-name> wired    OK | ERROR
  Stop hook path       OK | ERROR
  ...

CORTEX STATUS: OK | WARNING | ERROR
```

---

# PHASE 2 — PROJECT CODE DIAGNOSTICS

## Step 6 — Identify project type

Look at the working directory (the project root, NOT the Cortex repo itself). Determine what kind of project this is:

- `.sln` or `*.csproj` files present → .NET project
- `package.json` present → Node/React project
- Both → mixed project
- Neither → generic (scan shell scripts, config files, markdown)

Do NOT scan the `.claude/`, `.cortex/`, or `.git/` directories.

## Step 7 — Select files to scan

Based on project type, select files to scan. Be selective — do not read every file blindly.

For .NET: `*.cs`, `*.csproj`, `*.sln`
For Node/React: `*.ts`, `*.tsx`, `*.js`, `*.jsx`, `*.json` (non-lockfiles)
For generic/shell: `*.sh`, `*.json`, `*.md` (only those with logic)

Skip: `node_modules/`, `bin/`, `obj/`, `dist/`, `*.lock`, `*.log`, `*.min.js`, `*.map`

Use Glob to discover files, then read only those relevant to the checks below. Do not read files speculatively.

## Step 8 — Run code diagnostics

For each file read, check for the following. Only report issues you can see with confidence — do not hallucinate.

### 8a. Syntax / Runtime Risk
- Unclosed blocks, mismatched brackets
- Calling methods on potentially null/undefined values without guard
- Incorrect async/await usage (missing await, unhandled promise)
- Using variables before declaration
- Misused built-in APIs (wrong argument types, deprecated usage)

### 8b. Logical Bugs
- Conditions that can never be true or always be true
- Off-by-one errors in loops
- Missing `break` in switch/case (where unintentional)
- Functions that silently swallow exceptions
- Return paths that can produce `undefined`/`null` unexpectedly
- Dead code (unreachable after return/throw)

### 8c. Security Issues
- Hardcoded credentials, API keys, tokens, passwords (not already caught by post-scan.sh)
- Raw SQL string concatenation with user input
- `eval()` or `innerHTML` with dynamic content
- `Process.Start` or shell exec with unsanitized input
- Sensitive data in logs

### 8d. Code Quality Issues
Only flag these if they represent a real risk or significant maintainability problem:
- Functions longer than ~80 lines with no clear decomposition
- Magic numbers/strings used in critical logic without constants
- Obvious copy-paste duplication in logic paths (not just similar code)
- Catch blocks that swallow all exceptions silently (empty catch, or catch that only logs)

### 8e. Naming / Typo Issues
Only flag these if they could cause runtime errors or genuine confusion:
- Variable or function names that are clear typos (e.g. `resposne`, `retun`)
- Inconsistent casing in the same scope that could cause reference errors

## Phase 2 Output

For each issue found:

```
* [ERROR|WARNING|INFO] File: <relative/path/to/file>:<line>
  Problem: <what is wrong>
  Risk: <why it matters>
  → Suggested Fix: <minimal safe change>
```

Then print:

```
PROJECT STATUS: OK | WARNING | ERROR
```

---

# COMBINED SUMMARY

After both phases, print:

```
╔══════════════════════════════════════╗
║         DOCTOR REPORT SUMMARY        ║
╠══════════════════════════════════════╣
║  CORTEX:  OK | WARNING | ERROR       ║
║  PROJECT: OK | WARNING | ERROR       ║
╠══════════════════════════════════════╣
║  Cortex issues:  <n>                 ║
║  Project issues: <n>                 ║
║  Total:          <n>                 ║
╚══════════════════════════════════════╝
```

---

# FIX MODE

After printing the summary, ask exactly:

> "Do you want me to fix these issues? (yes / no)"

Wait for explicit user input. Do not proceed until answered.

**If NO:** Stop. Print "No changes made."

**If YES:** For each fixable issue, in order of severity (ERROR first):

1. Print the proposed change in diff-style format:
   ```
   File: <path>
   - <old line(s)>
   + <new line(s)>
   ```
2. Apply the fix using Edit (prefer) or Write only if full rewrite is necessary
3. Print: "Fixed: <brief description>"

Fix rules:
- Fix ONLY the specific issue identified — nothing else in that file
- Do NOT refactor, rename, or restructure surrounding code
- Do NOT introduce new dependencies, patterns, or abstractions
- If a fix requires understanding missing context (e.g., a missing file), skip it and note why
- Cortex config issues (missing files, broken paths) → do not create files; report as "requires manual action"

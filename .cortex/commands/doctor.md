# /doctor — Cortex Diagnostic Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--fix` → auto-apply safe fixes without asking
- `--deep` → run extended analysis (all scanners + architecture checks)
- `--dry-run` → simulate all actions; print what would be done; apply nothing

Flags may be combined. If no flags: read-only diagnostics only.

---

## SETUP

Read `~/.claude/cortex.env` to extract `CORTEX_ROOT`.

If missing:
```
[FAIL]

ERROR: cortex.env not found
DETAILS: ~/.claude/cortex.env does not exist
WHY: CORTEX_ROOT cannot be resolved — all Cortex checks will fail
FIX: run /init
```
Stop immediately.

Define:
- `CORTEX_DIR` = `$CORTEX_ROOT/.cortex`
- `HOOKS_SRC` = `$CORTEX_DIR/core/hooks`
- `SCANNERS_SRC` = `$CORTEX_DIR/core/scanners`
- `REGISTRY` = `$CORTEX_DIR/registry`
- `COMMANDS_DIR` = `$CORTEX_ROOT/.claude/commands`
- `RUNTIME_HOOKS` = `~/.claude/hooks`

Collect all issues into a list. Track the highest severity seen (PASS → WARN → FAIL).

---

## PHASE 1 — CORTEX SYSTEM DIAGNOSTICS

### CHECK 1 — Folder structure

Verify each required path exists:

| Path | Required |
|---|---|
| `$CORTEX_DIR/core/` | YES |
| `$CORTEX_DIR/core/hooks/` | YES |
| `$CORTEX_DIR/core/scanners/` | YES |
| `$CORTEX_DIR/registry/` | YES |
| `$CORTEX_DIR/config/` | YES |
| `$COMMANDS_DIR` | YES |

For each missing path, add:
```
TYPE: ERROR
TITLE: Required directory missing
DETAILS: <path> does not exist
WHY: Cortex cannot load hooks, scanners, or commands without this directory
FIX: run /init to restore the Cortex directory structure
```

### CHECK 2 — commands.json

Read `$REGISTRY/commands.json`.

If missing:
```
TYPE: ERROR
TITLE: commands.json not found
DETAILS: $REGISTRY/commands.json does not exist
WHY: command registry is required to validate command availability
FIX: restore commands.json from .cortex/registry/commands.json in the Cortex source repo
```

For each command name in the `commands` array, check `$COMMANDS_DIR/<name>.md` exists.
If missing:
```
TYPE: ERROR
TITLE: Command file missing: <name>
DETAILS: $COMMANDS_DIR/<name>.md is listed in commands.json but does not exist on disk
WHY: /name cannot be invoked — the command runner will exit non-zero
FIX: create $COMMANDS_DIR/<name>.md delegating to $CORTEX_DIR/commands/<name>.md
```

### CHECK 3 — hooks.json

Read `$REGISTRY/hooks.json`.

If missing:
```
TYPE: ERROR
TITLE: hooks.json not found
DETAILS: $REGISTRY/hooks.json does not exist
WHY: hook registry is required for version-aware deployment
FIX: restore hooks.json from the Cortex source repo
```

For each entry in hooks.json:

a. Check `source` and `version` fields exist. If either is absent:
```
TYPE: ERROR
TITLE: Malformed hooks.json entry: <key>
DETAILS: entry is missing the '<field>' field
WHY: /init cannot deploy this hook without a valid source path and version
FIX: add missing '<field>' field to the <key> entry in hooks.json
```

b. Check `$CORTEX_DIR/<source>` exists. If not:
```
TYPE: ERROR
TITLE: Hook source file missing: <key>
DETAILS: $CORTEX_DIR/<source> does not exist on disk
WHY: hook cannot be deployed or validated without its source file
FIX: restore <source> from the Cortex repository
```

### CHECK 4 — scanners.json

Read `$REGISTRY/scanners.json`.

If missing:
```
TYPE: ERROR
TITLE: scanners.json not found
DETAILS: $REGISTRY/scanners.json does not exist
WHY: post-scan.sh and post-format.sh are registry-driven and cannot dispatch without this file
FIX: restore scanners.json from the Cortex source repo
```

For each extension key (excluding `*`) and each scanner path in its array, check `$CORTEX_DIR/core/scanners/<path>` exists.
If missing:
```
TYPE: WARNING
TITLE: Scanner file missing: <path>
DETAILS: <path> is mapped in scanners.json but $CORTEX_DIR/core/scanners/<path> does not exist
WHY: files with extension <ext> will not be scanned — security issues or formatting errors may go undetected
FIX: create the scanner script at $CORTEX_DIR/core/scanners/<path> or remove the mapping from scanners.json
```

### CHECK 5 — Hook deployment and version validation

For each hook in hooks.json:

a. Read the source file at `$CORTEX_DIR/<source>`. Locate the line matching `^# @version:` (line 1 or 2). Extract the version string. If no version tag found, treat as `0.0.0` and add:
```
TYPE: WARNING
TITLE: Hook missing version tag: <hook-name>
DETAILS: $CORTEX_DIR/<source> has no '# @version: X.Y.Z' line
WHY: /init cannot perform version-aware deployment — hook may be redeployed unnecessarily or skipped
FIX: add '# @version: X.Y.Z' on line 2 of <source>
```

b. Check if the deployed file `$RUNTIME_HOOKS/<hook-name>` exists. If not:
```
TYPE: ERROR
TITLE: Hook not deployed: <hook-name>
DETAILS: $RUNTIME_HOOKS/<hook-name> does not exist
WHY: Claude Code cannot invoke this hook — the event it guards is unprotected
FIX: run /init
```

c. If deployed: read the runtime file's `# @version:` line. Compare source version vs runtime version (compare major, minor, patch as integers):
- source > runtime:
```
TYPE: ERROR
TITLE: Hook outdated in runtime: <hook-name>
DETAILS: source version <src_ver> is newer than deployed version <rt_ver>
WHY: the deployed hook is running old logic — security rules or formatting may be incorrect
FIX: run /init
```
- source < runtime:
```
TYPE: WARNING
TITLE: Runtime hook ahead of source: <hook-name>
DETAILS: runtime version <rt_ver> is newer than source version <src_ver>
WHY: deployed hook may contain untracked changes that will be lost on next /init
FIX: update the source file at $CORTEX_DIR/<source> to match the runtime version, then increment the version tag
```

d. Check `stop-build.sh` exists at `$HOOKS_SRC/runtime/stop-build.sh`:
```
TYPE: ERROR
TITLE: stop-build.sh missing
DETAILS: $HOOKS_SRC/runtime/stop-build.sh does not exist
WHY: the Stop hook will fail silently — build errors will not be reported after session end
FIX: restore stop-build.sh from the Cortex source repo
```

### CHECK 6 — settings.json wiring

Read `~/.claude/settings.json`.

If missing:
```
TYPE: ERROR
TITLE: settings.json not found
DETAILS: ~/.claude/settings.json does not exist
WHY: no hooks are wired to Claude Code events — the entire Cortex runtime is inactive
FIX: run /init
```

For each hook name in hooks.json, verify a `command` entry referencing `~/.claude/hooks/<hook-name>` exists in the hooks block.
If missing:
```
TYPE: ERROR
TITLE: Hook not wired: <hook-name>
DETAILS: settings.json has no command entry referencing ~/.claude/hooks/<hook-name>
WHY: <hook-name> will never fire — its guarded events have no protection
FIX: add the wiring entry for <hook-name> to ~/.claude/settings.json hooks block
```

Check the Stop hook entry points to `$HOOKS_SRC/runtime/stop-build.sh` (absolute path):
- Points to `~/.claude/hooks/stop-build.sh` instead:
```
TYPE: ERROR
TITLE: Stop hook misconfigured
DETAILS: Stop hook points to ~/.claude/hooks/stop-build.sh — must point directly to .cortex source
WHY: stop-build.sh is not deployed to ~/.claude/hooks/ — it runs from .cortex directly; this path will not resolve
FIX: update the Stop hook command in settings.json to point to $HOOKS_SRC/runtime/stop-build.sh
```
- Missing entirely:
```
TYPE: ERROR
TITLE: Stop hook missing from settings.json
DETAILS: no Stop hook entry found in ~/.claude/settings.json
WHY: build errors will not be surfaced after session end
FIX: add a Stop hook entry pointing to $HOOKS_SRC/runtime/stop-build.sh
```

Check for stale `.claude/.cortex/` references:
```
TYPE: WARNING
TITLE: Stale hook path in settings.json
DETAILS: settings.json contains a reference to .claude/.cortex/ — this is the old hook path pattern
WHY: hooks no longer live under .claude/ — these references will not resolve
FIX: replace all .claude/.cortex/ paths in settings.json with ~/.cortex/ paths
```

---

## PHASE 2 — PROJECT CODE DIAGNOSTICS

### Identify project type

Inspect the working directory (NOT the Cortex repo, NOT `.claude/`, `.cortex/`, or `.git/`).

- `.sln` or `*.csproj` present → .NET
- `package.json` present → Node/React
- Both → mixed
- Neither → generic (shell scripts, config, markdown)

### Select files to scan

.NET: `*.cs`, `*.csproj`
Node/React: `*.ts`, `*.tsx`, `*.js`, `*.jsx`
Generic: `*.sh`, `*.json`

Skip: `node_modules/`, `bin/`, `obj/`, `dist/`, `*.lock`, `*.log`, `*.min.js`, `*.map`, `.cortex/`, `.claude/`, `.git/`

In `--deep` mode: also scan `*.json` (non-lock), `*.yaml`, `*.yml`, `*.env`.

Use Glob to discover candidate files. Read only files needed to perform the checks below. Do not read files speculatively.

### Code checks

For every file read, perform these checks. Only report issues you can confirm from the file content — do not guess.

**Syntax / Runtime Risk**
- Calling methods on a value that may be null/undefined without a null guard
- Incorrect async/await usage: missing `await` on async call, unhandled promise rejection
- Variables used before declaration
- Wrong argument count/type for known APIs

**Logical Bugs**
- Conditions that are always true or always false
- Empty catch blocks (swallowing exceptions silently)
- Return paths that produce unexpected `undefined` or `null`
- Dead code after `return` or `throw`
- Missing `break` in switch/case where clearly unintentional

**Security Issues**
- Hardcoded credentials, API keys, tokens, connection strings
- Raw SQL string concatenation with a variable (`"SELECT * FROM ... " + userInput`)
- `eval()` or `innerHTML` with dynamic content
- Shell exec / `Process.Start` with unsanitized input
- Sensitive values written to logs

**Code Quality** (only flag if it represents a real risk)
- Functions exceeding ~80 lines with no decomposition
- Empty catch blocks that only log (error swallowed, caller not notified)
- Obvious copy-paste duplication in critical logic paths

**Architecture** (`--deep` only)
- Direct database/repository access from a controller or UI component
- Missing validation on any public API input parameter
- Cross-layer dependency violations (UI importing data-access types directly)

For each issue found:
```
TYPE: ERROR | WARNING | INFO
TITLE: <short description>
DETAILS: <file>:<line> — <what exactly is wrong>
WHY: <technical reason this is a problem>
FIX: <exact, single change to resolve this>
```

---

## OUTPUT

### Header

Print overall status based on highest severity found:
- Any ERROR → `[FAIL]`
- Any WARNING, no ERROR → `[WARN]`
- No issues → `[PASS]`

Then print all collected issues in order: ERRORs first, then WARNINGs, then INFOs.

Format each issue as:
```
TYPE: ERROR | WARNING | INFO
TITLE: <title>
DETAILS: <details>
WHY: <why>
FIX: <fix>
```

Then print the summary box:
```
╔══════════════════════════════════════╗
║         DOCTOR REPORT SUMMARY        ║
╠══════════════════════════════════════╣
║  CORTEX:  PASS | WARN | FAIL         ║
║  PROJECT: PASS | WARN | FAIL         ║
╠══════════════════════════════════════╣
║  Cortex issues:  <n>                 ║
║  Project issues: <n>                 ║
║  Total:          <n>                 ║
╚══════════════════════════════════════╝
```

---

## FIX MODE

If `--fix` was provided:

For each fixable issue (those whose FIX is deterministic and safe):
- Hook deployment issues → run `/init`
- Missing executable permissions → `chmod +x <file>`
- Stale path references in settings.json → apply Edit to correct the path

If `--dry-run` is also present: print the proposed changes as diffs but apply nothing.

If `--dry-run` is NOT present: apply fixes immediately, then print:
```
Fixed: <brief description of what was changed>
```

Do NOT auto-fix:
- Code issues in project files (these require human review)
- Registry corrections that require structural changes
- Anything that modifies `.cortex/local/`

Do NOT ask the user for permission before fixing. Apply deterministic fixes silently.

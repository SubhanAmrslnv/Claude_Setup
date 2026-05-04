# /init-cortex — Cortex Environment Setup and Validation

## WINDOWS PATH NOTE

On Windows (Git Bash / MSYS2), `$HOME` and `$(pwd)` expand to Unix-style paths like `/c/Users/...`. Native Windows Python cannot open these paths — it requires `C:/Users/...`.

**Rule**: never pass a bash-expanded path directly to Python's `open()`. Always use bash `[ -f ]` / `[ -d ]` / `cat` for file operations, or convert the path first:

```bash
NATIVE_PATH=$(python3 -c "import os,sys; print(os.path.normpath(sys.argv[1]))" "$THE_PATH")
```

---

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--force` → redeploy ALL hooks regardless of version
- `--dry-run` → simulate all actions; print what would be done; apply nothing

Flags may be combined.

---

## STEP 1 — Resolve CORTEX_ROOT

Cortex is strictly project-local. CORTEX_ROOT always points to the project's own `.claude/` directory.

If `$CORTEX_ROOT` is already set in the environment, use it. Otherwise set it to `$(pwd)/.claude`.

If the resolved path does not exist:
```
[FAIL]

TYPE: ERROR
TITLE: .claude directory not found
DETAILS: $(pwd)/.claude does not exist
WHY: /init-cortex must run from inside a Cortex-enabled project directory
FIX: cd to the project root that contains .claude/ and re-run /init-cortex
```
Stop.

There is no global install, no `~/.claude/cortex.env`, and no `~/.claude/hooks/` directory. All hooks run directly from `$CORTEX_ROOT/core/hooks/`.

---

## STEP 2 — Validate directory structure

Verify each required path exists under `$CORTEX_ROOT`:

| Path | Required |
|---|---|
| `$CORTEX_ROOT/core/hooks/guards/` | YES |
| `$CORTEX_ROOT/core/hooks/runtime/` | YES |
| `$CORTEX_ROOT/core/shared/bootstrap.sh` | YES |
| `$CORTEX_ROOT/core/scanners/` | YES |
| `$CORTEX_ROOT/registry/` | YES |
| `$CORTEX_ROOT/config/` | YES |

Ensure runtime directories exist (create if missing and not `--dry-run`):
- `$CORTEX_ROOT/cache/scans/`
- `$CORTEX_ROOT/logs/`
- `$CORTEX_ROOT/temp/`
- `$CORTEX_ROOT/state/`

For each missing required directory:
```
TYPE: ERROR
TITLE: Required directory missing: <path>
DETAILS: <path> does not exist
WHY: Cortex cannot load hooks, scanners, or commands without this directory
FIX: restore the directory from the Cortex source repository
```

---

## STEP 3 — Registry version validation and hook consistency

Read `$CORTEX_ROOT/registry/hooks.json`.

If missing:
```
[FAIL]

TYPE: ERROR
TITLE: hooks.json not found
DETAILS: $CORTEX_ROOT/registry/hooks.json does not exist
WHY: hook registry is required to validate hook versions
FIX: restore hooks.json from the Cortex source repository
```
Stop.

For each entry (hook name + `source` path + `version`), perform all of the following in a single pass (one read per source file):

a. Resolve source: `$CORTEX_ROOT/<source>`. If the file does not exist on disk, record:
```
TYPE: ERROR
TITLE: Hook source file missing: <hook-name>
DETAILS: $CORTEX_ROOT/<source> does not exist on disk
WHY: hook cannot fire — Claude Code will invoke a missing script
FIX: restore <source> from the Cortex source repository
```
Skip remaining checks for this entry.

b. Read the source file and simultaneously verify:

- **Version tag**: locate `# @version: X.Y.Z` on line 1 or 2. If absent, treat as `0.0.0` and record:
```
TYPE: WARNING
TITLE: Hook missing version tag: <hook-name>
DETAILS: $CORTEX_ROOT/<source> has no '# @version: X.Y.Z' line
WHY: /init-cortex cannot perform version-aware tracking
FIX: add '# @version: X.Y.Z' on line 2 of <source>
```

- **Version match**: compare source `# @version:` against the version in hooks.json:
  - In `--force` mode: always report as UPDATED regardless.
  - source version > registry version → record WARNING (source updated but registry not synced; run /init-cortex to sync)
  - source version == registry version → OK
  - source version < registry version → record WARNING (registry ahead of source — bump source version tag)

```
TYPE: WARNING
TITLE: Registry version mismatch: <hook-name>
DETAILS: hooks.json declares <registry_ver> but source file contains <source_ver>
WHY: version tracking is inaccurate — /doctor version checks will be unreliable
FIX: update the version field for <hook-name> in hooks.json to match the source file
```

- **Bootstrap usage**: first executable line must be `source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0`. If the hook still has an inline `if [ -z "$CORTEX_ROOT" ]` block:
```
TYPE: WARNING
TITLE: Hook not using bootstrap: <hook-name>
DETAILS: <hook-name> has an inline CORTEX_ROOT resolution block instead of sourcing bootstrap.sh
WHY: bootstrap.sh is the single source of truth — inline blocks will diverge
FIX: replace the inline block with: source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0
```

Record each hook as: `OK` | `WARNING` | `ERROR`

Since hooks run directly from `$CORTEX_ROOT/core/hooks/` there is no deployment step. The registry is used only for version tracking and `/doctor` validation.

---

## STEP 4 — Validate settings.json wiring

Read `$CORTEX_ROOT/settings.json`.

If missing:
```
TYPE: ERROR
TITLE: settings.json not found
DETAILS: $CORTEX_ROOT/settings.json does not exist
WHY: no hooks are wired to Claude Code events — the entire Cortex runtime is inactive
FIX: restore settings.json from the Cortex source repository
```

For each hook name in hooks.json, verify a `command` entry whose path contains `core/hooks/` and the hook filename exists in the hooks block.

Hook paths in settings.json must use the form:
```
${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<guards|runtime>/<hook-name>
```

No hook entry should reference `~/.claude/hooks/` — that is the old global model.

For each absent or incorrectly-pathed entry:
```
TYPE: ERROR
TITLE: Hook not wired: <hook-name>
DETAILS: settings.json has no command entry for <hook-name> using the project-local path pattern
WHY: <hook-name> will never fire — its guarded events have no protection
FIX: add the wiring entry using: bash ${CORTEX_ROOT:-$(pwd)/.claude}/core/hooks/<subdir>/<hook-name>
```

---

## STEP 5 — Validate command registry

Read `$CORTEX_ROOT/registry/commands.json`.

For each name in `commands`, check `$CORTEX_ROOT/commands/<name>.md` exists.

Record each as `OK` or `ERROR`.

---

## STEP 6 — Scanner Pruning

Minimize the project-local scanner footprint to only what the current repository needs. This step is idempotent and runs automatically on every `/init-cortex` invocation.

**Safety boundary**: This step operates exclusively on `$CORTEX_ROOT/core/scanners/`. Never delete from `$CORTEX_ROOT/base/`, `$CORTEX_ROOT/local/`, any global or user directory, or any path outside the resolved `$CORTEX_ROOT`. Any path that does not pass the safety check below is silently skipped.

### 6a — Detect active project languages

Resolve the project root as `$(dirname "$CORTEX_ROOT")` (the directory that contains `.claude/`). Run all detection checks from that directory.

Build a set of **scanner directories to keep**. Start with `{"generic"}` — this is unconditionally retained.

Use `find` with a depth limit of 5 and explicit prune expressions to exclude `.git`, `node_modules`, `.claude`, `vendor`, `target`, `obj`, `bin`, `__pycache__`, `.venv` from all searches.

Run each detection check using bash, then add the corresponding scanner directory to the keep set if the check yields any output (or succeeds):

**Primary language markers (run from project root):**

| Detection check | Scanner directory added |
|---|---|
| `find . -maxdepth 3 \( -name '*.csproj' -o -name '*.sln' \) -not -path './.claude/*' 2>/dev/null \| head -1` returns output | `dotnet` |
| `[ -f package.json ]` | `node` |
| `[ -f requirements.txt ] \|\| [ -f pyproject.toml ] \|\| [ -f setup.py ]` | `python` |
| `[ -f go.mod ]` | `go` |
| `[ -f Cargo.toml ]` | `rust` |
| `[ -f pom.xml ] \|\| find . -maxdepth 3 \( -name 'build.gradle' -o -name 'build.gradle.kts' \) -not -path './.claude/*' 2>/dev/null \| head -1` returns output | `java` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' -o -name 'vendor' -o -name 'target' \) -prune -o -name '*.kt' -print 2>/dev/null \| head -1` returns output | `kotlin` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' -o -name 'vendor' -o -name 'target' \) -prune -o -name '*.swift' -print 2>/dev/null \| head -1` returns output | `swift` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o -name '*.dart' -print 2>/dev/null \| head -1` returns output | `dart` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o -name '*.rb' -print 2>/dev/null \| head -1` returns output | `ruby` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.scala' -o -name '*.sc' \) -print 2>/dev/null \| head -1` returns output | `scala` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o -name '*.php' -print 2>/dev/null \| head -1` returns output | `php` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.r' -o -name '*.R' \) -print 2>/dev/null \| head -1` returns output | `r` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o -name '*.lua' -print 2>/dev/null \| head -1` returns output | `lua` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.sh' -o -name '*.bash' \) -print 2>/dev/null \| head -1` returns output | `bash` |

**Infrastructure/tooling markers (run from project root):**

| Detection check | Scanner directory added |
|---|---|
| `find . -maxdepth 4 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name 'Dockerfile' -o -name 'docker-compose.yml' -o -name '*.dockerfile' \) -print 2>/dev/null \| head -1` returns output | `docker` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.tf' -o -name '*.tfvars' \) -print 2>/dev/null \| head -1` returns output | `terraform` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.yaml' -o -name '*.yml' \) -print 2>/dev/null \| head -1` returns output | `yaml` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.sql' -o -name '*.psql' -o -name '*.pgsql' \) -print 2>/dev/null \| head -1` returns output | `sql` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.ps1' -o -name '*.psm1' -o -name '*.psd1' \) -print 2>/dev/null \| head -1` returns output | `powershell` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o -name '*.proto' -print 2>/dev/null \| head -1` returns output | `proto` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name '*.prompt' -o -name '*.claude' \) -print 2>/dev/null \| head -1` returns output | `ai-prompt` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name 'Makefile' -o -name '*.mk' \) -print 2>/dev/null \| head -1` returns output | `makefile` |
| `find . -maxdepth 5 \( -name '.git' -o -name 'node_modules' -o -name '.claude' \) -prune -o \( -name 'CMakeLists.txt' -o -name '*.cmake' \) -print 2>/dev/null \| head -1` returns output | `cmake` |

### 6b — Compute scanner directories to remove

List all subdirectories of `$CORTEX_ROOT/core/scanners/` using:

```bash
ls -d "$CORTEX_ROOT/core/scanners/"*/ 2>/dev/null | xargs -I{} basename {}
```

For each directory basename that is **not** in the keep set: mark it for removal.

**Path traversal safety check** — validate each candidate path before any deletion:

1. Resolve the absolute path: `CANDIDATE=$(cd "$CORTEX_ROOT/core/scanners/$dir" 2>/dev/null && pwd)`
2. Verify the resolved path starts with `$CORTEX_ROOT/core/scanners/` (use bash prefix comparison: `[[ "$CANDIDATE" == "$CORTEX_ROOT/core/scanners/"* ]]`)
3. Verify the basename contains only alphanumeric characters, hyphens, and underscores: `[[ "$dir" =~ ^[a-zA-Z0-9_-]+$ ]]`
4. Verify it is a real directory, not a symlink: `[ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ]`

If any check fails, skip the path and record:

```
TYPE: WARNING
TITLE: Scanner pruning skipped for unsafe path: <path>
DETAILS: Path failed safety validation — skipping to prevent unintended deletion
WHY: Path traversal or symlink protection triggered
FIX: Manually inspect and remove if unneeded: rm -rf "<path>"
```

### 6c — Apply removal

In `--dry-run` mode: log each directory as `[WOULD REMOVE]` but do not delete.

Otherwise: for each validated path, run `rm -rf "$CANDIDATE"`. Silently succeeds if the directory was already absent (idempotent). Never errors on missing directories.

After removal, re-list `$CORTEX_ROOT/core/scanners/` to confirm the final retained set.

---

## STEP 7 — Build Project File Index Cache

Build a project-wide file index at `$CORTEX_ROOT/cache/project-file-index.txt`. This cache is consumed by hooks and commands for fast file discovery without repeated filesystem scans.

In `--dry-run` mode: compute the count but write nothing. Log `[WOULD WRITE] $CORTEX_ROOT/cache/project-file-index.txt (<N> files)` and skip 7b–7c.

### 7a — Resolve project root

```bash
PROJECT_ROOT=$(dirname "$CORTEX_ROOT")
INDEX_TEMP="$CORTEX_ROOT/cache/project-file-index.tmp"
INDEX_FINAL="$CORTEX_ROOT/cache/project-file-index.txt"
```

### 7b — Scan all project files

Run `find` from `$PROJECT_ROOT`, collecting all regular files while pruning noise and generated directories:

```bash
find "$PROJECT_ROOT" -type f \
  -not -path "*/.git/*" \
  -not -path "*/node_modules/*" \
  -not -path "*/bin/*" \
  -not -path "*/obj/*" \
  -not -path "*/dist/*" \
  -not -path "*/build/*" \
  -not -path "*/.next/*" \
  -not -path "*/coverage/*" \
  -not -path "${CORTEX_ROOT}/cache/*" \
  -not -path "${CORTEX_ROOT}/temp/*" \
  2>/dev/null \
| sort > "$INDEX_TEMP"
```

Each line in `$INDEX_TEMP` is a full absolute path to one project file.

### 7c — Atomic write

Rename the temp file to the final location:

```bash
mv "$INDEX_TEMP" "$INDEX_FINAL"
```

Write to `$INDEX_TEMP` first, then rename to `$INDEX_FINAL` atomically — this prevents hooks from reading a partial index if the scan is interrupted mid-run.

If `mv` fails: delete `$INDEX_TEMP`, then record:
```
TYPE: WARNING
TITLE: File index write failed
DETAILS: $CORTEX_ROOT/cache/project-file-index.txt could not be written
WHY: Atomic rename failed — partial writes were discarded
FIX: Check disk space and permissions on $CORTEX_ROOT/cache/
```

### 7d — Report

Count indexed files and record the result:

```bash
INDEX_COUNT=$(wc -l < "$INDEX_FINAL" 2>/dev/null | tr -d ' ')
```

Record as: `[FILE INDEX] Built: $INDEX_FINAL — $INDEX_COUNT files indexed`

---

## STEP 8 — Validate scanner availability

Read `$CORTEX_ROOT/registry/scanners.json`.

For each extension key (excluding `*`), for each scanner path in its array, check `$CORTEX_ROOT/core/scanners/<path>` exists using bash `[ -f ]`.

If the scanner file is missing and its parent directory is also absent from `$CORTEX_ROOT/core/scanners/`, record as `INFO (pruned)` — this is expected after Step 6 removed an unused language scanner. Do not record a WARNING or ERROR for these entries.

If the scanner file is missing but its parent directory still exists, record as `WARNING (missing)`.

---

## STEP 9 — Remote version tracking

This step is **best-effort**. A failure here does NOT change the overall init status or stop execution.

Attempt to fetch the latest commit SHA from the remote main branch (lightweight — no clone needed):
```bash
REMOTE_SHA=$(git ls-remote https://github.com/SubhanAmrslnv/Cortex.git refs/heads/main 2>/dev/null | cut -f1)
```

If `REMOTE_SHA` is empty or the command exits non-zero:
- Record: `[REMOTE VERSION] Fetch failed — cortex-version.json not updated`
- Continue.

If `REMOTE_SHA` is non-empty:
- In `--dry-run` mode: record `[WOULD WRITE] $CORTEX_ROOT/state/cortex-version.json` and skip the write.
- Otherwise write (create if absent):
  ```bash
  mkdir -p "$CORTEX_ROOT/state"
  cat > "$CORTEX_ROOT/state/cortex-version.json" <<EOF
  {
    "remoteCommit": "$REMOTE_SHA",
    "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "sourceBranch": "main"
  }
  EOF
  ```
- Record: `[REMOTE VERSION] cortex-version.json updated — remote commit: ${REMOTE_SHA:0:7}`

Safety rules:
- NEVER touch any file under `$CORTEX_ROOT/local/`.
- NEVER touch any other file under `$CORTEX_ROOT/state/` — only `cortex-version.json` is written.
- If `mkdir -p` or the write fails, record a WARNING and continue. Never stop.

---

## OUTPUT

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on highest severity found.

Then print the structured report:

```
=== CORTEX INIT REPORT ===
Mode: <default | --force | --dry-run | --force --dry-run>
Generated: <timestamp>

[CORTEX_ROOT]
  Path:       <resolved path>
  Model:      project-local (no global install)

[STRUCTURE]
  <path>    OK | CREATED | MISSING
  ...

[HOOKS]
  <hook-name>    OK | WARNING | ERROR    source: <ver> registry: <ver>    bootstrap: OK | WARN
  ...

[SETTINGS]
  $CORTEX_ROOT/settings.json    OK | MISSING | INCOMPLETE
  <if INCOMPLETE: list each missing hook entry>

[COMMANDS]
  <command>    OK | ERROR
  ...

[SCANNER PRUNING]
  Project type(s):  <comma-separated detected languages/frameworks>
  Kept scanners:    <scanner1> <scanner2> ... (<N> total)
  Removed:          <scanner3> <scanner4> ... (<N> removed) | none
  Final scanners:   <list of all remaining scanner directory names>

[FILE INDEX]
  Path:   $CORTEX_ROOT/cache/project-file-index.txt
  Files:  <N> indexed | SKIPPED (--dry-run) | FAILED

[REMOTE VERSION]
  cortex-version.json:  UPDATED | SKIPPED (--dry-run) | FETCH FAILED
  Remote commit:        <short SHA> | N/A

[SCANNERS]
  <ext>/<scanner>    OK | INFO (pruned) | WARNING (missing)
  ...

STATUS: PASS | WARN | FAIL
```

For each issue, also print in structured format:
```
TYPE: ERROR | WARNING
TITLE: <title>
DETAILS: <details>
WHY: <why>
FIX: <fix>
```

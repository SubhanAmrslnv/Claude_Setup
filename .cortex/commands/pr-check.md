# /pr-check — Cortex PR Simulation Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--branch=<name>` → compare against this base branch (default: `main`)
- `--staged` → check only staged changes (default: all uncommitted + staged)
- `--skip-build` → skip the build step (use when no build system is present)
- `--skip-tests` → skip the test presence check

Default: compare HEAD against `main`, run all checks.

---

## STEP 1 — Establish diff scope

Determine which files are in scope:

| Mode | Command |
|---|---|
| `--staged` | `git diff --cached --name-only` |
| default | `git diff main...HEAD --name-only` (falls back to `git diff HEAD --name-only` if main is not reachable) |

Save result as `CHANGED_FILES`.

If `CHANGED_FILES` is empty:
```
[PASS]
PR RESULT: ACCEPTED

No changes detected — nothing to validate.
```
Stop.

Also collect:
- `BRANCH_NAME` via `git rev-parse --abbrev-ref HEAD`
- `COMMIT_COUNT` via `git rev-list main...HEAD --count` (or `1` if main is not reachable)
- `COMMIT_MESSAGES` via `git log main...HEAD --pretty=format:"%s"` (last 20)

---

## STEP 2 — BUILD CHECK

Detect project type from files present in the repo root (in priority order):

| Project type | Detection signal | Build command |
|---|---|---|
| .NET | `*.csproj`, `*.sln` | `dotnet build --no-restore 2>&1` |
| Node.js | `package.json` with `"build"` script | `npm run build 2>&1` |
| Python | `setup.py`, `pyproject.toml` | `python -m py_compile $(git ls-files '*.py') 2>&1` |
| Go | `go.mod` | `go build ./... 2>&1` |
| Rust | `Cargo.toml` | `cargo build 2>&1` |
| None detected | — | Skip build; record as `BUILD: SKIPPED` |

If `--skip-build` is set: record `BUILD: SKIPPED`.

Run the detected build command. Capture exit code and stderr.

- Exit 0 → `BUILD: PASS`
- Exit non-zero → `BUILD: FAIL` — capture first 20 lines of error output as `BUILD_ERRORS`

---

## STEP 3 — FORMATTER CHECK

Read `.cortex/registry/scanners.json` to get the formatter list.

For each file in `CHANGED_FILES`:
1. Determine its extension.
2. Look up matching `format.sh` entries in the scanner registry.
3. For each match, run: `bash ~/.cortex/core/scanners/<language>/format.sh <filepath> --check 2>&1`
   - If the formatter does not support `--check`, run it normally and compare output to original via diff.
   - Exit 0 or no diff → `PASS` for this file.
   - Exit non-zero or diff present → record file as `FORMAT_FAIL[filepath] = <formatter output>`

Aggregate:
- All files pass → `FORMAT: PASS`
- Any file fails → `FORMAT: WARN` (formatting issues are non-blocking but must be listed)

If no formatters match any changed file: `FORMAT: SKIPPED`

---

## STEP 4 — SECURITY SCAN

Read `.cortex/registry/scanners.json` to get the security scanner list.

Always run the `*` wildcard scanner (generic secret scan) against all `CHANGED_FILES`:
```
bash ~/.cortex/core/scanners/generic/secret-scan.sh <filepath>
```

For each file in `CHANGED_FILES`:
1. Determine its extension.
2. Look up matching `security-scan.sh` entries in the registry.
3. Run each matching scanner: `bash ~/.cortex/core/scanners/<language>/security-scan.sh <filepath>`
   - Exit 0 → PASS for this file
   - Exit non-zero → record as `SECURITY_FAIL[filepath] = <scanner output>`

Aggregate:
- All clean → `SECURITY: PASS`
- Any finding → `SECURITY: FAIL` — list each finding with file, line, and issue type

---

## STEP 5 — ARCHITECTURE CHECK

For each file in `CHANGED_FILES`, run lightweight structural checks (read each file):

**Complexity:**
- Methods or functions exceeding 50 lines → flag as `COMPLEXITY_WARN`
- Nesting depth > 3 (brace/indent tracking) → flag as `NESTING_WARN`
- Files > 500 lines → flag as `SIZE_WARN`

**Naming:**
- Non-descriptive variable names (`temp`, `data`, `obj`, `val`, `x`, `foo`, `bar`, `result`, `res`, `tmp`) — flag up to 3 per file as `NAMING_WARN`

**Separation of concerns (Cortex-specific):**
- Hook files (`.cortex/core/hooks/`) containing non-bash logic or inline data that belongs in registry → flag as `STRUCTURE_WARN`
- Scanner files calling external services or writing files → flag as `STRUCTURE_WARN`

Aggregate:
- No flags → `ARCHITECTURE: PASS`
- Only WARN-level flags → `ARCHITECTURE: WARN` — list each flag with file and line
- Any STRUCTURE_WARN in a hook or scanner → `ARCHITECTURE: FAIL`

---

## STEP 6 — COMMIT MESSAGE CHECK

For each message in `COMMIT_MESSAGES`, validate against the conventional commit format:

Pattern: `^(feat|fix|refactor|docs|chore|test|style|perf)(\([a-zA-Z0-9_-]+\))?: .+`

- All messages match → `COMMITS: PASS`
- Any message does not match → `COMMITS: WARN` — list non-conforming messages

Also check:
- No message contains `Co-Authored-By: Claude` or `🤖` → if found → `COMMITS: FAIL`

---

## STEP 7 — TEST PRESENCE CHECK

Skip if `--skip-tests` is set: record `TESTS: SKIPPED`.

For each non-test file in `CHANGED_FILES` (exclude paths containing `test`, `spec`, `__tests__`):
1. Derive the expected test file name (e.g., `foo.ts` → `foo.test.ts`, `foo.spec.ts`; `FooService.cs` → `FooServiceTests.cs`)
2. Use Glob to check if it exists anywhere in the repo.

Aggregate:
- All changed files have a corresponding test file → `TESTS: PRESENT`
- Any changed file has no corresponding test file → `TESTS: MISSING` — list the uncovered files

Note: MISSING is a warning, not a blocker. Record for output but do not fail the PR on this alone.

---

## STEP 8 — Determine PR outcome

Apply this decision table (first matching row wins):

| Condition | Outcome |
|---|---|
| `BUILD: FAIL` | `REJECTED` |
| `SECURITY: FAIL` | `REJECTED` |
| `COMMITS: FAIL` (Claude attribution found) | `REJECTED` |
| `ARCHITECTURE: FAIL` | `REJECTED` |
| `BUILD: SKIPPED` + `SECURITY: FAIL` | `REJECTED` |
| `ARCHITECTURE: WARN` or `FORMAT: WARN` or `COMMITS: WARN` or `TESTS: MISSING` | `WARNING` |
| All checks PASS or SKIPPED | `ACCEPTED` |

Map outcome to status:
- `REJECTED` → `[FAIL]`
- `WARNING` → `[WARN]`
- `ACCEPTED` → `[PASS]`

---

## STEP 9 — Generate WHY explanation

Produce one paragraph per FAIL or WARN check explaining:
- What was found (specific file, line, or message)
- Why it blocks or warns
- No vague statements — every claim must cite something found in Steps 2–7

---

## STEP 10 — Generate FIX steps

For each FAIL check, provide exact shell commands or specific file edits to resolve it.
For each WARN check, provide one actionable step.

Order: FAIL fixes first, then WARN fixes.

Do NOT provide optional alternatives — one fix per issue.

---

## OUTPUT

```
[PASS | WARN | FAIL]

PR RESULT: ACCEPTED | WARNING | REJECTED

  Branch:   <branch_name>
  Commits:  <commit_count>
  Files:    <changed_file_count>

CHECKS:

  BUILD:        ✔ PASS | ⚠ SKIPPED | ❌ FAIL
  FORMAT:       ✔ PASS | ⚠ WARN    | ⚠ SKIPPED
  SECURITY:     ✔ PASS | ❌ FAIL
  ARCHITECTURE: ✔ PASS | ⚠ WARN   | ❌ FAIL
  COMMITS:      ✔ PASS | ⚠ WARN   | ❌ FAIL
  TESTS:        ✔ PRESENT | ⚠ MISSING | ⚠ SKIPPED
```

If any check is WARN or FAIL, print its details block:

```
  <CHECK> DETAILS:
    - <file or message>: <issue>
    - ...
```

Then:

```
WHY:
<one paragraph per failing/warning check>

FIX:
<numbered list of exact steps — FAILs first, then WARNs>
```

---

## CONSTRAINTS

- Never skip a check without an explicit flag or absence of a build system
- Never mark SECURITY: PASS without running the generic secret scanner on every changed file
- Never mark BUILD: PASS without capturing the exit code
- Never output multiple FIX options for the same issue
- Never make optimistic assumptions about test coverage — check file existence
- Never flag TESTS: MISSING for files that are themselves test files

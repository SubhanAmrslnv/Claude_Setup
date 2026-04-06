# /commit — Safe Intelligent Commit Creation

## STEP 1 — Detect current branch

Run: `git rev-parse --abbrev-ref HEAD`

Save as `CURRENT_BRANCH`.

---

## STEP 2 — Check for changes

Run: `git status --short`

If working tree is clean and nothing staged:
```
[PASS]

Nothing to commit — working tree is clean.
```
Stop.

---

## STEP 3 — Run lightweight Cortex diagnostics

Before staging or committing anything, run a reduced /doctor check covering only Cortex system integrity (Phase 1 only). Do NOT run project code diagnostics here.

Perform:
- hooks.json readable
- All hooks deployed (each `~/.claude/hooks/<hook-name>` exists)
- All hook versions match (source == runtime)
- settings.json exists

Collect any issues. If any ERROR is found:
```
[FAIL]

TYPE: ERROR
TITLE: Cortex system integrity check failed
DETAILS: <specific hook or registry issue>
WHY: committing with a broken Cortex configuration may bypass security scanning or formatting
FIX: run /init-cortex
```
Stop. Do not proceed to commit.

---

## STEP 4 — Stage changed files

Run: `git add -u`

---

## STEP 5 — Run formatters and scanners

Get the list of staged files: `git diff --cached --name-only`

For each staged file, check its extension against `~/.cortex/registry/scanners.json` (or `$CORTEX_ROOT/.cortex/registry/scanners.json`).

**Formatters**: for each staged file matching a `format.sh` scanner entry, run that formatter script passing the file path. If a formatter fails (non-zero exit):
```
[FAIL]

TYPE: ERROR
TITLE: Formatter failed: <file>
DETAILS: <formatter script> exited non-zero for <file>
WHY: committing unformatted code violates project style rules and will trigger post-format failures on next edit
FIX: inspect formatter output above, fix formatting issues in <file>, then re-run /commit
```
Stop. Do not proceed to commit.

**Security scanners**: for each staged file, run matching `security-scan.sh` entries plus `generic/secret-scan.sh` (wildcard). If any scanner finds issues (non-zero exit or structured output with findings):
```
[FAIL]

TYPE: ERROR
TITLE: Security scan failed: <file>
DETAILS: <scanner> detected issues in <file>: <finding>
WHY: committing code with security vulnerabilities introduces risk that will propagate into git history
FIX: resolve the finding in <file> (line <n>), then re-run /commit
```
Stop. Do not proceed to commit.

If no staged files match any scanner, skip this step (no WARNING — sparse scanner coverage is tracked by /doctor).

---

## STEP 6 — Branch routing

### CASE A — Protected branch (main, master, develop)

Ask the user:
> "You are on a protected branch (`<CURRENT_BRANCH>`). Enter a new branch name:"

Wait for explicit user input. Do NOT auto-generate a branch name.

Then ask:
> "Enter the commit subject line:"

Wait for explicit user input. Do NOT proceed until provided.

Then ask:
> "Enter a short description (optional — press Enter to skip):"

Wait for user input.

Once all inputs are provided:
1. Run: `git checkout -b <branch-name>`
2. Print: `Branch '<branch-name>' created.`
3. Proceed to Step 7 using user-provided subject and description.

### CASE B — Safe branch

Generate a conventional commit message automatically from the staged diff.

Run: `git diff --cached` and `git diff --cached --stat`

**Derive commit type**:
| Signals in diff | Type |
|---|---|
| New files, new exported functions/classes | `feat` |
| Modified logic that corrects incorrect behavior | `fix` |
| Restructured code, no new behavior | `refactor` |
| Only documentation files changed | `docs` |
| Config, tooling, scripts, lock files | `chore` |
| Whitespace, formatting only | `style` |
| Test files added or modified | `test` |
| Performance-focused change | `perf` |

**Derive scope**: use the most specific directory or component name affected (e.g., `hooks`, `scanners`, `pre-guard`, `commit`).

**Generate subject**: `<type>(<scope>): <summary>`
- Summary must reflect the actual diff — no vague words like "update", "changes", "fix stuff"
- 72 characters max
- No trailing period
- No Claude attribution, no emoji

**Generate description** (body): 2–5 bullet points using `-`
- Each bullet is one concrete fact from the diff
- State what changed and why
- No vague filler, no Claude attribution

Print:
```
Generated commit:
  Subject:     <subject>
  Description:
    - <bullet 1>
    - <bullet 2>
    ...
```

Proceed to Step 7 with generated subject and description.

---

## STEP 7 — Commit

Run:
```
git commit -m "<subject>" -m "<description bullets joined with newlines>"
```

On success:
```
[PASS]

Commit created on '<branch>' — <subject>
```

On failure, print the git error verbatim and stop.

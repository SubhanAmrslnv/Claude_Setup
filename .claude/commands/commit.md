# /commit — Fast Intelligent Commit Creation

## STEP 1 — Detect current branch (mandatory)

Run: `git rev-parse --abbrev-ref HEAD`

Save as `CURRENT_BRANCH`.

**Never** auto-create a new branch. The user manages branching. This command's role is to commit on whatever branch is checked out, after explicit confirmation when the branch is protected (see Step 6).

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

## STEP 3 — Stage changed files

Run both of the following to capture modified and new untracked files:
```
git add -u
git add .
```

Then guard against an empty index:

Run: `git diff --cached --quiet`

If exit code is 0 (nothing staged):
```
[PASS]

No changes staged after add — nothing to commit.
```
Stop.

---

## STEP 4 — Sensitive file detection

Run: `git diff --cached --name-only`

If any staged file matches `\.env$|\.pem$|\.key$|\.pfx$|\.p12$|id_rsa|credentials`:
```
[FAIL]

TYPE: ERROR
TITLE: Sensitive file detected in staged changes
DETAILS: <matching filename(s)>
WHY: committing credentials or private keys permanently embeds them in git history — even a later revert does not remove them
FIX: unstage the file with `git reset HEAD <file>` and add it to .gitignore
```
Stop. Do not proceed to commit.

---

## STEP 5 — Collect staging metrics

Run: `git diff --cached --name-status`

Compute:
- `TOTAL_FILES` — total number of staged files
- `HAS_TESTS` — any staged file path contains `test` or `spec`
- `HAS_NEW` — any line in name-status starts with `A`
- `HAS_DELETED` — any line in name-status starts with `D`

---

## STEP 6 — Branch routing

### CASE A — Protected branch (main, master, develop)

Print the warning:
```
[WARN]

You are on a protected branch (<CURRENT_BRANCH>).
Committing directly here is allowed but discouraged for shared codebases.
Choose:
  (y) commit on <CURRENT_BRANCH> anyway
  (n) cancel and let me switch branches myself
```

Wait for explicit user input.

- If the user answers `y`: proceed to the same auto-generation flow as CASE B (no manual subject required), then commit on `<CURRENT_BRANCH>`.
- If the user answers `n` (or anything else): print `[PASS] Commit cancelled. Use \`git checkout -b <new-branch>\` and re-run /commit.` and stop.

**Never run `git checkout -b` from inside this command.** Branch creation is the user's decision, not the command's.

### CASE B — Safe branch

Generate a conventional commit message automatically from the staged diff.

Run: `git diff --cached --stat`

**Derive commit type** using semantic signals (evaluate in order):

| Priority | Condition | Type |
|---|---|---|
| 1 | `HAS_TESTS > 0` | `test` |
| 2 | `HAS_NEW > 0` AND content adds exported functions/classes | `feat` |
| 3 | diff content matches `fix\|bug\|error\|crash\|null\|undefined` | `fix` |
| 4 | only `.md` / doc files | `docs` |
| 5 | performance-focused change | `perf` |
| 6 | default | `refactor` |

**Derive scope** — find the dominant top-level directory:

Run:
```
git diff --cached --name-only | awk -F/ '{print $1}' | sort | uniq -c | sort -nr | head -1 | awk '{print $2}'
```

Use the result as scope. If the result is a file (no `/` in path), use its basename without extension.

**Generate subject**: `<type>(<scope>): <summary>`
- Summary must reflect the actual diff — no vague words like "update", "changes", "fix stuff"
- 72 characters max
- No trailing period
- No Claude attribution, no emoji

**Validate subject** before proceeding:
- Must match: `^(feat|fix|refactor|docs|chore|style|test|perf)\([^)]+\): .{1,50}$`
- Must not exceed 72 characters total
- If either check fails, regenerate once. If it still fails, fall back to CASE A (ask user).

**Generate description** (body): 2–5 bullet points using `-`
- Each bullet is one concrete fact from the diff
- No vague filler, no Claude attribution
- Append metadata line: `affects: <TOTAL_FILES> file(s) on <CURRENT_BRANCH>`

**If the original prompt contained `--y`**: skip preview and confirmation — proceed directly to Step 7.

**Otherwise**:
```
Generated commit:
  Subject:     <subject>
  Description:
    - <bullet 1>
    ...
    affects: <N> file(s) on <branch>
```
Ask: "Proceed? (y/n)" — if not `y`, print `[PASS] Commit cancelled.` and stop.

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

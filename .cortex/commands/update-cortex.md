# /update-cortex — Safe Framework Update System

## STEP 1 — Verify .cortex structure

Check that `.cortex/base/` exists in the current working directory.

### Case A — .cortex/base/ does not exist

Clone Cortex into `.cortex/base/`:
```
git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base
```

If clone fails:
```
[FAIL]

TYPE: ERROR
TITLE: Clone failed
DETAILS: git clone exited non-zero — remote may be unreachable or URL is incorrect
WHY: cannot update .cortex/base/ without a valid clone
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

Skip to Step 4.

### Case B — .cortex/base/ exists but is NOT a git repository

```
[FAIL]

TYPE: ERROR
TITLE: .cortex/base/ is not a git repository
DETAILS: .cortex/base/ exists but contains no .git/ directory
WHY: git fetch cannot run in a non-repository directory — updates cannot be pulled
FIX: delete .cortex/base/ manually, then re-run /update-cortex
```
Stop. Do NOT delete automatically.

---

## STEP 2 — Fetch remote changes

Inside `.cortex/base/`, run:
```
git fetch origin
```

If fetch fails:
```
[FAIL]

TYPE: ERROR
TITLE: Fetch failed
DETAILS: git fetch origin exited non-zero in .cortex/base/
WHY: cannot determine what has changed remotely without a successful fetch
FIX: verify network access and git remote configuration in .cortex/base/, then re-run /update-cortex
```
Stop.

---

## STEP 3 — Show diff and require confirmation

Run inside `.cortex/base/`: `git diff HEAD origin/main -- .`

If no changes:
```
[PASS]

Already up to date — no changes from remote.
```
Stop.

If there are changes: display the full diff to the user.

Ask exactly:
> "Apply these changes to .cortex/base/? (yes/no)"

Wait for explicit user input. If the answer is anything other than `yes`: stop without modifying any files. Print: `Update cancelled — no changes made.`

---

## STEP 4 — Apply update

Inside `.cortex/base/`, run:
```
git reset --hard origin/main
```

Do NOT touch `.cortex/local/` at any point.
Do NOT overwrite `.claude/` or any other project files outside `.cortex/base/`.

If merge conflicts arise during any git operation: DO NOT auto-resolve. Present the conflicting hunks to the user and wait for explicit instructions. Never pick a side or discard changes without user approval.

---

## STEP 5 — Run /init-cortex automatically

After the base update completes, run `/init-cortex` immediately.

Do NOT ask the user whether to run it — this is mandatory after every update.

---

## STEP 6 — Report

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on the outcome.

Then print:

```
=== UPDATE-CORTEX REPORT ===
Generated: <timestamp>

[BASE]
  Status:        UPDATED | CLONED | NO_CHANGE
  Latest commit: <hash> — <message>

[LOCAL OVERRIDES]
  .cortex/local/ preserved — untouched

[HOOKS REDEPLOYED]
  (output from /init-cortex below)
```

Follow with the full /init-cortex report output.

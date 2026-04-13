# /update-cortex — Safe Framework Update System

CORTEX_URL = `https://github.com/SubhanAmrslnv/Cortex.git`

---

## PRE-FLIGHT — Network reachability

Before touching any files, verify GitHub is reachable:
```
curl -s --connect-timeout 5 -o /dev/null -w "%{http_code}" https://github.com
```

If the HTTP status is not 200 (or curl exits non-zero):
```
[FAIL]

TYPE: ERROR
TITLE: GitHub unreachable
DETAILS: curl to https://github.com returned <status> or timed out
WHY: cannot clone or fetch without network access — all git operations would fail
FIX: check your network connection, then re-run /update-cortex
```
Stop.

---

## STEP 1 — Verify .cortex/base/ state

Check whether `.cortex/base/` exists AND whether it is a valid git repository.

A valid git repository must pass BOTH:
- `.cortex/base/.git/config` exists
- `git -C .cortex/base/ rev-parse --git-dir` exits 0

### Case A — .cortex/base/ does not exist

Clone Cortex:
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

Set `BASE_STATUS = CLONED`. Skip to Step 5.

### Case B — .cortex/base/ exists but fails the validity check

Auto-recover without prompting:

1. Run `rm -rf .cortex/base/`
2. Print: `[AUTO-FIX] .cortex/base/ was not a valid git repository — deleted and re-cloning…`
3. Clone fresh: `git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base`

If clone fails after auto-delete:
```
[FAIL]

TYPE: ERROR
TITLE: Re-clone failed after auto-fix
DETAILS: rm -rf succeeded but git clone exited non-zero
WHY: remote may be unreachable or URL is incorrect
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

Set `BASE_STATUS = CLONED`. Skip to Step 5.

### Case C — .cortex/base/ exists and is a valid git repository

Continue to Step 2.

---

## STEP 2 — Validate remote and fetch

### 2a — Verify remote URL

Run inside `.cortex/base/`:
```
git config --get remote.origin.url
```

If the URL does not match `https://github.com/SubhanAmrslnv/Cortex.git`:
```
[WARN]

TYPE: WARNING
TITLE: Unexpected remote origin
DETAILS: remote.origin.url is <actual-url>, expected https://github.com/SubhanAmrslnv/Cortex.git
WHY: fetching from a different remote may apply changes from an unofficial or forked repository
```
Ask the user: `Remote origin does not match the official Cortex repo. Proceed anyway? (yes/no)`

If the answer is not `yes`: print `Update cancelled — no changes made.` Stop.

### 2b — Fetch remote changes

Run inside `.cortex/base/`:
```
git fetch origin
```

If fetch fails, auto-recover:

1. Run `rm -rf .cortex/base/`
2. Print: `[AUTO-FIX] git fetch failed — deleted .cortex/base/ and re-cloning…`
3. Clone fresh: `git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base`

If clone fails after auto-delete:
```
[FAIL]

TYPE: ERROR
TITLE: Re-clone failed after fetch auto-fix
DETAILS: git fetch failed and re-clone also exited non-zero
WHY: remote may be unreachable, network is down, or URL is incorrect
FIX: verify network access and that https://github.com/SubhanAmrslnv/Cortex.git is reachable, then re-run /update-cortex
```
Stop.

If re-clone succeeds: set `BASE_STATUS = CLONED`. Skip to Step 5.

### 2c — Detect default branch

Run inside `.cortex/base/`:
```
git rev-parse --abbrev-ref origin/HEAD 2>/dev/null | cut -d/ -f2
```

If this returns a non-empty string, save it as `DEFAULT_BRANCH`. Otherwise default to `main`.

Use `DEFAULT_BRANCH` (not the hardcoded string `main`) in all subsequent git operations.

---

## STEP 3 — Pre-reset safety checks

### 3a — Dirty working tree check

Run inside `.cortex/base/`:
```
git status --short
```

If output is non-empty, print the dirty files to the user and ask:
> "`.cortex/base/` has uncommitted changes that will be discarded by the reset. Proceed? (yes/no)"

If the answer is not `yes`: print `Update cancelled — no changes made.` Stop.

### 3b — Disk space check

Run:
```
df -h .cortex/base/ | awk 'NR==2 {print $4}'
```

If available space is less than 100 MB:
```
[FAIL]

TYPE: ERROR
TITLE: Insufficient disk space
DETAILS: less than 100 MB available in the current filesystem
WHY: a partial reset would leave .cortex/base/ in a corrupted state
FIX: free up disk space, then re-run /update-cortex
```
Stop.

---

## STEP 4 — Show diff and require confirmation

Run inside `.cortex/base/`:
```
git diff HEAD origin/$DEFAULT_BRANCH -- .
```

Capture diff line count:
```
git diff HEAD origin/$DEFAULT_BRANCH -- . | wc -l
```

If no changes (diff is empty):
```
[PASS]

Already up to date — no changes from remote.
```
Set `BASE_STATUS = NO_CHANGE`. Skip to Step 6 (do NOT run /init-cortex — nothing changed).

If diff line count > 500:
- Show only the stat summary: `git diff --stat HEAD origin/$DEFAULT_BRANCH -- .`
- Print: `[INFO] Diff is large (> 500 lines). Showing summary only.`
- Ask: `Display full diff before deciding? (yes/no)` — if yes, show full diff; if no, proceed with summary.

Otherwise show the full diff.

If the diff touches `cortex.config.json`:
```
[WARN]

TYPE: WARNING
TITLE: cortex.config.json will be overwritten
DETAILS: the update includes changes to cortex.config.json — any local edits in .cortex/base/ will be lost
WHY: git reset --hard discards all local modifications
```

Ask exactly:
> "Apply these changes to .cortex/base/? (yes/no)"

Wait for explicit user input. If the answer is anything other than `yes`: print `Update cancelled — no changes made.` Stop.

Save the stat summary for the Step 6 report:
```
git diff --stat HEAD origin/$DEFAULT_BRANCH -- .
```

---

## STEP 5 — Apply update

Inside `.cortex/base/`, run:
```
git reset --hard origin/$DEFAULT_BRANCH
```

Do NOT touch `.cortex/local/` at any point.
Do NOT overwrite `.claude/` or any other project files outside `.cortex/base/`.

If `git reset --hard` exits non-zero:
- Check for merge conflicts: `git status | grep "both modified"`
- If conflicts found: present the conflicting files to the user. Ask them to resolve or re-clone. Never auto-resolve.
- If no conflicts, suggest: `git checkout -f HEAD -- .` then retry the reset once. If it still fails, report verbatim git error and stop.

### 5a — Post-reset integrity check

Verify that the reset left `.cortex/base/` in a usable state. Check that these files exist and are valid JSON:
- `.cortex/base/.cortex/registry/hooks.json`
- `.cortex/base/.cortex/registry/commands.json`

Run: `jq empty <file>` for each. If any file is missing or fails JSON validation:
```
[FAIL]

TYPE: ERROR
TITLE: Post-update integrity check failed
DETAILS: <file> is missing or contains invalid JSON after reset
WHY: the updated .cortex/base/ is corrupted — deploying from it would break the framework
FIX: run `rm -rf .cortex/base/` then re-run /update-cortex to clone fresh
```
Stop.

Set `BASE_STATUS = UPDATED`.

---

## STEP 6 — Run /init-cortex

Only run `/init-cortex` if `BASE_STATUS` is `UPDATED` or `CLONED` — skip entirely if `NO_CHANGE`.

Do NOT ask the user whether to run it — this is mandatory after an update.

Capture the full output of `/init-cortex` for the Step 7 report.

---

## STEP 7 — Report

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on the outcome.

Then print:

```
=== UPDATE-CORTEX REPORT ===
Generated: <YYYY-MM-DD HH:MM:SS UTC>

[BASE]
  Status:        UPDATED | CLONED | NO_CHANGE
  Branch:        <DEFAULT_BRANCH>
  Latest commit: <hash> — <message>

[CHANGES]
  <n> files changed, <+m> insertions, <-p> deletions
  (omit if NO_CHANGE or CLONED)

[LOCAL OVERRIDES]
  .cortex/local/ preserved — untouched

[HOOKS]
  <hook-name>   DEPLOYED | UPDATED | SKIPPED   <version>
  ...
  (omit if NO_CHANGE — hooks were not redeployed)
```

Follow with the full /init-cortex report output (omit if NO_CHANGE).

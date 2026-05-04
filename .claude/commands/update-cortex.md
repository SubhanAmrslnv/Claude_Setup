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

## STEP 0 — Remote SHA comparison (early-exit check)

Resolve CORTEX_ROOT:
```bash
CORTEX_ROOT="${CORTEX_ROOT:-$(pwd)/.claude}"
VERSION_FILE="$CORTEX_ROOT/state/cortex-version.json"
```

Fetch the latest commit SHA from the remote main branch (lightweight — no clone needed):
```bash
REMOTE_SHA=$(git ls-remote https://github.com/SubhanAmrslnv/Cortex.git refs/heads/main 2>/dev/null | cut -f1)
```

If this command fails or returns an empty string:
- Print: `[WARN] Could not fetch remote SHA — skipping SHA comparison, proceeding with standard update flow.`
- Set `REMOTE_SHA=""` and continue to STEP 1.

If `REMOTE_SHA` is non-empty, read the stored SHA:
```bash
STORED_SHA=$(jq -r '.remoteCommit // empty' "$VERSION_FILE" 2>/dev/null)
```

If `STORED_SHA` is non-empty AND equals `REMOTE_SHA`:
```
[PASS]

Already up to date — local installation matches remote main.
Commit: <REMOTE_SHA>

No files were modified.
```
Stop. Do NOT run /init-cortex (nothing changed).

Otherwise continue to STEP 1. Save `REMOTE_SHA` and `STORED_SHA` as variables for use in STEP 5a and STEP 7.

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

### Pre-apply snapshot (rollback baseline)

Before running `git reset --hard`, record the current HEAD so the update can be rolled back if it partially fails:
```bash
ROLLBACK_SHA=$(git -C .cortex/base/ rev-parse HEAD 2>/dev/null)
```

If `ROLLBACK_SHA` is empty (no commits yet — first-time clone path), skip rollback tracking.

### Apply

Inside `.cortex/base/`, run:
```
git reset --hard origin/$DEFAULT_BRANCH
```

Do NOT touch `.cortex/local/` at any point.
Do NOT overwrite `.claude/` or any other project files outside `.cortex/base/`.

If `git reset --hard` exits non-zero:

1. Attempt rollback immediately:
   ```bash
   git -C .cortex/base/ reset --hard "$ROLLBACK_SHA" 2>/dev/null
   ```
2. If rollback succeeds: report `[AUTO-ROLLBACK] Restored .cortex/base/ to $ROLLBACK_SHA`.
3. If rollback also fails: report the rollback failure verbatim and instruct the user to run `rm -rf .cortex/base/` then re-run `/update-cortex`.

Then classify the original failure:
- Check for merge conflicts: `git status | grep "both modified"`
- If conflicts found: present the conflicting files to the user. Ask them to resolve or re-clone. Never auto-resolve.
- If no conflicts, suggest: `git checkout -f HEAD -- .` then retry the reset once. If it still fails, report verbatim git error and stop.

### Post-reset integrity check

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

## STEP 5b — Scanner update filter (existing-only)

After the reset, prune any scanner directories that are new in the remote but do not already exist in the local installation. This prevents `/update-cortex` from silently introducing scanners for languages the project has never used.

### 5b-i — Snapshot local scanner set

Read the set of scanner directories currently installed under `$CORTEX_ROOT/core/scanners/`:
```bash
LOCAL_SCANNERS=$(ls -d "$CORTEX_ROOT/core/scanners/"*/ 2>/dev/null | xargs -I{} basename {} | sort)
```

If `$CORTEX_ROOT/core/scanners/` does not exist or is empty, skip this step entirely (nothing to protect).

### 5b-ii — Identify new remote scanners

List scanner directories present in the fetched remote base:
```bash
REMOTE_SCANNER_ROOT=".cortex/base/.claude/core/scanners"   # adjust if the remote layout uses a different path
REMOTE_SCANNERS=$(ls -d "$REMOTE_SCANNER_ROOT/"*/ 2>/dev/null | xargs -I{} basename {} | sort)
```

Compute the set difference — directories in remote but NOT in local:
```bash
NEW_SCANNERS=$(comm -13 <(echo "$LOCAL_SCANNERS") <(echo "$REMOTE_SCANNERS"))
```

### 5b-iii — Remove new-remote-only scanners from the base snapshot

For each directory name in `NEW_SCANNERS`:

1. **Path traversal safety check** (same rules as `/init-cortex` STEP 6b):
   - Resolve absolute path: `CANDIDATE=$(cd "$REMOTE_SCANNER_ROOT/$dir" 2>/dev/null && pwd)`
   - Verify it starts with the resolved `$REMOTE_SCANNER_ROOT` absolute path
   - Verify basename matches `^[a-zA-Z0-9_-]+$`
   - Verify it is a real directory, not a symlink: `[ -d "$CANDIDATE" ] && [ ! -L "$CANDIDATE" ]`
   - If any check fails: skip silently (do not delete, do not error)

2. Run: `rm -rf "$CANDIDATE"`

3. Record: `[SCANNER FILTER] Skipped new remote scanner: <dir> (not in local installation)`

If `NEW_SCANNERS` is empty, record: `[SCANNER FILTER] No new remote scanners — nothing filtered`

### 5b-iv — Report

Print a one-line summary at the end of this step:
```
[SCANNER FILTER] Local: <N> scanners | Remote new (skipped): <M> | Will update: <local set>
```

---

## STEP 5a — Persist remote version

Resolve the new commit SHA. Prefer `REMOTE_SHA` fetched in STEP 0. If it is empty (fetch failed earlier), read it from the local clone:
```bash
NEW_COMMIT=$([ -n "$REMOTE_SHA" ] && echo "$REMOTE_SHA" || git -C .cortex/base/ rev-parse HEAD 2>/dev/null)
```

Write `.claude/state/cortex-version.json` (CORTEX_ROOT is `$(pwd)/.claude` or `$CORTEX_ROOT`):
```bash
mkdir -p "$CORTEX_ROOT/state"
cat > "$CORTEX_ROOT/state/cortex-version.json" <<EOF
{
  "remoteCommit": "$NEW_COMMIT",
  "updatedAt": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "sourceBranch": "$DEFAULT_BRANCH"
}
EOF
```

Safety rules for this write:
- NEVER overwrite any file under `.claude/local/`.
- NEVER overwrite any other file under `.claude/state/` (only `cortex-version.json` is touched).
- If `mkdir -p` or the write fails, print a warning and continue — do NOT stop. The update itself already succeeded.

```
[WARN] (only if write failed)

TYPE: WARNING
TITLE: Version file write failed
DETAILS: .claude/state/cortex-version.json could not be written
WHY: disk permissions or space issue
FIX: manually create the file or check permissions on .claude/state/
```

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

[SCANNER FILTER]
  Local scanners:   <list of existing scanner dirs>
  Remote new (skipped): <list | none>
  Updated:          <list of scanners that received changes>

[HOOKS]
  <hook-name>   DEPLOYED | UPDATED | SKIPPED   <version>
  ...
  (omit if NO_CHANGE — hooks were not redeployed)
```

Follow with the full /init-cortex report output (omit if NO_CHANGE).

Then print the final summary block (always, regardless of NO_CHANGE):

```
Cortex Update Complete
Previous Commit: <STORED_SHA | "none">
New Commit:      <NEW_COMMIT | "unchanged">
Files Updated:   <N from diff stat | 0 if NO_CHANGE>
Init Cortex:     Success | Skipped | Failed
```

- `Previous Commit`: the `remoteCommit` value read from `cortex-version.json` before this run (or `"none"` if the file did not exist).
- `New Commit`: the commit SHA written to `cortex-version.json` in STEP 5a (or `"unchanged"` if BASE_STATUS is NO_CHANGE).
- `Files Updated`: the count of files listed in the diff stat (`0` if NO_CHANGE or CLONED with no prior base).
- `Init Cortex`: `Success` if /init-cortex ran and exited 0, `Failed` if it exited non-zero, `Skipped` if BASE_STATUS was NO_CHANGE.

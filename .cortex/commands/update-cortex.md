Safely update the Cortex base layer in this project while preserving local overrides.

CONTEXT:
- `.cortex/base/` contains the canonical framework files pulled from the remote Cortex repository.
- `.cortex/local/` contains project-specific overrides and must NEVER be modified.
- The remote Cortex repository URL is: https://github.com/SubhanAmrslnv/Cortex.git

## Step 1 — Verify .cortex structure

Check that `.cortex/base/` exists in the current project.

- If `.cortex/base/` does NOT exist:
  - Clone Cortex into `.cortex/base/`: `git clone https://github.com/SubhanAmrslnv/Cortex.git .cortex/base`
  - Skip to Step 4.

- If `.cortex/base/` exists but is not a git repository:
  - Stop. Report: "ERROR: .cortex/base/ exists but is not a git repository. Delete it manually and re-run /update-cortex."
  - Do not delete automatically.

## Step 2 — Fetch remote changes

Inside `.cortex/base/`, run:

```
git fetch origin
```

If fetch fails, stop and report the error.

## Step 3 — Show diff and require confirmation

Run: `git diff HEAD origin/main -- .`

If there are no changes: report "Already up to date — no changes from remote." and stop.

If there are changes:
- Display the diff to the user.
- Ask: "Apply these changes to .cortex/base/? (yes/no)"
- Wait for explicit user input.
- If user says anything other than "yes": stop without modifying any files.

## Step 4 — Apply update

Inside `.cortex/base/`, run:

```
git reset --hard origin/main
```

Do NOT touch `.cortex/local/` at any point.
Do NOT overwrite `.claude/` or any other project files.

## Step 5 — Run /init

After updating base, run `/init` to redeploy any updated hooks to `~/.claude/hooks/` using version-aware deployment.

## Step 6 — Report

```
=== UPDATE-CORTEX REPORT ===

[BASE]
  Status:        UPDATED | CLONED | NO_CHANGE
  Latest commit: <hash> — <message>

[HOOKS REDEPLOYED]
  <hook-name>    UPDATED | SKIPPED | WARNING
  ...

[LOCAL OVERRIDES]
  .cortex/local/ preserved — untouched
```

CONFLICT HANDLING:
- If any merge conflicts arise, DO NOT auto-resolve them.
- Present the conflicting hunks to the user and wait for explicit instructions.
- Never pick a side or discard changes without user approval.

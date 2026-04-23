# Usage

## Running the project

Cortex has no server or process to start — it runs passively through Claude Code's hook system. Once installed, hooks fire automatically on every tool invocation.

To confirm hooks are active in a session:

```
/doctor
```

To manually test a hook outside Claude Code:

```bash
echo '{"tool":"Bash","input":{"command":"git push --force origin main"}}' \
  | bash ~/.claude/core/hooks/guards/pre-guard.sh
```

---

## Configuration options

| Option | Where | Effect |
|---|---|---|
| `CORTEX_ROOT` | Environment variable | Overrides the `.claude/` location used by all hooks |
| `.claude/local/` | Directory | Place project-specific overrides here; never touched by updates |
| `.claude/config/cortex.config.json` | File | Framework version and default runtime paths; `riskThresholds` is overridable |
| `.claude/settings.json` | File | Hook event wiring; edit only to add or remove hook events |

To add a project-specific override without modifying the base framework, create the override file under `.claude/local/` using the same relative path as the original.

---

## Common workflows

### 1. Committing changes

Run the interactive commit command:

```
/commit
```

The command inspects staged changes, generates a conventional commit message, prompts for confirmation, routes to the correct branch, and blocks if you are on a protected branch.

### 2. Checking impact before merging

Before raising a PR, trace the blast radius of your changes:

```
/impact --staged
```

Or against a specific ref:

```
/impact --since=main
```

Each changed file is classified by architectural role (Controller / Service / Repository / etc.) and assigned LOW / MEDIUM / HIGH risk with a FIX recommendation.

### 3. Running a pre-merge validation

Simulate full PR validation locally:

```
/pr-check
```

Or against a specific branch:

```
/pr-check --branch=feature/my-branch
```

Six checks run in sequence: build, format, security scan, architecture, conventional commit validation, and test presence. Result is ACCEPTED / WARNING / REJECTED.

### 4. Detecting code quality regressions

Save a baseline:

```
/regression --save
```

Later, compare against it:

```
/regression
```

New issues and severity escalations since the baseline commit are reported as regressions with a root-cause trace via `git log`.

### 5. Finding high-risk files

Surface files that are most likely to contain bugs or cause merge conflicts:

```
/hotspot --top=10
```

Files are scored by `(change_freq × 3) + (size_lines / 50) + (dep_count × 2)`. Files scoring ≥40 are HIGH, 20–39 are MEDIUM.

---

## Troubleshooting

### Hooks are not firing

**Symptom:** No security warnings, no format output, no audit log entries.

**Resolution:**
1. Verify `.claude/settings.json` exists in your project root
2. Run `/doctor` — it will identify missing or misconfigured hooks
3. Check that `jq` is on `$PATH`: `jq --version`
4. Verify `CORTEX_ROOT` resolves correctly: `echo ${CORTEX_ROOT:-$(pwd)/.claude}`

### `/doctor` reports version mismatch

**Symptom:** `pre-guard.sh` or another hook shows a version different from the registry.

**Resolution:** Run `/init-cortex`. It compares source vs deployed versions and redeploys only what changed.

### `jq: command not found` in hook output

**Symptom:** All hooks silently no-op; audit log is empty.

**Resolution:** Install `jq` (see [setup.md](setup.md)). This is the most common cause of a non-functional Cortex install.

### `pre-guard.sh` is blocking a legitimate command

**Symptom:** A safe Bash command is blocked with risk score ≥70.

**Resolution:** Review the structured JSON reason output. If the block is incorrect, adjust the command to avoid the flagged pattern (e.g., use `git push` without `--force`). To lower thresholds, edit `riskThresholds` in `.claude/config/cortex.config.json`. Do not bypass the guard with `--no-verify`.

### Session profiling skips on every start

**Symptom:** `project-profile.json` is never updated even after changing dependencies.

**Resolution:** `session-start.sh` uses a fingerprint to skip unchanged projects. Delete `.claude/cache/project-profile.json` to force a fresh profile on next session start.

### Scan cache is returning stale results

**Symptom:** Security scanner reports an issue in a file that has been fixed.

**Resolution:** Delete `.claude/cache/scans/` to clear the hash-based scan cache. It will be rebuilt on the next file write. Entries also auto-prune after 7 days.

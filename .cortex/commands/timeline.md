# /timeline — Cortex Code Evolution Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--file=<path>` → analyze evolution of a specific file (required unless `--module` is set)
- `--module=<dir>` → analyze all files under a directory as a single module
- `--depth=<n>` → limit to the last N commits (default: all history)
- `--since=<date>` → limit to commits after this date (e.g., `--since=2024-01-01`)

If neither `--file` nor `--module` is provided and no path is in `$ARGUMENTS`: stop and report:
```
Usage: /timeline --file=<path> | --module=<dir> [--depth=<n>] [--since=<date>]
```

---

## STEP 1 — Collect commit history

**For `--file=<path>`:**
```
git log --follow --pretty=format:"%H %ai %s" -- <path>
```
The `--follow` flag traces renames.

**For `--module=<dir>`:**
```
git log --pretty=format:"%H %ai %s" -- <dir>
```

Apply `--depth` and/or `--since` if provided.

Save result as `COMMITS`: a list of `{ hash, datetime, message }` ordered newest-first.

If `COMMITS` is empty:
```
[INFO]

No commit history found for the specified target.
```
Stop.

Also collect per-commit diff stats:
```
git log --follow --stat --pretty=format:"%H" -- <path>
```
Save as `DIFF_STATS[hash] = { files_changed, insertions, deletions }`.

For `--module`: use `git log --stat --pretty=format:"%H" -- <dir>` and aggregate stats per commit.

Save:
- `TOTAL_COMMITS` = count of COMMITS
- `FIRST_COMMIT` = oldest entry (hash, date, message)
- `LAST_COMMIT` = newest entry (hash, date, message)
- `DATE_RANGE` = FIRST_COMMIT.date → LAST_COMMIT.date
- `ACTIVE_AUTHORS` = `git log --follow --pretty=format:"%an" -- <path> | sort -u`

---

## STEP 2 — Classify each commit by change type

For each commit in `COMMITS`, classify its `message` against conventional commit prefixes and keywords:

| Class | Detection signals |
|---|---|
| `INITIAL` | first commit in history for this file; message contains "init", "add", "create", "initial" |
| `FEATURE` | message starts with `feat`; contains "add", "implement", "support", "introduce" |
| `FIX` | message starts with `fix`; contains "fix", "bug", "patch", "correct", "resolve" |
| `REFACTOR` | message starts with `refactor`; contains "refactor", "restructure", "rewrite", "cleanup", "clean up", "simplify", "move", "rename", "migrate" |
| `DOCS` | message starts with `docs`; contains "doc", "comment", "readme" |
| `CHORE` | message starts with `chore`, `style`, `test`, `perf`; contains "bump", "update deps", "version" |
| `HOTFIX` | message contains "hotfix", "urgent", "emergency", "critical fix", "quick fix" |
| `REVERT` | message starts with "revert" or "Revert" |

If a message matches multiple classes, assign the highest-priority match in the order listed above.
If no class matches: assign `UNKNOWN`.

Save as `COMMIT_CLASS[hash] = class`.

---

## STEP 3 — Group commits into phases

Divide `COMMITS` into chronological phases based on the dominant change type in each temporal cluster.

**Algorithm:**
1. Reverse `COMMITS` to chronological order (oldest first).
2. Use a sliding window of 20% of `TOTAL_COMMITS` (minimum 3, maximum 15) to group commits.
3. For each window, compute the dominant class (most frequent `COMMIT_CLASS` in the window).
4. A new phase begins when the dominant class changes between consecutive windows.
5. Merge consecutive windows with the same dominant class into a single phase.
6. Cap at 6 phases — if more would result, merge the smallest adjacent phases.

For each phase, record:
```
PHASES[n] = {
  index: n,
  start_date: <first commit date in phase>,
  end_date: <last commit date in phase>,
  commit_count: <count>,
  dominant_class: <class>,
  total_insertions: <sum>,
  total_deletions: <sum>,
  messages: [<list of commit messages in phase>]
}
```

**Phase naming** — assign a label based on dominant class:

| Dominant class | Phase label |
|---|---|
| `INITIAL` | Initial Implementation |
| `FEATURE` | Feature Growth |
| `FIX` | Bug Fix Cycle |
| `HOTFIX` | Hotfix Pressure |
| `REFACTOR` | Refactor / Stabilization |
| `CHORE` | Maintenance |
| `REVERT` | Instability (Reverts) |
| `UNKNOWN` | Unclassified Changes |

---

## STEP 4 — Detect instability signals

Across all `COMMITS`, compute:

- `FIX_RATIO` = count(FIX + HOTFIX) / TOTAL_COMMITS
- `REVERT_COUNT` = count(REVERT commits)
- `CHURN_RATE` = (total insertions + total deletions) / TOTAL_COMMITS
- `FIX_AFTER_REFACTOR` = count of FIX commits within 5 commits following a REFACTOR commit
- `REPEATED_FIX_WINDOW` = any 10-commit window where FIX_RATIO > 50%

Flag signals:
- `FIX_RATIO > 0.30` → `SIGNAL_HIGH_FIX_RATIO`
- `REVERT_COUNT >= 2` → `SIGNAL_REVERTS`
- `FIX_AFTER_REFACTOR >= 2` → `SIGNAL_REFACTOR_INSTABILITY` (refactors introducing bugs)
- `REPEATED_FIX_WINDOW` exists → `SIGNAL_FIX_CLUSTER`
- Last phase dominant class is `FIX` or `HOTFIX` → `SIGNAL_CURRENT_PRESSURE`
- Last phase dominant class is `REFACTOR` and commit count in last phase ≥ 3 → `SIGNAL_ACTIVE_STABILIZATION`

---

## STEP 5 — Determine current state

Apply this decision table (first matching row wins):

| Condition | State |
|---|---|
| `SIGNAL_REVERTS` + `SIGNAL_HIGH_FIX_RATIO` | `DEGRADED` |
| `SIGNAL_FIX_CLUSTER` + `SIGNAL_CURRENT_PRESSURE` | `DEGRADED` |
| `SIGNAL_REFACTOR_INSTABILITY` | `DEGRADED` |
| `SIGNAL_HIGH_FIX_RATIO` (no reverts) | `EVOLVING` |
| `SIGNAL_ACTIVE_STABILIZATION` | `EVOLVING` |
| Last phase is `FEATURE` with no following FIX phase | `EVOLVING` |
| Last phase is `REFACTOR` or `CHORE` with FIX_RATIO < 0.15 | `STABLE` |
| Last phase is `FEATURE` with FIX_RATIO < 0.15 overall | `STABLE` |
| No signals triggered | `STABLE` |

Map state to status:
- `DEGRADED` → `[WARN]`
- `EVOLVING` → `[INFO]`
- `STABLE` → `[INFO]`

---

## STEP 6 — Generate WHY explanation

Produce one paragraph tracing the causal chain from early phases to current state:
- Name the phases in order and what they indicate about the file's trajectory
- Cite specific signal values (e.g., "FIX_RATIO of 0.42", "3 reverts", "2 fixes within 5 commits of refactor")
- Explain what the current state means for maintainability and future changes
- No vague language — every claim must reference a phase index, signal, or commit count

---

## STEP 7 — Generate FIX (DEGRADED only)

If state is `DEGRADED`, provide ONE refactor direction:

Select the most applicable based on dominant signals:

- `SIGNAL_REVERTS` dominant: "The repeated reverts indicate unstable invariants in `<construct>` — extract the volatile logic into a separate function with explicit preconditions documented as assertions, making the boundaries testable in isolation."
- `SIGNAL_FIX_CLUSTER` dominant: "The fix cluster between `<start_date>` and `<end_date>` traces to `<phase description>` — the root cause is likely an untested assumption; add a characterization test covering the current behavior before the next change."
- `SIGNAL_REFACTOR_INSTABILITY` dominant: "Refactors in Phase `<n>` consistently introduced bugs — the refactors changed structure without updating callers; map all consumers via Grep before the next structural change and update them atomically."

Do NOT generate a FIX for STABLE or EVOLVING states.
Do NOT provide multiple options.

---

## OUTPUT

```
[INFO | WARN]

EVOLUTION TIMELINE:
  File:          <path or module dir>
  Total commits: <TOTAL_COMMITS>
  Date range:    <DATE_RANGE>
  Authors:       <ACTIVE_AUTHORS count> (<list if ≤ 3, else "N contributors">)
  Phases:        <phase count>
```

For each phase (chronological order):

```
* Phase <n>: <label> (<start_date> → <end_date>)
  Commits:    <commit_count>
  Net change: +<insertions> / -<deletions>
  Signal:     <dominant signal if any, else "none">
  Summary:    <3–5 representative commit messages, truncated to 72 chars each>
```

Then:

```
CURRENT STATE: STABLE | EVOLVING | DEGRADED

SIGNALS DETECTED:
  - <signal name>: <value> (e.g., FIX_RATIO: 0.38)
  - ...
  (or "None" if no signals triggered)

WHY:
<one paragraph — causal chain, cites phases and signal values>
```

If DEGRADED:
```
FIX:
<single refactor direction>
```

---

## CONSTRAINTS

- Never fabricate phases — phases must derive from actual commit groupings
- Never assign a phase label without a dominant class computed from real commit messages
- Never claim a signal without computing its value from git history
- Never generate a FIX for STABLE or EVOLVING states
- Never summarize commits with vague language ("various changes", "multiple updates") — list actual messages
- Never output more than 6 phases regardless of history length

# /hotspot — Cortex Hotspot Analysis Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--since=<ref>` → limit history to commits reachable from `<ref>` (e.g., `--since=main`, `--since=90.days.ago`)
- `--top=<n>` → limit output to top N hotspots (default: 10)
- `--deep` → include dependency tracing via Grep for each hotspot

Default (no flags): analyze full git history, top 10 hotspots.

---

## STEP 1 — Collect commit frequency per file

Run:
```
git log --pretty=format:"%H" [--since=<ref>] | xargs -I{} git diff-tree --no-commit-id -r --name-only {} | sort | uniq -c | sort -rn
```

If `--since=<ref>` is provided, pass it as `--since=<ref>` to `git log`.

Save result as `CHANGE_FREQ_MAP`: a list of `(count, filepath)` pairs.

If the map is empty:
```
[PASS]

No commit history found — nothing to analyze.
```
Stop.

Collapse path aliases caused by renames: if the same logical file appears under two paths (detectable via `git log --diff-filter=R --summary`), sum their counts and attribute to the current path.

---

## STEP 2 — Collect file sizes

For each file in `CHANGE_FREQ_MAP` that currently exists on disk, run:
```
wc -l <filepath>
```

Save as `SIZE_MAP[filepath] = line_count`.

Files that no longer exist (deleted) receive `size = 0` and are excluded from hotspot scoring.

---

## STEP 3 — Collect dependency counts

For each file still on disk:

**If `--deep` flag is set:**
Use Grep to count how many other tracked files reference this file by name (basename without extension). Save as `DEP_MAP[filepath] = reference_count`.

**Without `--deep`:**
Use a fast heuristic: count how many other files in `CHANGE_FREQ_MAP` share a common path prefix at depth-2 (same subsystem). This approximates coupling without full Grep traversal. Save as `DEP_MAP[filepath] = heuristic_count`.

Do NOT search inside: `node_modules/`, `bin/`, `obj/`, `dist/`, `.git/`, `*.lock`, `*.log`.

---

## STEP 4 — Score each file

For each file, compute a composite `HOTSPOT_SCORE`:

```
HOTSPOT_SCORE = (change_freq × 3) + (size_lines / 50) + (dep_count × 2)
```

Score components:
| Component | Weight | Rationale |
|---|---|---|
| `change_freq` | ×3 | Primary instability signal |
| `size_lines / 50` | ×1 | Complexity proxy (normalized) |
| `dep_count` | ×2 | Blast radius multiplier |

Assign `RISK_LEVEL`:
| Score | Risk |
|---|---|
| ≥ 40 | HIGH |
| 20–39 | MEDIUM |
| < 20 | LOW (exclude from output) |

Map risk to status (worst across all hotspots):
- Any HIGH → `[FAIL]`
- All MEDIUM, no HIGH → `[WARN]`
- All LOW → `[PASS]`

Sort results by `HOTSPOT_SCORE` descending. Take top `N` where N = `--top` value (default 10). Exclude LOW-risk files from output.

---

## STEP 5 — Generate WHY explanation per file

For each hotspot, produce a concise explanation referencing:
- Exact change count from git history
- Line count from disk
- Which structural migrations or renames inflated the count (if detectable from `git log --diff-filter=R`)
- What other files reference it (if `--deep`)

No vague statements. Every claim must cite a number from Steps 1–3.

---

## STEP 6 — Generate FIX recommendation per file

**If RISK is HIGH:**
Give ONE specific structural recommendation:
- If file is a central registry/config: "Generate this file from source-of-truth data rather than hand-maintaining it"
- If file is a large monolithic script (>150 lines): "Split into `<name>-core` (engine) and `<name>-rules` (data/config) modules"
- If file is documentation kept in sync manually: "Generate the volatile sections from registry data; hand-maintain only policy sections"
- If file is a single point of wiring/adapter: "Add a validation step (e.g., `/doctor` check) that detects drift rather than requiring manual edits"

**If RISK is MEDIUM:**
Give ONE targeted recommendation:
- "Add a change-detection test or checksum that fails CI when this file changes without a corresponding registry update"
- "Extract the <specific section> into a separate file to isolate future changes"

Select the most applicable recommendation. ONE fix only.

---

## OUTPUT

Print:

```
[PASS | WARN | FAIL]

HOTSPOT SUMMARY:
  Files analyzed:   <total files in history>
  Hotspots found:   <count of MEDIUM+ files>
  Commits scanned:  <total commit count>
  History range:    <oldest commit date> → <newest commit date>

HOTSPOTS:
```

For each hotspot (sorted by score descending):

```
* File: <relative/path/to/file>
  SCORE:   <numeric>
  CHANGES: <count>
  LINES:   <line_count>
  DEPS:    <dep_count>
  RISK:    HIGH | MEDIUM

  REASON:
  - <reason bullet 1 — must cite a number>
  - <reason bullet 2>
  - <reason bullet 3 if applicable>

  WHY:
  <one technical paragraph — no vague statements>

  FIX:
  <single deterministic recommendation>
```

Then print:

```
STABILITY INDEX: <score 0–100>
```

Compute as: `100 - (sum of HIGH scores × 2 + sum of MEDIUM scores) / total_files_analyzed × 100`, clamped to [0, 100]. Higher = more stable.

---

## CONSTRAINTS

- Never score a file without real data from git history
- Never assign HIGH risk based on change count alone — score formula must be applied
- Never output a FIX with multiple options — ONE recommendation only
- Never include files that no longer exist on disk
- Never claim a dependency without either a Grep result (`--deep`) or an explicit co-change count (default mode)
- Collapse rename aliases before scoring — a file that moved paths is one file, not two

# Commands

All commands are invoked inside Claude Code as `/command-name`. Each command is implemented as a Markdown file in `.cortex/commands/` and validated against `.cortex/registry/commands.json` before execution.

---

## Command summary

| Command | Flags | Description |
|---|---|---|
| `/init-cortex` | — | Deploy hooks, validate registry, validate settings |
| `/commit` | — | Interactive conventional commit with branch routing and auto-generated message |
| `/doctor` | `--fix` `--deep` `--dry-run` | Full system diagnostics across hooks, settings, registry, and scanners |
| `/update-cortex` | — | Fetch framework updates from remote with diff preview before applying |
| `/impact` | `--staged` `--deep` `--since=<ref>` | Trace changed files through the dependency graph; assign risk level |
| `/regression` | `--save` `--reset` `--since=<ref>` `--deep` | Compare current diagnostics against a saved baseline |
| `/hotspot` | `--since=<ref>` `--top=<n>` `--deep` | Score files by change frequency, size, and dependency count |
| `/pr-check` | `--branch=<name>` `--staged` `--skip-build` `--skip-tests` | Simulate full PR validation locally |
| `/pattern-drift` | `--since=<ref>` `--deep` `--layer=<name>` | Detect deviations from dominant project coding patterns |
| `/optimize` | `--file=<path>` `--lang=<lang>` `--focus=perf\|clarity` | Optimize code for performance and readability |
| `/overengineering-check` | `--file=<path>` `--since=<ref>` `--deep` | Detect unnecessary abstractions and structural complexity |
| `/timeline` | `--file=<path>` `--module=<dir>` `--depth=<n>` `--since=<date>` | Analyze file evolution through git history; classify stability |
| `/documentation` | — | Generate or update a structured `documentation/` folder |

---

## Per-command reference

### `/init-cortex`

**Purpose:** Version-aware hook deployment and registry validation. Run after initial setup and after any hook update.

**What it does:**
- Compares `# @version:` tags in source files against deployed hook versions
- Redeploys only hooks where source is newer than runtime
- Validates `settings.json` wiring against `registry/hooks.json`
- Validates `registry/commands.json` and `registry/scanners.json`
- Prints a structured report: status per hook, command, and scanner

**Usage example:**
```
/init-cortex
```

---

### `/commit`

**Purpose:** Interactive conventional commit workflow with auto-generated message and branch protection.

**What it does:**
- Inspects staged changes and generates a conventional commit message
- Validates format: `type(scope): message`
- Blocks commits to `main`, `master`, or `develop` branches
- Prompts for confirmation before committing
- Enforces no Claude/Anthropic attribution in commit messages

**Usage example:**
```
/commit
```

---

### `/doctor`

**Purpose:** Full system diagnostics — verify every component of the Cortex install.

**Flags:**

| Flag | Description |
|---|---|
| `--fix` | Auto-apply safe fixes (redeploy hooks, set permissions) |
| `--deep` | Run extended architecture checks |
| `--dry-run` | Simulate fixes without applying them |

**What it checks:**
- All hooks are deployed and match registry versions
- `settings.json` wires every hook correctly
- All scanner scripts exist
- `jq` and `node` are on `$PATH`

**Usage example:**
```
/doctor --fix
/doctor --deep --dry-run
```

---

### `/update-cortex`

**Purpose:** Safely fetch and apply framework updates from the remote repository.

**What it does:**
1. Fetches changes from the remote repository
2. Shows a diff of what changed in `.cortex/base/`
3. Requires confirmation before applying
4. Updates `.cortex/base/` only — `.cortex/local/` overrides are never touched
5. Re-runs `/init-cortex` to redeploy any updated hooks

**Usage example:**
```
/update-cortex
```

---

### `/impact`

**Purpose:** Trace changed files through the dependency graph and assign a risk level before merging.

**Flags:**

| Flag | Description |
|---|---|
| `--staged` | Analyze only staged files |
| `--deep` | Include transitive consumers |
| `--since=<ref>` | Analyze files changed since a git ref (commit, branch, tag) |

**Output:** Each changed file is classified by architectural role (Controller / Service / Repository / DTO / Configuration / Schema / Hook / Scanner), consumers are traced via Grep, and the file is assigned LOW / MEDIUM / HIGH risk with a single FIX recommendation.

**Usage example:**
```
/impact --staged
/impact --since=main --deep
```

---

### `/regression`

**Purpose:** Detect new issues and severity escalations since a saved diagnostic baseline.

**Flags:**

| Flag | Description |
|---|---|
| `--save` | Save the current `/doctor` output as the baseline snapshot |
| `--reset` | Delete the current snapshot |
| `--since=<ref>` | Restrict analysis to changes since a git ref |
| `--deep` | Run extended checks before comparing |

**What it does:** Issues are fingerprinted for stable cross-session comparison. New issues and escalated severities since the snapshot commit are reported as regressions; root cause is traced via `git log` between snapshot commit and HEAD. State stored in `.cortex/state/snapshot.json`.

**Usage example:**
```
/regression --save
/regression
/regression --since=v1.0.0 --deep
```

---

### `/hotspot`

**Purpose:** Score files by risk and surface the highest-risk areas in the codebase.

**Flags:**

| Flag | Description |
|---|---|
| `--since=<ref>` | Limit change frequency count to commits since a git ref |
| `--top=<n>` | Show only the top N results (default: all) |
| `--deep` | Include transitive dependency analysis |

**Scoring formula:** `(change_freq × 3) + (size_lines / 50) + (dep_count × 2)`

- Score ≥ 40 → HIGH
- Score 20–39 → MEDIUM
- Score < 20 → LOW

Outputs a Stability Index (0–100) for the repository overall.

**Usage example:**
```
/hotspot --top=10
/hotspot --since=v1.0.0 --top=5
```

---

### `/pr-check`

**Purpose:** Simulate full PR validation locally before submitting.

**Flags:**

| Flag | Description |
|---|---|
| `--branch=<name>` | Check a specific branch (default: current) |
| `--staged` | Include staged-only changes |
| `--skip-build` | Skip the build step |
| `--skip-tests` | Skip test presence check |

**Six checks run in sequence:**
1. Build — blocks on failure
2. Format — warns on violations
3. Security scan — blocks on any finding
4. Architecture — blocks on structural violations
5. Conventional commit validation — blocks on Claude attribution or malformed messages
6. Test presence — warns if no tests found

Result is **ACCEPTED**, **WARNING**, or **REJECTED**.

**Usage example:**
```
/pr-check
/pr-check --branch=feature/auth --skip-build
```

---

### `/pattern-drift`

**Purpose:** Detect files that deviate from the dominant coding patterns in the codebase.

**Flags:**

| Flag | Description |
|---|---|
| `--since=<ref>` | Limit analysis to files changed since a ref |
| `--deep` | Analyze more files for pattern inference |
| `--layer=<name>` | Restrict to a specific architectural layer |

**How it works:** Infers dominant patterns from unchanged files at ≥60% prevalence. Isolated deviations are flagged as FAIL; multi-file deviations (possible intentional migration) are flagged as WARN. Test files are never flagged.

**Usage example:**
```
/pattern-drift
/pattern-drift --since=main --layer=services
```

---

### `/optimize`

**Purpose:** Optimize code for performance and readability without changing signatures or behavior.

**Flags:**

| Flag | Description |
|---|---|
| `--file=<path>` | Target a specific file |
| `--lang=<lang>` | Override language detection |
| `--focus=perf\|clarity` | Focus on performance or readability (default: both) |

**What it detects:**
- Performance: N+1 queries, O(n²) loops, missing async
- Complexity: deep nesting, methods over 50 lines
- Redundancy: dead assignments, duplicate conditions

Never changes function signatures or introduces new abstractions.

**Usage example:**
```
/optimize --file=src/services/UserService.ts --focus=perf
```

---

### `/overengineering-check`

**Purpose:** Detect unnecessary abstractions, pass-through layers, unused generics, and redundant DTOs.

**Flags:**

| Flag | Description |
|---|---|
| `--file=<path>` | Target a specific file |
| `--since=<ref>` | Limit to files changed since a ref |
| `--deep` | Include transitive abstraction chain analysis |

**Seven named patterns detected:**
- `SINGLE_IMPL_INTERFACE` — interface with only one implementation
- `PASSTHROUGH_ABSTRACTION` — layer that adds no logic
- `UNUSED_GENERICS` — generic type parameters that are never varied
- `STRUCTURAL_NESTING` — excessive directory depth without separation of concerns
- `SINGLE_USE_FACTORY` — factory that creates only one type
- `REDUNDANT_DTO` — DTO that mirrors its entity exactly
- `MULTI_RESPONSIBILITY_HOOK` / `MIXED_SCANNER` — hook or scanner with mixed concerns

Validates simplification safety before flagging as actionable.

**Usage example:**
```
/overengineering-check
/overengineering-check --file=src/factories/UserFactory.cs
```

---

### `/timeline`

**Purpose:** Analyze a file's evolution through git history and classify its stability.

**Flags:**

| Flag | Description |
|---|---|
| `--file=<path>` | Target file (required unless `--module` is given) |
| `--module=<dir>` | Analyze all files in a directory |
| `--depth=<n>` | Number of commits to analyze |
| `--since=<date>` | Restrict to commits after a date |

**Stability states:** STABLE / EVOLVING / DEGRADED

**Instability signals computed:**
- `FIX_RATIO` — proportion of commits that are bug fixes
- `REVERT_COUNT` — number of reverts in the window
- `SIGNAL_REFACTOR_INSTABILITY` — refactors closely followed by fixes
- `SIGNAL_FIX_CLUSTER` — fixes grouped within a short time window

A FIX recommendation is generated only for DEGRADED state.

**Usage example:**
```
/timeline --file=.cortex/core/hooks/guards/pre-guard.sh
/timeline --module=.cortex/core/hooks/runtime --depth=50
```

---

### `/documentation`

**Purpose:** Generate or update a structured `documentation/` folder from real project analysis.

**What it does:**
- Reads `CLAUDE.md` and any existing documentation files first
- Detects project type, Cortex presence, and API surface
- Generates or updates: `README.md`, `overview.md`, `architecture.md`, `setup.md`, `usage.md`, `modules.md`
- Conditionally generates `commands.md` (Cortex active) and `api.md` (backend detected)
- Never contradicts `CLAUDE.md`; never invents features or endpoints

**Usage example:**
```
/documentation
```

---

## Adding new commands

1. Create `<command>.md` in `.cortex/commands/` with the full implementation
2. Create a thin wrapper `<command>.md` in `.claude/commands/` delegating to the command-runner
3. Add the command name to `.cortex/registry/commands.json`
4. Run `/init-cortex` to validate the registry

Thin wrapper format:
```markdown
This is a thin wrapper. The implementation lives in `.cortex/commands/<command>.md`.

1. Run `bash ${CORTEX_ROOT:-$HOME/.cortex}/core/runtime/command-runner.sh <command>`
2. Read the file path returned by the runner.
3. Read that file and follow its instructions exactly.
```

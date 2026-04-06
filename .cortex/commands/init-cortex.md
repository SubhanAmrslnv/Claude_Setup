# /init-cortex — Cortex Environment Setup and Hook Deployment

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--force` → redeploy ALL hooks regardless of version
- `--dry-run` → simulate all actions; print what would be done; apply nothing

Flags may be combined.

---

## STEP 1 — Resolve CORTEX_ROOT

Determine the absolute path to this Cortex repository (the directory containing `.cortex/`). Save it as `CORTEX_ROOT`.

If `CORTEX_ROOT` cannot be resolved (not in a Cortex repo):
```
[FAIL]

TYPE: ERROR
TITLE: CORTEX_ROOT not resolvable
DETAILS: the current working directory does not contain a .cortex/ folder
WHY: /init-cortex must run from inside the Cortex repository
FIX: cd to the Cortex repository root and re-run /init-cortex
```
Stop.

Write the following to `~/.claude/cortex.env` (create or overwrite):
```
export CORTEX_ROOT="<absolute-path>"
```

If `--dry-run`: print `[DRY-RUN] Would write CORTEX_ROOT=<path> to ~/.claude/cortex.env` and skip the write.

---

## STEP 2 — Ensure hooks directory

Check that `~/.claude/hooks/` exists.

If not and `--dry-run`: print `[DRY-RUN] Would create ~/.claude/hooks/`

If not and not `--dry-run`: run `mkdir -p ~/.claude/hooks`

---

## STEP 3 — Version-aware hook deployment

Read `$CORTEX_ROOT/.cortex/registry/hooks.json`.

If missing:
```
[FAIL]

TYPE: ERROR
TITLE: hooks.json not found
DETAILS: $CORTEX_ROOT/.cortex/registry/hooks.json does not exist
WHY: hook registry is required — cannot determine which hooks to deploy
FIX: restore hooks.json from the Cortex source repo
```
Stop.

For each entry (hook name + `source` path):

a. Resolve source: `$CORTEX_ROOT/.cortex/<source>`
b. Resolve runtime: `~/.claude/hooks/<hook-name>`
c. Extract source version from `# @version: X.Y.Z` on line 1 or 2. If absent, treat as `0.0.0`.
d. If runtime file exists, extract its version the same way. If absent, treat as `0.0.0`.
e. Compare versions (major, minor, patch as integers):

**`--force` mode**: always redeploy regardless of version comparison.

**Normal mode**:
- source > runtime OR runtime absent → deploy
- source == runtime → skip (up to date)
- source < runtime → skip and add a WARNING

Deployment (if not `--dry-run`): copy source to runtime exactly.

Record each hook as one of: `DEPLOYED` | `UPDATED` | `SKIPPED` | `WARNING`

---

## STEP 4 — Validate settings.json

Read `~/.claude/settings.json`.

If missing and not `--dry-run`: copy from `$CORTEX_ROOT/.claude/settings.json`, record as `COPIED`.
If missing and `--dry-run`: print `[DRY-RUN] Would copy settings.json from $CORTEX_ROOT/.claude/settings.json`.

If present: for each hook name in hooks.json, verify a `command` entry referencing `~/.claude/hooks/<hook-name>` exists in the hooks block.

For each absent entry, record as `INCOMPLETE` with the specific hook name missing.

Do not auto-merge a partial settings.json — report the missing entries and instruct the user to add them from `$CORTEX_ROOT/.claude/settings.json`.

---

## STEP 5 — Validate command registry

Read `$CORTEX_ROOT/.cortex/registry/commands.json`.

For each name in `commands`, check `$CORTEX_ROOT/.claude/commands/<name>.md` exists.

Record each as `OK` or `ERROR`.

---

## STEP 6 — Validate scanner availability

Read `$CORTEX_ROOT/.cortex/registry/scanners.json`.

For each extension key (excluding `*`), for each scanner path in its array, check `$CORTEX_ROOT/.cortex/core/scanners/<path>` exists.

Record each as `OK` or `WARNING (missing)`.

---

## STEP 7 — Validate hook registry consistency

For each hook in hooks.json, verify the version in hooks.json matches the `# @version:` tag in the source file.

If mismatched:
```
TYPE: WARNING
TITLE: Registry version mismatch: <hook-name>
DETAILS: hooks.json declares <registry_ver> but source file contains <source_ver>
WHY: /init-cortex version comparison uses the registry — a mismatch causes incorrect deployment decisions
FIX: update the version field for <hook-name> in hooks.json to match the source file
```

---

## OUTPUT

Print the overall status (`[PASS]`, `[WARN]`, or `[FAIL]`) based on highest severity found.

Then print the structured report:

```
=== CORTEX INIT REPORT ===
Mode: <default | --force | --dry-run | --force --dry-run>
Generated: <timestamp>

[CORTEX_ROOT]
  Path:       <resolved path>
  cortex.env: written | skipped (dry-run)

[HOOKS]
  <hook-name>    DEPLOYED | UPDATED | SKIPPED | WARNING    source: <ver> runtime: <ver>
  ...

[SETTINGS]
  ~/.claude/settings.json    OK | COPIED | INCOMPLETE
  <if INCOMPLETE: list each missing hook entry>

[COMMANDS]
  <command>    OK | ERROR
  ...

[SCANNERS]
  <ext>/<scanner>    OK | WARNING
  ...

[REGISTRY CONSISTENCY]
  <hook-name>    OK | WARNING <detail>
  ...

STATUS: PASS | WARN | FAIL
```

For each issue, also print in structured format:
```
TYPE: ERROR | WARNING
TITLE: <title>
DETAILS: <details>
WHY: <why>
FIX: <fix>
```

---

## SAVE STATE

After completion, save or update a project memory in `init_state.md` recording:
- Resolved `CORTEX_ROOT`
- Which hooks were deployed/updated/skipped
- Overall status
- Timestamp

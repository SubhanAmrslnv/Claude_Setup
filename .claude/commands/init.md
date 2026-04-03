Initialize the global Claude Code configuration for this machine.

Perform the following steps in order.

## Step 1 — Resolve Cortex root

Determine the absolute path to this Cortex repository (the directory containing `.claude/`). Save it as `CORTEX_ROOT`.

Write the following to `~/.claude/cortex.env` (create or overwrite):

```
export CORTEX_ROOT="<absolute-path-to-cortex-repo>"
```

Confirm the write succeeded.

## Step 2 — Verify hooks directory

Check that `~/.claude/hooks/` exists. If not, run: `mkdir -p ~/.claude/hooks`

## Step 3 — Version-aware hook deployment

Read `$CORTEX_ROOT/.claude/.cortex/registry/hooks.json`.

For each entry (hook name + `source` path):

a. Resolve source file: `$CORTEX_ROOT/.claude/.cortex/<source>`
b. Resolve runtime file: `~/.claude/hooks/<hook-name>`
c. Extract source version: read the source file, find the first line matching `^# @version:`, extract the version string (e.g. `1.0.0`). If absent, treat as `0.0.0`.
d. Extract runtime version: if the runtime file exists, do the same. If the file is absent, treat as `0.0.0`.
e. Compare versions — compare major, then minor, then patch as integers:
   - source > runtime OR runtime does not exist → copy source to runtime; record as DEPLOYED or UPDATED
   - source == runtime → record as SKIPPED (up to date)
   - source < runtime → do NOT overwrite; record as WARNING (runtime ahead of source)

## Step 4 — Validate settings.json

Check that `~/.claude/settings.json` exists and contains a `hooks` block wiring each hook in hooks.json via `bash ~/.claude/hooks/<hook-name>`.

- Missing file → copy from `$CORTEX_ROOT/.claude/settings.json`; record as COPIED
- File exists, all hooks wired → OK
- File exists, some entries missing → report which entries are absent; do not auto-merge; record as INCOMPLETE

## Step 5 — Validate command registry

Read `$CORTEX_ROOT/.claude/.cortex/registry/commands.json`.

For each name in the `commands` array, check that `$CORTEX_ROOT/.claude/commands/<name>.md` exists.

- Present: OK
- Missing: record ERROR

## Step 6 — Validate scanner availability

Read `$CORTEX_ROOT/.claude/.cortex/registry/scanners.json`.

For each language block, verify every path under `security_scanner` and `formatter` exists at `$CORTEX_ROOT/.claude/.cortex/<path>`.

- Present: OK
- Missing: record WARNING

## Step 7 — Print summary report

```
=== CORTEX INIT REPORT ===

[CORTEX_ROOT]
  Path:       <resolved path>
  cortex.env: written

[HOOKS]
  <hook-name>    DEPLOYED | UPDATED | SKIPPED | WARNING    <version detail>
  ...

[SETTINGS]
  ~/.claude/settings.json    OK | COPIED | INCOMPLETE
  <detail if INCOMPLETE>

[COMMANDS]
  <command>    OK | ERROR
  ...

[SCANNERS]
  <language>/<scanner>    OK | WARNING
  ...

[RESULT]
  STATUS: OK | WARNING | ERROR
```

## Step 8 — Save memory

Save or update a `project` memory recording which hooks were deployed/updated, the resolved CORTEX_ROOT, and overall status. Use memory file `init_state.md` under the project memory directory.

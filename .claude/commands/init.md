Initialize the global Claude Code configuration for this machine.

Perform the following steps in order:

## 1. Verify hooks directory
Check that `~/.claude/hooks/` exists. If not, create it.

## 2. Verify hook scripts
Check that all required hook scripts exist in `~/.claude/hooks/`:
- `pre-guard.sh`
- `post-format.sh`
- `post-secret-scan.sh`
- `post-dotnet-security-scan.sh`
- `post-audit-log.sh`
- `stop-build-and-fix.sh`

If any are missing, read the corresponding file from the current repo's `.claude/hooks/` directory and write it to `~/.claude/hooks/`.

## 3. Verify settings.json
Check that `~/.claude/settings.json` exists and contains the `hooks` key wiring all the scripts above. If missing or incomplete, copy from this repo's `.claude/settings.json`.

## 4. Report
Print a summary table of what was already present, what was created, and what still needs manual action.

## 5. Memorize
After the report, save a memory of the initialization state:
- Save or update a `project` memory recording which hooks were present and which were created.
- Use the memory file `init_state.md` under the project memory directory.
- Update the `MEMORY.md` index with a pointer to `init_state.md` if not already present.

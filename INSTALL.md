# Install Guide

---

## 1. Clone the Cortex repository

```bash
git clone https://github.com/SubhanAmrslnv/Cortex.git ~/cortex
```

Or copy it to any stable location on your machine.

---

## 2. Copy `.claude` into your project

Copy only the `.claude` folder (the adapter layer) into the root of your target project:

```bash
cp -r ~/cortex/.claude /path/to/your/project/
```

This folder contains the hook wiring (`settings.json`) and thin command wrappers. It does not contain any framework logic.

---

## 3. Run `/init`

Open Claude Code in your project directory and run:

```
/init
```

`/init` will:
- Write `~/.claude/cortex.env` pointing to the Cortex repo
- Deploy hooks to `~/.claude/hooks/` using version-aware comparison
- Validate `settings.json` wiring
- Validate command and scanner registries

Run `/init` once after setup, and again after any hook update.

---

## 4. Keep Cortex up to date

To pull the latest framework updates from the remote Cortex repository:

```
/update-cortex
```

This command:
1. Fetches changes from the remote repository
2. Shows you a diff of what changed
3. Asks for confirmation before applying anything
4. Updates only `.cortex/base/` — your local overrides in `.cortex/local/` are never touched
5. Re-runs `/init` to redeploy any updated hooks

**No destructive updates.** You always see the diff before anything changes.

---

## 5. Local overrides

To customize Cortex behavior for a specific project without affecting the base framework:

Place your overrides in `.cortex/local/`. These files are never modified by `/update-cortex`.

---

## Architecture

```
.cortex/core/       ← all framework logic (hooks, scanners, runtime)
.cortex/registry/   ← all configuration (hooks.json, scanners.json, commands.json)
.cortex/commands/   ← full command implementations
.cortex/base/       ← remote framework snapshot (auto-updated)
.cortex/local/      ← your project overrides (never auto-updated)
.claude/            ← adapter layer only (hook wiring + thin command wrappers)
```

The `.claude/` folder contains no business logic. All logic lives in `.cortex/`.

# Install Guide

---

## 1. Place the `.claude` folder

Copy the `.claude` folder into the root of your target project:

```bash
cp -r .claude /path/to/your/project/
```

This folder contains all hooks, settings, and slash commands. No additional dependencies required.

---

## 2. Run `/init`

Open Claude Code in your project directory and run:

```
/init
```

`/init` verifies that all hook scripts exist in `~/.claude/hooks/`, syncs any missing ones, and confirms `settings.json` is wired correctly. Run it once after placing the folder, and again after any hook update.

---

## 3. Keep Cortex in sync

To pull the latest hooks and commands from the central Cortex repository:

```
/update-cortex
```

This overwrites the `.claude` folder with the latest remote version. If conflicts arise, they will be presented to you for manual resolution.

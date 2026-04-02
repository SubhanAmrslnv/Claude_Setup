# Setup Guide

---

## Setup

The only required step is placing the `.claude` folder into the root of your target project:

```bash
cp -r .claude /path/to/your/project/
```

No additional installation, configuration, or setup is needed.

Open Claude Code in your project directory and run:

```
/init
```

`/init` verifies all hooks and settings are wired correctly. Run it once after placing the folder.

---

## Optional: ANTHROPIC_API_KEY

Required only if you use AI-assisted commit messages or the auto build-fix hook.

Add to your shell profile (`~/.bashrc` or `~/.zshrc`):

```bash
export ANTHROPIC_API_KEY="sk-ant-..."
```

Then reload: `source ~/.bashrc`

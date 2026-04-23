# Setup

## Prerequisites

| Tool | Version | Required | Purpose |
|---|---|---|---|
| [Claude Code](https://claude.ai/code) | Any | Yes | Runs all hooks and commands |
| `bash` | 4.0+ | Yes | All hook scripts are bash |
| `jq` | 1.7+ | Yes | JSON parsing in every hook; without it all scanning and guard logic silently no-ops |
| `git` | Any | Yes | Branch detection in pre-guard, commit command, and all analysis commands |

### Installing jq

```bash
# macOS
brew install jq

# Ubuntu / Debian
sudo apt install jq

# Windows — Scoop (recommended)
scoop install jq

# Windows — winget
winget install jqlang.jq

# Windows — Chocolatey
choco install jq
```

Verify: `jq --version` — expected: `jq-1.7.x` or later.

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/SubhanAmrslnv/Cortex.git ~/cortex
```

Or copy it to any stable location on your machine.

### 2. Make Cortex available at runtime — choose one option

**Option A — Global install (recommended)**

Copy `.claude/` to `~/.claude/` so hooks fall back to it automatically without any environment variable. Claude Code already uses `~/.claude/` as its global config directory, so this is the natural home for the framework:

```bash
cp -r ~/cortex/.claude ~/.claude
```

Or use a symlink to stay in sync with the repo:

```bash
ln -s ~/cortex/.claude ~/.claude
```

**Option B — Project-local install**

Copy `.claude/` into the root of a specific project. Cortex detects `$(pwd)/.claude` at session start and uses it automatically:

```bash
cp -r ~/cortex/.claude /path/to/your/project/.claude
```

**Option C — Environment variable (CI/CD, Docker, custom paths)**

Set `CORTEX_ROOT` to the absolute path of the `.claude/` directory:

```bash
export CORTEX_ROOT="/custom/path/to/.claude"
```

Add this to `~/.bashrc`, `~/.zshrc`, or your CI environment for persistent use.

Resolution priority: `$CORTEX_ROOT` → `$(pwd)/.claude` → `$HOME/.claude`

### 3. Deploy hooks

Open Claude Code in your project directory and run:

```
/init-cortex
```

This command version-compares each hook source against the deployed runtime, deploys only what changed, validates `settings.json` wiring against the registry, and prints a structured status report per hook, command, and scanner.

---

## Environment configuration

| Variable | Required | Default | Description |
|---|---|---|---|
| `CORTEX_ROOT` | No | `$(pwd)/.claude` → `$HOME/.claude` | Absolute path to the `.claude/` directory. Set when using a non-standard install location. |

No secrets or API keys are required. Cortex runs entirely locally.

The framework version and runtime paths are stored in `.claude/config/cortex.config.json`. You should not need to edit this file directly. Risk thresholds (`warn=30`, `block=70`) can be overridden per-project by editing `riskThresholds` in this file.

---

## Verification

Run the diagnostics command after setup:

```
/doctor
```

This checks:
- All hooks are deployed and match registry versions
- `settings.json` wires every hook correctly
- All scanner scripts exist and are executable
- `jq` is available on `$PATH`

Expected output: all checks green. If any check fails, run `/doctor --fix` to apply safe automated fixes.

To verify a specific hook manually:

```bash
echo '{"tool":"Bash","input":{"command":"rm -rf /"}}' | bash ~/.claude/core/hooks/guards/pre-guard.sh
```

Expected: exit 1 with a structured JSON block reason.

To run the full smoke test suite:

```bash
bash .claude/test/run.sh
```

Runs 13 fixture-based tests covering pre-guard, post-error-analyzer, and post-scan. All should pass on a correctly installed system.

# Installation & Setup Guide

Complete setup guide for Git, Claude Code, and this global configuration on a new Windows machine.

---

## Quick Setup

1. Drag and drop the `.claude` folder into your project or home directory
2. Open Claude Code and type `/init`

That's it — `/init` will verify all hooks, scripts, and settings are wired correctly.

---

---

## 1. Install Git

**Download:** https://git-scm.com/download/win

During installation, select:
- Default editor: your preferred editor (VS Code recommended)
- `Git from the command line and also from 3rd-party software`
- `Use bundled OpenSSH`
- `Use the OpenSSL library`
- `Checkout Windows-style, commit Unix-style line endings`
- `Use MinTTY` (Git Bash terminal)

Verify:
```bash
git --version
```

---

## 2. Configure Git Identity

```bash
git config --global user.name "SubhanAmrslnv"
git config --global user.email "emraslanovsupan290@gmail.com"
```

Recommended globals:
```bash
git config --global core.autocrlf true        # Windows line endings
git config --global init.defaultBranch main   # default branch name
git config --global pull.rebase true          # rebase on pull
git config --global fetch.prune true          # clean stale remote refs
```

---

## 3. Install Required Tools

The hooks in this config depend on the following tools being available in Git Bash:

### jq (JSON parser — required by all hooks)
```bash
# Download jq.exe from https://jqlang.github.io/jq/download/
# Place jq.exe in C:\Program Files\Git\usr\bin\
jq --version
```

### Node.js + npm (required for Prettier, ESLint)
Download: https://nodejs.org (LTS version)
```bash
node --version
npm --version
```

### .NET SDK (required for dotnet format)
Download: https://dotnet.microsoft.com/download
```bash
dotnet --version
```

---

## 4. Install Claude Code

```bash
npm install -g @anthropic-ai/claude-code
claude --version
```

---

## 5. Clone and Link This Config

```bash
git clone https://github.com/SubhanAmrslnv/Claude_Setup.git
```

The `.claude/` directory in this repo is your global Claude Code configuration.
Claude Code automatically picks it up when run from this directory.

To make hooks available globally, run `/init` inside Claude Code after cloning —
it will verify all hook scripts and settings are in place.

---

## 6. Install Prettier and ESLint Globally

Used by `post-format.sh` for TypeScript/React projects:
```bash
npm install -g prettier eslint
```

---

## 7. Verify Setup

Open Git Bash and run:
```bash
git config --list --global     # confirm identity and settings
jq --version                   # confirm jq
dotnet --version               # confirm .NET SDK
node --version                 # confirm Node.js
claude --version               # confirm Claude Code
```

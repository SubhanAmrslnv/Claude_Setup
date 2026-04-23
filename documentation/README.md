# Cortex — Documentation Index

Cortex is a modular Claude DevOps configuration framework: a portable system of hooks, scanners, and slash commands that extends Claude Code with automated security scanning, formatting, risk-gating, and code analysis across any project.

---

## Quick Start

1. Clone the repository and copy `.claude/` to `~/.claude/` (or any location; set `$CORTEX_ROOT` if non-standard)
2. Copy `.claude/` into the root of each project you want Cortex active in
3. Open Claude Code in that project and run `/init-cortex`
4. Run `/doctor` to verify the install
5. Use any `/command` listed below

---

## Documentation Index

- [overview.md](overview.md) — Project purpose and problem statement
- [architecture.md](architecture.md) — System design and layer responsibilities
- [setup.md](setup.md) — Installation and environment setup
- [usage.md](usage.md) — How to run and use the project day-to-day
- [commands.md](commands.md) — Full Cortex slash command reference
- [modules.md](modules.md) — Modules, folders, and responsibilities
- [HLD.docx](HLD.docx) — High Level Design document (enterprise architecture artifact)

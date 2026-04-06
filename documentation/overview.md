# Overview

## What it is

Cortex is a modular Claude DevOps configuration framework — a portable set of shell scripts, JSON registries, and Markdown command definitions that wire directly into Claude Code's hook system. It adds automated security scanning, file formatting, risk-gating, code intelligence, and structured slash commands to any project without requiring changes to application code. No application lives in this repository; everything is infrastructure for Claude's own behavior.

## Problem it solves

Claude Code, by default, executes tool calls with no enforcement layer: destructive commands run without warning, files are written without security checks, and there is no persistent audit trail. Cortex addresses this by inserting a scoring-based risk engine before every Bash invocation, running security and format scanners after every file write, and providing a structured command layer for common DevOps workflows (commits, PR validation, dependency tracing, hotspot detection, and more).

## Who it is for

Developers and teams using Claude Code who want automated safeguards, consistent code hygiene enforcement, and structured DevOps workflows without manually writing Claude configuration for each project. Cortex is designed to be installed once globally and adopted per-project by copying a single adapter folder.

## Key capabilities

- **Risk-scored command gating** — pre-guard scores every Bash command across 6 risk categories (destructive ops, privilege escalation, dangerous flags, security threats, sensitive files, protected branches) and blocks, warns, or silently allows based on score thresholds
- **Registry-driven security scanning** — 25 language scanners triggered automatically on every file write, dispatched by file extension from a central registry
- **Registry-driven formatting** — format scripts for all supported languages run on every Edit/Write without per-project configuration
- **Audit logging** — every tool use appended to `~/.claude/audit.log` for full session traceability
- **Code intelligence** — post-write analysis of `.cs`, `.js`, `.ts`, `.jsx`, `.tsx` files for complexity, duplication, naming, and structural issues
- **Structured slash commands** — 13 commands covering commits, diagnostics, dependency impact, regression detection, hotspot scoring, PR simulation, pattern drift, code optimization, overengineering detection, timeline analysis, and documentation generation
- **Session-aware prompt optimization** — project profile is built at session start and injected as structured context into every prompt
- **Error classification** — when a tool invocation fails, the error is classified and a structured fix suggestion is emitted automatically

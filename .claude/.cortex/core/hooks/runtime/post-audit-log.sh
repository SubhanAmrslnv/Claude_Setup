#!/usr/bin/env bash
# @version: 1.0.0
# PostToolUse audit logger — appends every tool use to ~/.claude/audit.log.

echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TOOL_NAME: $TOOL_INPUT" >> ~/.claude/audit.log

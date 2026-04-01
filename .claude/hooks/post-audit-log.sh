#!/usr/bin/env bash
# Appends every tool use to ~/.claude/audit.log for session review.

echo "[$(date '+%Y-%m-%d %H:%M:%S')] $TOOL_NAME: $TOOL_INPUT" >> ~/.claude/audit.log
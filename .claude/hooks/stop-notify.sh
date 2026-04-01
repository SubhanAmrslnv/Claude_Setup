#!/usr/bin/env bash
# Shows a Windows desktop notification when Claude finishes a task.

powershell -Command "
  [System.Reflection.Assembly]::LoadWithPartialName('System.Windows.Forms') | Out-Null
  [System.Windows.Forms.MessageBox]::Show('Claude Code finished', 'Done')
" 2>/dev/null || true
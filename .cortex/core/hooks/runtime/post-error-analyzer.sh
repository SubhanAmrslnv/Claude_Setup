#!/usr/bin/env bash
# @version: 1.0.1
# PostToolUseFailure error analyzer — parses stderr, classifies error type,
# extracts file/line, identifies root cause, emits a fix suggestion.
# Reads payload from stdin. Always exits 0.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.cortex" ]; then
    export CORTEX_ROOT="$(pwd)/.cortex"
  else
    export CORTEX_ROOT="$HOME/.cortex"
  fi
fi
command -v jq &>/dev/null || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

stderr=$(echo "$input" | jq -r '.stderr // .error_output // empty' 2>/dev/null)
[[ -z "$stderr" ]] && exit 0

# ─── Classification (first match wins) ──────────────────────────────────────

type="unknown"

if echo "$stderr" | grep -qiE 'cannot find module|module not found|unresolved import|package .* not found|npm err|pip.*not found|go: no module|failed to resolve'; then
  type="dependency_error"
elif echo "$stderr" | grep -qiE 'permission denied|eacces|access is denied|operation not permitted'; then
  type="permission_error"
elif echo "$stderr" | grep -qiE 'syntaxerror|parse error|unexpected token|unexpected end|invalid syntax|unexpected identifier|unterminated string|compilation error'; then
  type="syntax_error"
elif echo "$stderr" | grep -qiE 'build failed|compilation failed|error cs[0-9]+|error ts[0-9]+|linker error|cargo.*error\[E|javac.*error'; then
  type="build_error"
elif echo "$stderr" | grep -qiE 'nullreferenceexception|typeerror|referenceerror|rangeerror|segmentation fault|sigsegv|stack overflow|out of memory|panic:|fatal error|uncaught exception'; then
  type="runtime_error"
elif echo "$stderr" | grep -qiE 'econnrefused|enotfound|etimedout|connection refused|could not resolve host|ssl.*error|certificate.*error'; then
  type="network_error"
elif echo "$stderr" | grep -qiE 'timed? ?out|deadline exceeded'; then
  type="timeout_error"
fi

# ─── File + line extraction ──────────────────────────────────────────────────

file=""
line=""

# "File.cs:45" / "file.ts:12:5" / "file.py, line 12" / "File "x.py", line 12" / "File.cs(45,1)"
raw=$(echo "$stderr" | grep -oiE \
  '([^ "'"'"']+\.[a-z]{1,6}):([0-9]+):[0-9]+|'\
'([^ "'"'"']+\.[a-z]{1,6})\(([0-9]+),[0-9]+\)|'\
'File "([^"]+)", line ([0-9]+)|'\
'([^ "'"'"']+\.[a-z]{1,6}), line ([0-9]+)|'\
'at [^ ]+\.[a-z]{1,6}:[0-9]+' \
  | head -1)

if [[ -n "$raw" ]]; then
  file=$(echo "$raw" | grep -oiE '[^ "'"'"'(,]+\.[a-z]{1,6}' | head -1)
  line=$(echo "$raw" | grep -oE '[0-9]+' | head -1)
fi

# ─── Message — first line containing "error" keyword ────────────────────────

message=$(echo "$stderr" \
  | grep -im1 'error\|fatal\|panic\|exception\|failed' \
  | sed 's/^[[:space:]]*//' \
  | cut -c1-200)
[[ -z "$message" ]] && message=$(echo "$stderr" | head -1 | cut -c1-200)

# ─── Root cause ──────────────────────────────────────────────────────────────

root_cause="Could not determine root cause from available output"

if echo "$stderr" | grep -qiE 'nullreferenceexception|cannot read prop.*null|is null|is undefined'; then
  root_cause="Null or undefined value accessed without a guard check"
elif echo "$stderr" | grep -qiE 'cannot find module|module not found|unresolved import'; then
  root_cause="Required module or package is not installed"
elif echo "$stderr" | grep -qiE 'permission denied|eacces|access is denied'; then
  root_cause="Process lacks required filesystem or OS permissions"
elif echo "$stderr" | grep -qiE 'command not found|is not recognized'; then
  root_cause="Required CLI tool is not installed or not on PATH"
elif echo "$stderr" | grep -qiE 'syntaxerror|unexpected token|invalid syntax|parse error'; then
  root_cause="Source file contains a syntax error preventing parsing"
elif echo "$stderr" | grep -qiE 'econnrefused|connection refused'; then
  root_cause="Target service is not running or the port is wrong"
elif echo "$stderr" | grep -qiE 'enotfound|could not resolve host'; then
  root_cause="Hostname does not resolve — DNS failure or typo"
elif echo "$stderr" | grep -qiE 'out of memory|heap.*out of memory'; then
  root_cause="Process exhausted available heap memory"
elif echo "$stderr" | grep -qiE 'stack overflow'; then
  root_cause="Infinite or excessively deep recursion"
elif echo "$stderr" | grep -qiE 'segmentation fault|sigsegv'; then
  root_cause="Invalid memory access — likely a dangling pointer or buffer overrun"
elif echo "$stderr" | grep -qiE 'typeerror.*is not a function'; then
  root_cause="Calling a value that is not a function — wrong type or missing import"
elif echo "$stderr" | grep -qiE 'referenceerror|is not defined'; then
  root_cause="Variable or function used before declaration or import"
elif echo "$stderr" | grep -qiE 'build failed|compilation failed|error cs[0-9]+|error ts[0-9]+'; then
  root_cause="Compile-time error in source code — check the reported file and line"
fi

# ─── Suggestion ──────────────────────────────────────────────────────────────

suggestion="Review the full error output and check the reported file and line number"

if echo "$stderr" | grep -qiE 'nullreferenceexception|cannot read prop.*null|is null'; then
  suggestion="Add a null/undefined guard before accessing the value (e.g. \`if (x != null)\` or \`x?.prop\`)"
elif echo "$stderr" | grep -qiE 'cannot find module|module not found'; then
  suggestion="Run \`npm install\` (Node) / \`pip install <pkg>\` (Python) / \`go mod tidy\` (Go)"
elif echo "$stderr" | grep -qiE 'unresolved import'; then
  suggestion="Add the missing import/using statement or install the package"
elif echo "$stderr" | grep -qiE 'permission denied|eacces'; then
  suggestion="Check ownership with \`ls -la\` and fix with \`chmod\` or run as the correct user"
elif echo "$stderr" | grep -qiE 'command not found|is not recognized'; then
  suggestion="Install the missing tool and ensure it is on PATH; verify with \`which <tool>\`"
elif echo "$stderr" | grep -qiE 'syntaxerror|unexpected token|invalid syntax'; then
  suggestion="Open the reported file at the indicated line and fix the syntax error"
elif echo "$stderr" | grep -qiE 'econnrefused|connection refused'; then
  suggestion="Verify the target service is running and the host/port are correct"
elif echo "$stderr" | grep -qiE 'enotfound|could not resolve host'; then
  suggestion="Check hostname spelling and DNS; try \`nslookup <host>\`"
elif echo "$stderr" | grep -qiE 'out of memory|heap.*out of memory'; then
  suggestion="Increase heap size (e.g. \`node --max-old-space-size=4096\`) or reduce memory usage"
elif echo "$stderr" | grep -qiE 'stack overflow'; then
  suggestion="Add a recursion base case or convert to an iterative approach"
elif echo "$stderr" | grep -qiE 'segmentation fault|sigsegv'; then
  suggestion="Run under gdb/lldb or valgrind to locate the invalid memory access"
elif echo "$stderr" | grep -qiE 'typeerror.*is not a function'; then
  suggestion="Verify the variable type before calling it; check imports and API surface"
elif echo "$stderr" | grep -qiE 'referenceerror|is not defined'; then
  suggestion="Declare or import the identifier before use; check for typos"
elif echo "$stderr" | grep -qiE 'error ts[0-9]+'; then
  suggestion="Run \`tsc --noEmit\` locally to see the full TypeScript error and fix the type mismatch"
elif echo "$stderr" | grep -qiE 'build failed|error cs[0-9]+'; then
  suggestion="Review the compiler error at the reported file:line and fix the type or syntax issue"
fi

# ─── Output ──────────────────────────────────────────────────────────────────

jq -n \
  --arg type       "$type" \
  --arg file       "$file" \
  --arg line       "$line" \
  --arg message    "$message" \
  --arg rootCause  "$root_cause" \
  --arg suggestion "$suggestion" \
  '{
    type:       $type,
    file:       (if $file != "" then $file else null end),
    line:       (if $line != "" then ($line | tonumber) else null end),
    message:    $message,
    rootCause:  $rootCause,
    suggestion: $suggestion
  } | with_entries(select(.value != null))'

exit 0

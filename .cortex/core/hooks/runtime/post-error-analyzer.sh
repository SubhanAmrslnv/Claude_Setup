#!/usr/bin/env bash
# @version: 1.1.0
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

# ─── Single-pass classifier: type + root_cause + suggestion set together ────
# Eliminates a full second pass through identical patterns.

type="unknown"
root_cause="Could not determine root cause from available output"
suggestion="Review the full error output and check the reported file and line number"

if echo "$stderr" | grep -qiE 'nullreferenceexception|cannot read prop.*null|is null|is undefined'; then
  type="runtime_error"
  root_cause="Null or undefined value accessed without a guard check"
  suggestion="Add a null/undefined guard before accessing the value (e.g. \`if (x != null)\` or \`x?.prop\`)"
elif echo "$stderr" | grep -qiE 'typeerror.*is not a function'; then
  type="runtime_error"
  root_cause="Calling a value that is not a function — wrong type or missing import"
  suggestion="Verify the variable type before calling it; check imports and API surface"
elif echo "$stderr" | grep -qiE 'referenceerror|is not defined'; then
  type="runtime_error"
  root_cause="Variable or function used before declaration or import"
  suggestion="Declare or import the identifier before use; check for typos"
elif echo "$stderr" | grep -qiE 'stack overflow'; then
  type="runtime_error"
  root_cause="Infinite or excessively deep recursion"
  suggestion="Add a recursion base case or convert to an iterative approach"
elif echo "$stderr" | grep -qiE 'segmentation fault|sigsegv'; then
  type="runtime_error"
  root_cause="Invalid memory access — likely a dangling pointer or buffer overrun"
  suggestion="Run under gdb/lldb or valgrind to locate the invalid memory access"
elif echo "$stderr" | grep -qiE 'out of memory|heap.*out of memory'; then
  type="runtime_error"
  root_cause="Process exhausted available heap memory"
  suggestion="Increase heap size (e.g. \`node --max-old-space-size=4096\`) or reduce memory usage"
elif echo "$stderr" | grep -qiE 'panic:|fatal error|uncaught exception'; then
  type="runtime_error"
  root_cause="Unhandled fatal error or panic condition"
  suggestion="Check the stack trace for the panic location and add error handling"
elif echo "$stderr" | grep -qiE 'unresolved import'; then
  type="dependency_error"
  root_cause="Required module or package is not installed"
  suggestion="Add the missing import/using statement or install the package"
elif echo "$stderr" | grep -qiE 'cannot find module|module not found|package .* not found|npm err|pip.*not found|go: no module|failed to resolve'; then
  type="dependency_error"
  root_cause="Required module or package is not installed"
  suggestion="Run \`npm install\` (Node) / \`pip install <pkg>\` (Python) / \`go mod tidy\` (Go)"
elif echo "$stderr" | grep -qiE 'command not found|is not recognized'; then
  type="dependency_error"
  root_cause="Required CLI tool is not installed or not on PATH"
  suggestion="Install the missing tool and ensure it is on PATH; verify with \`which <tool>\`"
elif echo "$stderr" | grep -qiE 'permission denied|eacces|access is denied|operation not permitted'; then
  type="permission_error"
  root_cause="Process lacks required filesystem or OS permissions"
  suggestion="Check ownership with \`ls -la\` and fix with \`chmod\` or run as the correct user"
elif echo "$stderr" | grep -qiE 'syntaxerror|parse error|unexpected token|unexpected end|invalid syntax|unexpected identifier|unterminated string|compilation error'; then
  type="syntax_error"
  root_cause="Source file contains a syntax error preventing parsing"
  suggestion="Open the reported file at the indicated line and fix the syntax error"
elif echo "$stderr" | grep -qiE 'error ts[0-9]+'; then
  type="build_error"
  root_cause="Compile-time TypeScript error — check the reported file and line"
  suggestion="Run \`tsc --noEmit\` locally to see the full TypeScript error and fix the type mismatch"
elif echo "$stderr" | grep -qiE 'build failed|compilation failed|error cs[0-9]+|linker error|cargo.*error\[E|javac.*error'; then
  type="build_error"
  root_cause="Compile-time error in source code — check the reported file and line"
  suggestion="Review the compiler error at the reported file:line and fix the type or syntax issue"
elif echo "$stderr" | grep -qiE 'econnrefused|connection refused'; then
  type="network_error"
  root_cause="Target service is not running or the port is wrong"
  suggestion="Verify the target service is running and the host/port are correct"
elif echo "$stderr" | grep -qiE 'enotfound|could not resolve host'; then
  type="network_error"
  root_cause="Hostname does not resolve — DNS failure or typo"
  suggestion="Check hostname spelling and DNS; try \`nslookup <host>\`"
elif echo "$stderr" | grep -qiE 'ssl.*error|certificate.*error'; then
  type="network_error"
  root_cause="SSL/TLS certificate validation failure"
  suggestion="Check certificate validity and trust store configuration"
elif echo "$stderr" | grep -qiE 'etimedout|timed? ?out|deadline exceeded'; then
  type="timeout_error"
  root_cause="Operation exceeded time limit"
  suggestion="Increase timeout configuration or investigate the slow service/query"
fi

# ─── File + line extraction ──────────────────────────────────────────────────

file=""
line=""

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

# ─── Message — first line containing error keyword ───────────────────────────

message=$(echo "$stderr" \
  | grep -im1 'error\|fatal\|panic\|exception\|failed' \
  | sed 's/^[[:space:]]*//' \
  | cut -c1-200)
[[ -z "$message" ]] && message=$(echo "$stderr" | head -1 | cut -c1-200)

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

This is a thin wrapper. The implementation lives in `.cortex/commands/documentation.md`.

1. Run `bash ${CORTEX_ROOT:-$HOME/.cortex}/core/runtime/command-runner.sh documentation` to validate the command exists in the registry.
   - If it exits non-zero, report the error and stop.
2. Read the file path returned by the runner.
3. Read that file and follow its instructions exactly.

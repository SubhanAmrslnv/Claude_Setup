# /debug — Cortex Runtime-Aware Debugging Engine

Autonomous full-stack debugging that combines **runtime evidence** (logs,
processes, builds, tests, HTTP) with **static code inspection** in a single
self-healing loop.

This command no longer walks the entire repo statically. It calls
`core/debug/runtime-monitor.sh`, which fans out 5 probes in parallel via the
planner and returns a merged evidence bundle. You — the model — then reason
over evidence, propose ONE root cause, apply ONE patch, and re-run the loop
until the bundle reports `RESOLVED`.

---

## Flags

| Flag                    | Meaning                                                            |
|-------------------------|--------------------------------------------------------------------|
| `--endpoint=/path`      | Adds a synthetic HTTP probe to the DAG via `network-trace.sh`.     |
| `--error="message"`     | Pre-seeds the bundle with a user-reported error message.           |
| `--file=path/to/file`   | Narrows static retrieval to a specific file.                       |
| `--payload='<json>'`    | Body to send on the `--endpoint` probe.                            |
| `--loop`                | Uncaps the self-heal loop (default cap: 3 iterations).             |
| `--fix`                 | Output the patch only; do not apply.                               |
| `--ui` / `--backend`    | Bias retrieval to frontend or backend layers.                      |

Suffix mode is also supported: `<any prompt> /debug`.

---

## Execution Recipe

For every invocation, you (the model) MUST follow these steps in order:

### Step 1 — Collect runtime evidence

Run:
```
bash .claude/core/debug/runtime-monitor.sh
```
The output is a JSON bundle:
```json
{
  "status": "OK|PARTIAL|FAIL",
  "completed": [...],
  "results": {
    "inspect-process": { "kind": "process", "listening": [...], "processes": [...] },
    "tail-logs":       { "kind": "logs",    "errors": [...] },
    "run-build":       { "kind": "build",   "status": "OK|FAIL", "errors": [...] },
    "replay-tests":    { "kind": "tests",   "status": "OK|FAIL", "failures": [...] },
    "curl-endpoint":   { "kind": "network", "status_code": "...", "body_preview": "..." }
  }
}
```
If `--endpoint=` was given, pass it through:
```
bash .claude/core/debug/network-trace.sh --endpoint=/path
```

If a HAR file was provided under `.claude/temp/har/`, also run:
```
bash .claude/core/debug/browser-trace.sh
```

### Step 2 — Retrieve relevant code (lazy)

Call memory **only** when evidence points at a code path:
```
bash .claude/core/memory/retrieve.sh debug "<key terms from the error>"
```
Hard cap: 5 files. Do not Read them all — pick the 1–2 with the highest score
and read those.

### Step 3 — Pick the model tier (advisory)

```
MODEL=$(CORTEX_INTENT=debug bash .claude/core/router/model-router.sh)
```
Use this as guidance on how aggressively to reason. Default is sonnet for
debug. Escalate to opus only if a first pass returns `STATUS=INSUFFICIENT`.

### Step 4 — Identify ONE root cause

Build a short, evidence-citing hypothesis. Reject anything not grounded in the
bundle. Format:
```
ROOT_CAUSE: <one sentence>
EVIDENCE:
  - <probe>: <fact>
  - <probe>: <fact>
LOCATION: <file:line> or <layer>
```

### Step 5 — Apply ONE surgical patch

Use `Edit` (preferred) or `Write`. Do not introduce abstractions, do not
refactor, do not add error handling around the fix. Touch only the lines that
remove the root cause.

If `--fix` is set, print the patch and stop.

### Step 6 — Re-verify

Re-run only the probes whose failure originally surfaced:
- If `run-build` was FAIL → `bash .claude/core/debug/build-watcher.sh`
- If `replay-tests` was FAIL → `bash .claude/core/debug/test-replay.sh`
- If `curl-endpoint` was 4xx/5xx → `bash .claude/core/debug/network-trace.sh --endpoint=...`

### Step 7 — Loop or resolve

- If the re-verified probe returns OK and no other probe is FAIL → emit:
  ```
  STATUS: RESOLVED
  ```
  Then append the resolution to `.claude/project/memory/debug.json`:
  ```bash
  jq --arg rc "<root_cause>" --arg loc "<file>" \
     '.resolved += [{root_cause:$rc, location:$loc, ts:now|todate}]' \
     .claude/project/memory/debug.json > /tmp/d.json && mv /tmp/d.json .claude/project/memory/debug.json
  ```
- Otherwise → return to Step 1 (cap at 3 iterations unless `--loop`).

If the loop hits its cap without RESOLVED, emit:
```
STATUS: ESCALATE
REMAINING_EVIDENCE: <bundle>
```

---

## Hard Rules

- **Static-only fixes are forbidden.** Do not write a patch until you have
  at least one runtime evidence item (log line, build error, test failure,
  HTTP response, listening-port mismatch).
- **One patch per loop iteration.** Bundle changes are not allowed.
- **No new commands.** Do not introduce helpers, new probes, or commands —
  use only `core/debug/*` and the planner.
- **No global state.** Everything reads from `.claude/` under `$(pwd)`.
- **Token discipline.** Never paste an entire file. Read at most 60 lines
  per file in step 2.

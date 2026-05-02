# /debug — Cortex Autonomous Debugging Engine

## ACTIVATION

**Direct — with flags:**
```
/debug --endpoint=/api/cases/create
/debug --file=CaseService.cs
/debug --component=LoginForm
/debug --error="401 unauthorized"
/debug --endpoint=/api/login --deep --value --loop
/debug --file=OrderService.cs --backend --fix
/debug --payload='{"userId":1}' --endpoint=/api/orders --value
```

**Suffix mode** — append `/debug` to any natural-language prompt:
```
login returns 401 /debug
checkout button does nothing /debug
user list renders blank /debug
```

In suffix mode: strip `/debug` from the input, treat the remainder as the problem description, and proceed immediately. Never ask for clarification.

---

## FLAGS

### Core Flags

| Flag | Default | Behavior |
|---|---|---|
| `--deep` | off | Extend trace to include Middleware, Interceptors, Validators, and env/config layers not traced by default |
| `--ui` | off | Force frontend mode — always run Steps 5–6 regardless of auto-detection. Does NOT skip backend tracing |
| `--backend` | off | Restrict trace to API Route → Controller → Service → Repository → Database only; skip all frontend analysis |
| `--value` | off | Verbose value tracking — show step-by-step data flow for **every** layer, not just anomalous layers |
| `--fix` | off | Skip ISSUE and FLOW sections entirely; output only the patch and STATUS |
| `--loop` | off | Remove the 3-iteration self-healing cap; continue until `STATUS = RESOLVED` |

**Default behavior when no core flag is provided:**
- Full-stack trace across all layers
- Value tracking at anomalous layers only
- Self-healing capped at 3 iterations

### Input Flags

| Flag | Behavior |
|---|---|
| `--endpoint=<value>` | Override entry point with a specific API route (e.g., `/api/cases/create`) |
| `--file=<value>` | Override entry point with a specific file path |
| `--error="<value>"` | Treat the value as `SYMPTOM`; bypass keyword inference for symptom |
| `--payload='<json>'` | Inject this JSON as the known request payload; use concrete values in value tracking |

---

## FLAG RESOLUTION

Parse all flags from `$ARGUMENTS` immediately. Set mode variables:

```
DEEP_MODE    = true if --deep is present, else false
UI_MODE      = true if --ui is present, else false
BACKEND_MODE = true if --backend is present, else false
VALUE_MODE   = true if --value is present, else false
FIX_MODE     = true if --fix is present, else false
LOOP_MODE    = true if --loop is present, else false
```

If `--payload` is present: attempt to parse its value as JSON.
- If valid JSON: set `PAYLOAD = parsed object`
- If malformed JSON: emit inline `[PAYLOAD ERROR: invalid JSON — falling back to inferred values]` and set `PAYLOAD = null`

---

## PRIORITY RULES

Applied in order after flag parsing, before any step runs:

1. **`--backend` wins over `--ui`** — if both `BACKEND_MODE = true` and `UI_MODE = true`: force `UI_MODE = false`. Backend scope always takes precedence. Note: `--ui` without `--backend` forces frontend steps but does NOT restrict backend tracing — this asymmetry is intentional; frontend bugs often require tracing the API call the component makes.

2. **`--backend` constrains `--deep`** — if `BACKEND_MODE = true` and `DEEP_MODE = true`: extend only the backend layer set with Middleware / Interceptors / Validators; skip all frontend-side deep layers.

3. **`--ui` sets IS_FRONTEND** — if `UI_MODE = true` (and not overridden by rule 1): force `IS_FRONTEND = true` regardless of file-based auto-detection.

4. **`--fix` suppresses narrative** — if `FIX_MODE = true`: skip ISSUE and FLOW sections in output entirely; print only FIX, VERIFY, RESULT (if applicable), and STATUS.

5. **`--loop` removes the cap** — if `LOOP_MODE = true`: the 3-iteration limit in Step 10 is removed; never emit `STATUS = ESCALATE`.

---

## BEHAVIOR RULES

- Never ask questions
- Never wait for more input
- Always act immediately
- Always assume a bug exists
- Always trace the FULL flow before fixing — never stop at the first anomaly
- One root cause per round — no lists of possible causes
- One fix per round — no alternative solutions
- Re-debug after every fix until the issue is fully resolved

---

## STEP 1 — Infer the Problem

**Input flag overrides (apply first, before inference):**
- If `--endpoint` is set: use its value as `ENTRY_POINT`; set `SUSPECTED_LAYER = api`
- If `--file` is set: use its value as `ENTRY_POINT`
- If `--error` is set: use its value as `SYMPTOM`; skip keyword inference for symptom
- `PAYLOAD` is available for use in Step 4 if set

If no input flags override, parse `$ARGUMENTS` (or the suffix-mode input) to extract:

**Symptom** — what the user observed:
- HTTP status code (e.g., `401`, `500`, `404`)
- UI behavior (e.g., "blank render", "button does nothing", "layout broken")
- Data problem (e.g., "wrong value", "missing field", "NaN")
- Exception / crash — if a stack trace is present, parse it:
  - Extract the top frame: file path, line number, function name
  - Set `ENTRY_POINT` to that file and `ENTRY_LINE` to that line
  - Skip keyword inference — the stack trace is authoritative

**Entry point** — infer from keywords if not already set by a flag:
- REST endpoint → search for route definition
- Component name → search for component file
- Feature name → search for the dominant file by that name

**Suspected layer** — infer from symptom (or use override from flag):

| Symptom | Suspected layer |
|---|---|
| HTTP status code | api / auth |
| Blank / missing UI | frontend |
| Wrong data in UI | mapping or service |
| Crash / exception | runtime (any layer) |
| Styling / layout | frontend |
| Config / env error | config |
| Slow / timeout | repository or database |

**Language detection** from entry point file extension:

| Extension | Language |
|---|---|
| `.cs` | C# |
| `.ts`, `.tsx` | TypeScript |
| `.js`, `.jsx` | JavaScript |
| `.py` | Python |
| `.go` | Go |
| `.rs` | Rust |
| `.java` | Java |
| `.sh`, `.bash` | Bash |
| other | infer from content |

**Frontend detection:**
- Auto: language is TypeScript / JavaScript AND path contains `component`, `page`, `view`, `ui`, `frontend`, or extension is `.tsx`, `.jsx`, `.vue`, `.svelte`
- `UI_MODE = true` → force `IS_FRONTEND = true` (subject to priority rule 1)
- `BACKEND_MODE = true` → force `IS_FRONTEND = false`

Save:
```
SYMPTOM         = <what the user saw>
ENTRY_POINT     = <file, endpoint, or component>
ENTRY_LINE      = <line number from stack trace, or null>
SUSPECTED_LAYER = frontend | api | service | repository | database | mapping | auth | config | runtime
LANGUAGE        = <detected language>
IS_FRONTEND     = true | false
```

---

## STEP 2 — File Discovery

Before reading any code, locate the relevant files on disk.

**File index cache**: Check if `.claude/cache/project-file-index.txt` exists at the project root.
- If it exists: use it as the primary discovery source. To locate files matching `ENTRY_POINT`, grep the cache: `grep -i "<name>" .claude/cache/project-file-index.txt`. Filter the results with additional patterns as needed. Read matched files directly by their full absolute paths from the cache output.
- If missing: proceed with Grep and Glob below, and note inline: "Run /init-cortex to rebuild file index cache"

Use Grep and Glob to find files related to `ENTRY_POINT` (used as fallback when cache is absent, or to confirm ambiguous cache results):
- If `ENTRY_POINT` is an endpoint (e.g., `/api/orders`): Grep for the route string across all source files
- If `ENTRY_POINT` is a component or class name: Grep for the name, then Glob for `**/<name>.*`
- If `ENTRY_POINT` is a file path: verify it exists, then trace callers via Grep for the function/export name
- If a stack trace was parsed: start from `ENTRY_LINE` in the named file
- If `DEEP_MODE = true`: additionally Glob for middleware, interceptors, validators, and `.env` / config files in the entry path's directory tree (constrained to backend layers only if `BACKEND_MODE = true`)

Build `FILE_MAP`:
```
FILE_MAP = {
  entry: <primary file path>,
  related: [<controller>, <service>, <repository>, <model>, <test>, ...]
}
```

If no files are found via search: widen the search — grep for significant keywords from `SYMPTOM` across the source tree. If still nothing, state the search result and stop.

---

## STEP 3 — Full System Flow Trace

**Layer scope:**
- Default: trace all layers — `Frontend → API Route → Controller → Service → Repository → Database → Response → Frontend render`
- `BACKEND_MODE = true`: trace `API Route → Controller → Service → Repository → Database → Response` only
- `DEEP_MODE = true`: extend the active layer set with `Middleware → Interceptor → Validator → Env/Config` (scoped to backend layers only if `BACKEND_MODE = true`)

For each layer in scope:
- Read the code
- Map the data flow: what enters, what is transformed, what exits
- If `PAYLOAD` is set: use its concrete values to trace the actual request path through conditionals
- Identify all branches that could produce `SYMPTOM`
- Mark every anomaly found — **do NOT stop at the first anomaly**

Build `FLOW`:
```
FLOW[n] = {
  layer: <Frontend | API | Middleware | Controller | Service | Repository | Database |
          Mapping | Auth | Config | Interceptor | Validator>,
  file: <path>,
  construct: <function / method / component / query>,
  input: <what enters this layer>,
  output: <what this layer returns>,
  branches: [<condition> → <outcome>],
  anomaly: <null_deref | type_mismatch | wrong_condition | missing_guard | stale_state |
            wrong_query | missing_field | wrong_return | missing_await | config_missing | none>
}
```

Trace every layer in scope. Mark `anomaly = none` for clean layers. Collect all anomalies before proceeding to Step 4.

---

## STEP 4 — Value Tracking

**Scope:**
- Default (`VALUE_MODE = false`): track values only within layers where `FLOW[n].anomaly ≠ none`
- `VALUE_MODE = true`: track values across **every** layer in `FLOW` — full step-by-step data flow for every construct

For each variable, parameter, state value, or config entry in scope:
- Trace all assignments: declaration → mutations → final read
- If `PAYLOAD` is set (and not null): seed the entry-point values with the concrete payload fields; trace how each field propagates through the layers
- Detect:
  - **Null dereference**: value accessed without null guard
  - **Incorrect mapping**: field name mismatch, wrong index, off-by-one
  - **Overwritten value**: variable reassigned before being used
  - **Stale state**: frontend reading a value not yet updated
  - **Type mismatch**: string compared to number, object where primitive expected
  - **Missing await**: async value read synchronously
  - **Config missing**: environment variable or config key undefined at runtime

Save as:
```
VALUE_TRACE[n] = {
  name: <variable / field / prop / state / env key>,
  at_entry: <concrete value from PAYLOAD or inferred expression>,
  mutations: [{ location, new_value }],
  at_fault: <value at the point of failure>,
  issue: <null | mismatch | overwritten | stale | type_error | missing_await | config_missing | none>
}
```

---

## STEP 5 — Frontend Analysis (skip if IS_FRONTEND = false)

If `IS_FRONTEND = false`: skip this step entirely.
If `IS_FRONTEND = true`: run in full.

Analyze the component structure at the fault site:

**Props**: name, type, required/optional, current value passed
**State**: name, type, initial value, current value at fault
**Side effects**: useEffect / lifecycle hooks — dependency arrays, execution timing
**Event handlers**: what they mutate, whether mutations are applied correctly
**Conditional renders**: which condition controls the failing render branch
**API calls**: URL, method, response shape expected vs actual
**Layout** (when `UI_MODE = true` or symptom is visual): flex/grid/positioning rules causing the observed layout fault

---

## STEP 6 — Frontend Snapshot (skip if Step 5 was skipped)

Capture the UI state before and after the fix.

**BEFORE** — current broken state:
- Which branch renders (or fails to render)
- Which props / state values drive the failure
- What the user sees (or doesn't see)

**AFTER** — projected state after fix:
- What changes in the render tree
- What the user will see

**DIFF** — only what changes:
```
+ <added element or corrected value>
- <removed element or wrong value>
~ <changed prop / state / class>
```

---

## STEP 7 — Root Cause

From the full set of anomalies collected in Steps 3 and 4, identify exactly one root cause: the anomaly that causally produces `SYMPTOM`. All other anomalies are downstream effects of this one cause.

```
ROOT_CAUSE = {
  layer: <layer from FLOW>,
  file: <path>,
  line: <line number or construct>,
  description: <one sentence — what is wrong and why it produces the observed symptom>,
  evidence: <the specific value, condition, or code that proves it>,
  confidence: HIGH | MEDIUM | LOW
}
```

Confidence rules:
- **HIGH**: the exact value or code path that produces the symptom is visible in the source
- **MEDIUM**: the anomaly is confirmed but the triggering condition depends on runtime data not visible in the source
- **LOW**: the anomaly is inferred — no direct code evidence, only structural argument

---

## STEP 8 — Apply Fix

Apply the minimal code change that resolves `ROOT_CAUSE`.

Rules:
- Change only the fault zone — do not touch surrounding logic
- Preserve all function signatures, return types, and observable behavior elsewhere
- Do not introduce new abstractions, classes, or imports not already present
- One surgical edit per file — smallest change that eliminates the root cause
- If the fix requires changes to multiple files (e.g., DTO contract mismatch between controller and frontend): apply all required changes, one per file

Save as:
```
FIXED_FILES = [
  { file: <path>, language: <language>, code: <full patched file content> },
  ...
]
```

---

## STEP 9 — Verify Fix

After patching, check for co-located test files:
- Glob for `*.test.<ext>`, `*.spec.<ext>`, `*_test.<ext>` in the same directory as each patched file
- If test files exist: read the relevant test cases and determine whether the fix satisfies existing assertions
  - If yes: note `TESTS: pass`
  - If the fix breaks an existing assertion: revise the fix to satisfy the test, or flag as `TESTS: requires update` with the specific assertion

If no test files exist: note `TESTS: none found` and suggest one assertion the user should add to verify the fix.

**Contract-aware mock check** — for each patched file whose name matches a contract pattern (contains `Dto`, `Request`, `Response`, `Command`, `Schema`, `Model`, `Entity`, `Contract`, `Payload`, `ViewModel`):
1. Derive the entity base name by stripping the contract suffix.
2. Search for frontend mock/fixture/example files referencing that base name (files matching `*.mock.*`, `*.fixture.*`, `*.example.*`, `*.stub.*`, `*.stories.*` across the repo, excluding `node_modules`).
3. For each mock file found: note `MOCKS: requires update` — list the file path and describe which fields in the contract changed so the consumer can update the mock accurately.
4. If no mock files are found but the project contains at least one mock/fixture file elsewhere: note `MOCKS: not found` and suggest creating a sample mock object that reflects the current contract shape with realistic values.
5. If the project has no mock files at all: skip silently (`MOCKS: n/a`).

---

## STEP 10 — Self-Healing Loop

Re-execute Steps 3 and 4 against `FIXED_FILES` to verify the fix.

**Check:**
- Does the fix eliminate `ROOT_CAUSE.anomaly`?
- Does the fix introduce any new anomaly anywhere in the flow?

**If resolved:** mark `STATUS = RESOLVED`. Output the result.

**If a new anomaly is introduced or the symptom persists:**
- Return to Step 7 with the updated FLOW
- Identify the new root cause
- Apply a new fix
- Repeat:
  - `LOOP_MODE = true`: no iteration cap — continue until `STATUS = RESOLVED`
  - `LOOP_MODE = false` (default): stop after 3 total iterations and mark `STATUS = ESCALATE`

---

## OUTPUT

If iteration > 1, wrap each round at the top:
```
── Round <N> ──────────────────────────────
```

---

### ISSUE (omit if FIX_MODE = true)

```
<ROOT_CAUSE.description>

Evidence:   <ROOT_CAUSE.evidence>
Location:   <ROOT_CAUSE.file> — <ROOT_CAUSE.line>
Confidence: <HIGH | MEDIUM | LOW>
```

---

### FLOW (omit if FIX_MODE = true)

For each entry in `FLOW` where `anomaly ≠ none`:
```
<layer> → <file> :: <construct>
  In:  <input>
  Out: <output>
  ⚠   <anomaly>: <detail>
```

For clean layers (anomaly = none), print one collapsed line:
```
<layer> → <construct> [clean]
```

If `VALUE_MODE = true`, append to every layer entry (anomalous or clean):
```
  Values: <name>: <at_entry> → <mutations> → <at_fault>
```

---

### FIX

For each entry in `FIXED_FILES`, print a fenced code block with the language identifier and file path as the caption:

```
// <file path>
<patched code>
```

One-line description of what changed per file:
```
Changed: <what was wrong> → <what it is now>
```

---

### VERIFY

```
Tests: <pass | requires update | none found>
Mocks: <requires update | not found | n/a>
```

If `Tests: requires update`:
```
Assertion to update: <test file path> — <specific assertion and why it needs to change>
```

If `Tests: none found`:
```
Suggested assertion: <one concrete test case to add>
```

If `Mocks: requires update`:
```
Mock files to update: <file path> — <list of fields that changed and their new types/values>
```

If `Mocks: not found`:
```
Suggested mock: <object literal showing all current contract fields with realistic example values>
```

---

### RESULT (only if IS_FRONTEND = true and snapshot captured)

```
BEFORE: <what user saw>
AFTER:  <what user will see>
DIFF:
  + <added>
  - <removed>
  ~ <changed>
```

---

```
STATUS: RESOLVED | ESCALATE
```

If `ESCALATE` (only possible when `LOOP_MODE = false`):
```
After 3 fix iterations the issue was not fully resolved.
Final state: <description of remaining anomaly>
Next step:   <one concrete action>
```

---

## CONSTRAINTS

- Never ask questions or request more context — infer everything from available code
- Never stop the flow trace early — collect ALL anomalies before identifying root cause
- Never list multiple root causes per round — one only
- Never list alternative fixes per round — one only
- Never change code outside the fault zone
- Never introduce new dependencies, abstractions, or imports
- Never output a fix without completing the flow trace first
- Never skip file discovery — always use Grep/Glob before reading code
- `--backend` and `--ui` together: `--backend` always wins — never run frontend steps
- `--deep` with `--backend`: extend backend layers only — never include frontend-side deep layers
- `--fix` suppresses ISSUE and FLOW — never print them when `FIX_MODE = true`
- `--loop` removes the escalation cap — never emit `STATUS = ESCALATE` when `LOOP_MODE = true`
- If `--payload` JSON is malformed: emit parse error inline, set `PAYLOAD = null`, continue with inferred values
- `--value` is strictly opt-in — default value tracking covers anomalous layers only
- `--loop` is strictly opt-in — default self-healing is capped at 3 iterations

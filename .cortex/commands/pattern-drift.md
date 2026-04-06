# /pattern-drift — Cortex Pattern Consistency Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--since=<ref>` → scan only files changed since `<ref>` (e.g., `--since=main`)
- `--deep` → expand pattern inference to the full codebase (default: sample up to 30 files per layer)
- `--layer=<name>` → restrict scan to a specific layer (e.g., `--layer=service`, `--layer=controller`)

Default: scan all files changed relative to `main` (`git diff main...HEAD --name-only`), infer patterns from up to 30 files per layer.

---

## STEP 1 — Establish scan scope

Collect `CHANGED_FILES`:
```
git diff main...HEAD --name-only
```
Falls back to `git diff HEAD --name-only` if `main` is not reachable.
If `--since=<ref>`: use `git diff <ref>...HEAD --name-only`.

If `CHANGED_FILES` is empty:
```
[PASS]

No changes detected — nothing to scan.
```
Stop.

---

## STEP 2 — Classify files by layer

For each file in `CHANGED_FILES`, assign a layer based on path segments and naming conventions:

| Layer | Detection signals |
|---|---|
| `Controller` | path contains `Controller`, `api/`, `routes/`; names end in `Controller` or `Handler` |
| `Service` | path contains `Service`, `Application/`; names end in `Service` or `Manager` |
| `Repository` | path contains `Repository`, `DataAccess/`, `Persistence/`; names end in `Repository` or `Store` |
| `DTO` | path contains `Dto`, `DTOs/`, `Models/`, `ViewModels/`, `Requests/`, `Responses/` |
| `Hook` | path under `.cortex/core/hooks/` |
| `Scanner` | path under `.cortex/core/scanners/` |
| `Registry` | path under `.cortex/registry/` |
| `Config` | path contains `appsettings`, `config`, `.env`, `Program.cs`, `Startup.cs`, `tsconfig`, `webpack.config` |
| `Test` | path contains `Test`, `Spec`, `__tests__`, `.test.`, `.spec.` |
| `Unknown` | none of the above |

Save as `LAYER_MAP[filepath] = layer`.

---

## STEP 3 — Infer dominant patterns from the codebase

For each layer present in `LAYER_MAP`, use Glob and Grep to collect a reference sample of existing files **not** in `CHANGED_FILES`.

Sample size: up to 30 files per layer (or all files if fewer exist). With `--deep`: no cap.

Do NOT read files in: `node_modules/`, `bin/`, `obj/`, `dist/`, `.git/`.

For each sampled file, read it and extract the following pattern signals:

### Pattern signals to extract

**Controllers:**
- Injection style: constructor injection vs property injection vs static access
- Return type convention: `IActionResult` / `ActionResult<T>` / raw type / `ResponseDto<T>`
- Route attribute style: `[Route("...")]` + `[HttpGet]` vs `[HttpGet("...")]` combined
- DTO usage: does it use DTOs for input/output, or raw entities?
- Validation: data annotations vs FluentValidation vs manual guard clauses

**Services:**
- Interface presence: does every service have a corresponding `I<Name>Service` interface?
- Dependency resolution: constructor injection vs service locator vs static
- Return type: domain entity vs DTO vs primitive
- Error handling: exceptions vs Result pattern vs nullable return

**Repositories:**
- ORM pattern: direct `DbContext` vs repository abstraction vs raw SQL
- Return type: entity vs DTO vs `IQueryable`
- Async convention: all methods async, or mixed?

**DTOs:**
- Naming convention: `<Name>Dto` vs `<Name>Request`/`<Name>Response` vs `<Name>Model` vs `<Name>ViewModel`
- Structure: flat vs nested
- Validation attributes: present or absent

**Hooks (Cortex-specific):**
- Payload parsing: stdin JSON via `jq` vs env vars
- Output format: structured JSON vs plain text
- Exit code convention: 0 = allow, 1 = block
- Version tag: `# @version: X.Y.Z` present on line 2

**Scanners (Cortex-specific):**
- Input method: file path as `$1` vs stdin
- Output format: JSON findings vs plain text
- Exit code: 0 = clean, non-zero = findings

For each pattern signal, record the **dominant value** (most common across the sample) and its **prevalence** (count / sample size).

Save as `DOMINANT_PATTERNS[layer][signal] = { value, prevalence, sample_count }`.

---

## STEP 4 — Scan changed files for deviations

For each file in `CHANGED_FILES`, read it and extract the same pattern signals as Step 3.

For each signal, compare the file's value against `DOMINANT_PATTERNS[layer][signal]`:

A deviation is flagged when:
- The file's value differs from the dominant value, **AND**
- The dominant pattern's prevalence is ≥ 60% (i.e., it is a genuine majority pattern, not just a plurality in a diverse codebase)

Do NOT flag a deviation if:
- The dominant prevalence is < 60% (no clear pattern established)
- The signal is not present in any sampled file (no baseline to compare against)
- The file is a Test file (tests often have legitimately varied patterns)

Save deviations as:
```
DRIFTS[filepath] = [
  { signal, expected_value, actual_value, prevalence, example_file }
]
```

---

## STEP 5 — Validate intentionality

For each flagged deviation, check whether it appears in multiple changed files:

- Deviation appears in ≥ 2 files in `CHANGED_FILES` with the same signal and same actual value → mark as `INTENTIONAL_CHANGE` (possible pattern migration, not drift)
- Deviation appears in only 1 file → mark as `ISOLATED_DRIFT`

`INTENTIONAL_CHANGE` items are still reported but at lower severity (WARN vs FAIL).

---

## STEP 6 — Assign severity per deviation

| Condition | Severity |
|---|---|
| `ISOLATED_DRIFT` in Controller, Service, or Repository layer | FAIL |
| `ISOLATED_DRIFT` in DTO layer | WARN |
| `ISOLATED_DRIFT` in Hook or Scanner (Cortex-specific) | FAIL |
| `INTENTIONAL_CHANGE` in any layer | WARN |
| Deviation in Config or Registry layer | WARN |

Map overall status (worst across all deviations):
- Any FAIL → `[FAIL]`
- All WARN, no FAIL → `[WARN]`
- No deviations → `[PASS]`

---

## STEP 7 — Generate WHY explanation per deviation

For each deviation, produce one sentence explaining:
- What the dominant pattern is and how many files follow it
- What the changed file does instead
- Why the inconsistency hurts maintainability (e.g., "breaks uniform dependency resolution", "makes consumer code unable to mock this component")

Cite the `example_file` from Step 4 as the reference implementation.

---

## STEP 8 — Generate FIX per deviation

For each deviation, provide ONE exact change to align with the dominant pattern:
- Name the specific line or block to change
- State what it should be changed to (citing the dominant value)
- Do NOT provide multiple options

---

## OUTPUT

```
[PASS | WARN | FAIL]

PATTERN DRIFT SUMMARY:
  Files scanned:      <count>
  Patterns inferred:  <total signal count across all layers>
  Deviations found:   <total drift count>
  Isolated drift:     <ISOLATED_DRIFT count>
  Intentional change: <INTENTIONAL_CHANGE count>
```

If no deviations:
```
No pattern drift detected.
```
Stop.

For each file with deviations:

```
DRIFT DETECTED:

* File: <relative/path/to/file>
  Layer: <layer>
  Status: ISOLATED DRIFT | INTENTIONAL CHANGE

  SIGNAL: <signal name>
  EXPECTED PATTERN: <dominant value> (<prevalence>% of <sample_count> sampled files)
  REFERENCE:        <example_file>
  CURRENT:          <actual value in this file>
  SEVERITY:         FAIL | WARN

  WHY:
  <one sentence — cites prevalence and example file>

  FIX:
  <single exact change>
```

Repeat for each signal deviation within the file, then continue to the next file.

---

## CONSTRAINTS

- Never flag a deviation without a dominant pattern at ≥ 60% prevalence
- Never infer patterns from files in `CHANGED_FILES` — baseline must come from unchanged files only
- Never flag Test files as drifting
- Never provide multiple FIX options for a single deviation
- Never make assumptions about intended patterns — infer only from real file reads
- Never flag a signal if no baseline sample exists for that layer

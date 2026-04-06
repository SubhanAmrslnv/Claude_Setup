# /optimize — Cortex Optimization Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--file=<path>` → optimize the specified file
- `--lang=<language>` → override language detection (e.g., `--lang=sql`, `--lang=csharp`, `--lang=js`)
- `--focus=perf` → prioritize performance over readability (default: balance both)
- `--focus=clarity` → prioritize readability over micro-optimizations

If no `--file` is provided and no inline code is passed via arguments: prompt the user to specify a file or paste code. Stop.

Default: auto-detect language from file extension or code content, balance performance and readability.

---

## STEP 1 — Load target

If `--file=<path>` is provided:
- Read the file.
- Save content as `TARGET_CODE`.
- Save the file path as `TARGET_FILE`.
- Detect language from extension:

| Extension | Language |
|---|---|
| `.cs` | C# |
| `.ts`, `.tsx` | TypeScript |
| `.js`, `.jsx` | JavaScript |
| `.py` | Python |
| `.go` | Go |
| `.rs` | Rust |
| `.java` | Java |
| `.sql` | SQL |
| `.sh`, `.bash` | Bash |
| `.ps1` | PowerShell |
| other | infer from content |

If `--lang` is set, override the detected language.

Save as `LANGUAGE`.

If inline code was provided in `$ARGUMENTS` (no `--file`): use that as `TARGET_CODE`, set `TARGET_FILE = (inline)`.

---

## STEP 2 — Analyze inefficiencies

Read `TARGET_CODE` and identify issues across these categories. Only flag issues that are present in the actual code — do not flag hypothetical problems.

### Performance issues
- **Redundant iterations**: nested loops where a single pass suffices; re-scanning a collection already scanned
- **N+1 patterns**: database calls inside loops; repeated external calls with cacheable results
- **Unnecessary allocations**: creating intermediate collections (`.ToList()`, `new List<>()`) that are immediately iterated and discarded
- **Unindexed lookups**: linear search (`FirstOrDefault` with predicate, `Contains` on list) where a dictionary or set lookup would be O(1)
- **Repeated computation**: same expression evaluated multiple times in a loop; recomputable constants not hoisted
- **Missing async**: synchronous I/O in an async context (`.Result`, `.Wait()`, blocking reads)
- **SQL-specific**: `SELECT *`; missing `WHERE` clause; correlated subquery replaceable with JOIN; `LIKE '%value'` preventing index use; implicit type coercion in predicates; cursor where set operation suffices

### Complexity issues
- **Deep nesting**: more than 3 levels of indent for non-trivial logic; early-return / guard-clause pattern would flatten it
- **Long methods**: single function > 50 lines doing multiple distinct operations (split only if the split is semantically meaningful, not just line count)
- **Boolean logic**: double negatives; compound conditions that simplify to a single expression; flag variables that can be replaced with a direct predicate

### Redundancy issues
- **Dead assignments**: variable assigned but never read before being overwritten or going out of scope
- **Unnecessary null checks**: null guard on a value guaranteed non-null by prior logic
- **Duplicate conditionals**: same condition checked in consecutive branches
- **No-op operations**: appending to a collection then immediately clearing it; adding 0, multiplying by 1

Save each finding as:
```
ISSUES[n] = { category, description, location (line range or construct name), severity (HIGH | MEDIUM | LOW) }
```

If no issues are found:
```
[PASS]

No optimization opportunities detected — implementation is already efficient.
```
Stop.

---

## STEP 3 — Prioritize issues

Sort `ISSUES` by severity: HIGH first, then MEDIUM, then LOW.

If `--focus=perf`: promote all performance issues to HIGH, demote clarity-only issues to LOW.
If `--focus=clarity`: promote complexity and redundancy issues; do not demote performance issues below MEDIUM.

Select issues to address:
- All HIGH severity issues.
- MEDIUM issues only if they do not require adding new abstractions.
- LOW issues only if the fix is a one-line change.

Do NOT address an issue if fixing it would:
- Change observable behavior (return values, side effects, error handling)
- Require introducing a new class, interface, or abstraction not already present in the file
- Require importing a new dependency not already in the file

---

## STEP 4 — Produce optimized version

Rewrite `TARGET_CODE` applying all selected fixes from Step 3.

Rules:
- Preserve all function/method signatures exactly
- Preserve all comments unless they describe the removed inefficiency
- Preserve error handling behavior
- Apply fixes inline — do not restructure the file layout
- Do NOT add explanatory comments to the optimized code itself

Save as `OPTIMIZED_CODE`.

Compute a diff summary:
- Lines removed: count
- Lines added: count
- Net change: `+N` or `-N`

---

## STEP 5 — Assess impact

For each addressed issue, state the concrete impact:

**Performance impact** (only if measurable from static analysis):
- Complexity change: e.g., `O(n²) → O(n)`, `O(n) → O(1)`
- Allocation reduction: e.g., "removes 1 intermediate List allocation per call"
- Query improvement: e.g., "eliminates correlated subquery; single pass instead of N+1"

**Readability impact**:
- Nesting depth reduction: e.g., "3 levels → 1 level via early return"
- Line count reduction: e.g., "-12 lines"
- Logic simplification: e.g., "3-condition boolean reduced to single predicate"

Do NOT claim performance improvements that cannot be derived from the code alone (e.g., do not state "2× faster" without a complexity argument).

---

## OUTPUT

```
[PASS | IMPROVED]
```

If `IMPROVED`:

```
ORIGINAL ISSUES:
```

For each addressed issue:
```
* [<CATEGORY>] <description>
  Location: <line range or construct name>
  Severity: HIGH | MEDIUM | LOW
```

```
WHY:
<one paragraph — explains root cause of the inefficiency, language-specific where relevant>

OPTIMIZED VERSION:
```

Print `OPTIMIZED_CODE` in a fenced code block with the language identifier.

```
IMPACT:
```

For each addressed issue, print:
```
* <Performance | Readability>: <concrete impact statement>
```

If issues were identified but NOT addressed (excluded in Step 3):
```
SKIPPED (out of scope):
* <description> — <reason skipped>
```

---

## CONSTRAINTS

- Never change function signatures, return types, or observable behavior
- Never introduce new classes, interfaces, or abstractions not already present
- Never import dependencies not already present in the file
- Never output multiple versions of the optimized code — ONE output only
- Never claim a performance improvement without a complexity or allocation argument
- Never optimize Test files — report `[PASS]` with note: "Test files are excluded from optimization."
- Never rewrite the entire file when only a subset of constructs has issues — scope changes to affected constructs only

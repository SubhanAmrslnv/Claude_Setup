# /overengineering-check — Cortex Simplicity Enforcement Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--file=<path>` → check a single file
- `--since=<ref>` → check only files changed since `<ref>` (e.g., `--since=main`)
- `--deep` → include dependency graph analysis via Grep (default: structural analysis only)

Default (no flags): check all files changed relative to `main` (`git diff main...HEAD --name-only`).

---

## STEP 1 — Establish file scope

If `--file=<path>`: use that single file as `TARGET_FILES`.

If `--since=<ref>`: collect via `git diff <ref>...HEAD --name-only`.

Default: collect via `git diff main...HEAD --name-only` (falls back to `git diff HEAD --name-only`).

If `TARGET_FILES` is empty:
```
[PASS]

No files in scope — nothing to check.
```
Stop.

Exclude from analysis: `node_modules/`, `bin/`, `obj/`, `dist/`, `.git/`, `*.lock`, `*.log`, `*.min.js`, `*.map`, `*.generated.*`.

---

## STEP 2 — Read and classify each file

For each file in `TARGET_FILES`, read it and classify its layer (same signals as other Cortex commands):

| Layer | Signals |
|---|---|
| `Controller` | path/name contains Controller, Handler, api/, routes/ |
| `Service` | path/name ends in Service, Manager |
| `Repository` | path/name ends in Repository, Store; contains ORM calls |
| `DTO` | path/name contains Dto, Request, Response, ViewModel, Model |
| `Interface` | file defines only an interface/abstract class with no implementation |
| `Hook` | path under `.cortex/core/hooks/` |
| `Scanner` | path under `.cortex/core/scanners/` |
| `Config` | appsettings, tsconfig, webpack.config, Program.cs |
| `Test` | contains Test, Spec, __tests__, .test., .spec. |
| `Unknown` | none of the above |

Skip `Test` files — report `[PASS]` for them individually with note "Test files are excluded."

---

## STEP 3 — Detect overengineering patterns

For each non-Test file, check for the following patterns. Only flag a pattern if evidence is found in the actual file content — no assumptions.

---

### Pattern 1: Interface with a single implementation

**Detection:**
1. File defines an interface `IFoo`.
2. Use Grep to find all implementations of `IFoo` across the codebase.
3. If exactly ONE concrete implementation exists and there is no evidence of mocking in test files (search for `Mock<IFoo>`, `IFoo mock`, `Substitute.For<IFoo>`):

→ Flag as `SINGLE_IMPL_INTERFACE`

**Severity:** MEDIUM
**Exception:** Do not flag if the interface is in a public library/SDK surface (`public` access modifier + in a package/namespace suggesting external consumption).

---

### Pattern 2: Abstraction layer with no logic

**Detection:**
Read the file. If a class/service:
- Has methods that do nothing except call the exact same method on an injected dependency with no transformation, no error handling, and no additional logic
- E.g., `public Foo GetFoo(int id) => _repo.GetFoo(id);` (pure pass-through across all methods)

→ Flag as `PASSTHROUGH_ABSTRACTION`

**Severity:** HIGH
**Threshold:** ALL public methods must be pure pass-throughs, not just some. A class with 5 methods where 4 pass through and 1 adds logic is NOT flagged.

---

### Pattern 3: Generic implementation for a single use case

**Detection:**
- Class or function uses type parameters (`<T>`, generics) but is only ever instantiated or called with ONE concrete type.
- Use Grep to count unique type argument usages across the codebase.
- If called with only 1 distinct type → flag as `UNUSED_GENERICS`.

**Severity:** MEDIUM
**Exception:** Do not flag generic base classes/utilities explicitly designed for extension (abstract classes, framework base types).

---

### Pattern 4: Deeply nested structure with no branching

**Detection:**
- Nesting depth > 4 levels (brace/indent tracking) where inner levels contain no conditional logic (`if`, `switch`, `try`, `for`, `while`).
- Pure structural nesting (e.g., namespace → class → method → using → lambda → object initializer) that adds no control flow value.

→ Flag as `STRUCTURAL_NESTING`

**Severity:** LOW (MEDIUM if depth > 6)

---

### Pattern 5: Overly generic configuration or factory

**Detection:**
- A factory, builder, or configuration class that accepts arbitrary type parameters or strategy functions but is only invoked once in the codebase with a hardcoded configuration.
- Use Grep to count invocation sites.
- Single invocation site with no variation → flag as `SINGLE_USE_FACTORY`.

**Severity:** MEDIUM

---

### Pattern 6: DTO mirroring an entity 1:1

**Detection:**
- A DTO class has the same property names and types as an entity/model class (≥ 90% property overlap).
- Use Grep to find the corresponding entity by name (`FooDto` → look for `Foo`, `FooEntity`, `FooModel`).
- Read both files and compare properties.
- If ≥ 90% of properties are identical (same name, same type) AND no mapping logic transforms values between them → flag as `REDUNDANT_DTO`.

**Severity:** LOW
**Exception:** Do not flag if the DTO has validation attributes, serialization annotations, or if the entity has navigation properties / ORM attributes that the DTO omits.

---

### Pattern 7: Hook or scanner doing more than one job (Cortex-specific)

**Detection (hooks):**
- A hook script handles more than one event type or dispatches to more than one unrelated concern.
- More than 2 distinct `if/case` branches dispatching to different tools or categories → flag as `MULTI_RESPONSIBILITY_HOOK`.

**Detection (scanners):**
- A scanner script performs both formatting AND security scanning in the same file.
- Presence of both format-related commands (`prettier`, `black`, `gofmt`) and security-related patterns (`grep -E`, secret patterns) in the same script → flag as `MIXED_SCANNER`.

**Severity:** HIGH (violates Cortex separation of concerns)

---

## STEP 4 — Assess simplification safety

For each flagged issue, determine whether simplification is safe:

**SAFE to simplify when:**
- The removed abstraction has no test doubles (no mocks/stubs found via Grep)
- The removed layer has no consumers outside the immediate call chain
- The consolidated logic fits in the consumer without exceeding 50 lines

**UNSAFE (do not flag as actionable) when:**
- The interface is used in DI registration with multiple environments or configurations
- The generic is in a shared library consumed by external projects
- Removing the layer would require changes in > 3 files

If UNSAFE: downgrade severity to LOW and add note "Simplification requires cross-file changes — review manually."

---

## STEP 5 — Assign overall status

| Condition | Status |
|---|---|
| Any HIGH severity finding that is SAFE to simplify | `[FAIL]` |
| Any MEDIUM severity finding, no HIGH | `[WARN]` |
| Only LOW severity findings | `[WARN]` |
| No findings | `[PASS]` |

---

## STEP 6 — Generate WHY explanation

For each finding, produce one paragraph:
- State what the pattern is and where it appears (file + construct name)
- Explain the concrete cost: what does this complexity make harder? (reading, testing, extending, tracing)
- Cite evidence: line count, Grep result count (implementations, callers), property overlap percentage
- No subjective language ("ugly", "messy", "bad") — only structural and maintainability arguments

---

## STEP 7 — Generate FIX instruction

For each finding, provide ONE specific structural instruction:
- Name the exact construct to remove or collapse
- State what it should be replaced with (inline the logic, remove the layer, merge the files)
- Do NOT provide alternatives
- If simplification is UNSAFE: state exactly what cross-file changes are needed before it becomes safe

---

## OUTPUT

```
[PASS | WARN | FAIL]

OVERENGINEERING SUMMARY:
  Files checked:   <count>
  Issues found:    <count>
  HIGH severity:   <count>
  MEDIUM severity: <count>
  LOW severity:    <count>
```

If no issues:
```
No overengineering detected.
```
Stop.

For each issue:

```
OVERENGINEERING DETECTED:

* File: <relative/path/to/file>
  Layer:    <layer>
  Pattern:  <SINGLE_IMPL_INTERFACE | PASSTHROUGH_ABSTRACTION | UNUSED_GENERICS | STRUCTURAL_NESTING | SINGLE_USE_FACTORY | REDUNDANT_DTO | MULTI_RESPONSIBILITY_HOOK | MIXED_SCANNER>
  Severity: HIGH | MEDIUM | LOW
  Safe:     YES | NO (<reason if NO>)
  ISSUE: <one-line description of the specific instance>

  WHY:
  <one paragraph — structural argument only, no subjective language, cites evidence>

  FIX:
  <single instruction — names the construct, states the exact change>
```

---

## CONSTRAINTS

- Never flag a pattern without evidence from the actual file content or a Grep result
- Never flag Test files
- Never provide multiple FIX options for a single finding
- Never use subjective language (ugly, messy, bad, terrible) — structural arguments only
- Never flag UNSAFE simplifications as HIGH or MEDIUM actionable — downgrade to LOW with manual review note
- Never flag partial pass-throughs as PASSTHROUGH_ABSTRACTION — ALL public methods must be pure pass-throughs
- Never flag an interface used in test mocking as SINGLE_IMPL_INTERFACE

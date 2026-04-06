# /impact — Cortex Impact Analysis Engine

## MODE DETECTION

Parse `$ARGUMENTS` for flags:
- `--staged` → analyze only staged changes (`git diff --cached`)
- `--deep` → trace transitive dependencies (2nd-degree consumers)
- `--since=<ref>` → analyze changes since a specific commit/branch (e.g., `--since=main`)

Default (no flags): analyze all uncommitted changes (`git diff HEAD`).

---

## STEP 1 — Collect changed files

### Source selection

| Flag | Git command |
|---|---|
| `--staged` | `git diff --cached --name-only` |
| `--since=<ref>` | `git diff <ref>...HEAD --name-only` |
| default | `git diff HEAD --name-only` |

If no changed files are found:
```
[PASS]

No changes detected — nothing to analyze.
```
Stop.

Save the full list as `CHANGED_FILES`.

Also run the matching diff command with `-p` (patch output) and save as `FULL_DIFF`. This is used for content-level analysis in Step 3.

---

## STEP 2 — Classify each changed file

For each file in `CHANGED_FILES`, assign one or more of the following types based on path segments, naming conventions, and file content (read the file to confirm when ambiguous):

| Type | Detection signals |
|---|---|
| `Controller` | path contains `Controller`, `Controllers/`, `api/`, `routes/`; class/function names end in `Controller` or `Handler`; decorators like `@Controller`, `[ApiController]`, `app.get/post` |
| `Service` | path contains `Service`, `Services/`, `Application/`; class names end in `Service` or `Manager`; decorators like `@Injectable`, `@Service` |
| `Repository` | path contains `Repository`, `Repositories/`, `DataAccess/`, `Persistence/`; class names end in `Repository` or `Store`; ORM calls (`DbContext`, `_context.`, `findOne`, `save`) |
| `DTO` | path contains `Dto`, `DTOs/`, `Models/`, `ViewModels/`, `Requests/`, `Responses/`; class/interface is purely data (only properties, no methods) |
| `Configuration` | path contains `appsettings`, `config`, `.env`, `.json` config files, `Program.cs`, `Startup.cs`, `webpack.config`, `tsconfig` |
| `Test` | path contains `Test`, `Tests/`, `Spec`, `__tests__/`, `.spec.`, `.test.` |
| `Hook` | path under `.cortex/core/hooks/` or `.claude/hooks/` |
| `Scanner` | path under `.cortex/core/scanners/` |
| `Registry` | path under `.cortex/registry/` |
| `Schema / Migration` | path contains `Migration`, `Schema`, `.sql`, `prisma/` |

If a file does not match any type: classify as `Unknown`.

Read each file to confirm classification when the path alone is ambiguous. Do not read files that do not belong to `CHANGED_FILES`.

---

## STEP 3 — Trace dependencies

For each changed file, determine what depends on it. Use Grep to find references across the codebase.

Do NOT search inside: `node_modules/`, `bin/`, `obj/`, `dist/`, `.git/`, `*.lock`, `*.log`, `*.min.js`, `*.map`.

### By type

**DTO changed**
- Search for the DTO class/interface name across all source files.
- Each file importing or using it is a consumer.
- For each consumer, identify its type (Controller, Service, etc.) and note the dependency.

**Service changed**
- Search for the service class/interface name across all source files.
- Identify all injection points (constructor parameters, DI registrations).
- Trace up to Controllers and other Services that consume it.

**Repository changed**
- Search for the repository class/interface name.
- Identify all Services that inject it.
- From those Services, trace up to Controllers.

**Controller changed**
- Identify all route definitions in the file (e.g., `[HttpGet]`, `app.get(`, `@Get(`).
- Each route is a directly affected endpoint.
- No further upward tracing needed.

**Configuration changed**
- Search for the configuration key names referenced in the changed config.
- Find all source files that read those keys (e.g., `_config["key"]`, `process.env.KEY`, `IOptions<>`).
- Each reading file is a consumer.

**Schema / Migration changed**
- Identify table names from the migration or schema file.
- Search for those table names or corresponding model/entity names across Repositories and Services.

**Hook or Scanner changed** (Cortex-specific)
- No dependency tracing needed — Cortex hooks are event-driven, not imported.
- Note the event they guard and which tool invocations they affect.

**`--deep` mode**: for each consumer found, repeat the dependency trace one level further (find consumers of consumers). Cap at 2 levels of transitive tracing to avoid combinatorial explosion.

Save all traces as: `DEPENDENCY_MAP[file] = { consumers: [], entry_points: [], db_tables: [] }`

---

## STEP 4 — Calculate impact metrics

Aggregate across all `DEPENDENCY_MAP` entries:

- **Files changed**: count of `CHANGED_FILES`
- **Services affected**: unique Service-type files in consumers + changed Services
- **Endpoints affected**: count of unique route definitions in changed Controllers + routes in Controllers that consume changed Services or DTOs
- **Layers touched**: set of unique types present in changed files + their consumers (e.g., `{DTO, Service, Controller}` = 3 layers)
- **DB tables affected**: unique table/entity names from Repository and Migration traces

---

## STEP 5 — Assign risk level

Assign a single `RISK_LEVEL` using this decision table (first matching row wins):

| Condition | Risk |
|---|---|
| Any `Schema / Migration` change | `HIGH` |
| Any `Repository` change with ≥2 Service consumers | `HIGH` |
| Layers touched ≥ 3 | `HIGH` |
| Any `Configuration` change affecting ≥2 consumers | `HIGH` |
| Any `DTO` change with ≥3 consumers | `HIGH` |
| Layers touched == 2 | `MEDIUM` |
| Any `Service` change with ≥1 Controller consumer | `MEDIUM` |
| Any `DTO` change with 1–2 consumers | `MEDIUM` |
| All changes isolated to 1 layer with ≤2 consumers | `LOW` |
| No consumers found for any changed file | `LOW` |

Map risk to status:
- `HIGH` → `[FAIL]`
- `MEDIUM` → `[WARN]`
- `LOW` → `[PASS]`

---

## STEP 6 — Generate WHY explanation

Produce a single technical paragraph explaining why the change carries this risk level. Reference:
- Specific files changed
- Specific consumers found
- Which layers are crossed
- Which endpoints or DB tables are affected

No vague statements. Every claim must trace back to a file or line found in Steps 2–4.

---

## STEP 7 — Generate FIX recommendation

**If `RISK_LEVEL` is `HIGH`**:
Identify the specific coupling that elevated the risk and give ONE actionable recommendation:

Examples (pick the most applicable):
- "Extract the changed logic in `<file>` into a new `<Name>Service` to isolate the `<RepositoryName>` dependency from `<n>` callers"
- "Split this commit — the DTO change in `<file>` and the schema migration in `<file>` touch different risk domains and should be reviewed independently"
- "Add an interface layer between `<RepositoryName>` and its `<n>` Service consumers to reduce the blast radius of future repository changes"

**If `RISK_LEVEL` is `MEDIUM`**:
- "Add or update integration tests covering the `<endpoint>` endpoint before merging — this change propagates through `<ServiceName>` to `<ControllerName>`"

**If `RISK_LEVEL` is `LOW`**:
- "No structural changes recommended — impact is isolated."

Do NOT provide multiple options. ONE fix only.

---

## OUTPUT

Print:

```
[PASS | WARN | FAIL]

IMPACT SUMMARY:
  Files changed:      <n>
  Services affected:  <n>
  Endpoints affected: <n>
  Layers touched:     <n> (<list of layer types>)
  DB tables affected: <n> (<list of table names, or "none">)

RISK LEVEL: LOW | MEDIUM | HIGH

DETAILS:
```

For each file in `CHANGED_FILES`, print:

```
  File:    <relative/path/to/file>
  Type:    <Controller | Service | Repository | DTO | Configuration | ...>
  Impact:  <what this file affects — specific consumer names and counts>
  Consumers:
    - <consumer file> (<type>)
    - ...
  Endpoints:
    - <METHOD> <route> (in <ControllerFile>)
    - ...
  DB Tables:
    - <table name>
    - ...
```

Then print:

```
WHY:
<single technical paragraph — no vague statements>

FIX:
<single deterministic recommendation>
```

---

## CONSTRAINTS

- Never state a dependency without a Grep result confirming it
- Never claim an endpoint is affected without tracing the call chain
- Never assign HIGH risk based on file count alone — use the decision table
- Never output multiple FIX options
- Never include files outside `CHANGED_FILES` in the Files Changed count

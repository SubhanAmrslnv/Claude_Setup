# /documentation — Cortex Documentation Generator

## OVERVIEW

Generate or update a structured documentation system inside the `/documentation` folder in the current project root.

All content must be derived from real project analysis. Never hallucinate features, modules, or endpoints.

---

## STEP 1 — Read existing context

### 1a. Read CLAUDE.md

Check if `CLAUDE.md` exists in the project root. If it does, read it in full. This file defines the authoritative architecture, conventions, and constraints for the project. All generated documentation must align with it. Never contradict anything stated in `CLAUDE.md`.

### 1b. Read existing documentation

Check if a `documentation/` folder exists in the project root using Glob on `documentation/**/*.md`.

For each file found, read it in full before generating anything. Apply the following decision logic per file:

- File exists and content is accurate → keep and improve
- File exists but contains outdated or incorrect content → update, preserving correct parts
- File is missing → create from scratch

Never overwrite a file blindly. Never duplicate content that already exists in another file.

---

## STEP 2 — Analyze the project

Perform a real analysis of the project to inform documentation content. Use the following checks:

### Detect project type

Use Glob to check for:
- `*.sln` or `*.csproj` → .NET project
- `package.json` → Node / JavaScript / TypeScript project
- `requirements.txt` or `pyproject.toml` → Python project
- `go.mod` → Go project
- `.cortex/` or `.claude/` → Cortex framework project

A project may match multiple types. Record all that apply.

### Detect Cortex usage

If `.cortex/` exists in the project root, Cortex is active. Include `commands.md` in the output.

### Detect backend / API

Check for:
- Route definitions (`router.get`, `app.post`, `[HttpGet]`, `@GetMapping`, etc.) via Grep
- Controller files via Glob on `**/*Controller*`, `**/*controller*`, `**/*routes*`, `**/*router*`
- OpenAPI/Swagger files via Glob on `**/swagger*`, `**/openapi*`

Only create `api.md` if real API surface is found.

### Collect structural information

Use Glob and Grep to find:
- Entry points (`Program.cs`, `index.ts`, `main.py`, `cmd/main.go`, etc.)
- Key directories (`src/`, `api/`, `services/`, `tests/`, `config/`, `scripts/`, etc.)
- Dependency files (`package.json`, `*.csproj`, `requirements.txt`, `go.mod`)
- Hook and scanner directories if Cortex is present

Do not read files speculatively. Only read files necessary to populate documentation content.

---

## STEP 3 — Generate documentation files

Create or update each file listed below. Write each file using the Write or Edit tool. All files go inside `documentation/` in the project root.

---

### documentation/README.md

**Purpose:** Index and entry point for the documentation folder.

**Required sections:**

1. Project name and one-sentence description (derived from CLAUDE.md or the detected project type)
2. Quick start — minimum steps to get the project running, in numbered list form
3. Documentation index — a list with links to every other file in the `documentation/` folder:
   - `overview.md` — Project purpose and problem statement
   - `architecture.md` — System design and layer responsibilities
   - `setup.md` — Installation and environment setup
   - `usage.md` — How to run and use the project
   - `commands.md` — Cortex commands (only link if Cortex is active)
   - `modules.md` — Modules, folders, and responsibilities
   - `api.md` — API endpoints (only link if a backend was detected)

---

### documentation/overview.md

**Purpose:** What this project is, why it exists, and what problem it solves.

**Required sections:**

1. **What it is** — one paragraph describing the project clearly and specifically. No generic filler.
2. **Problem it solves** — concrete description of the pain point or gap this project addresses.
3. **Who it is for** — the target user or environment (developers, CI pipelines, specific teams, etc.).
4. **Key capabilities** — a bullet list of the top 5–8 real capabilities derived from actual project analysis.

Do not invent capabilities. Only list what is confirmed by reading CLAUDE.md or actual project files.

---

### documentation/architecture.md

**Purpose:** System design, layer structure, and separation of concerns.

If `CLAUDE.md` defines an architecture or layer responsibilities, reproduce and extend it here. Do not contradict it.

**Required sections:**

1. **System overview** — one paragraph describing how the system is structured at a high level.
2. **Directory layout** — a code block showing the real folder structure (use Glob to derive it). Only show directories and key files. Do not include `.git/`, `node_modules/`, `obj/`, `bin/`.
3. **Layer responsibilities** — a table or subsection per layer describing what each directory or module does. Base this on real file analysis.
4. **Separation of concerns** — describe which layers are allowed to call which. Derive from CLAUDE.md if defined; otherwise infer from project structure.
5. **Key design decisions** — bullet list of non-obvious architectural choices visible in the codebase. Only include confirmed facts.

For Cortex projects: reproduce the hook event flow, registry-driven dispatch model, and CORTEX_ROOT resolution from CLAUDE.md.

---

### documentation/setup.md

**Purpose:** Installation and environment configuration.

**Required sections:**

1. **Prerequisites** — table of all required tools, versions, and what they are needed for. Derive from dependency files and CLAUDE.md.
2. **Installation** — numbered steps to install the project from scratch. Include platform-specific variants (macOS, Linux, Windows) where they differ.
3. **Environment configuration** — describe any environment variables, config files, or secrets that must be set before the project will run. List file names and required keys.
4. **Verification** — one or two commands the user can run to confirm the setup is working.

---

### documentation/usage.md

**Purpose:** How to run, operate, and interact with the project day-to-day.

**Required sections:**

1. **Running the project** — commands to start the project in development and production modes.
2. **Configuration options** — flags, environment variables, or config file options that affect runtime behavior.
3. **Common workflows** — 3–5 concrete, named workflows a user would perform. Each workflow is a numbered list of steps.
4. **Troubleshooting** — 3–5 common failure modes with their symptoms and resolution steps.

Only include workflows and failure modes that are grounded in actual project behavior.

---

### documentation/commands.md

**Only generate this file if Cortex is active (`.cortex/` exists in the project root).**

**Purpose:** Complete reference for all Cortex slash commands available in the project.

**Required sections:**

1. **Command summary table** — columns: Command, Flags, Description. Derive from `.cortex/registry/commands.json` and `.cortex/commands/*.md`.
2. **Per-command reference** — for each command: purpose, available flags with descriptions, output format, and one usage example. Derive directly from the implementation files in `.cortex/commands/`.
3. **Adding new commands** — steps to create a new Cortex command (from CLAUDE.md).

---

### documentation/modules.md

**Purpose:** Explain what each directory and module does.

**Required sections:**

1. **Top-level structure** — table with columns: Path, Type, Responsibility. List every top-level directory and key file in the project root. Derive from real Glob results.
2. **Module deep-dives** — one subsection per significant directory. Each subsection describes:
   - What lives in this directory
   - What it is responsible for
   - What it is NOT responsible for (boundary definition)
   - Files of note (entry points, registries, critical configs)

For Cortex projects, cover: `core/hooks/guards/`, `core/hooks/runtime/`, `core/scanners/`, `commands/`, `registry/`, `cache/`, `state/`, `base/`, `local/`.

---

### documentation/api.md

**Only generate this file if a real API surface was detected in Step 2.**

**Purpose:** Endpoint reference and request/response contract documentation.

**Required sections:**

1. **Base URL and versioning** — how the API is addressed and versioned.
2. **Authentication** — how requests are authenticated (token, cookie, API key, etc.).
3. **Endpoint reference** — per endpoint:
   - Method and path
   - Description
   - Request parameters (path, query, body) with types
   - Response structure with types
   - Example request and response

Only document endpoints confirmed by reading actual route/controller files. Do not invent endpoints.

---

## STEP 4 — Output

Write or update all applicable files using the Write or Edit tool.

- Use Write for files that do not yet exist.
- Use Edit for files that already exist and need targeted updates.
- Do not output explanatory text. Only perform file operations.
- Every file must contain only valid Markdown.
- Do not generate files outside `documentation/`.

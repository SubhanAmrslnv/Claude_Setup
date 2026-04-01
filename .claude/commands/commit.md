Perform a local Git commit following strict interactive branch and message rules.

## Step 1 — Detect current branch

Run: `git rev-parse --abbrev-ref HEAD`

## Step 2 — Check for changes

Run: `git status --short`

If there are no changes (working tree clean and nothing staged):
- Respond: "Nothing to commit — working tree is clean"
- Stop.

## Step 3 — Branch routing

### CASE A — Protected branch (main, master, develop)

If the current branch is `main`, `master`, or `develop`:

Ask the user:
"You are on a protected branch (main/master/develop). Please enter a new branch name:"

Wait for explicit user input. Do NOT:
- Auto-generate a branch name
- Suggest a branch name
- Proceed until the user provides one

Then ask:
"Please enter commit message:"

Wait for explicit user input. Do NOT proceed until a non-empty message is provided.

Once both are provided:
1. Run: `git checkout -b <branch-name>`
2. Respond: "Branch '<branch-name>' created and switched."
3. Run: `git add -u`
4. Proceed to Step 4 using the user-provided message.

### CASE B — Safe branch

If the current branch is NOT `main`, `master`, or `develop`:

1. Run: `git add -u`
2. Run: `git diff --cached --stat` and `git diff --cached --name-only`
3. Auto-generate a commit message from the diff:

Derive the commit type from what changed:
- `feat` — new functionality added
- `fix` — bug fix or correction
- `refactor` — restructuring without behavior change
- `docs` — documentation only
- `chore` — config, tooling, scripts, dependencies
- `style` — formatting, whitespace, no logic change
- `test` — test additions or fixes
- `perf` — performance improvement

Format: `<type>: <short specific summary>`

Rules:
- Summary must reflect the actual diff — no vague words like "update", "fix stuff", "changes"
- No trailing period
- No Claude attribution, no emoji
- 72 characters max

Show the generated message to the user:
"Generated commit message: '<message>'"

Proceed to Step 4 using the generated message.

## Step 4 — Commit

Run: `git commit -m "<message>"`

On success, respond:
"Commit created successfully on '<branch-name>' with message: '<message>'"

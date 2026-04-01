Perform a local Git commit with a clean conventional commit message.

## 1. Check branch

Run: `git rev-parse --abbrev-ref HEAD`

If the branch is `main`, `master`, or `develop`:
- Stop immediately
- Respond: "Commit blocked on protected branch"

## 2. Check for staged or modified changes

Run: `git status --short`

If there are no changes (working tree clean and nothing staged):
- Stop immediately
- Respond: "Nothing to commit — working tree is clean"

## 3. Stage changes

Run: `git add -u` to stage all modifications to tracked files.

Do NOT stage untracked files unless the user explicitly listed them.

## 4. Generate commit message

Run: `git diff --cached --stat` and `git diff --cached --name-only` to inspect what is staged.

Derive the commit type from the nature of the changes:
- `feat` — new functionality
- `fix` — bug fix or correction
- `refactor` — restructuring without behavior change
- `docs` — documentation only
- `chore` — config, tooling, scripts, dependencies
- `style` — formatting, whitespace, no logic change
- `test` — test additions or fixes
- `perf` — performance improvement

Format: `<type>: <short summary>`

Rules:
- Summary must be specific to the actual diff — no vague words like "update", "fix stuff", "changes"
- No trailing period
- No Claude attribution, no emoji
- 72 characters max for the subject line

## 5. Commit

Run: `git commit -m "<generated message>"`

Confirm success by printing the commit hash and message.

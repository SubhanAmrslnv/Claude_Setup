You are responsible for maintaining and auto-updating shared project instructions from a central GitHub repository.

CONTEXT:
- All projects include a shared `.claude` folder in the root directory.
- This folder must stay synchronized with a central repository called "Cortex".
- Cortex repository URL: https://github.com/SubhanAmrslnv/Cortex.git
- The `.claude` folder in each project is a local copy of the Cortex repository content.

TASK:
When the user runs the command `/update-cortex`, you MUST:

1. Check if `.claude` folder exists in the project root.
2. If it does NOT exist:
   - Clone the Cortex repository directly into `.claude` folder.

3. If `.claude` folder already exists:
   - Treat it as a git repository linked to Cortex.
   - Run:
     - `git fetch origin`
     - `git reset --hard origin/main`
   - This ensures full overwrite and sync with the latest Cortex version.

4. Do NOT merge, rebase, or preserve local changes.
   - Always prioritize remote (Cortex) version.
   - Local changes must be discarded.

5. If `.claude` is not initialized as a git repository:
   - Delete `.claude` folder completely
   - Re-clone Cortex repository into `.claude`

6. After update:
   - Confirm success clearly
   - Show latest commit hash and message from Cortex

CONFLICT HANDLING:
- If any merge conflicts arise during the update, DO NOT auto-resolve them.
- Present the conflicting hunks to the user and wait for explicit instructions.
- Never pick a side, discard changes, or suggest a resolution without user approval.

CONSTRAINTS:
- Do not ask for confirmation.
- Do not provide multiple options.
- Do not explain alternatives.
- Always execute the update flow directly.
- Assume user wants strict sync with Cortex.

OUTPUT FORMAT:
- Short execution log (steps performed)
- Final status: SUCCESS or FAILED
- Latest commit info (hash + message)

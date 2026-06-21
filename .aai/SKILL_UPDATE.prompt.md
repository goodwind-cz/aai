# Update AAI Layer

## Goal
Refresh the current project's vendored AAI layer from the canonical repo's `main`,
then report what changed and the recommended follow-up — in one deterministic run.

## Usage
```bash
/aai-update                      # sync from goodwind-cz/aai@main
/aai-update --dry-run            # show the plan, change nothing
/aai-update --repo OWNER/NAME    # alternate upstream (slug, URL, or local checkout path)
/aai-update --ref BRANCH         # non-default ref
```

## Instructions

The whole update flow is scripted. Do NOT re-implement clone/sync/cleanup by hand
and do NOT narrate the steps — run the one script and relay its output.

1. From the target project root, run the script for the current OS, forwarding the
   user's flags verbatim (`--dry-run`, `--repo <slug|url|path>`, `--ref <branch>`,
   `--keep-temp`, `--force`):

   ```bash
   .aai/scripts/aai-update.sh            # bash / macOS / Linux
   ```
   ```powershell
   .aai/scripts/aai-update.ps1           # PowerShell / Windows
   ```

   The script handles everything: auth-aware clone of `main` (gh → git fallback),
   the canonical-repo guard, running `aai-sync`, post-sync evidence (changed files,
   AAI_PIN, conflict advisory), and temp cleanup.

2. Relay the script's output as a SHORT report — do not paste the full sync log.
   Surface only: target path, upstream + ref, sync vs dry-run, changed-file count
   (and notable paths), any conflict-advisory path, and the recommended next command.

3. If the script exits non-zero, report the cause plainly and stop:
   - exit 2 = refused (this looks like the canonical AAI repo; use normal git, or `--force`)
   - exit 3 = upstream fetch failed (auth/network — an access issue, not a missing repo)
   - exit 4 = source is malformed (sync script missing in the fetched source)

## Safety
- Never auto-commit. Stop after reporting the diff and next steps; the user commits.
- If a conflict advisory was written, tell the user to review it before committing.
- The script preserves project-specific files via aai-sync's rules — never hand-copy
  or hand-overwrite vendored files to "fix" an update.

# Update AAI Layer

## Goal
Refresh the current project's vendored AAI layer from the `main` branch of the canonical git repository, review what changed, and surface any follow-up actions.

## Usage

```bash
/aai-update
/aai-update --dry-run
/aai-update --repo goodwind-cz/aai
```

## Instructions

### 1. Resolve target and upstream source

- Treat the current working directory as the target project to update.
- Default upstream repository to `goodwind-cz/aai` and default ref to `main`.
- If the user supplied `--repo`, use that repository slug, SSH remote, or HTTPS remote instead.
- Treat the upstream as potentially private. Prefer authenticated access.
- Do not use `.aai/system/AAI_PIN.md` as the sync source. It is only post-sync evidence.
- If the current project is itself the canonical AAI repository checkout, stop and explain that `/aai-update` is for syncing AAI into a target project; updating the canonical AAI repository itself should be done with normal git workflow.

### 2. Decide execution mode

- If the user asked for preview only, or supplied `--dry-run`, do not modify files.
- For preview mode, show the exact git clone/fetch + sync commands that should be run and describe the expected follow-up checks.
- Otherwise continue with the sync.

### 3. Materialize the latest `main`

- Create a temporary working directory for the update source.
- If GitHub CLI is available and authenticated, prefer it for private repositories:

```bash
gh repo clone <REPO_SLUG> <TEMP_AAI_DIR> -- --branch main --depth 1
```

- Otherwise fetch the canonical repository with an authenticated git remote:

```bash
git clone --branch main --depth 1 <REPO_URL> <TEMP_AAI_DIR>
```

- If the user explicitly provided an existing local checkout instead of a URL, update it first:

```bash
git -C <LOCAL_AAI_CHECKOUT> fetch origin main --depth 1
git -C <LOCAL_AAI_CHECKOUT> checkout main
git -C <LOCAL_AAI_CHECKOUT> pull --ff-only origin main
```

- Use the checked out files from the fetched `main` as `<SOURCE>`.

### 4. Run the sync

- Prefer the script that matches the current shell/OS:

```powershell
& "<SOURCE>/.aai/scripts/aai-sync.ps1" -TargetRoot .
```

```bash
"<SOURCE>/.aai/scripts/aai-sync.sh" .
```

- Run the script from the target project root so relative paths in the output stay meaningful.
- Do not hand-copy files that the sync script already manages.

### 5. Review update evidence

- Inspect `git status --short`.
- Re-read `.aai/system/AAI_PIN.md` and report the updated source/version/commit if available.
- Check for conflict advisory reports:
  - `docs/ai/reports/sync-conflicts-*.md`
- If a conflict advisory exists, summarize the affected paths and tell the user to review the generated recommendations before committing.

### 6. Recommend post-update health checks

- If the target project uses dynamic/project-local skills or if the sync changed skill indexes, recommend:
  - `/aai-bootstrap`
- Recommend:
  - `/aai-doctor`
  - `/aai-test-skills`
- If the repo only needed a dry-run, present these as next steps rather than executed steps.

### 7. Return concise completion output

- Report:
  - target project path
  - upstream git repository slug or remote
  - upstream ref
  - whether this was a real sync or dry-run
  - key changed files/directories from `git status --short`
  - conflict advisory report path if created
  - recommended next command

## Safety

- Do not overwrite project-specific docs manually; let the sync script enforce its preservation rules.
- Do not claim success without showing the sync command result and post-sync evidence.
- Do not auto-commit; stop after reporting the diff and next steps.
- Clean up temporary clone directories after the update unless the user asks to keep them.
- If upstream access fails, report it as an authentication/authorization issue instead of implying the repository is missing.

---
id: pr-ceremony-friction-fixes
type: issue
number: 121
status: done
links:
  pr: []
  commits: []
---

# PR ceremony friction: evidence names trip the secrets check, and the base sync runs on an uncommitted tree

## Summary
Two downstream friction reports against the PR ceremony, both from a project
pinned at v2026.10.29 (harness claude, macOS):

1. GitHub issue #565 (human_corrected_defect, aai-pr/commit):
   `.aai/scripts/pre-commit-checks.sh` CHECK 2 blocks any staged file whose
   path contains `secret`, `credentials` or `.env`, whatever the file holds.
   A Validation role named its evidence log `worker-env-and-secrets` (it held
   only environment variable NAMES) and the ride's close commit failed.
2. GitHub issue #566 (abstraction_leak_recovery, aai-pr/sync-with-base):
   `.aai/SKILL_PR.prompt.md` step 5b syncs the branch with base even when the
   commit step left staged changes or did not move HEAD, so the merge runs on
   an uncommitted tree.

## Type
bug

## Impact
- Every project that vendors the layer. (1) blocks a ride's close commit on a
  harmless evidence file name; the operator has to rename by hand. (2) lets
  an agent merge base into a branch whose content commit never happened; the
  merge either aborts silently or records unrelated staged changes.
- Severity: P2 (both reported high impact, reproducible, manual workaround).

## Current Behavior
- (1) CHECK 2 runs a content scan over each staged file, then a name check:
  `*.env*`, `*credentials*`, `*secret*` anywhere in the path is an error.
  Evidence under `docs/ai/validation`, `docs/ai/tdd`, `docs/ai/reports` and
  `docs/ai/reviews` is treated the same as any other path.
- (2) Step 5b is prose only; nothing checks the index or HEAD before the
  sync merge.

## Expected Behavior
- (1) A staged file under one of the AAI evidence folders (`docs/ai/reports`,
  `docs/ai/tdd`, `docs/ai/validation`, `docs/ai/reviews`) is judged by its
  content only: the content scan still blocks a secret-looking assignment
  there, the name alone does not. Every other path keeps the name check
  unchanged (a staged `.env`, `config/credentials.json` or `secret.key`
  outside those folders is still blocked).
- (1) The role prompt that tells a role where to put local evidence also
  tells it not to use these words in evidence file names.
- (2) Before syncing with base, a deterministic script check refuses while
  `git diff --cached` is non-empty, or while HEAD still equals the HEAD
  recorded before the commit step; step 5b calls it.

## Steps to Reproduce (if applicable)
1) (1) In a git repository carrying the layer, stage
   `docs/ai/validation/worker-env-and-secrets.txt` holding `API_BASE_URL` and
   `DB_NAME`, run `bash .aai/scripts/pre-commit-checks.sh`: exit 1,
   "Sensitive file staged".
2) (2) Leave a change staged after a failed `git commit`, then follow step
   5b: nothing stops `git merge origin/main`.

## Verification
- New failing-first cases in `tests/skills/test-aai-pre-commit-checks.sh`
  (evidence-folder name, evidence-folder secret content, `.env` and
  credential files elsewhere still blocked) and in the branch-guard suite for
  the sync check (staged change refused, HEAD not advanced refused, clean
  advanced tree admitted).
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>`
  passes for each touched suite.

## Constraints / Risks
- `.aai/scripts/pre-commit-checks.sh` is an L3 protected surface
  (`docs/ai/docs-audit.yaml` `protected_paths_l3`): ceremony level 3.
- `.aai/scripts/pre-commit-checks.ps1` is a retired deprecation launcher (no
  checks); there is no PowerShell twin to keep in parity.
- Existing pins in `tests/skills/test-aai-pre-commit-checks.sh` (TEST-3454
  diff size against its baseline, TEST-3461 line counts) move with the edit.
- Prompt-corpus governance applies to any `.aai` prompt change.
- Do not touch files of open PRs #563 and #564 (docs-audit, docs-audit-core,
  pre-commit-index.sh, test-aai-docs-audit.sh, allocate-doc-number.mjs,
  test-aai-intake.sh).
- Secrets preflight results: no secret referenced.

## Notes
- Implementation mode (autopilot recommendation): tdd. A guard change on an
  L3 surface plus a new deterministic ceremony check.
- Autopilot defaults: human_time_minutes null.

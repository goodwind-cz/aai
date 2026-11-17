---
id: hook-gate-staged-content
type: issue
capability: docs-close-gate
number: null
status: draft
links:
  pr: []
  commits: []
---

# Commit-time guards read the working tree and skip some staged files

## Summary
Four open follow-ups (docs/ai/decisions.jsonl) describe one defect class: a
commit-time guard decides on something other than the staged content, or
never looks at a staged file at all. The owner chose to close them together
(2026-11-17):

1. `fu-hook-gate-reads-worktree-spec` (Codex P1 on PR #564): the docs close
   gate in `.aai/templates/git-hooks/pre-commit-index.sh` gates a staged
   intake done-flip through its linked spec(s), but `docs-audit.mjs
   --gate-file` reads those linked specs from the working tree, so an
   unstaged edit of a linked spec decides the verdict of the commit.
2. `fu-precommit-deleted-staged-skip`: `.aai/scripts/pre-commit-checks.sh`
   CHECK 2 skips a staged file whose working-tree copy was deleted
   (`[ -f ]` guard), so a staged secret behind an `rm` is never scanned.
3. `fu-precommit-suffix-env-evidence`: inside the four evidence folders
   (`docs/ai/{reports,tdd,validation,reviews}`) a suffix dotenv name such as
   `prod.env` passes CHECK 2 by name; only `.env` and `.env.*` basenames stay
   blocked there.
4. `fu-precommit-quoted-path-skip`: CHECK 2 reads `git diff --cached
   --name-only` with `core.quotePath` on, so a staged name with non-ASCII
   characters arrives quoted, fails `[ -f ]` and skips every check.

Optional, owner-approved only if small and safe:
`fu-gate-not-called-by-close-item` (close-work-item.mjs flips docs to done
without running the close gate itself).

## Type
bug

## Impact
- Every project that vendors the layer and installs the pre-commit hook or
  runs `pre-commit-checks.sh` before a commit. The secrets check (CHECK 2) is
  the one blocking check of that script; each skip lets a staged secret or a
  sensitive file name into a commit. The close gate under `close_gate:
  enforce` can pass or refuse a commit on content the commit does not record.
- Severity: P3 each (follow-up severity); together they are a guard-integrity
  defect on an L3 surface.

## Current Behavior
- (1) `gateFile` in `.aai/scripts/lib/docs-audit-core.mjs` resolves linked
  specs through `scanGateEntries(root)`, which reads every scanned doc from
  the working tree.
- (2) CHECK 2 (and CHECK 3/4) `continue` when the working-tree file is
  absent, even when the index holds a blob for it.
- (3) The evidence-folder exemption re-blocks only basenames `.env` and
  `.env.*`.
- (4) The staged list is newline-separated with C-quoted names.

## Expected Behavior
- (1) When the hook gates a commit, the intake doc and every linked spec are
  read from the index (the staged blob); a linked spec absent from the index
  falls back to HEAD's committed blob. The gate itself is not duplicated:
  `docs-audit.mjs --gate-file` gains a staged mode that feeds the existing
  resolver from the index.
- (2) A staged file is scanned whenever the index holds a blob for it,
  whatever the working tree says.
- (3) A basename ending in `.env` is blocked by name in every folder, like
  `.env` and `.env.*`.
- (4) The staged list is read NUL-separated (`-z`), so every staged name,
  including non-ASCII ones, is checked under its real path.

## Steps to Reproduce (if applicable)
1) (1) Stage an intake doc flipped to `status: done` whose linked spec has a
   failing AC table in the index; fix the spec only in the working tree;
   commit through the installed hook with `close_gate: enforce`: the gate
   passes.
2) (2) Stage `app/config.txt` holding an `api_key = "..."` assignment, then
   `rm app/config.txt`; run `bash .aai/scripts/pre-commit-checks.sh`: exit 0.
3) (3) Stage `docs/ai/tdd/prod.env` with harmless content: exit 0, no
   "Sensitive file staged" line.
4) (4) Stage `app/café.txt` (a real non-ASCII name) holding an api_key
   assignment: exit 0.

## Verification
- Failing-first cases in `tests/skills/test-aai-pre-commit-checks.sh` for
  (2), (3), (4) and in `tests/skills/test-aai-docs-audit.sh` for (1) (staged
  mode of `--gate-file` and the hook through a real `git commit`).
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/<suite>`
  passes for each touched suite.

## Constraints / Risks
- `.aai/scripts/pre-commit-checks.sh` is an L3 protected surface
  (`docs/ai/docs-audit.yaml` `protected_paths_l3`): ceremony level 3, the
  owner merges.
- The hook template is installed downstream; a staged mode must not slow a
  commit noticeably (one batched git read, not one process per doc).
- Secrets preflight: no secret referenced.

## Notes
- Assumption (autopilot): CHECK 3 and CHECK 4 share CHECK 2's file loop
  shape and the same `[ -f ]` skip; they move to the index-existence test and
  the staged blob together with CHECK 2, since the follow-up names CHECK 2-4.
- Assumption (autopilot): `fu-gate-not-called-by-close-item` is evaluated in
  Planning; it is included only if the wiring is small and safe.

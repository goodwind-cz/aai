---
id: spec-release-tagged-by-ci-after-merge
type: spec
number: 228
status: done
frozen_sha256: f4158ae10382ab13d371452ef1f066659c0dcafd7a24bde1047b750f13a2a750
ceremony_level: 2
links:
  requirement: release-tagged-by-ci-after-merge
  rfc: null
  pr: []
  commits: []
---

# Spec — Release Tagged and Published by CI After Merge

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-0015-release-tagged-by-ci-after-merge.md
- Engine: .aai/scripts/aai-release.sh
- Engine: .aai/scripts/aai-release.ps1
- Workflow: .github/workflows/release.yml
- Canon: .aai/SKILL_RELEASE.prompt.md
- Test Suite: tests/skills/test-aai-release.sh
- Test Suite: tests/skills/aai-release.Tests.ps1
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: direct
- Rationale: Direct refactor of release engines and workflow to make PR-only cut in isolated worktree the primary path and delegate tagging/publishing to CI on merge.

## Acceptance Criteria Details

### Spec-AC-01 (PR-only release cut in isolated temporary worktree)
`aai-release.sh --confirm` builds the release commit `chore(release): $VERSION` on branch `chore/release-$VERSION` in a temporary worktree created from `origin/main` (or `$REMOTE/$BRANCH`). It never creates a local tag in the caller's repository. After creating and pushing `chore/release-$VERSION` and opening the release PR via `gh pr create`, it removes the temporary worktree and leaves the caller's repository/checkout completely byte-identical and clean, even when run from a detached HEAD or a dirty checkout.
- **Verify:** `--confirm` from a detached HEAD, dirty tree, or clean branch opens a release PR, creates no local tag, and leaves the caller's tree byte-identical.
- **Test Plan:** TEST-001 | integration | tests/skills/test-aai-release.sh | release cut builds in temporary worktree leaving caller clean | none | pending

### Spec-AC-02 (CI tag and publish on merge of release PR)
`.github/workflows/release.yml` triggers on push to `main` (in addition to `push: tags: 'v*'`). When the pushed commit on `main` is a release commit (`chore(release): <version>`), the workflow extracts `<version>`, creates the annotated tag `git tag -a "$TAG" -m "$TAG"`, pushes the tag `refs/tags/$TAG` to `origin`, extracts the release notes from `CHANGELOG.md`'s `## [$TAG]` section, and publishes the GitHub release via `gh release create`. The operation is idempotent (skips tag/release creation if already present).
- **Verify:** Merging `chore(release): vX` to `main` triggers tag creation and GitHub release publication with exact CHANGELOG notes.
- **Test Plan:** TEST-002 | unit | tests/skills/test-aai-release.sh | workflow tags on merge and publishes release idempotently | none | pending

### Spec-AC-03 (Elimination of direct push, local tagging, and exits 17 and 18)
`aai-release.sh` removes the direct branch push attempt, the protected branch rejection classifier (`is_protected_branch_rejection`), the local tag creation (`git tag -a`), the pre-cut reset (`git reset --hard $PRE_CUT_SHA`), and exit codes 17 and 18. Opening the PR is the primary success path (exit 0).
- **Verify:** `aai-release.sh` contains no references to exit 17 or exit 18, and `test_034_exit_codes_documented` passes.
- **Test Plan:** TEST-003 | unit | tests/skills/test-aai-release.sh | removal of direct push fallback exits 17 and 18 | none | pending

### Spec-AC-04 (Drop golden flow release coupling)
`aai-release.sh` drops `golden_flow_record_gap` and any release-time golden flow warning. CI already runs golden-flow tests.
- **Verify:** `aai-release.sh` does not check or warn about golden flow records.
- **Test Plan:** TEST-004 | unit | tests/skills/test-aai-release.sh | golden flow record check removed from release engine | none | pending

### Spec-AC-05 (House link style support for unlogged PR check)
`unlogged_prs` in `aai-release.sh` recognizes the repository's house link styles (e.g. `(#123)`, `#123`, `goodwind-cz/aai#123`), preventing false-positive unlogged PR warnings for documented PRs.
- **Verify:** PRs referenced with house link styles in CHANGELOG notes are not flagged as unlogged.
- **Test Plan:** TEST-005 | unit | tests/skills/test-aai-release.sh | house link styles recognized in unlogged PR check | none | pending

### Spec-AC-06 (PowerShell parity in aai-release.ps1)
`aai-release.ps1` mirrors the bash engine: isolated worktree build for `--confirm`, zero local tags, PR opening, removal of exits 17/18, removal of golden flow coupling, and updated unlogged PR matching.
- **Verify:** `aai-release.ps1` behaves identically to `aai-release.sh`.
- **Test Plan:** TEST-006 | unit | tests/skills/aai-release.Tests.ps1 | PowerShell release twin matches bash engine contract | none | pending

### Spec-AC-07 (SKILL_RELEASE prompt updates and prompt diet)
`.aai/SKILL_RELEASE.prompt.md` is updated to reflect that `/aai-release --confirm` opens a PR and CI tags and publishes on merge. Exits 17 and 18 are removed from the prompt. Prompt diet is reconciled with a reclaimed credit entry in `prompt-diet-ledger.sh`.
- **Verify:** `.aai/SKILL_RELEASE.prompt.md` documents only active exit codes, prompt diet passes.
- **Test Plan:** TEST-007 | unit | tests/skills/test-aai-release.sh | SKILL_RELEASE documents active exit codes and prompt diet passes | none | pending

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | PR-only release cut in isolated temporary worktree | done | TEST-003, TEST-009, TEST-027, TEST-028, TEST-029 in tests/skills/test-aai-release.sh | — | verified |
| Spec-AC-02 | CI tag and publish on merge of release PR | done | TEST-030 in tests/skills/test-aai-release.sh | — | verified |
| Spec-AC-03 | Elimination of direct push, local tagging, and exits 17 and 18 | done | TEST-005, TEST-032 in tests/skills/test-aai-release.sh | — | verified |
| Spec-AC-04 | Drop golden flow release coupling | done | TEST-036 in tests/skills/test-aai-release.sh | — | verified |
| Spec-AC-05 | House link style support for unlogged PR check | done | TEST-031 in tests/skills/test-aai-release.sh | — | verified |
| Spec-AC-06 | PowerShell parity in aai-release.ps1 | done | TEST-019, TEST-033 in tests/skills/test-aai-release.sh, aai-win-dispatch.Tests.ps1 | — | verified |
| Spec-AC-07 | SKILL_RELEASE prompt updates and prompt diet | done | TEST-034 in tests/skills/test-aai-release.sh, tests/skills/test-aai-prompt-diet.sh | — | verified |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | release cut builds in temporary worktree leaving caller clean | none | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-release.sh | workflow tags on merge and publishes release idempotently | none | green |
| TEST-003 | Spec-AC-03 | unit | tests/skills/test-aai-release.sh | removal of direct push fallback exits 17 and 18 | none | green |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-release.sh | golden flow record check removed from release engine | none | green |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-release.sh | house link styles recognized in unlogged PR check | none | green |
| TEST-006 | Spec-AC-06 | unit | tests/skills/aai-release.Tests.ps1 | PowerShell release twin matches bash engine contract | none | green |
| TEST-007 | Spec-AC-07 | unit | tests/skills/test-aai-release.sh | SKILL_RELEASE documents active exit codes and prompt diet passes | none | green |

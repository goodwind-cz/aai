---
id: spec-amendment-signoff-implied-by-merge
type: spec
number: 226
status: done
frozen_sha256: 25912a814ad89692f3da886a3fb91b0368d29c60cb90ed0d61a9ec0bdbd77c33
ceremony_level: 2
links:
  requirement: amendment-signoff-implied-by-merge
  rfc: null
  pr:
    - 460
  commits:
    - 5479a818
---

# Spec — A contract amendment is signed by the merge of its ride, not by a written record

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-0013-amendment-signoff-implied-by-merge.md
- Engine: .aai/scripts/spec-amend.mjs
- Engine: .aai/scripts/merge-cleanup.mjs
- Canon: .aai/SKILL_MERGE.prompt.md
- Canon: .aai/SKILL_PR.prompt.md
- Test Suite: tests/skills/test-aai-spec-amend.sh
- Test Suite: tests/skills/test-aai-merge-cleanup.sh
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
- Rationale: mechanical addition of read-time implied signature fold in spec-amend.mjs, deletion of dead post-merge signing code in merge-cleanup.mjs, and updating test suites.

## Background & Root Cause
Every contract amendment previously required:
1. A `spec_amendment` record.
2. A `fu-amend-*` tracker item.
3. The `/aai-pr` `spec-amend list --strict` gate.
4. "signs on merge" preflight lines.
5. One `spec_amendment_classification` overlay per record written by `merge-cleanup` sign-amendments after the merge.
6. A tracker close record.

The overlays were written into the main checkout after the merge. Protected `main` cannot take direct pushes from the agent, so every `/aai-merge` left `decisions.jsonl` dirty with uncommitted changes.
The signature is already fully determined by facts in git: the ride doc is `status: done` and its PR is merged into the base branch.

## Acceptance Criteria Details

### Spec-AC-01 (Implied signature fold at read time)
`spec-amend.mjs` folds a contract-class amendment as signed at read time when its ride doc is `status: done` and linked PR is merged into base (the base branch carries the done doc with `links.pr`), without requiring a `spec_amendment_classification` overlay.
- **Verify:** `spec-amend.mjs list` on a repo where a ride doc is merged onto base reports its contract amendments as `signed` (`owner_signoff: true`).
- **Test Plan:** TEST-517 | unit | tests/skills/test-aai-spec-amend.sh | merged ride contract amendment folds to signed | pending

### Spec-AC-02 (Unmerged ride remains unsigned)
An unmerged ride (or a ride whose doc is not done or PR not merged into base) continues to fold as `unsigned-tracked` (or `unsigned-untracked` if untracked), preserving the PR/amendment gate on unmerged rides.
- **Verify:** `spec-amend.mjs list` reports an in-flight unmerged ride's contract amendment as `unsigned-tracked`.
- **Test Plan:** TEST-518 | unit | tests/skills/test-aai-spec-amend.sh | unmerged ride amendment remains unsigned-tracked | pending

### Spec-AC-03 (Existing overlays remain honored)
Existing `spec_amendment_classification` overlays in `decisions.jsonl` remain valid and continue to fold to `signed`, ensuring full backward compatibility with historical records.
- **Verify:** `spec-amend.mjs list` preserves signed status for all historical overlay records.
- **Test Plan:** TEST-519 | unit | tests/skills/test-aai-spec-amend.sh | existing overlays fold to signed | pending

### Spec-AC-04 (Writer and helper deletion in merge-cleanup)
`sign-amendments` step is completely removed from `STEP_IDS` and execution pipeline in `merge-cleanup.mjs`; `signAmendments`, `runSignMerged`, `preflightSigns`, and `appendDirectedMerge` pre-merge writes are deleted.
- **Verify:** `merge-cleanup.mjs` step list does not contain `sign-amendments`, and `sign-merged` subcommand is removed.
- **Test Plan:** TEST-018 amended | integration | tests/skills/test-aai-merge-cleanup.sh | step list excludes sign-amendments | pending

### Spec-AC-05 (Zero post-merge writes to decisions.jsonl)
`merge-cleanup.mjs apply` leaves `docs/ai/decisions.jsonl` completely untouched in the main checkout (`git status --porcelain docs/ai/decisions.jsonl` is empty after merge-cleanup).
- **Verify:** Applying merge-cleanup on a merged PR leaves `decisions.jsonl` unstaged and unmodified.
- **Test Plan:** TEST-018 amended | integration | tests/skills/test-aai-merge-cleanup.sh | decisions.jsonl unmodified after apply | pending

### Spec-AC-06 (Prompt and docs alignment)
`.aai/SKILL_MERGE.prompt.md` and `.aai/SKILL_PR.prompt.md` are updated to remove references to `signs on merge:` preflight lines, `sign-amendments` step, and post-merge amendment signing.
- **Verify:** Prompts no longer instruct agent to expect `signs on merge` or run post-merge amendment signing.
- **Test Plan:** TEST-024 amended | unit | tests/skills/test-aai-merge-cleanup.sh | prompts free of dead signing instructions | pending

### Spec-AC-07 (Green test suites & Codebase reduction)
`test-aai-spec-amend.sh` and `test-aai-merge-cleanup.sh` pass 100% green, and `merge-cleanup.mjs` line count decreases by at least 200 lines.
- **Verify:** `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-spec-amend.sh` and `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-merge-cleanup.sh` exit 0; line count of `merge-cleanup.mjs` <= 1490.
- **Test Plan:** TEST-058 | integration | tests/skills/test-aai-merge-cleanup.sh | suite green and line reduction verified | pending

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Implied signature fold at read time for merged rides | done | TEST-517 in tests/skills/test-aai-spec-amend.sh | — | exit 0 |
| Spec-AC-02 | Unmerged ride remains unsigned-tracked | done | TEST-518 in tests/skills/test-aai-spec-amend.sh | — | exit 0 |
| Spec-AC-03 | Existing overlays honored backward-compatibly | done | TEST-519 in tests/skills/test-aai-spec-amend.sh | — | exit 0 |
| Spec-AC-04 | sign-amendments step and sign-merged helpers removed from merge-cleanup | done | TEST-018 in tests/skills/test-aai-merge-cleanup.sh | — | exit 0 |
| Spec-AC-05 | Zero post-merge writes to decisions.jsonl | done | TEST-020 in tests/skills/test-aai-merge-cleanup.sh | — | exit 0 |
| Spec-AC-06 | Prompts (SKILL_MERGE / SKILL_PR) updated and aligned | done | TEST-024 in tests/skills/test-aai-merge-cleanup.sh | — | exit 0 |
| Spec-AC-07 | Green test suites and merge-cleanup line count reduced by >=200 lines | done | TEST-058 (1310 <= 1490 lines, both suites green) | — | exit 0 |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-517 | Spec-AC-01 | unit | tests/skills/test-aai-spec-amend.sh | Merged ride contract amendment folds to signed at read time | none | green |
| TEST-518 | Spec-AC-02 | unit | tests/skills/test-aai-spec-amend.sh | Unmerged ride contract amendment remains unsigned-tracked | none | green |
| TEST-519 | Spec-AC-03 | unit | tests/skills/test-aai-spec-amend.sh | Historical overlays continue to fold to signed | none | green |
| TEST-018 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | STEP_IDS and handlers exclude sign-amendments | none | green |
| TEST-020 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | decisions.jsonl is not modified by apply | none | green |
| TEST-024 | Spec-AC-06 | unit | tests/skills/test-aai-merge-cleanup.sh | Prompts verify no obsolete signing references | none | green |
| TEST-058 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | Full suites green and merge-cleanup.mjs <= 1490 lines | none | green |

## Isolation and review
- Primary file: `.aai/scripts/spec-amend.mjs`
- Companion file: `.aai/scripts/merge-cleanup.mjs`
- Test files: `tests/skills/test-aai-spec-amend.sh tests/skills/test-aai-merge-cleanup.sh`
- Inline review scope: `.aai/scripts/spec-amend.mjs .aai/scripts/merge-cleanup.mjs tests/skills/test-aai-spec-amend.sh tests/skills/test-aai-merge-cleanup.sh docs/specs/SPEC-0226-spec-amendment-signoff-implied-by-merge.md`

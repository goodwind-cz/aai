---
id: spec-merge-cleanup-dead-steps
type: spec
number: 225
status: done
frozen_sha256: c2bc2261042afd22e95586e321d1d9db591707d0b358e8e3b12d1a20dc8faba8
ceremony_level: 2
links:
  requirement: merge-cleanup-dead-steps
  rfc: null
  pr:
    - TBD
  commits:
    - 733db13489c49ddb8a777c223722e7f94245ebae
---

# Spec — Delete merge-cleanup dead steps, consolidate branch deletion, and drop redundant gates

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-0012-merge-cleanup-dead-steps.md
- Engine: .aai/scripts/merge-cleanup.mjs
- Canon: .aai/SKILL_MERGE.prompt.md
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
- Rationale: mechanical removal of unexercised steps and redundant gates from merge-cleanup.mjs, accompanied by pruning obsolete tests and asserting green on the remaining test suite.

## Background & Root Cause
Over PRs #448 through #457, merge-cleanup grew to nearly 2000 lines. Four steps in the cleanup pipeline have never executed an action (0/8 runs):
1. `archive-drafts`: 0/8
2. `state`: 0/8 (`focus_not_this_ref`, focus already cleared at close since SPEC-0224)
3. `index-audit`: 0/8 (index checked by CI and pre-commit)
4. `reexec`: 0/8 (engine self-reexec mechanism never triggered in real workflows)

Additionally:
- Preflight duplicates gates that GitHub and `--match-head-commit` already enforce (`checks_failing`, `not_mergeable`).
- `archive-runtime` copies up to 34 MB of gitignored files per merge that are never referenced.
- Branch deletion is split across two separate steps (`delete-branch` and `delete-remote-branch`).
- Report is written to disk in duplicate rather than emitted to stdout.

## Acceptance Criteria Details

### Spec-AC-01 (Dead steps removed from pipeline)
`archive-drafts`, `state`, `index-audit`, and `reexec` are completely removed from `STEP_IDS` and execution pipeline in `merge-cleanup.mjs`.
- **Verify:** `node -e 'import("./.aai/scripts/merge-cleanup.mjs")'` or step list inspection contains none of `archive-drafts`, `state`, `index-audit`, `reexec`.
- **Test Plan:** TEST-010 amended | integration | tests/skills/test-aai-merge-cleanup.sh | step list excludes dead steps | pending

### Spec-AC-02 (Runtime archive narrowed)
`archive-runtime` copies only the ride's `STATE.yaml` file (if present) to the archive root, skipping gitignored evidence folders (`reports`, `tdd`, `validation`, `reviews`, `evidence`).
- **Verify:** Applying merge-cleanup archives `docs/ai/STATE.yaml` and does not copy files under runtime directories.
- **Test Plan:** TEST-010 amended | integration | tests/skills/test-aai-merge-cleanup.sh | runtime archive includes only STATE.yaml | pending

### Spec-AC-03 (Branch deletion consolidated)
Local and remote branch deletion are consolidated into a single `delete-branch` step that removes the local branch and deletes the merged remote branch by lease.
- **Verify:** Step list contains `delete-branch` and no `delete-remote-branch`; applying removes local branch and deletes remote branch with lease.
- **Test Plan:** TEST-036 amended | integration | tests/skills/test-aai-merge-cleanup.sh | delete-branch deletes local and remote branch | pending

### Spec-AC-04 (Duplicate preflight gates pruned)
Preflight no longer evaluates `checks_failing` or `not_mergeable`, delegating those checks to GitHub branch protection and `--match-head-commit`.
- **Verify:** `preflight` does not query or refuse on GitHub status checks rollup or mergeStateStatus.
- **Test Plan:** TEST-001 amended | integration | tests/skills/test-aai-merge-cleanup.sh | preflight passes without statusCheckRollup evaluation | pending

### Spec-AC-05 (Report stdout-only)
`merge-cleanup` outputs the final report exclusively to stdout; no duplicate report files are written to `docs/ai/archive/merge-cleanup/pr-N/report.txt`.
- **Verify:** Running apply writes journal.jsonl and manifest.jsonl but no report.txt.
- **Test Plan:** TEST-010 amended | integration | tests/skills/test-aai-merge-cleanup.sh | report printed to stdout, no report.txt file created | pending

### Spec-AC-06 (Historical journal tolerance)
The journal reader tolerates historical journal entries naming removed steps (`archive-drafts`, `state`, `index-audit`, `reexec`, `delete-remote-branch`) without error or failure.
- **Verify:** `merge-cleanup` plan/apply on a fixture with historical journal entries succeeds without error.
- **Test Plan:** TEST-056 | unit | tests/skills/test-aai-merge-cleanup.sh | journal with removed steps parsed cleanly | pending

### Spec-AC-07 (Codebase reduction & Green suite)
`merge-cleanup.mjs` line count decreases by at least 250 lines, and the pruned `test-aai-merge-cleanup.sh` suite passes 100% green.
- **Verify:** `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-merge-cleanup.sh` exits 0.
- **Test Plan:** TEST-057 | integration | tests/skills/test-aai-merge-cleanup.sh | full suite green | pending

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Dead steps (archive-drafts, state, index-audit, reexec) removed from STEP_IDS and pipeline | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-010 pass |
| Spec-AC-02 | Runtime archive narrowed to STATE.yaml only, dropping gitignored runtime directories | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-011 pass |
| Spec-AC-03 | Local and remote branch deletion consolidated into a single delete-branch step | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-036 pass |
| Spec-AC-04 | Duplicate preflight check gates (checks_failing, not_mergeable) removed | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-001 pass |
| Spec-AC-05 | Report output printed strictly to stdout with no duplicate report.txt file written | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-015 pass |
| Spec-AC-06 | Journal reader tolerates historical journals naming removed steps | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-056 pass |
| Spec-AC-07 | Codebase line count reduced by >=250 lines and test suite passes green | done | docs/ai/reports/VALIDATION-20261011235906-merge-cleanup-dead-steps.md | — | TEST-057 pass |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-010 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | Step list verification: excludes archive-drafts, state, index-audit, reexec | none | passed |
| TEST-011 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | Runtime archive verification: archives only STATE.yaml and excludes runtime directories | none | passed |
| TEST-036 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | Consolidated delete-branch step deletes both local branch and merged remote branch | none | passed |
| TEST-001 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | Preflight without redundant GitHub check gates | none | passed |
| TEST-015 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | Report output printed to stdout only, no report.txt written to disk | none | passed |
| TEST-056 | Spec-AC-06 | unit | tests/skills/test-aai-merge-cleanup.sh | Historical journal reader tolerance for removed steps | none | passed |
| TEST-057 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | Pruned merge-cleanup test suite execution is green | none | passed |

## Isolation and review
- Primary file: `.aai/scripts/merge-cleanup.mjs`
- Test file: `tests/skills/test-aai-merge-cleanup.sh`
- Inline review scope: `.aai/scripts/merge-cleanup.mjs tests/skills/test-aai-merge-cleanup.sh docs/specs/SPEC-0225-spec-merge-cleanup-dead-steps.md`

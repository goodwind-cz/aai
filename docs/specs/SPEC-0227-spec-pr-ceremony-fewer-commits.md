---
id: spec-pr-ceremony-fewer-commits
type: spec
number: 227
status: done
frozen_sha256: b2989f4f62cbf19c721b7e1e1982b50f7390b965da054e1eaf7ea0d815a29dc1
ceremony_level: 2
links:
  requirement: pr-ceremony-fewer-commits
  rfc: null
  pr: []
  commits: []
---

# Spec — PR Ceremony Stops Adding Commits After Content Commit

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/DEBT-0014-pr-ceremony-fewer-commits.md
- Engine: .aai/scripts/generate-docs-index.mjs
- Engine: .aai/scripts/close-work-item.mjs
- Engine: .aai/scripts/lane-gate.mjs
- Engine: .aai/scripts/merge-cleanup.mjs
- Canon: .aai/SKILL_PR.prompt.md
- Canon: .aai/SKILL_MERGE.prompt.md
- Test Suite: tests/skills/test-aai-close-work-item.sh
- Test Suite: tests/skills/test-aai-merge-cleanup.sh
- Test Suite: tests/skills/test-aai-docs-audit.sh
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
- Rationale: Mechanical removal of redundant PR ceremony steps, clock line from docs index, committed pr_sweep ledger writes, and dead close-before-push-guard.

## Acceptance Criteria Details

### Spec-AC-01 (Deterministic docs/INDEX.md without clock line)
`generate-docs-index.mjs` no longer writes a `Generated: <ISO timestamp>` clock line in `docs/INDEX.md` or its companions. Running `generate-docs-index.mjs` over an unmodified tree produces byte-identical output with 0 git diff.
- **Verify:** Multiple runs of `generate-docs-index.mjs` leave `git status docs/INDEX.md` clean.
- **Test Plan:** TEST-001 | unit | tests/skills/test-aai-docs-audit.sh | generate-docs-index produces deterministic output with no clock line | none | pending

### Spec-AC-02 (Zero pr_sweep ledger writes in PR ceremony)
`.aai/SKILL_PR.prompt.md` no longer instructs the agent to record a committed `pr_sweep` event in `docs/ai/EVENTS.jsonl`. The PR ceremony does not add a commit to record `pr_sweep`.
- **Verify:** PR ceremony creates zero commits for `pr_sweep`.
- **Test Plan:** TEST-002 | unit | tests/skills/test-aai-merge-cleanup.sh | SKILL_PR prompt free of pr_sweep commit instructions | none | pending

### Spec-AC-03 (Live unresolved review check at merge preflight)
`merge-cleanup.mjs preflight` checks open review comments directly via GitHub CLI / API rather than relying on a committed `pr_sweep` event in `docs/ai/EVENTS.jsonl`. Any unresolved review comments block preflight with an actionable report; zero writes are made to `EVENTS.jsonl`.
- **Verify:** `merge-cleanup.mjs preflight` refuses merge when review threads are unresolved, and succeeds with 0 ledger writes when threads are resolved.
- **Test Plan:** TEST-003 | integration | tests/skills/test-aai-merge-cleanup.sh | preflight checks review threads live with zero ledger writes | none | pending

### Spec-AC-04 (Lane gate drops committed sweep requirement)
`lane-gate.mjs` removes the `--sweep-check` requirement that insisted on a committed `pr_sweep` record in `EVENTS.jsonl` matching the PR head SHA.
- **Verify:** `lane-gate.mjs` does not block a merge due to a missing `pr_sweep` event in `EVENTS.jsonl`.
- **Test Plan:** TEST-004 | unit | tests/skills/test-aai-merge-cleanup.sh | lane-gate passes without pr_sweep event in EVENTS.jsonl | none | pending

### Spec-AC-05 (Single-pass close ceremony without --pr TBD sentinels)
`close-work-item.mjs` runs once before the PR content commit without requiring `--pr TBD` sentinels or a follow-up `--stamp-pr` transaction commit. Ephemeral ride commit SHAs are not stamped into `links.commits`.
- **Verify:** `close-work-item.mjs` completes work item closure cleanly in a single pass.
- **Test Plan:** TEST-005 | unit | tests/skills/test-aai-close-work-item.sh | single-pass close without pr TBD sentinel or stamp-pr | none | pending

### Spec-AC-06 (Deletion of close-before-push-guard.mjs and duplicate probes)
`.aai/scripts/close-before-push-guard.mjs` is deleted, and references to it in `.aai/SKILL_PR.prompt.md` and `.aai/system/PROFILES.yaml` are removed.
- **Verify:** `close-before-push-guard.mjs` is deleted and not called in `SKILL_PR`.
- **Test Plan:** TEST-006 | unit | tests/skills/test-aai-close-work-item.sh | close-before-push-guard removed cleanly | none | pending

### Spec-AC-07 (Prompt diet for SKILL_PR)
`.aai/SKILL_PR.prompt.md` line count and token size are significantly reduced by eliminating post-PR ceremony loops, `pr_sweep` instructions, and `--stamp-pr` transactions.
- **Verify:** Line count of `.aai/SKILL_PR.prompt.md` decreases significantly, prompt diet tests pass.
- **Test Plan:** TEST-007 | unit | tests/skills/test-aai-merge-cleanup.sh | SKILL_PR prompt diet verified | none | pending

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | Deterministic docs/INDEX.md without clock line | done | TEST-001 in tests/skills/test-aai-docs-audit.sh | — | verified |
| Spec-AC-02 | Zero pr_sweep ledger writes in PR ceremony | done | TEST-002 in tests/skills/test-aai-merge-cleanup.sh | — | verified |
| Spec-AC-03 | Live unresolved review check at merge preflight | done | TEST-003 in tests/skills/test-aai-merge-cleanup.sh | — | verified |
| Spec-AC-04 | Lane gate drops committed sweep requirement | done | TEST-004 in tests/skills/test-aai-merge-cleanup.sh | — | verified |
| Spec-AC-05 | Single-pass close ceremony without --pr TBD sentinels | done | TEST-005 in tests/skills/test-aai-close-work-item.sh | — | verified |
| Spec-AC-06 | Deletion of close-before-push-guard.mjs and duplicate probes | done | TEST-006 in tests/skills/test-aai-close-work-item.sh | — | verified |
| Spec-AC-07 | Prompt diet for SKILL_PR | done | TEST-007 in tests/skills/test-aai-merge-cleanup.sh | — | verified |

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-docs-audit.sh | generate-docs-index produces deterministic output with no clock line | none | green |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-merge-cleanup.sh | SKILL_PR prompt free of pr_sweep commit instructions | none | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | preflight checks review threads live with zero ledger writes | none | green |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-merge-cleanup.sh | lane-gate passes without pr_sweep event in EVENTS.jsonl | none | green |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-close-work-item.sh | single-pass close without pr TBD sentinel or stamp-pr | none | green |
| TEST-006 | Spec-AC-06 | unit | tests/skills/test-aai-close-work-item.sh | close-before-push-guard removed cleanly | none | green |
| TEST-007 | Spec-AC-07 | unit | tests/skills/test-aai-merge-cleanup.sh | SKILL_PR prompt diet verified | none | green |

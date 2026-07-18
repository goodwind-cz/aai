---
id: remediate-spec-id-collisions
type: issue
number: 15
status: draft
links:
  pr: []
  commits: []
---

# Issue: remediate the 3 legacy spec-id collisions surfaced by SPEC-0057

## Summary
- Three specs were created without the `spec-` prefix, so their frontmatter
  `id` collided with their change docs (SPEC-0048≡DEBT-0002, SPEC-0049≡ISSUE-0010,
  SPEC-0051≡ISSUE-0011). The SPEC-0057 duplicate-doc-id detector flagged them
  (NEEDS-TRIAGE 3). This remediates the collisions so the repo returns to CLEAN.

## Root Cause
- Planning agents named those spec DRAFT slugs without the `spec-` prefix; the
  allocator/audit did not enforce uniqueness (fixed detection in SPEC-0057).

## Fix (applied)
- Renamed each spec's frontmatter `id: <slug>` → `id: spec-<slug>` (SPEC-0048 →
  `spec-prompt-diet-byte-budget-true-up`, SPEC-0049 →
  `spec-secrets-preflight-env-multiline`, SPEC-0051 →
  `spec-spec-lint-duplicate-ac-id`). The change docs keep their `<slug>` id and
  their existing close telemetry.
- Backfilled each renamed spec's close telemetry under the NEW id
  (`doc_lifecycle` →done, `work_item_closed` pass/pass, `ac_evidence` with the
  spec's delivering commit) so it is not flagged missing-close-telemetry or
  probable-false-done.
- Updated SPEC-0057 TEST-104 from "real repo reports the 3 collisions" to "real
  repo has 0 duplicate-doc-ids" (the remediated reality).

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: the 3 spec ids are `spec-`-prefixed and unique; docs-audit reports `Duplicate doc ids: 0` and Verdict CLEAN on the real repo. | pending | |
| AC-002: no spec is flagged missing-close-telemetry or probable-false-done after the rename (telemetry backfilled under the new id); full docs-audit suite green (TEST-104 updated). | pending | |

Ceremony justification: mechanical governance-data remediation (doc-id +
append-only telemetry) + one test update; no product code, self-verified by the
SPEC-0057 detector (L1).

## Verification
- `node .aai/scripts/docs-audit.mjs` → `Duplicate doc ids: 0`, Verdict CLEAN.
- `tests/skills/test-aai-docs-audit.sh` → green (TEST-104 asserts 0 collisions).

## Notes
- Source: SPEC-0057 detector output + decisions.jsonl process_finding (2026-07-18).
  Follow-up still open: enforce the `spec-` prefix at allocation/Planning so this
  cannot recur; harden `byId` (defence-in-depth).

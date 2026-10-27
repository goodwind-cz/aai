---
id: spec-current-head-ci-reader
type: spec
number: 256
status: done
mutation_gate: v1
frozen_sha256: 04d613141a3acdd723ae8e01d5c70395ece20e0e16c6f4bc688b91159219f6c2
ceremony_level: 2
capability: release-command-finish
links:
  requirement: current-head-ci-reader
  rfc: null
  pr: []
  commits: []
---

# Current-head CI result selection

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-0232-current-head-ci-reader.md
- Split decision: docs/decisions/DECISION-release-passes-first-time-split.md
- Product: docs/product/release-command-finish.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy

- Strategy: hybrid
- Rationale: TDD for newest-run selection and fail-closed transport; direct for consumer wiring and product prose.

## Isolation and review

- Worktree recommendation: recommended
- User decision: worktree (continue in existing split worktree)
- Base ref: main
- Inline review scope: `.aai/scripts/lib/github-checks.mjs`, `.aai/scripts/lib/release-rollup.mjs` (pure extract), `.aai/scripts/watch-ci.mjs`, `.aai/scripts/release-finish.mjs`, current-head tests/fixture, suite-map/PROFILES, CHANGELOG, product doc, this intake/spec, append-only evidence.

## Decisions and boundaries

D1. One shared reader/normalizer (`github-checks.mjs`) is consumed by `watch-ci` and every release required-check observation.
D2. Resolve and bind the PR head SHA on both sides of the observation. Paginate authoritative check-run and status pages. Select only the newest run per check name. Actions observations order by workflow creation time, workflow ID, then check-run ID. Do not use response order or success preference.
D3. Mixed heads, incomplete pagination, malformed identities and transport failures refuse closed. Release additionally binds its journal head. Registration grace, required filtering, skipped-check and merge-queue semantics remain.
D4. Pure extraction of the existing release rollup helper into `release-rollup.mjs` is allowed only as a no-behavior-change dependency of the release-finish consumer edit. Dry-run CI job and V4-1 Git-metadata report guards are out of scope (sibling `release-rollup-dry-run`).

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN a cancelled aggregate is red and a newer successful or pending run exists on the same head, watch-ci and the release wait SHALL report the newest outcome, not the superseded failure | done | docs/ai/reports/VALIDATION-20261027T170446Z-current-head-ci-reader.md; TEST-001 | — | — |
| Spec-AC-02 | WHEN heads mix, pagination is incomplete, identities are malformed, or transport fails, the shared reader SHALL refuse closed and never report PASS | done | docs/ai/reports/VALIDATION-20261027T170446Z-current-head-ci-reader.md; TEST-002 | — | — |
| Spec-AC-03 | WHEN the historical PR #504 current-head fixture is replayed, watch-ci and the release wait SHALL not refuse on the cancelled superseded aggregate | done | docs/ai/reports/VALIDATION-20261027T170446Z-current-head-ci-reader.md; TEST-003 | — | — |
| Spec-AC-04 | PROFILES, suite-map, product docs and CHANGELOG SHALL name the current-head reader surfaces for this ride | done | docs/ai/reports/VALIDATION-20261027T170446Z-current-head-ci-reader.md; TEST-004 | — | — |

## Test Plan

| ID | Spec-AC | Verification |
|---|---|---|
| TEST-001 | Spec-AC-01 | Newer pending/success over cancelled; queued same-workflow supersession |
| TEST-002 | Spec-AC-02 | Mixed heads, paging, required filters, malformed transport, ordering permutations |
| TEST-003 | Spec-AC-03 | Historical PR #504 current-head fixture |
| TEST-004 | Spec-AC-04 | Profile, suite-map, product and CHANGELOG pins |

## Notes

Carved from the superseded `release-passes-first-time` worktree after owner split. Parent Validation4 V4-1 remains owned by the sibling ride.

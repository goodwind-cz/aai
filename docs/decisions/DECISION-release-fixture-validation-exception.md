# Decision: Accept only the incomplete global aggregate for the fixture repair

Date: 2026-11-07T09:56:43Z
Blocking ref: release-fixture-atomic-publication
Decided by: human

## Question

Accept a one-off exception for the incomplete global sweep, finish independent review and the pull request, and require green current-head Linux CI, or keep this repair blocked until complete global verification?

## Decision

The owner answered `1`: accept this narrowly scoped exception and continue review and PR preparation. The full command remains exit 124: 125 PASS, one Hermes SKIP, sync-seed TEST-790 interrupted and twenty later cases unstarted (TEST-791 through TEST-796 and TEST-820 through TEST-833). These 21 cases are not declared passed.

The final fixture regression, mutation controls, final-source full release suite and all 58 ordinary/rolled rehearsal executions passed. The immutable Validation report remains FAIL: docs/ai/reports/VALIDATION-release-fixture-atomic-publication.md, SHA256 dfed1cacd87bf9295d1a7b56dd78ded1f1ec20d12ff42ca1e5eaaa811a1d163d.

## Limits

This authorizes the typed workflow exception for this ref only. It does not waive new failures, independent code review or green current-head Linux CI. Hosted CI evidence is obtained after opening the PR and remains a required gate. No second full sweep is authorized or claimed. No general global-gates policy change, merge or release is authorized. The earlier PR #535 exception remains separate.

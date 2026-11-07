# Decision: Extend the deferred hosted-measurement review deadline

Date: 2026-11-07
Blocking ref: SPEC-0245/Spec-AC-06
Decided by: human

## Question

The deferred hosted measurement became overdue on 2026-11-07 UTC. Approve a Review-By extension of 14 days from confirmation, retaining deferred status and pending evidence, or keep PR #535 blocked?

## Decision

The owner answered `1`: approve only the Review-By extension from 2026-11-06 to 2026-11-21 and finish PR #535. The status remains deferred. Hosted after measurements and suite-weight provenance remain pending. No measurement completion or broader validation waiver is authorized.

## Assumptions

Confirmation date is 2026-11-07 UTC. The new deadline is exactly 14 days later. The existing TEST-829/830 and incomplete-full-sweep exception remains separate and unchanged.

## Subsequent base reconciliation

At PR preparation the updated main b27cad401e8e5490985dac8c8cf534f43179f195 already carries independently delivered hosted measurements and Spec-AC-06 done. The rebase preserves that main row unchanged; this earlier date-extension decision remains historical and does not revert completed evidence.

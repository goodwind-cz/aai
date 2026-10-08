# Decision: split native TEST008 follow-up for PR434

Date: 2026-10-08
Blocking ref: pr-capability-preflight
Decided by: human

## Question

Continue a separate bounded native TEST008 fix: obtain the full Windows clone error, verify the path-length hypothesis, use a short lossless evidence alias only if confirmed, then finish fresh Review, metadata-only closure, green native/full CI and independent Validation for PR434; or stop blocked.

## Decision

The owner replied: "Pokracuj" (continue).

## Scope and assumptions

This approves the proposed split TEST008 follow-up within PR434, tracked separately from the completed endpoint parsing repair. It authorizes bounded diagnostic CI snapshots and a minimal cause-based test/evidence repair. Preserve previous failures and historical evidence bytes. Existing isolated worktree and CI snapshot permission continue. Do not weaken any global test/selector/byte gate or change Git global configuration. The provider implementation is outside this follow-up unless actual evidence proves an existing requirement defect.

Fresh independent Review must pass before the previously authorized metadata-only closure; final green native/full CI and independent Validation remain mandatory. This is no gate or merge waiver. Existing frozen-spec follow-up remains owed. Merging is operator-only. Do not reinterpret the prior one-time round as still pending: it ended with its truthful FAIL report; this decision explicitly authorizes the new separately scoped follow-up.

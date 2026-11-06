---
id: singleton-reservation-portability
type: change
number: 247
status: done
links:
  pr:
    - 535
  commits: []
---

# Portable bounded document-number reservations

## Summary
Deliver phase B of RFC-0016: make singleton reservation pushes portable and bound reservation network operations with actionable diagnostics.

## Motivation / Business Value
The allocator currently requires atomic-push support even for one reservation ref and leaves its push unbounded. Servers without atomic support cannot reserve a singleton. Historical downstream failures remain attributed to the RFC report; no live Azure reproduction is claimed.

## Scope
- In scope: allocator reservation transport, executable regression coverage, user-facing contract documentation and RFC-0016 phase B rollout status.
- Out of scope: RFC phases A, C, D and E, capability caching, releases, merges and other Node-first rides.

## Affected Area
`.aai/scripts/allocate-doc-number.mjs` and its existing reservation tests and documentation.

## Desired Behavior (To-Be)
Push exactly one reservation ref without `--atomic`, preserving unique reservation commits and the empty expected-value lease. Keep multi-ref coupled reservations atomic and refuse unsupported atomic transport without partial reservation. Bound network operations and report operation-specific failures without retrying arbitrary errors as collisions.

## Acceptance Criteria
- AC-001: Singleton reservations succeed against a fixture remote that rejects atomic pushes, while retaining create-only uniqueness and collision detection.
- AC-002: Multi-ref reservations retain all-or-nothing atomic semantics, including refusal on unsupported atomic support without partial remote changes.
- AC-003: Reservation network calls have finite timeouts and distinguish timeout, collision, unsupported atomic capability, permission and connectivity failures with actionable diagnostics.
- AC-004: Existing allocator behavior remains covered, including unique-object lease controls and non-collision refusal; no arbitrary-error collision retries.
- AC-005: RFC-0016 phase B cites this change, with the umbrella RFC left open.

## Verification
Use hermetic disposable Git repositories and deterministic transport fixtures, existing impacted suites plus CORE between rounds, and one full sweep during independent Validation before close. All suite invocations unset AAI_ROLE and AAI_GIT_WRITE; full sweep timeout is 3600 seconds.

## Constraints / Risks
Node stdlib only. Preserve append-only ledgers and unrelated shared checkout work. Use an isolated worktree through ride-handoff. No merge or release is authorized. The source brief requested Opus for Planning/Validation/Review and Sonnet for Implementation/Remediation; the owner explicitly overrode that model choice on 2026-11-06 and authorized available Codex models with an independent implementer and validator. Validation and Review execute sequentially; the validator is independent of the implementer. No local secret is referenced.

## Notes
Owner authorization: continue according to the supplied parallel-agent brief, first phase B, one PR per slice. Human-time estimate: null (autopilot default). Implementation strategy is for Planning to decide. The worktree is explicitly authorized by the brief. Parent: `docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md`.

## Delivery evidence

The owner approved the scope-bound exception recorded in docs/decisions/DECISION-singleton-reservation-portability.md. Validation reports remain FAIL; no passing full sweep is claimed. Independent code review passed both verdicts.

- Original validation: docs/ai/reports/VALIDATION-singleton-reservation-portability.md
- Revalidation: docs/ai/reports/VALIDATION-r2-singleton-reservation-portability.md
- Code review: docs/ai/reviews/review-20261106T224004Z-singleton-reservation-portability.md
- Mechanical filename reversal proof: docs/ai/reports/RESTAMP-singleton-reservation-portability.json

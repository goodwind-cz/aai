# Decision: one-time validation exception for reservation portability

Date: 2026-11-06T22:38:52Z
Blocking ref: singleton-reservation-portability
Decided by: human

## Question

Authorize one one-time validation waiver for unchanged sync-seed TEST-829/830 and the corresponding incomplete full-sweep verification outcome, preserving all FAIL and timeout evidence, then continue independent code review and PR; or leave phase B blocked without PR.

## Decision

The owner answered “1”, selecting the recommended waiver and continuation through code review and PR. No merge or release is authorized.

## Scope and evidence

This exception applies only to singleton-reservation-portability, RFC-0016 phase B. TEST-829/830 timed out at their original 180-second FIFO limits, including serial retests. TEST-829 also failed on clean main with identical suite and sync implementation bytes. Causation under an idle host remains unverified. The full framework ended at 126/127 boundaries with exit 124; 18 of the 20 originally interrupted sync-seed functions passed separately. All six sandbox-related suite failures have successful unrestricted retests, including the complete release suite. The scope-introduced registry disclosure issue was fixed and independently verified.

The original and round-two Validation reports remain immutable FAIL evidence. This exception does not assert a successful full sweep, modify global policy, waive code review, or extend to later RFC phases.

## Assumptions

The numbered answer refers to the immediately preceding two-option menu. No broader authorization is inferred.

## References

- docs/ai/reports/VALIDATION-singleton-reservation-portability.md
- docs/ai/reports/VALIDATION-r2-singleton-reservation-portability.md

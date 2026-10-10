---
id: classify-same-ts-pair
type: change
number: null
status: draft
links:
  pr: []
  commits: []
---

# classify can address one record of a same-timestamp amendment pair

## Summary

`spec-amend.mjs classify --ts <ts> --ref <ref>` addresses a spec_amendment
record by its (ts, ref_id) pair. When two records share that pair, classify
refuses the call as ambiguous, and `--class` does not help. An owner
signature therefore cannot be recorded on either record. Give classify an
exact, unambiguous way to address one record of such a pair, without
editing the append-only ledger. Then record the owner's existing signature
on the stuck record from PR #448.

## Motivation / Business Value

At the PR #448 merge checkpoint on 2026-10-10 the owner answered "Podepsat"
(sign) for every unsigned contract amendment of
spec-directed-merge-and-post-merge-cleanup. Two of the three records were
signed with classify.

The third record (ts 2026-10-10T11:35:07Z) shares its (ts, ref_id) pair
with a measurement record written by the same remediation run in the same
second. classify refused it as ambiguous. The orchestrator then:

- reopened the tracker `fu-amend-directed-merge-and-post-007bae`, so that
  `spec-amend list --strict` stays green;
- appended a new signed `add` record that carries the owner's decision.

The original record still reads as unsigned, and the ledger reports an
owner signature as still owed when it is not.

`spec-amend list` already notes that 36 spec_amendment records share a
(ts, ref_id) pair with an earlier one, so this is not a one-off.

## Scope

In scope:

- An exact addressing mode for `classify`. It must select one record when
  (ts, ref_id) matches more than one, for example:
  - by the record's own `amendment_class` when exactly one candidate has it;
  - or by a stable per-record key such as a content digest or line
    identity.
- The fold applies such an overlay to exactly that record. Overlays that
  are already on the ledger keep folding exactly as before.
- Cheap prevention of new same-second collisions in `add` and the other
  writers, if that is cheap. Example: `add` refuses or adjusts when the
  (ts, ref_id) it would write already exists.
- Using the new mode to sign the 2026-10-10T11:35:07Z contract record of
  directed-merge-and-post-merge-cleanup, citing the owner's existing answer.
  Then close `fu-amend-directed-merge-and-post-007bae` and
  `fu-classify-same-ts-pair`.

Out of scope:

- Rewriting or deduplicating existing ledger lines (HAZ-LEDGER: never edit
  in place).
- Re-classifying the other historical same-pair records. A later sweep can
  use the new mode.
- Changes to what a signature means or to who may sign.

## Acceptance Criteria

- AC-001: For a (ts, ref_id) pair matching two records with different
  `amendment_class`, classify can sign exactly the contract one. The
  measurement one stays unchanged in `list` output and the strict gate.
- AC-002: A pair matched by records the new mode still cannot tell apart
  stays refused with a named reason. classify never guesses.
- AC-003: Every overlay already on the ledger folds to the same `list`
  result before and after the change. This is proven against the live
  `docs/ai/decisions.jsonl`.
- AC-004: A new same-second collision from `add` is prevented or made
  addressable. The chosen behaviour is pinned by a test.
- AC-005: The #448 record (2026-10-10T11:35:07Z,
  directed-merge-and-post-merge-cleanup, contract) reads as signed, with the
  owner's 2026-10-10 "Podepsat" answer as its source. Both
  `fu-amend-directed-merge-and-post-007bae` and `fu-classify-same-ts-pair`
  are closed, and `spec-amend list --strict` exits 0.

## Verification

Use fixture ledgers with same-pair records for AC-001, AC-002 and AC-004,
plus the live ledger fold comparison for AC-003. Run the spec-amend and
follow-ups suites through the canonical test wrapper, with mutation
evidence that each new decision is load-bearing.

## Constraints / Risks

- `docs/ai/decisions.jsonl` is append-only. Every fix appends; nothing
  rewrites a line.
- The overlay addressing must not change the fold of any existing record.
  A silent re-fold would flip historical signature states.
- No secret is referenced; secrets preflight skipped.

## Notes

- Raised by the orchestrator at the PR #448 merge checkpoint, 2026-10-10.
  Follow-up `fu-classify-same-ts-pair` (P2).
- Owner direction 2026-10-10: "Já doporučujes" — fix this before the next
  release.
- Implementation mode: left to Planning (autopilot default, /aai-ship).

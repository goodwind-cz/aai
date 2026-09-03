---
id: unsigned-spec-amendment-has-no-outflow
number: null
type: change
status: draft
links:
  pr: []
  commits: []
---

# An unsigned post-freeze spec amendment must file a tracked item, not just a sentence

## Summary
- `.aai/system/AUTONOMOUS_LOOP.md` assigns scope changes to HITL: the owner
  "resolves disputed decisions, scope changes, and high-impact risk
  decisions". When an autonomous ride outgrows its frozen spec, the
  established practice is to amend additive-with-disclosure — a
  `## Amendment (post-freeze, ...)` section in the spec plus a
  `type: spec_amendment` record in `docs/ai/decisions.jsonl` — and to state
  plainly that no owner sign-off was obtained and that the owner may reverse
  it.
- That disclosure has no outflow. It lands in an append-only ledger no role
  is obliged to read, sets no `human_input`, files no follow-up, and enters
  no queue. Nothing surfaces it to the owner and nothing tracks whether the
  sign-off it defers was ever given.
- Consequence: a HITL gate is discharged by self-disclosure. Three such
  amendments now stand unsigned, and the owner has not exercised the
  reversal on any of them — which is indistinguishable from never having
  seen them.

## Motivation / Business Value
- The convention is sound; its termination is missing. Disclosure without a
  drainable artifact converts an owner decision into a notice, and a notice
  nobody is routed to is not a decision the owner made.
- Observed drift, flagged independently by the Validation and Code Review
  roles rather than by the rides that produced it:
  - `SPEC-0153` (2026-08-25), `SPEC-0161` (2026-09-02) and
    `spec-ac-table-premature-flip-recurs` (2026-09-02) all carry unsigned
    post-freeze amendments — the last two on consecutive rides.
  - The convention has begun citing `SPEC-0132` as precedent for proceeding
    unsigned, but that amendment is headed `(owner decision, ...)`. One
    genuinely signed amendment is being laundered into a chain of unsigned
    ones, which makes the practice look more established than it is.
- Each individual amendment was defensible and honestly disclosed. The
  defect is structural: the mechanism cannot distinguish "the owner saw this
  and accepted it" from "nobody ever read it".

## Scope
- In scope: making an unsigned post-freeze `spec_amendment` produce a
  tracked, drainable artifact — a follow-up registry entry, a `human_input`
  record, or an equivalent the orchestrator and the owner actually see —
  and a check that the artifact exists whenever such a record is written.
  Also in scope: correcting any prose that cites an owner-authorized
  amendment as precedent for an unsigned one.
- Out of scope: forbidding unsigned amendments outright (that would stall
  autonomous rides at exactly the moment a frozen spec proves incomplete,
  which is when the disclosure convention earns its keep); redesigning
  spec freezing; retroactively invalidating the three standing amendments —
  they should be surfaced for a decision, not reversed by default.

## Affected Area
- `.aai/system/AUTONOMOUS_LOOP.md` (the HITL clause that assigns scope
  changes to the owner).
- Whichever role prompts instruct the additive-with-disclosure amendment
  (Planning, Remediation, and the shared role canon).
- `docs/ai/decisions.jsonl` (`type: spec_amendment` records) and whichever
  mechanism is chosen to carry the tracked item (`follow-ups.mjs`,
  `state.mjs set-human-input`, or a docs-audit check).

## Desired Behavior (To-Be)
- Writing an unsigned `type: spec_amendment` record also creates a tracked
  item naming the spec, the amendment, and the sign-off still owed — so the
  owner has a list to drain rather than a ledger to search.
- A mechanical check can answer "which post-freeze amendments are still
  unsigned?" without reading prose.
- An amendment that DID carry owner authorization is recorded distinguishably
  from one that did not, so precedent chains cannot conflate them.
- Planning decides the mechanism; this intake does not prescribe it.

## Acceptance Criteria
- AC-001: An unsigned post-freeze `spec_amendment` cannot be recorded without
  a tracked item existing that names it and the sign-off it defers.
- AC-002: A single command answers which post-freeze amendments are still
  unsigned, from data rather than prose.
- AC-003: Owner-authorized and unsigned amendments are distinguishable in the
  ledger by a field, not by heading text.
- AC-004: The three standing unsigned amendments (`SPEC-0153`, `SPEC-0161`,
  `spec-ac-table-premature-flip-recurs`) are surfaced as tracked items for an
  owner decision, without being reversed by default.
- AC-005: Any canon prose citing `SPEC-0132` as precedent for proceeding
  without sign-off is corrected to reflect that it was an owner decision.

## Verification
- Command(s) and expected results:
  - Record an unsigned amendment on a fixture and confirm the tracked item is
    required/created; confirm the query in AC-002 lists it.
  - Record an owner-authorized amendment and confirm it is distinguishable
    from the unsigned shape by a field (AC-003).
  - Negative control: an ordinary decision record that is not a
    `spec_amendment` must be unaffected.
  - Confirm the three standing amendments appear in the AC-002 listing.

## Constraints / Risks
- `docs/ai/decisions.jsonl` is append-only (HAZ-LEDGER): the three existing
  records must NOT be edited in place. Distinguishing them, if needed, is
  done by appending, never by rewriting.
- The check must not become a hard block that strands an autonomous ride
  mid-remediation — the point is to make the sign-off drainable, not to make
  the disclosure path unusable. Weigh a fail-closed check against that.
- Do not let this become a fourth unsigned amendment: if implementing it
  outgrows its own frozen spec, that is the moment to stop and ask.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Raised by the Validation role (round 2, `ac-table-premature-flip-recurs`)
  and independently echoed by Code Review, then filed at the owner's
  direction. Verbatim framing from the validator: a HITL gate discharged
  three times running by self-disclosure is not a gate.
- Related: [[ac-table-premature-flip-recurs]], [[release-protected-branch-fallback]].

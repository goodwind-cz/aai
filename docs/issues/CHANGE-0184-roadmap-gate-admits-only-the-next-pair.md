---
id: roadmap-gate-admits-only-the-next-pair
type: change
number: 184
status: draft
blocks: standardized-backlog-drain
links:
  pr: []
  commits: []
---

# The roadmap gate admits only the first unfinished pair, so the owner's order is enforced, not decorative

## Summary
- `ride-select.mjs gate` admits ANY capability named on the roadmap
  (`pair.capability === ref` → admit) and any maintenance half whose
  capability has started. It never asks whether an earlier pair is still
  unfinished. `nextRide()` (the `next` subcommand) does compute "first
  unfinished pair, capability before maintenance", but the gate does not
  consult it.
- `orchestration-dispatch.mjs` rule 4a turns two or more admitted open
  intakes into `needs_llm: multiple_open_intakes`. With wave 2 on the roadmap,
  three refs are admitted at once (`harness-universal-routing`,
  `update-installs-ref-guard-undisclosed`, and
  `hand-authored-friction-is-second-class`, whose capability is done), so every
  post-close retarget stalls on a human — the exact ceremony unattended
  chaining exists to remove — and nothing stops a lower-ranked pair from
  being ridden before pair 1.
- Found by bot review on PR #375 (Codex P1, `docs/ai/roadmap.yaml:26`).

## Motivation / Business Value
- The roadmap's first rule is "rides are taken from here, top pair first".
  Today that order is prose; the gate enforces the 1:1 budget and the
  blocks relation, not the ranking. An unattended factory can only follow a
  ranking the gate enforces.
- `standardized-backlog-drain` cannot chain rides unattended while every
  retarget with more than one eligible intake stops for a human. This change
  blocks that capability, and rides ahead of it via the designed `blocks:`
  path.

## Scope
- In scope: the gate's admission predicate for on-roadmap refs (capability
  and maintenance halves); a clear refusal message naming the pair that is
  ahead; keeping `blocks:` admission and already-STARTED refs admitted so a
  ride in flight is never refused mid-flight; tests for each admission and
  refusal path; the dispatch rule-4a interaction (with sequential admission
  the multiple-open-intakes branch should become rare, not removed).
- Out of scope: changing the 1:1 budget, the `blocks:` semantics, the
  `--override` path (it stays logged and one-shot), or `nextRide()`'s own
  ordering rule (capability before maintenance unless started).

## Affected Area
- `.aai/scripts/ride-select.mjs` (`gate`, reuse of `nextRide`),
  `.aai/scripts/orchestration-dispatch.mjs` rule 4a (behaviour unchanged,
  a test proving the stall no longer occurs with the wave-2 roadmap), the
  ride-select suite, `docs/ai/roadmap.yaml` header comment documenting the
  rule.

## Desired Behavior (To-Be)
- The gate admits an on-roadmap ref only when it is a half of the FIRST pair
  that is not done, per `nextRide()`'s ordering; every other on-roadmap ref is
  refused with a message naming the ref that is ahead of it and the pair it
  belongs to.
- A ref whose doc is already `implementing` stays admitted regardless of
  position, so an in-flight ride is never refused by a roadmap edit.
- `blocks:` admission is unchanged: an off-roadmap ref that blocks a roadmap
  item is admitted whether or not that item is first.
- With the wave-2 roadmap and no ride in flight, rule 4a sees exactly one
  admitted candidate and retargets without a human.

## Acceptance Criteria
- AC-001: with a roadmap of three planned pairs and no docs started, `gate`
  admits pair 1's capability and refuses pair 2's and pair 3's capabilities,
  naming pair 1's capability in each refusal.
- AC-002: with pair 1's capability `implementing`, `gate` admits pair 1's
  maintenance and still admits the implementing capability; pair 2 stays
  refused.
- AC-003: with pair 1 done, `gate` admits pair 2's capability and refuses
  pair 3's.
- AC-004: a ref that is `implementing` and belongs to a pair that is NOT
  first is still admitted, with a reason naming it as in flight.
- AC-005: an off-roadmap ref carrying `blocks: <not-first roadmap ref>` is
  admitted exactly as today.
- AC-006: `orchestration-dispatch.mjs` rule 4a on a STATE fixture with the
  wave-2 roadmap and three open intakes dispatches a single retarget instead
  of `needs_llm: multiple_open_intakes`.
- AC-007: `--override` remains one-shot and logged; no new persistent
  override is introduced.

## Verification
- `bash tests/skills/test-aai-ride-select.sh` with new fixtures for AC-001
  to AC-005, each with a named mutation (for example deleting the
  first-unfinished check) that reddens it.
- A dispatch fixture for AC-006.
- `node .aai/scripts/ride-select.mjs validate` and `gate` against the live
  roadmap after the change: exactly one admitted planned capability.

## Constraints / Risks
- A stricter gate can refuse a ride the owner meant to run out of order; the
  remedy is the existing `--override "<reason>"`, which is logged, and the
  refusal message must say so.
- Sequential admission must not refuse a ride already in flight; AC-004 is the
  guard against that regression.
- No secret is referenced by this scope; secrets preflight skipped.

## Notes
- Source: Codex P1 on PR #375. The same PR that ranked wave 2 is the one on
  which the ranking was shown to be unenforced.
- Implementation mode (user choice): tdd — admission logic where a test that
  cannot fail would silently admit the wrong pair.

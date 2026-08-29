---
id: operator-waiver-unblocks-pr
type: change
number: 167
status: draft
ceremony_level: 1
---

# An operator who validated the change themselves can reach a PR without lying

Ceremony justification: single surface (the aai-pr precondition and its
report), no change to the state engine, no new enum, no gate weakened for
anything that does not carry an explicit waiver record. The heavy half of this
problem — a first-class `waived` verdict in `state.mjs` — touches a protected
L3 surface and is deliberately left to a successor so the operator is not
blocked on it.

## The blocker, measured

`aai-pr` refuses unless `last_validation.status` is `pass`
(.aai/SKILL_PR.prompt.md:21), and `state.mjs` accepts only
`pass | fail | not_run` for that field (VALIDATION_STATUSES,
.aai/scripts/state.mjs:138). There is no value meaning "a human looked at this
and consciously took the risk".

So an operator who does not want to buy a validation round has two routes to a
PR: pay for it anyway, or record `pass` for a validation that never ran. The
factory is asking them to lie, and afterwards its own ledger cannot tell that
record apart from an honest one.

The asymmetry is the tell: `code_review.status` already accepts `waived`
(VALIDATION's sibling enum at .aai/scripts/state.mjs:139) and `aai-pr` already
honours it (.aai/SKILL_PR.prompt.md:22). Validation never got the same exit.

## Owner decisions (2026-08-28, recorded before work started)

1. The record says what happened: waived by operator, never "review performed
   by human". A waiver dressed as a pass makes the factory's quality numbers
   quietly untrue. It is meant to appear in the report as an admitted hole.
2. An agent MAY issue one, but it is recorded distinctly as self-waived and
   shown separately. A gate an agent can silently clear for itself is not a
   gate.
3. Split accepted: this L1 ride unblocks the route today; the L3 successor
   makes it first-class in the state engine, with the operator's sign-off.

## Scope

- A waiver is recorded in fields `state.mjs` ALREADY accepts, with no engine
  change: `last_validation.status` stays `not_run` — which is true, nothing
  ran — and the waiver itself is a structured `--notes` record naming who
  waived, when, and why. The status keeps saying what happened; the note says
  what was decided about it. That is strictly more honest than a `pass`.
- `aai-pr` accepts `not_run` PLUS a well-formed waiver record, and nothing
  else. A bare `not_run` still blocks exactly as today.
- A missing or empty reason is not a waiver. Unaccountable is worse than none.
- Who waived is recorded explicitly, never inferred from the environment:
  `AAI_ROLE` was measured UNSET live in this repo despite a dispatch mandating
  it, so it cannot carry this weight.
- The factory report surfaces waived rides, self-waived ones separately.

## Out of scope

Adding a `waived` value to `VALIDATION_STATUSES` (protected L3 surface — the
successor's job). Changing what validation costs. Making any gate advisory.
Nothing here lowers a bar; it adds a named, attributable exit and makes the
exit visible.

## Test Plan

Every row names a directly executable command (required at L1).

- TEST-01: `bash tests/skills/test-aai-pr-waiver.sh 01` — bare `not_run` with
  no waiver record still blocks the PR precondition.
- TEST-02: `bash tests/skills/test-aai-pr-waiver.sh 02` — `not_run` plus a
  well-formed operator waiver satisfies it.
- TEST-03: `bash tests/skills/test-aai-pr-waiver.sh 03` — a waiver with an
  empty or missing reason is refused, not silently accepted.
- TEST-04: `bash tests/skills/test-aai-pr-waiver.sh 04` — a self-waived
  (agent) record is accepted but marked distinctly from an operator waiver.
- TEST-05: `bash tests/skills/test-aai-factory-report.sh` — waived rides
  appear in the report, self-waived ones counted separately.

## Source

Downstream operator report, 2026-08-28 (Codex agent, Windows sandbox).
Registry: fu-no-route-from-intake-to-pr, fu-review-cost-not-operator-gated.

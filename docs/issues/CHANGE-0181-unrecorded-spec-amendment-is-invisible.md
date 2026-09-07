---
id: unrecorded-spec-amendment-is-invisible
number: 181
type: change
status: draft
links:
  pr: []
  commits: []
---

# An amendment nobody recorded is invisible to the gate that exists to catch it

## Summary
- `spec-amend list --strict` is the gate that refuses an untracked or
  unclassified post-freeze amendment. It reads `docs/ai/decisions.jsonl` and
  judges the `spec_amendment` records it finds there.
- A spec amended WITHOUT calling `spec-amend add` produces no record, so the
  gate finds nothing to judge and exits 0. The stricter the amendment, the
  quieter the gate: an author who skips the writer entirely is never refused,
  while an author who uses it honestly and leaves the sign-off open is.

## Motivation / Business Value
- Observed 2026-09-06 on the ride `live-page-shows-dead-heartbeats-not-live-work`.
  Its frozen SPEC-0171 was amended during implementation — Spec-AC-01 through
  Spec-AC-03 were rewritten from a pid-liveness probe to an age-based hide
  window, and the AC cells say so in prose ("Amendment 2 — freshness, not a pid
  probe"). No `spec_amendment` record was ever written.
  `node .aai/scripts/spec-amend.mjs list --strict` exited 0 on that state, and
  `list --status all` had no row for the ref at all. The amendment reached
  `main` in PR #351 with the gate green throughout.
- The sign-off was only recovered because a human was told about the amendment
  in conversation and asked for it. Nothing in the pipeline would have raised it.
- This is the failure mode the operator contract's rule 5 names: a rule that
  must hold wherever AAI is installed is a guard, not a note. Here the guard
  exists but its precondition — that the writer was called — is itself only a
  note.

## Scope
- In scope: closing the gap between "a frozen spec changed" and "a
  `spec_amendment` record exists", so the gate judges the former rather than
  the latter. The mechanism is deliberately left open for Planning: candidates
  include comparing a frozen spec's content hash at close against the hash at
  freeze, or having the close gate diff SPEC-FROZEN documents against their
  freeze state, or a pre-commit check on any edit to a `status: implementing`
  spec.
- Out of scope: changing what a signed amendment means, the sign-off authority
  (it stays the owner's), the shape of the ledger record, and back-filling the
  20 historical unsigned-tracked amendments already in the registry.

## Affected Area
- `.aai/scripts/spec-amend.mjs` (`list --strict`), `.aai/scripts/spec-freeze.mjs`
  (which owns the freeze marker a detector would anchor to), the close/PR gate
  that runs the strict list, and their suites.

## Desired Behavior (To-Be)
- A frozen spec whose body changed after freeze without a corresponding
  `spec_amendment` record fails the gate, naming the spec and what changed.
- An honest author is never worse off than one who skipped the writer.

## Acceptance Criteria
- AC-001: Given a spec frozen by `spec-freeze.mjs` and subsequently edited with
  no `spec_amendment` record appended, the strict gate exits non-zero and names
  that spec.
- AC-002: The refusal prints a runnable remediation — the `spec-amend add` line
  that clears it — and that printed line, run verbatim, does clear it.
- AC-003: A frozen spec edited WITH a matching record still passes, whether the
  record is signed or unsigned-tracked, so the change adds no new pressure to
  sign.
- AC-004: Editing a spec that is not frozen, or a non-spec document, changes
  nothing.
- AC-005: The 20 pre-existing unsigned-tracked amendments and any legacy frozen
  spec whose freeze-time state cannot be reconstructed do not turn the gate red
  retroactively; the degrade is named in output rather than silent.

## Verification
- The `spec-amend` suite green, including a new arm that freezes a fixture spec,
  edits it without a record, and asserts the non-zero exit and the named spec.
- A mutation arm: removing the new detection turns that arm red.
- `node .aai/scripts/spec-amend.mjs list --strict` against the live repository
  exits 0 (no retroactive red) or names exactly what it degrades.

## Constraints / Risks
- `docs/ai/decisions.jsonl` is append-only (HAZ-LEDGER); nothing here may edit
  an existing record.
- Anchoring on content requires a freeze-time reference that survives a rebase
  and a squash merge. A naive "diff against the freeze commit" breaks on both.
  This is the hard part of the scope and Planning should treat it as the seam.
- No secret is referenced by this scope.
- Roadmap: off-roadmap maintenance. It needs an owner decision to be added to
  `docs/ai/roadmap.yaml` or an explicit `--override` at ride time.

## Notes
- Sibling intake from the same session: shared-worktree-moves-another-agents-head.

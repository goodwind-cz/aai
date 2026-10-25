---
id: implied-signing-without-links-pr
type: change
number: 229
status: done
user_visible: false
links:
  pr: []
  commits: []
---

# A directed merge signs the ride's amendments even when the ride closed before its PR existed

## Summary

SPEC-0226 (DEBT-0013) made a merge sign a ride's contract amendments at read
time: `spec-amend.mjs` reads an unsigned contract amendment as signed when its
ride doc is `done`, merged into the base branch and carries a PR number in
`links.pr`. The canonical `/aai-pr` flow runs `close-work-item.mjs` before
`gh pr create`, so `links.pr` stays empty (`closed ... (pr #null)`) and nothing
fills it after the merge. Every directed merge therefore leaves its contract
amendments unsigned: 6 records after PR #501, 4 after PR #502.

## Motivation / Business Value

The owner's merge direction is the sign-off the canon promises
(`.aai/system/AUTONOMOUS_LOOP.md`). Today each merge leaves an unsigned backlog
that the next ride has to sign by hand, and `spec-amend list` shows open
`fu-amend-*` trackers for work the owner already approved.

## Scope

In scope:

- Planning measures which merged rides carry an empty `links.pr`, and picks one
  seam so the implied signature holds for a ride closed before its PR. Candidate
  seams: the implied-signature check resolves the PR from the squash merge
  commit on the base branch; `merge-cleanup.mjs apply` records `links.pr` after
  the merge; `close-work-item.mjs` backfills it. The chosen seam is described by
  what it compares.
- Signing the 4 unsigned contract amendments of
  `provider-adapter-registry-slice` (SPEC-0253) from the owner's recorded merge
  direction for PR #502 ("Mergni #502 (Recommended)", merged 2026-10-25 as
  72a8c2ea, head 8ce9e708), and closing their tracker
  `fu-amend-provider-adapter-registry-slice`.

Out of scope:

- Changing when `close-work-item.mjs` runs in the `/aai-pr` flow.
- Signing anything for an unmerged ride, or for a merge without a recorded owner
  direction beyond what SPEC-0226 already covers.

## Affected Area

`.aai/scripts/spec-amend.mjs` or `.aai/scripts/merge-cleanup.mjs` (whichever
seam Planning picks), its tests, `docs/ai/decisions.jsonl`.

## Desired Behavior (To-Be)

After a directed merge of a ride whose close ran before `gh pr create`,
`spec-amend list` reads that ride's contract amendments as signed with no hand
step, and `--strict` stays at exit 0. A ride that is not merged stays unsigned.

## Acceptance Criteria

- AC-001: A merged ride whose doc is `done` but whose `links.pr` is empty has
  its contract amendments read as signed, by the seam Planning chose; the
  description says exactly what the seam compares.
- AC-002: An unmerged ride, or a ride whose merge cannot be proven on the base
  branch, stays unsigned.
- AC-003: Replays of the real PR #501 and PR #502 histories: their records read
  signed through the new seam without the hand-written overlays (measured on a
  copy of the ledger with those overlays removed).
- AC-004: The 4 SPEC-0253 records are signed by one `hitl_decision` carrying
  the owner's words "Mergni #502 (Recommended)" and one
  `spec-amend classify --record <key> --signoff owner` per record; the tracker
  reads done; `spec-amend list --strict` exits 0.

## Verification

- New or extended suite rows for AC-001..003, red before the change.
- `spec-amend list --strict` exit 0 after the signatures.

## Constraints / Risks

- Node stdlib only. The signature must never be implied for a ride that is not
  provably merged (a false signature is worse than a missing one).
- Secrets preflight: no secret referenced.

## Notes

- Owner decision 2026-10-25: "Oprava podpisu + #502 (Recommended)".
- Assumption (autopilot): if the seam is ambiguous Planning picks the one with
  the fewest moving parts and records the choice in the spec.

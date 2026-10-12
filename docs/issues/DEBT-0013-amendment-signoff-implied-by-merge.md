---
id: amendment-signoff-implied-by-merge
type: techdebt
number: 13
status: done
links:
  pr:
    - 460
  commits:
    - 5479a818
---

# Tech Debt: a contract amendment is signed by the merge of its ride, not by a written record

## Debt Summary
- Every contract amendment needs the following: a `spec_amendment` record, a
  `fu-amend-*` tracker, the `/aai-pr` `spec-amend list --strict` gate, the
  "signs on merge" preflight lines, one `spec_amendment_classification` overlay
  per record written by `merge-cleanup` sign-amendments after the merge, and
  a tracker close.
- The overlays are written into the main checkout after the merge. Protected
  `main` cannot take them, so every `/aai-merge` leaves `decisions.jsonl`
  dirty. PR #456 left 9 lines; the stopgap was PR #458.

## Root Cause
- SPEC-0220 made the owner's `/aai-merge` direction sign the ride's
  amendments, but kept it as a write of per-record overlays. The signature is
  already fully determined by facts in git: the ride doc is `done` and its PR
  is merged.

## Current Cost / Risk
- October so far: 229 amendments, about 8 per ride (105 contract, 101
  measurement, 23 unclassed). There are 353 classification records.
- About 330 lines in merge-cleanup (`sign-amendments`, `sign-merged`,
  `preflightSigns`). SPEC-0219 exists only to address overlays of
  same-timestamp record pairs. An estimated 40% of `spec-amend.mjs` is
  overlay and tracker bookkeeping; that figure is not measured per function.
- Signatures that are not committed are invisible to new rides and lost by a
  `git restore`.

## Target State
- `spec-amend` folds a contract amendment as signed at read time when its
  ride's doc is `done` and the ride's PR is merged into the base: links.pr
  plus a first-parent commit naming it, the same predicate `sign-merged`
  uses today.
- Nothing is written after the merge. Unmerged rides still list their
  unsigned contract amendments, so the PR gate keeps its meaning.
- Existing overlays stay valid. No history is rewritten.

## Scope
- In scope: `.aai/scripts/spec-amend.mjs` fold/list, `merge-cleanup.mjs`
  (delete sign-amendments, sign-merged, preflightSigns and the
  directed_merge pre-merge write if nothing else needs it), the `fu-amend-*`
  tracker lifecycle for merged rides, `SKILL_MERGE` and `SKILL_PR` text,
  and the related tests.
- Out of scope: how amendments are recorded during a ride; measurement-class
  amendments, which already ask nobody (SPEC-0205).

## Plan / Migration
- Add the implied-signature fold, and prove that `list --strict` on the live
  ledger is unchanged for every already-signed record.
- Delete the writers and the trackers they closed.
- Rollback: the fold is additive. Reverting it restores the old behavior,
  because the overlays are still read.

## Verification
- `spec-amend list --strict` passes on a fresh clone of origin/main right
  after a ride's merge, with no post-merge writes.
- A ride that is not merged still fails the PR gate on an unsigned contract
  amendment (positive control).
- `/aai-merge` leaves `git status` of the main checkout unchanged in
  `decisions.jsonl`.

## Constraints / Risks
- A lane or standing merge would also count as a signature. If that is
  unwanted, restrict the fold to a merge of the PR by a human, or to a PR
  body that carries a "Signs on merge" line. Decide this in Planning.
- `spec-amend.mjs` and the close machinery may sit under hash pins and the
  L3 classification. Check before freezing.

## Notes
- Owner direction 2026-10-12: "2 Implicitní podpis". Replaces the draft
  merge-signatures-committed-before-merge (deleted unfiled).

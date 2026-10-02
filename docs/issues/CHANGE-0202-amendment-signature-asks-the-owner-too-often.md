---
id: amendment-signature-asks-the-owner-too-often
type: change
number: 202
status: done
links:
  pr:
    - TBD
  commits:
    - 3c6a7056
---

# Change — the amendment signature asks the owner too often

## Summary
- Every post-freeze change to a frozen spec currently creates an owner
  obligation, whatever the change was. Measured on `main` at `1ffc03de`:
  **218 amendment records, 28 signed, 190 unsigned** — 13%. The oldest
  unsigned record has waited since **2026-09-04**, roughly four weeks.
- The backlog is not the defect. The defect is that most of those 190 should
  never have asked. A correction to **how a claim is measured** — a mutation
  cell that did not redden, a renumbered Test Plan id, an allocator restamp —
  is the author fixing their own instrument. A change to **what the spec
  promises** — an AC predicate, its scope, an AC added or removed — is a
  scope decision and belongs to the owner.
- Today both are one bucket, so the second is hidden inside the first.

## Motivation

The disclosure half of this mechanism works, and it earns its keep. In the
ride that closed as `ISSUE-0092` / `SPEC-0204` on 2026-10-01, **nine of the
eleven frozen mutation cells actually exercised turned out to be unusable** —
one left the target byte-identical, one matched a second occurrence, one used
delimiters the parser cannot read, one was a semantic no-op, one matched an
unrelated stanza, and one would have killed the program with a
`ReferenceError`, reddening everything and certifying nothing. Each
correction was disclosed. Without the mechanism they would have been silent
edits to a frozen document, and the spec would have read as though it had
always said that.

The signature half does not work, and it fails in a way this project has a
name for. Disclosure is enforced: `spec-amend list --strict` refuses, and the
tools will not proceed without it. The signature depends on a human with no
forcing function at all — `list --strict` treats `unsigned-tracked` as
acceptable, CI never reads it, and nothing downstream consumes
`bucket: 'signed'` except `spec-amend`'s own listing. So 190 items carry the
label *"owner sign-off owed"*, which asserts a review that is not happening.

That is the same defect class `SPEC-0204` was written to remove — a control
that asserts more than it proves — one level up, in the process rather than
in the code.

## Scope

- In scope:
  - A **decidable** partition between an amendment that changes what a spec
    promises and one that changes only how it is measured, and the rule that
    only the first creates an owner obligation.
  - The writer declaring the class at `add` / `classify` time.
  - Migration of the existing 190 unsigned records to the new partition,
    without silently reclassifying anything as signed.
  - Whatever `list`, `--strict` and the `fu-amend-*` co-creation need so the
    two classes have different outflows.
- Out of scope:
  - Making the signature block a merge. Considered and rejected for now: it
    would turn the existing 190 into a wall before the partition exists to
    shrink them.
  - Retiring the signature altogether.
  - Signing any of the current backlog as part of this ride.
  - Reworking the mutation-gate defect that produced many of these
    amendments — that is `fu-frozen-mutation-cells-unusable`, a separate
    P2 item, and this ride must not absorb it.

## Proposed Behaviour

- An amendment records its **class** as a structured field supplied by the
  writer, not inferred afterwards from prose.
- A measurement-class amendment is disclosed exactly as today (the record,
  the re-stamped anchor, `list` still counts it) but creates **no** owner
  obligation and no `fu-amend-*` item.
- A contract-class amendment behaves exactly as today, including the tracked
  item and the owner signature.
- `list --strict` keeps refusing an undisclosed post-freeze edit. Its
  violation buckets do not change.

## Constraints / Risks

- **The classifier must not read prose.** `nothing-left-behind.mjs` already
  learned this and says so in its own source: Class 4 membership "is decided
  by the follow-up's `id` prefix, never by the prose in `finding`", because
  the old six-word text match counted any item that *mentioned* the ceremony
  rather than any item that *was* about it. The overview built for this
  decision made the same mistake deliberately and said so — it classified 190
  records with regexes over `what` and reported 132 as "needs reading" while
  stating that the number is an upper bound, not a verdict. A regex is fine
  for a reading aid and is not fine for a gate.
- **The writer declaring its own class is a self-report.** That is the
  honest hazard of this design and must be stated, not designed around in
  silence: an author who wants no owner obligation can claim the measurement
  class. The mitigation is that the class is visible in the record and in
  `list`, so a wrong claim is auditable after the fact rather than invisible.
  Decide explicitly whether anything beyond visibility is warranted.
- **Migration must not launder.** Moving an existing record out of the owner
  queue is itself a decision about that record. Deciding in bulk which of the
  190 "must have been" measurement-class is exactly the laundering
  `spec-amend` was built to stop — its own source says deciding which bucket
  an old record belongs in is "the laundering this tool exists to stop".
  Whatever the migration does, it cannot read the old prose and guess.
- One `(ts, ref_id)` pair in the ledger is duplicated, and `classify` refuses
  such a pair as ambiguous. That record cannot be migrated by `classify`
  without being disambiguated first.
- Changing a shipped gate's vocabulary is the standing hazard class (a guard
  that newly reddens or newly permits existing work); expect one extra
  validation round.
- Secrets preflight: skipped — no secret referenced.

## Verification
- `node .aai/scripts/spec-amend.mjs list --strict` still exits non-zero on an
  undisclosed post-freeze edit and zero otherwise.
- A measurement-class amendment creates no `fu-amend-*` item; a
  contract-class one still does.
- The 190 existing records are accounted for by the migration with no record
  moved to `signed` that an owner did not sign.
- `tests/skills/test-aai-spec-amend.sh` and the suites that read the
  follow-up registry green; full sweep before close.

## Notes
- Owner decision 2026-10-02, from a menu of four: narrow what the signature
  requires (chosen), keep as-is and sign down the backlog, make the signature
  block merges, or drop the signature. The three rejected options are
  recorded here so a later reader does not re-propose them as new.
- Source measurements, all against `main` at `1ffc03de`:
  `spec-amend list --status signed|unsigned|unclassified|all` →
  28 / 190 / 0 / 218; unsigned span 2026-09-04 .. 2026-10-01; 31 distinct
  specs; 6 of them carry no record that even a prose classifier calls
  contract-changing.
- The reading aid built for the decision is an artifact, not a repository
  document, and is not evidence for this ride; re-measure from the ledger.

---
id: amendment-class-migration-correction
type: report
status: done
---

# Report — the amendment-class migration, re-verified and shrunk

Spec: `docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md`
(D3 as corrected, Spec-AC-19, TEST-1375). This report supersedes the cohort
claim in `docs/ai/reports/amendment-class-migration-20261002T081152Z.md`; that
report's own measurements stand, its *selector* does not.

## Why the first migration was wrong

The 25 records were moved into the obligation-free `measurement` bucket because
each carries `from_frozen_sha256`/`to_frozen_sha256` and a `what` byte-equal to
`RESTAMP_WHAT`. The reasoning was that only `cmdRestamp` writes that shape.

That is true and it proves nothing. The Spec-AC-18 remediation in this same
ride established why: the OLD `cmdRestamp` wrote that exact literal and those
exact fields after ANY post-freeze edit, because it never verified its cause —
`computeSpecRestamp` asks only whether the contract hash MOVED. The shape is
therefore evidence that `restamp` ran, never evidence of what moved the bytes.
The migration discharged 25 obligations on a selector this ride itself proved
is not probative.

## What was re-verified, and how

For each of the 26 restamp-shaped records on `docs/ai/decisions.jsonl`:

1. find, across every blob in the git object store (`git cat-file
   --batch-all-objects`, not a path- or history-filtered walk — the allocator's
   merge rewrite and later renames both move specs between paths), the spec
   content the restamp actually saw: the blob whose contract projection hashes
   to the record's `to_frozen_sha256` under
   `.aai/scripts/lib/spec-contract-hash.mjs`;
2. run the SAME reversal `verifyAllocatorCause` implements over that content —
   candidates are the spec's own `<PREFIX>-<NNNN>-<frontmatter id>`
   self-reference plus every numbered governed-doc basename in its
   frontmatter, every non-empty subset reversed to its `-DRAFT-` form, capped
   at 8 — and compare `contractHash` of the result against the record's
   `from_frozen_sha256`;
3. a byte-exact match is a proof; everything else is not.

Where only the post-restamp blob survived (the restamp rewrites the anchor
line and nothing else), the pre-restamp content was reconstructed by restoring
the old anchor into that blob's frontmatter. That is sound: the frontmatter is
stripped before hashing, so the reconstruction and the restamp-time content
have the SAME contract projection by construction, and the proof is taken
through `contractHash` alone.

## Outcome

| | records |
|---|---|
| restamp-shaped records on the ledger | 26 |
| allocator cause reproduced byte-exactly | 13 |
| allocator cause NOT reproducible | 13 |
| of the proven 13, written by the fixed `restamp` (never migrated) | 1 |
| migrated cohort as it stands after this correction | 12 |
| corrective overlays appended, back to the contract lane | 13 |

The 13 that could not be proven split three ways:

- **5 — no measurable bytes.** No blob in the object store hashes to the
  record's `to_frozen_sha256`, so the content the restamp saw was never
  committed and cannot be re-measured at all. (Two of these are the first half
  of a two-restamp chain whose second half IS provable.)
- **5 — the reversal does not reproduce the anchor.** The drift is not
  allocator-shaped, or not only allocator-shaped. One is decisive and is worth
  naming: `2026-09-24T11:07:42Z / spec-update-installs-ref-guard-undisclosed`,
  whose projection diff is a rewrite of the spec's own `## Verification`
  command list (a remediation note added and `bash` inserted into six
  commands). A human prose edit, recorded by the old writer as "the allocator
  rewrote this frozen spec's own SPEC-DRAFT- path(s) at merge", and then
  discharged by the migration. That is the laundering this ride promised not
  to do, committed by this ride, and it is now reversed.
- **3 — genuinely allocator-caused, not reachable by the rule.** These are the
  two shapes the spec's own residual risk R5 predicted. Two records
  (`routing-tables-have-an-owner-and-a-seam`) drift only by a
  `CHANGE-DRAFT-routing-tables-…` → `CHANGE-0192-routing-tables-…` rewrite the
  candidate set cannot reach, because the spec's frontmatter does not name that
  document and its own `id` is a different slug. One
  (`spec-shipped-guards-have-no-downstream-trigger`) drifts by a rename whose
  numbered slug differs from the DRAFT slug (`SPEC-DRAFT-shipped-guards-…` →
  `SPEC-0201-spec-shipped-guards-…`), which the unsuffixed-DRAFT reconstruction
  cannot invert. R5 says both fail CLOSED, and they do. They go back to the
  contract lane anyway: unprovable is unprovable, and "it looks mechanical" is
  the standard this correction exists to retire.

## Before / after on the live ledger

```
BEFORE  total=226 signed=28 measurement=28 unsigned-tracked=170 unsigned-untracked=0 unclassified=0
AFTER   total=226 signed=28 measurement=15 unsigned-tracked=183 unsigned-untracked=0 unclassified=0
```

`signed` is unchanged; nothing was laundered upward. `total` is unchanged; the
correction is 13 appended `spec_amendment_classification` overlays and not one
edited line (HAZ-LEDGER — the pre-correction 1063208 bytes are byte-identical
as a prefix of the file). No `fu-amend-` item changed status and none was
created: all 13 records already carried an OPEN tracker, which the corrective
overlay reuses, so the obligation each one really owes is visible in
`follow-ups.mjs list --status open` again.

The 15 `measurement` records that remain are the 12 proven migrated records
plus the 3 this ride's own fixed writers emitted with their cause verified at
write time.

## What this does NOT claim

Unprovable does not mean "a contract change". It means nothing on the record or
in the bytes discharges the obligation, so the obligation stands. Three of the
13 are very probably mechanical; the point of the contract lane is that
"probably" is not a signature.

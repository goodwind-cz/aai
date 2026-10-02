---
id: amendment-class-migration
type: report
status: done
---

# Report — the amendment-class migration on the live ledger

Spec: `docs/specs/SPEC-DRAFT-spec-amendment-signature-asks-the-owner-too-often.md`
(D3, Spec-AC-15, TEST-1370). Spec-AC-15 is a claim about `docs/ai/decisions.jsonl`
itself and cannot be proven by a fixture, so the before/after measurement is
recorded here as the spec's Evidence contract requires.

## What was run

The cohort was selected STRUCTURALLY from the tool's own fold — never from a
regex over the ledger and never from prose. A record qualifies iff
`tool_restamp` is true (it carries BOTH `from_frozen_sha256` and
`to_frozen_sha256`, which only `cmdRestamp` writes, AND its `what` is
byte-equal to `RESTAMP_WHAT`, hoisted in this scope out of `cmdRestamp`'s
inline literal so selector and writer cannot disagree) and it is neither
already `signed` nor already `measurement`.

```
node .aai/scripts/spec-amend.mjs list --json > before.json
# cohort = items where tool_restamp === true && bucket !== "signed" && amendment_class !== "measurement"
while IFS=$'\t' read -r ts ref; do
  node .aai/scripts/spec-amend.mjs classify --ts "$ts" --ref "$ref" \
    --signoff none --class measurement --origin backfill \
    --why "<the per-record reason recorded on each overlay>" \
    --source "<the spec D3 selector, with the run-time measurement>"
done < cohort.tsv
node .aai/scripts/spec-amend.mjs list --json > after.json
```

## Measured at run time, never hardcoded

- cohort size: **25** records, over **18** distinct specs
- every one `owner_signoff: false`, every one in bucket `unsigned-tracked`
- **0** already carried a classification overlay, so none was re-decided
- **0** cohort pairs are ambiguous `(ts, ref_id)` ledger-wide, so every one was
  reachable by `classify` (the one duplicated pair the intake warns about,
  `2026-09-14T00:31:29Z` / `test-framework-sweep`, is not in the cohort)
- overlays appended: **25**; lines modified: **0**

## Counts

```
BEFORE: shown=220 total=220 signed=28 measurement=0  unsigned-tracked=192 unsigned-untracked=0 unclassified=0
AFTER : shown=220 total=220 signed=28 measurement=25 unsigned-tracked=167 unsigned-untracked=0 unclassified=0
```

Every Spec-AC-15 clause, checked mechanically:

| Claim | Result |
|-------|--------|
| `signed` unchanged at its pre-migration count | PASS (28 -> 28) |
| `measurement` equals the number of appended overlays | PASS (25 == 25) |
| `unsigned-tracked` falls by exactly that number | PASS (192 -> 167) |
| `unsigned-untracked` and `unclassified` are both 0 | PASS |
| total record count unchanged | PASS (220 -> 220) |
| no pre-existing line modified (HAZ-LEDGER, append-only) | PASS — every pre-existing byte is byte-identical at the same offset |
| no `fu-amend-` item changed status, and none was created | PASS — the whole registry projects identically before and after |
| nothing laundered to `signed` | PASS — 0 cohort records reached `signed` |

## The legacy cohort still reads CONTRACT

The ~165 non-restamp unsigned records are NOT migrated, by design. Proven by
folding the live ledger through the pre-change code (`main` at `1ffc03de`) and
the new code and comparing every record's bucket:

```
records compared: 220
NON-COHORT records that changed bucket (moved): 0
cohort records that changed bucket (intended):  25
```

`moved = 0`. The reader default for a class-absent record is the contract
lane, which is the no-change reading: it discharges nothing and is therefore
not a verdict about any record.

## Deliberately NOT done

- Nothing moved to `signed`. The measurement lane can reduce an obligation to
  disclosure; it can never mint a signature.
- No `fu-amend-*` tracker was closed. The item is keyed per SPEC, not per
  record, so closing one would forge a signature the owner never gave — five
  trackers now have every backing record in the measurement lane and are left
  OPEN for the owner.
- The remaining 167 unsigned-tracked records stay a closed legacy cohort,
  drained one at a time by `classify` or signed, or neither. This ride ran
  none of those.

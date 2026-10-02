---
id: spec-amendment-signature-asks-the-owner-too-often
type: spec
number: 205
status: done
mutation_gate: v1
frozen_sha256: e0e5bdcd76d1c1ba788aee26d60115d2a710194961be5dac46375121f6a248d2
ceremony_level: 2
links:
  requirement: null
  rfc: null
  intake: docs/issues/CHANGE-0202-amendment-signature-asks-the-owner-too-often.md
  pr:
    - 422
  commits:
    - 3c6a7056
---

# Spec — the amendment signature asks the owner too often

SPEC-FROZEN: true

## Links
- Intake: docs/issues/CHANGE-0202-amendment-signature-asks-the-owner-too-often.md
- Prior art: docs/specs/SPEC-0165-spec-unsigned-spec-amendment-has-no-outflow.md (the writer and the gate), docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md (D11 the anchor scan, D2 `restamp`)
- Convention body: `.aai/system/AUTONOMOUS_LOOP.md` section 6a
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero network, no LLM)

## Problem

`spec-amend.mjs` folds every post-freeze amendment into one obligation: an
owner signature. Re-measured on this worktree's base, `main` at `1ffc03de`,
with the tool itself (`list --status signed|unsigned|unclassified|all`):

- `total=218 signed=28 unsigned-tracked=190 unsigned-untracked=0 unclassified=0`
- unsigned span `2026-09-04T06:54:58Z` .. `2026-10-01T22:04:09Z`, 31 distinct
  specs, 33 distinct `fu-amend-*` trackers, 32 of them open.
- `node .aai/scripts/spec-amend.mjs list --strict` exits **0** today. The
  backlog is not a refusal and nothing downstream reads it:
  `nothing-left-behind.mjs` excludes `fu-amend-*` structurally
  (`CEREMONY_FOLLOW_UP_ID_PREFIXES` at line 108 does not contain the prefix).
  So 190 records carry the label "owner sign-off owed" and no mechanism
  anywhere acts on it.

Two populations are inside that one bucket:

- a change to **what the spec promises** — an AC predicate, its scope, an AC
  added or removed — which is a scope decision and belongs to the owner;
- a change to **how a claim is measured** — a mutation cell that did not
  redden, a renumbered TEST id, an allocator restamp — which is the author
  fixing their own instrument.

The second population is not hypothetical and part of it is machine-emitted.
**25 of the 218 records carry `from_frozen_sha256` and `to_frozen_sha256`**,
which only `cmdRestamp` writes, and **all 25 carry one byte-identical `what`
and one byte-identical `why`** — the two string literals hardcoded in
`cmdRestamp`. The tool itself manufactures an owner obligation for a change
whose mechanical nature it already knows, 25 times, across 18 specs; for 5 of
those specs every unsigned amendment on the ledger is one of these.

## Scope

In scope:
- A declared, closed-vocabulary **amendment class** (`contract` or
  `measurement`) on the amendment record, supplied by the writer, never
  inferred from prose.
- A fifth fold bucket, `measurement`, that is disclosed and counted but owes
  no owner signature and no `fu-amend-*` item.
- `restamp` declaring itself `measurement` by construction.
- `list` surfacing the class, and a one-time, structurally-selected migration
  of the tool-emitted restamp cohort.

Out of scope (each named in the intake):
- Making the signature block a merge; retiring the signature; signing any of
  the current backlog.
- `fu-frozen-mutation-cells-unusable` (open P2, ref
  `a-check-cannot-tell-silence-from-a-verdict`) — the defect that produced many
  of these amendments. This ride must not absorb it.
- Bulk reclassification of the ~165 non-restamp unsigned records. See
  "The migration refuses to guess" below.

## The four decisions this spec settles

### D1 — Where the class is declared, and its legal values

`amendment_class` is a **top-level key on the `spec_amendment` record**, with a
closed vocabulary of exactly two values: `contract` and `measurement`. Measured:
no record on the live ledger carries any key matching `/class/i` today, so the
key is free.

It is declared at `add` time by the writer, at `classify` time as an overlay,
and by `restamp` as a hardcoded constant. It is **not** required at `add`:
`--class` is optional, defaults to `contract`, and `add` STAMPS the resolved
value on the record explicitly so a record written by either live writer is
never class-absent. A `--class`-less `add` prints a NOTE naming the other
value.

Why optional rather than required. `add` is the mid-ride, fail-OPEN writer
("its only non-zero exits are usage errors — defects in the invocation, never
states of the world the ride cannot fix"), and this layer is VENDORED into
downstream projects, so a newly-required flag breaks invocations that worked
yesterday, including the remedy line `list --strict` prints and every copy of
the AUTONOMOUS_LOOP 6a example in flight. Constitution Article 5 ("prefer
additive, backward-compatible edits at public boundaries") decides it. The
declaration is still real, because the direction that costs something —
claiming the lighter lane — requires an affirmative `--class measurement`,
while the omission lands in the heavier lane that exists today.

**`restamp` is the existing precedent, and the class generalises it.**
`restamp` is already the one subcommand that knows, structurally, that its
change is mechanical: it is reached only when a frozen spec's content drifted
from its own anchor because `allocate-doc-number.mjs` rewrote the spec's own
`SPEC-DRAFT-` self-references, and it writes its own `what`/`why` rather than
accepting them. It is therefore not a separate thing to be preserved beside
the class — it is the one site where the class is NOT a self-report, and it
hardcodes `measurement`. It cannot however carry the whole job: `restamp` only
handles allocator anchor drift, and the other measurement cases (a corrected
Mutation cell, a renumbered TEST id, a reworded Verify command) arrive through
`add`, which is why the class is a record field and not a fourth subcommand.

### D2 — What happens to the `fu-amend-*` co-creation

`pickAmendItemId` is measured as **one definition and exactly three call
sites** (`/usr/bin/grep -cF 'pickAmendItemId(' = 4`,
`/usr/bin/grep -cF 'const picked = pickAmendItemId' = 3` — `cmdAdd`,
`cmdClassify`, `cmdRestamp`). It is the only place that decides WHICH item an
amendment attaches to, and that property is why `add` and `classify` cannot
drift.

`pickAmendItemId` is **not modified and gains no parameter**. The class gate
sits ABOVE it, as a second single-purpose shared function:

```
function owesOwnerObligation(amendmentClass, signed) {
  return signed !== true && amendmentClass !== MEASUREMENT_CLASS;
}
```

All three writers call `owesOwnerObligation(...)` and only enter their existing
`pickAmendItemId` + `appendAmendItem` block when it returns true. So after this
change exactly one function decides WHETHER an obligation is owed and exactly
one decides WHICH item carries it, and neither is duplicated per writer. The
no-drift property is then provable behaviourally rather than by inspection: for
one spec, the item id `add --class contract` picks and the item id `classify
--class contract` picks must be byte-identical (Spec-AC-10).

### D3 — How the 190 existing unsigned records are migrated

Two different defaults, at two different layers, and that is deliberate:

- **The writer always stamps.** `add`, `classify` and `restamp` write
  `amendment_class` explicitly on every record they emit.
- **The reader defaults a class-absent record to the contract lane.** A record
  with no `amendment_class` and no class overlay folds exactly as it folds
  today — same bucket, same tracker, same row in `list`.

That reader default is the only reading that is not a decision about the
record. `spec-amend.mjs`'s own source states the principle: "deciding which
bucket an old record belongs in is the laundering this tool exists to stop",
and "`unclassified` is a distinct bucket ON PURPOSE. Reading an absent field as
'unsigned' is a guess". Reading an absent `amendment_class` as `measurement`
would discharge 190 obligations nobody decided — the laundering. Reading it as
`contract` discharges nothing and changes no record's bucket, so it is not a
verdict at all; it is the no-change reading. That asymmetry is why
`amendment_class` does NOT need an `unclassified`-style third bucket while
`owner_signoff` does.

**So the bulk of the backlog is not migrated.** The ~165 non-restamp unsigned
records stay exactly where they are, a closed legacy cohort, drained one at a
time by `classify --class measurement --why … --source …` (an append, per
record, with evidence, attributable to an actor) or signed, or neither. This
ride runs none of those.

**One cohort IS migrated, and it is selected structurally, never from prose.**
A record qualifies iff BOTH of the following hold, which is identity of a
tool-emitted literal rather than a reading of prose:

1. it carries both `from_frozen_sha256` and `to_frozen_sha256` (only
   `cmdRestamp` writes either), and
2. its `what` is byte-equal to `RESTAMP_WHAT`, the constant `cmdRestamp`
   emits — hoisted in this scope from its current inline literal so the
   selector and the writer can never disagree.

Measured at planning time: 25 records qualify, all `owner_signoff: false`,
**none already carrying a classification overlay**, so none is being
re-decided. The one duplicated `(ts, ref_id)` pair the intake warns about
(`2026-09-14T00:31:29Z` / `test-framework-sweep`, which `classify` refuses as
ambiguous) is **not in this cohort** — verified — so the cohort is fully
reachable by `classify`. The migration appends one
`spec_amendment_classification` overlay per qualifying record
(`--class measurement --signoff none --origin backfill`), edits no line
(HAZ-LEDGER), moves nothing to `signed`, and closes no follow-up item. The
cohort is re-measured at implementation time from `list --json`, never
hardcoded to 25.

Trackers are deliberately left alone. `fu-amend-*` is keyed per SPEC, not per
record, so moving one record out of the owner queue does not discharge the
item; a tracker whose last backing record became measurement-class is left
OPEN for the owner to close, because closing it is the signature this ride
does not forge.

### D4 — Whether the writer self-reporting its own class needs more than visibility

**No gate beyond visibility. One refusal, which is not a gate on the class but
on a contradiction.**

The only non-prose signal the repository already owns is the contract
projection, `lib/spec-contract-hash.mjs`. Read against this question it is
useless: its own documented projection keeps "every other cell and every prose
section VERBATIM" and blanks only AC Status/Evidence/Review-By/Notes and Test
Plan Status. A corrected Mutation cell and a rewritten AC predicate both change
it, identically. It cannot discriminate.

A finer "promise projection" (hashing only the AC id and Description cells)
WOULD discriminate one-directionally — it can only ever contradict a
`measurement` claim, never confirm one — but it needs a **pre-edit** promise
anchor stored in frontmatter, and nothing stores one. Measured on this tree:
**197 frozen specs, 20 of which carry even the existing `frozen_sha256`
anchor.** A cross-check that answers "cannot tell" on 177 of 197 frozen specs
is a control that asserts more than it proves — which is precisely the defect
class `SPEC-0204` (the ride this intake's own motivation cites) was written to
remove. Shipping it now would reproduce that defect in the mechanism built to
prevent it.

So the mitigation is visibility, made measurable rather than asserted:
- the class prints on every `list` row (`class=<value>`);
- `--json` carries `amendment_class` per item and a `measurement` count;
- `--status measurement` is a named, enumerable view, so "show me every
  obligation that was waived and who waived it" is one command;
- the actor is already on the record, so a wrong claim is attributable.

Beyond visibility, exactly one thing, which costs nothing and closes the only
route by which the lighter lane could manufacture authority:
`--class measurement --signoff owner` is a usage error. The measurement lane
can reduce an obligation to disclosure; it can never produce a `signed`
record. A record whose `owner_signoff` is literally `true` still folds to
`signed` regardless of class — a signature is never downgraded.

The promise-anchor cross-check is filed as a follow-up with the 20/197
measurement as its stated precondition; it is not deferred vaguely.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the scope changes a shipped gate's vocabulary (the
  standing hazard class) AND appends to the live `docs/ai/decisions.jsonl`
  that every other running session reads; `/Users/ales/Projects/aai` is held
  by another session on a different branch.
- User decision: worktree
- Base ref: main at 1ffc03de
- Worktree branch/path: change/amendment-signature-asks-the-owner-too-often at /Users/ales/Projects/aai-amend
- Inline review scope: .aai/scripts/spec-amend.mjs, .aai/system/AUTONOMOUS_LOOP.md, .aai/ROLE_COMMON.md, tests/skills/test-aai-spec-amend.sh, tests/skills/test-aai-downstream-autopilot.sh, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, docs/ai/decisions.jsonl

## Implementation strategy
- Strategy: tdd
- Rationale: this changes the vocabulary of a shipped gate, which is the
  standing hazard class in this repository (a guard that newly reddens or
  newly permits existing work). Every AC below is a behaviour of one CLI
  whose refusals and buckets must be observed FAILING first; the seven
  negative controls (Spec-AC-07, 08, 09) are the whole safety argument and are
  worth nothing unless each was seen red. The suite
  `tests/skills/test-aai-spec-amend.sh` already runs every assertion through
  the real writer and the real `follow-ups.mjs`, never a mock.

## Implementation plan

Components affected, in dependency order:

1. `.aai/scripts/spec-amend.mjs`
   - new module constants, each a single mandated line so the Test Plan's
     mutation cells have a stable, unique anchor:
     `const AMENDMENT_CLASSES = ['contract', 'measurement'];`,
     `const DEFAULT_AMENDMENT_CLASS = 'contract';`,
     `const MEASUREMENT_CLASS = 'measurement';`,
     `const CLASS_LABEL = 'class=';`, and `RESTAMP_WHAT` hoisted from
     `cmdRestamp`'s inline literal.
   - `BUCKETS` gains `'measurement'`. `STRICT_VIOLATION_BUCKETS` is UNCHANGED.
   - `STATUS_FILTERS` gains `measurement: ['measurement'],`.
   - `foldAmendments`: resolve the class (record's own key, else the latest
     overlay carrying one, else `DEFAULT_AMENDMENT_CLASS` — the same
     record-wins-over-overlay precedence `tracked_by` already uses, inverted
     only where the record has nothing); expose `amendment_class` and the
     structural `tool_restamp` boolean on the item; bucket order is
     `signed` first, then `measurement`, then today's logic unchanged.
   - `owesOwnerObligation(amendmentClass, signed)` as above; the three writers
     gate their existing `pickAmendItemId` + `appendAmendItem` block on it.
   - `parseArgs`: `--class` on `add` and `classify`; value validated against
     `AMENDMENT_CLASSES`; `--class measurement` with `--signoff owner` is a
     usage error.
   - `cmdRestamp`: `amendment_class: MEASUREMENT_CLASS`, no `tracked_by`, no
     item; its post-write re-read proof asserts `bucket === 'measurement'`
     instead of the tracker. The ledger-before-file ordering and the
     `AAI_SPEC_AMEND_INJECT_CRASH=before-rename` atomicity property are
     untouched.
   - `cmdList`: `CLASS_LABEL` column in `formatRow`, `amendment_class` and
     `tool_restamp` in `--json`, `counts.measurement`.
   - the printed `undisclosed-amendment` remedy line gains `--class contract`
     verbatim (the conservative value; the author edits it, exactly as it
     already does for `--what`/`--why`).
2. `tests/skills/test-aai-spec-amend.sh` — new arms; the 15 existing
   `run_sa add` and 11 `run_sa classify` arms keep their current invocations
   unchanged and so become the regression proof that the default lane did not
   move.
3. `tests/skills/test-aai-downstream-autopilot.sh` — its two `add --signoff
   none` fixture calls are unchanged (the flag is optional); the suite is run
   to prove it.
4. `.aai/system/AUTONOMOUS_LOOP.md` section 6a — the convention BODY (outside
   both TEST-010's live `.aai/*.prompt.md` glob and its extra-file accounting,
   the same placement CHANGE-0171 used for this convention; no ledger cost).
5. `.aai/ROLE_COMMON.md` POST-FREEZE block — the minimum pointer naming
   `--class contract|measurement`. This file IS inside TEST-010's extra
   accounting, so it carries a prompt-diet ledger cost.
   `.aai/SKILL_PR.prompt.md` is NOT edited: the AMENDMENT GATE bullet's
   contract ("exit 0 proceed, exit 1 run what it prints") is unchanged, so
   the live `.aai/*.prompt.md` glob does not grow.
6. `tests/skills/lib/prompt-diet-ledger.sh` — one `JUSTIFIED_ADDITIONS` entry
   slugged `amendment-class-partition`, crediting the measured ROLE_COMMON
   delta 1:1, with the TEST-012 pin moved from its current 50036.
7. `docs/ai/decisions.jsonl` — the migration overlays, appended.

Data flows: `add`/`classify`/`restamp` write; `foldAmendments` is the only
reader and every CLI surface projects from it, so the four surfaces cannot
drift (unchanged property).

Edge cases, each with a row below: a hand-appended record carrying
`owner_signoff: true` AND `amendment_class: measurement`; a class overlay on a
record that already has its own class; a record with neither class nor
`owner_signoff`; a measurement record whose spec's anchor still drifted.

## Constitution deviations

None. The CLI change is additive (a new optional flag, a new bucket, a new
status filter, new JSON fields); no existing invocation changes meaning and no
existing exit code changes for an unchanged ledger (Article 5). The migration
appends and never edits (Article 3, HAZ-LEDGER). Nothing in this scope writes
`docs/ai/STATE.yaml` (Article 6) and nothing merges (Article 7).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN `spec-amend.mjs add --class measurement --signoff none` succeeds against a fixture ledger THEN that ledger gains one `spec_amendment` record carrying `amendment_class` `measurement` and NO `tracked_by`, and `follow-ups.mjs list` over the same ledger shows zero new `fu-amend-` items | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1354.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1354.txt | — | the whole point of the scope |
| Spec-AC-02 | WHEN `spec-amend.mjs add --class contract --signoff none` succeeds against a fixture ledger THEN the ledger gains the record AND the co-created open `fu-amend-` item exactly as before this scope, and the record carries `amendment_class` `contract` | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1355.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1355.txt | — | the contract lane is bit-for-bit today's behaviour |
| Spec-AC-03 | WHEN `spec-amend.mjs add --signoff none` runs with no `--class` flag THEN it exits 0, the appended record carries `amendment_class` `contract` explicitly, and stdout carries a NOTE naming `--class measurement` | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1356.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1356.txt | — | non-breaking by Article 5; the writer always stamps |
| Spec-AC-04 | WHEN `add` or `classify` is given a `--class` value outside the closed set THEN it exits 2 and stderr names both legal values `contract` and `measurement` | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1357.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1357.txt | — | closed vocabulary, same shape as `--signoff` |
| Spec-AC-05 | WHEN `add --class measurement --signoff owner` is invoked THEN it exits 2, nothing is appended to the ledger, and stderr says the measurement class cannot carry an owner signature | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1358.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1358.txt | — | the one route by which the light lane could manufacture authority |
| Spec-AC-06 | A `spec_amendment` with `amendment_class` `measurement` and no `tracked_by` folds to bucket `measurement`, and the SAME record with `owner_signoff` true folds to `signed` instead | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1359.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1359.txt | — | signature outranks class; a signature is never downgraded |
| Spec-AC-07 | `STRICT_VIOLATION_BUCKETS` is unchanged: against a fixture ledger holding one `owner_signoff` false record with no tracker and one record with no `owner_signoff` key, `list --strict` still exits 1 and still names `unsigned-untracked` and `unclassified` | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1360.log (negative control, mutated-tree RED, disclosed in the capture) and docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1361.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1360.txt and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1361.txt | — | the explicit do-not-weaken constraint; STRICT_VIOLATION_BUCKETS is byte-unchanged and TEST-1361 proves measurement is excluded by the fold, not by weakening the set |
| Spec-AC-08 | A frozen spec whose content no longer matches its `frozen_sha256` anchor still makes `list --strict` exit 1 with an `undisclosed-amendment` violation, whatever class the ledger's records carry | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1362.log (negative control, mutated-tree RED, disclosed in the capture) and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1362.txt | — | the disclosure half is untouched |
| Spec-AC-09 | Folding the LIVE `docs/ai/decisions.jsonl` at the pre-migration commit with the new code produces, for every record outside the restamp cohort, the identical bucket the pre-change code produced | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1363.log (pre-change-tree RED, base-ref blob swapped in, disclosed in the capture) and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1363.txt | — | class-absent reads contract-lane; the reader default decides nothing |
| Spec-AC-10 | For one spec id, the `fu-amend-` id that `add --class contract --signoff none` attaches to and the id that `classify --class contract --signoff none` attaches to are byte-identical, and neither `add --class measurement` nor `classify --class measurement` creates any item | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1364.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1364.txt | — | the two writers cannot drift; `pickAmendItemId` unmodified |
| Spec-AC-11 | WHEN `restamp` re-anchors a drifted frozen spec THEN its appended record carries `amendment_class` `measurement` and no `tracked_by`, no `fu-amend-` item is created, and `list --strict` over that ledger and specs dir exits 0 | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1365.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1365.txt | — | restamp is measurement by construction, never a self-report |
| Spec-AC-12 | WHEN `classify --class measurement --signoff none` names one existing record THEN that record's bucket becomes `measurement`, its previously-tracking `fu-amend-` item keeps its open status unchanged, and a `classify` run with no `--class` leaves the target's resolved class exactly as it was | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1366.log (pre-change-tree RED, base-ref blob swapped in, disclosed in the capture) and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1366.txt | — | the per-record route; the printed remedy line stays runnable verbatim |
| Spec-AC-13 | `list` prints `class=<value>` on every row, `list --json` items carry `amendment_class`, the counts object carries a `measurement` key, and `--status measurement` is accepted and returns only measurement-bucket rows | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1367.log and docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1368.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1367.txt and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1368.txt | — | D4 visibility, made enumerable |
| Spec-AC-14 | `list --json` marks an item `tool_restamp` true iff the record carries both `from_frozen_sha256` and `to_frozen_sha256` AND its `what` is byte-equal to `RESTAMP_WHAT`; a record matching only one of the two conditions is false | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1369.log (pre-change-tree RED, base-ref blob swapped in, disclosed in the capture) and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1369.txt | — | the structural selector, no prose read |
| Spec-AC-15 | After the migration on the live ledger: `signed` is unchanged at its pre-migration count, `measurement` equals the number of appended overlays, `unsigned-tracked` falls by exactly that number, `unsigned-untracked` and `unclassified` are both 0, the total record count is unchanged, no pre-existing line is modified, and no `fu-amend-` item changed status | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1370.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1370.txt and docs/ai/reports/amendment-class-migration-20261002T081152Z.md | — | nothing laundered to `signed`, nothing closed |
| Spec-AC-16 | `.aai/ROLE_COMMON.md`'s POST-FREEZE block names `--class contract` and `--class measurement`, `.aai/system/AUTONOMOUS_LOOP.md` section 6a states the two-class partition, and `tests/skills/test-aai-prompt-diet.sh` exits 0 with an itemized `amendment-class-partition` ledger entry | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1371.log and docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1372.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1371.txt and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1372.txt | — | companion obligation; `.aai/SKILL_PR.prompt.md` untouched |
| Spec-AC-17 | WHEN `classify --class <X>` names a target whose `amendment_class` the fold would NOT resolve to `<X>` THEN it exits 2, appends nothing, and names both the refused flag and the class the fold does resolve; and `classify` reads the obligation decision off the SAME `foldAmendments` call that assigns the bucket, so a record whose bucket is `measurement` can never be given an owner obligation | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1373.log and docs/ai/tdd/amendment-signature-asks-the-owner-too-often-green-1373.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1373.txt | — | code review round 1, BLOCKING, reproduced; the two readers agree by construction rather than by a second precedence rule kept in step by hand |
| Spec-AC-18 | WHEN `restamp` re-anchors a drifted frozen spec THEN its `amendment_class` is `measurement` ONLY IF reverse-applying the allocator's DRAFT-to-numbered substitution over this spec's own frontmatter `id` and over the numbered documents its frontmatter `links` name reproduces the stored `frozen_sha256`; when no such reversal reproduces it the record is `contract`, co-creates the `fu-amend-` item, and carries a `what` naming the drift as unexplained rather than as an allocator rewrite | done | docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-1374.log and docs/ai/tdd/amendment-signature-asks-the-owner-too-often-green-1374.log and docs/ai/tdd/spec-amendment-signature-asks-the-owner-too-often/mutation-TEST-1374.txt | — | code review round 2 (Codex P1 on PR #422), BLOCKING, reproduced; the hardcoded class was justified by a comment nothing enforced |

## Test Plan

Mutation cells are deliberately one-token substitutions on lines this spec
MANDATES by name (the new constants) or on bytes measured to be unique in the
current file. Measured uniqueness, `/usr/bin/grep -cF` on
`.aai/scripts/spec-amend.mjs` at `1ffc03de`:
`contractHash(content) !== anchor` = 1,
`const specKey = target.spec_id ?? target.ref_id;` = 1,
`const BUCKETS = ['signed'` = 1,
`'unsigned-untracked', 'unclassified'` = 2 (so that anchor is taken with its
`STRICT_VIOLATION_BUCKETS = ` prefix, which is 1).
Measured the same way for the row added at remediation:
`projected.amendment_class !== amendmentClass` = 1.
Measured the same way for the row added at remediation round 2:
`cause.verified ? MEASUREMENT_CLASS : DEFAULT_AMENDMENT_CLASS` = 1.

| Test ID  | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|----------|---------|------|----------------------|-------------|----------|--------|
| TEST-1354 | Spec-AC-01 | integration | tests/skills/test-aai-spec-amend.sh | `add --class measurement --signoff none` on a fixture ledger, then `follow-ups.mjs list` over it shows no new item | sed:s/amendmentClass !== MEASUREMENT_CLASS/amendmentClass === MEASUREMENT_CLASS/ | green |
| TEST-1355 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | `add --class contract --signoff none` still co-creates the open item and stamps the class | sed:s/const DEFAULT_AMENDMENT_CLASS = 'contract'/const DEFAULT_AMENDMENT_CLASS = 'measurement'/ | green |
| TEST-1356 | Spec-AC-03 | integration | tests/skills/test-aai-spec-amend.sh | `add --signoff none` with no `--class` exits 0, stamps `contract`, prints the NOTE | sed:s/const CLASS_NOTE = 'NOTE/const CLASS_NOTE = 'SILENT/ | green |
| TEST-1357 | Spec-AC-04 | integration | tests/skills/test-aai-spec-amend.sh | `--class bogus` exits 2 on both `add` and `classify`, message names both legal values | sed:s/'contract', 'measurement'/'contract', 'measurement', 'bogus'/ | green |
| TEST-1358 | Spec-AC-05 | integration | tests/skills/test-aai-spec-amend.sh | `add --class measurement --signoff owner --authority x` exits 2 and appends nothing | sed:s/signed \&\& amendmentClass === MEASUREMENT_CLASS/false && amendmentClass === MEASUREMENT_CLASS/ | green |
| TEST-1359 | Spec-AC-06 | unit | tests/skills/test-aai-spec-amend.sh | hand-built fixture records: measurement folds to `measurement`; the same record with `owner_signoff` true folds to `signed` | sed:s/const BUCKETS = \['signed'/const BUCKETS = ['measurement'/ | green |
| TEST-1360 | Spec-AC-07 | integration | tests/skills/test-aai-spec-amend.sh | negative control: untracked-unsigned and no-key records still make `list --strict` exit 1 and still print both bucket names | sed:s/STRICT_VIOLATION_BUCKETS = \['unsigned-untracked', 'unclassified'\]/STRICT_VIOLATION_BUCKETS = ['unclassified']/ | green |
| TEST-1361 | Spec-AC-07 | integration | tests/skills/test-aai-spec-amend.sh | negative control: adding `measurement` to the strict violation set must break this arm, proving `measurement` is excluded on purpose | sed:s/STRICT_VIOLATION_BUCKETS = \['unsigned-untracked', 'unclassified'\]/STRICT_VIOLATION_BUCKETS = ['unsigned-untracked', 'unclassified', 'measurement']/ | green |
| TEST-1362 | Spec-AC-08 | integration | tests/skills/test-aai-spec-amend.sh | a drifted frozen spec in a fixture specs dir still exits 1 with `undisclosed-amendment` while the ledger holds only measurement records | sed:s/contractHash\(content\) !== anchor/false/ | green |
| TEST-1363 | Spec-AC-09 | integration | tests/skills/test-aai-spec-amend.sh | fold the live ledger at the pre-migration blob through `list --json` and compare every non-cohort record's bucket against the committed pre-change output | sed:s/const DEFAULT_AMENDMENT_CLASS = 'contract'/const DEFAULT_AMENDMENT_CLASS = 'unclassified'/ | green |
| TEST-1364 | Spec-AC-10 | integration | tests/skills/test-aai-spec-amend.sh | `add` and `classify` pick the same item id for one spec; neither measurement call creates an item | sed:s/const specKey = target.spec_id \?\? target.ref_id;/const specKey = target.ref_id;/ | green |
| TEST-1365 | Spec-AC-11 | integration | tests/skills/test-aai-spec-amend.sh | `restamp` on a drifted fixture spec writes a measurement record with no tracker and leaves `list --strict` at exit 0 | sed:s/cause\.verified \? MEASUREMENT_CLASS : DEFAULT_AMENDMENT_CLASS/DEFAULT_AMENDMENT_CLASS/ | green |
| TEST-1366 | Spec-AC-12 | integration | tests/skills/test-aai-spec-amend.sh | `classify --class measurement` moves one record and leaves its tracker open; `classify` with no `--class` changes no class | sed:s/entry.amendment_class = amendmentClass;/void 0;/ | green |
| TEST-1367 | Spec-AC-13 | integration | tests/skills/test-aai-spec-amend.sh | `list` row carries the class label and `--json` carries `amendment_class` and `counts.measurement` | sed:s/const CLASS_LABEL = 'class='/const CLASS_LABEL = 'klass='/ | green |
| TEST-1368 | Spec-AC-13 | integration | tests/skills/test-aai-spec-amend.sh | `--status measurement` is accepted and returns only measurement rows; an unknown status still exits 2 | sed:s/measurement: \['measurement'\],/measurement: [],/ | green |
| TEST-1369 | Spec-AC-14 | unit | tests/skills/test-aai-spec-amend.sh | fixture records: both anchors plus the exact `what` is `tool_restamp` true; either condition alone is false | sed:s/const RESTAMP_WHAT = 'mechanical restamp/const RESTAMP_WHAT = 'mechanical restamps/ | green |
| TEST-1370 | Spec-AC-15 | integration | tests/skills/test-aai-spec-amend.sh | fixture ledger with three cohort records and two non-cohort records: the documented migration loop moves exactly three, signs none, closes no item | sed:s/\&\& str\(rec.what\) === RESTAMP_WHAT/&& true/ | green |
| TEST-1371 | Spec-AC-16 | integration | tests/skills/test-aai-spec-amend.sh | `.aai/ROLE_COMMON.md` and `.aai/system/AUTONOMOUS_LOOP.md` both name the two class values | sed:s/--class contract/--klass contract/ | green |
| TEST-1372 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh | the diet ledger carries an itemized `amendment-class-partition` entry and the suite exits 0 | sed:s/amendment-class-partition/amendment-class-partitionX/ | green |
| TEST-1373 | Spec-AC-17 | integration | tests/skills/test-aai-spec-amend.sh | a `--class` the fold would not adopt is refused in BOTH directions and appends nothing, an agreeing `--class` is still accepted, and a class-absent legacy record still moves | sed:s/projected\.amendment_class !== amendmentClass/false/ | green |
| TEST-1374 | Spec-AC-18 | integration | tests/skills/test-aai-spec-amend.sh | a contract-shaped AC-description edit and an allocator rename mixed with an unrelated edit both take the contract lane with an open owner obligation, while a genuine allocator rename of the spec's own and its intake's DRAFT paths keeps the measurement lane and owes nothing | sed:s/cause\.verified \? MEASUREMENT_CLASS : DEFAULT_AMENDMENT_CLASS/MEASUREMENT_CLASS/ | green |

Every Spec-AC has at least one row. Spec-AC-07 and Spec-AC-13 carry two.

RED plan. Each row above is observed FAILING on the pre-change tree before the
corresponding code exists, and the capture is stored under
`docs/ai/tdd/amendment-signature-asks-the-owner-too-often-red-<n>.log`. Rows
TEST-1360 and TEST-1362 are negative controls over behaviour that already
exists, so their RED is taken against the MUTATED tree (the mutation column
above is the RED instrument for those two) and that is disclosed in the stored
capture, never presented as a pre-change product red.

## Verification

Commands, in order:

1. `node .aai/scripts/spec-amend.mjs list --json > /tmp/before.json` on the
   pre-migration tree — the baseline Spec-AC-09 and Spec-AC-15 compare against.
2. `bash tests/skills/test-aai-spec-amend.sh` — exit 0.
3. `bash tests/skills/test-aai-downstream-autopilot.sh` — exit 0 (proves the
   flag is optional and the vendored fixture calls still work).
4. `bash tests/skills/test-aai-follow-ups.sh` — exit 0 (the registry reader).
5. `bash tests/skills/test-aai-prompt-diet.sh` — exit 0.
6. `node .aai/scripts/mutation-gate.mjs --spec <this spec>` — GATE PASS,
   degraded 0, unstamped 0.
7. the migration loop, then
   `node .aai/scripts/spec-amend.mjs list --json > /tmp/after.json` and the
   Spec-AC-15 diff of counts.
8. `node .aai/scripts/spec-amend.mjs list --strict` — exit 0.
9. `node .aai/scripts/follow-ups.mjs verify-closures --strict` — exit 0.
10. `node .aai/scripts/docs-audit.mjs --check --strict` — clean.
11. full framework sweep with `AAI_TEST_TIMEOUT=3000` before close.

PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract

Strategy is `tdd`, so each AC-gating test owes a stored RED artifact under
`docs/ai/tdd/` plus the full verification matrix. Per artifact record: ref_id
`amendment-signature-asks-the-owner-too-often`, the Spec-AC and TEST-xxx, the
command, the exit code, the evidence path, and the commit SHA or diff range.

The migration owes two extra artifacts that are NOT test output:
`/tmp/before.json` and `/tmp/after.json` copied to
`docs/ai/reports/amendment-class-migration-<ts>.md` with the two count lines
and the appended overlay count, because Spec-AC-15 is a claim about the live
ledger and cannot be proven by a fixture.

## Seams this change crosses

| Seam | What it touches | Reader that must not break | Test |
|------|-----------------|----------------------------|------|
| S1 | `foldAmendments` bucket vocabulary | every `list` surface and `--strict` | TEST-1359, TEST-1360, TEST-1361 |
| S2 | the `fu-amend-` co-creation | `follow-ups.mjs list`, read through the real CLI | TEST-1354, TEST-1364 |
| S3 | the printed remedy lines | `.aai/SKILL_PR.prompt.md` step 4c, which runs what they print | TEST-013 (existing, runs the line through eval) |
| S4 | `docs/ai/decisions.jsonl` append discipline | `routine-emit.mjs`'s authorization reader, which fails CLOSED over the whole ledger on one malformed line | TEST-1370 plus the machine serialization already in `appendLine` |
| S5 | `.aai/ROLE_COMMON.md` byte count | TEST-010 extra-file accounting and the TEST-012 pin | TEST-1372 |
| S6 | `spec-freeze.mjs` stamps the anchor `add` re-stamps | unchanged in this scope; named so review checks it was not touched | TEST-1362 |

## Registry items closed by this scope

`none`.

Named, and deliberately NOT closed:
- the 32 open `fu-amend-*` items — this ride signs nothing (intake scope).
  Five of them track specs where every unsigned amendment is in the migrated
  cohort; they are left open because closing one is the owner's signature.
- `fu-frozen-mutation-cells-unusable` (P2, open) — explicitly out of scope.

Filed by this scope: one new follow-up for the promise-anchor cross-check
rejected in D4, carrying its precondition (20 of 197 frozen specs anchored).

## Residual risks

- R1. The writer self-reports its class. Accepted, with D4's reasoning and
  mitigations. Auditable after the fact, never invisible.
- R2. The ~165 non-restamp unsigned records remain an owner queue with no
  forcing function. Unchanged by this ride, by design; the intake rejected
  making the signature a merge blocker "before the partition exists to shrink
  them", and this is that partition.
- R3. A gate vocabulary change is the standing hazard class. Expect one extra
  validation round; Spec-AC-09 is the specific control.
- R4. The migration's structural selector trusts that only `cmdRestamp` ever
  wrote `from_frozen_sha256`. A hand-appended record forging both anchor
  fields AND the exact `RESTAMP_WHAT` literal would be swept in. Measured: 0
  such records today, and the conjunction makes forging it a deliberate act
  that leaves its own ledger line.

- R5. The restamp cause check reverses only the DRAFT-to-numbered rewrites
  this spec itself declares (its own `id`, and the documents its frontmatter
  `links` name), and reconstructs the unsuffixed DRAFT basename. Two genuine
  allocator shapes therefore fail to verify and fall to the contract lane: a
  sibling draft numbered in the same batch that this spec does not link, and a
  collision-suffixed draft basename, whose suffix the numbered name drops. Both
  fail CLOSED (an owner signature is asked for where none was owed), which is
  the safe direction for a laundering guard; neither can make an unverified
  drift read as verified.

## Notes

This document defines HOW, not WHAT/WHY. It does not define workflow.

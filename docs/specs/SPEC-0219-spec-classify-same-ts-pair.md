---
id: spec-classify-same-ts-pair
type: spec
number: 219
status: done
mutation_gate: v1
frozen_sha256: 6fdb2844ae3c3dfaeee765f23b60a2ce537f898955bef2907c567b39e40e81e5
ceremony_level: 2
links:
  requirement: classify-same-ts-pair
  rfc: null
  pr:
    - 449
  commits:
    - 3f76f35e3772ee2566550f3853c3fd7bfb671b93
---

# Spec — classify can address one record of a same-timestamp amendment pair

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0207-classify-same-ts-pair.md
- Engine: .aai/scripts/spec-amend.mjs (fold `foldAmendments`, writers
  `cmdAdd`, `cmdClassify`, `cmdRestamp`, gate `cmdList`)
- Prior art: docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md
  (the class partition and the projected-class refusals this scope must not
  disturb); tests/skills/test-aai-spec-amend.sh `test_1363_live_ledger_folds_identically`
  (the run-the-superseded-program baseline pattern Spec-AC-03 reuses)
- Technology contract: docs/TECHNOLOGY.md

## Registry items closed by this scope

Registry items closed by this scope: fu-classify-same-ts-pair, fu-amend-directed-merge-and-post-007bae

Registry scan: `node .aai/scripts/follow-ups.mjs list` on 2026-10-10, filtered
for classify, spec-amend, same-ts, amendment_class, (ts, ref), digest.

- `fu-classify-same-ts-pair` (P2) — CLOSED by Spec-AC-01 to Spec-AC-05 (the
  addressing mode) and Spec-AC-06 (its first use).
- `fu-amend-directed-merge-and-post-007bae` (P2) — CLOSED by Spec-AC-06: the
  last unsigned record it tracks (2026-10-10T11:35:07Z, contract) is signed
  through the new mode with the owner's existing answer as its source; the
  two other records it tracks are already `signed`.

## Registry items assessed, not closed

- `fu-classify-trial-fold-race` (P3) — NOT closed. Two concurrent `classify`
  calls on one target racing between preflight and append is a locking
  question; this scope changes WHICH record an overlay addresses, not how
  concurrent writers serialize.
- `fu-classify-rerun-not-deduped` (P3) — NOT closed. A repeated identical
  overlay and the implicit-`tracked_by` closed-tracker check are unchanged
  here; the new mode inherits today's behaviour for both.
- `fu-frozen-mutation-cells-unusable` (P2) — NOT closed, mitigated for this
  spec only: the Mutation cells below anchor on identifiers this spec
  MANDATES (D2, D3, D5, D6, D7), so they are applicable to the delivered code
  by construction. If an anchor still does not match, the corrected cell is a
  `measurement`-class amendment (`spec-amend add --class measurement`).

## Implementation strategy

- Strategy: tdd
- Rationale: Planning's decision (the intake leaves the mode to Planning).
  The change touches the fold that decides every owner-signature state on an
  append-only ledger. A silent re-fold would flip historical signature
  states, and the one way to know a test pins that is to watch it fail first.
  Every Spec-AC gets a stored RED and a mutation that reddens it. STATE
  carries a stale intake-sourced strategy for `slowest-suite-hot-spots`; its
  ref_id differs, so it is not this item's choice and is replaced.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to an append-only-ledger writer and
  its gate; the ride already runs isolated in
  `/Users/ales/Projects/aai-change-classify-same-ts-pair` on branch
  `change/classify-same-ts-pair`. Not `required`: no `protected_paths_l3`
  surface is touched.
- User decision: undecided (Implementation Preparation records it; the ride
  is already in the worktree)
- Base ref: origin/main cf39c58f
- Worktree branch/path: change/classify-same-ts-pair at
  /Users/ales/Projects/aai-change-classify-same-ts-pair
- Inline review scope: .aai/scripts/spec-amend.mjs,
  tests/skills/test-aai-spec-amend.sh, CHANGELOG.md,
  docs/issues/CHANGE-0207-classify-same-ts-pair.md,
  docs/specs/SPEC-0219-spec-classify-same-ts-pair.md, and the ledger lines
  Spec-AC-06 appends to docs/ai/decisions.jsonl (diff range origin/main..HEAD)
- Code review required: true (code and test change).

## Phasing

One ride. 6 Spec-ACs, 9 TEST rows, one engine file and one suite. Expected
three TDD dispatches of about three tests each: (A) TEST-001, 002, 003;
(B) TEST-004, 005, 008; (C) TEST-006, 007, then TEST-009 written RED. The
orchestrator then runs Spec-AC-06's commands, which turn TEST-009 green.

## Design decisions

- D1 RECORD KEY. Every `spec_amendment` record has a stable per-record key:
  the first 12 hex characters of sha256 over `JSON.stringify(record)`, where
  `record` is the parsed ledger line. Measured on the ledger at cf39c58f plus
  this branch: all 380 amendment records get distinct keys. For 363 of them
  `JSON.stringify(JSON.parse(line))` equals the line; 17 were written with
  spaced JSON, so their key is the hash of the re-serialised record, not of
  the raw line. The key is deterministic either way. Two records with equal content get equal keys
  and are by definition indistinguishable. The key is computed, never
  stored on the amendment record.
- D2 MANDATED IDENTIFIERS (the Mutation cells anchor on them):
  `const RECORD_KEY_LEN = 12;`, `function recordKey(rec)`,
  `const RECORD_OVERLAY_FIELD = 'classifies_record';`. The fold exposes
  `byRecord` (record key to item, first record wins, same as `byKey`) beside
  the unchanged `byKey`, and every folded item carries `record_key`.
- D3 RECORD-ADDRESSED OVERLAY. `classify --ts <ts> --ref <ref> --record <key>`
  appends a `spec_amendment_classification` whose target field is
  `classifies_record: <key>` and which carries NO `classifies_ts` and NO
  `classifies_ref`. The writer branch is exactly
  `if (wantRecord === null) { entry.classifies_ts = opts.ts; entry.classifies_ref = opts.ref; } else { entry[RECORD_OVERLAY_FIELD] = wantRecord; }`.
  Reason: a reader older than this change (another branch, a downstream
  copy) computes `overlayKey(undefined, undefined) === null` and counts the
  overlay as dangling, never applied. An old reader therefore keeps the
  record unsigned, and can never sign a sibling. A pair-addressed overlay
  would be applied to every record of the pair by the old fold.
- D4 FOLD. An item's overlay history is the pair-addressed overlays for its
  `(ts, ref_id)` (exactly today's list) plus the record-addressed overlays
  whose `classifies_record` equals its `record_key`, sorted by
  `byTsAscending`; latest-wins applies to that union unchanged. With no
  record-addressed overlay on the ledger, every item's history is
  byte-for-byte today's history, so the fold is unchanged. A
  record-addressed overlay is not counted as dangling. One that matches no
  record is counted in a NOTE (`… address a record key with no
  spec_amendment — counted, never applied`) and never applied.
- D5 CLASSIFY SELECTION. Candidates are the items matching `(ts, ref)`
  (today). Without `--record`: one candidate proceeds (unchanged); several
  are refused exit 2 with the word `ambiguous`, and the refusal lists one
  line per candidate: `record=<key> class=<amendment_class> bucket=<bucket> what=<first 80 chars>`,
  followed by the runnable `--record` form. With `--record <key>`: `matched`
  is `candidates.filter((i) => i.record_key === wantRecord)`. Zero matches
  are refused exit 2 naming the pair's candidate keys. More than one match
  is refused exit 2 with the word `indistinguishable`, through the guard
  `if (matched.length > 1)`. `--record` must be exactly 12 lowercase hex
  characters, else it is a usage error. Projection, the class refusals,
  `owes`, co-creation and the post-append proof all read the target through
  `byRecord.get(<key>)` when `--record` is given, and through
  `byKey` otherwise (today). `--record` is added to `FLAG_SPECS.classify`
  and to USAGE.
- D6 WRITER COLLISIONS (`add`, `restamp`). These writers stay fail-OPEN (D2
  of the original spec): a same-second `(ts, ref_id)` collision is never a
  refusal, and the timestamp is never adjusted, because the timestamp is a
  fact. The appended record is addressable by its key (D1). Each writer
  proves its write through one shared helper, `function landedRecord(after, entry)`,
  whose body is `return after.byRecord.get(recordKey(entry)) ?? null;`. Today
  both writers re-read through `byKey`, which on a collision returns the
  EARLIER record and judges the wrong one. When the pair already held a
  record, the writer prints
  `NOTE this record shares (ts, ref_id) with <n> earlier record(s); address it with --record <key>`.
- D7 PRINTED REMEDIES NAME THE RECORD. The two places that print a runnable
  `classify` line, the `list --strict` violation remedy and the
  unverified-`restamp` NOTE, append `--record <key>` when the pair is shared.
  Shared is decided by `function pairIsShared(reg, ts, ref)`. They print no
  `--record` otherwise, so every existing printed line stays byte-identical.
  The duplicate-key NOTE text changes its tail to
  `only \`classify\` without --record refuses such a pair, as ambiguous`.
- D8 SURFACES. `list --json` items gain `record_key`. Text rows
  (`formatRow`) are unchanged.
- D9 OUT OF SCOPE (intake): no ledger line is edited or deduplicated, the
  other seven shared pairs are not re-classified, and the
  meaning of a signature and who may give one are unchanged.

## Acceptance Criteria Mapping

| Intake AC | Spec-AC | Verification | Observable and evidence |
|---|---|---|---|
| AC-001 sign exactly the contract record of a mixed pair | Spec-AC-01 | V1 TEST-001, TEST-002 | contract record bucket signed with classified_by set; measurement sibling's list --json row and the strict exit unchanged |
| AC-002 indistinguishable stays refused, named | Spec-AC-02 | V1 TEST-003 | exit 2 with `ambiguous`, `indistinguishable` or the no-match reason; ledger sha256 unchanged |
| AC-003 existing overlays fold identically, live ledger | Spec-AC-03 | V1 TEST-004, TEST-005 | historical and live fold digests equal (record_key excluded); pre-change reader never applies a record overlay |
| AC-004 add collisions prevented or addressable | Spec-AC-04, Spec-AC-05 | V1 TEST-006, TEST-007, TEST-008 | exit 0, NOTE names the key, re-read judges the new record, printed remedies run verbatim |
| AC-005 #448 record signed, both items closed, strict 0 | Spec-AC-06 | V2 TEST-009; V3 commands | live row signed with source naming 'Podepsat'; both follow-ups done; `list --strict` exit 0 |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN `classify --ts T --ref R --record K --signoff owner` names the contract record of a (T, R) pair whose other record is measurement, the system SHALL append one record-addressed overlay, fold the contract record to bucket `signed` with `classified_by` set, and leave the measurement record's `list --json` row (record_key excluded) and the `list --strict` exit code exactly as before the call. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-001.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-001.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-001.txt, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-002.txt | — | D1 to D5 |
| Spec-AC-02 | WHEN the addressed records cannot be told apart (no `--record` on a shared pair; a `--record` matching two equal-content records; a `--record` matching no record of the pair; a malformed `--record`) the system SHALL exit 2 with a reason naming that case (`ambiguous` with one `record=` line per candidate, `indistinguishable`, the pair's candidate keys, or the format), and SHALL leave the ledger byte-identical. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-003.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-003.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-003.txt | — | D5; classify never guesses |
| Spec-AC-03 | WHEN the changed engine folds the cf39c58f ledger, the system SHALL produce `list --json` items (record_key removed), counts and violations byte-equal to the pre-change engine at cf39c58f on the same ledger; on the live ledger the same SHALL hold for every record no record-addressed overlay targets; and a pre-change reader SHALL count a record-addressed overlay as dangling and apply it to no record. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-004.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-004.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-004.txt, docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-005.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-005.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-005.txt | — | D3, D4; immutable pin cf39c58f |
| Spec-AC-04 | WHEN `add` or `restamp` appends a record whose (ts, ref_id) pair already exists, the system SHALL append it (exit 0, timestamp not altered), prove the write by re-reading THAT record through its key, and print a NOTE naming `--record <key>`, where the key equals the recomputed key of the appended line. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-006.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-006.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-006.txt, docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-007.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-007.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-007.txt | — | D6; behaviour chosen: addressable, not refused |
| Spec-AC-05 | WHEN `list --strict` or an unverified `restamp` prints a `classify` remedy for a record of a shared pair, the system SHALL include `--record <key>`, and each printed line run verbatim SHALL exit 0; lines for unshared pairs SHALL stay byte-identical to the pre-change output; `list --json` items SHALL carry `record_key`; `--help` SHALL document `--record`. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-008.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-008.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-008.txt | — | D7, D8; the seam between gate output and classify input |
| Spec-AC-06 | The live ledger SHALL read the 2026-10-10T11:35:07Z contract record of directed-merge-and-post-merge-cleanup (record key ae5529c8b535) as `signed`, through an overlay whose `source` cites the owner's 2026-10-10 'Podepsat' answer at the PR #448 merge checkpoint; its measurement sibling (1c45f52a2649) SHALL stay `measurement` with `classified_by` null; `fu-amend-directed-merge-and-post-007bae` and `fu-classify-same-ts-pair` SHALL be `done`; and `spec-amend list --strict` SHALL exit 0. | done | docs/ai/tdd/spec-classify-same-ts-pair/red-TEST-009.log, docs/ai/tdd/spec-classify-same-ts-pair/green-TEST-009.log, docs/ai/tdd/spec-classify-same-ts-pair/mutation-TEST-009.txt | — | V3 run by the orchestrator: classify --record ae5529c8b535 signed the contract record citing the owner answer Podepsat; both follow-ups closed; list --strict exit 0; append-only |

## Implementation plan

- Components: `.aai/scripts/spec-amend.mjs` only (fold, `cmdClassify`,
  `cmdAdd`, `cmdRestamp`, `cmdList`, `FLAG_SPECS`, USAGE, header comment
  "BACK-CLASSIFICATION IS BY APPEND" gains the record-addressed form);
  `tests/skills/test-aai-spec-amend.sh` new test functions wired into
  `main()`; `CHANGELOG.md` one `## [unreleased] — <title>` entry at the
  product-docs step.
- Data flow: ledger line, then parse, then `recordKey`, then fold item
  `record_key`; classify `--record` filters candidates, writes the overlay
  with `classifies_record`; the fold attaches it to the item with that key.
- Edge cases: record overlay plus a later pair overlay on the same record
  (latest by ts wins across the union, D4); a record overlay naming a key in
  another pair (D5 refuses, because the key must belong to `(ts, ref)`);
  `--record` on an unshared pair (accepted when it matches the single
  candidate); an `add` collision with a record that tracks a different item
  (D6 must judge the new record).

### Seams (each crossed by a real producer and a real consumer in a test)

- S1 `list --strict` and `restamp` PRODUCE remedy lines; `classify`
  CONSUMES them — TEST-008 evals the printed lines verbatim.
- S2 This engine WRITES record-addressed overlays; the PRE-CHANGE engine
  (any older vendored copy) READS the same ledger — TEST-005 runs the real
  cf39c58f program from `git show` over a ledger the new writer produced.
- S3 `classify` overlays (written here) and `follow_up_status` lines
  (written by `follow-ups.mjs close`) both feed the same fold's bucket and
  tracker state — TEST-009 reads the live ledger through the real
  `spec-amend list --json` and `follow-ups.mjs list --json`.
- S4 `add` and `restamp` write a record that `classify` must then address
  — TEST-006 and TEST-007 run `classify --record` with the key the writer
  printed.
- Residual: an older reader that does NOT treat a missing pair as dangling
  is not available to test (all shipped versions since the overlay was
  introduced share the `overlayKey` null check); TEST-005 covers the one at
  the base.

## Test Plan

All fixtures live under the suite's existing `mktemp -d` root
(`setup_fixture`); paths are checked non-empty and absolute before `cd`
(HAZ-CD). Fixture ledgers are written with `mk_ledger` or raw `printf`.
Live-ledger reads never write the shipping ledger. Each test is a
`test_*` function wired into `main()` and runnable alone with
`bash tests/skills/test-aai-spec-amend.sh <function>`. The mutation target
is `.aai/scripts/spec-amend.mjs` for every row.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-spec-amend.sh | test_classify_record_signs_one_of_a_pair: fixture pair (contract unsigned-tracked, measurement) at one (ts, ref); classify --record with the contract key and --signoff owner exits 0; list --json shows the contract row signed with classified_by set, the measurement row equal to its pre-call row with record_key removed; list --strict exit code equal before and after; positive control: exactly one new overlay line carrying classifies_record and no classifies_ts | sed:s/const RECORD_KEY_LEN = 12;/const RECORD_KEY_LEN = 0;/ | green |
| TEST-002 | Spec-AC-01 | unit | tests/skills/test-aai-spec-amend.sh | test_record_overlay_folds_to_its_record_only: HAND-WRITTEN overlay line with classifies_record = the measurement-pair contract key and owner_signoff true; list --json folds only that record to signed, sibling untouched; a second hand-written overlay with an unknown key is counted in the record-key NOTE and applied to nothing | sed:s/const RECORD_OVERLAY_FIELD = 'classifies_record';/const RECORD_OVERLAY_FIELD = 'classifies_recordx';/ | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-spec-amend.sh | test_classify_refuses_what_it_cannot_tell_apart: four arms, each exit 2 with ledger sha256 unchanged: shared pair without --record (stderr has ambiguous and one record= line per candidate), two byte-identical records with --record (indistinguishable), --record not in the pair (lists the pair keys), --record not 12 hex (usage); positive control: the same fixture with a distinct-content pair and a valid --record exits 0 | sed:s/if \(matched\.length > 1\)/if (false)/ | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-spec-amend.sh | test_existing_overlays_fold_unchanged: git show cf39c58f spec-amend.mjs and decisions.jsonl (immutable pin; skipped-arm with a named reason when the commit is unreachable, as TEST-1363); old and new list --json over that ledger: items with record_key removed, counts and violations equal; live arm: old and new over docs/ai/decisions.jsonl equal for every record no classifies_record overlay targets; positive control: item count over 300 and at least 100 overlays read | sed:s/const key = overlayKey\(rec\.classifies_ts, rec\.classifies_ref\);/const key = null;/ | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-spec-amend.sh | test_old_reader_never_applies_a_record_overlay: the NEW classify --record signs the contract record of a two-contract pair in a fixture; the cf39c58f program folds the result: both records keep their pre-call bucket and its dangling NOTE counts 1; the new program shows exactly one signed | sed:s/if \(wantRecord === null\) \{/if (true) {/ | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-spec-amend.sh | test_add_collision_is_addressable: seed signed contract records with the same ref for each second of a 6 s window from now; add --signoff none exits 0; NOTE names --record K, K equals recordKey of the appended last amendment line; tracked item exists; classify --record K --signoff owner exits 0 and only that record turns signed | sed:s/return after\.byRecord\.get\(recordKey\(entry\)\) \?\? null;/return after.byKey.get(overlayKey(entry.ts, entry.ref_id)) ?? null;/ | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-spec-amend.sh | test_restamp_collision_is_addressable: same seeded window under the spec's ref; restamp of an allocator-renamed frozen spec (existing mk_linked_freezable_spec helper) exits 0 with bucket measurement on the NEW record, NOTE names its key, seeded records unchanged | sed:s/return after\.byRecord\.get\(recordKey\(entry\)\) \?\? null;/return after.byKey.get(overlayKey(entry.ts, entry.ref_id)) ?? null;/ | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-spec-amend.sh | test_printed_remedies_address_the_record: legacy pair of two unclassified records at one (ts, ref) plus one unshared unclassified record; list --strict exit 1 prints three classify lines, the two shared ones carry --record and the unshared one is byte-equal to the cf39c58f program's line; each line evaled verbatim exits 0; list --strict then exits 0; list --json items carry record_key equal to the recomputed key; --help names --record | sed:s/function pairIsShared\(reg, ts, ref\) \{/function pairIsShared(reg, ts, ref) { return false;/ | green |
| TEST-009 | Spec-AC-06 | contract | tests/skills/test-aai-spec-amend.sh | test_448_record_signed_on_the_live_ledger: over docs/ai/decisions.jsonl: the ts 2026-10-10T11:35:07Z ref directed-merge-and-post-merge-cleanup row with record_key ae5529c8b535 is signed, and its overlay source contains Podepsat and PR #448; row 1c45f52a2649 is measurement with classified_by null; follow-ups.mjs list --json shows both ids done; list --strict exit 0. RED until the orchestrator runs V3 | sed:s/const RECORD_OVERLAY_FIELD = 'classifies_record';/const RECORD_OVERLAY_FIELD = 'classifies_recordx';/ | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-spec-amend.sh | test_add_duplicate_is_idempotent (PR #449 bot sweep): seed byte-identical measurement records for each second of a window from now; add of the same what/why exits 0, appends nothing, and prints the existing record's --record key (which addresses exactly one record); positive control: a non-identical add in the same window still appends one record | sed:s/if \(reg\.byRecord\.has\(dupKey\)\) \{/if (false) {/ | green |
| TEST-011 | Spec-AC-05 | integration | tests/skills/test-aai-spec-amend.sh | test_strict_remedy_for_identical_pair_is_a_named_note (PR #449 bot sweep): two byte-identical legacy records at one (ts, ref) plus one unshared record; list --strict exit 1 prints a classify line only for the unshared record (no --record) and the named note 'indistinguishable duplicate records: no classify can address one; see the ledger lines' once per identical record | sed:s/if \(indistinguishableInPair\(reg, v\.ts, v\.ref_id, v\.record_key\)\) \{/if (false) {/ | green |

RED discipline: each row is observed failing on the pre-change engine for
its semantic assertion (not a syntax error or a missing helper). TEST-004 is
the exception: it pins invariance, so its RED is the declared mutation, and
it is recorded as such. TEST-009 is written in dispatch (C) and observed RED
on the live ledger before V3 runs. RED logs go to
`docs/ai/tdd/classify-same-ts-pair-red.log`, labelled with the TEST id.

## Verification

- V1: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-amend.sh`
  exits 0 (run under `env -u AAI_ROLE`). Single test: append the function
  name.
- V2: TEST-009 green after V3.
- V3 (orchestrator, after implementation, before Validation; append-only,
  run from the worktree root):
  1. `node .aai/scripts/spec-amend.mjs list --json` and confirm the row with
     ts `2026-10-10T11:35:07Z`, ref `directed-merge-and-post-merge-cleanup`,
     `amendment_class` contract carries `record_key` `ae5529c8b535`
     (recomputed, not trusted from this spec).
  2. `node .aai/scripts/spec-amend.mjs classify --ts 2026-10-10T11:35:07Z --ref directed-merge-and-post-merge-cleanup --record ae5529c8b535 --signoff owner --why "owner signed every unsigned contract amendment of spec-directed-merge-and-post-merge-cleanup at the PR #448 merge checkpoint; the signed add record 2026-10-10T13:57:26Z carried that decision while classify could not address this record" --source "owner menu answer 2026-10-10 'Podepsat' (PR #448 merge checkpoint)"`
     and expect exit 0 with `bucket signed`.
  3. `node .aai/scripts/follow-ups.mjs close --id fu-amend-directed-merge-and-post-007bae --resolved-by classify-same-ts-pair --source "spec-amend classify --record ae5529c8b535 (owner 'Podepsat', PR #448)"`
  4. `node .aai/scripts/follow-ups.mjs close --id fu-classify-same-ts-pair --resolved-by classify-same-ts-pair --source "spec-amend classify --record (SPEC spec-classify-same-ts-pair)"`
  5. `node .aai/scripts/spec-amend.mjs list --strict` exits 0, then
     `bash tests/skills/test-aai-spec-amend.sh test_448_record_signed_on_the_live_ledger`
     exits 0.
- V4 regression: the suites `node .aai/scripts/select-suites.mjs` picks for
  `.aai/scripts/spec-amend.mjs` (expect test-aai-downstream-autopilot.sh,
  test-aai-mutation-gate.sh, test-aai-spec-amend.sh) plus
  test-aai-hygiene-pack.sh (TEST-562 NUL guard, learned-guard lints over the
  new tests), all through the wrapper.
- Lint: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0219-spec-classify-same-ts-pair.md`.
- Mutation: `node .aai/scripts/mutation-run.mjs` per row against
  `.aai/scripts/spec-amend.mjs`, then `mutation-gate.mjs` at close.

PASS criteria: every TEST row green with evidence, every Spec-AC terminal,
`spec-amend list --strict` exit 0 on the live ledger.

## Evidence contract

Every artifact records ref_id `classify-same-ts-pair`, the Spec-AC and
TEST ids, the exact command, exit code, log path and diff or commit
identity. TDD stores RED per AC-gating test, GREEN output and one mutation
record per row under `docs/ai/tdd/spec-classify-same-ts-pair/`. Validation
repeats V1, V2 and V4 independently, and checks the V3 ledger lines by
reading them (grep plus the folded `list --json`), never from the report.
The Validation report carries an admissible aai-outcome-v1 block, and its
path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Assumptions (autopilot, recorded instead of questions)

- A1 Addressing by content key (D1) is chosen over addressing by the
  record's own `amendment_class`. The class form resolves 1 of the 8 live
  shared pairs; the key resolves all 8. It also needs no second selector.
  The intake allows either.
- A2 AC-004 is met by "made addressable", not "refused": `add` and
  `restamp` are fail-OPEN writers by their original design (a refusal there
  strands a ride), and altering a timestamp falsifies the record.
- A3 The owner's 2026-10-10 'Podepsat' answer covers the 11:35:07Z contract
  record (the intake states he signed every unsigned contract amendment of
  that spec). Signing it through the new mode records an existing decision;
  it is not a new one.
- A4 TEST-009 asserts specific live-ledger rows. The ledger is append-only,
  so the assertion can only be invalidated by a later overlay on that
  record, which would itself be a reviewed signature change.

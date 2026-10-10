---
id: spec-merge-direction-signs-amendments
type: spec
number: 220
status: done
mutation_gate: v1
frozen_sha256: 071b98685eefc7d45f15c5b6d3ab9dff41f0622a3330ab872a91f37230debff5
ceremony_level: 2
links:
  requirement: merge-direction-signs-amendments
  rfc: null
  pr:
    - 452
  commits:
    - a0f53aeb571f76cc8ff929f50d78d4db54c428f0
---

# Spec — the owner's merge direction signs the ride's contract amendments

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0208-merge-direction-signs-amendments.md
  (owner decision 2026-10-10, answer "Merge = podpis + backlog (Recommended)")
- Engines: .aai/scripts/merge-cleanup.mjs (preflight, apply, `mergedRefs`,
  `deliveredDoneRefs`, `appendDirectedMerge`, `recordDirection`, report),
  .aai/scripts/spec-amend.mjs (`classify --record`, `list --json`, `list --strict`),
  .aai/scripts/follow-ups.mjs (`list --json`, `close`)
- Prior art: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  (the directed_merge record and the apply step contract),
  docs/specs/SPEC-0219-spec-classify-same-ts-pair.md (`classify --record`),
  docs/specs/SPEC-0205-spec-amendment-signature-asks-the-owner-too-often.md
  (the contract/measurement partition this scope does not change)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only)

## Registry items closed by this scope

Registry items closed by this scope: the 34 amendment trackers that
Spec-AC-08 closes (open at da1abba5), and no other item:
`fu-amend-a-check-cannot-tell-sile-14f9e5`,
`fu-amend-amendment-signature-asks-cf289a`,
`fu-amend-antigravity-cli-skill-paths`,
`fu-amend-downstream-rides-ask-no-d8106d`,
`fu-amend-feedback-triage-missing-4bcf68`,
`fu-amend-feedback-triage-missing-df9156`,
`fu-amend-friction-issues-arrive-w-42a6d1`,
`fu-amend-friction-publish-hides-r-b86049`,
`fu-amend-friction-upsert-channel-ba7701`,
`fu-amend-gate-checks-declared-mutation`,
`fu-amend-growth-pins-dont-wall-th-095102`,
`fu-amend-lessons-that-must-hold-d-13bccc`,
`fu-amend-live-agent-dashboard-ser-e1ff12`,
`fu-amend-mutation-clone-fidelity-8bfdf9`,
`fu-amend-mutation-clone-windows-r-2da676`,
`fu-amend-original-request-outcome-f44716`,
`fu-amend-prompts-invoke-wsl-bash-d70757`,
`fu-amend-roadmap-driven-ride-sele-1e2448`,
`fu-amend-roadmap-serves-downstrea-bc77da`,
`fu-amend-shipped-guards-have-no-d-2c787c`,
`fu-amend-spec-canon-is-a-build-artifact`,
`fu-amend-spec-close-ceremony-sweep`, `fu-amend-spec-dispatch-state-sweep`,
`fu-amend-spec-friction-channel-sweep`,
`fu-amend-spec-harness-universal-routing`,
`fu-amend-spec-mutation-gate-for-tests`,
`fu-amend-spec-pr-capability-preflight`,
`fu-amend-spec-pr-generic-url-validity`,
`fu-amend-spec-pr-github-case-identity`,
`fu-amend-spec-roadmap-takes-direction`,
`fu-amend-spec-telemetry-fields-not-prose`,
`fu-amend-spec-test-framework-sweep`,
`fu-amend-strategy-unscoped-from-c-4f2cdf`,
`fu-amend-sync-deletes-target-only-hooks`.

Registry scan: `node .aai/scripts/follow-ups.mjs list` on 2026-10-10,
filtered for amend, sign, merge-cleanup, directed, aai-merge, classify.

## Registry items assessed, not closed

- `fu-classify-rerun-not-deduped` (P3): the sign step and `sign-merged` never
  re-classify a record already folded `signed`, which makes THIS writer
  idempotent; `classify` itself still has no duplicate-overlay guard. Not closed.
- `fu-classify-trial-fold-race` (P3): the signing writers run their classify
  calls one after another in one process; the race between two independent
  classify callers is unchanged. Not closed.
- `fu-constitution-art7-directed-merge` (P3): Constitution wording about
  merge lanes; unrelated to signatures. Not closed.
- `fu-merge-foreign-journal-archive-path`, `fu-merge-pending-diverged-regression`,
  `fu-skill-tree-selects-deslop`, `fu-win-real-wrapper-smoke-hang`: other
  merge-cleanup defects, untouched by this scope. Not closed.
- `fu-amend-worktree-lacks-vendored-04c4f1`: excluded by the intake (another
  session's ride); left open, named in the PR body.
- `fu-amend-update-installs-ref-guar-f8caa1`: two of its eleven records belong
  to `routing-tables-have-an-owner-and-a-seam`, whose intake is still `draft`
  (not merged). Its nine merged-ride records are signed; the tracker stays
  open, named in the PR body.

## Implementation strategy

- Strategy: tdd
- Rationale: Planning's decision (the intake says "Planning decides"). The
  change writes owner signatures into an append-only ledger. A signature
  written in error cannot be removed, only overlaid, and a missing guard looks
  exactly like a working one until a test is seen failing without it. Every
  Spec-AC gets a stored RED and a mutation that reddens it. STATE holds an
  intake-sourced strategy for `slowest-suite-hot-spots`; its ref_id differs,
  so it is stale and is replaced.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a ledger writer, four canon prompts
  and two suites; the ride already runs in
  `/Users/ales/Projects/aai-change-merge-direction-signs-amendments` on branch
  `change/merge-direction-signs-amendments`. Not `required`: no
  `protected_paths_l3` surface is touched.
- User decision: worktree (already recorded in STATE for this branch)
- Base ref: origin/main da1abba5
- Worktree branch/path: change/merge-direction-signs-amendments at
  /Users/ales/Projects/aai-change-merge-direction-signs-amendments
- Inline review scope: diff range origin/main..HEAD, which covers
  .aai/scripts/merge-cleanup.mjs, tests/skills/test-aai-merge-cleanup.sh,
  .aai/ROLE_COMMON.md, .aai/SKILL_MERGE.prompt.md, .aai/SKILL_SHIP.prompt.md,
  .aai/SKILL_PR.prompt.md, .aai/system/AUTONOMOUS_LOOP.md,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  docs/product/directed-merge-and-post-merge-cleanup.md, CHANGELOG.md, the
  intake and this spec, and the lines Spec-AC-08 appends to
  docs/ai/decisions.jsonl
- Code review required: true (code, canon and test change).

## Phasing

One ride. 8 Spec-ACs, 9 TEST rows, one engine file, one suite (plus the
prompt-diet pin). Expected three TDD dispatches of about three tests each:
(A) TEST-018, TEST-020, TEST-021 (the sign step and its guards);
(B) TEST-022, TEST-023, TEST-019 (trackers, idempotence, resume, preflight,
downstream layout); (C) TEST-025, TEST-024, then TEST-026 written RED
(`sign-merged`, canon, live contract). The orchestrator then runs V3, which
turns TEST-026 green.

## Design decisions

- D1 New apply step `sign-amendments`, placed in `STEP_IDS` right after
  `sync-base` and before `state` (the synced ledger holds the ride's records
  only after the fast-forward). It runs only in `apply`; `plan` lists its
  targets (record keys) without writing. The suite's `ALL_STEPS` and the
  interrupted-run convergence test include it.
- D2 Authority. The step looks in the origin's `docs/ai/decisions.jsonl` for a
  record with `type: directed_merge`, `by: human`, `pr` equal to the PR
  number, `head` equal to the PR's `headRefOid`, and a non-empty `answer`.
  When apply is given `--direction` and no such record exists yet, the step
  first writes it through the existing `appendDirectedMerge` (the record that
  `recordDirection` would otherwise write at `report`; it stays
  idempotent). With no such record the step is a named no-op
  `no_human_direction` and writes nothing. Any other record type, any
  `by` other than `human`, another PR or another head authorizes nothing.
- D3 Which records. A record is "of a ride merged by this PR" when its
  `ref_id` is one of the ride keys of a doc in `mergedRefs` (the existing
  `deliveredDoneRefs` predicate: a non-spec doc the merge commit added or
  changed, status done, links.pr naming the PR). Ride keys of a doc are its
  frontmatter `id`, `spec-` + that id, and its numbered display id taken from
  the filename (`CHANGE-0179` for `CHANGE-0179-<slug>.md`). Of those records
  the step signs exactly the ones whose `list --json` row has
  `amendment_class` `contract` and a bucket other than `signed`.
  Measurement records, signed records and records of any other ref are not
  passed to any writer.
- D4 How it signs. Through the shipped CLI only: for each record,
  `spec-amend.mjs classify --ts <ts> --ref <ref_id> --record <record_key>
  --signoff owner --actor merge-cleanup --why "<…>" --source "<…>"
  --ledger <origin ledger>`. `--source` names the directed_merge: PR number,
  head sha, the record's ts and the verbatim `answer`, plus the merge commit.
  The step reads the fold back after each call and stops (exit 4) on a
  classify that did not land as `signed`; a re-run resumes.
- D5 Trackers. After signing, for each `fu-amend-*` id that any of the signed
  records is tracked by and that `follow-ups.mjs list --json` shows open, the
  step closes it with `follow-ups.mjs close --id <id> --resolved-by <ride ref>
  --source <merge commit> --actor merge-cleanup` only when every
  `contract` row in `list --json` with that `tracked_by` folds `signed`. One
  unsigned contract record keeps the tracker open. The close predicate reads
  the ledger as it is, not the run's own list of signed keys, so a run that
  was killed between signing and closing closes on the re-run.
- D6 Report. The step reports `done` with `N signed, M closed`, or a named
  no-op (`no_human_direction`, `nothing_to_sign`). The JSON report gains
  `signed` (record keys) and `closed` (tracker ids); the saved Markdown report
  gains `## Signed` and `## Trackers closed` sections. A second apply signs
  nothing, closes nothing and reports `nothing_to_sign`.
- D7 Preflight. After all gates pass and before the merge command line,
  preflight prints one line per record it expects the direction to sign:
  `signs on merge: <record_key> <ref_id> <what, first 100 chars>`, or
  `signs on merge: none`. It derives the ride docs from the ride checkout
  (diff of `git merge-base HEAD refs/remotes/origin/<base>`..HEAD, same done +
  links.pr predicate, ride keys as D3) and the records from that checkout's
  ledger. `--json` output gains `signs_on_merge: [{record_key, ref_id, what}]`.
  Preflight writes nothing new beyond the existing directed_merge line.
- D8 Backlog command (reusable): `merge-cleanup.mjs sign-merged
  --authority-ts <ISO ts> [--exclude <fu-id>]... [--base <name>] [--dry-run]
  [--origin <abs>] [--json]`. No `--pr`. It refuses (exit 3, nothing written)
  unless exactly one ledger record has that `ts`, `by: human`, a type of
  `hitl_decision` or `directed_merge`, and a non-empty `answer`. For each open
  `fu-amend-*` tracker not excluded, it takes the tracker's unsigned contract
  records and resolves each record's ride doc on `refs/remotes/origin/<base>`
  (default `main`) by ride key (D3; intake doc types only, never spec, product,
  report or review). A record is signable only when that doc is status done
  with links.pr naming a PR N, and a first-parent commit C of origin/<base>
  carries that doc with status done and links.pr naming N (the first such
  commit is cited as the merge commit). Signing and closing reuse D4 and D5
  with `--source "owner decision <ts> by=human answer=\"<answer>\"; <ride ref>
  merged by PR #N at <C>"`. `--dry-run` prints the plan (per tracker: keys to
  sign, close or stays-open with the reason) and writes nothing. Trackers left
  open are printed with their reason (`excluded`, `unmerged:<ref>`).
- D9 Contract anchors. The mutation cells below act on these literals, so the
  implementation carries them verbatim:
  - `const SIGN_STEP_ID = 'sign-amendments';`
  - `if (!direction) return { status: 'noop', detail: 'no_human_direction' };`
  - `const SIGNABLE_CLASS = 'contract';` and the record filter
    `.filter((i) => i.amendment_class === SIGNABLE_CLASS && i.bucket !== 'signed')`
  - the ride filter `.filter((i) => keys.has(i.ref_id))`
  - the close predicate `const fullySigned = mine.every((i) => i.bucket === 'signed');`
  - the preflight line prefix `signs on merge: `
  - the backlog guard `if (!authority) refuse('no_owner_decision',`
  - the backlog merge predicate `if (!delivery) {`
- D10 Canon. ROLE_COMMON "POST-FREEZE SPEC AMENDMENT", SKILL_MERGE,
  SKILL_SHIP (step 5 and step 6, where `owed sign-offs:` becomes
  `signs on merge:`), SKILL_PR (the PR body lists the amendments the merge
  direction will sign) and .aai/system/AUTONOMOUS_LOOP.md section 6a say that
  the owner's `/aai-merge` direction signs the ride's contract amendments and
  that there is no separate sign-off question before the merge. Net prompt
  bytes are credited 1:1 in tests/skills/lib/prompt-diet-ledger.sh under key
  `merge-direction-signs-amendments`, and the TEST-012 pin in
  tests/skills/test-aai-prompt-diet.sh moves by the same measured delta.

## Seams

- S1 merge-cleanup writes overlays that spec-amend's fold reads: TEST-018,
  TEST-021, TEST-022 assert through the real `spec-amend.mjs list --json`, never
  by reading the overlay text.
- S2 merge-cleanup closes trackers that follow-ups' fold reads and that
  spec-amend's `unsigned-tracked` bucket depends on: TEST-022 asserts through
  real `follow-ups.mjs list --json` AND `spec-amend.mjs list --strict` (a
  tracker closed too early turns a record `unsigned-untracked` and the gate red).
- S3 preflight writes the directed_merge into the main checkout and apply
  reads it after the merge: TEST-018 runs preflight then apply on one fixture
  world, with no hand-written directed_merge line.
- S4 the engine spawns sibling scripts in the installed core layout: TEST-019
  runs apply from `aai-sync.sh --profile core` output.
- S5 close-work-item's `status: done` + `links.pr` stamp is what makes a ride
  "merged" for both apply and `sign-merged`: the fixtures use the same stamp
  shape the existing suite's `numbered_issue` writes.

## Acceptance Criteria Mapping

- Intake AC-001 -> Spec-AC-01; AC-002 -> Spec-AC-02; AC-003 -> Spec-AC-03;
  AC-004 -> Spec-AC-04; AC-005 -> Spec-AC-05; AC-006 -> Spec-AC-06;
  AC-007 -> Spec-AC-07 (the reusable command) and Spec-AC-08 (the live result).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN apply runs for a merged PR and the origin ledger holds a `directed_merge` record with `by` human, that PR and its `headRefOid`, the system SHALL append one `spec_amendment_classification` overlay with `owner_signoff` true and `classifies_record` per unsigned contract record of the rides that PR delivered, each `source` containing the PR number, the head sha and the verbatim answer, so that `spec-amend list --json` folds every such record to bucket `signed`; this SHALL hold in the source layout and in a `--profile core` installed layout. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-018.log, docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-019.log, docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-027.log | — | D1 to D4, D6; seams S1, S3, S4; PFA-8 |
| Spec-AC-02 | WHEN no `directed_merge` record matches with `by` human, the PR number and the PR head (four arms: none; `by` orchestrator; another head; another PR), apply SHALL append no overlay and no `follow_up_status` line, SHALL leave the `decisions.jsonl` bytes as they were after `sync-base`, and SHALL report step `sign-amendments` as noop `no_human_direction`. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-020.log | — | D2 |
| Spec-AC-03 | WHEN an owner-directed apply signs, the system SHALL leave the `list --json` rows of measurement records, already-signed records and records whose ref is not a ride key of a doc delivered by the PR equal to their rows before apply, and SHALL append overlays for the unsigned contract records only (count of new overlays equals count of those records). | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-021.log | — | D3 |
| Spec-AC-04 | WHEN every contract record tracked by a `fu-amend-*` tracker folds `signed` after the step, the system SHALL close that tracker (follow-ups `list --json` status done) and keep `spec-amend list --strict` at exit 0; a tracker with one remaining unsigned contract record SHALL stay open; a second apply SHALL append nothing to `decisions.jsonl`; and a run killed after its first classify SHALL, on re-run, end in the same ledger fold and tracker states as an uninterrupted run with no duplicate overlay. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-022.log | — | D4, D5; seam S2 |
| Spec-AC-05 | WHEN preflight passes all gates, its stdout SHALL contain one `signs on merge: <record_key> <ref_id> <what>` line per unsigned contract record of the ride (or `signs on merge: none`) before the printed `gh pr merge` line, and `--json` SHALL carry the same records in `signs_on_merge`; preflight SHALL append no overlay. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-023.log | — | D7 |
| Spec-AC-06 | ROLE_COMMON, SKILL_MERGE, SKILL_SHIP, SKILL_PR and AUTONOMOUS_LOOP section 6a SHALL state that the owner's merge direction signs the ride's contract amendments; none of them SHALL contain `owed sign-offs`, and SKILL_SHIP step 6 SHALL carry `signs on merge:`; the prompt-diet ledger SHALL carry an entry keyed `merge-direction-signs-amendments` and test-aai-prompt-diet.sh SHALL exit 0. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-024.log | — | D10 |
| Spec-AC-07 | WHEN `sign-merged` runs, the system SHALL refuse with exit 3, reason `no_owner_decision` and an unchanged ledger unless `--authority-ts` names exactly one `by` human `hitl_decision` or `directed_merge` record with a non-empty answer; `--dry-run` SHALL write nothing; otherwise it SHALL sign each unsigned contract record whose ride doc is done on origin/base with a PR delivered by a first-parent commit, citing the authority ts, answer, PR and that commit in `source`; SHALL leave records of unmerged rides and of `--exclude`d trackers unsigned; and SHALL close only trackers whose contract records are all signed. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-025-r1.log | — | D8 |
| Spec-AC-08 | On the live ledger after V3: every `fu-amend-*` tracker open at da1abba5 SHALL be done except `fu-amend-worktree-lacks-vendored-04c4f1` and `fu-amend-update-installs-ref-guar-f8caa1`; the 202 records of the merged rides (206 unsigned at da1abba5, minus 2 of `routing-tables-have-an-owner-and-a-seam` and 2 of the excluded tracker) SHALL fold `signed` through overlays whose `source` names the authority ts and a commit on origin/main; every other record present at da1abba5 SHALL keep its `owner_signoff`, `amendment_class` and `bucket`; and `spec-amend list --strict` SHALL exit 0. | done | docs/ai/tdd/spec-merge-direction-signs-amendments/green-TEST-026-r1.log | — | V3 run by the orchestrator |

## Implementation plan

- .aai/scripts/merge-cleanup.mjs: `rideKeys(doc)`, a `signAmendments(ctx)`
  handler (D1 to D6), shared `signRecords` / `closeFullySigned` helpers that
  spawn `spec-amend.mjs` and `follow-ups.mjs` from `SCRIPT_DIR`, the preflight
  listing (D7), the `sign-merged` mode (D8) with its own argument rules (no
  `--pr`), HELP text, report fields. Test seam `AAI_MERGE_CLEANUP_CRASH_AT=sign-after-classify`
  (inert without `AAI_MERGE_CLEANUP_TEST_SEAMS=1`, like the others).
- tests/skills/test-aai-merge-cleanup.sh: TEST-018 to TEST-026 functions,
  `ALL_STEPS` gains `sign-amendments`, selector cases, default run order.
  Fixture worlds seed `spec_amendment` records and `follow_up` lines through
  the real `spec-amend.mjs add` and `follow-ups.mjs add` (not hand-written),
  with `--ledger` pointing into the fixture.
- Canon, product doc, CHANGELOG `## [unreleased] — <title>` entry.
- Edge cases: a record whose ref is the spec id (`spec-<slug>`); a numbered
  display-id ref (`CHANGE-0179`); one tracker spanning a merged and an
  unmerged ride; a pair sharing (ts, ref) (always `--record`); a directed_merge
  written by preflight without `merge_commit`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-018 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_018_direction_signs_ride_amendments: fixture ride with two contract records (one ref = issue id, one ref = spec- id) added by real spec-amend add --signoff none; preflight with --direction writes the directed_merge into the origin; merge fixture; apply exits 0; list --json shows both signed; positive control: exactly two new overlay lines with classifies_record, each source containing the PR number, head sha and answer; step sign-amendments done | sed:s/const SIGN_STEP_ID = 'sign-amendments';/const SIGN_STEP_ID = 'sign-amendments-off';/ | green |
| TEST-019 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_019_downstream_signs: DOWNSTREAM=1 core install; apply from the installed engine with --direction signs the ride's contract record (list --json via the installed spec-amend.mjs shows signed); spaced scratch path | sed:s/path\.join\(SCRIPT_DIR, 'spec-amend\.mjs'\)/path.join(SCRIPT_DIR, 'spec-amend-x.mjs')/ | green |
| TEST-020 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_020_no_human_direction_signs_nothing: four arms (no directed_merge; by orchestrator; other head; other PR); each apply exits 0, sign-amendments noop no_human_direction, decisions.jsonl sha256 equal to the post-sync bytes, list --json rows unchanged, no follow_up_status line; positive control arm with a matching human record signs | sed:s/if \(!direction\) return \{ status: 'noop', detail: 'no_human_direction' \};/if (false) return null;/ | green |
| TEST-021 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_021_signs_only_unsigned_contract_of_the_ride: ledger holds a measurement record and an owner-signed contract record of the ride plus an unsigned contract record of another ref; after apply their list --json rows equal the pre-apply rows; new overlay count equals the ride's unsigned contract count (positive control 1) | sed:s/\.filter\(\(i\) => keys\.has\(i\.ref_id\)\)/.filter(() => true)/ | green |
| TEST-022 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_022_trackers_close_idempotent_resumable: tracker A (all records of the ride) closes; tracker B (one ride record, one record of an unmerged ref) stays open; list --strict exit 0 after; second apply appends zero bytes to decisions.jsonl and reports nothing_to_sign; CRASH_AT=sign-after-classify then re-run equals the uninterrupted control (folded rows, tracker states) with no duplicate overlay | sed:s/mine\.every\(/mine.some(/ | green |
| TEST-023 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_023_preflight_lists_signs_on_merge: open-PR world with two unsigned contract records and one measurement record; preflight exit 10; stdout has two signs on merge lines (record keys equal to list --json keys) before the gh pr merge line, none for the measurement record; --json signs_on_merge length 2; no overlay appended; a ride with none prints signs on merge: none | sed:s/signs on merge: /signs-hidden: / | green |
| TEST-024 | Spec-AC-06 | contract | tests/skills/test-aai-merge-cleanup.sh | test_024_canon_merge_direction_signs: ROLE_COMMON, SKILL_MERGE, SKILL_SHIP, SKILL_PR, AUTONOMOUS_LOOP each carry the phrase merge direction signs; none carries owed sign-offs; SKILL_SHIP step 6 carries signs on merge:; prompt-diet ledger carries merge-direction-signs-amendments with a positive integer credit | sed:s/signs on merge:/owed sign-offs:/ | green |
| TEST-025 | Spec-AC-07 | integration | tests/skills/test-aai-merge-cleanup.sh | test_025_sign_merged_backlog: origin main with ride X done and delivered (squash commit), ride Y draft, tracker T1 (X only), T2 (X and Y), T3 (X, excluded); --authority-ts of a by-orchestrator record and of a missing ts exit 3 no_owner_decision, ledger sha256 unchanged; --dry-run writes nothing and lists T1 close, T2 stays open unmerged, T3 excluded; real run signs X's records with source naming the authority ts, answer, PR and the squash commit; T1 closed, T2 and T3 open; Y's records and T3's records unsigned; list --strict exit 0 | sed:s/if \(!authority\) refuse\('no_owner_decision',/if (false) refuse('no_owner_decision',/ | green |
| TEST-026 | Spec-AC-08 | contract | tests/skills/test-aai-merge-cleanup.sh | test_026_backlog_signed_on_live_ledger: over docs/ai/decisions.jsonl: the trackers open in the da1abba5 blob are done except the two named; the 202 keys signed with overlay source containing the authority ts and a 40-hex commit on origin/main; for every other record_key present in the da1abba5 fold the fields owner_signoff, amendment_class, bucket are equal; list --strict exit 0; positive control: over 380 items read, over 30 trackers checked. RED until the orchestrator runs V3 | sed:s/const RECORD_OVERLAY_FIELD = 'classifies_record';/const RECORD_OVERLAY_FIELD = 'classifies_recordx';/ | green |
| TEST-027 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_027_signature_cites_the_current_direction: two by-human directed_merge records for the same PR and head with different answers (ts 03:00 and 04:00); four arms: apply --direction with the second answer cites it; apply --direction with the first answer cites it; apply without --direction cites the latest; with one record, apply --direction with new words records them first and cites them; each arm: step done, two overlays, each source carries the wanted answer and ts and not the other answer | sed:s/mine\.at\(-1\)/mine[0]/ | green |

## Verification

- V1: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0. Single test: append the function name or `TEST-0xx`.
- V2: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  exits 0 (TEST-010 headroom, TEST-012 pin).
- V3 (orchestrator, after implementation, before Validation; append-only,
  from the worktree root):
  1. Record the owner's decision once (if absent):
     `{"v":1,"ts":"<now>","actor":"orchestrator","type":"hitl_decision","ref_id":"merge-direction-signs-amendments","by":"human","question":"Should the owner's merge direction also sign the PR's contract amendments?","answer":"Merge = podpis + backlog (Recommended)","decision":"the owner's /aai-merge direction signs the ride's contract amendments; the merged-ride backlog is signed once"}`
     appended to docs/ai/decisions.jsonl.
  2. `node .aai/scripts/spec-amend.mjs list --json > <scratch>/before.json`.
  3. `node .aai/scripts/merge-cleanup.mjs sign-merged --authority-ts <ts of step 1> --exclude fu-amend-worktree-lacks-vendored-04c4f1 --origin "$PWD" --dry-run --json`
     (`--origin` names the ride worktree; without it the engine reads the main checkout);
     check the plan: 202 records to sign, 34 trackers to close,
     `fu-amend-update-installs-ref-guar-f8caa1` stays open `unmerged:routing-tables-have-an-owner-and-a-seam`.
     A different count is a finding to explain before step 4, not to push through.
  4. The same command (with `--origin`) without `--dry-run`; exit 0.
  5. `node .aai/scripts/spec-amend.mjs list --strict` exits 0;
     `node .aai/scripts/follow-ups.mjs list --status open | /usr/bin/grep fu-amend-`
     shows only the two named trackers (plus any filed after da1abba5 by this
     ride, named in the PR body);
     `bash tests/skills/test-aai-merge-cleanup.sh test_026_backlog_signed_on_live_ledger` exits 0.
- V4 regression: the suites `node .aai/scripts/select-suites.mjs` picks for
  the changed paths (at least test-aai-merge-cleanup.sh, test-aai-spec-amend.sh,
  test-aai-prompt-diet.sh, test-aai-hygiene-pack.sh) through the wrapper, and
  `node .aai/scripts/docs-audit.mjs --check --strict`.
- Lint: `node .aai/scripts/spec-lint.mjs --path <this spec>`.
- Mutation: `node .aai/scripts/mutation-run.mjs` per row (target
  .aai/scripts/merge-cleanup.mjs, except TEST-024 on .aai/SKILL_SHIP.prompt.md
  and TEST-026 on .aai/scripts/spec-amend.mjs), then `mutation-gate.mjs` at close.

PASS criteria: every TEST row green with evidence, every Spec-AC terminal,
`spec-amend list --strict` exit 0 on the live ledger.

## Evidence contract

Every artifact records ref_id `merge-direction-signs-amendments`, the Spec-AC
and TEST ids, the exact command, exit code, log path and diff or commit
identity. TDD stores RED per AC-gating test, GREEN output and one mutation
record per row under `docs/ai/tdd/spec-merge-direction-signs-amendments/`.
Validation repeats V1, V2 and V4 independently and checks the V3 ledger lines
by reading them through `list --json` and `follow-ups list --json`, never
from a report. The Validation report carries an admissible aai-outcome-v1
block, and its path is the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Residual risks

- R1 The engine cannot prove that `--direction` words are the owner's. Only
  canon (SKILL_MERGE runs on the owner's explicit `/aai-merge <n>`) keeps an
  agent from calling preflight or apply with invented words. This was already
  true of the directed_merge record (SPEC-0218); this scope makes that record
  carry more weight. Lane and standing merges never pass `--direction`, so
  they sign nothing (Spec-AC-02).
- R2 The backlog "merged" predicate trusts the close stamp (status done +
  links.pr) and the first-parent commit that first carries it. A doc stamped
  done in a commit that was not the PR's merge would cite that commit. Measured
  at da1abba5: every one of the 35 merged trackers resolves to a commit whose
  subject names its PR, except PR #385 and #393, whose merge commits have no
  `(#N)` suffix (b477fb3b, e48c0bef); V3 step 3 output is read for those two.
- R3 `fu-amend-worktree-lacks-vendored-04c4f1` is excluded on the intake's word
  although its ride (PR #433) reads as merged; it stays open for the owning
  session.

## Assumptions (autopilot, recorded instead of questions)

- A1 The backlog authority is the owner's 2026-10-10 answer quoted in the
  intake. It is recorded as a `hitl_decision` (`by: human`, verbatim answer)
  in V3 step 1 before any signature, so every overlay cites a ledger record,
  not prose.
- A2 The backlog is a reusable `merge-cleanup.mjs sign-merged` mode (not a
  scripted loop), because it shares the ride-key, signing and close logic with
  apply and its refusal guard is testable. No new `.aai/**` file, so no
  PROFILES entry is owed.
- A3 Records of a tracker that spans a merged and an unmerged ride: the merged
  ones are signed and the tracker stays open (AC-004's rule applied to the
  backlog).
- A4 `unclassified` records are not signed by either writer (the intake names
  "unsigned contract records"); none exist at da1abba5 (`list --strict` exit 0).
- A5 Ceremony level 2: no `protected_paths_l3` surface; the engine is
  SPEC-0218's L2 engine.

## Post-freeze amendments

Additive; every sentence above stands except the clause a PFA below names as
narrowed. Disclosed with
`spec-amend.mjs add --class contract --signoff none` (ref
`merge-direction-signs-amendments`); the owner's merge direction signs it.

- PFA-1 (batch B, D7): preflight refuses `signs_unknown` (exit 3, before the
  directed_merge line is written) when it cannot derive the signing list: an
  unsafe base name, no merge base of HEAD with `origin/<base>`, or a ride
  ledger that `spec-amend list --json` cannot read. D7 names no refusal; a
  preflight that printed `signs on merge: none` over an unreadable ledger would
  misstate what the direction signs.
- PFA-2 (batch C, D8): `sign-merged` treats `--pr` as a usage error (exit 2)
  and refuses `base_unreadable` (no `refs/remotes/origin/<base>`) and
  `ledger_unreadable` (exit 3, nothing written). Ride docs are the intake types
  issue, change, techdebt, rfc, prd, requirement and research; a ride key that
  names more than one such doc resolves no ride, so its records stay unsigned
  and the tracker stays open as `unmerged:<ref>`. An open `fu-amend-*` tracker
  with no contract record stays open as `no_contract_records`. `--json` carries
  `authority`, `plan` (per tracker: `action` close or open, `reason`, `sign`),
  `to_sign`, `to_close`, `signed` and `closed`; text output ends
  `would sign N, would close M` (dry run) or `signed N, closed M`.
- PFA-3 (batch C, D10 and Isolation and review): the review scope gains
  tests/skills/test-aai-downstream-autopilot.sh. Its TEST-1211 pinned the
  SKILL_SHIP step 6 `owed sign-offs:` line that D10 replaces; it now pins
  `signs on merge:` naming `spec-amend.mjs list --json` and refuses
  `owed sign-offs`. This supersedes the step 6 clause of SPEC-0200 Spec-AC-08
  (the `--signoff none` default sentences it pins are unchanged).
- PFA-4 (remediation round 1, D8 and Spec-AC-07, contract): the backlog
  authority narrows to a `by: human` `hitl_decision` with a non-empty answer.
  A `directed_merge` is the owner's words about one pull request; it no longer
  authorizes `sign-merged` and refuses `no_owner_decision` (this narrows the
  "`hitl_decision` or `directed_merge`" clause of D8 and Spec-AC-07). The
  refusal detail names the ledger path it read. HELP lists `sign-merged` and
  states that `--origin` defaults to the main checkout (the first git
  worktree) in every mode; the V3 runbook and the product doc pass `--origin`.
  TEST-025 gains a refusal arm for a `by: human` `directed_merge` with an
  answer, with a positive control that the record is in the ledger.
- PFA-5 (remediation round 1, V4 and Isolation and review, contract): the
  review scope gains tests/skills/test-aai-spec-amend.sh and
  tests/skills/test-aai-pr-preflight.sh. TEST-1375 arm 1 pinned the 13
  unprovable restamp records as `contract`/`unsigned-tracked`; the contract
  lane is its point, so it now accepts `contract` with `unsigned-tracked` or
  with `signed` through an owner overlay, and still refuses `measurement`.
  TEST-008 adds this ride's SKILL_PR growth (+163 B) and its 560 B ledger
  credit to its pins.
- PFA-6 (remediation round 1, TEST-026, measurement): TEST-026 measures
  Spec-AC-08 at what V3 wrote, not at the moving live fold: exactly 202
  overlays cite the authority ts, each classifies one of the 202 merged-ride
  records, cites a 40-hex commit on origin/main, and that record folds
  `signed`; each of the 34 trackers has a `merge-cleanup` close after the
  authority record citing a commit on origin/main; `list --strict` exits 0. A
  later `/aai-merge` that signs or closes more keeps it green.
- PFA-7 (remediation round 1, Registry items closed, measurement): the
  closure line names the 34 closed tracker ids instead of a wildcard, so
  `follow-ups verify-closures` reads real ids.
- PFA-8 (bot-sweep round on PR #452, D2 and Spec-AC-01, contract): when the
  origin holds several `by: human` `directed_merge` records for the PR and its
  head (preflight re-run with other words, for example after a failed merge
  command), the step cites the record whose `answer` equals apply's
  `--direction`, writing it first when no record carries those words; without
  `--direction` it cites the latest matching record. D2 named no choice and the
  forward search cited the oldest answer. TEST-027 pins it.

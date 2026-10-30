---
id: spec-watch-ci-reread-refresh-and-p3-cleanup
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: f8fa009639df45b3bd87572e3648049d4984f25cc23cac9144743e479dc151b3
ceremony_level: 2
links:
  requirement: watch-ci-reread-refresh-and-p3-cleanup
  rfc: null
  pr: []
  commits: []
---

# watch-ci re-read refresh, SKILL_PR release-notes wording, and two ledger corrections

SPEC-FROZEN: true

## Links

- Intake: docs/issues/CHANGE-DRAFT-watch-ci-reread-refresh-and-p3-cleanup.md
- Prior art: docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md
  (superseded cancelled runs, the snapshot-skew re-read, the release-notes
  shipped-docs list), docs/specs/SPEC-0256-spec-current-head-ci-reader.md
  (shared current-head reader), docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md
  (Amendment 1, A1-n)
- Product: docs/product/release-notes-gate.md, docs/product/release-command-finish.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only; Bash 3.2 and GNU Bash)
- Baseline commit: `7d38415a` (main at planning time)

## Implementation strategy

- Strategy: hybrid
- Rationale: the reader change (Spec-AC-01 to 04) decides what CI and the
  release accept, so each of those rows goes RED first with a stored artifact
  and a mutation record (TDD). The prompt wording, the prompt-diet true-up, the
  two ledger correction records and the four follow-up closes (Spec-AC-05 to
  08) are written in loop mode; their inspection rows are still mutation-gated.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions; the
  mutation runs temporarily rewrite `.aai/scripts/lib/github-checks.mjs`,
  `.aai/SKILL_PR.prompt.md` and the live `docs/ai/decisions.jsonl`, which must
  not race another session's ledger append; the scope is PR-bound. No file is
  in `protected_paths_l3` (docs/ai/docs-audit.yaml), so not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the list in "Files Implementation touches" below.
- Code review required: true.

## What Planning measured

Read from the code and the ledger at `7d38415a`; inputs, not attestations.

### Defect 1: stale workflow cache on the re-read

- `.aai/scripts/lib/github-checks.mjs` `readCurrentChecks` fills the
  `workflows` Map inside `readCheckRuns()` only when `!workflows.has(runId)`
  (line 109). The status and conclusion stored there come from the first
  `actions/runs/<id>` read.
- When the first read finds a run with conclusion `cancelled`, the reader
  fetches the run list (line 141) and calls `readCheckRuns()` again (line 161).
  Cached runs are not re-fetched on that second call.
- Consequence: run W, in progress on read 1, cancelled before read 2. Read 2
  sees W's check run as `cancelled` (bucket `cancel`) but W is not in
  `cancelledRuns`, so supersession never considers it. watch-ci exits 5 on a
  superseded run. Never a false green, because bucket `cancel` is never pass.
- The line 162 guard (`workflow state moved during observation`) only fires
  for a run first seen on read 2. Code review r2 of SPEC-0261 noted that no
  committed test exercises it.
- watch-ci.mjs maps a reader throw to exit 3 (DEGRADED, stops) and a settled
  `cancel` or `fail` bucket to exit 5 (FAILED). The release reader throws.

### Defect 2: SKILL_PR step 3b wording

- `.aai/SKILL_PR.prompt.md:163` says `Docs/test/evidence-only changes are
  exempt.` Since PR #517, `release-notes-gate.mjs` `isShipped` treats
  README.md, AGENTS.md, CLAUDE.md, CODEX.md, GEMINI.md, SKILLS.md,
  docs/USER_GUIDE.md and docs/product/** as shipped. That list is stated in
  docs/product/release-notes-gate.md.
- `.aai/SKILL_PR.prompt.md` is already a glob of the `aai-release-notes`
  suite in tests/skills/suite-map.yaml.
- The file is in the prompt corpus. Byte growth means a prompt-diet ledger
  entry is owed (PLANNING companion obligation 1). No new `.aai/**` file, so
  no PROFILES.yaml entry (obligation 2 does not apply).

### Defect 3: two false spec_amendment statements

Each claim was checked against the spec file and the review:

- (a) `docs/ai/decisions.jsonl` line 2545, ts `2026-10-29T21:38:47Z`,
  ref `watch-ci-cancelled-runs-and-release-gate-docs`. Its `why` field says
  the re-read (NB-1) and the docs fix (NB-3) are "both outside the frozen file
  list". This is false for NB-1. SPEC-0261 "Files Implementation touches"
  lists `.aai/scripts/lib/github-checks.mjs`,
  `tests/skills/lib/current-head-ci.test.mjs` and
  `tests/skills/test-aai-current-head-ci.sh`. Only `docs/USER_GUIDE.md` was
  outside the list. The same wording appears in two other places: the
  companion follow_up `fu-amend-watch-ci-cancelled-runs-f5717d` (line 2546,
  same ts), and the spec's own Amendment section ("Files touched beyond the
  list above: docs/USER_GUIDE.md and the TEST-2711 test.").
- (b) Line 2541, ts `2026-10-29T18:07:55Z`, ref
  `docs-audit-content-engine-split`. Its `why` field credits "Validation r2
  NB-2". SPEC-0260 A1-n says the same and also says `tests/skills/suite-map.yaml`
  "was edited outside the original file list". Both statements are false. SPEC-0260
  "Files Implementation touches" lists `tests/skills/suite-map.yaml`. The
  finding is NB-2 of code review r2:
  docs/ai/reviews/review-docs-audit-content-engine-split-r2-20261029T180433Z.md,
  "NB-2 (new): content-only globs left on the engine row". Not verified here:
  that Validation r2 has no NB-2. Code review r3 says so, and the validation
  report is gitignored and absent from this checkout.
- The two record types the ledger readers fold for amendments are
  `spec_amendment` and `spec_amendment_classification` (spec-amend.mjs). For
  follow-ups they are `follow_up` and `follow_up_status` (follow-ups.mjs).
  No reader folds a correction of a record's `what`/`why` text:
  - A new `spec_amendment` would be a new amendment and would make a new
    `fu-amend-*` tracker.
  - A classification overlay can only move sign-off, class or tracker.
  - `follow-ups close --correct` can only fix a close's resolver.
  The house precedent for correcting a false ledger statement is an inert
  `process_finding` record whose `finding` begins "correction to ..." and
  which carries `detail` (ledger lines 202, 232, 234; line 232 also carries
  `relates_to` and `source`). No script reads `process_finding`. This spec
  uses that shape. It does not invent one that a reader would have to fold.

## Decisions

- D1 Refresh on the re-read. The second `readCheckRuns` call (made only when
  read 1 saw a cancelled run) re-fetches `actions/runs/<id>` for every run
  it meets, cached or not. Its call site is literally `readCheckRuns(true)`.
  The first call and the no-cancellation path stay as they are: one fetch per
  run and zero run-list calls (SPEC-0261 Spec-AC-04 is unchanged).
- D2 Identity is immutable. On refresh, `created_at`, `workflow_id` and
  `event` must equal the first read. Otherwise the reader refuses with
  `workflow identity moved during observation`. Status and conclusion are the
  only fields allowed to move.
- D3 Supersession reads refreshed state. After the re-read, the cancelled set
  is every run whose refreshed conclusion is `cancelled`. A run cancelled on
  read 1 and re-run by read 2 is no longer cancelled, so it is judged by its
  own checks.
- D4 Newly cancelled with a sibling: a run that is cancelled on the re-read
  but was not cancelled on read 1 (including a run first seen on read 2)
  gets superseded exactly as a read-1 cancellation would. The sibling must be
  a newer run of the same workflow_id and event in the run list fetched
  before the re-read:
  - Sibling unfinished: the check is pending.
  - Sibling completed without the check: the check is dropped. In required
    mode that refuses with `required context missing`.
  - Sibling has its own copy of the check: that copy governs.
  This uses the same invariant as SPEC-0261's snapshot-skew fix. The run list
  comes before the check read the decision uses, so a sibling's checks are
  visible before anything is dropped.
- D5 Newly cancelled without a sibling: such a run refuses closed with the
  existing text `workflow state moved during observation` (watch-ci exit 3
  DEGRADED; the release reader throws). It does not keep its `cancel` bucket
  (exit 5). The sibling that cancelled it may have been created after the run
  list was read, so FAILED would be a guess. DEGRADED says the reader could
  not decide, and the next watch-ci run decides on a first read. A run that
  was already cancelled on read 1 with no sibling keeps its own bucket
  (SPEC-0261 Spec-AC-02, unchanged).
  Rejected: re-reading the run list after the re-read. Then the run list
  would postdate the check read, which reopens the NB-1 false-green window
  that SPEC-0261 closed. Rejected: keeping the `cancel` bucket. That is the
  spurious red this scope removes.
- D6 Cost: one extra `actions/runs/<id>` call per distinct run, only on the
  re-read path, which already runs only when a cancelled run was seen.
- D7 Prompt wording. Step 3b keeps its line structure and replaces the
  exemption sentence with one that names user-facing docs as shipped,
  points to `docs/product/release-notes-gate.md` for the exact list, and
  keeps tests, evidence and other docs exempt. Byte growth is at most 160 B
  and the file gains at most one line. The growth is credited 1:1 as one
  `JUSTIFIED_ADDITIONS` entry for this ref, and the TEST-012 checkpoint moves
  by the same amount.
- D8 Correction records. Two appended lines with this shape (key order as
  written, `JSON.stringify` serialisation, no spaces):
  `{"v":1,"ts":"<now>","actor":"implementation","type":"process_finding","ref_id":"<the corrected record's ref_id>","severity":"P3","finding":"correction to the <ts> spec_amendment record on <ref_id>","detail":"<the true facts from D8a or D8b>","relates_to":"docs/ai/decisions.jsonl ts=<ts> type=spec_amendment ref_id=<ref_id>","source":"<spec file list path>; <review path>"}`
  - D8a, ts `2026-10-29T21:38:47Z`, ref
    `watch-ci-cancelled-runs-and-release-gate-docs`. Detail states:
    - github-checks.mjs and both TEST-2711 files are on the SPEC-0261 file
      list, so the re-read (NB-1) was inside the frozen list;
    - only docs/USER_GUIDE.md (NB-3) was outside it;
    - the same false wording in follow_up
      `fu-amend-watch-ci-cancelled-runs-f5717d` (same ts) and in the spec's
      Amendment section is corrected by this record.
  - D8b, ts `2026-10-29T18:07:55Z`, ref `docs-audit-content-engine-split`.
    Detail states:
    - tests/skills/suite-map.yaml is on the SPEC-0260 file list, so A1-n's
      "outside the original file list" is false;
    - the finding is NB-2 of code review r2
      (review-docs-audit-content-engine-split-r2-20261029T180433Z.md), not
      Validation r2; this applies to both A1-n and this record.
  No existing ledger line is edited. The frozen, done specs SPEC-0260 and
  SPEC-0261 are not edited (their frozen hash and anchors stay intact); the
  ledger record is the correction of record.
- D9 Follow-up closes. Implementation runs the four
  `node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by watch-ci-reread-refresh-and-p3-cleanup --source <this spec path>`
  calls as its final step: after every TEST row is green and after the two
  correction records are appended. Not at PR time, for three reasons:
  - the ledger is branch-scoped, so the closes reach main only with the merge
    of the fix that justifies them;
  - Validation must observe Spec-AC-08 before the AC flip at close;
  - a decisions.jsonl write after the PR sweep invalidates the sweep's
    head_sha binding.
  If a later round reopens the github-checks fix, the same branch carries
  the remediation, so the close stays true at merge.
- D10 CHANGELOG. Both `.aai/scripts/lib/github-checks.mjs` and
  `.aai/SKILL_PR.prompt.md` are shipped surfaces, so the PR owes one
  `## [unreleased] — fix: ... (watch-ci-reread-refresh-and-p3-cleanup)`
  entry in CHANGELOG.md. The release-notes gate checks it at the PR
  ceremony. It is not an AC row.

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01. Verify with
  `bash tests/skills/test-aai-current-head-ci.sh test_2931`.
- Intake AC-002 maps to Spec-AC-02. Verify with `... test_2932`.
- Intake AC-003 maps to Spec-AC-03 (refresh contract, `... test_2933` and
  `... test_2934`) and Spec-AC-04 (no regression: the full current-head-ci
  suite, TEST-2711 kept).
- Intake AC-004 maps to Spec-AC-05 (wording,
  `bash tests/skills/test-aai-release-notes.sh test_2935`) and Spec-AC-06
  (governance, `bash tests/skills/test-aai-prompt-diet.sh`).
- Intake AC-005 maps to Spec-AC-07. Verify with
  `bash tests/skills/test-aai-spec-amend.sh test_2937_wcr_reread_corrections_on_live_ledger`
  plus the append-only check.
- Intake AC-006 maps to Spec-AC-08. Verify with
  `bash tests/skills/test-aai-follow-ups.sh test_2938_wcr_reread_followups_closed`
  plus `follow-ups.mjs verify-closures --strict --path <this spec>`.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the first check-run read shows run W in progress and the re-read (triggered by another run cancelled on read 1) shows W and its check cancelled, and the run list holds a newer run of W's workflow_id and event that is not completed, watch-ci --required SHALL report W's check pending (exit 3 at the deadline naming pending, output without degraded, never exit 5) and readReleaseRequiredChecks SHALL exit 0 returning bucket pending for that check. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2931.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2931.txt | — | — |
| Spec-AC-02 | WHEN the same mid-observation cancellation of W has no newer run of the same workflow_id and event in the run list (arm 1 no sibling, arm 2 only a newer run of another event), watch-ci --required SHALL exit 3 with a degraded line naming workflow state moved during observation and readReleaseRequiredChecks SHALL throw (exit 20 in the fixture); neither SHALL report pass and watch-ci SHALL NOT exit 5; WHEN W's newest sibling had completed before the run list without W's required check (arm 3), watch-ci --required SHALL exit 3 degraded and the release reader SHALL throw. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2932.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2932.txt | — | — |
| Spec-AC-03 | WHEN read 1 sees a cancelled run, the fixture call log SHALL show exactly two actions/runs/ID requests per distinct workflow run and one run-list request; WHEN no run is cancelled, exactly one per distinct run and zero run-list requests; WHEN the refreshed record of a run differs from read 1 in created_at, workflow_id or event, watch-ci SHALL exit 3 degraded naming workflow identity moved during observation and the release reader SHALL throw. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2933.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2933.txt; docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2934.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2934.txt | — | — |
| Spec-AC-04 | bash tests/skills/test-aai-current-head-ci.sh with no selector SHALL exit 0 with every pre-existing case (TEST-001 to TEST-004, TEST-2701 to TEST-2705, TEST-2711) unchanged and passing; TEST-2711 SHALL still observe watch-ci exit 5 and release bucket fail with id 2. | done | docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2711.txt | — | — |
| Spec-AC-05 | The step 3b block of .aai/SKILL_PR.prompt.md (from the line starting 3b. to the next numbered step) SHALL NOT contain the sentence Docs/test/evidence-only changes are exempt., SHALL name docs/product/release-notes-gate.md, SHALL state that user-facing docs are shipped and that tests, evidence and other docs are exempt; the file SHALL grow by at most 160 bytes and at most one line against the baseline commit. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2935.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2935.txt | — | — |
| Spec-AC-06 | tests/skills/lib/prompt-diet-ledger.sh SHALL carry exactly one JUSTIFIED_ADDITIONS entry naming watch-ci-reread-refresh-and-p3-cleanup whose leading byte count equals the measured .aai/SKILL_PR.prompt.md growth against the baseline commit, the TEST-012 pin SHALL move by that amount, and bash tests/skills/test-aai-prompt-diet.sh SHALL exit 0. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2936.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2936.txt | — | — |
| Spec-AC-07 | docs/ai/decisions.jsonl SHALL gain exactly two process_finding records whose finding starts correction to the 2026-10-29T21:38:47Z spec_amendment record and correction to the 2026-10-29T18:07:55Z spec_amendment record respectively, each with relates_to naming that ts, type spec_amendment and its ref_id, and detail naming the facts of D8a or D8b; the diff of that file against the base SHALL contain zero removed lines; node .aai/scripts/spec-amend.mjs list --strict SHALL exit 0 and its JSON item count SHALL equal the base ledger's. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2937.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2937.txt | — | — |
| Spec-AC-08 | node .aai/scripts/follow-ups.mjs list --status open SHALL NOT list fu-current-head-ci-reread-stale-cache, fu-skill-pr-3b-shipped-docs-wording, fu-amend-wcr-file-list-correction or fu-docs-split-a1n-attribution; each SHALL fold to status done with resolved_by watch-ci-reread-refresh-and-p3-cleanup; node .aai/scripts/follow-ups.mjs verify-closures --strict --path on this spec SHALL exit 0. | done | docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/red-test-2938.log; docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/mutation-TEST-2938.txt | — | — |

## Implementation plan

1. Reader (`.aai/scripts/lib/github-checks.mjs`):
   - `readCheckRuns(refresh)`: with `refresh` true, fetch each distinct run
     once per call even when cached. Check `head_sha` and id as today. Refuse
     on a changed `created_at`, `workflow_id` or `event` (D2), then overwrite
     status and conclusion. The re-read call becomes `readCheckRuns(true)`.
   - After the re-read, build the cancelled set from refreshed state (D3).
     Apply the existing malformed-identity check to every member.
   - Replace the line-162 blanket refusal: a newly cancelled run joins
     supersession (D4), and `workflow state moved during observation` fires
     only when it has no qualifying sibling in `listed` (D5).
   - Keep the lazy run-list fetch and the header comment truthful; add one
     header sentence for D3 to D5.
   - Update watch-ci.mjs's header comment only if it states the old rule.
2. Tests (`tests/skills/lib/current-head-ci.test.mjs`): extend the gh stub
   with a per-run response sequence for `actions/runs/<id>`, such as a
   `workflowSeq` map with a persisted per-id counter that clamps to its last
   element, the same way `checkSeq` does. Release-reader calls reset both
   counters, as TEST-2711 resets `crn`. Add cases TEST-2931 to TEST-2934.
   Register `test_2931` to `test_2934` in
   `tests/skills/test-aai-current-head-ci.sh` (functions and ALL_TESTS).
3. Prompt (`.aai/SKILL_PR.prompt.md` step 3b) per D7. Add a TEST-2935 node
   case in `tests/skills/lib/release-notes-docs.test.mjs` and `test_2935` in
   `tests/skills/test-aai-release-notes.sh`. Then measure the byte delta
   against `7d38415a`, append the ledger entry in
   `tests/skills/lib/prompt-diet-ledger.sh`, move the TEST-012 pin in
   `tests/skills/test-aai-prompt-diet.sh`, and add
   `test_2936_skill_pr_3b_growth_ledgered` there, following the shape of
   `test_697_corpus_growth_ledgered`.
4. Ledger: append the D8a and D8b records with `node -e` and
   `JSON.stringify` (one line each, appended, never through an editor). Add
   `test_2937_wcr_reread_corrections_on_live_ledger` to
   `tests/skills/test-aai-spec-amend.sh` and register it in main. It
   asserts:
   - both records are on the live ledger with the D8 fields;
   - `spec-amend.mjs list --json` gives the same item list on a scratch copy
     of the ledger with and without the two records (inert to the fold);
   - `list --strict` exits 0 on the live ledger.
5. Closes per D9, last. Add `test_2938_wcr_reread_followups_closed` to
   `tests/skills/test-aai-follow-ups.sh`. It asserts, through the real
   `follow-ups.mjs list --json`, that each of the four ids is done with
   resolved_by `watch-ci-reread-refresh-and-p3-cleanup`.
6. CHANGELOG.md: one `## [unreleased] — fix: ...` entry (D10). One sentence
   for the reader: a run cancelled while watch-ci is observing it no longer
   reports a false failure.

Edge cases: a run cancelled on read 1 and re-run by read 2 (D3); a newly
cancelled run first seen on read 2 (D4/D5, the same rule); several newly
cancelled runs of one workflow (newest-sibling rule unchanged); a refreshed
record that loses `head_sha` (existing head refusal).

## Seams crossed

- S1, shared reader to two consumers: TEST-2931, TEST-2932 and TEST-2934 run
  watch-ci.mjs as a CLI subprocess and `readReleaseRequiredChecks` from
  release-finish.mjs against the same gh stub. Neither consumer is mocked.
- S2, GitHub run model to reader: the stub serves sequenced `actions/runs/<id>`
  and `check-runs` responses, as GitHub would across the two reads. Residual
  risk: real GitHub ordering between run cancellation, the check-run
  conclusion and the run list cannot be replayed offline (SPEC-0261 r2
  cannot_verify, unchanged).
- S3, correction writer to amendment reader: TEST-2937 runs the real
  spec-amend.mjs over the live ledger and over a with/without copy.
- S4, close writer to registry reader and close gate: TEST-2938 reads through
  the real follow-ups.mjs. `verify-closures --strict` on this spec checks the
  spec's own "Registry items closed by this scope" claim against the same fold.
- S5, prompt bytes to diet ledger: TEST-2936 and the existing TEST-010 and
  TEST-012 measure the real file on disk.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2931 | Spec-AC-01 | integration | tests/skills/test-aai-current-head-ci.sh | test_2931 runs node:test case TEST-2931: run A of workflow 2 cancelled with an in-progress sibling; run W of workflow 5 in progress on read 1 and cancelled on the re-read (check-run and workflow sequences); run Y, newer than W in workflow 5, in progress in the run list; watch-ci --required exits 3 naming pending without degraded; the release reader returns bucket pending | `sed:s/readCheckRuns\(true\)/readCheckRuns()/` on .aai/scripts/lib/github-checks.mjs | green |
| TEST-2932 | Spec-AC-02 | integration | tests/skills/test-aai-current-head-ci.sh | test_2932 three arms of the same W cancellation: no workflow-5 sibling; only a newer workflow-5 run of another event; newest workflow-5 sibling completed without the check; each watch-ci --required exits 3 with degraded (arms 1 and 2 name workflow state moved during observation) and the release reader exits 20 | `sed:s/fail\('workflow state moved during observation'\)/void 0/` on .aai/scripts/lib/github-checks.mjs | green |
| TEST-2933 | Spec-AC-03 | integration | tests/skills/test-aai-current-head-ci.sh | test_2933 counts actions/runs/ID requests in the call log of one watch-ci poll: re-read fixture gives two per distinct run and one run-list call; all-success fixture gives one per run and zero run-list calls | `sed:s/readCheckRuns\(true\)/readCheckRuns()/` on .aai/scripts/lib/github-checks.mjs | green |
| TEST-2934 | Spec-AC-03 | integration | tests/skills/test-aai-current-head-ci.sh | test_2934 arms where the refreshed record changes created_at, workflow_id or event: watch-ci exits 3 naming workflow identity moved during observation and the release reader exits 20 | `sed:s/fail\('workflow identity moved during observation'\)/void 0/` on .aai/scripts/lib/github-checks.mjs | green |
| TEST-2711 | Spec-AC-04 | integration | tests/skills/test-aai-current-head-ci.sh | existing test_2711 kept unchanged: the sibling check registered between the snapshot and the run list is never dropped (watch-ci exit 5, release bucket fail id 2); the full suite run with no selector exits 0 | `sed:s/readCheckRuns\(true\);/void 0;/` on .aai/scripts/lib/github-checks.mjs | green |
| TEST-2935 | Spec-AC-05 | inspection | tests/skills/test-aai-release-notes.sh | test_2935 runs node:test case TEST-2935 in tests/skills/lib/release-notes-docs.test.mjs: slices the step 3b block of .aai/SKILL_PR.prompt.md; asserts the old exemption sentence is absent, docs/product/release-notes-gate.md is named, shipped user-facing docs and exempt tests and evidence are stated | `sed:s/docs\/product\/release-notes-gate\.md/docs\/product\/gone.md/` on .aai/SKILL_PR.prompt.md | green |
| TEST-2936 | Spec-AC-06 | inspection | tests/skills/test-aai-prompt-diet.sh | test_2936_skill_pr_3b_growth_ledgered asserts exactly one JUSTIFIED_ADDITIONS entry naming watch-ci-reread-refresh-and-p3-cleanup with a positive byte count equal to the SKILL_PR growth over the baseline blob; TEST-010 and TEST-012 stay green in the same suite run | `sed:s/"[0-9]+ watch-ci-reread-refresh-and-p3-cleanup/"0 watch-ci-reread-refresh-and-p3-cleanup/` on tests/skills/lib/prompt-diet-ledger.sh | green |
| TEST-2937 | Spec-AC-07 | integration | tests/skills/test-aai-spec-amend.sh | test_2937_wcr_reread_corrections_on_live_ledger asserts the two D8 records on the live ledger (finding prefix, relates_to, detail facts), spec-amend list --json identical on a scratch ledger with and without them, list --strict exit 0 on the live ledger | `sed:s/correction to the 2026-10-29T21:38:47Z/correction to the 2026-10-29T00:00:00Z/` on docs/ai/decisions.jsonl | green |
| TEST-2938 | Spec-AC-08 | integration | tests/skills/test-aai-follow-ups.sh | test_2938_wcr_reread_followups_closed asserts through follow-ups.mjs list --json that the four ids fold to done with resolved_by watch-ci-reread-refresh-and-p3-cleanup | `sed:s/"resolved_by":"watch-ci-reread-refresh-and-p3-cleanup"/"resolved_by":"other-ref"/` on docs/ai/decisions.jsonl | green |

RED plan:
- Observed failing on the baseline code before the change:
  - TEST-2931: exit 5 and bucket cancel on baseline.
  - TEST-2932 arms 1 and 2: exit 5 instead of 3, because the cache keeps W
    in progress.
  - TEST-2933 re-read arm: one fetch per run instead of two.
  - TEST-2934: no refresh, so no refusal.
  - TEST-2935: the old sentence is present.
  - TEST-2936 to TEST-2938: before their artifacts exist, each fails on the
    missing entry, record or close.
- TEST-2932 arm 3 also fails on the baseline (exit 5, W's check keeps bucket
  cancel). TEST-2711 passes on the baseline; its RED is the mutation record
  only.
- RED artifacts go to docs/ai/tdd/watch-ci-reread-refresh-and-p3-cleanup/.
  Mutation records go to docs/ai/tdd/spec-watch-ci-reread-refresh-and-p3-cleanup/.
- Mutations on docs/ai/decisions.jsonl run only in the isolated worktree, with
  no concurrent ledger writer. The mutation tool must restore the file
  byte-identically: verify with `git diff --stat` before and after each run.

## Verification

- Run with `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh` per suite, one
  per call: `aai-current-head-ci`, `aai-release-notes`, `aai-release`,
  `aai-release-first`, `aai-prompt-diet`, `aai-spec-amend`, `aai-follow-ups`,
  plus whatever `node .aai/scripts/select-suites.mjs` adds as CORE for the
  diff. Intermediate rounds run selected plus CORE. Run one full sweep before
  close (`AAI_TEST_TIMEOUT=3600`).
- `git diff 7d38415a -- docs/ai/decisions.jsonl` shows only added lines. Check
  it with `/usr/bin/grep -c '^-[^-]'` on the diff, which must print 0.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- `node .aai/scripts/follow-ups.mjs verify-closures --strict --path <this spec>`
  exits 0.
- `node .aai/scripts/spec-lint.mjs --path <this spec>` exits 0.
- `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exits 0 before
  close.
- PR ceremony: `release-notes-gate.mjs --staged` passes with the D10 CHANGELOG
  entry.
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Evidence contract

For each artifact, record the ref_id, the Spec-AC and TEST links, the command,
the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

hybrid: a stored RED artifact per AC-gating test under docs/ai/tdd/, a
mutation record per Test Plan row, and green suite outputs.

## Files Implementation touches

- .aai/scripts/lib/github-checks.mjs
- .aai/scripts/watch-ci.mjs (header comment only, if it states the old rule)
- .aai/SKILL_PR.prompt.md (step 3b only)
- tests/skills/lib/current-head-ci.test.mjs
- tests/skills/test-aai-current-head-ci.sh
- tests/skills/lib/release-notes-docs.test.mjs
- tests/skills/test-aai-release-notes.sh
- tests/skills/lib/prompt-diet-ledger.sh
- tests/skills/test-aai-prompt-diet.sh
- tests/skills/test-aai-spec-amend.sh
- tests/skills/test-aai-follow-ups.sh
- docs/ai/decisions.jsonl (append-only: two correction records, four close records)
- CHANGELOG.md
- docs/issues/CHANGE-DRAFT-watch-ci-reread-refresh-and-p3-cleanup.md
- docs/specs/SPEC-DRAFT-spec-watch-ci-reread-refresh-and-p3-cleanup.md
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

No new `.aai/**` file, so no PROFILES.yaml entry. Prompt-corpus growth is
folded per D7 (Spec-AC-06).

## Amendments (post-freeze, additive-with-disclosure)

- A1 (2026-10-30, Implementation): `tests/skills/test-aai-pr-preflight.sh`
  (TEST-008) is touched although it is not in the file list above. It pins the
  SKILL_PR.prompt.md byte growth and the `want_growth` sum, so the 72 B step-3b
  growth (Spec-AC-05/06) moves both pins by +72. No AC changes; signed by the
  owner's merge direction (`--signoff none`).

## Assumptions (autopilot, no owner question)

- A1. Correction record shape: no reader folds a text correction, so the inert
  `process_finding` precedent is the honest shape (What Planning measured,
  Defect 3).
- A2. D5 chooses refuse-closed (exit 3) over keeping the cancel bucket
  (exit 5) for a newly cancelled run with no sibling. Both are never-green.
  D5 gives the reasons.

## Risks and rollback

- Reader is shared by watch-ci and release finish. D4 reuses the SPEC-0261
  invariant (the run list precedes the deciding check read), so no new path
  to PASS is opened. Rollback means reverting github-checks.mjs and the four
  new cases.
- Residual (accepted): a sibling created after the run list still costs one
  DEGRADED watch-ci run (D5) rather than a pending read. It is never green.
- Residual: frozen SPEC-0260 and SPEC-0261 keep their false prose. The ledger
  correction records are the correction of record (D8).
- Mutations on the live ledger: worktree only (Isolation).

## Registry disposition

Related open items, left open:

- `fu-platform-adapter-watch-ci` (moving watch-ci onto lib/platform-adapter.mjs)
  and `fu-platform-adapter-skill-pr-release` (gh-only prompt mechanics) are
  different subjects.
- `fu-release-notes-heading-multiset` concerns audit accept multiplicity,
  which is untouched here.
- `fu-amend-watch-ci-cancelled-runs-f5717d` and
  `fu-amend-docs-audit-content-engine-split` await the owner's sign-off on
  those amendments. That sign-off is the owner's to give and is out of scope.

## Registry items closed by this scope

- fu-current-head-ci-reread-stale-cache
- fu-skill-pr-3b-shipped-docs-wording
- fu-amend-wcr-file-list-correction
- fu-docs-split-a1n-attribution

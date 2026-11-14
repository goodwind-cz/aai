---
id: spec-flush-drops-reopened-runs
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 7b9a1e1b10008c0dd46f53dae3d5c5fe809834847c58da9649164e265d2232d4
ceremony_level: 2
links:
  requirement: flush-drops-reopened-runs
  rfc: null
  pr: []
  commits: []
---

# A flush after a reopen writes the new runs as a continuation line and never deletes runs the ledger does not hold

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-flush-drops-reopened-runs.md
- Prior scopes this one changes (closed, not edited):
  - SPEC-0068 (metrics-flush --sweep): its crash-resume rule ("a ref already in
    the ledger and still in STATE is an interrupted flush") is narrowed by D1.
  - SPEC-0163 (metrics-flush-invalidates-pr-precondition): its ledger proof
    ("exactly one PASS entry for that scope on that day") is narrowed by D5 to
    one PASS entry per flush segment.
- Related reader: `.aai/scripts/ride-handoff.mjs` reconcile already refuses to
  clear origin runs that are not in the ledger (`origin_runs_not_in_ledger`).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: this is a data-integrity fix on a core telemetry path that ships
  downstream. Every behaviour below can be seen failing on the unchanged tree:
  the orchestrator's scratch repro (flush, set-focus, append-run, set-validation,
  flush) exits 0 with `RESUME CHANGE-0001: already in ledger — cleanup-only
  pass`, one ledger line and the new run gone. The intake's autopilot
  recommendation is tdd; it is a recommendation, not a recorded user choice.
  Proposed TDD runs (about three Spec-ACs each): run 1 Spec-AC-01..03 (the
  flush), run 2 Spec-AC-04 and Spec-AC-05 (the PR-gate seam and the incident
  recovery, which needs the fixed flush), run 3 Spec-AC-06 (product doc and
  CHANGELOG).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound fix on a shipping telemetry script plus an
  append to the shared METRICS ledger; the main checkout is shared with other
  sessions and holds uncommitted telemetry.
- User decision: worktree (already recorded in STATE before Planning)
- Base ref: origin/main at 1667981e
- Worktree branch/path: fix/flush-drops-reopened-runs at
  /Users/ales/Projects/aai-worktrees/flush-drops-reopened-runs
- Review required: true
- Review scope (explicit paths): .aai/scripts/metrics-flush.mjs;
  .aai/scripts/validation-waiver.mjs; tests/skills/test-aai-metrics.sh;
  tests/skills/test-aai-pr-waiver.sh; docs/ai/METRICS.jsonl (the one appended
  line only); docs/product/telemetry.md; CHANGELOG.md;
  docs/issues/ISSUE-DRAFT-flush-drops-reopened-runs.md;
  docs/specs/SPEC-DRAFT-spec-flush-drops-reopened-runs.md.

## Ceremony

Ceremony level 2. The change touches `.aai/scripts/metrics-flush.mjs` and
`.aai/scripts/validation-waiver.mjs`. Neither is in `protected_paths_l3` of
docs/ai/docs-audit.yaml (state engine, allocator, guards, WORKFLOW.md,
CONSTITUTION.md), and the fix does not need `state.mjs` or
`lib/state-engine.mjs`: the STATE cleanup keeps using the existing engine
calls. It is not L1 because it changes two scripts, a gate and a shared
ledger. No `.aai/*.prompt.md` and no new `.aai/**` file is touched
(`.aai/METRICS_FLUSH.prompt.md` does not describe the resume rule, and
`.aai/SKILL_PR.prompt.md` delegates the archive grammar to the script header),
so neither companion obligation applies.

## Decisions

### D1. Idempotence is keyed on runs, not on the ref

The resume test at `metrics-flush.mjs:1788`
(`if (inLedger.has(ref)) { toResume.push(entry); continue; }`) asks only
whether the ref has a summary line. It is replaced by a run-level test.

- Run identity: the tuple (role, model_id, started_utc, ended_utc) projected
  exactly as `buildEntry` writes it: `role` as read, `model_id` or the string
  `unknown` when absent, `started_utc` and `ended_utc` as strings or null. One
  helper, `runIdentity(run)`, computes it for both sides, so a STATE run and the
  ledger run that `buildEntry` wrote from it always compare equal.
- `ledgerRunCounts(metricsPath)` replaces `ledgerRefs(metricsPath)`. It reads
  every line `isMetricsFlushRecord` accepts, keyed on the exact `ref_id`, and
  returns for each ref the number of summary lines (`lines`) and a multiset of
  run identities (`counts`) over all of that ref's lines.
- `freshRuns(runs, counts)` walks the STATE runs in order against a copy of the
  multiset: a run whose identity still has a count left uses one up; every other
  run is fresh. A run held k times in STATE and j times in the ledger (j < k)
  yields k - j fresh copies. The multiset is the exact inverse of what
  `buildEntry` writes, so no run is counted twice and none is dropped; it is
  also what the first flush does with duplicated runs (it writes all of them).
- Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor
  a mutation to the code it writes, disclosed as a measurement amendment):
  - `const fresh = freshRuns(entry.runs, prior.counts);`
  - `if (fresh.length === 0) { toResume.push(entry); continue; }   // interrupted flush`
  - `work = { ...entry, runs: fresh, segment: prior.lines + 1 };`
  - `if (defaultReason === null) { toFlush.push(work); continue; }`

### D2. Three outcomes for a ref that already has a ledger line

1. No fresh run: the existing cleanup-only resume, byte-identical in STATE
   result, stdout and ledger to today (the crash-after-ledger case TEST-013 and
   TEST-107 pin). The `RESUME <ref>` line stays as it is.
2. Fresh runs, admitted: the entry goes through the same default gate and, under
   `--sweep`, the same sweep gate as any other entry, with ONLY the fresh runs.
   The flush appends one NEW summary line holding only the fresh runs, built by
   the unchanged `buildEntry` (cost, totals, reliability and
   verdict_after_last_implementer are computed over the fresh runs only). The
   whole STATE metrics entry for the ref is then removed (its other runs are
   already durable in the ledger) and the usual partial or full reset applies,
   exactly as for a first flush. The defaultReason check "no agent_runs
   recorded" never fires here because a continuation has at least one run.
3. Fresh runs, refused: nothing is appended and nothing in STATE changes for
   the ref: its metrics entry, its runs and the verdict blocks stay, and the ref
   does not enter `completedRefs`, so it triggers no reset. The SKIP line reads
   `SKIP <ref>: <k> agent_runs not in METRICS.jsonl kept in STATE (continuation of an earlier flush) — <gate reason>`,
   where the gate reason is the existing default or sweep refusal text.

This also removes the second half of the defect: today the resume branch runs
before the verdict and review gates and resets `last_validation` and
`code_review` for a ride that is still in progress.

### D3. The continuation marker

A continuation line carries one additive field, `flush_segment: <n>`, where n is
the number of summary lines the ref had before this flush plus 1 (so the first
continuation is 2). It is written after `verdict` (before `validation_waiver`
when that is present) and ONLY on continuation lines. First-flush lines are
built exactly as today, so every existing golden stays byte-identical. Readers
that do not know the field ignore it; `isMetricsFlushRecord` still accepts the
line because it carries `title`, `agent_runs`, `totals` and `verdict`.

### D4. Output

- The `Flushed: <ref> -> <metrics path>` line is unchanged for a continuation,
  so a caller filtering on `Flushed` sees it.
- One extra line follows the `verdict_basis` lines for each continuation:
  `  continuation: <ref> flush_segment <n> (<k> runs not in the ledger before this flush)`.
- `--dry-run`: a continuation is listed under `flush`, not under `resume`, and
  its planned entry in `entries` carries `flush_segment`. No new plan key.

### D5. The PR gate counts one PASS per flush segment

`validation-waiver.mjs` evaluateArchive refuses `archive_ledger_ambiguous`
when more than one same-day PASS line names the archived ref. After this fix a
same-day reopen that ends in a partial reset legitimately leaves two such lines
(segment 1 and segment 2), and the gate would refuse a ride that today opens
with `validation_archived_pass`. That is a regression this scope would create,
so it is fixed here:

- `readArchiveLedger` also returns `flush_segment` (the line's integer value
  when it is an integer of at least 1, else 1).
- evaluateArchive keeps the zero-hit refusal (`archive_no_ledger_pass`) and
  refuses `archive_ledger_ambiguous` only when two hits carry the same segment
  value. Planned anchor: `const segs = hits.map((e) => e.flush_segment);` and
  `if (new Set(segs).size !== segs.length) return { open: false, reason: 'archive_ledger_ambiguous', archive_ref: rec.ref };`.
- A byte-for-byte duplicated line (pr-waiver TEST-12(d)) still refuses: both
  copies have segment 1. Distinct segments of one ref are flushes of one ride,
  so which ride is proven stays decidable, which is the reason the refusal
  exists. The header comment's "exactly one" sentence is updated to match.

### D6. No append-only run spool

Not needed. The cause is the flush's ref-keyed idempotence, not where runs are
stored. Runs already live in STATE from `append-run` until a flush; STATE is
written only by the transactional engine, a crash between ledger append and
STATE commit already leaves STATE original, and merge-cleanup archives a
worktree STATE before removing it. After D1 and D2 the flush is the only
deleter of runs, and it deletes a run only after that run is durable in the
ledger (ledger-before-reset ordering is unchanged). A spool would add a second
store, a second writer and a reconciliation problem for no loss path that
remains. The one remaining path where reopened runs do not reach the ledger is
dispatch rule 14 reporting `already_flushed` (R1); there the runs stay in STATE
and are written by the next flush, so it strands runs but does not delete them.

### D7. Fixtures whose pre-existing summary holds no runs

Two existing fixtures model a resume with a pre-existing summary line whose
`agent_runs` is empty while STATE holds runs:
`test_013_legacy_timestamp_summary_is_cleanup_only` in
tests/skills/test-aai-metrics.sh (four STATE runs, `agent_runs: []`) and
`MK_RESUME=cheat` in tests/skills/test-aai-pr-waiver.sh (one STATE run,
`agent_runs: []`, used by TEST-17(d)). Under D1 those runs are not in the
ledger, so these are no longer resumes. Both arms test the resume lane (the
first: that a historical UTC-timestamp `date_utc` is recognised as a summary;
the second: that a resume without sweep or crash mints no archive record). The
fixture is adjusted so the pre-existing summary holds the STATE runs (role,
model_id, started_utc, ended_utc copied from the STATE fixture), keeping
everything else, including the historical timestamp and the same-day date. The
assertions stay as they are. The old fixture shape (a summary with no runs and
STATE runs) is then pinned by Spec-AC-01 as a continuation.

### D8. Recovery of the incident's 11 runs

The ride `consumer-config-routing-override` (PR #555, not merged) lost 11 runs
at the 2026-11-14T12:19:11Z flush. They are rebuilt from the ride
orchestrator's transcript: every `state.mjs append-run` command line (role,
model, tokens_total, requested and actual model, effort, prompt hash, verdict,
note) and its stdout (`duration_seconds=N (ended_utc self-stamped T)`).
`state.mjs` computes the duration from the second-precision ended stamp and the
given start (`Math.round((Date.parse(ended) - Date.parse(started)) / 1000)`),
so started_utc = ended_utc - duration_seconds exactly. Nothing else is
estimated; tokens_in and tokens_out stay null because they were never recorded.

Reconstruction table (the source of truth for Spec-AC-05):

| Run | Role | model_id | started_utc | ended_utc | duration_seconds | tokens_total | prompt_hash | verdict |
|-----|------|----------|-------------|-----------|------------------|--------------|-------------|---------|
| R01 | Planning | claude-opus-5-5 | 2026-11-14T06:17:03Z | 2026-11-14T06:31:04Z | 841 | 234771 | absent | none |
| R02 | TDD Implementation | claude-sonnet-5-5 | 2026-11-14T06:31:10Z | 2026-11-14T06:41:39Z | 629 | 132381 | 052efe031096 | none |
| R03 | TDD Implementation | claude-sonnet-5-5 | 2026-11-14T06:41:43Z | 2026-11-14T06:51:24Z | 581 | 152959 | 052efe031096 | none |
| R04 | TDD Implementation | claude-sonnet-5-5 | 2026-11-14T06:51:28Z | 2026-11-14T07:06:41Z | 913 | 153887 | 052efe031096 | none |
| R05 | Validation | claude-opus-5-5 | 2026-11-14T07:24:33Z | 2026-11-14T07:59:46Z | 2113 | 244815 | 6267e8d79157 | fail |
| R06 | Remediation | claude-sonnet-5-5 | 2026-11-14T07:59:46Z | 2026-11-14T08:23:07Z | 1401 | 80793 | ec58355ece5e | none |
| R07 | Validation | claude-opus-5-5 | 2026-11-14T08:23:13Z | 2026-11-14T08:55:10Z | 1917 | 155399 | 6267e8d79157 | pass |
| R08 | Code Review | claude-opus-5-5 | 2026-11-14T08:55:12Z | 2026-11-14T09:03:25Z | 493 | 195619 | 8e6aae0d5197 | fail |
| R09 | Remediation | claude-sonnet-5-5 | 2026-11-14T11:18:52Z | 2026-11-14T11:35:10Z | 978 | 114859 | ec58355ece5e | none |
| R10 | Validation | claude-opus-5-5 | 2026-11-14T11:35:23Z | 2026-11-14T12:09:55Z | 2072 | 186882 | 6267e8d79157 | pass |
| R11 | Code Review | claude-opus-5-5 | 2026-11-14T12:09:56Z | 2026-11-14T12:18:56Z | 540 | 146785 | 8e6aae0d5197 | pass |

Sum of tokens_total 1799150; sum of duration_seconds 12478. Every run was
recorded with `--harness claude`, `--requested-model` and `--actual-model`
equal to model_id, `--requested-effort` high (opus) or medium (sonnet) and
`--effort-applied param`; the notes are copied verbatim from the command lines
(for example `owner extension re-plan usage_total_tokens=234771`, `VERDICT:
FAIL extension round usage_total_tokens=244815`). "verdict none" means the
command passed no `--verdict`. Where the full command lines live: the ride
orchestrator's session transcript; the subagent transcript
`agent-a2a86f1e7b064ff89.jsonl` of session 2071b3a2 holds a verbatim extract of
all eleven commands and their stdout (the orchestrator's pointer
`tool-results/bx4dqn140.txt` holds them truncated at 400 characters, so the
flags are read from the subagent extract).

Procedure (Implementation, run 2):

1. In one scratch directory S under the session scratchpad (HAZ-SCRATCH),
   build S/docs/ai/METRICS.jsonl from a comment header plus the ref's
   first-close summary line read with
   `git show origin/change/consumer-config-routing-override:docs/ai/METRICS.jsonl`
   (read-only; never check out or touch that branch or its worktree), and copy
   the ride's intake doc from the same branch to the path its
   `primary_path` names under S so `titleFor` resolves the same title.
2. Write S/docs/ai/STATE.yaml as a fixture file, the way the suites' fixtures
   are written (it is a scratch input, not docs/ai/STATE.yaml, and
   `state.mjs append-run` cannot be used because it self-stamps ended_utc from
   the clock). From the transcript: focus and work item for the ref,
   `implementation_strategy` selected tdd, `code_review` required true and
   status pass, `last_validation` pass naming the ref with run_at_utc
   2026-11-14T12:09:56Z (the set-validation result's own timestamp, truncated
   to the second), the per-ref validation pass that `set-validation --ref`
   stamps, and the 11 runs of the table with exactly the fields append-run
   would have written from those command lines. `check-state.mjs` must pass on
   it before the flush runs. The fixture is saved with the evidence.
3. Run the FIXED flush with cwd S:
   `node <worktree>/.aai/scripts/metrics-flush.mjs --state S/docs/ai/STATE.yaml --metrics S/docs/ai/METRICS.jsonl --ticks S/docs/ai/LOOP_TICKS.jsonl --pricing <worktree>/.aai/system/PRICING.yaml --events S/docs/ai/EVENTS.jsonl --now 2026-11-14T12:19:11Z`.
   The pinned instant is the lossy flush's own, so `date_utc` is 2026-11-14,
   the day the line should have been written. Expect `Flushed:` and
   `continuation: consumer-config-routing-override flush_segment 2 (11 runs ...)`.
4. Take the appended line, add `reconstructed: {source, reason}` as the last
   key with a JSON parse and stringify (no other change), and append it with a
   trailing newline to docs/ai/METRICS.jsonl in the worktree. `source` names the
   transcript and the spec table; `reason` names the 2026-11-14T12:19:11Z
   resume deletion and this ref (flush-drops-reopened-runs). Save the scratch
   flush output, the raw line and the committed line under
   docs/ai/tdd/flush-drops-reopened-runs/ as evidence.

On main the ref's first-close line arrives with PR #555. The two PRs append to
an append-only ledger, so after both merge the reconstructed line may sit
before or after the first-close line; every reader in D9 is order-independent.

### D9. Readers of a ledger with two summary lines for one ref

Measured on this tree; no ref on main has two summary lines today.

- generate-overview `tokensByRef` and effort sums: summed per ref across lines;
  correct, no double count (a continuation holds only new runs).
- docs-audit-core `readMetricsFlushes`: keeps the latest date per ref; correct.
- ride-handoff reconcile `ledgerKeys`: unions run keys across all lines of the
  ref; a continuation makes more origin runs reconcilable, never fewer.
- validation-waiver archive lane: fixed in D5 (in scope, it would regress).
- orchestration-dispatch `flushed` probe (rule 14 and rule 4a): true when any
  summary line names the focus ref, so a reopened ride with new runs reads as
  already flushed and rule 14 does not dispatch a flush. Out of scope (R1).
- generate-factory-report per-ride rows, metrics-report per-item rows and
  per-strategy reliability, golden-flow tokens_median_last10: one row per
  ledger line, so a reopened ride shows as two rows. Totals stay correct; ride
  counts and per-ride medians shift. Out of scope (R2).

## Acceptance Criteria Mapping

- Maps to: intake Expected Behavior bullet 1 (cleanup-only only when every run
  is in the ledger, byte-identical) to Spec-AC-03; bullet 2 (new runs go
  through the gates and land as a new line with only those runs) to
  Spec-AC-01; bullet 3 (refused runs stay in STATE with a SKIP) to Spec-AC-02;
  the regression the fix would create at the PR gate to Spec-AC-04; intake
  Constraints "recovery of the incident's 11 runs" to Spec-AC-05; the
  consumer-visible change to Spec-AC-06.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a ref already has a summary line in METRICS.jsonl and its STATE metrics entry holds agent_runs that no ledger line of that ref holds (run identity role, model_id or unknown, started_utc, ended_utc, counted as a multiset) and the default gate admits the ref, metrics-flush SHALL exit 0, append exactly one new summary line whose agent_runs are exactly the fresh runs in STATE order and which carries flush_segment equal to the prior line count plus 1, leave every earlier ledger byte unchanged, remove the ref from STATE metrics, print a Flushed line and a continuation line for the ref and print no RESUME line for it; --dry-run SHALL list the ref under flush and not under resume | planned | — | — | D1, D2 outcome 2, D3, D4 |
| Spec-AC-02 | WHEN fresh runs exist for a ref that has a ledger line and neither the default gate nor, under --sweep, the sweep gate admits it, metrics-flush SHALL exit 0, append nothing, leave STATE byte-identical (no metrics removal, no partial or full reset) and print a SKIP line for the ref that names the number of runs not in METRICS.jsonl and the gate reason | planned | — | — | D2 outcome 3 |
| Spec-AC-03 | WHEN every STATE run of a ref is already held by that ref's ledger lines, metrics-flush SHALL take the existing cleanup-only resume, and a crash-after-ledger resume SHALL leave the same STATE bytes, ledger bytes and Flushed-free RESUME output as a flush that never crashed; the existing resume tests (metrics TEST-013 crash resume, TEST-107, the historical-timestamp arm with its D7 fixture, pr-waiver TEST-17 c d e with the D7 fixture) SHALL pass with no golden edited | planned | — | — | D2 outcome 1, D7 |
| Spec-AC-04 | WHEN a ride is flushed, reopened, given a new run and a validation pass, and flushed again on the same UTC day with a partial reset, validation-waiver.mjs --state SHALL exit 0 with reason validation_archived_pass; two same-day PASS lines for the archived ref with the same flush_segment value (absent counts as 1) SHALL still refuse with archive_ledger_ambiguous | planned | — | — | D5; seam flush to PR gate |
| Spec-AC-05 | docs/ai/METRICS.jsonl SHALL end with exactly one appended line for consumer-config-routing-override whose agent_runs equal the D8 table in order on role, model_id, started_utc, ended_utc, duration_seconds, tokens_total, prompt_hash and verdict, with tokens_in and tokens_out null, tokens_total summing to 1799150, flush_segment 2 and a reconstructed object with non-empty source and reason; every byte before it SHALL equal origin/main's file, and the line without reconstructed SHALL deep-equal the line the fixed flush wrote in the scratch reconstruction | planned | — | — | D8; HAZ-LEDGER |
| Spec-AC-06 | docs/product/telemetry.md SHALL describe the continuation line, flush_segment and the SKIP that keeps refused runs in STATE, and CHANGELOG.md SHALL hold exactly one per-entry heading for this fix in the form unreleased or a rolled vYYYY.MM.DD, followed by an em dash and fix | planned | — | — | Consumer-visible; ships downstream through aai-sync |

## Implementation plan

Components:
- `.aai/scripts/metrics-flush.mjs`
  - `runIdentity`, `ledgerRunCounts`, `freshRuns` (D1) next to the current
    `ledgerRefs`, which is removed (its only caller is `main`).
  - `main` loop: the `inLedger.has(ref)` line becomes the D1 anchor block; the
    continuation `work` entry replaces `entry` on the `toFlush.push` lines of
    both the default and the sweep lane; every `skipped[ref] = ...` for a ref
    with a prior line gets the D2 outcome 3 prefix (one small helper).
  - `buildEntry`: `if (entry.segment !== undefined) ledgerEntry.flush_segment = entry.segment;`
    placed right after the `verdict` key (D3).
  - Report: the D4 continuation line; `--dry-run` unchanged in shape.
  - Header comment: the IDEMPOTENT RESUME paragraph and the archive-eligibility
    comment ("the RESUME branch takes the mere PRESENCE of a ledger line") are
    rewritten to the run-level rule.
- `.aai/scripts/validation-waiver.mjs`: D5 (`readArchiveLedger`,
  `evaluateArchive`, header sentence).
- `tests/skills/test-aai-metrics.sh`: new functions for TEST-3720..3723,
  TEST-3726, TEST-3727; D7 fixture change in
  `test_013_legacy_timestamp_summary_is_cleanup_only`; registered in the
  suite's main.
- `tests/skills/test-aai-pr-waiver.sh`: TEST-3724 is the D7 change to the
  `MK_RESUME=cheat` fixture; TEST-3725 a new arm.
- `docs/ai/METRICS.jsonl`: one appended line (D8).
- `docs/product/telemetry.md`, `CHANGELOG.md`.

Data flow: `state.mjs append-run` writes runs into STATE; `metrics-flush`
compares them with the ledger multiset, appends a first or continuation line,
then removes the STATE entry and resets; `validation-waiver` reads the ledger
lines and the archive record the reset wrote; overview, docs-audit,
ride-handoff and the reports read the ledger.

Edge cases:
- A legacy summary line with `agent_runs: []` (or none) and STATE runs: the runs
  are fresh, so they flush as a continuation when admitted. Writing them is the
  no-loss choice; the legacy line carries no run of its own to double-count.
- A STATE run without `model_id`: its identity uses `unknown`, as `buildEntry`
  writes it.
- A ref whose STATE entry holds both already-flushed runs and fresh runs (a
  crash, then more runs): the continuation holds only the fresh runs and the
  whole entry is removed once it is durable.
- `--ref <id>` restriction and the `--ref`-not-a-candidate refusal: unchanged.
- `--retire` and `--release`: branch before the loop, unchanged.
- Tests that run metrics-flush from the shipping tree regenerate the tracked
  overview files (registry `fu-recheck-tests-regen-shipping-overview`); never
  stage docs/ai/overview-data.json or docs/ai/overview.html from this ride.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3720 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | the intake repro with the real CLIs: flush a validated ref, state.mjs set-focus, append-run Validation with verdict pass, set-validation pass naming the ref, flush again; asserts exit 0, two summary lines, line 1 bytes unchanged, line 2 agent_runs is exactly the new run with flush_segment 2, line 1 has no flush_segment, STATE has no entry for the ref, stdout has the Flushed and continuation lines and no RESUME line | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(fresh.length === 0\)/if (true)/` sends every in-ledger ref back to the cleanup-only resume and the case must fail | green |
| TEST-3721 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | three arms: STATE holds two runs already in the ledger plus one new run, so the continuation holds only the new one; STATE holds one run twice while the ledger holds it once, so the continuation holds one copy; a historical summary with agent_runs empty plus four STATE runs flushes them as segment 2; --dry-run of the first arm lists the ref under flush, not resume, with flush_segment in entries | target `.aai/scripts/metrics-flush.mjs`; `sed:s/runs: fresh,/runs: entry.runs,/` re-appends the first-flush runs and the case must fail | green |
| TEST-3722 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | reopened ref with a new run and last_validation fail, then a second fixture with validation pass but code_review required and not_run, then the same under --sweep with the item not done: each exits 0, ledger byte-identical, STATE byte-identical by cmp, stdout has SKIP for the ref naming 1 agent_runs not in METRICS.jsonl kept in STATE and the gate reason, and no Partial-flush or Full reset line | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(defaultReason === null\) \{ toFlush.push\(work\)/if (true) { toFlush.push(work)/` flushes a refused continuation and the case must fail | green |
| TEST-3723 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh | same fixture flushed twice in separate repos, once cleanly and once crashed after the ledger then resumed; the resumed repo's STATE and ledger are byte-identical to the clean repo's and its stdout holds RESUME and no Flushed line; then runs the D7-adjusted historical-timestamp arm and asserts one ledger line and a cleaned STATE | target `.aai/scripts/metrics-flush.mjs`; `sed:s/const fresh = freshRuns\(entry.runs, prior.counts\);/const fresh = entry.runs;/` turns the crash resume into a duplicate line and the case must fail | green |
| TEST-3724 | Spec-AC-03 | integration | tests/skills/test-aai-pr-waiver.sh | TEST-17 arms c, d and e with the D7 cheat fixture (the same-day line now holds the STATE run): each still takes the RESUME branch, appends nothing and reaches the gate with the same verdict as before | target `.aai/scripts/metrics-flush.mjs`; `sed:s/const fresh = freshRuns\(entry.runs, prior.counts\);/const fresh = entry.runs;/` makes the cheat arm append a line and its premise must fail | green |
| TEST-3725 | Spec-AC-04 | integration | tests/skills/test-aai-pr-waiver.sh | real flush of ARCH-1 with HOLD_REF in progress, then state.mjs append-run and set-validation pass for ARCH-1, then a real flush one hour later on the same day; asserts two same-day PASS lines with segments 1 and 2, the archive record at the second flush instant, and validation-waiver.mjs --state exits 0 with validation_archived_pass; a control appends a byte copy of the segment-2 line and the gate refuses archive_ledger_ambiguous | target `.aai/scripts/validation-waiver.mjs`; `sed:s/if \(new Set\(segs\).size !== segs.length\)/if (hits.length > 1)/` restores the old count and the case must fail | green |
| TEST-3726 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh | reads the real docs/ai/METRICS.jsonl: exactly one line for consumer-config-routing-override carries reconstructed with non-empty source and reason; its eleven runs match the D8 table field by field in order, tokens_in and tokens_out are null, tokens_total sums to 1799150, flush_segment is 2; and none of its run identities appears in another line for the ref | target `docs/ai/METRICS.jsonl`; `sed:s/"tokens_total":80793/"tokens_total":80794/` breaks the R06 row and the sum and the case must fail | green |
| TEST-3727 | Spec-AC-06 | unit | tests/skills/test-aai-metrics.sh | CHANGELOG.md holds exactly one heading matching an unreleased or vYYYY.MM.DD bracket, an em dash and fix: naming the reopened-ride flush; docs/product/telemetry.md mentions flush_segment and that refused runs are kept in STATE | target `CHANGELOG.md`; `sed:s/## \[unreleased\] — fix: a flush after a reopen/## [unreleased] — fix: x/` removes the named heading and the case must fail | green |

Seams crossed (each by a real producer and a real reader):
- `state.mjs append-run` / `set-validation` (producer) to `metrics-flush.mjs`
  gate and ledger writer (reader): TEST-3720 and TEST-3725 drive both CLIs; no
  hand-written STATE for the reopen.
- `metrics-flush.mjs` ledger line plus archive record (producer) to
  `validation-waiver.mjs` gate (reader): TEST-3725 runs the real gate on what
  the real second flush wrote.
- `metrics-flush.mjs` ledger (producer) to `metrics-flush.mjs` resume test
  (reader, next run): TEST-3721 and TEST-3723.
- The incident's transcript (producer) to the real ledger (reader: every suite
  that reads docs/ai/METRICS.jsonl): TEST-3726 plus the Verification list.
- Not crossed by a test: dispatch rule 14 `already_flushed` (R1) and the
  per-line report readers (R2).

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root.

1. RED before GREEN per TDD run: `docs/ai/tdd/flush-drops-reopened-runs/red-<run>.log`
   and `green-<run>.log`. RED for TEST-3720 is the intake repro on the
   unchanged tree (ledger 1 line, RESUME line).
2. `bash tests/skills/test-aai-metrics.sh` and
   `bash tests/skills/test-aai-pr-waiver.sh` exit 0, with no golden edited
   beyond the two D7 fixtures.
3. Suites that read the real ledger or the flush, all exit 0:
   test-aai-pricing.sh, test-aai-factory-report.sh, test-aai-dashboard.sh,
   test-aai-hygiene-pack.sh, test-aai-reconcile-telemetry.sh,
   test-aai-token-capture.sh, test-aai-model-effort.sh,
   test-aai-merge-cleanup.sh, test-aai-docs-audit.sh,
   `node --test tests/skills/lib/ride-handoff.test.mjs`, plus CORE.
4. Mutation records for TEST-3720..3727 under
   `docs/ai/tdd/spec-flush-drops-reopened-runs/` via `mutation-run.mjs`.
5. Recovery evidence (D8 step 4): the scratch flush stdout, the raw line and
   the committed line; a node one-liner proving deep-equality without the
   `reconstructed` key; `git diff origin/main -- docs/ai/METRICS.jsonl` showing
   one added line and no removed line.
6. `node .aai/scripts/docs-audit.mjs --gate spec-flush-drops-reopened-runs` and
   `--ac-flip-check` exit 0 before hand-off.
7. One full sweep at final validation with `AAI_TEST_TIMEOUT=3600`.
8. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id flush-drops-reopened-runs, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs under docs/ai/tdd/flush-drops-reopened-runs/,
mutation records under docs/ai/tdd/spec-flush-drops-reopened-runs/, recovery
evidence under docs/ai/tdd/flush-drops-reopened-runs/reconstruction/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Registry items closed by this scope

none. Checked `follow-ups.mjs list` (329 open). Adjacent and NOT closed:
`fu-sweep-ignores-reopen` (the sweep's close predicate ignores a later reopen;
this scope does not change that predicate, a continuation passes the same sweep
gate as any entry), `fu-4b-item-absent-with-runs-wedge` (rule 4b dispatch, not
the flush), `fu-recheck-tests-regen-shipping-overview` (noted under edge cases;
the new tests inherit it).

Suggested follow-ups (not filed by Planning):
- suggested: `fu-dispatch-flushed-probe-ref-keyed` (R1).
- suggested: `fu-ledger-readers-fold-flush-segments` (R2).

## Residual risks

- R1. orchestration-dispatch's `flushed` probe is still keyed on the ref. A
  reopened ride whose new runs are in STATE reads as flushed: rule 14 returns
  `already_flushed` and does not dispatch a flush, and rule 4a can retarget away
  once the item is done. The runs are no longer deleted; they stay in STATE
  (and in merge-cleanup's archived worktree STATE) until a flush runs, and the
  fixed flush writes them. Fixing the probe needs the run identity in the
  dispatcher's snapshot; follow-up.
- R2. Per-line ledger readers (factory report per-ride rows, metrics-report
  per-item rows and per-strategy reliability, golden-flow medians) count a
  continuation as another ride. Totals stay correct; ride counts and medians
  shift by one row per reopened ride. Follow-up: fold lines with
  `flush_segment` into their ride.
- R3. PR #555's branch still carries the old flush. Any flush in that worktree
  after further append-run calls deletes those runs the same way until the
  branch is rebased onto this fix. Only the 11 runs between 06:17Z and 12:19Z
  are reconstructed here; later losses would need their own reconstruction.
- R4. If PR #555 is closed without merging, main holds a `flush_segment: 2`
  line with no segment 1 for the ref. Readers do not depend on segment 1.
- R5. The reconstruction depends on transcript text; the D8 table is the
  committed record of what was read, and TEST-3726 pins the ledger to it. The
  reconstructed line's cost uses PRICING.yaml at reconstruction time, the
  same as any flush on that day.
- R6. A ledger line written by a hand flush with different field names (for
  example `model` instead of `model_id`) does not match its STATE run, so a
  STATE still holding such runs would flush them again as a continuation. No
  current writer produces such lines; the old hand-flush era predates
  metrics-flush and its STATE entries are gone.

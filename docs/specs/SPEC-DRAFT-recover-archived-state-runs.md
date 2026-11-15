---
id: spec-recover-archived-state-runs
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: a73e33197669979634f10ddefe3528e5d3040edc5fac2c7707a052650b4eeb99
ceremony_level: 2
links:
  requirement: recover-archived-state-runs
  rfc: null
  pr: []
  commits: []
---

# Role runs held only by archived STATE copies are recovered into METRICS as historical lines that no gate reads as a PASS

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-recover-archived-state-runs.md
  (follow-up `fu-archived-state-runs-not-in-ledger`, P2).
- Prior scope this one builds on (closed, not edited):
  docs/specs/SPEC-0291-spec-flush-drops-reopened-runs.md (PR #556): run-level
  resume (`runIdentity`, `ledgerRunCounts`, `freshRuns`), the `flush_segment`
  continuation line, the `reconstructed: {source, reason}` line shape, and
  `foldRideSegments` in `.aai/scripts/lib/metrics-flush-record.mjs`.
- Related reader: `.aai/scripts/ride-handoff.mjs` reconcile keys a run on role
  and started_utc (`ledgerKeys`), the precedent for D2.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: this adds a writer to the shared METRICS ledger and changes four
  readers that feed gates (docs-audit delivery evidence, dispatch rule 14) and
  reports (the ride fold, golden-flow). Every behaviour below can be seen
  failing on the unchanged tree: `--recover-archives` is an unknown flag
  (exit 2), and a hand-appended verdict-null `reconstructed` line already
  counts as delivery evidence in docs-audit, as "flushed" in dispatch, and
  overwrites a delivered ride's PASS verdict in the fold. The intake's
  autopilot recommendation is tdd; it is a recommendation, not a recorded user
  choice (STATE holds `implementation_strategy.selected: undecided`).
  Proposed TDD runs (about three Spec-ACs each): run 1 Spec-AC-01..04 (the
  command), run 2 Spec-AC-05..08 (the flush, PR-gate, docs-audit and dispatch
  seams), run 3 Spec-AC-09..11 (the fold, golden-flow, ride-handoff), run 4
  Spec-AC-12 and Spec-AC-13 (the real recovery run, product doc, CHANGELOG).

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a shipping telemetry script and an
  append of 65 lines to the shared METRICS ledger; the main checkout is shared
  with other sessions and is the read-only source of the archives.
- User decision: worktree (already recorded in STATE before Planning)
- Base ref: origin/main at 5bbc129e
- Worktree branch/path: fix/recover-archived-state-runs at
  /Users/ales/Projects/aai-worktrees/recover-archived-state-runs
- Review required: true
- Review scope (explicit paths): .aai/scripts/metrics-flush.mjs;
  .aai/scripts/lib/metrics-flush-record.mjs;
  .aai/scripts/lib/docs-audit-core.mjs;
  .aai/scripts/orchestration-dispatch.mjs; .aai/scripts/golden-flow.mjs;
  tests/skills/test-aai-metrics.sh; tests/skills/test-aai-pr-waiver.sh;
  tests/skills/test-aai-docs-audit.sh;
  tests/skills/test-aai-orchestration-dispatch.sh;
  tests/skills/test-aai-factory-report.sh;
  tests/skills/test-aai-golden-flow.sh; tests/skills/test-aai-ride-handoff.sh;
  docs/ai/METRICS.jsonl (the appended lines only); docs/product/telemetry.md;
  CHANGELOG.md; docs/issues/ISSUE-DRAFT-recover-archived-state-runs.md;
  docs/specs/SPEC-DRAFT-recover-archived-state-runs.md.

## Ceremony

Ceremony level 2. The change touches `.aai/scripts/metrics-flush.mjs`, two
libs and three readers. None is in `protected_paths_l3` of
docs/ai/docs-audit.yaml (`state.mjs`, `lib/state-engine.mjs`,
`lib/state-core.mjs`, the allocator, the guards, WORKFLOW.md,
CONSTITUTION.md); `lib/state-core.mjs` is imported, not edited, and STATE is
never written by the new branch. It is not L1 because it adds a ledger writer
and changes gate inputs. No `.aai/*.prompt.md`, no `.aai/AGENTS.md` and no new
`.aai/**` file is touched (the command is a branch of an existing script;
`.aai/METRICS_FLUSH.prompt.md` does not change), so neither companion
obligation applies.

## Decisions

### D1. Inventory (measured 2026-11-15, main checkout, read-only)

- 130 STATE copies: docs/ai/archive/** 125 (merge-cleanup 66, handoffs 26,
  worktrees 25, ci-body-only-rechecks 3, rfc-0017-selected-ci-conditional-sharding
  2, longhorizon-planning 1, docs-audit-node-test-pilot 1),
  docs/ai/reports/** 3, .git/aai/checkpoints/** 3
  (release-fixture-atomic-publication). 89 of them hold a `metrics:` block with
  runs.
- Parsed with metrics-flush's own `parseMetricsEntries`: 461 distinct runs
  keyed (ref, role, started_utc); 181 already held by METRICS.jsonl (of which
  27 match only on role and started_utc, see D2); 280 not held, over 65 refs,
  carrying 79,080,170 recorded `tokens_total`. 21 of the 65 refs already have
  one summary line (their recovery line is segment 2); 44 have none.
- No run has a null started_utc. One cross-copy field conflict exists:
  `cloudflare-share-on-node` Planning 2026-11-06T16:30:00Z, whose `note`
  differs between two copies (one carries `; usage_capture=none`). The
  orchestrator's brief said "no conflicts"; this one is real and is the
  fixture shape for the D2 NOTE.
- Inventory digest: `find docs/ai/archive docs/ai/reports .git/aai/checkpoints
  -name 'STATE*' -type f` sorted and piped to `shasum -a 256`, run in
  /Users/ales/Projects/aai, starts `51751363e1811852`.
- 27 of the 65 refs (157 runs) still sit in the main checkout's live STATE
  `metrics.work_items` (stranded since September; 23 of their work items read
  `in_progress`, 4 `done`). Their live run fields equal the archive copies on
  every field compared (ended_utc, model_id, tokens_total, duration_seconds).
- Git history cannot hold a gitignored copy, so a STATE deleted without an
  archive copy is out of reach.

### D2. Run identity and deduplication

- Archive side: runs from every copy are keyed (ref, role, started_utc); one
  key is one run. The winner among copies is the copy whose path sorts first
  (byte order of the absolute path). When two copies of one key disagree on any
  field the line would carry (model_id, ended_utc, duration_seconds,
  tokens_in, tokens_out, tokens_total, cost_usd, note, verdict, prompt_hash,
  harness, requested_model, actual_model, requested_effort, effort_applied,
  cache_read_tokens, cache_creation_tokens, tdd_tests), the command prints one
  line `NOTE <ref> <role> <started_utc>: archive copies disagree on <fields>; kept <winner path>`.
- A run without a string started_utc cannot be keyed: it is not recovered and
  prints `NOTE <ref> <role>: run without started_utc in <path> not recovered`.
- Ledger side: a run is already held when any summary line of the same exact
  ref_id (`isMetricsFlushRecord`) holds a run with the same role and
  started_utc. This is weaker than #556's four-field `runIdentity` on purpose:
  the July 2026 lines wrote `model_id: "unknown"` and one ci-body-only-rechecks
  Planning run carries a re-stamped ended_utc, so the four-field test would
  write 27 runs twice. A four-field match is always a role and started_utc
  match, so one test covers both. Precedent: ride-handoff reconcile
  `ledgerKeys`.
- Live wins: when the `--state` file's `metrics.work_items.<ref>.agent_runs`
  holds a run with the same (ref, role, started_utc), the line is built from
  the live run, not from the archive copy. A later normal flush compares STATE
  runs with the ledger on #556's four-field identity, so the recovered run must
  carry exactly the live fields or that flush would see it as fresh and write
  it a second time. (Orchestrator design point 3 did not state this; it is an
  addition, no conflict today because the fields are equal, D1.)

### D3. The command

A structurally disjoint branch of `.aai/scripts/metrics-flush.mjs`, entered
right after `parseArgs` and before the STATE read of the flush path, like
`--retire` and `--release` (the no-flag behaviour stays byte-unchanged by
construction).

- Flags: `--recover-archives`, repeatable `--archive <file-or-dir>`, plus the
  existing `--metrics`, `--pricing`, `--state`, `--now`, `--dry-run`.
  `--archive` without `--recover-archives` is exit 2. `--recover-archives`
  with `--ref`, `--sweep`, `--retire` or `--release` is exit 2 (it selects
  nothing by ref). A named `--archive` path that does not exist is exit 2,
  nothing written. With no `--archive`, the default is `docs/ai/archive`
  relative to the cwd; an absent default directory means no copies (exit 0,
  summary with zero counts).
- Directories are walked recursively without following symbolic links; a file
  is a copy when its basename starts with `STATE` and contains `.yaml`. A file
  named directly by `--archive` is read whatever its name. Copies are read in
  sorted absolute-path order; the same file named twice is read once. A copy
  that cannot be read prints a NOTE and is skipped (a later run picks it up).
- `--state` (default docs/ai/STATE.yaml) is READ ONLY. Its absence is exit 1
  with nothing written: without it the command cannot tell which ride is in
  flight (fail-closed).
- The repository root for pricing and titles is the cwd, not the directory of
  `--state` (the real run reads the main checkout's STATE but writes the
  worktree's ledger with the worktree's PRICING).
- It never writes STATE, EVENTS, LOOP_TICKS or the overview, and never opens
  EVENTS or LOOP_TICKS; it only appends to `--metrics`.
- Exit codes: 0 recovered, nothing to recover, or dry-run plan printed; 1
  `--state` absent or a ledger line that fails the JSON round-trip guard; 2
  usage.

### D4. The recovered line

One line per ref, built by the unchanged `buildEntry` over the ref's recovered
runs (same pricing, `cost_basis`, `trustedDuration` against `--now`, totals and
`reliabilityOf`), with this context and these overrides:

- runs ordered by started_utc, then role;
- `title`: `titleFor(cwd, workItemDocPath(copy, ref))` from the first copy in
  sorted order whose `active_work_items` names the ref with a resolvable doc;
  else null;
- `human_time_minutes`: intake and reviews from the first copy in sorted order
  whose metrics entry for the ref carries a number for that field, else null
  (no LOOP_TICKS). The fold already takes the maximum across segments, so a
  value repeated from an earlier line is not double-counted (#556 D9);
- `date_utc`: the UTC date of the latest run instant (ended_utc, else
  started_utc) among the recovered runs;
- overridden after `buildEntry` by assignment, so key order stays buildEntry's:
  `strategy: null`, `verdict_basis: null`, `verdict: null` (never `"PASS"`),
  `reliability.verdict_after_last_implementer: null`;
- `flush_segment`: the ref's existing summary line count plus 1 when it has
  lines (built through `entry.segment`, so it sits after `verdict` exactly as
  #556 D3 places it); absent when the ref has none;
- `reconstructed` as the last key: `{source, reason, recovered_utc}`. `source`
  is the `;`-joined, sorted, de-duplicated list of the copies that hold at least
  one recovered run of the ref, each written as the path suffix starting at
  `docs/ai/` or `.git/aai/` (first occurrence), else the path relative to the
  cwd in POSIX form. `reason` is the fixed text
  `role runs held only by archived STATE copies; recovered by metrics-flush --recover-archives (recover-archived-state-runs); verdict unknown`.
  `recovered_utc` is the `--now` instant (else the clock), second precision.
- No `validation_waiver` (buildEntry gets `waiver: null`).

Lines are appended in one `appendFileSync`, ordered by (date_utc, ref_id); the
earlier ledger bytes stay a byte-exact prefix (HAZ-LEDGER). A line that fails
buildEntry's JSON round-trip guard is exit 1 with nothing appended.

### D5. Skips, output and dry-run

- The `--state` `current_focus.ref_id` is skipped:
  `SKIP <ref>: current focus of <state path> (in flight; its runs reach the ledger through its own flush)`.
- Refs whose runs still sit in the live `--state` `metrics.work_items` are
  recovered (orchestrator decision; D2 live-wins makes this safe for the
  identity) and print one extra line
  `  live: <ref> <k> runs also in <state path>; a later flush treats them as held`.
- Per recovered ref: `Recovered: <ref> -> <metrics path> (<k> runs)`, with
  `, flush_segment <n>` before the closing parenthesis on a continuation.
- Last line: `RECOVER SUMMARY copies=<n> runs=<distinct> held=<h> recovered=<r> refs=<k> continuation=<c> skipped=<s> tokens_total=<t>`.
- `--dry-run` writes nothing and prints one JSON object
  `{mode: "recover-archives", copies, runs_distinct, runs_held, runs_recovered, refs, continuation, tokens_total, skipped, notes, entries}`
  where `entries` are exactly the lines the real run would append (with the
  same `--now`).

### D6. What a recovered line is to every reader (gate safety)

A "recovery line" is a summary line (`isMetricsFlushRecord`) whose
`reconstructed` is a non-null object and whose `verdict` is not `"PASS"`. One
exported helper, `isRecoveryRecord(record)` in
`.aai/scripts/lib/metrics-flush-record.mjs`, decides it. #556's reconstructed
line (verdict PASS, a real ride segment) is NOT a recovery line, so its
behaviour is unchanged everywhere.

| Reader | Today on a recovery line | This scope |
|---|---|---|
| validation-waiver.mjs archive lane (`evaluateArchive`) | counts only `verdict === 'PASS'` lines | unchanged, pinned by Spec-AC-06 |
| lib/docs-audit-core.mjs `readMetricsFlushes` (Arm D) | any flush record is delivery evidence | skips recovery lines (Spec-AC-07) |
| orchestration-dispatch.mjs rule-14 and 4a `flushed` probe | any flush record names the focus as flushed | skips recovery lines (Spec-AC-08) |
| lib/metrics-flush-record.mjs `foldRideSegments` | merged record takes the last segment's fields and position | base segment rule below (Spec-AC-09) |
| golden-flow.mjs `tokensMedianLast10` | every folded ride, by position | skips all-recovery rides (Spec-AC-10) |
| generate-factory-report.mjs | folded rides; `verdict_mix` buckets the folded verdict | safe after the fold change; an all-recovery ride sits in the `null` bucket, which is the truth |
| metrics-report.mjs | folded rows; Features delivered counts PASS | safe after the fold change; an all-recovery ride is not counted as delivered |
| generate-dashboard.mjs | work items per ref; per-run status from the line verdict, unknown verdict renders `success` (line 153) | runs and tokens correct; the status default is pre-existing behaviour for verdict-less lines, residual R4 |
| generate-overview.mjs `tokensByRef`, effort | sums per ref across lines | safe: recovered runs are real effort of that ref |
| ride-handoff.mjs reconcile `ledgerKeys` | unions role and started_utc keys of the ref | safe and intended: recovered runs become held, so reconcile can clear them (Spec-AC-11) |
| reconcile-telemetry.mjs | carries uncommitted lines by ref | safe: a recovery line is an ordinary ledger line |
| merge-cleanup.mjs ledger union and reconcile | append-only union; calls ride-handoff reconcile | safe (as above) |
| metrics-flush.mjs `ledgerRunCounts` (next flush) | counts every summary line and its runs | intended: recovered runs are held; segment numbering counts the recovery line |

Fold base segment rule (`foldRideSegments`, multi-line refs only): the base is
the latest segment that is not a recovery line, else the last segment. The
merged record spreads the base (not the last segment), so `verdict`,
`verdict_basis`, `strategy`, `reconstructed` and every other non-summed field
come from it; `reliability` starts from the base's reliability (so
`verdict_after_last_implementer` is the base's) and keeps the summed counts;
`validation_waiver` comes from the latest non-recovery segment that carries
one; the merged record is emitted at the base's ledger position. Summed and
maximised fields (runs, seconds, cost, human time, date, flush_segment,
flush_lines) are computed over all segments as today. A ref whose lines are
all recovery lines keeps today's behaviour (last segment, its own position). A
single-line ref is returned as the same object. With no recovery line present
the base is the last segment, so every existing #556 output is unchanged.

golden-flow: the last-10 median is over delivered rides; a ride whose folded
record is itself a recovery line (all its lines are recovery lines) is
skipped, because it was appended now but happened months ago and would
otherwise displace the ten most recent real rides.

### D7. Interaction with a later normal flush

- A ref recovered while its runs are still in the live STATE: the next flush
  of that ref finds every recovered run held (four-field identity, D2 live
  wins). With at least one fresh run and the default gate admitting the ref it
  appends a `verdict: "PASS"` continuation line holding only the fresh runs,
  `flush_segment` = line count plus 1, and mints the archive record as usual,
  so the PR gate opens with `validation_archived_pass` (the recovery line is
  not a PASS hit, so it never makes the gate ambiguous).
- With zero fresh runs the flush takes #556's cleanup-only resume and appends
  no PASS line. For the 27 stranded September refs that is acceptable: they
  were delivered long ago and their only future flush path is `--sweep`, whose
  close event is already the delivery evidence. For a ride that is genuinely in
  flight it would lose its PASS line; the focus skip (D5) is the guard, and the
  non-focus in-flight case is residual R1.

### D8. The real recovery run (Implementation, run 4)

From the worktree root, cwd the worktree, reading the main checkout
read-only:

1. `node .aai/scripts/metrics-flush.mjs --recover-archives --archive /Users/ales/Projects/aai/docs/ai/archive --archive /Users/ales/Projects/aai/docs/ai/reports --archive /Users/ales/Projects/aai/.git/aai/checkpoints --state /Users/ales/Projects/aai/docs/ai/STATE.yaml --metrics docs/ai/METRICS.jsonl --dry-run`
   and save the JSON. `--state` is the main checkout's STATE because that is
   the live STATE these archives belong to (D2 live wins needs it); its focus
   is null today. This ride's own ref holds no archived run (measured).
2. Recompute the D1 inventory digest. If it, or origin/main's METRICS.jsonl,
   differs from Planning's measurement, re-measure, record the new counts as a
   measurement amendment (spec-amend, additive-with-disclosure) before step 3,
   and use them in Spec-AC-12.
3. Check `gh pr list --state open` heads against the dry-run's refs; a match is
   a stop-and-ask (residual R2).
4. Run the same command without `--dry-run`; then run it a second time and
   save both outputs. Evidence under docs/ai/tdd/recover-archived-state-runs/recovery/.

Expected (Planning measurement, to be confirmed by the step 1 dry-run, which
is authoritative because live wins and the focus skip are applied by the
command itself): copies 130, runs_distinct 461, runs_held 181,
runs_recovered 280, refs 65, continuation 21, tokens_total 79080170, one NOTE
for the D1 conflict, skipped 0; the second run recovers 0 and appends nothing.
TEST-3749 pins the dry-run's reported values, the D4 reason text as the marker
of this ride's lines, and the pre-ride prefix as byte length 866116 plus
sha256 5ef04d1fe299fd1d6d8a2e1678a9c60c675650a2deb1460eeb83e0004e311d41 of
docs/ai/METRICS.jsonl at origin/main 5bbc129e (append-only, so the pin stays
valid on main and in every later PR; shallow CI clones need no git history).
If origin/main's ledger changed before the run (D8 step 2), the counts are
re-measured and disclosed; the 5bbc129e prefix pin stays valid because a
later base only appends after it.

## Acceptance Criteria Mapping

- Intake Expected Behavior bullet 1 (one repeatable command, one line per ref
  through the flush's builder, marked reconstructed with sources and reason) to
  Spec-AC-01 and Spec-AC-04; bullet 2 (a held run is never written again, a
  second run adds nothing) to Spec-AC-02 and Spec-AC-03; bullet 3 (never a
  PASS, never delivery, never flushed, folded rides keep verdict and position)
  to Spec-AC-06, Spec-AC-07, Spec-AC-08, Spec-AC-09 and Spec-AC-10; the
  interaction with the live STATE and a later flush to Spec-AC-05 and
  Spec-AC-11; the actual recovery in this repository to Spec-AC-12; the
  consumer-visible change to Spec-AC-13.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN metrics-flush runs with --recover-archives over a fixture archive directory whose copies hold runs of a ref with no ledger line and of a ref whose one ledger line holds some of its runs, it SHALL exit 0 and append exactly one line per ref in date_utc then ref_id order, leave every earlier ledger byte unchanged and leave STATE and EVENTS byte-identical; each line SHALL hold exactly the not-yet-held runs in started_utc order, carry verdict null, verdict_basis null, strategy null, reliability.verdict_after_last_implementer null, date_utc equal to the UTC date of the latest run instant and reconstructed as the last key with non-empty source naming the contributing copies, the fixed reason and recovered_utc equal to --now; the second ref's line SHALL carry flush_segment 2 and the first ref's line none; and each line's agent_runs and totals SHALL deep-equal what a normal flush of the same runs writes | planned | — | — | D3, D4 |
| Spec-AC-02 | WHEN a run appears in several copies it SHALL be written once from the copy whose path sorts first, and a field disagreement SHALL print one NOTE naming the ref, role, started_utc, the fields and the kept path; WHEN the ledger holds a run of the same ref with the same role and started_utc but model_id unknown or a different ended_utc it SHALL count as held and not be written; a run without started_utc SHALL not be written and SHALL print a NOTE | planned | — | — | D2 |
| Spec-AC-03 | WHEN the command runs a second time over the same archives and ledger it SHALL exit 0, append nothing and report recovered=0 in the summary; --dry-run SHALL write nothing to METRICS, STATE or EVENTS and print one JSON plan whose entries deep-equal the lines the real run with the same --now appends | planned | — | — | D5; idempotence |
| Spec-AC-04 | the --state current_focus ref SHALL be skipped with a SKIP line and get no line; a directory archive SHALL be walked recursively and only files whose basename starts with STATE and contains .yaml read; the default archive SHALL be docs/ai/archive under the cwd; --archive without --recover-archives, --recover-archives combined with --ref or --sweep or --retire or --release, and a named --archive path that does not exist SHALL each exit 2 with nothing written; an absent --state SHALL exit 1 with nothing written | planned | — | — | D3, D5 |
| Spec-AC-05 | WHEN a ref's runs sit both in the live --state metrics.work_items and in an archive copy whose ended_utc for one run differs, the recovered line SHALL carry the live run's fields; WHEN that ref is then focused, given one new run with state.mjs append-run and a validation pass with set-validation, and flushed normally, the flush SHALL exit 0 and append one verdict PASS line whose agent_runs are exactly the new run with flush_segment 2, and validation-waiver.mjs --state SHALL exit 0 with reason validation_archived_pass; the same flush with no new run SHALL take the RESUME cleanup-only lane and append nothing | planned | — | — | D2 live wins, D7; seam recovery to flush to PR gate |
| Spec-AC-06 | WHEN the only same-day line for the archived ref is a recovery line, validation-waiver.mjs --state SHALL exit 1 with reason archive_no_ledger_pass; WHEN the ledger holds one real PASS line and one same-day recovery line for that ref it SHALL exit 0 with validation_archived_pass and not archive_ledger_ambiguous | planned | — | — | D6 row 1; validation-waiver.mjs unchanged |
| Spec-AC-07 | WHEN a draft intake's only METRICS record is a recovery line, docs-audit SHALL NOT give it the reason work-item flush record and SHALL NOT classify it false-open on that ground; the same line with verdict PASS and a reconstructed object SHALL still give that reason | planned | — | — | D6 row 2 |
| Spec-AC-08 | WHEN the focus ref holds a validation pass and its only METRICS record is a recovery line, orchestration-dispatch SHALL dispatch Metrics Flush under rule 14 and SHALL NOT return no_action already_flushed; with a PASS line for the focus ref it SHALL still return no_action already_flushed | planned | — | — | D6 row 3 |
| Spec-AC-09 | foldRideSegments over a ref with a PASS line followed later in the ledger by a recovery line SHALL return one record at the PASS line's position whose verdict, verdict_basis, strategy and reliability.verdict_after_last_implementer are the PASS line's, with agent_runs concatenated and tokens summed over both; a ref whose lines are all recovery lines SHALL keep verdict null at its own position; a single-line ref SHALL be the same object; and the factory report verdict_mix and the metrics report Features delivered SHALL count the first ride as PASS | planned | — | — | D6 fold base rule |
| Spec-AC-10 | golden-flow tokens_median_last10 over a ledger of eleven PASS rides followed by a recovery line for the first ride and an all-recovery ride SHALL equal the median over rides two to eleven, excluding the all-recovery ride and keeping the first ride at its original position | planned | — | — | D6 golden-flow decision |
| Spec-AC-11 | WHEN ride-handoff reconcile refuses origin_runs_not_in_ledger for a ride whose origin runs are held only by an archive copy, then after a recovery run over that copy (with another ref focused) the same reconcile SHALL report RECONCILED | planned | — | — | D6 row ride-handoff; seam recovery to reconcile |
| Spec-AC-12 | docs/ai/METRICS.jsonl SHALL begin with the pre-ride ledger, its first 866116 bytes hashing to sha256 5ef04d1fe299fd1d6d8a2e1678a9c60c675650a2deb1460eeb83e0004e311d41 (docs/ai/METRICS.jsonl at origin/main 5bbc129e); the lines whose reconstructed.reason equals the D4 reason text SHALL all lie after that prefix, each be a recovery line, and match in line count, run count, tokens_total sum and flush_segment split the values the D8 dry-run reported (Planning measurement 65 lines, 280 runs, 79080170 tokens_total, 21 with flush_segment 2 and 44 without); no run of those lines SHALL share ref, role and started_utc with a run of a non-recovery line of the same ref; and a second run of the D8 command SHALL report recovered=0 and append nothing | planned | — | — | D1, D8; HAZ-LEDGER; durable after merge: identified by marker, prefix pinned by length and hash, no git call |
| Spec-AC-13 | docs/product/telemetry.md SHALL describe --recover-archives, the recovery line shape and that it is never a PASS, delivery or flushed record; CHANGELOG.md SHALL hold exactly one per-entry heading for this fix in the form unreleased or a rolled vYYYY.MM.DD, followed by an em dash and fix | planned | — | — | Consumer-visible; ships downstream |

## Implementation plan

Components:
- `.aai/scripts/metrics-flush.mjs`
  - `parseArgs`: `--recover-archives` (boolean) and repeatable `--archive`
    (array), the D3 usage refusals, and the valid-flags list in the unknown-flag
    message.
  - `main`: `if (opts.recoverArchives) { handleRecoverArchives(opts); return; }`
    right after `parseArgs`.
  - `handleRecoverArchives` and small helpers: `archiveCopies(paths)` (walk,
    D3), `archiveRuns(copies)` (D2 dedupe and NOTE), `ledgerRoleStarts(metricsPath)`
    (held keys plus per-ref line count), `sourceLabel(path)` (D4), the D4 line
    build through `buildEntry`, the D5 output and dry-run, one append.
  - Header comment: one paragraph for `--recover-archives`.
- `.aai/scripts/lib/metrics-flush-record.mjs`: `isRecoveryRecord` export; the
  D6 base segment in `mergeSegments` and the position in `foldRideSegments`;
  the header comment updated.
- `.aai/scripts/lib/docs-audit-core.mjs` `readMetricsFlushes`: skip recovery
  lines.
- `.aai/scripts/orchestration-dispatch.mjs` rule-14 probe (~line 1069): skip
  recovery lines.
- `.aai/scripts/golden-flow.mjs` `tokensMedianLast10`: skip all-recovery rides.
- Tests in the suites of the Test Plan; `docs/ai/METRICS.jsonl` (D8);
  `docs/product/telemetry.md`; `CHANGELOG.md`.

Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor a
mutation to the code it writes, disclosed as a measurement amendment):
- `const RECOVERY_VERDICT = null;`
- `segment: prior.lines > 0 ? prior.lines + 1 : undefined,`
- `if (held.has(roleStartKey(ref, run))) continue;`
- `if (byKey.has(key)) { noteConflict(byKey.get(key), cand); continue; }`
- `const src = liveRun(live, ref, run) ?? run;`
- `if (ref === focusRef) { skipped[ref] = SKIP_FOCUS; continue; }`
- `if (opts.dryRun) { printRecoveryPlan(plan); exit(0); }`
- lib: `const base = baseSegment(segs);` and `if (baseSegment(segs) === r) out.push(mergeSegments(segs));`
- docs-audit-core: `if (isRecoveryRecord(rec)) continue;`
- dispatch: `if (isMetricsFlushRecord(record) && !isRecoveryRecord(record) && record.ref_id === focusRef)`
- golden-flow: `if (isRecoveryRecord(r)) continue;`

Data flow: archived STATE copies (merge-cleanup, ride-handoff, worktree
cleanup, planning transfer) hold `metrics.work_items` runs; the recovery reads
them with the flush's own parser, subtracts the runs METRICS holds, builds one
line per ref with the flush's builder and appends; the next flush, the PR
gate, docs-audit, dispatch, the fold and its reports, the overview and
ride-handoff read the ledger.

Edge cases:
- A copy whose `metrics:` block is absent or empty contributes nothing.
- A ref recovered in one run and given more archived runs later (a new copy):
  the next recovery writes another recovery line with `flush_segment` n+1;
  the fold sums it.
- Archive runs of a ref whose ledger lines use a multi-ref `/`-joined ref_id:
  matching is on the exact ref_id, as `ledgerRunCounts` does; such a run is
  recovered under its own ref (none in the D1 inventory).
- Duration: `trustedDuration` nulls a duration that does not match its stamps;
  never estimated.
- Tests that run metrics-flush from the shipping tree regenerate the tracked
  overview (registry `fu-recheck-tests-regen-shipping-overview`); the recovery
  branch does not regenerate it, and the new tests run in fixture directories.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3734 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | fixture repo with a ledger line for ref B holding one of its runs and an archive dir with two copies holding runs of A and B: recovery exits 0, ledger prefix byte-identical by cmp, two appended lines in order, null verdict fields, reconstructed last with source naming both copies, the fixed reason and recovered_utc equal to --now, STATE and EVENTS byte-identical; a normal flush of the same runs in a second fixture yields agent_runs and totals deep-equal to the recovered lines | target `.aai/scripts/metrics-flush.mjs`; `sed:s/const RECOVERY_VERDICT = null;/const RECOVERY_VERDICT = 'PASS';/` writes a PASS verdict and the case must fail | green |
| TEST-3735 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | same fixture: line A has no flush_segment, line B has flush_segment 2 and only the not-held run, date_utc is the latest run instant's date | target `.aai/scripts/metrics-flush.mjs`; `sed:s/prior.lines > 0 \? prior.lines \+ 1 : undefined/prior.lines > 0 ? prior.lines : undefined/` writes segment 1 and the case must fail | green |
| TEST-3736 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | ledger holds a run with model_id unknown and a re-stamped ended_utc for the same role and started_utc as an archive run: that run is not written; a run without started_utc prints its NOTE and is not written | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(held.has\(roleStartKey\(ref, run\)\)\) continue;/if (false) continue;/` writes the held run again and the case must fail | green |
| TEST-3737 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | one run in two copies with different notes: written once with the note of the first-sorted copy, one NOTE line naming ref, role, started_utc, note and the kept path | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(byKey.has\(key\)\) \{ noteConflict\(byKey.get\(key\), cand\); continue; \}/if (false) { continue; }/` writes the run twice and the case must fail | green |
| TEST-3738 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh | dry-run first: ledger, STATE and EVENTS unchanged and the plan entries deep-equal the lines of the following real run with the same --now; then a second real run appends nothing and prints recovered=0 | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(opts.dryRun\) \{ printRecoveryPlan\(plan\); exit\(0\); \}/if (false) { printRecoveryPlan(plan); exit(0); }/` makes the dry run write and the case must fail | green |
| TEST-3739 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh | focus ref skipped with SKIP and no line; nested dir walked and a non-STATE yaml ignored; default docs/ai/archive used; the five usage refusals exit 2 and the absent --state exits 1, each with the ledger unchanged | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(ref === focusRef\) \{ skipped\[ref\] = SKIP_FOCUS; continue; \}/if (false) { continue; }/` recovers the in-flight focus and the case must fail | green |
| TEST-3740 | Spec-AC-05 | integration | tests/skills/test-aai-metrics.sh | the real CLIs: recovery of a ref whose runs sit in live STATE and in an archive copy with one differing ended_utc, then state.mjs set-focus, append-run, set-validation pass and a normal flush: one PASS line with only the new run and flush_segment 2, validation-waiver.mjs --state exits 0 with validation_archived_pass; a second fixture without the new run takes RESUME and appends nothing | target `.aai/scripts/metrics-flush.mjs`; `sed:s/const src = liveRun\(live, ref, run\) \?\? run;/const src = run;/` writes the archive fields so the later flush re-writes that run and the case must fail | green |
| TEST-3741 | Spec-AC-06 | integration | tests/skills/test-aai-pr-waiver.sh | an archive record for ARCH-1 with only a same-day recovery line refuses archive_no_ledger_pass; one PASS line plus a same-day recovery line opens with validation_archived_pass | target `.aai/scripts/validation-waiver.mjs`; `sed:s/e.verdict === 'PASS' && e.date_utc === day/e.date_utc === day/` counts the recovery line and the case must fail | green |
| TEST-3742 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | draft intake plus a METRICS recovery line for its slug: no work-item flush record reason and no false-open; control with verdict PASS and reconstructed keeps the reason | target `.aai/scripts/lib/docs-audit-core.mjs`; `sed:s/if \(isRecoveryRecord\(rec\)\) continue;//` counts the recovery line as delivery and the case must fail | green |
| TEST-3743 | Spec-AC-08 | integration | tests/skills/test-aai-orchestration-dispatch.sh | focus ref with validation pass and only a recovery line: rule 14 dispatches Metrics Flush; control with a PASS line returns no_action already_flushed | target `.aai/scripts/orchestration-dispatch.mjs`; `sed:s/ && !isRecoveryRecord\(record\)//` reads the recovery line as flushed and the case must fail | green |
| TEST-3744 | Spec-AC-09 | unit | tests/skills/test-aai-factory-report.sh | foldRideSegments over a PASS ride followed by a later recovery line, an all-recovery ref and a single-line ref: merged verdict, verdict_basis, strategy and verdict_after_last_implementer from the PASS line, runs concatenated, tokens summed; all-recovery ref verdict null; single line the same object | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/const base = baseSegment\(segs\);/const base = segs[segs.length - 1];/` takes the recovery line's null verdict and the case must fail | green |
| TEST-3745 | Spec-AC-09 | integration | tests/skills/test-aai-factory-report.sh | the same fixture through generate-factory-report: verdict_mix PASS 1 and null 1 for the two refs; and through metrics-report: Features delivered counts the PASS ride and not the all-recovery ride | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/const base = baseSegment\(segs\);/const base = segs[segs.length - 1];/` buckets the delivered ride as null and the case must fail | green |
| TEST-3746 | Spec-AC-10 | integration | tests/skills/test-aai-golden-flow.sh | eleven PASS rides with usage totals 100 to 1100 in ledger order, then a recovery line for ride 1 with usage 5000 and an all-recovery ride with usage 5000: tokens_median_last10 is 650 | target `.aai/scripts/golden-flow.mjs`; `sed:s/if \(isRecoveryRecord\(r\)\) continue;//` lets the all-recovery ride into the last ten and the case must fail | green |
| TEST-3747 | Spec-AC-10 | integration | tests/skills/test-aai-golden-flow.sh | the same ledger: ride 1 stays at its first-line position, so the median is not the value it takes when ride 1 is moved to the end (750) | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/if \(baseSegment\(segs\) === r\) out.push/if (segs[segs.length - 1] === r) out.push/` moves ride 1 to its last line and the case must fail | green |
| TEST-3748 | Spec-AC-11 | integration | tests/skills/test-aai-ride-handoff.sh | origin STATE holding ride R's runs and a ledger without them: ride-handoff reconcile --dry-run refuses origin_runs_not_in_ledger; after a recovery run over an archive copy of those runs with another ref focused, the same reconcile reports RECONCILED | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(opts.dryRun\) \{ printRecoveryPlan\(plan\); exit\(0\); \}/if (true) { printRecoveryPlan(plan); exit(0); }/` appends nothing and reconcile still refuses, so the case must fail | green |
| TEST-3749 | Spec-AC-12 | integration | tests/skills/test-aai-metrics.sh | reads only the working-tree docs/ai/METRICS.jsonl with no git call: the first 866116 bytes hash to the pinned sha256; the lines whose reconstructed.reason equals the D4 reason all start after that offset, are recovery lines and match the pinned D8 dry-run counts (lines, runs, tokens_total sum, flush_segment split); none of their (ref, role, started_utc) appears in a non-recovery line of the same ref; stays green after merge and after later appends | target `docs/ai/METRICS.jsonl`; `sed:s/"verdict":null,"reconstructed"/"verdict":"PASS","reconstructed"/` turns one recovery line into a PASS line and the case must fail | pending |
| TEST-3750 | Spec-AC-13 | unit | tests/skills/test-aai-metrics.sh | CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix naming the archived-runs recovery; docs/product/telemetry.md mentions --recover-archives and that a recovery line is never a PASS | target `CHANGELOG.md`; `sed:s/— fix: role runs held only by archived STATE copies/— fix: x/` removes the named heading and the case must fail | pending |

Seams crossed (each by a real producer and a real reader):
- Archived STATE copy (producer: the real `parseMetricsEntries` read of a
  fixture written in STATE's own shape) to the recovery writer: TEST-3734..3739.
- Recovery writer (producer) to the next normal flush and its run-level resume,
  then to the PR gate (readers): TEST-3740 drives `state.mjs` and
  `metrics-flush.mjs` and `validation-waiver.mjs` for real.
- Recovery line (producer) to validation-waiver, docs-audit, dispatch, the
  fold, factory-report, metrics-report, golden-flow (readers): TEST-3741..3747
  with lines the real recovery wrote where the suite can run it, else lines in
  its exact D4 shape.
- Recovery writer (producer) to ride-handoff reconcile (reader): TEST-3748.
- Main checkout archives (producer) to the real ledger (reader: every suite
  that reads docs/ai/METRICS.jsonl): TEST-3749 plus Verification item 3.
- Not crossed by a test: a non-focus in-flight ride in the same STATE (R1);
  an open PR branch elsewhere that will flush runs also held by an archive
  copy (R2); the dashboard status default (R4).

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suites'
`set -euo pipefail` (no `printf | grep -q`; assert with here-strings or files).

1. RED before GREEN per TDD run: `docs/ai/tdd/recover-archived-state-runs/red-<run>.log`
   and `green-<run>.log`. RED for TEST-3734 is `unknown flag "--recover-archives"`
   (exit 2) on the unchanged tree; RED for TEST-3742..3744 and TEST-3746 is the
   unchanged reader counting a hand-written recovery line.
2. `bash tests/skills/test-aai-metrics.sh`, `test-aai-pr-waiver.sh`,
   `test-aai-docs-audit.sh`, `test-aai-orchestration-dispatch.sh`,
   `test-aai-factory-report.sh`, `test-aai-golden-flow.sh`,
   `test-aai-ride-handoff.sh` exit 0 with no golden edited.
3. Suites that read the real ledger, all exit 0 after the D8 append:
   test-aai-pricing.sh, test-aai-dashboard.sh, test-aai-hygiene-pack.sh,
   test-aai-reconcile-telemetry.sh, test-aai-token-capture.sh,
   test-aai-model-effort.sh, test-aai-merge-cleanup.sh,
   `node --test tests/skills/lib/ride-handoff.test.mjs`, plus CORE.
4. Mutation records for TEST-3734..3750 under
   `docs/ai/tdd/spec-recover-archived-state-runs/` via `mutation-run.mjs`.
5. Recovery evidence (D8): the dry-run JSON, the real-run and second-run
   stdout, the inventory digest, the open-PR check, and
   `git diff origin/main -- docs/ai/METRICS.jsonl --stat` showing 65 added
   lines and none removed.
6. `node .aai/scripts/docs-audit.mjs --gate spec-recover-archived-state-runs`
   and `--ac-flip-check` exit 0 before hand-off.
7. One full sweep at final validation with `AAI_TEST_TIMEOUT=3600`.
8. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id recover-archived-state-runs, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs under
docs/ai/tdd/recover-archived-state-runs/, mutation records under
docs/ai/tdd/spec-recover-archived-state-runs/, recovery evidence under
docs/ai/tdd/recover-archived-state-runs/recovery/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Out of scope

- `merge-cleanup.mjs` `archiveRuntime` and the `SKILL_WORKTREE` cleanup
  archive a STATE copy without checking that its runs reached METRICS. The
  recovery command could run there (or the archive step could refuse). Follow-up
  suggested below; this scope only recovers what is already archived.
- Flushing or retiring the 27 stranded refs in the main checkout's live STATE:
  their runs are recovered here, and the live entries stay for `--sweep` or
  `--retire` (D7).
- Dispatch rule 14's ref-keyed `flushed` probe for a reopened ride
  (`fu-dispatch-flushed-probe-ref-keyed`): this scope only makes it ignore
  recovery lines.
- The dashboard's `success` default for a verdict-less line (R4).

## Registry items closed by this scope

`fu-archived-state-runs-not-in-ledger` (P2): closed by Spec-AC-01..05 (the
command) and Spec-AC-12 (the recovery on this repository's ledger). Checked
`node .aai/scripts/follow-ups.mjs list` (342 open). Adjacent and NOT closed:
`fu-dispatch-flushed-probe-ref-keyed` (rule 14 stays ref-keyed for real
lines; recovery lines are excluded, which neither fixes nor worsens it),
`fu-continuation-rerecords-human-time` (D4 takes human time from the copy; the
fold's maximum already bounds it), `fu-recheck-tests-regen-shipping-overview`
and `fu-test-flush-regens-overview` (the recovery branch does not regenerate
the overview).

Suggested follow-ups (not filed by Planning):
- suggested: `fu-archive-step-skips-ledger-check` (merge-cleanup
  archiveRuntime and SKILL_WORKTREE cleanup archive STATE without checking
  that its runs reached METRICS).
- suggested: `fu-recovery-in-flight-non-focus` (R1).

## Residual risks

- R1. A ride that is in flight in the `--state` STATE but is not its
  current focus (parallel orchestration) can have its runs recovered if an
  archive copy holds them; its eventual flush with no further runs then takes
  the cleanup-only resume and appends no PASS line, so its PR gate archive lane
  does not open and dispatch rule 14 keeps reading it as not flushed. No such
  ride exists today (main's live STATE has no focus; the 27 stranded refs date
  from September).
- R2. A ride flushed on another branch (an open PR with no local worktree)
  whose runs are also in a main-checkout archive copy (a ride-handoff
  pre-handoff STATE) would, after both merge, hold the same runs in a recovery
  line and a PASS line, double-counting them. Measured: the two open PRs
  (#558, #535) name no ref of the 65. D8 step 3 re-checks at run time.
- R3. Recovered lines are priced with today's PRICING.yaml, like any flush on
  this day; `trustedDuration` nulls inconsistent durations. Tokens and
  durations are as recorded, never estimated.
- R4. generate-dashboard renders a verdict-less line's runs with status
  `success` (pre-existing default for verdict-less legacy lines); the recovered
  runs appear as successful operations. Totals are correct.
- R5. The D8 counts are a snapshot of a shared, changing archive tree; D8
  step 2 re-measures and discloses rather than editing the numbers silently.

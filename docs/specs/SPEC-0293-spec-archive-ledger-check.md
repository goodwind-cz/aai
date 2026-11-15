---
id: spec-archive-ledger-check
type: spec
number: 293
status: done
mutation_gate: v1
frozen_sha256: db6b0bee5d20742e876e28555b268a9c34661c7b0643cd188fed16d42b81301b
ceremony_level: 2
links:
  requirement: archive-ledger-check
  rfc: null
  pr: []
  commits: []
---

# Archiving a ride's STATE copy writes the role runs the ledger lacks, through the existing recovery

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0116-archive-ledger-check.md (follow-up
  `fu-archive-step-skips-ledger-check`, P3).
- Prior scope this one builds on (closed, not edited):
  docs/specs/SPEC-0292-spec-recover-archived-state-runs.md (PR #559): the
  `--recover-archives` command, its run identity (ref, role, started_utc),
  live-wins rule, `buildEntry` line, `reconstructed` marker and
  `flush_segment` numbering.
- Prior scope for the ride ledger tails: merge-cleanup D6
  (`ledgerTails`, `moveLedgerTails`): lines appended to a ride worktree's
  tracked ledgers are moved to the main checkout after the base sync.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: a data-integrity change to a vendored cleanup engine and a
  ledger writer. Every behaviour below can be seen failing on the unchanged
  tree: `--include-focus` is an unknown flag (exit 2), and merge-cleanup apply
  leaves a late run only in the archive copy. The intake's tdd note is an
  autopilot recommendation, not a recorded user choice.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions and
  holds uncommitted files owned by others; the operator directed an own
  worktree.
- User decision: worktree (recorded in STATE before Planning, autopilot
  default with the operator's direction)
- Base ref: origin/main at 822569b2
- Worktree branch/path: fix/archive-ledger-check at
  /Users/ales/Projects/aai-worktrees/archive-ledger-check
- Review required: true
- Review scope (explicit paths): .aai/scripts/metrics-flush.mjs;
  .aai/scripts/lib/metrics-flush-record.mjs; .aai/scripts/merge-cleanup.mjs;
  .aai/scripts/lib/merge-outcomes.mjs; .aai/SKILL_WORKTREE.prompt.md;
  tests/skills/test-aai-metrics.sh; tests/skills/test-aai-merge-cleanup.sh;
  tests/skills/test-aai-worktree.sh; tests/skills/suite-map.yaml;
  tests/skills/suite-weights.tsv; tests/skills/lib/prompt-diet-ledger.sh;
  tests/skills/test-aai-prompt-diet.sh; tests/skills/test-aai-pr-preflight.sh;
  docs/product/telemetry.md; CHANGELOG.md;
  docs/issues/ISSUE-0116-archive-ledger-check.md;
  docs/specs/SPEC-0293-spec-archive-ledger-check.md.

## Ceremony

Ceremony level 2. No file in `protected_paths_l3` of docs/ai/docs-audit.yaml
is touched (`state.mjs`, `lib/state-engine.mjs`, `lib/state-core.mjs`, the
allocator, the guards, WORKFLOW.md, CONSTITUTION.md). It is not L1: it adds a
ledger write to the post-merge cleanup engine and changes a prompt.

Companion obligations: `.aai/SKILL_WORKTREE.prompt.md` gains bytes, so the
prompt-diet ledger true-up applies (a `JUSTIFIED_ADDITIONS` entry in
tests/skills/lib/prompt-diet-ledger.sh, the TEST-012 pin in
tests/skills/test-aai-prompt-diet.sh and the credit sum pinned in
tests/skills/test-aai-pr-preflight.sh). No new `.aai/**` file, so PROFILES.yaml
does not change.

## Decisions

### D1. Write, not refuse (the trade-off)

The archive step writes the missing runs instead of refusing.

- Refusing would keep the worktree (or the step) for every merged ride whose
  STATE took a run after its flush. That is the common case: review, CI-fix
  and bot-answer rounds run after the close commit's flush. Each such merge
  would then need a person to run a command. The owner's rule is that metrics
  are not lost, and his standing rule is that fixes run without asking.
- Writing goes into the ride WORKTREE's `docs/ai/METRICS.jsonl` as an
  append-only tail. merge-cleanup already moves such tails to the main
  checkout after the base sync (D6 of the ride-leftovers scope), so the main
  checkout gets the same kind of uncommitted ledger lines it already gets
  from every ride that appends to a ledger after its push. No new kind of
  drift is created; the lines are committed by the next ledger-carrying
  change, as today.
- Writing into the main checkout's METRICS directly was rejected: the step
  runs before the base sync, so the merged PR's flush lines are not in that
  file yet and the identity check would see every flushed run as missing.
  The worktree's ledger at the PR head is the one that already holds them.
- The cost: an uncommitted ledger line in the main checkout after cleanup.
  The alternative cost is a person in the loop for every merge. The refuse
  branch stays as the fallback for the cases where writing is not safe (D3).

### D2. One recovery path, one new flag

`metrics-flush.mjs --recover-archives` gains `--include-focus`.

- Without it nothing changes: the `--state` current_focus ref is skipped and
  the `--state` file is excluded from the copies with its NOTE.
- With it, the `--state` current_focus ref is NOT skipped and the `--state`
  file MAY be named by `--archive` (it is read as a copy, not excluded). It
  means: the ride of this STATE has ended and its STATE is being archived,
  so its own runs are recovered too.
- Everything else is SPEC-0292 unchanged: identity (ref, role,
  started_utc), live wins, `buildEntry`, `reconstructed` as the last key with
  the fixed reason, null verdict fields, `flush_segment` n+1, dry-run JSON
  plan, the summary line, idempotence.
- `--include-focus` without `--recover-archives` is exit 2.
- `--held-in <file>` (repeatable; review round 1, B1 and B2) names another
  ledger whose runs also count as held (the main checkout's, when `--metrics`
  is the ride worktree's): a run either ledger holds by (ref, role,
  started_utc) is never written, and a continuation's `flush_segment` counts
  the larger of the ledgers' line counts for the ref. Without it nothing
  changes. `--held-in` without `--recover-archives` is exit 2.
- No second identity rule or line builder is written anywhere. The caller in
  merge-cleanup runs the CLI as a child process (the same way merge-cleanup
  already runs ride-handoff reconcile) through one exported helper in
  `.aai/scripts/lib/metrics-flush-record.mjs`.

### D3. merge-cleanup `archive-runtime`

After the archive copy is made (archive first, unchanged), the step runs the
recovery over the ARCHIVED copy (so the line's `reconstructed.source` names
the durable archive path `docs/ai/archive/merge-cleanup/pr-<n>/worktree/docs/ai/STATE.yaml`),
with `--state` the worktree STATE, `--metrics` the worktree METRICS,
`--held-in` twice: the main checkout's working METRICS and the METRICS at
`refs/remotes/origin/<base>` (the commit the base sync lands on, written by
the helper to a temporary file and removed after; review round 2, B3),
`--pricing` the engine's own `.aai/system/PRICING.yaml`, cwd the worktree.
The held ledgers keep a resumed cleanup (the tail already moved to the main
checkout and the worktree ledger reset to its HEAD blob), a run another flush
already put in the main ledger, and a run another PR merged on the base that
the main checkout has not pulled yet from being written a second time.

1. A dry run first counts the missing runs. Zero: nothing is written.
2. More than zero, and the worktree is at the PR head and its
   `docs/ai/METRICS.jsonl` exists: the real run appends the line(s) to the
   worktree METRICS. The remove-worktree step then moves them to the main
   checkout with the other ledger tails.
3. More than zero but the worktree is not at the PR head, or it has no
   METRICS file, or the child fails: nothing is written; the step is
   `retained` with reason `ledger_runs_unchecked` (a `kept('archive-runtime')`
   outcome) and its detail names the count or the error and the exact command
   to run from the main checkout:
   `node .aai/scripts/metrics-flush.mjs --recover-archives --include-focus --state <archive path> --archive <archive path>`.
   The archive copy holds the runs, so nothing is lost when the other steps
   (including the worktree removal) run.
4. Step result: `done` with detail `1 archived` and, when runs were written,
   `; <k> run(s) recovered to worktree:docs/ai/METRICS.jsonl`; on a re-run
   with nothing new archived and nothing recovered, `noop already_archived`.
5. Plan mode (read-only): the archive-runtime targets add
   `recover <k> run(s) of <refs> -> worktree:docs/ai/METRICS.jsonl`, or
   `keep (ledger_runs_unchecked <detail>)`, using the dry run over the live
   worktree STATE. Nothing is written.
6. merge-cleanup.mjs stays at or below its 1490-line ceiling (TEST-058,
   TEST-2923); the child-process call and result parsing live in the helper.

### D4. SKILL_WORKTREE manual cleanup

Cleanup Worktree step 2 keeps the `cp` and adds one command right after it,
run from the main checkout:
`node .aai/scripts/metrics-flush.mjs --recover-archives --include-focus --state <archived copy> --archive <archived copy>`.
It writes the runs the main checkout's METRICS lacks (an abandoned
worktree's runs reach no other ledger). A comment line in the block says that
a merged branch must pull main first, else the runs its flush lines carry are
written a second time (review round 1, N1). The Safety section names the command
in the existing archive-first bullet. Byte growth is credited in the
prompt-diet ledger.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN metrics-flush runs with --recover-archives --include-focus, --state and --archive naming the same STATE whose current_focus ref F holds one run the ledger has and one it lacks, it SHALL exit 0, print no SKIP line, append exactly one line for F holding only the missing run with flush_segment 2 and reconstructed as the last key, and leave the STATE byte-identical; the same call without --include-focus SHALL append nothing and print the NOTE that the file is the --state file; --include-focus without --recover-archives SHALL exit 2 with the ledger unchanged | done | TEST-3751 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D2 |
| Spec-AC-02 | WHEN the D2 call is repeated it SHALL exit 0, append nothing and report recovered=0; its --dry-run SHALL leave METRICS and STATE byte-identical and print one JSON plan whose entries deep-equal the line the real run with the same --now appends | done | TEST-3752 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D2; idempotence; read-only dry run |
| Spec-AC-03 | WHEN merge-cleanup apply runs for a merged ride whose worktree STATE (focus foo) holds a run that the PR's METRICS line holds and a later run that it does not, it SHALL exit 0, the main checkout's METRICS SHALL hold the later run exactly once in a reconstructed line for foo with flush_segment 2 and the held run exactly once, the archive-runtime step SHALL be done with a detail naming 1 run recovered, and the archived copy SHALL equal the pre-run worktree STATE | done | TEST-3753 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D1, D3 steps 1, 2, 4; seam archive-runtime to remove-worktree tail move to main ledger |
| Spec-AC-04 | WHEN every run of the worktree STATE is already in the PR's METRICS line, merge-cleanup apply SHALL leave the main checkout's METRICS equal to the merge commit's blob and report archive-runtime done with detail 1 archived and no recovered count; a second apply SHALL report archive-runtime noop already_archived and leave METRICS unchanged | done | TEST-3754 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D3 step 1 and 4; idempotence |
| Spec-AC-05 | WHEN merge-cleanup plan runs for the Spec-AC-03 world it SHALL exit 0, change no file of the fixture (world digest equal), create no archive directory, and its archive-runtime targets SHALL include recover 1 run(s) of foo -> worktree:docs/ai/METRICS.jsonl | done | TEST-3755 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D3 step 5; read-only plan |
| Spec-AC-06 | WHEN the ride worktree has no docs/ai/METRICS.jsonl but its STATE holds a run, merge-cleanup apply SHALL exit 0, report archive-runtime retained with reason ledger_runs_unchecked and a remaining line holding the exact command metrics-flush.mjs --recover-archives --include-focus --state and --archive naming the archive copy, keep the archive copy, and running that printed command from the main checkout SHALL append the run to the main checkout's METRICS | done | TEST-3756 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D3 step 3; the loud fallback |
| Spec-AC-07 | the Cleanup Worktree section of .aai/SKILL_WORKTREE.prompt.md SHALL carry, in its step 2 block after the cp, the command metrics-flush.mjs --recover-archives --include-focus naming the archived copy; WHEN that block runs with its placeholders filled against a fixture whose worktree STATE holds a run the main METRICS lacks, the run SHALL be in the main METRICS afterwards; the prompt-diet ledger SHALL credit the measured growth and test-aai-prompt-diet.sh SHALL pass | done | TEST-3757 PASS, mutation killed; prompt-diet TEST-010 and TEST-012 PASS; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D4; companion obligation |
| Spec-AC-09 | WHEN a merge-cleanup apply wrote a recovered run, moved the tail to the main checkout and stopped before the worktree removal, a second apply SHALL exit 0, report no recovered run for archive-runtime and leave that run exactly once in the main checkout's METRICS; WHEN the ride STATE carries a run of another ref that only the main checkout's METRICS holds, or that only the base branch's METRICS holds because another PR merged there and the main checkout has not pulled it, apply SHALL not write it again and that run SHALL be exactly once in the main METRICS after the base sync | done | TEST-3759, TEST-3760 and TEST-3761 PASS, mutations killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | D2 --held-in, D3; review round 1 B1 and B2, review round 2 B3 |
| Spec-AC-08 | docs/product/telemetry.md SHALL state that merge-cleanup and the worktree cleanup write the archived copy's missing runs through --recover-archives --include-focus; CHANGELOG.md SHALL hold exactly one per-entry heading for this fix in the form unreleased or a rolled vYYYY.MM.DD, then an em dash and fix | done | TEST-3758 PASS, mutation killed; docs/ai/reports/VALIDATION-20261115T1927Z-archive-ledger-check.md | — | Consumer-visible; merge-cleanup ships downstream |

## Implementation plan

Components:
- `.aai/scripts/metrics-flush.mjs`: `parseArgs` gains `--include-focus`
  (boolean, only with `--recover-archives`, else exit 2; listed in the
  unknown-flag message); `handleRecoverArchives` skips the `--state`
  exclusion and the focus skip when it is set; header paragraph updated.
- `.aai/scripts/lib/metrics-flush-record.mjs`: one export,
  `recoverStateCopy({ scriptDir, root, copy, rel, writable, dryRun })`
  -> `{ would, refs, recovered, keep }`, which spawns the CLI (cwd `root`,
  `--state` and `--metrics` under `root/docs/ai/`, `--pricing` beside
  `scriptDir`) and reads the dry run's JSON or the real run's
  `RECOVER SUMMARY` line; `keep` is null or the D3 step 3 detail with the
  fallback command naming `rel`.
- `.aai/scripts/merge-cleanup.mjs`: `archiveRuntime` and its planner (D3);
  the import; no other step changes.
- `.aai/scripts/lib/merge-outcomes.mjs`: `ledger_runs_unchecked:
  kept('archive-runtime')` and the `STEP_OBJECT` entry for archive-runtime.
- `.aai/SKILL_WORKTREE.prompt.md`: D4.
- Tests, suite-map globs (aai-merge-cleanup gains metrics-flush.mjs and
  lib/metrics-flush-record.mjs; aai-worktree gains metrics-flush.mjs), the
  prompt-diet true-up, `docs/product/telemetry.md`, `CHANGELOG.md`.

Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor
a mutation to the code it writes, disclosed as a measurement amendment):
- metrics-flush: `if (ref === focusRef && !opts.includeFocus) { skipped[ref] = SKIP_FOCUS; continue; }`
- metrics-flush: `if (opts.dryRun) { printRecoveryPlan(plan); exit(0); }` (unchanged SPEC-0292 line)
- merge-cleanup: `if (g.keep) return keepStep(ctx, 'archive-runtime', 'ledger_runs_unchecked', g.keep);`
- lib: `const write = writable && would > 0;`

Seams crossed (each by a real producer and a real reader):
- Ride worktree STATE (producer: a fixture in STATE's own shape read by the
  real parser) to the recovery writer: TEST-3751, TEST-3752.
- archive-runtime's write (producer) to the remove-worktree tail move and the
  main checkout's ledger (reader): TEST-3753, TEST-3754 run the real engine
  end to end in the existing build_world fixture.
- Printed fallback command (producer) to a real run from the main checkout
  (reader): TEST-3756.
- Prompt block (producer) to a real run: TEST-3757 extracts and runs it.
- Not crossed by a test: a ride whose worktree HEAD differs from the PR head
  (D3 step 3 branch shares the code path with the no-METRICS case; R2).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3751 | Spec-AC-01 | integration | tests/skills/test-aai-metrics.sh | fixture STATE focused on F with two runs, ledger line for F holding one: --include-focus with --state and --archive the same file appends one line for F with only the missing run, flush_segment 2, reconstructed last, no SKIP, STATE byte-identical; without the flag nothing is appended and the NOTE is printed; the flag without --recover-archives exits 2 | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(ref === focusRef && !opts.includeFocus\)/if (ref === focusRef)/` skips the ending ride and the case must fail | green |
| TEST-3752 | Spec-AC-02 | integration | tests/skills/test-aai-metrics.sh | dry run first: METRICS and STATE unchanged, the plan entries deep-equal the line the following real run appends with the same --now; a second real run appends nothing and prints recovered=0 | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(opts.dryRun\) \{ printRecoveryPlan\(plan\); exit\(0\); \}/if (false) { printRecoveryPlan(plan); exit(0); }/` makes the dry run write and the case must fail | green |
| TEST-3753 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | build_world with a tracked METRICS line for foo in the PR and a worktree STATE holding that run plus a later one: apply exits 0, the main METRICS holds the later run once in a reconstructed foo line with flush_segment 2 and the earlier run once, archive-runtime done naming 1 run, the archived copy equals the pre-run STATE | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/const write = writable && would > 0;/const write = false;/` writes nothing and the case must fail | green |
| TEST-3754 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | same world with every run already in the PR line: apply leaves the main METRICS equal to the merge commit's blob, archive-runtime done with detail 1 archived and no recovered text; a second apply reports archive-runtime noop already_archived and METRICS unchanged | target `.aai/scripts/metrics-flush.mjs`; `sed:s/if \(held.has\(roleStartKey\(ref, run\)\)\) continue;/if (false) continue;/` writes the held run again and the case must fail | green |
| TEST-3755 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | plan over the Spec-AC-03 world: exit 0, world digest equal, no archive directory, archive-runtime targets include recover 1 run(s) of foo -> worktree:docs/ai/METRICS.jsonl | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/'--recover-archives', '--include-focus'/'--recover-archives'/` makes the dry run skip foo, the target line is missing and the case must fail | green |
| TEST-3756 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | worktree without docs/ai/METRICS.jsonl and a STATE run: apply exits 0, archive-runtime retained with ledger_runs_unchecked, the remaining line holds the exact command naming the archive copy, the archive copy exists; the printed command run from the origin appends the run to the origin METRICS | target `.aai/scripts/merge-cleanup.mjs`; `sed:s/if \(g.keep\) return keepStep\(ctx, 'archive-runtime', 'ledger_runs_unchecked', g.keep\);//` reports the step done without the command and the case must fail | green |
| TEST-3757 | Spec-AC-07 | integration | tests/skills/test-aai-worktree.sh | extract the Cleanup Worktree step 2 bash block, fill its placeholders with a fixture main checkout and a worktree STATE holding a run the main METRICS lacks, run it: the archived copy exists and the main METRICS holds the run in a reconstructed line; the block names --include-focus; test-aai-prompt-diet.sh TEST-010 and TEST-012 pass | target `.aai/SKILL_WORKTREE.prompt.md`; `sed:s/ --include-focus --state/ --state/` drops the flag, the focus ride is skipped and the case must fail | green |
| TEST-3759 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | metrics_world with a late run: the first apply is stopped by the before-remove-verify touch seam after the tail move; after undoing the touch a second apply exits 0, archive-runtime names no recovered run, the late run is once in the main METRICS | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/, \.\.\.held\.flatMap\(\(f\) => \['--held-in', f\]\)\]/]/` drops the held ledgers from the check and the case must fail | green |
| TEST-3760 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | the main METRICS holds a line for bar that the PR head lacks and the ride STATE carries bar's run: apply exits 0, archive-runtime names no recovered run, bar's run is once in the main METRICS | target `.aai/scripts/metrics-flush.mjs`; `sed:s/for \(const k of more.held\) held.add\(k\);//` ignores the --held-in ledger and the case must fail | green |
| TEST-3761 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | another PR with bar's line merged on the bare main before ours and the main checkout not pulled, the ride STATE carries bar's run: apply exits 0, sync-base done, archive-runtime names no recovered run, bar's run is once in the main METRICS | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/fs.writeFileSync\(tmp, blob.stdout\); held.push\(tmp\);/fs.writeFileSync(tmp, blob.stdout);/` leaves the base ledger out and the case must fail | green |
| TEST-3758 | Spec-AC-08 | unit | tests/skills/test-aai-metrics.sh | CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix naming the archive step; docs/product/telemetry.md names --include-focus and merge-cleanup | target `CHANGELOG.md`; `sed:s/— fix: archiving a ride's STATE copy/— fix: x/` removes the named heading and the case must fail | green |

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suites'
`set -euo pipefail` (no `printf | grep -q`).

1. RED before GREEN: `docs/ai/tdd/archive-ledger-check/red-*.log` and
   `green-*.log`. RED for TEST-3751 is `unknown flag "--include-focus"` (exit
   2); RED for TEST-3753 is the late run absent from the main METRICS after
   apply on the unchanged engine.
2. `bash tests/skills/test-aai-metrics.sh`, `test-aai-merge-cleanup.sh`,
   `test-aai-worktree.sh`, `test-aai-prompt-diet.sh`,
   `test-aai-pr-preflight.sh` exit 0; TEST-058 and TEST-2923 stay green
   (merge-cleanup.mjs <= 1490 lines).
3. Mutation records for TEST-3751..3758 under
   `docs/ai/tdd/spec-archive-ledger-check/` via `mutation-run.mjs`.
4. One full sweep before close with `AAI_TEST_TIMEOUT=4500`.
5. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id archive-ledger-check, its Spec-AC and TEST links,
the command, the exit code and the evidence path, plus the commit SHA once
one exists. RED and GREEN logs under docs/ai/tdd/archive-ledger-check/,
mutation records under docs/ai/tdd/spec-archive-ledger-check/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Out of scope

- Other places that archive a STATE copy (ride-handoff out, planning
  transfer, `metrics-flush` pre-flush recovery files): their copies are
  either of an in-flight ride whose runs travel with it or are recovered by
  the default `--recover-archives` sweep. Not changed here.
- Committing the main checkout's uncommitted ledger lines after cleanup: the
  existing carry (reconcile-telemetry, the next ledger-carrying PR) is
  unchanged.
- `fu-recovery-in-flight-non-focus` (R1 of SPEC-0292): unchanged; this scope
  only stops skipping the focus when the caller says the ride ended.

## Registry items closed by this scope

`fu-archive-step-skips-ledger-check` (P3): closed by Spec-AC-03..07. Checked
`node .aai/scripts/follow-ups.mjs list` (344 open); no other open item names
archiveRuntime or the worktree cleanup archive step.

## Residual risks

- R1. If someone runs the default `--recover-archives` sweep in the main
  checkout after the archive step but before the remove-worktree step moved
  the worktree tail (a kept or interrupted cleanup), the runs are written to
  the main ledger, and the later tail move adds the worktree's line too: the
  run is counted twice. A re-run of the cleanup does not add a third copy
  (`--held-in`, Spec-AC-09), but it does not remove the second one either;
  the window is a manual sweep between two cleanup steps.
- R2. A worktree that is not at the PR head takes the loud fallback (D3 step
  3), not a write; the person runs the printed command. Tested only through
  the shared no-METRICS branch.
- R3. A run without started_utc cannot be keyed and is not recovered (the
  SPEC-0292 NOTE); state.mjs always stamps started_utc, so none is expected.

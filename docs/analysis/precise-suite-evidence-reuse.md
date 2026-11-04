---
id: precise-suite-evidence-reuse
type: analysis
status: draft
updated: 2026-10-31
---

# Precise reuse of local suite results: measured effect

Spec: docs/specs/SPEC-DRAFT-spec-precise-suite-evidence-reuse.md (D11, Spec-AC-13
as amended by M1). This note reports what reuse bought on three rounds and,
plainly, where it did not. It makes no claim that reuse is faster on the
representative round: on that round it reused nothing.

## Measurements

R1 and R2 were measured on commit 97790628adef95b13736e79e0bb3c8d7a61e2f53
(the branch tip that carried the helper, the manifest and the framework
wiring); R3 was re-measured after validation round 1 on commit
316d1187c28154f0651d964e0fad232a63df6d51, the commit that corrects the manifest
(see the R3 line). Each round ran in a disposable detached worktree of its
commit, never in the shared main checkout. Each round: one seed run with reuse on on the clean tree, a copy of
`tests/skills/results/reuse/` as a snapshot, the round delta applied, then six
samples alternating off (`AAI_SUITE_REUSE=0`) and on, restoring the store from
the snapshot before every on sample. Command per sample:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill <each suite>`
with `AAI_TEST_TIMEOUT=3000` and `AAI_ROLE` unset. Wall seconds are whole
seconds from `date +%s` around the command. "Check s" is the number printed on
the framework line `Evidence reuse: on (<M> of <N> suites reused, check <s>s)`.

- R1: the M5 round of the spec, a remediation-shaped delta of one comment line
  appended to `.aai/scripts/ride-status.mjs`. Suites: aai-check-state,
  aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-ride-status,
  aai-win-fallback, aai-prompt-diet (7).
- R2: a second round whose delta is one production-script edit that changes
  no docs/ file: one comment line appended to `.aai/scripts/orchestration-mode.mjs`.
  Suites, as selected plus CORE by `select-suites.mjs`: aai-check-state,
  aai-docs-content, aai-spec-lint, aai-hygiene-pack, aai-orchestration-mode,
  aai-prompt-diet (6).
- R3: a supplementary round, added after R1 and R2 reused nothing, to show
  where reuse does help: the five suites declared in the manifest
  (aai-feedback-status, aai-pricing, aai-redact, aai-orchestration-mode,
  aai-runtime-file) re-checked after a comment line was appended to the
  unrelated production script `.aai/scripts/pr-preflight.mjs`. R3 was first
  measured with aai-check-state in the manifest in place of aai-feedback-status
  (4 of 5 reused); validation round 1 showed that aai-check-state reads files
  outside its identity, so it was removed and R3 was measured again on the
  corrected manifest. The table and medians below are the second measurement.
  R1 and R2 stay as first measured: aai-check-state was run in both modes of
  those rounds, so removing it from the manifest changes neither their wall
  time nor their reused count (0).

| Round | Sample | Mode | Wall s | Executed | Reused | Check s |
|---|---|---|---|---|---|---|
| R1 | 1 | off | 93 | 7 | 0 | - |
| R1 | 1 | on | 92 | 7 | 0 | 0 |
| R1 | 2 | off | 93 | 7 | 0 | - |
| R1 | 2 | on | 94 | 7 | 0 | 0 |
| R1 | 3 | off | 92 | 7 | 0 | - |
| R1 | 3 | on | 92 | 7 | 0 | 0 |
| R2 | 1 | off | 91 | 6 | 0 | - |
| R2 | 1 | on | 91 | 6 | 0 | 0 |
| R2 | 2 | off | 90 | 6 | 0 | - |
| R2 | 2 | on | 99 | 6 | 0 | 0 |
| R2 | 3 | off | 106 | 6 | 0 | - |
| R2 | 3 | on | 100 | 6 | 0 | 0 |
| R3 | 1 | off | 4 | 5 | 0 | - |
| R3 | 1 | on | 1 | 0 | 5 | 0 |
| R3 | 2 | off | 5 | 5 | 0 | - |
| R3 | 2 | on | 1 | 0 | 5 | 0 |
| R3 | 3 | off | 5 | 5 | 0 | - |
| R3 | 3 | on | 2 | 0 | 5 | 0 |

Round R1 medians: off 93 s, on 92 s, reused 0 of 7 suites (worst off 93 s, worst on 94 s).

Round R2 medians: off 91 s, on 99 s, reused 0 of 6 suites (worst off 106 s, worst on 100 s).

Round R3 medians: off 5 s, on 1 s, reused 5 of 5 suites (worst off 5 s, worst on 2 s).

Every check time is 0 s (limit 5 s). On R1 and R2 the on and off medians differ
by run-to-run noise only (92 against 93, 99 against 91): nothing was reused, so
the on mode did the same work plus a sub-second identity calculation.

Environment: host Apple M4 Max, 16 logical CPUs, macOS 27.0.1 (Darwin 27.0.0 arm64);
Node v22.23.1; Bash GNU bash 3.2.57(1)-release (the system bash the framework
runs under); Git 2.54.0 (Apple Git-157).

R3 re-measured on 2026-11-01 at commit cb2cafdd (after the after-literal rule
and the `lib/` allowlist), same delta and procedure, five separate wrapped
framework runs per sample (one per suite, so each sample also carries five
wrapper start-ups): off 16 s in all three samples, on 10 s in all three,
reused 3 of 5 (aai-feedback-status, aai-pricing, aai-redact);
aai-orchestration-mode and aai-runtime-file ran in both modes.

### Where reuse helps

Reuse helps for a suite whose declared identity is narrow: its suite file, the
shared-library tree, the harness and a handful of named data files. R3 shows
it: all five manifest suites were reported REUSED and skipped, wall time 5 s
to 1 s (an all-reused run executes nothing; its summary carries `Reused: 5` and
`Total: 0`). That measurement is tied to its commit: at the head of 2026-11-01 only 3 of the 5 manifest suites can reuse, because aai-orchestration-mode and aai-runtime-file are inputs-unresolvable (a `${VAR:-path}` literal) and always run. The absolute saving is
small because the manifest suites are the cheap, pure ones (weights of a few
seconds). It would grow with more suites qualified into the manifest, but only
suites whose closure stays narrow can qualify honestly.

### Why the docs-closure suites miss

The expensive suites of the representative round are not reusable, by design
and by measurement. `suite-reuse.mjs explain` on aai-docs-content,
aai-spec-lint, aai-hygiene-pack, aai-prompt-diet, aai-ride-status and
aai-win-fallback gives closures of about 3,430 files, 2,506 of them under
docs/, including docs/ai/EVENTS.jsonl and the docs/ai/STATE files. Three
mechanisms keep those identities moving:

- The framework itself appends a line to the tracked
  `docs/ai/tests/test-runs.jsonl` on every run, and EVENTS and STATE change
  with every role action, all under docs/. Any suite whose closure reaches
  docs/ sees a different identity on the very next run, even with no edit.
- Shared-library prose literals: test-side files under `tests/skills/lib/`
  (for example `prompt-diet-ledger.sh`, `docs-audit-live.sh`) name docs/
  directories in text, and the closure follows every such literal, so a suite
  that merely sources the lib inherits the whole docs/ tree.
- These suites also read the real repository history (a history marker in the
  closure), so HEAD is part of the identity.

None of these suites is in the manifest, so they report
`RUN <suite> reason=not-declared`; the rule that errs toward a miss is working
as designed. Listing them would give a false hit risk (R1 of the spec) that the
measured closure shows cannot be bounded by a reviewed `note`.

One further miss in R1 and R2 is not docs-related. aai-orchestration-mode is
the suite whose own input was edited in R2, a legitimate miss.

aai-check-state was in the manifest when R1 to R3 were first measured, and it
missed in all three rounds, which the first draft of this note put down to the
closure rule reading a sandbox write destination (`$sandbox/.aai/scripts/`) as
a directory of 176 files. That explanation was incomplete and the suite did not
belong in the manifest. Validation round 1 traced its reads and showed that it
also runs `orchestration-dispatch.mjs` against the real checkout, which reads
`docs/TECHNOLOGY.md`, `.aai/workflow/WORKFLOW.md`, `.aai/system/LOCKS.md`,
`.aai/system/MODEL_ROUTING.yaml`, `docs/ai/roadmap.yaml` and `docs/issues/*`
(359 files), none of them in its identity. Renaming `docs/TECHNOLOGY.md` left
the suite reported REUSED although a re-run failed. The suite was removed from
the manifest; the miss in R1 to R3 was thus a symptom of a closure that was
too narrow in one direction and too wide in another, not a tuning problem.

## Manifest suites

aai-feedback-status, aai-pricing, aai-redact, aai-orchestration-mode,
aai-runtime-file (five suites, `tests/skills/suite-reuse.json`). None of the
seven suites of the M5 round qualifies: they either read docs/ broadly or are
dominated by the docs closure described above, so no honest `note` can bound
their reads. Each manifest suite is qualified by a Node fs read trace of the
whole suite plus a literal review of its bash, and TEST-3193 repeats the trace
on every run of the reuse suite, so a manifest entry whose traced Node fs read
falls outside its identity fails the test instead of waiting for a validator
to find it.

The trace is narrower than "reads nothing outside the identity". These read
paths are not traced and are covered only by the literal bash review and the
manifest note: bash `cat`, `grep`, `cp` and `source`; `git` commands; Node
`fs.promises` reads; `fs.copyFileSync` and `fs.cpSync`; and any child process
whose environment drops `NODE_OPTIONS` (release-dry-run.mjs does). A manifest
suite that reads a docs file through bash `cat` passes TEST-3193. The residual
risk R1 therefore stands for those channels.

## Measurements (trace identity)

The SPEC-0266 section above stays as history. This section measures the access
trace identity of the change that replaced the source-text reader, following
the protocol of its D11. Measured commit: 770210a1c5c2081339bcc9482b0a518c9db1f8f8
(the implementation tip), in a disposable detached worktree of that commit,
never in the shared main checkout.

Method. Suites (8): aai-check-state, aai-docs-content, aai-spec-lint,
aai-hygiene-pack, aai-pr-preflight, aai-prompt-diet, aai-ride-status,
aai-win-fallback. One seed run with reuse on; a copy of
`tests/skills/results/reuse/` as the snapshot; then two rounds, each with six
samples alternating off (`AAI_SUITE_REUSE=0`) and on, restoring the store from
the snapshot before every on sample. R0 is the zero delta (no edit). R1 appends
one comment line to `.aai/scripts/pr-preflight.mjs`. Command per sample:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` with one `--skill` per
suite, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE` unset. Wall seconds are whole seconds
from `date +%s`; "Executed" is the framework's Total line, "Reused" its Reused
line, "Check s" the number on `Evidence reuse: on (<M> of <N> suites reused, check <s>s)`.
All twelve samples exited 0.

| Round | Sample | Mode | Wall s | Executed | Reused | Check s |
|---|---|---|---|---|---|---|
| R0 | 1 | off | 105 | 8 | 0 | - |
| R0 | 1 | on | 108 | 7 | 1 | 1 |
| R0 | 2 | off | 107 | 8 | 0 | - |
| R0 | 2 | on | 110 | 7 | 1 | 0 |
| R0 | 3 | off | 109 | 8 | 0 | - |
| R0 | 3 | on | 124 | 7 | 1 | 1 |
| R1 | 1 | off | 109 | 8 | 0 | - |
| R1 | 1 | on | 121 | 7 | 1 | 0 |
| R1 | 2 | off | 104 | 8 | 0 | - |
| R1 | 2 | on | 118 | 7 | 1 | 0 |
| R1 | 3 | off | 128 | 8 | 0 | - |
| R1 | 3 | on | 123 | 7 | 1 | 0 |

Round R0 medians: off 107 s, on 110 s, reused 1 of 8 suites (worst off 109 s, worst on 124 s).

Round R1 medians: off 109 s, on 121 s, reused 1 of 8 suites (worst off 128 s, worst on 123 s).

On did not beat off in either round: the one suite that reuses is the cheapest
of the large ones (aai-ride-status, about 15 s) and it runs concurrently with
the longest suite (aai-hygiene-pack, about 95 s), which sets the wall time, so
reusing it saves nothing on the wall clock. The differences between the
medians (110 against 107, 121 against 109) are run-to-run noise of this
host plus a check of at most 1 s. The lesson is the one the spec predicted.

Per suite, the outcome of every on sample (identical in all three samples of
a round; the RUN reason is what `suite-reuse.mjs check` printed against the
restored store, with the framework's own environment, and the framework
executed exactly the suites it names) and the files the recorded trace read:

| Suite | Files read (record) | R0 on | R1 on |
|---|---|---|---|
| aai-check-state | not traced (not in the manifest) | RUN reason=not-declared | RUN reason=not-declared |
| aai-docs-content | 1536 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-spec-lint | 1481 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-hygiene-pack | 1950 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-pr-preflight | not traced (not in the manifest) | RUN reason=not-declared | RUN reason=not-declared |
| aai-prompt-diet | 1935 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |
| aai-ride-status | 27 files, git index not read | REUSED | REUSED |
| aai-win-fallback | 1935 files, git index read | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl | RUN reason=inputs changed .aai/scripts/pr-preflight.mjs |

What the table shows. aai-ride-status, which the source-text reader could never
reuse (3,188 inputs, 2,194 unresolvable forms), is reused after a zero delta
and after an edit of an unrelated production script, with 27 files read. The
five large suites read the whole checkout, so they are admitted but are reused
only when no tracked file changed; even the zero delta misses, because the
framework appends a line to the tracked `docs/ai/tests/test-runs.jsonl` after
every run and those suites read that file (follow-up
`fu-reuse-local-ledger-append`). The corpus-wide cases of those suites would
have to be split from their fixture cases to change this
(`fu-reuse-split-corpus-cases`). No edit of the ledger writer was made.

Trace cost: arm plus collect took 178 ms (median of five, range 167 to 219 ms;
arm about 155 ms, collect about 20 ms) on the 1,950-file checkout of the
measured commit, per traced suite, run in-process on a fresh local clone. The
framework's per-suite overhead beyond that is the two helper process starts.

Environment: host Apple M4 Max, 16 logical CPUs, macOS 27.0.1 (Darwin 27.0.0
arm64); Node v22.23.1; Bash GNU bash 3.2.57(1)-release; Git 2.54.0 (Apple
Git-157).

Identity and its limits (validation round 1). An input's identity is its
sha256 plus its executable bit (`mode & 0o111`), because a validator showed
that `chmod -x` on a script a suite runs left the suite REUSED while a fresh
run failed; the change only adds misses (SPEC amendment recorded under
`fu-amend-reuse-for-docs-reading-suites`). Three read classes stay outside the
identity and fall under the D3 caveat, each reproduced by the validator: a file
the suite only stat-s (`[ -s f ]`) is not seen, an environment variable read as
`process.env['X']` is not named, and a file read through an APFS clone
(`cp -c`) does not advance the original's access time. The admission gate's
poisoned run overwrites only the checkout files on the path list that the trace did
not see read (and poisons nothing when the trace saw the git index read), and requires
the suite to exit 0, at admission time only; it does not look at the clone case
as such, and the other two are accepted risk.

## Measurements (ledger append)

SPEC `spec-reuse-local-ledger-append` D6. The sections above stay as history. This
section measures what the run-ledger append tolerance changes: for each of two
commits, a disposable detached worktree of that commit (never the shared main
checkout), one framework run of the eleven manifest suites with reuse on (the
seed), the per-suite outcome of `suite-reuse.mjs check` against the seed's store
with the framework's environment, then one zero-delta rerun with reuse on and no
edit in between. Command for both runs:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` with one
`--skill` per manifest suite, `AAI_TEST_TIMEOUT=3000`, `AAI_ROLE` unset.

Before: 9c487740cf606419046a3f5488508520507ff9e3 (main at planning time). After:
0d7992dcbbcde189a9c28b62f13600148bc13ec9 (the implementation tip). Host: Apple M4 Max,
macOS 27.0.1, Node v22.23.1, Bash 3.2.57 (GNU bash), Git 2.54.0.

The "after" run was taken at 0d7992dc; only tests and docs changed between that commit and the branch tip, and validation round 1 reproduced the result at e7797c86 (113 s seed, 1 s rerun, 11 of 11 suites reused).

| Commit | Seed exit | Seed wall s | Rerun exit | Rerun wall s | Rerun reuse line |
|---|---|---|---|---|---|
| before | 0 | 112 | 0 | 109 | Evidence reuse: on (6 of 11 suites reused, check 0s) |
| after | 0 | 112 | 0 | 1 | Evidence reuse: on (11 of 11 suites reused, check 0s) |

Per suite, REUSED or the first RUN reason that `check` printed after the seed:

| When | Suite | Outcome |
|---|---|---|
| before | aai-ride-status | REUSED |
| before | aai-feedback-status | REUSED |
| before | aai-pricing | REUSED |
| before | aai-redact | REUSED |
| before | aai-orchestration-mode | REUSED |
| before | aai-runtime-file | REUSED |
| before | aai-docs-content | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl |
| before | aai-spec-lint | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl |
| before | aai-hygiene-pack | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl |
| before | aai-prompt-diet | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl |
| before | aai-win-fallback | RUN reason=inputs changed docs/ai/tests/test-runs.jsonl |
| after | aai-ride-status | REUSED |
| after | aai-feedback-status | REUSED |
| after | aai-pricing | REUSED |
| after | aai-redact | REUSED |
| after | aai-orchestration-mode | REUSED |
| after | aai-runtime-file | REUSED |
| after | aai-docs-content | REUSED |
| after | aai-spec-lint | REUSED |
| after | aai-hygiene-pack | REUSED |
| after | aai-prompt-diet | REUSED |
| after | aai-win-fallback | REUSED |

Before, the five index-reading suites (aai-docs-content, aai-spec-lint,
aai-hygiene-pack, aai-prompt-diet, aai-win-fallback) each miss on the one input
the framework itself changed, `docs/ai/tests/test-runs.jsonl`, so the rerun
executes them and takes as long as the seed. After, all eleven are reused and the
rerun takes about a second. Any other tracked change still misses (TEST-3301).

## Measurements (corpus split)

SPEC `spec-reuse-split-corpus-cases` D6. The sections above stay as history. This section
holds the case inventory of the five suites that were considered for a split and the
before and after reruns of two representative edits.

Host: Apple M4 Max, macOS 27.0.1, Node v22.23.1, GNU bash 3.2.57 (Bash 3.2.57), Git 2.54.0.
Baseline (before): 6db05ffa562ba582a8f4e597417a95042ed60801 (main at planning time). Implementation tip (after):
c8bc6c36286b999362dbb303196996eeee167978; only tests and documents changed between that commit and the branch head.

### Case inventory

Method (M1): for each suite a fresh `git clone --local --no-hardlinks` of the implementation
tip, detached; for every case of the suite's full-run list at the baseline commit, in list
order, `git reset --hard` and `git clean -fd`, the access trace armed with
`.aai/scripts/lib/checkout-trace.mjs`, the case alone through the suite's single-case dispatch,
the trace collected. The cases of aai-docs-content share state, so they were traced in one bash
process that sources the definition file. Class: index (the trace read the git index), wide (no
index read, at least 100 checkout files read), ledger (reads docs/ai/decisions.jsonl,
docs/ai/METRICS.jsonl or docs/ai/EVENTS.jsonl), fixture (everything else). Half: fixture and
corpus for the two split suites (corpus = the cases of HYGIENE_CORPUS_CASES and
WIN_FALLBACK_CORPUS_TESTS), unsplit for the three suites that were not split. Seconds are the
wall time of one case alone, including its own bash start.

| Suite | Case | Class | Files read | Index | Seconds | Half |
|---|---|---|---|---|---|---|
| aai-hygiene-pack | test_010_skill_pr | fixture | 8 | no | 0.1 | fixture |
| aai-hygiene-pack | test_011_external_review_response | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_012_report_staging | fixture | 5 | no | 0.0 | fixture |
| aai-hygiene-pack | test_013_metrics_flush_partial | fixture | 14 | no | 0.1 | fixture |
| aai-hygiene-pack | test_014_warnings_policy | fixture | 5 | no | 0.0 | fixture |
| aai-hygiene-pack | test_015_fixture_diversity | fixture | 5 | no | 0.1 | fixture |
| aai-hygiene-pack | test_016_wrapup_promise_and_guards | fixture | 12 | no | 0.1 | fixture |
| aai-hygiene-pack | test_017_invoke_lines | fixture | 27 | no | 0.1 | fixture |
| aai-hygiene-pack | test_018_skill_meta_loader | fixture | 7 | no | 0.0 | fixture |
| aai-hygiene-pack | test_022_pr_review_companions | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_030_auto_trigger_deprecation | wide | 1638 | no | 0.3 | corpus |
| aai-hygiene-pack | test_031_guard_config_conformance | fixture | 6 | no | 0.6 | fixture |
| aai-hygiene-pack | test_040_dual_verdict_prompt | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_041_anti_gaming_protocol | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_042_dual_verdict_surfaces | fixture | 9 | no | 0.1 | fixture |
| aai-hygiene-pack | test_043_review_taxonomy_alignment | wide | 474 | no | 0.6 | corpus |
| aai-hygiene-pack | test_050_pr_merge_conflict | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_051_no_number_prediction | fixture | 5 | no | 0.0 | fixture |
| aai-hygiene-pack | test_052_loop_drift_preflight | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_060_work_item_brief | index | 9 | yes | 0.1 | corpus |
| aai-hygiene-pack | test_070_companion_obligations | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_080_subagent_contract_exists | fixture | 4 | no | 0.0 | fixture |
| aai-hygiene-pack | test_081_no_rule_duplication | fixture | 5 | no | 0.0 | fixture |
| aai-hygiene-pack | test_082_dispatch_refs_name_contract | fixture | 9 | no | 0.0 | fixture |
| aai-hygiene-pack | test_083_subagent_contract_hazards | fixture | 4 | no | 4.9 | fixture |
| aai-hygiene-pack | test_090_suite_map_pin | fixture | 4 | no | 0.5 | fixture |
| aai-hygiene-pack | test_091_session_journal_index_complete | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_092_no_phantom_node_apis | wide | 139 | no | 0.1 | corpus |
| aai-hygiene-pack | test_093_test_registration | wide | 130 | no | 0.3 | corpus |
| aai-hygiene-pack | test_100_assert_payload_contract | fixture | 3 | no | 0.1 | fixture |
| aai-hygiene-pack | test_101_helper_survives_the_pipe_buffer | fixture | 3 | no | 0.1 | fixture |
| aai-hygiene-pack | test_102_pgq_ratchet_gate_and_bite | wide | 131 | no | 1.2 | corpus |
| aai-hygiene-pack | test_103_pgq_baseline_is_measured_not_typed | wide | 131 | no | 0.7 | corpus |
| aai-hygiene-pack | test_104_pgq_shrink_never_lowers_the_bar | wide | 131 | no | 0.7 | corpus |
| aai-hygiene-pack | test_562_no_nul_in_tracked_text | index | 1971 | yes | 0.4 | corpus |
| aai-hygiene-pack | test_563_pgq_scan_reports_read_errors | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_122_pgq_corpus_drained_to_zero | wide | 131 | no | 0.6 | corpus |
| aai-hygiene-pack | test_123_pgq_bite_at_zero_and_handtyped_baseline_rejected | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_124_degenerate_pass_guards_uncovered_and_ratcheted | index | 1957 | yes | 30.4 | corpus |
| aai-hygiene-pack | test_125_learned_guard_lints_bite | fixture | 4 | no | 0.4 | fixture |
| aai-hygiene-pack | test_126_learned_guard_lints_live_and_markers | wide | 211 | no | 0.4 | corpus |
| aai-hygiene-pack | test_668_session_bullets_carry_a_marker | fixture | 11 | no | 0.1 | fixture |
| aai-hygiene-pack | test_830_learned_split_conserves_every_line | fixture | 6 | no | 0.1 | fixture |
| aai-hygiene-pack | test_831_learned_standing_lint_live_and_bites | fixture | 5 | no | 0.2 | fixture |
| aai-hygiene-pack | test_832_sync_leaves_history_out_of_downstream | wide | 492 | no | 5.2 | corpus |
| aai-hygiene-pack | test_105_converted_sites_keep_their_needles | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_121_new_assert_payload_helpers | fixture | 3 | no | 0.1 | fixture |
| aai-hygiene-pack | test_106_base_ref_pin_gate_and_bite | wide | 150 | no | 0.4 | corpus |
| aai-hygiene-pack | test_107_base_ref_baseline_is_measured_not_typed | fixture | 5 | no | 0.1 | fixture |
| aai-hygiene-pack | test_108_cd_subshell_leak_gate_and_bite | wide | 164 | no | 0.7 | corpus |
| aai-hygiene-pack | test_109_cd_subshell_leak_baseline_is_measured_not_typed | fixture | 5 | no | 0.2 | fixture |
| aai-hygiene-pack | test_110_skill_set_parity | fixture | 4 | no | 0.4 | fixture |
| aai-hygiene-pack | test_111_generator_check_clean_and_idempotent | index | 1957 | yes | 1.1 | corpus |
| aai-hygiene-pack | test_112_generator_refuses_bad_manifest | fixture | 7 | no | 0.7 | fixture |
| aai-hygiene-pack | test_113_bite_proofs_in_detached_worktree | index | 1957 | yes | 4.4 | corpus |
| aai-hygiene-pack | test_114_cursor_rule_contract | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_115_root_shim_and_manifest_header | fixture | 5 | no | 0.0 | fixture |
| aai-hygiene-pack | test_120_userguide_catalog_covers_every_skill | fixture | 4 | no | 0.2 | fixture |
| aai-hygiene-pack | test_116_metrics_correction_not_counted | ledger | 4 | no | 0.1 | corpus |
| aai-hygiene-pack | test_117_source_skills_are_lf_pinned | index | 4 | yes | 0.1 | corpus |
| aai-hygiene-pack | test_118_bite_proofs_preserve_seeded_state | fixture | 5 | no | 4.9 | fixture |
| aai-hygiene-pack | test_119_generator_idempotence_preserves_seeded_state | fixture | 5 | no | 1.5 | fixture |
| aai-hygiene-pack | test_127_withdrawn_phrases_drained | wide | 765 | no | 0.6 | corpus |
| aai-hygiene-pack | test_128_shipping_scripts_pipe_safe_at_zero | fixture | 27 | no | 0.1 | fixture |
| aai-hygiene-pack | test_094_mutation_selector_fails_closed_corpus_wide | index | 1957 | yes | 10.7 | corpus |
| aai-hygiene-pack | test_135_selector_probe_counts | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_136_nonul_batch_equivalence | fixture | 4 | no | 1.0 | fixture |
| aai-hygiene-pack | test_129_mutation_gate_suite_registration | wide | 134 | no | 0.4 | corpus |
| aai-hygiene-pack | test_130_node_bash_selector_scanner_whitespace_parity | wide | 132 | no | 1.0 | corpus |
| aai-hygiene-pack | test_131_vendored_script_deps_gate_and_bite | wide | 198 | no | 0.5 | corpus |
| aai-hygiene-pack | test_132_nested_suite_lint_shapes | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_133_nested_suite_lint_live_and_base | wide | 129 | no | 1.4 | corpus |
| aai-hygiene-pack | test_134_nested_suite_disclosures | ledger | 9 | no | 1.6 | corpus |
| aai-hygiene-pack | test_137_hot_spot_disclosures | ledger | 9 | no | 1.6 | corpus |
| aai-hygiene-pack | test_138_ci_node_pins | wide | 186 | no | 0.1 | corpus |
| aai-hygiene-pack | test_139_node22_compat_step | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_140_technology_node_floor | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_141_node_floor_single_value | fixture | 12 | no | 0.1 | fixture |
| aai-hygiene-pack | test_142_rfc0017_node_row | fixture | 4 | no | 0.1 | fixture |
| aai-hygiene-pack | test_618_ref_guard_grep_conformance | fixture | 5 | no | 0.3 | fixture |
| aai-hygiene-pack | test_800_installed_hook_reaches_guard | fixture | 47 | no | 0.7 | fixture |
| aai-hygiene-pack | test_801_guard_block_propagates_block | fixture | 47 | no | 0.4 | fixture |
| aai-hygiene-pack | test_802_upgrade_inserts_once | fixture | 47 | no | 1.4 | fixture |
| aai-hygiene-pack | test_803_foreign_refusal_names_print_guard_checks | fixture | 47 | no | 0.5 | fixture |
| aai-hygiene-pack | test_804_pre_push_slot_contract | fixture | 47 | no | 1.7 | fixture |
| aai-hygiene-pack | test_805_feature_push_reports_open_doc | fixture | 47 | no | 1.4 | fixture |
| aai-hygiene-pack | test_806_enforce_refuses_default_branch_only | fixture | 47 | no | 1.0 | fixture |
| aai-hygiene-pack | test_807_default_branch_resolution_and_notes | fixture | 47 | no | 1.3 | fixture |
| aai-hygiene-pack | test_813_ps1_twin_parity | fixture | 48 | no | 1.9 | fixture |
| aai-hygiene-pack | test_814_disclosure_and_docs | fixture | 49 | no | 0.3 | fixture |
| aai-hygiene-pack | test_815_suite_map_and_registration | wide | 131 | no | 0.4 | corpus |
| aai-hygiene-pack | test_816_default_unchanged_and_pushed_config_wins | fixture | 47 | no | 1.0 | fixture |
| aai-hygiene-pack | test_817_marker_order_and_ownership_are_exact | fixture | 47 | no | 0.7 | fixture |
| aai-hygiene-pack | test_818_ps1_upgrade_is_byte_exact_and_order_checked | fixture | 48 | no | 4.6 | fixture |
| aai-hygiene-pack | test_819_nonregular_slot_is_refused_before_any_write | fixture | 47 | no | 0.3 | fixture |
| aai-win-fallback | test_007 | index | 1957 | yes | 6.8 | corpus |
| aai-win-fallback | test_009 | fixture | 6 | no | 0.0 | fixture |
| aai-win-fallback | test_013 | fixture | 4 | no | 0.0 | fixture |
| aai-win-fallback | test_014 | fixture | 4 | no | 0.0 | fixture |
| aai-win-fallback | test_015 | fixture | 8 | no | 0.1 | fixture |
| aai-win-fallback | test_016 | fixture | 4 | no | 0.0 | fixture |
| aai-win-fallback | test_017 | fixture | 7 | no | 0.1 | fixture |
| aai-win-fallback | test_018 | fixture | 6 | no | 0.0 | fixture |
| aai-win-fallback | test_019 | fixture | 4 | no | 0.1 | fixture |
| aai-win-fallback | test_020 | fixture | 7 | no | 0.1 | fixture |
| aai-win-fallback | test_021 | fixture | 4 | no | 0.1 | fixture |
| aai-win-fallback | test_022 | fixture | 5 | no | 0.0 | fixture |
| aai-win-fallback | test_023 | fixture | 7 | no | 0.0 | fixture |
| aai-win-fallback | test_024 | fixture | 14 | no | 0.1 | fixture |
| aai-win-fallback | test_025 | fixture | 5 | no | 0.0 | fixture |
| aai-win-fallback | test_026 | fixture | 7 | no | 0.0 | fixture |
| aai-win-fallback | test_027 | fixture | 3 | no | 0.0 | fixture |
| aai-win-fallback | test_028 | fixture | 4 | no | 0.0 | fixture |
| aai-win-fallback | test_029 | index | 1957 | yes | 2.7 | corpus |
| aai-win-fallback | test_030 | index | 1957 | yes | 2.5 | corpus |
| aai-win-fallback | test_031 | index | 1957 | yes | 2.4 | corpus |
| aai-win-fallback | test_032 | fixture | 4 | no | 0.1 | fixture |
| aai-win-fallback | test_033 | fixture | 4 | no | 0.1 | fixture |
| aai-win-fallback | test_034 | fixture | 39 | no | 1.0 | fixture |
| aai-win-fallback | test_035 | fixture | 39 | no | 9.7 | fixture |
| aai-win-fallback | test_036 | fixture | 4 | no | 0.2 | fixture |
| aai-win-fallback | test_037 | fixture | 4 | no | 0.0 | fixture |
| aai-win-fallback | test_038 | fixture | 4 | no | 0.8 | fixture |
| aai-win-fallback | test_039 | fixture | 4 | no | 0.4 | fixture |
| aai-win-fallback | test_040 | fixture | 4 | no | 0.9 | fixture |
| aai-win-fallback | test_041 | fixture | 4 | no | 10.7 | fixture |
| aai-win-fallback | test_042 | index | 1957 | yes | 4.7 | corpus |
| aai-spec-lint | test_001_duplicate_id | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_002_gap_and_malformed | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_003_done_without_evidence | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_004_test_plan_mapping | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_005_frozen_consistency | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_006_ceremony_and_status | fixture | 10 | no | 0.2 | unsplit |
| aai-spec-lint | test_007_unparseable_row | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_008_cli_contract | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_009_real_corpus | wide | 285 | no | 0.3 | unsplit |
| aai-spec-lint | test_010_advisory_wiring | fixture | 6 | no | 0.1 | unsplit |
| aai-spec-lint | test_011_seam_survival | index | 1208 | yes | 16.9 | unsplit |
| aai-spec-lint | test_delta_003_shape | fixture | 10 | no | 0.3 | unsplit |
| aai-spec-lint | test_delta_004_legacy_control | wide | 285 | no | 0.4 | unsplit |
| aai-spec-lint | test_dupac_001_dropped_duplicate | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_dupac_002_both_parse_no_double_report | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_dupac_003_vanished_no_double_report | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_dupac_004_no_false_positives | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_dupac_005_real_corpus | wide | 285 | no | 0.3 | unsplit |
| aai-spec-lint | test_specidshape_001_bareslug_flagged | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_specidshape_002_negative_controls | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_specidshape_003_type_guard | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_specidshape_004_real_corpus_loop | wide | 280 | no | 9.4 | unsplit |
| aai-spec-lint | test_specidshape_005_fixture_alignment_regression | fixture | 4 | no | 0.0 | unsplit |
| aai-spec-lint | test_stratev_001_direct_demanding_red | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_stratev_002_tdd_hybrid_unchanged | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_stratev_003_untested_and_unknown | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_stratev_004_negative_controls | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_stratev_005_strategy_flag | fixture | 10 | no | 0.2 | unsplit |
| aai-spec-lint | test_stratev_006_template_and_prompt | fixture | 6 | no | 0.0 | unsplit |
| aai-spec-lint | test_stratev_007_real_corpus | wide | 285 | no | 0.3 | unsplit |
| aai-spec-lint | test_stratev_template_no_selfflag | fixture | 11 | no | 0.1 | unsplit |
| aai-spec-lint | test_halffrozen_001_marker_without_status | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_halffrozen_002_status_without_marker | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_halffrozen_003_negative_controls | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_halffrozen_004_real_corpus | wide | 285 | no | 0.3 | unsplit |
| aai-spec-lint | test_actest_001_untested_ac | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_actest_002_negative_controls | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_actest_003_lean_table | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_actest_004_terminal_scope | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_actest_005_real_corpus | wide | 285 | no | 0.3 | unsplit |
| aai-spec-lint | test_clarify_001_live_markers | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_003_specimen_exemption | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_004_cap | fixture | 10 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_006_vague_terms | fixture | 11 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_009_terminal_and_corpus | wide | 285 | no | 0.4 | unsplit |
| aai-spec-lint | test_clarify_010_prompt_and_guide | fixture | 6 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_011_no_new_ceremony | wide | 303 | no | 0.1 | unsplit |
| aai-spec-lint | test_clarify_012_red_class_stamped | fixture | 4 | no | 0.0 | unsplit |
| aai-spec-lint | test_478_mutation_cell_lint | fixture | 10 | no | 0.2 | unsplit |
| aai-spec-lint | test_479_column_by_name | wide | 285 | no | 0.4 | unsplit |
| aai-spec-lint | test_494_header_prefix_match_and_unmapped_finding | wide | 285 | no | 0.4 | unsplit |
| aai-spec-lint | test_541_shared_specimen_masker | fixture | 10 | no | 0.1 | unsplit |
| aai-prompt-diet | test_001_include_reference | fixture | 11 | no | 0.1 | unsplit |
| aai-prompt-diet | test_002_common_blocks | fixture | 12 | no | 0.1 | unsplit |
| aai-prompt-diet | test_003_intake_line_budget | fixture | 11 | no | 0.0 | unsplit |
| aai-prompt-diet | test_004_intake_dry_run | index | 1957 | yes | 0.3 | unsplit |
| aai-prompt-diet | test_005_profile_defictioned | fixture | 4 | no | 0.1 | unsplit |
| aai-prompt-diet | test_006_fallback_single_source | fixture | 73 | no | 0.1 | unsplit |
| aai-prompt-diet | test_007_pointer_form | fixture | 13 | no | 0.1 | unsplit |
| aai-prompt-diet | test_008_loop_caching_and_payload | fixture | 4 | no | 0.1 | unsplit |
| aai-prompt-diet | test_009_digest_contract | index | 1957 | yes | 0.2 | unsplit |
| aai-prompt-diet | test_010_audit_and_reduction | index | 781 | yes | 1.9 | unsplit |
| aai-prompt-diet | test_011_tick_wrappers | fixture | 6 | no | 0.1 | unsplit |
| aai-prompt-diet | test_012_growth_sum_matches_ledger | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_013_ledger_entry_shape | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_014_breach_suggestion_deficit | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_015_headroom_cap_still_bites | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_016_skill_loop_prompt_hash_pointer | fixture | 5 | no | 0.1 | unsplit |
| aai-prompt-diet | test_017_dashboard_test_skills_pins | fixture | 5 | no | 0.1 | unsplit |
| aai-prompt-diet | test_018_journal_report_contract_pins | fixture | 5 | no | 0.1 | unsplit |
| aai-prompt-diet | test_019_core_prompt_diet_dedup | fixture | 73 | no | 0.1 | unsplit |
| aai-prompt-diet | test_020_g4_disk_artifact_poll_contract | wide | 302 | no | 0.1 | unsplit |
| aai-prompt-diet | test_021_ledger_has_no_unescaped_backtick | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_022_ac_flip_guard_canon_wiring | fixture | 74 | no | 0.1 | unsplit |
| aai-prompt-diet | test_023_ac_flip_growth_credited | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_429_select_suites_named_in_both_prompts | fixture | 5 | no | 0.0 | unsplit |
| aai-prompt-diet | test_622_diet_true_up | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_697_corpus_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_746_roadmap_takes_direction_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_1215_downstream_rides_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_1336_roadmap_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_766_diet_credit_verdict_floor | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_767_diet_credit_verdict_arithmetic | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_769_agents_md_ceiling | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_770_corpus_scan_no_equality_pins | wide | 129 | no | 0.8 | unsplit |
| aai-prompt-diet | test_771_diet_credit_verdict_pr388_states | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_028_windows_prompt_credit | fixture | 3 | no | 0.0 | unsplit |
| aai-prompt-diet | test_1372_amendment_class_partition_credited | fixture | 5 | no | 0.1 | unsplit |
| aai-prompt-diet | test_1531_merge_policy_lanes_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_1641_roadmap_advisory_growth_ledgered | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_1734_local_evidence_growth_ledgered | fixture | 7 | no | 0.1 | unsplit |
| aai-prompt-diet | test_2722_diet_entry_for_slice | fixture | 3 | no | 0.1 | unsplit |
| aai-prompt-diet | test_2824_diet_entry_for_binding | fixture | 72 | no | 0.1 | unsplit |
| aai-prompt-diet | test_2936_skill_pr_3b_growth_ledgered | fixture | 3 | no | 0.0 | unsplit |
| aai-docs-content | check_deps | fixture | 0 | no | 0.0 | unsplit |
| aai-docs-content | setup_fixture | fixture | 41 | no | 0.2 | unsplit |
| aai-docs-content | test_deterministic_index_no_clock_line | index | 1558 | yes | 4.2 | unsplit |
| aai-docs-content | test_1351_live_corpus_near_miss_set_is_dispositioned | index | 1201 | yes | 1.9 | unsplit |
| aai-docs-content | test_1348_near_miss_headline_carries_the_count | index | 1235 | yes | 2.1 | unsplit |
| aai-docs-content | test_1349_verdict_names_the_unreadable_tables | fixture | 41 | no | 0.6 | unsplit |
| aai-docs-content | test_spec0006_no_regression_real_repo | fixture | 1 | no | 0.0 | unsplit |
| aai-docs-content | test_change0166_closeout_is_clean_and_terminal | index | 1201 | yes | 0.2 | unsplit |
| aai-docs-content | test_534_two_stale_halves_are_closed | index | 12 | yes | 0.2 | unsplit |
| aai-docs-content | setup_indexarm_snapshots | index | 1559 | yes | 2.1 | unsplit |
| aai-docs-content | test_indexarm_earlier_day_generation_is_green | index | 1 | yes | 1.2 | unsplit |
| aai-docs-content | test_issue0001_posix_paths_noop | fixture | 1 | no | 0.1 | unsplit |
| aai-docs-content | test_indexarm_index_is_not_stale | index | 0 | yes | 4.8 | unsplit |
| aai-docs-content | test_indexarm_overdue_boundary_is_green | fixture | 40 | no | 0.7 | unsplit |
| aai-docs-content | test_issue0001_no_regression_real_repo | fixture | 1 | no | 0.0 | unsplit |
| aai-docs-content | test_spec0011_regression | fixture | 1 | no | 0.0 | unsplit |
| aai-docs-content | test_537_shape_check_live_yield | fixture | 1 | no | 0.1 | unsplit |
| aai-docs-content | test_change0007_regression | wide | 706 | no | 0.3 | unsplit |
| aai-docs-content | test_change0012_regression | fixture | 42 | no | 0.2 | unsplit |
| aai-docs-content | test_docsaicanon_real_repo_clean | wide | 706 | no | 0.4 | unsplit |
| aai-docs-content | test_change0028_real_repo_clean | fixture | 1 | no | 0.0 | unsplit |
| aai-docs-content | test_spec0057_real_repo_known_collisions | index | 1201 | yes | 1.9 | unsplit |
| aai-docs-content | test_pdcm_product_family_repo_wide_clean | index | 1201 | yes | 0.4 | unsplit |
| aai-docs-content | test_acflip_real_repo_clean | wide | 706 | no | 0.1 | unsplit |
| aai-docs-content | test_2310_rfc0017_rollout_rows | fixture | 1 | no | 0.0 | unsplit |

Cases per suite and half: aai-docs-content unsplit 25, aai-hygiene-pack corpus 29, aai-hygiene-pack fixture 66, aai-prompt-diet unsplit 42, aai-spec-lint unsplit 52, aai-win-fallback corpus 5, aai-win-fallback fixture 27.

### Before and after

Two edits, each in a disposable detached worktree of the commit, created and removed with `git worktree add` and `git worktree remove`: E1 appends one comment line to `.aai/scripts/pr-preflight.mjs`
(a production script no fixture half reads); E2 appends one line to
`docs/product/precise-suite-evidence-reuse.md` (a product document no fixture half reads). For each edit and
each side: one seed run with reuse on, a copy of `tests/skills/results/reuse/` and of
`docs/ai/tests/test-runs.jsonl`, the edit, then three rerun samples with reuse on, the store
and the ledger restored from the copies before every sample. Suites: the five original suites before; the same
five plus aai-hygiene-corpus and aai-win-fallback-corpus after. Command:
`bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` with one `--skill` per suite,
`AAI_TEST_TIMEOUT=3000`, `AAI_ROLE`, `CI` and `AAI_SUITE_REUSE` unset. Outcome per suite: REUSED, or RUN with the
first reason that `suite-reuse.mjs check` printed before the sample.

| Edit | When | Sample | Wall s | Exit | Evidence reuse line | Suite outcomes |
|---|---|---|---|---|---|---|
| E1 | before | 1 | 105.7 | 0 | Evidence reuse: on (0 of 5 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E1 | before | 2 | 106.4 | 0 | Evidence reuse: on (0 of 5 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E1 | before | 3 | 106.9 | 0 | Evidence reuse: on (0 of 5 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E2 | before | 1 | 106.0 | 0 | Evidence reuse: on (0 of 5 suites reused, check 1s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |
| E2 | before | 2 | 105.5 | 0 | Evidence reuse: on (0 of 5 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |
| E2 | before | 3 | 106.3 | 0 | Evidence reuse: on (0 of 5 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |
| E1 | after | 1 | 72.1 | 0 | Evidence reuse: on (2 of 7 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E1 | after | 2 | 71.5 | 0 | Evidence reuse: on (2 of 7 suites reused, check 1s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E1 | after | 3 | 71.5 | 0 | Evidence reuse: on (2 of 7 suites reused, check 1s) | aai-docs-content=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-spec-lint=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs aai-win-fallback-corpus=RUN:reason=inputs_changed_.aai/scripts/pr-preflight.mjs |
| E2 | after | 1 | 71.1 | 0 | Evidence reuse: on (2 of 7 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |
| E2 | after | 2 | 71.4 | 0 | Evidence reuse: on (2 of 7 suites reused, check 0s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |
| E2 | after | 3 | 71.0 | 0 | Evidence reuse: on (2 of 7 suites reused, check 1s) | aai-docs-content=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-spec-lint=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-hygiene-pack=REUSED aai-prompt-diet=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback=REUSED aai-hygiene-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md aai-win-fallback-corpus=RUN:reason=inputs_changed_docs/product/precise-suite-evidence-reuse.md |

E1 before median: 106.4
E1 after median: 71.5
E2 before median: 106.0
E2 after median: 71.1

Ratios after over before: E1 0.67, E2 0.67.

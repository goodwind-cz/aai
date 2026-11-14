# Code review: flush-drops-reopened-runs

```yaml
review:
  scope: "git diff origin/main...HEAD (head da0df9ad, branch fix/flush-drops-reopened-runs); paths per STATE code_review.scope"
  spec: docs/specs/SPEC-DRAFT-spec-flush-drops-reopened-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/metrics-flush.mjs:1837-1847 (freshRuns, continuation work entry), :924 (flush_segment), :2035-2037 (continuation line); TEST-3720 + TEST-3721 green (test-aai-metrics.sh, this review's run rc 0)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "metrics-flush.mjs:1843-1870 (keptNote prefix on every skipped[ref]; refused ref never enters completedRefs); TEST-3722 green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "metrics-flush.mjs:1842 (fresh.length === 0 -> toResume); TEST-3723 + TEST-3724 (pr-waiver TEST-17 c/d/e) green; D7 fixtures only golden-adjacent edits" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/validation-waiver.mjs:350 (flush_segment default 1), :505-506 (segment-uniqueness refusal); TEST-3725 (pr-waiver TEST-19) green incl. byte-copy control" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "docs/ai/METRICS.jsonl: origin/main bytes are an exact prefix (841485 B), one line appended; line minus reconstructed deep-equals docs/ai/tdd/flush-drops-reopened-runs/reconstruction/raw-line.jsonl; TEST-3726 green" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "CHANGELOG.md:33 '## [unreleased] — fix: a flush after a reopen keeps the new runs instead of dropping them'; docs/product/telemetry.md continuation + PR-gate paragraphs; TEST-3727 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 883,
          issue: "a continuation line re-records human_time_minutes (global LOOP_TICKS review minutes when STATE reviews is null; STATE intake on the crash-then-more-runs path) that segment 1 already recorded, so per-ride human time doubles across segments; docs/product/telemetry.md's 'a reader that sums per ref gets the ride total' is false for human time",
          failure_scenario: "two work items (ref A done, B in progress), LOOP_TICKS holds 120 s of human_resume review; flush A (partial reset keeps ticks); reopen A with set-focus/append-run/set-validation/set-code-review; flush again -> segment 1 and segment 2 both carry reviews 2, totals.human_time_minutes 2+2=4 for 2 real minutes; metrics-report 'Human time' total and leverage inflate. Repro: scratchpad repro-continuation-human-time.sh exits 1 printing 'ride human minutes summed across lines: 4'" }
  cannot_verify:
    - { claim: "D8 reconstruction is faithful flag-for-flag (notes, prompt_hash prefixes, requested/actual model, effort) to the original append-run command lines",
        closes_with: "a line-by-line diff of the eleven append-run commands in the ride transcript against recon-runs.json; this review only confirmed all 11 duration_seconds/ended_utc stamps and all 11 usage_total_tokens values occur in subagents/agent-a2a86f1e7b064ff89.jsonl" }
    - { claim: "new suite code survives set -euo pipefail with GNU tools on the Linux CI runner",
        closes_with: "green CI skill-suite job on the PR head SHA (local runs here are macOS only)" }
    - { claim: "R1: dispatch rule 14 already_flushed strands (does not delete) reopened runs until a later flush",
        closes_with: "an orchestration-dispatch test with a reopened ref whose new runs sit in STATE (suggested fu-dispatch-flushed-probe-ref-keyed)" }
    - { claim: "R2: per-line ledger readers (factory report, metrics-report ride counts, golden-flow medians) only shift by one row per reopened ride",
        closes_with: "reader tests over a ledger holding a flush_segment 2 line (suggested fu-ledger-readers-fold-flush-segments)" }
    - { claim: "R6/backward compatibility: downstream STATE entries left by an interrupted flush from an older flush version whose ledger run shape differs (or whose line has agent_runs []) now flush again as a continuation, or stay in STATE as a sticky SKIP when refused, instead of being cleaned up",
        closes_with: "a corpus sweep of downstream METRICS/STATE pairs, or a scratch aai-sync install with an older-era ledger line" }
    - { claim: "PR #555 interaction: after both PRs merge, order-independent readers see segment 1 (first close) and segment 2 (reconstruction) with disjoint runs",
        closes_with: "re-run TEST-3726 and test-aai-pr-waiver.sh on main after #555 merges" }
  overall: pass
```

security_relevant: false

## Scope and spec

- Scope: `git diff origin/main...HEAD` at da0df9ad (two commits: ab891833, da0df9ad). The STATE
  `code_review.scope` path list was reviewed. Companion telemetry in the diff (docs/INDEX.md,
  EVENTS.jsonl +6, decisions.jsonl +1, tests/test-runs.jsonl +1) is additions only. `git ls-files -ci`
  is empty.
- Spec: docs/specs/SPEC-DRAFT-spec-flush-drops-reopened-runs.md (frozen, ceremony 2).
- Dispatch prompt: the "Focus" list names areas to examine and states that they are not
  conclusions. No severity was pre-rated and no area was excluded, so this is not recorded as
  coaching. The full scope was reviewed.

## Verdict 1: spec_compliance = pass

The AC Status table still reads `planned` on all six rows. This is the canon AC-FLIP DEFERRAL
(VALIDATION step 8a): the doc is `implementing`, so `docs-audit --gate` exits 1 with Rule-1
non-terminal rows only, and `--ac-flip-check` exits 0. Both were re-run in this review. The flip
belongs to the close ceremony. This review does not count it as a gap.

| Spec-AC | Call | Evidence |
|---|---|---|
| 01 | compliant | `runIdentity` (role, `model_id ?? 'unknown'`, string-or-null started/ended) is exactly buildEntry's projection (metrics-flush.mjs:845-848). `ledgerRunCounts` builds the multiset. `freshRuns` uses up counts in STATE order. The continuation `work = {...entry, runs: fresh, segment: prior.lines + 1}` goes through the default gate and the sweep gate. `flush_segment` comes after `verdict` and before `validation_waiver`. The Flushed and continuation lines print with no RESUME. Under --dry-run the ref is listed under `flush`. TEST-3720/3721 green. |
| 02 | compliant | A refused continuation is never pushed to toFlush or toResume, so it is not in completedRefs, gets no reset and keeps STATE. Every `skipped[ref]` carries the D2 prefix. TEST-3722 green (cmp on STATE and ledger). |
| 03 | compliant | `fresh.length === 0` takes the old resume, and the RESUME text is unchanged. TEST-3723 shows crash and clean are byte-equal. The D7 fixtures are the only edits to existing tests. I also ran an extra probe (scratchpad `probe-continuation-crash.sh`): a crash after the ledger append of a CONTINUATION resumes cleanup-only, and STATE and the ledger are byte-equal to a clean continuation (2 lines). |
| 04 | compliant | `readArchiveLedger` turns a non-integer or <1 `flush_segment` into 1. evaluateArchive refuses only on a repeated segment. TEST-3725 (real flush, real reopen CLIs, real gate, byte-copy control) green. |
| 05 | compliant | Prefix check: origin/main's 841485 bytes equal HEAD's first 841485 bytes, and exactly one line follows with a trailing LF. The line minus `reconstructed` deep-equals the scratch flush's raw line. `reconstructed` is the last key, and its source and reason are non-empty. `tokens_in`/`tokens_out` are null, the tokens sum is 1799150 and `flush_segment` is 2. The cost is total-blended at reconstruction time (R5 discloses this). |
| 06 | compliant | The CHANGELOG heading has the `## [unreleased] — fix: …` per-entry shape and sits under the scaffold. telemetry.md describes the run-level resume, the continuation, `flush_segment`, the SKIP, `reconstructed` and the PR-gate rule. TEST-3727 green. |

TEST evidence: this review re-ran both suites through `aai-run-tests.sh`.
`test-aai-pr-waiver.sh` gave rc 0 (19 arms). `test-aai-metrics.sh` gave rc 0, with
TEST-3720..3723/3726/3727 PASS. Mutation records for TEST-3720..3727 exist under
docs/ai/tdd/spec-flush-drops-reopened-runs/. Validation round 2 reports 8/8 replay red. Replay was
not re-run here.

Deviations from the frozen spec (all reasonable, all disclosed here):
1. The Implementation plan says `ledgerRefs` "is removed (its only caller is main)". It is kept as
   a one-line wrapper over `ledgerRunCounts` because `handleRelease` (metrics-flush.mjs:1277, 1282)
   also calls it. The spec's caller claim was wrong, and the semantics are unchanged (same key
   set).
2. tests/skills/test-aai-pr-waiver.sh `main` now strips a leading `test_` from the requested arm
   name, so mutation-run.mjs can select an arm. This runner change is not in the Test Plan. It only
   adds a name form the runner accepts.
3. The TEST-3727 mutation was re-anchored (leading `^` dropped). This is recorded as a measurement
   amendment in decisions.jsonl (spec-amend, 2026-11-14T18:30:18Z).

## Verdict 2: code_quality = pass

Checked and found sound:
- **Collision / deletion.** A genuinely new run is read as already flushed only if role, model_id,
  started_utc and ended_utc all match a ledger run of the same ref. append-run stamps both times to
  the second from the clock, so this needs two same-role, same-model runs that start and end in the
  same seconds. The multiset gives k−j fresh copies when STATE holds a duplicate.
- **Double append.** The identity is the same projection buildEntry writes, and the STATE value
  passes through one parser on both sides, so a flushed run always compares equal. R6 (foreign
  writers) is disclosed.
- **Archive eligibility.** `defaultOkRefs` is still set before the continuation branch. A
  continuation admitted by the default gate archives. A swept continuation does not. A refused
  continuation never resets.
- **--release/--retire.** Both branch before the loop and are unchanged (`ledgerRefs` keeps the
  same key set).
- **--dry-run.** It lists a continuation under `flush`, and the plan entries carry
  `flush_segment`.
- **Crash resume.** It is covered for both the first flush and a continuation (probe above).
- **Gate.** A malformed `flush_segment` (string, 0, negative, fraction) collapses to 1, so it fails
  closed against a real segment 1. Two same-segment lines still refuse.
- **Tests.** The new tests use `|| true` on `grep -c`, `&&`-guarded greps and `|| EC=$?` captures.
  No bare `rc=$?`, and no `grep | head` under pipefail. TEST-3726/3727 read the source repo's live
  ledger and CHANGELOG by design. tests/skills is not synced downstream (aai-sync has no
  tests/skills entry).

### NB-1 (NON-BLOCKING, P3): continuation lines re-record human time

- Location: metrics-flush.mjs:883-887. buildEntry takes `reviews` from STATE or else from the
  GLOBAL `ticksReviewMinutes`, and takes `intake` from STATE. Continuations enter it at :1843.
  docs/product/telemetry.md (the "Continuation lines" paragraph) also says "Each line's totals …
  cover only the runs on that line; a reader that sums per ref gets the ride total".
- Failure scenario (reproduced):
  1. Ref A is done and ref B is in progress. LOOP_TICKS holds 120 s of human review.
  2. Flush A. The partial reset keeps LOOP_TICKS, because only a full reset cleans it.
  3. Reopen A with the real CLIs and flush again.
  4. Segment 1 and segment 2 both record `reviews: 2`. The ride's summed human time is 4 minutes,
     but only 2 minutes happened.
  5. metrics-report.mjs:213-220 adds each line into "Human time" and leverage.
  6. Second path, crash then more runs: the STATE `intake` value is written again on the
     continuation.
- Repro:
  `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/repro-continuation-human-time.sh <worktree> <scratch>`
  exits 1 and prints `ride human minutes summed across lines: 4 (ticks hold 2 min of review in total)`.
- Why it is not BLOCKING:
  - The global tick attribution is older than this scope: any second ref flushed under a partial
    reset already re-records the same tick minutes.
  - The incident's reconstructed line carries null/0 human time.
  - No current ledger line is wrong.
  - The spec (D2) pins an unchanged buildEntry, so a fix changes spec scope.
- Recommended disposition: **promote-to-follow-up** (b). Suggested id
  `fu-continuation-rerecords-human-time`, P3, filed by the orchestrator. (d) is not available
  because the defect leaves an inflated number in a durable record. The fix: a continuation records
  human time only from a non-null STATE value that the ledger does not already hold, or null.
  Correct the telemetry.md sentence ("ride total" holds for runs, tokens and cost, not for human
  time). The fix could also fold into the suggested `fu-ledger-readers-fold-flush-segments` (R2).

### INFO (no failure mode; does not gate)

- TEST-3722 arm (c) is labelled "--sweep with the item not done". The metrics fixture repo has no
  EVENTS.jsonl, so the sweep refuses at the earlier `no durable work_item_closed event` check, not
  at the status check. Spec-AC-02 holds either way, because the assertion pins only the shared
  prefix.
- `test_3723` calls `test_013_legacy_timestamp_summary_is_cleanup_only` again. That function also
  runs on its own in main, so it runs twice. This costs time but is harmless.

## cannot_verify

See the YAML block above (six entries). The diff alone does not prove:
- that the reconstruction is faithful flag-for-flag (only the numbers were spot-checked against the
  cited transcript);
- that CI on Linux passes;
- R1 and R2 reader behaviour;
- downstream R6 behaviour;
- the post-#555 merge state.

## Warning dispositions (H6)

- NB-1: promote-to-follow-up (b), suggested `fu-continuation-rerecords-human-time` (P3, not filed by
  this read-only reviewer).

## Next steps

1. The orchestrator files NB-1's follow-up and records the disposition in `code_review.notes`.
2. PR as planned. Then confirm CI green on the head SHA.
3. Close ceremony flips the AC table.

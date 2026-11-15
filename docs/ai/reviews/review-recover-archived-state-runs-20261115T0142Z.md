# Code review: recover-archived-state-runs (round 1)

review_started_utc: 2026-11-15T01:42:19Z
Reviewer: claude-opus-5-5, dispatched CODE REVIEW role, read-only on implementation files.
Scope: `git diff 5bbc129e...ecac2cf9` on fix/recover-archived-state-runs (worktree
/Users/ales/Projects/aai-worktrees/recover-archived-state-runs), limited to STATE
code_review.scope: .aai/scripts/metrics-flush.mjs, lib/metrics-flush-record.mjs,
lib/docs-audit-core.mjs, orchestration-dispatch.mjs, golden-flow.mjs, the touched
tests/skills/*.sh suites, tests/skills/lib/ride-handoff.test.mjs, docs/ai/METRICS.jsonl
(appended lines), docs/product/telemetry.md, CHANGELOG.md, the intake and the spec.
Spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md (SPEC-FROZEN).

security_relevant: false

Coaching check: the dispatch prompt named focus areas (identity, dedupe, live-wins,
focus-skip, reader safety, the fold and NB3, idempotence, hygiene). It did not pre-rate
severity or exclude any area. The full scope was reviewed anyway.

```yaml
review:
  scope: "5bbc129e...ecac2cf9 (paths of STATE code_review.scope)"
  spec: docs/specs/SPEC-0292-spec-recover-archived-state-runs.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "metrics-flush.mjs handleRecoverArchives (buildEntry + null overrides, reconstructed last, segment prior.lines+1); TEST-3734, TEST-3735 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "byKey first-sorted winner + noteConflict; ledgerRoleStarts role+started_utc held; started_utc NOTE; TEST-3736, TEST-3737 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "dry-run exit before append; held keys make the second run a no-op; TEST-3738 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "focus skip, walk filter STATE*+.yaml, default docs/ai/archive, parseArgs refusals exit 2, absent --state exit 1; TEST-3739 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "liveRun(...) ?? run; TEST-3740 green (real state.mjs, metrics-flush, validation-waiver)" }
      - { ac: Spec-AC-06, call: compliant, citation: "validation-waiver.mjs:500 counts verdict PASS only (unchanged); TEST-3741 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "docs-audit-core.mjs:800 skips isRecoveryRecord; TEST-3742 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "orchestration-dispatch.mjs:1069; TEST-3743 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "metrics-flush-record.mjs baseSegment/mergeSegments/foldRideSegments; TEST-3744, TEST-3745 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "golden-flow.mjs:346; TEST-3746, TEST-3747 green" }
      - { ac: Spec-AC-11, call: compliant, citation: "ride-handoff.test.mjs TEST-3748 green (node --test rc 0)" }
      - { ac: Spec-AC-12, call: compliant, citation: "independently re-measured: first 866116 bytes sha256 5ef04d1f... = base; 65 lines appended, 0 removed; 280 runs; 79080170 tokens_total; 21/44 split; 0 bad-shape lines; 0 role+started_utc collisions with non-recovery lines (any ref); TEST-3749" }
      - { ac: Spec-AC-13, call: compliant, citation: "CHANGELOG.md one [unreleased] — fix heading; telemetry.md paragraph; TEST-3750" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1690,
          issue: "archiveCopies never excludes the --state file itself; an --archive directory that contains the live STATE reads it as an archived copy",
          failure_scenario: "operator runs --recover-archives --archive docs/ai: live docs/ai/STATE.yaml (basename STATE.yaml) is a 'copy'; every non-focus in-flight ride's runs get a verdict-null recovery line; that ride's own flush later finds every run held, takes the RESUME cleanup-only lane and never writes its PASS line, so the PR-gate archive lane refuses archive_no_ledger_pass. Repro: scratchpad fixture, dry-run reports refs=1 for in-flight RIDE-B with source docs/ai/STATE.yaml" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-metrics.sh, line: 4882,
          issue: "TEST-3749 picks 'this ride's lines' by the fixed RECOVERY_REASON, which every future --recover-archives run also writes, and pins the count at 65",
          failure_scenario: "a later legitimate recovery on this repo (spec Edge case: a new archive copy gives a ref more runs) appends one more line with the same reason; TEST-3749 fails 'recovery lines 66 != 65' although nothing is wrong. The spec row says the test 'stays green after later appends'. Keying also on reconstructed.recovered_utc 2026-11-15T00:09:46Z would fix it" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/metrics-flush-record.mjs, line: 115,
          issue: "when the base segment has no reliability, rel falls back to the last present reliability, which can be a recovery line (validation round NB3)",
          failure_scenario: "a legacy PASS line with no reliability followed by a recovery line: the merged ride now reports first_pass_clean and verdict_after_last_implementer null taken only from the recovered runs. Confirmed by a direct fold call; 0 cases on the real ledger (all 21 bases carry reliability)" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "'A run already in the ledger or in the live STATE is not written again' is inaccurate: a run in the live STATE IS written (from its live fields), and a later flush treats it as held",
          failure_scenario: "a downstream operator reads that live-STATE runs are skipped, then expects the recovery to leave stranded live refs alone, and is surprised by recovery lines for them (27 such refs here)" }
  cannot_verify:
    - { claim: "the D8 real-run inputs (130 copies, digest 51751363e1811852, main live STATE) produced exactly these 65 lines", closes_with: "re-run the D8 dry-run against the unchanged main checkout and diff its entries with the 65 appended lines (only possible while the archive tree is unchanged)" }
    - { claim: "R2: no open PR branch elsewhere will flush runs that these recovery lines already hold", closes_with: "gh pr list --state open heads checked against the 65 refs at merge time" }
    - { claim: "the no-flag metrics-flush path is unchanged in behaviour", closes_with: "partly verified: the diff adds only flag parsing, two refusals that need the new flags, and one early branch; the unknown-flag error text changed (lists the new flags). The full pre-existing test-aai-metrics suite passing on this head is the evidence" }
    - { claim: "generate-dashboard shows recovered runs as successful operations (R4) and no other reader outside .aai/scripts treats a verdict-null reconstructed line as a PASS", closes_with: "reader grep covered .aai/scripts only; skills and downstream tools reading METRICS.jsonl directly were not swept" }
  overall: pass
```

## Scope and method

Diff preflight: worktree mode (`worktree.user_decision: worktree`, branch
fix/recover-archived-state-runs at ecac2cf9, base origin/main 5bbc129e). At the start the
worktree was clean. I read the frozen spec, then the whole code diff, the new and
touched tests, the CHANGELOG and the product doc.

Targeted suites run on this head (env -u AAI_ROLE -u AAI_GIT_WRITE): test-aai-pr-waiver,
test-aai-docs-audit, test-aai-orchestration-dispatch, test-aai-factory-report,
test-aai-golden-flow, test-aai-ride-handoff, node --test ride-handoff.test.mjs all rc=0;
test-aai-metrics rc=0 (All aai-metrics tests passed). No full sweep was run.

Side effect: after the targeted suites, the worktree showed `M docs/ai/overview-data.json`
and `M docs/ai/overview.html`. Some pre-existing suite regenerates the shipping
overview (registry `fu-recheck-tests-regen-shipping-overview`). The new recovery tests
run in fixture directories. The reviewer may not run git restore, so the orchestrator
must restore those two files before committing.

## Focus areas checked

- Identity and dedupe: the archive side is keyed on (ref, role ?? null, started_utc).
  The sorted copy list makes the first copy win, `noteConflict` collects the fields that
  differ over RECOVER_FIELDS, and every copy that holds the run goes into `files`. The
  ledger side is held on role plus started_utc within the exact ref_id, as D2 says.
  Re-measured on the real ledger: no recovered run collides with a non-recovery line,
  not even under a different ref.
- Live-wins: `liveRun` returns the live run object, so buildEntry projects the live fields.
  `liveCount` counts by object identity. TEST-3740 proves that a later normal flush sees
  those runs as held under the four-field identity.
- Focus skip: it is applied only to refs with unheld runs, which is correct. A skipped
  ref adds nothing to the tokens or run counts.
- Gate safety: every reader of METRICS in .aai/scripts was listed with grep. Beyond the
  D6 table, aai-doctor only counts lines (CAT-07), lib/recheck and lib/pr-sweep list the
  ledger as a path and do not parse it, and metrics-report folds before counting PASS.
  No missed reader treats a verdict-null `reconstructed` line as a PASS, a delivery or a
  flush. On every PASS-keyed path, `isRecoveryRecord` is false for #556's PASS
  reconstructed line.
- Fold: the base is the latest non-recovery segment. The position and the spread follow
  the base. The waiver comes from non-recovery segments only. With no recovery line the
  output is identical to #556 (the base is the last segment). The NB3 case is above.
- Idempotence: the second run finds every key held. The real second run's stdout is in
  the recovery evidence (validator r1), and TEST-3738 covers it.
- No invented numbers: tokens, durations and stamps are copied as recorded, and
  `trustedDuration` nulls a duration that does not match its stamps. Costs are
  buildEntry's usual pricing (decomposed, or total-blended when only a total exists),
  disclosed as R3. human_time totals follow buildEntry's own `(intake ?? 0) + (reviews ?? 0)`.
  buildEntry's INFO/WARNING lines are dropped by the recovery branch (INFO only).
- No-flag path: the branch is entered right after parseArgs. The new refusals fire only
  with the new flags. Only the unknown-flag message text changed.
- Test hygiene: every touched suite runs under `set -euo pipefail`. The added lines have
  no `printf | grep -q` and no bare `rc=$?`, and every `grep -c` carries `|| true` inside
  its `$()`. TEST-3750 hard-codes `/usr/bin/grep`, which is fine on the CI runners.

## INFO (no gate)

- `archiveCopies` lets an unreadable subdirectory (EACCES in readdirSync) throw
  uncaught, giving a stack trace and exit 1. D3's NOTE-and-skip covers unreadable
  copies only. Nothing is written in that case.
- Two parallel runs of one ref that share role and started_utc would collapse into one
  run. This matches the ride-handoff `ledgerKeys` precedent.

## Warning dispositions (recommended; the orchestrator records them)

- NB-1 (P2, --state inside an --archive dir): remediate in-tree. Drop
  `realpath(statePath)` from `copies` (or refuse it with exit 2), and add one case to
  TEST-3739. If it is not fixed, promote it to a follow-up (it widens R1).
- NB-2 (P3, TEST-3749 marker not ride-unique): remediate in-tree. Also match
  `reconstructed.recovered_utc === "2026-11-15T00:09:46Z"`.
- NB-3 (P3, base without reliability): accepted residual: no instance on the real
  ledger (all 21 base segments carry reliability); the fallback equals #556's pre-change
  behaviour; no false record exists today.
- NB-4 (P3, CHANGELOG wording on live-STATE runs): remediate in-tree. Suggested
  wording: "a run already in the ledger is not written again; a run also in the live
  STATE is written from its live fields, so a later flush treats it as held".

## Next steps

Overall: pass, with conditions. Before closeout, restore docs/ai/overview-data.json and
docs/ai/overview.html in the worktree. Fix NB-1, NB-2 and NB-4, or record their
dispositions. Record NB-3 as the accepted residual quoted above.

review_ended_utc: 2026-11-15T01:50:36Z

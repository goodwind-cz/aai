# Code review r1: done-work-item-stays-in-current-focus

- Reviewer: claude-opus-5-5, independent of the implementer (claude-sonnet-5-5). This is the first code review of the ride.
- Scope: `git diff origin/main..HEAD`, with `origin/main` = `690fc3b0` and HEAD = `2c82c881`. The branch is `fix/done-work-item-stays-in-current-focus` in a dedicated worktree.
- Files reviewed:
  - `.aai/scripts/metrics-flush.mjs`
  - `.aai/scripts/orchestration-dispatch.mjs`
  - `tests/skills/test-aai-metrics.sh`
  - `tests/skills/test-aai-orchestration-dispatch.sh`
  - the intake and the spec
  - `docs/INDEX.md` (regenerated)
- Uncommitted worktree changes (`docs/ai/decisions.jsonl`, `EVENTS.jsonl`, `overview*`, `test-runs.jsonl`) are outside the committed diff. They are judged only under N6.
- Spec: `docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md` (frozen, amended 2026-10-11T19:44:25Z).
- Behavioural evidence comes from the validation r3 probes in `docs/ai/validation/done-work-item-stays-in-current-focus-r3/`.

```yaml
review:
  scope: origin/main..HEAD (690fc3b0..2c82c881)
  spec: docs/specs/SPEC-0224-spec-done-work-item-stays-in-current-focus.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "metrics-flush.mjs:1561 --ref not-a-candidate refusal; TEST-1382/1383" }
      - { ac: Spec-AC-02, call: compliant, citation: "handleRelease metrics-flush.mjs:1126; TEST-1384/1385" }
      - { ac: Spec-AC-03, call: compliant, citation: "focus null on release; TEST-1386; probe10 (c)" }
      - { ac: Spec-AC-04, call: compliant, citation: "metrics-flush.mjs:1134-1149; TEST-1387/1388" }
      - { ac: Spec-AC-05, call: compliant, citation: "metrics-flush.mjs:1151-1156; TEST-1389/1390" }
      - { ac: Spec-AC-06, call: compliant, citation: "releaseLedgerEntries empty; TEST-1391; probe7 METRICS cmp" }
      - { ac: Spec-AC-07, call: compliant, citation: "guards before dry-run branch metrics-flush.mjs:1203; TEST-1392" }
      - { ac: Spec-AC-08, call: compliant, citation: "work_item_released event payload; TEST-1398" }
      - { ac: Spec-AC-09, call: compliant, citation: "orchestration-dispatch.mjs:476-492; TEST-1393" }
      - { ac: Spec-AC-10, call: compliant, citation: "Metrics Flush arm kept orchestration-dispatch.mjs:493; TEST-1394/1395" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-1396; probe4 96/96 no_focus_ref after remedy" }
      - { ac: Spec-AC-12, call: compliant, citation: "metrics-flush.mjs:1298-1303; TEST-1397 (item-done fixture; see N10)" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-1740; probe7 16/16 release shapes act" }
      - { ac: Spec-AC-14, call: compliant, citation: "applyReleaseReset metrics-flush.mjs:1097; TEST-1741" }
      - { ac: Spec-AC-15, call: compliant, citation: "metrics-flush.mjs:1157-1165; TEST-1742" }
      - { ac: Spec-AC-16, call: compliant, citation: "closeSupersededByReopen metrics-flush.mjs:366; dispatch :465; TEST-1743/1744" }
      - { ac: Spec-AC-17, call: compliant, citation: "parseArgs metrics-flush.mjs:205-210; TEST-1745" }
      - { ac: Spec-AC-18, call: compliant, citation: "orchestration-dispatch.mjs:477-486; TEST-1746; probe7 48/48 clear-focus shapes act, badprint=0" }
      - { ac: Spec-AC-19, call: compliant, citation: "metrics-flush.mjs:1187-1201; TEST-1747; probe6/probe10 (b)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 493, issue: "N9: closed focus whose item is absent but which carries agent_runs (no pass verdict) is still dispatched to Metrics Flush, which no flush arm can act on (default skips not_run, --sweep needs item done, --retire says would flush, --release says absent)", failure_scenario: "set-focus on a closed ref with no item, then any append-run for it (or a STATE left by origin/main's old dispatch) -> 4b Metrics Flush every tick forever (probe9). Pre-existing on origin/main." }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1302, issue: "N10: --retire hint names --release for a zero-run closed ref even when its work item is absent, where --release refuses", failure_scenario: "item absent + agent_runs: [] + close event: --retire says 'use --release', --release exits 1 'absent from active_work_items' (probe10 a); dispatch correctly says clear-focus" }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 108, issue: "RULES['4b'].when describes only the --release arm; the item-absent clear-focus arm and its reason are undocumented in the rule table that --human / rule listings print", failure_scenario: "operator reads the rule table to interpret closed_focus_item_absent_no_flushable_metrics and finds no mention" }
      - { rank: NON-BLOCKING, file: .aai/scripts/orchestration-dispatch.mjs, line: 477, issue: "redundant re-test 's.focus_flushable_runs < 1 &&' inside the identical outer if; it exists as the TEST-1746 mutation anchor but reads as a bug", failure_scenario: "a later reader 'simplifies' it and the frozen mutation cell stops applying (restamp churn)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 1091, issue: "releaseWouldFlushByDefaultGate is used only by --retire since the B1 fix; name and comment ('shared by --retire and --release') are stale. existingScopeRef is destructured into handleRelease (:1128) but unused while scope_ref_id is re-read three times; releaseLedgerEntries (:1184/:1252) is a dead append branch kept as a mutation anchor", failure_scenario: "maintainer trusts the comment and assumes release honours the default-gate predicate" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-metrics.sh, line: 3956, issue: "TEST-1747 asserts only the substring 'fail' in stderr; nearly every refusal in this file contains 'fail' (fail-closed), so it does not prove the AC-19 refusal fired rather than another one", failure_scenario: "a regression that refuses for a different reason still passes the message assertion (exit code and cmp still pin behaviour)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-orchestration-dispatch.sh, line: 4887, issue: "TEST-1746 builds item-absent only by renaming the item to another done ref; the canonical-CLI shape active_work_items: [] (probe5) and the other-item-in-flight shape are covered by probes, not by the suite", failure_scenario: "a future change to work_item lookup for an empty list regresses unseen" }
      - { rank: NON-BLOCKING, file: .aai/scripts/metrics-flush.mjs, line: 98, issue: "header comment: overlong merged line and no mention of the AC-19 full-reset refusal", failure_scenario: "reader of the contract header misses that --release refuses any unowned fail on the full-reset branch" }
  cannot_verify:
    - { claim: "the real live-repo wedge (CHANGE-0199 readme-portable-workflow-onboarding) is released end-to-end", closes_with: "running dispatch + the printed remedy on the shared checkout's STATE after merge (STATE is gitignored; fixtures only here)" }
    - { claim: "the LLM orchestrator stops and reports on the two unlisted needs_llm reasons rather than improvising", closes_with: "an observed /aai-loop tick on a wedged STATE (prompt behaviour, not script behaviour)" }
  overall: pass
```

## Spec compliance

The walk covers all 19 Spec-ACs and finds every one compliant. Each has a mapped TEST and a RED log accepted as `product_red`; mutation replay is 25/25 and the mutation gate passes 25 rows. Behaviour was confirmed independently by running every printed remedy for real across 160 + 960 fixture shapes (validation r3).

**The clear-focus exception (Spec-AC-18) is sound as gated.** Dispatch prints it only when all of these hold:

- the close event is present and not superseded;
- there is no fail verdict;
- the required review is satisfied;
- the focus has zero runs;
- the item is absent.

Over 960 shapes it was never printed outside that predicate (`badprint=0`). Two caveats:

- `clear-focus` itself is unconditional. The safety lives in dispatch, and a human runs the command later, so there is a benign time-of-check gap.
- The announcement half of `fu-clearfocus-announces-unwritten-phase` does fire on this path. It prints `work item phase=closed status=done` when there is no item. The spec's "no item line for the defect to mishandle" holds for the write but not for the message. That follow-up already exists and is open.

## Code quality

The design is careful:

- `handleRelease` is structurally disjoint from the flush loop.
- Every guard runs before the dry-run branch.
- EVENTS is written before STATE, a post-commit check-state runs, and a recovery file is written on failure.
- The partial reset leaves verdicts that do not name the released ref byte-identical.
- The new full-reset refusal (AC-19) is placed correctly: after the per-ref guards and before the dry-run.
- `closeSupersededByReopen` mirrors dispatch's notion exactly.

There are no BLOCKING findings. The non-blocking findings are in the YAML above; dispositions are below.

## Carried non-blocking findings

| ID | Judgement |
|---|---|
| N6 | `docs/ai/decisions.jsonl` is still uncommitted. It holds 4 `spec_amendment` records (18:17:25Z, 18:33:15Z, 19:11:36Z, 19:44:25Z) plus `fu-amend-done-work-item-stays-in-6aea5b`. All must ride the PR, or `spec-amend` and the close audit will see a frozen spec amended with no ledger. The worktree also carries other rides' or tooling churn: PR #455 merge-cleanup records, one `docs_audit` EVENTS line, overview and test-runs. Stage only this ref's records at the PR step. |
| N8 | `--sweep` (`metrics-flush.mjs:1503`, `closedRefs`) still flushes a ref whose close was superseded by a reopen, while release and dispatch now honour the reopen. This is pre-existing and outside the spec's file-level contract, but it is now an inconsistency inside one file. A follow-up is warranted. |

## Warning dispositions (H6)

| Finding | Disposition |
|---|---|
| N9 | (b) follow-up `fu-4b-item-absent-with-runs-wedge`, P2. Alternatively the owner may choose one more round; see the validation r3 menu. |
| N10 | (b) follow-up `fu-retire-hint-release-item-absent`, P3. It could be folded into the N9 follow-up. |
| N8 | (b) follow-up `fu-sweep-ignores-reopen`, P3. |
| N6 | (a) remediate at the PR step: commit this ref's ledger records. |
| RULES['4b'] text, redundant guard, stale helper name / unused `existingScopeRef` / dead ledger branch, header comment | accepted residual: P3 clarity and maintenance only, with no behavioural bite and no false record. Several of these exist as frozen mutation anchors, so changing them costs a restamp. |
| TEST-1747 message assertion, TEST-1746 shape coverage | accepted residual: P3 assurance strength. Exit code and cmp still pin the behaviour, and the uncovered shapes are proven by probe5 and probe7. |

## Next steps

On merge direction, take the PR step:

1. Commit this ref's `decisions.jsonl` records (N6).
2. File the follow-ups above with `follow-ups.mjs add`.
3. Get owner sign-off on the 4 unsigned contract amendments; the merge direction signs them per CHANGE-0208.

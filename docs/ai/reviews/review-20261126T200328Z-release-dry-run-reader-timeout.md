# Code review: release-dry-run-reader-timeout

```yaml
review:
  scope: "git diff origin/main (3a81b019) -- .aai/scripts/release-dry-run.mjs tests/skills/lib/release-first.test.mjs tests/skills/test-aai-sync-node.sh tests/skills/suite-weights.tsv tests/skills/test-aai-suite-select.sh CHANGELOG.md; untracked docs/issues/CHANGE-0272-release-dry-run-reader-timeout.md, docs/specs/SPEC-0321-spec-release-dry-run-reader-timeout.md; bookkeeping docs/ai/decisions.jsonl, docs/ai/EVENTS.jsonl, docs/ai/roadmap.yaml"
  spec: docs/specs/SPEC-0321-spec-release-dry-run-reader-timeout.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-dry-run.mjs:15-16; tests/skills/lib/release-first.test.mjs:372,390; TEST-007 rc=0 (rerun)" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/release-first.test.mjs:8,304; TEST-006 rc=0 (rerun); 901 RED in docs/ai/tdd/release-dry-run-reader-timeout/red-test_006-901.log" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/suite-weights.tsv:14-20,281-282; tests/skills/test-aai-suite-select.sh:2448-2460; TEST-4037 rc=0 (rerun); scratch mutations reject other-suite and D-WEIGHTS-in-release-cut (see NB-2 for the gap)" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/test-aai-sync-node.sh:885-886; TEST-4019 rc=0 (rerun)" }
      - { ac: Spec-AC-05, call: cannot-verify, citation: "TEST-5001: no PR yet; observe gh pr checks on the PR head" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-dry-run.mjs, line: 10,
          issue: "comment (and CHANGELOG) say the 1800 s budget fits a timed-out rolled run plus its ordinary diagnostic; with 900 x 2 = 1800 the slack is zero and the rolled arm itself runs about 1150-1250 s of wall time over 49 readers",
          failure_scenario: "a reader that hangs on both payloads: rolled arm ends around 1200 s, the 900 s diagnostic cannot finish, the budget timer fires and the reader is reported diagnostic-incomplete instead of baseline-failure (job still fails). Under 540 s the same case fitted (about 1200 + 540)." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-select.sh, line: 2459,
          issue: "TEST-4037 checks that aai-release-cut names only re-measure runs, not all five; the amendment record says it 'may (and must) name its five'",
          failure_scenario: "scratch probe: sample rewritten to count=3 runs=45875856570,45820326840,45808578900 seconds=371,363,408 and row 371 -> TEST-4037 rc=0, though Spec-AC-03 says weight 408" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "'timed out at 540 seconds on most recent pull requests' overstates the measurement (4 timeouts + 1 budget-exhausted of 19 PR runs per the spec); '(116 to 408 seconds)' reads as the run range rather than the weight change",
          failure_scenario: "a release-notes reader takes away a wrong failure rate and a wrong run-time range" }
  cannot_verify:
    - { claim: "Spec-AC-05: the release dry-run check passes on the PR head with 900 s", closes_with: "gh pr checks <pr> after the PR opens; release-dry-run.json shows aai-release-cut rolled pass" }
    - { claim: "the 408 weight puts aai-release-cut in the first wave of the hosted dry-run and lowers its contention slowdown", closes_with: "schedule.orderedReaders and durations in the PR's release-dry-run.json artifact" }
    - { claim: "the source-run timings (371,601,363,597,408 s) and the 346-517 s dry-run range are as stated", closes_with: "the named GitHub Actions run logs; not fetched by this review" }
  overall: pass
```

security_relevant: false

## Scope and spec
Scope: worktree `fix/release-dry-run-reader-timeout`, uncommitted diff against origin/main 3a81b019, the paths above. Spec: SPEC-0321-spec-release-dry-run-reader-timeout (frozen, ceremony 1). The dispatch prompt listed points worth checking but did not pre-rate severities. The full scope was reviewed anyway.

## AC walk
- Spec-AC-01: compliant. The constants are 900/1800 and TEST-007 pins both in the report. Rerun rc=0.
- Spec-AC-02: compliant. TEST-006 imports the export (the main guard at release-dry-run.mjs:502 keeps the import side-effect free) and asserts 1800 >= 2 x default. Rerun rc=0. The 901 RED log is recorded.
- Spec-AC-03: compliant. The median of 363,371,408,597,601 is 408. The five source lines and the header are present. Scratch mutations: another suite (aai-release) naming a re-measure run gives rc=1, aai-release-cut naming a D-WEIGHTS run gives rc=1, weight 116 gives rc=1, and dropping one source line gives rc=1. So the "only aai-release-cut" half is tight. The subset gap is NB-2.
- Spec-AC-04: compliant. The comment names 900 s and 30 min. Rerun rc=0.
- Spec-AC-05: cannot-verify (no PR yet).
- Whole file `node --test tests/skills/lib/release-first.test.mjs`: 24/24 pass.

Deviations from the frozen spec: none found.

## Independent checks
- **Thresholds:** 900 s against 517 s (the worst dry-run pass) is about 1.74x. Against the worst standalone main-push leg of 601 s times the measured 1.25 contention factor (about 751 s), the headroom is about 20%. That is justified by the spec's numbers. The 1800 s default matches the workflow (`--budget-seconds 1800`, skill-suite.yml:400). The workflow is unchanged.
- **Stale pins:** a repo grep for 540, 1080 and the weight 116, excluding docs/ai/{reviews,reports,tdd} and frozen specs, finds no live pin. Remaining mentions are history or unrelated:
  - release-first.test.mjs:298 is history prose ("1080 s left the plan unfinishable").
  - The 540 in node-first-remaining-plan.md is a line count.
  - The intake, spec and brief describe the change itself.
- **Default-budget side effect:** the only in-repo caller of `release-dry-run.mjs` is the workflow, and it passes the budget explicitly. The new default affects only local runs without `--budget-seconds`, where it becomes 30 minutes. tests/skills/test-aai-suite-reuse.sh:390 passes its own bounds. No other side effect found.
- **Fallback weights:** fallback rows use the maximum measured weight. That maximum is 450 (aai-sync-node), and 408 stays below it, so the fallback rows are unchanged. auditWeights passes.
- **Amendment record:** decisions.jsonl has one `spec_amendment` (SPEC-0313 Spec-AC-01, contract, owner_signoff false) whose five run ids match the test's `remeasure` set exactly. Its tracked_by `fu-amend-node-first-cleanup-20261-de1515` follow-up exists. The EVENTS doc_lifecycle line and the roadmap append are consistent.
- **CHANGELOG shape:** `## [unreleased] — ci: <title>` matches the per-entry heading convention, and `ci:` is an established type.

## Findings and dispositions (H6)
- NB-1 (P3, zero-slack budget, diagnostic-incomplete for a reader that hangs on both payloads). Recommended disposition: (b) a note on the existing follow-up `fu-dry-run-budget-from-weights`, which owns deriving the budget. Also soften the comment and CHANGELOG claim in-tree. Reason: the "two arms fit" argument ignores the rolled arm's wall time, and slack went from 720 s to 0.
- NB-2 (P3, TEST-4037 does not enforce that all five re-measure runs are named). Recommended disposition: (a) remediate in-tree, a one-line `assert.deepEqual` of the aai-release-cut runs against `remeasure['aai-release-cut']`. Otherwise (d), with an accepted residual named in the notes.
- NB-3 (P3, CHANGELOG wording "most recent pull requests" and "(116 to 408 seconds)"). Recommended disposition: (a) remediate in-tree, e.g. "timed out at 540 seconds on several recent pull requests, including the release PR" and "weight raised from 116 to 408 seconds".

## Next steps
Optionally fold NB-2 and NB-3 in-tree, then record the NB-1 note. Open the PR and observe Spec-AC-05 on the PR head.

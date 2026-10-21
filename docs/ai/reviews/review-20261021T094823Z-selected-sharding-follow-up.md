```yaml
review:
  scope: "89e7150e3bdf38c4c61bacacf27a8f9d07cd05af to working tree at HEAD 61928d867a6265c0b62bd8bb24d6ab06af7845e4, including checker help remediation"
  spec: docs/specs/SPEC-0240-spec-selected-ci-conditional-sharding.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/select-suites.mjs:246; conditional TEST-001 in independent validation suite-select.log" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/select-suites.mjs:249; conditional TEST-002 in independent validation suite-select.log" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/lib/shard-plan-check.sh:142; conditional TEST-003; final help invocation exits 2" }
      - { ac: Spec-AC-04, call: compliant, citation: ".github/workflows/skill-suite.yml:207; conditional TEST-004 real framework execution evidence" }
      - { ac: Spec-AC-05, call: compliant, citation: ".github/workflows/skill-suite.yml:423; conditional TEST-005 executed aggregate truth table and anchor regressions" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/selected-scheduling-benchmark-check.mjs:39; conditional TEST-006; reviewer recomputation of five raw pairs" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "H1 hosted small and large selected execution and observed wall/runner cost on candidate workflow code", closes_with: "Independent candidate-SHA run/job evidence with plan, exactly-once membership, successful gate, wall and summed runner seconds" }
    - { claim: "H2 hosted full/platform regression and full-anchor usability on the candidate SHA", closes_with: "Independent candidate-SHA full/platform run results and anchor verification" }
    - { claim: "General hosted speedup or universal measured 25 percent runner-cost ceiling", closes_with: "Representative hosted measurements; tune or amend policy if the operational delivery condition misses" }
  overall: pass
```

# Code Review — PR 486 final diff and help follow-up

**PASS for local acceptance. This review does not establish hosted H1/H2 or merge readiness.** No blocking or non-blocking code-quality finding remains established. The two external comments have the dispositions below.

## Scope and method

First system-clock capture: 2026-10-21T09:48:23Z (after initial canonical-payload read). Requested model gpt-6-astra; actual granted identity unavailable. Used the aai-code-review skill and canonical Code Review payload. No caller-provided answer key or coaching was present. Read STATE: worktree mode, no inline scope. Git status showed only the checker help edit. Reviewed the explicit base-to-working-tree range directly through Git, including the complete executable/test diff and scope documents. Also inspected lifecycle/ledger, product/release, index and generated-report companions. Long generated HTML rows were considered alongside their source JSON; no visual browser inspection was performed.

The full PR remains in scope, not merely the uncommitted help edit. Base is 89e7150e3bdf38c4c61bacacf27a8f9d07cd05af; current HEAD is 61928d867a6265c0b62bd8bb24d6ab06af7845e4. The checker final SHA-256 is d839e09a54808d9367c9509e380055f9728a3be66314502a8a3c085e48b8c3af. The independent local validation final-observations file still exactly matches the current selector, workflow, benchmark checker and both modified test suites. Only the checker hash differs; its HEAD-to-working-tree delta adds five comment lines and one usage echo, with no planning/checking/extraction logic change. This directly supports reuse of the prior execution evidence, rather than asserting a fresh full sweep occurred.

Read prior independent review `docs/ai/reviews/review-20261021T090151Z.md`, authoritative local Validation `docs/ai/reports/VALIDATION-20261021T082701Z-selected-ci-conditional-sharding.md`, its source attestations and focused suite evidence, the benchmark report/JSON, and `/private/tmp/aai-sharding-help-remediation-result.md`. No source, STATE, ledger, stage, commit, push or external comment was changed by this reviewer.

## Acceptance criteria walk

Evidence prefix below: `docs/ai/validation/selected-ci-conditional-sharding-validation-`.

| AC | Call | Evidence and reasoning |
|---|---|---|
| Spec-AC-01 | compliant | Selector line 246 onward validates and deduplicates, orders weight/name deterministically, uses four worker clocks plus 30 seconds, creates two LPT buckets, then applies the specified five eligibility predicates. `suite-select.log` conditional TEST-001 covers exact values, thresholds, membership and deterministic output; those source bytes are unchanged since validation. |
| Spec-AC-02 | compliant | Input refusal precedes output, and weight faults emit a diagnostic and retain one runner. Conditional TEST-002 covers malformed, missing, unreadable, duplicate, incomplete, overflow and nonfinite weights, plus unsafe/non-runnable/empty input and a valid control. No changed logic invalidates those results. |
| Spec-AC-03 | compliant | Checker line 142 onward independently checks record grammar, metadata counts, safe expected names, exact unique membership and contiguous one/two nonempty IDs. Conditional TEST-003 covers corruptions and changed checkout. Help now accurately states the interface and success output; malformed invocation retains exit 2. |
| Spec-AC-04 | compliant | Workflow lines 207 onward produce/check a plan, pin consumers to the selection checkout, recheck membership, extract only a nonempty shard and pass repeated data arguments to one framework invocation with four workers. Conditional TEST-004 runs the production shell with real framework dispatch, exact starts, failure propagation and pre-start refusal. Hosted orchestration is separately H1. |
| Spec-AC-05 | compliant | Gate line 423 onward retains the stable name and always-reporting dependency graph, and rejects absent/failed/cancelled/skipped required results. Conditional TEST-005 executes the single/sharded/full truth table; carry-forward fixtures retain full anchors and reject selected matrix anchors. Full job semantics and concurrency/platform contracts remain unchanged. Hosted coverage is separately H2. |
| Spec-AC-06 | compliant | Versioned benchmark checker and conditional TEST-006 cover required pair, membership, runtime, exit/skip and arithmetic constraints while retaining the predecessor schema. Reviewer reran the checker and independently recomputed median/worst/summed leg time from JSON: five fixed-workload pairs, all recorded exits 0 and no skips. Measured and modeled values remain distinct in product/release docs. |

All six required conditional TEST rows exist and are reached by the suite entrypoints (001–003 via test_1757, 004 via test_1802, 005 in carry-forward, 006 directly in main). Their PASS evidence is present in the focused independent validation logs. No frozen-spec deviation is established at the explicitly defined local acceptance boundary. The parent RFC remains open, and no excluded selection narrowing, body-edit reuse, weight refresh, dependency or runtime migration was introduced.

## External review dispositions and H6

- [Comment 4335144345](https://github.com/goodwind-cz/aai/pull/486#discussion_r4335144345), matrix evaluation ordering: **disputed**. The premise that a false job-level condition still applies this matrix conflicts with GitHub's documented ordering: the job condition is evaluated before the matrix is applied. The condition at workflow line 269 is false in full and selected-single mode; the selected plan is produced and independently checked before a successful selected-two output. See [GitHub workflow syntax, jobs.if](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#jobsjob_idif), retrieved during this review. This source supports rejecting the asserted failure mechanism; it is not a replacement for candidate hosted H1/H2 evidence. Parent owns the inline reply and reviewer resolution.
- [Comment 4335144409](https://github.com/goodwind-cz/aai/pull/486#discussion_r4335144409), missing help: **real, remediated in the reviewed working tree** at checker lines 11, 24–26 and 57. The header and usage function now list `--check-selected <plan-file> <skills-dir> <expected-list>`, and the header describes its constraints/output. The remediation report preserves the pre-edit exit-2 omission; this reviewer independently observed the post-edit exit-2 usage including all three modes and syntax check exit 0. This is documentation-only remediation; no redundant behavioral regression test was added. Parent should cite the eventual remediation commit when replying.

No open H6 WARNING remains; the help finding is disposed by in-tree remediation, and the matrix finding is disputed with primary evidence. No follow-up was filed. Informational freshness note: RFC-0017 still says independent Validation is pending although the local report now exists; it does not claim unobserved hosted success.

## Verification and preserved limitations

Reviewer checks: `git diff --check` exit 0; `bash -n tests/skills/lib/shard-plan-check.sh` exit 0; malformed `--check-selected` invocation exit 2 with corrected usage; benchmark checker exit 0. Python read-only verification confirmed unchanged validated source hashes for the five files above, byte-exact base prefixes for EVENTS, METRICS, decisions and test-runs ledgers, valid generated JSON, and benchmark arithmetic. No new uncertain runtime API was introduced.

Recomputed benchmark baseline median/worst: 279.168684625/280.330104417 seconds; candidate: 172.843141459/173.384052125 seconds. Summed runner seconds: 1396.092308624 versus 1645.908142540. The workload-specific local result is 38.086486% lower median wall and 17.893934% more runner time. The five pairs have no slower pair. This reviewer read the raw JSON and prior raw-log audit, rather than rerunning the expensive benchmark or claiming to independently rerun all 15 legs.

The earlier full aggregate remains 105/109 with four environmental failures followed by successful bounded unchanged-suite retries; the earlier Pester aggregate remains 155/156 followed by its targeted origin-fixture retry. The Bash 3.x internal execution-arm skip remains disclosed. These are not rewritten as fresh all-green aggregates.

The benchmark's pair-1 after-leg-2 outer `AAI-TRIPWIRE FAIL` for `docs/ai/tests/test-runs.jsonl` remains visible in the prior independent reports. Their ledger-prefix audit distinguishes the expected five appended run records from the clean per-suite isolation and successful leg exits. Do not describe this benchmark as warning-free. This is retained evidence context, not a newly established sharding defect or an open H6 finding.

## Cannot verify and handoff

H1/H2 remain unverified by this review and must be closed by the independently running hosted Validation with exact candidate identity and complete observations. General hosted performance or a universal measured runner-cost bound cannot be inferred from five local pairs. The parent must stage this report with the follow-up, record the returned review command, reply per external thread, and retain hosted obligations before declaring merge readiness.

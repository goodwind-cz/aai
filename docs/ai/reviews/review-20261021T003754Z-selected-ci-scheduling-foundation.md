```yaml
review:
  scope: "Complete 17-path uncommitted worktree delta against 35f1448410a3e9a813367a60defeb6551199db7f, including staged, unstaged and untracked scope files"
  spec: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/suite-weights.tsv:1; tests/skills/test-aai-suite-select.sh:2041; TEST-001; raw source recount: 540 PASS timings, five excluded SKIPs" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/select-suites.mjs:204; tests/skills/test-aai-suite-select.sh:1965; TEST-002; independent CRLF/tie/dedup probe" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/select-suites.mjs:218; tests/skills/test-aai-suite-select.sh:1979; TEST-003; independent weight-fallback and invalid-input probes" }
      - { ac: Spec-AC-04, call: compliant, citation: ".github/workflows/skill-suite.yml:215; tests/skills/test-aai-suite-select.sh:1993; tests/skills/test-aai-ci-carry-forward.sh:648; TEST-004/005; round2 full-set-check.json" }
      - { ac: Spec-AC-05, call: compliant, citation: ".github/workflows/skill-suite.yml:103; tests/skills/test-aai-suite-select.sh:2024; TEST-006; local configuration acceptance only" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/selected-scheduling-benchmark-check.mjs:39; docs/ai/validation/selected-ci-scheduling-foundation-benchmark.md:1; TEST-007; ten raw logs independently recounted" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "H1: GitHub cancels the superseded same-PR candidate run, replacement succeeds, unrelated run remains unaffected", closes_with: "Two same-PR candidate workflow runs plus unrelated control, exact run/job IDs, SHAs, times and conclusions, independently observed before merge" }
    - { claim: "H2: candidate-SHA full hosted regression and retained platform jobs succeed", closes_with: "Successful full hosted run and existing platform results on the candidate SHA, independently checked before merge" }
    - { claim: "Strict historical per-row pre-implementation RED and actual granted model separation", closes_with: "Original harness/timestamp evidence if available; current controls cannot reconstruct RED chronology, and requested models do not prove granted identity" }
    - { claim: "Global CI speedup or completion of the umbrella RFC", closes_with: "Representative hosted measurements and evidence for the remaining RFC slices; the fixed eight-suite benchmark establishes neither" }
  overall: pass
```

# Code review — selected CI scheduling foundation

**Local review PASS: spec compliance pass; code quality pass.** No BLOCKING or NON-BLOCKING findings. This is not a merge-readiness or hosted-delivery verdict: H1 and H2 remain mandatory and pending.

Review started at 2026-10-21T00:37:54Z, captured from the system clock. Requested model: gpt-6-astra high as the available premium fallback for routed gpt-5.3-codex. Actual granted model identity and token usage are unavailable; neither is inferred. This was a fresh dispatched reviewer context. No coaching or scope-exclusion instruction was observed.

## Scope and integrity

Read the canonical dispatch contract, Code Review role and learned rules; read STATE and the frozen/amended spec, intake, RFC, technology contract, complete tracked delta and all four untracked scope files. STATE selects a worktree. Scope is the current working-tree content against `35f1448410a3e9a813367a60defeb6551199db7f`, not `base...HEAD` (the implementation is uncommitted).

Reviewed all 17 paths:

- `.aai/scripts/select-suites.mjs`
- `.github/workflows/skill-suite.yml`
- `CHANGELOG.md`
- `docs/ai/EVENTS.jsonl`
- `docs/ai/decisions.jsonl`
- `docs/ai/roadmap.yaml`
- `docs/ai/tests/test-runs.jsonl`
- `docs/issues/CHANGE-0214-selected-ci-scheduling-foundation.md`
- `docs/product/ci-test-impact-selection.md`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`
- `docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md`
- `tests/skills/lib/selected-scheduling-benchmark-check.mjs`
- `tests/skills/suite-map.yaml`
- `tests/skills/suite-weights.tsv`
- `tests/skills/test-aai-ci-carry-forward.sh`
- `tests/skills/test-aai-product-docs.sh`
- `tests/skills/test-aai-suite-select.sh`

Sixteen paths match the dispatch SHA256 manifest exactly. EVENTS differs by exactly one appended validation_verdict at 2026-10-21T00:37:05Z; removing that final record in memory reproduces the manifest hash. The parent confirmed the manifest preceded its validation merge. Reviewed the added record. Current EVENTS SHA256 is `28cab0d866ffa0450683301fe8333dce71736a97be1a93d1a7cd360f8d98e1e3`. All three append-only ledgers retain their byte-exact base prefixes. `git diff --check 35f1448410a3e9a813367a60defeb6551199db7f` exits 0.

## Acceptance criteria and test evidence

| AC | Call | Review evidence |
|---|---|---|
| Spec-AC-01 | compliant | The 109 discovered top-level suites have exactly one positive weight each. Independently matched all 540 successful timings to the source JSON, run conclusions and named SHAs; five aai-state SKIPs are excluded. Its fallback is the measured maximum, 212. The shipped audit recomputes medians and catches stale/missing/duplicate/nonpositive rows. TEST-001 exists, is invoked, and passes in round2 selector evidence. |
| Spec-AC-02 | compliant | The new mode validates the deduplicated list, orders descending by weight and compares ASCII-safe names bytewise for ties. Independent scratch probes confirmed CRLF input, deduplication and mixed-case tie order. TEST-002 is wired and passes. |
| Spec-AC-03 | compliant | List/read/discovery failures return exit 1 before emitting names. Weight read/parse failure leaves an empty map and diagnoses on stderr, so all names remain and sort by name. Missing individual weights use max. Independent malformed-weight, missing-weight, empty, nested-only, shell-token and whitespace-name probes passed. TEST-003 additionally covers absent and unreadable files. |
| Spec-AC-04 | compliant | Selected names cross an environment/file boundary, ordering must succeed under set -e, and exactly one framework call receives repeated quoted --skill arguments. Four workers and the existing timeout remain configured. Framework discovery preserves argument order (test-framework.sh:945). TEST-004 executes the actual workflow body against the real framework; TEST-005 executes the real aggregate shell with failure/cancelled/skipped/missing cases. Full membership, gate dependencies and carry-forward job identities remain unchanged. |
| Spec-AC-05 | compliant | Group includes workflow, event and PR number; cancellation is conditional on pull_request. Non-PR run IDs separate ordinary runs. All workflow jobs perform verification with read permissions; release workflow is unchanged. TEST-006 covers identity/cancellation scenarios. This meets the amended local configuration contract; it does not prove H1. |
| Spec-AC-06 | compliant | Five paired records have identical eight-suite membership, host/runtime, one runner and four workers. All 80 outcomes match the ten raw logs. Recomputed baseline median 31.243796417 s, worst 31.611726333 s, sum 155.593636916 runner-s; after median 26.208173542 s, worst 26.230764542 s, sum 130.080746250 runner-s. TEST-007 verifies arithmetic and adverse schemas. The report explicitly marks unobservable components unavailable and limits its 16.117% median reduction to this workload. |

Required TEST-001 through TEST-007 all exist and have passing evidence. The registration in suite main functions was inspected. Read the timestamped remediation controls, including independently reachable TEST-003 refusal checks against old and current selectors, and the product-doc vacuity/structure controls. These are current controls, not historical RED.

The authoritative independent report is `docs/ai/reports/VALIDATION-20261021T003600Z-selected-ci-scheduling-foundation-round2.md`. Independently verified both intake/spec hashes and all six outcome artifact hashes. Its final-tree evidence records 109/109 suites passing, zero skips/failures, all isolated/fully seeded, four workers, wrapper/reaper exit 0, plus self-hosting smoke. The exact-scope scratch PowerShell rerun records Pester 156 passed, zero failed/skipped. Initial environment-sensitive Pester failures and the interrupted shipping-tree invocation remain disclosed in that report and are not counted as passing evidence. No broad sweep was repeated for this review.

## Code quality assessment

No concrete merge-blocking defect or required warning disposition was found. The implementation reuses the existing parser/comparator, changes ordering without narrowing selection, treats suite names as data, and refuses invalid selected input before the framework. No dependency or runtime sidecar was added. Full-mode logic and carry-forward implementation are untouched. The new helper is mapped to its owning suite. New tests exercise both success and failure paths; the real-framework seam has a positive execution control before its no-start assertion.

The product-doc repair retains live structural checks while checking the original twelve-doc migration at immutable commit `a93bdfedc786c8cbd2c92a4ef5aba0ec62c13c22`. It removes the moving-HEAD restriction that rejected legitimate later prose updates. It verifies nonempty bodies and a delimiter-containing sentinel against vacuous extraction. CI suite checkouts fetch full history, so the historical object is available there.

The historical weight ceilings replaced in two prior tests are explicitly treated as old observations in the new scope/product documentation; refreshed provenance and existing balance checks remain tested. No failure or skip is relabelled a successful measurement.

## Limitations, deviations and disposition

The four cannot_verify entries above are explicit. H1/H2 must close before any merge-readiness claim. The owner-signoff follow-up `fu-amend-selected-ci-scheduling-f-3b2ba6` already exists in the ledger; its unsigned contract amendments and the RED chronology shortfall remain visible. The current frozen/amended contract permits local acceptance with disclosure and independent controls. No new historical evidence is claimed and no new follow-up is filed by this reviewer.

The benchmark was run on its recorded db7ce778 base, not restamped as a final-35f1448 measurement. Its first outer-wrapper tripwire notice concerns scratch framework bookkeeping and is disclosed; all 80 suite outcomes remain independently matched. It is not a production/hosted speed guarantee.

Reviewer-only probe corrections: initial integrity probe stopped at the explained EVENTS hash mismatch; the next ledger probe exceeded Node's default subprocess buffer and was rerun with a bounded 16 MiB buffer; the first mixed-case fixture used colliding aai-A/aai-a filenames on a case-insensitive host and was corrected to noncolliding aai-B/aai-bb. Corrected probes passed. None changed implementation files. All probe writes stayed under `/private/tmp/aai-selected-ci-review-scratch`.

Warnings/dispositions: none. Parent next steps: merge the returned code-review state command, stage this report with the scope under the canonical ceremony, preserve the unsigned-amendment disclosure, and obtain independent H1/H2 observations after PR creation before merge. Reviewer did not write STATE or stage implementation files.

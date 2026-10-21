```yaml
review:
  scope: "PR485: base 35f1448410a3e9a813367a60defeb6551199db7f to HEAD a505ab30ae40ec850cfb00b44325fe730e25f016 plus current unstaged delta and tests/fixtures/product-docs/migration.json; 27 paths"
  spec: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/suite-weights.tsv:1; TEST-001; current weights audit 109 suites, maximum 212" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/select-suites.mjs:204; tests/skills/test-aai-suite-select.sh:1965; TEST-002" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/select-suites.mjs:227; tests/skills/test-aai-suite-select.sh:1981; TEST-003; independent empty/whitespace/comment-only probes" }
      - { ac: Spec-AC-04, call: compliant, citation: ".github/workflows/skill-suite.yml:215; tests/skills/test-aai-ci-carry-forward.sh:648; TEST-004/005; independent selected/core Validation 10/10" }
      - { ac: Spec-AC-05, call: compliant, citation: ".github/workflows/skill-suite.yml:103; TEST-006; H1 runs 39524262530, 39524388008 and 39524301745" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/selected-scheduling-benchmark-check.mjs:39; TEST-007; unchanged five-pair benchmark and fresh arithmetic check" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Final remediation-SHA hosted full regression and existing platform jobs (H2)", closes_with: "Commit/push the reviewed remediation, obtain successful full skill-suite and retained platform jobs on that exact SHA, independently verify IDs, conclusions and times before merge" }
    - { claim: "Original strict per-row pre-implementation RED and actual granted model separation", closes_with: "Original timestamps/harness identities if available; current controls cannot reconstruct past RED or prove actual model identity" }
    - { claim: "Global CI speedup or completed RFC-0017 rollout", closes_with: "Representative hosted measurements and separately accepted remaining RFC slices; the fixed local benchmark does not establish either" }
  overall: pass
```

# Code review — PR485 remediation, round 1

**Local dual PASS.** No new BLOCKING or NON-BLOCKING findings. The two external defects are remediated in the reviewed working tree. This verdict does not assert final H2 or merge readiness.

Started UTC: 2026-10-21T01:19:59Z. Requested model: gpt-6-astra; actual granted identity unknown. This is the original reviewer context, reused for canonical re-review and independent of the maker context. No token usage is estimated. Read-only GitHub review queries were made; no remote reply, resolution, commit or push was performed.

## Scope

Read STATE and the canonical Code Review/Subagent Contract. STATE selects a worktree with no inline scope. Reviewed the complete `git diff 35f1448410a3e9a813367a60defeb6551199db7f...HEAD`, `git diff HEAD`, and new fixture, not only the two external-comment hunks. Included numbered CHANGE-0214/SPEC-0239, draft RFC-0017, tests, workflow, weight records, generated projections, original review and ledgers. The 27-path scope is listed below. Snapshot hashes remained identical during review. All four changed append-only ledgers retain the exact base prefix.

The scope documents remain locally closed under their explicit local-versus-hosted amendment. RFC-0017 remains draft and its roadmap capability active. The dispatcher’s closed-focus state is orchestration context, not a waiver of review or delivery requirements. No coaching attempt or scope exclusion was observed.

## AC walk and required tests

| AC | Assessment and evidence |
|---|---|
| Spec-AC-01 | Compliant. The unchanged TSV has exactly 109 positive rows; the current audit returns maximum 212. Prior independently recounted evidence has 540 successful timings and excludes five aai-state SKIPs; the unsampled suite retains the conservative 212 fallback. TEST-001 executes in the current full selector suite. |
| Spec-AC-02 | Compliant. `orderMain` deduplicates safe top-level names and applies descending weight, then bytewise name order. TEST-002 current evidence covers duplicate input, nonalphabetic weights and ties. The remediation does not alter this code. |
| Spec-AC-03 | Compliant after remediation. `select-suites.mjs:227` treats zero parsed rows as unusable weights and uses the existing diagnostic/name-order fallback. Updated TEST-003 reaches empty and comment-only cases, plus prior missing/unreadable/malformed cases. Fresh independent empty, whitespace-only and comment-only probes all returned 0, exactly the deduplicated name-sorted membership and `WEIGHTS_IGNORED reason=no weight rows`. Invalid names still refuse before framework dispatch. |
| Spec-AC-04 | Compliant locally. Workflow consumes env/file data, orders under `set -e`, constructs quoted repeated --skill arguments, runs one framework invocation and retains four workers. TEST-004 real-framework seam and TEST-005 actual aggregate-script success/failure/missing-job cases pass in current Validation. Full sharding and carry-forward identities remain unchanged. Current selected/core Validation is 10/10; earlier broad sweep is historical evidence, not restamped final-candidate proof. |
| Spec-AC-05 | Compliant. Workflow group/cancel expressions and read-only jobs are unchanged from a505. TEST-006 verifies identity cases. H1's captured run/job evidence shows the specified older-run cancellation, successful replacement and unaffected overlapping unrelated dispatch; details below. |
| Spec-AC-06 | Compliant. The five-pair eight-suite local benchmark is unchanged. Fresh checker returns baseline median 31.243796417 s, worst 31.611726333 s, total 155.593636916 runner-s; after median 26.208173542 s, worst 26.230764542 s, total 130.080746250 runner-s. One runner/four workers, unavailable components and all 80 outcomes remain documented. No representative hosted or global-speed inference is made. |

TEST-001 through TEST-007 exist, are registered and have current passing selector/carry-forward evidence. Product-doc TEST-012/016 cover the bounded regression repair. Independent Validation report `docs/ai/reports/VALIDATION-20261021T011700Z-selected-ci-external-review-round1.md` records 10 isolated/fully seeded PASS, zero failures/skips, wrapper/reaper exit 0, 173 seconds. Independently recomputed both intake/spec source hashes and all eight outcome artifact hashes: all match. The prior 109/109 and 156/156 Pester results remain attributed to the earlier tree; final candidate hosted H2 remains pending.

## External findings and quality review

Live GitHub reads returned two unresolved inline threads and two COMMENTED reviews. Both original inline findings were real on a505, and both are fixed locally:

1. **4331949523 — empty weights diagnostic:** remediate-in-tree, complete in the reviewed delta at `.aai/scripts/select-suites.mjs:227`. The RED at 01:08:01–01:08:02 shows actual missing diagnostics `[empty, comments]`; GREEN at 01:08:29–01:08:31 passes. The new guard is confined to order mode, preserving existing shard-parser behavior. Independent probes confirmed it.
2. **4331949532 — old Git-object dependency:** remediate-in-tree, complete in `tests/skills/test-aai-product-docs.sh:479` and `tests/fixtures/product-docs/migration.json`. The RED at 01:07:26–01:07:28 reaches the old failing `git diff-tree` in the no-history fixture; GREEN at 01:08:32–01:08:33 succeeds. Runtime TEST-012 no longer requests historical Git objects. Independently compared every before/after string with its immutable Git blob: 24/24 byte-identical, across the exact twelve original paths. Live structure, nonempty/equal bodies, migration metadata and the nonvacuous extraction control remain enforced.

Ran `AAI_ROLE=subagent TMPDIR=/private/tmp/aai-selected-ci-external-review/tmp AAI_TEST_TIMEOUT=90 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-product-docs.sh test_016_migration_without_git_history` inside the named independent source copy. Exit 0. It first executes all twelve pairs with no `.git`, then deliberately changes fixture prose and requires failure with the expected diagnostic. The wrapper's degraded-isolation notice is expected because this experiment intentionally has no Git database and is entirely under the named scratch directory. No shipping files were altered.

The new fixture glob selects its owning product-doc suite. No runtime sidecar, dependency or new external effect was introduced. Reviewed generated HTML text changes against their data projections; script/style blocks are byte-identical to base. Those changes reflect local close, date/age/counter refresh and the existing unsigned follow-up, while RFC remains open. `git diff --check` against the full base exits 0.

This report supersedes the original review’s assurance concerning empty weight files and history availability: those gaps were caught externally, and this re-review verifies the concrete repairs. Parent must commit/push, reply to each thread with the fixing SHA and regression evidence, and resolve only after the required reply. No outstanding warning remains in this local tree; remote threads remain unresolved until parent delivery.

## Hosted evidence and limits

Inspected captured run and job JSON, rather than relying on the validation narrative:

- Older PR485 run **39524262530**, workflow **316140990**, SHA **a505ab30ae40ec850cfb00b44325fe730e25f016**, created **00:55:45Z**, updated/concluded cancelled **00:57:44Z**. Selected job **118975211156** cancelled; native job **118975121665** cancelled. The aggregate **118975703273** fails as expected for cancelled prerequisites.
- Replacement PR485 run **39524388008**, same workflow/SHA, created **00:57:01Z**, updated/concluded success **01:04:29Z**. Selected job **118975809598** and aggregate **118977902008** succeed.
- Overlapping unrelated `workflow_dispatch` run **39524301745**, same workflow/SHA, created **00:56:08Z**, updated/concluded success **01:00:47Z**. All four full shard jobs and aggregate **118976697870** succeed.

These observations meet H1's specified pattern for the unchanged configuration. Run metadata alone does not independently reveal the causal cancellation mechanism. Old-SHA full run 39524301745 and platform run 39524304814 do not satisfy H2 for the uncommitted remediation; the eventual final SHA needs fresh hosted evidence.

The original RED-history exception and unsigned tracked amendment `fu-amend-selected-ci-scheduling-f-3b2ba6` remain disclosed. New RED/GREEN logs show actual failing-first assertions; their absent RED_CLASS markers are not invented, and the recorded strategy is loop. Actual model identity and broad RFC targets remain unverified as listed above. No new follow-up was filed. Warnings/dispositions: none outstanding after local remediation.

Parent next steps: apply the returned state command, stage this review with the remediation, complete the two remote replies, and independently verify H2 on the final candidate SHA before merge. Reviewer wrote no STATE or implementation file.

## Reviewed paths
- `.aai/scripts/select-suites.mjs`
- `.github/workflows/skill-suite.yml`
- `CHANGELOG.md`
- `docs/INDEX.md`
- `docs/USER_GUIDE.md`
- `docs/ai/EVENTS.jsonl`
- `docs/ai/METRICS.jsonl`
- `docs/ai/decisions.jsonl`
- `docs/ai/factory-report-data.json`
- `docs/ai/factory-report.html`
- `docs/ai/overview-data.json`
- `docs/ai/overview.html`
- `docs/ai/reviews/review-20261021T003754Z-selected-ci-scheduling-foundation.md`
- `docs/ai/roadmap.yaml`
- `docs/ai/tests/test-runs.jsonl`
- `docs/issues/CHANGE-0214-selected-ci-scheduling-foundation.md`
- `docs/product/ci-test-impact-selection.md`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`
- `docs/skill-catalog-data.json`
- `docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md`
- `tests/fixtures/product-docs/migration.json`
- `tests/skills/lib/selected-scheduling-benchmark-check.mjs`
- `tests/skills/suite-map.yaml`
- `tests/skills/suite-weights.tsv`
- `tests/skills/test-aai-ci-carry-forward.sh`
- `tests/skills/test-aai-product-docs.sh`
- `tests/skills/test-aai-suite-select.sh`

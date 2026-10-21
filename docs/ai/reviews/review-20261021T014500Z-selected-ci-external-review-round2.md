```yaml
review:
  scope: "PR485 full base 35f1448410a3e9a813367a60defeb6551199db7f to HEAD 79de99883318e592a42b1c5a7e98a918ea55bada plus all working-tree edits; 28 paths"
  spec: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/suite-weights.tsv:1; TEST-001; 109 positive rows and conservative fallback, unchanged audited bytes" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/select-suites.mjs:204; tests/skills/test-aai-suite-select.sh:1965; TEST-002" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/select-suites.mjs:227; tests/skills/test-aai-suite-select.sh:1981; TEST-003; round1 independent empty/whitespace/comment probes" }
      - { ac: Spec-AC-04, call: compliant, citation: ".github/workflows/skill-suite.yml:215; TEST-004/005; 79de selected/full jobs; current local product/provenance Validation" }
      - { ac: Spec-AC-05, call: compliant, citation: ".github/workflows/skill-suite.yml:103; TEST-006; H1 final pair 39527452951/39527461176 and unrelated 39527456690" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/selected-scheduling-benchmark-check.mjs:39; TEST-007; unchanged five-pair fixed-workload observations" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Hosted full regression and retained platform jobs on the successor commit containing this metadata correction", closes_with: "Fresh H2 run/job evidence bound to that exact committed SHA, independently verified before merge" }
    - { claim: "Original strict per-row pre-implementation RED and actual granted model separation", closes_with: "Original timestamps and harness identities if available; current probes cannot reconstruct historical evidence or identify the granted model" }
    - { claim: "Representative global CI speedup and completion of RFC-0017", closes_with: "Representative hosted measurements and separately accepted remaining RFC slices" }
  overall: pass
```

# Code review — PR485 external review round 2

**Local dual PASS.** No outstanding BLOCKING or NON-BLOCKING findings in the reviewed tree. The external provenance defect is repaired. Final successor-SHA hosted H2 and parent remote response remain outstanding; this report does not assert merge readiness or whole-RFC delivery.

Started 2026-10-21T01:45:00Z. Requested model gpt-6-astra; actual granted identity unknown. Same independent reviewer context as the preceding full review, without maker context. No token estimate, STATE mutation, source edit, commit, push or external reply was made.

## Scope and integrity

Read STATE, canonical role and subagent contract, and established the full branch scope using Git, including committed diff, working-tree diff and the fixture. STATE selects worktree mode with no inline scope. The 28 paths below cover every changed path from base 35f1448410a3e9a813367a60defeb6551199db7f to HEAD 79de99883318e592a42b1c5a7e98a918ea55bada plus current edits. No scope exclusion or pre-rated finding was supplied.

Compared all paths with the prior complete review's SHA256 snapshot. Executable code, workflow, tests, fixture, frozen spec, weights and benchmark remain byte-identical to the previously examined round1 remediation. Re-examined the changed intake/product metadata, new prior-review artifact, generated INDEX entries and ledger additions. INDEX's three new missing-path diagnostics refer to the literal historical product-doc fixture identities, not promised live documents. All four append-only ledgers retain their exact base byte prefix. During review the parent added only the 01:46:24 validation_verdict event, hash ba94ad731460b6451414e5e52d4c6f5484bcc3d2f89d1bf53d4cd1f58fb10377; I read this delta and rechecked prefixes. All other scope hashes remained stable. Full-base git diff --check passes.

## AC walk

| AC | Independent assessment |
|---|---|
| Spec-AC-01 | Compliant. Unchanged audited TSV has exactly 109 positive suite rows. The previously recounted 540 successful observations exclude five aai-state SKIPs, and the unsampled suite retains conservative 212 fallback. TEST-001 exists and passes in the retained selector evidence. |
| Spec-AC-02 | Compliant. The reviewed order helper deduplicates safe names, sorts descending weight then bytewise name, and preserves membership. TEST-002 exercises duplicate inputs, ties and nonalphabetic weights. No subsequent executable change. |
| Spec-AC-03 | Compliant. Order mode rejects invalid suite input; unusable weights including zero-row files produce the diagnostic and deterministic name-order fallback. TEST-003 plus this reviewer's preceding empty/whitespace/comment-only probes substantiate it on identical current bytes. |
| Spec-AC-04 | Compliant. One selected framework invocation uses quoted repeated --skill arguments and four workers; aggregate gate rejects missing/failing dependencies. TEST-004/005 remain passing, full shard and carry-forward identities unchanged. Historical 79de selected job has 26 PASS; full shard coverage is 109 unique suites, 108 PASS plus one explicit known aai-state SKIP, zero FAIL. Current metadata-only correction independently passes product-doc and provenance checks. |
| Spec-AC-05 | Compliant. Workflow/PR identity and PR-only cancel-in-progress expressions are unchanged, with unique non-PR runs and isolated release mutation. TEST-006 remains passing. H1 records the older cancelled run, successful replacement and successful unrelated overlapping full dispatch; metadata supports the required pattern but alone does not prove cancellation causality. |
| Spec-AC-06 | Compliant. Five paired fixed-workload observations, one runner/four workers, all 80 outcomes and unavailable component boundaries remain intact. Prior independent arithmetic gives baseline median 31.243796417 s, worst 31.611726333 s, total 155.593636916 runner-s; after median 26.208173542 s, worst 26.230764542 s, total 130.080746250 runner-s. TEST-007/checker bytes unchanged. No global CI speedup inference. |

TEST-001 through TEST-007 remain present and covered by the cited original/round1 evidence; the earlier 10/10 isolated selected/core validation is not relabelled a fresh round2 rerun. Product TEST-012/016 continue to validate 12 migration pairs without Git history and retain the prose mutation negative control. Their exact 24 blob strings were independently verified in round1 and are unchanged.

## External findings and current correction

Read live PR485 review threads and review receipts. Earlier comments 4331949523 (empty weight diagnostic) and 4331949532 (historical Git-object dependency) are fixed in 79de, replied to and resolved; their regression evidence remains valid. New comment **4332128557**, thread PRRT_kwDORMHhts6ulzkj, was real on 79de and remains remotely unresolved pending delivery.

Disposition: **remediate-in-tree, complete locally** at `docs/product/ci-test-impact-selection.md:8` and `docs/issues/CHANGE-0214-selected-ci-scheduling-foundation.md:7`. PRODUCT_TEMPLATE D3 requires current delivery provenance. The intake lacked user_visible, so the existing close helper did not stamp it. Current metadata sets user_visible true and appends this ride once, preserves CHANGE-0071 once and updates the date. Independently parsed both frontmatters through the canonical parser, checked matching capability and compared all product prose bytes with 79de: identical. No source behavior or spec contract changed.

Read the remediation report and actual RED/GREEN logs. Original RED at 01:38:57–58 predates edits and fails on missing provenance. The separate post-fix Boolean/string assertion mismatch is disclosed; the canonical parser returns string true and the corrected test normalizes it. The missing-provenance assertion itself was unchanged. Corrected baseline RED is a later negative control, not relabelled preimplementation proof; corrected GREEN succeeds. Existing canonical helper generated the metadata in scratch, with hash-bound output and idempotency/prose preservation evidence. No permanent test is necessary for this bounded metadata-only repair beyond the existing product suite and ephemeral assertion.

The preceding local review missed this project-wide provenance obligation. This report supersedes that assurance and independently checks the repair rather than treating the old PASS as proof of the missing metadata.

## Validation and hosted evidence

Read independent `docs/ai/reports/VALIDATION-20261021T014540Z-selected-ci-provenance-round2.md` and canonical result (01:42:28–01:45:51Z, 203 seconds). Fresh direct wrapped product suite passes 35 live docs and 12 migration pairs; ephemeral provenance assertion passes. Read both actual output logs. Recomputed both source hashes and both outcome artifact hashes, all match. Independently reran validation-outcome-check (exit 0) and full diff check (exit 0). An initial reviewer ledger probe exceeded Node's default child-process output buffer; rerun with explicit 20 MiB bound succeeded. This was a probe limitation, not a product failure.

Validation honestly distinguishes its clean direct wrapper gate from the framework's expected ledger append tripwire warning and the initial sandbox setup denial. The supplied scope guard predates the parent's subsequent validation event; this review separately includes that event.

Inspected historical H1/H2 JSON and recomputed their report-bound hashes. H1 final pair: older a505 run **39527452951** cancelled, replacement 79de run **39527461176** successful, unrelated full **39527456690** successful. Historical H2: full 39527456690 on 79de, created 01:27:50Z/completed 01:32:41Z; aggregate **118986832856** success and exact 109-suite unique coverage. PR selected 39527461176 created 01:27:53Z/completed 01:34:06Z, selected **118985839320** 26 PASS and aggregate **118987262025** success. Platform **39527459366**, created 01:27:52Z/completed 01:36:12Z, success: Linux 156 PASS/0 SKIP; WSL1 and each native engine 152 PASS/4 declared SKIP; zero FAIL. These are immutable **79de** observations only. New metadata will produce a successor SHA, which still requires fresh H2 before merge.

## Process, warnings and next steps

Read `docs/ai/validation/selected-ci-post-pr-provenance-process-note.md` and verified the cited owner-signed 2026-09-12T19:56:52Z standing decision in decisions.jsonl. Its single extra round for an inseparable feature-introduced hazard is consumed by this correction; no further extension is inferred. Already-closed intake/spec remain closed, RFC remains draft. Parent's immediate dispatcher exit4 closed_focus_stale_state is preserved; no fresh tree stamp or successful repeated whole-ride close is claimed. New validation binds actual source hashes, and eventual hosted evidence must bind the committed SHA.

The three historical missing usage_capture=none markers, parent telemetry timing transcription/delay and already-flushed metrics limitation are explicitly disclosed; no token numbers are fabricated or old records rewritten. Original RED-history exception and unsigned tracked amendment fu-amend-selected-ci-scheduling-f-3b2ba6 remain disclosed. They are not newly verified history. No new warning or follow-up is filed; warning dispositions: none outstanding in the local tree after remediation.

Parent next steps: apply the returned state command, stage this report with the correction, commit/push, reply to the provenance thread with fixing SHA/evidence before resolution, and obtain independently verified successor-SHA hosted H2. Reviewer has made no external mutation.

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
- `docs/ai/reviews/review-20261021T011959Z-selected-ci-external-review-round1.md`
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

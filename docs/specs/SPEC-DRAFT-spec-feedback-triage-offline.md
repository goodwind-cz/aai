---
id: spec-feedback-triage-offline
type: spec
number: null
status: draft
ceremony_level: 2
links:
  requirement: CHANGE-DRAFT-feedback-triage-offline
  rfc: RFC-0012
  pr: []
  commits: []
---

# SPEC — RFC-0012 Phase 2 / RFC-0013 Slice B: offline triage over schema-v2 records

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-feedback-triage-offline.md
- RFC: docs/rfc/RFC-0012-...md (section 2 triage); docs/rfc/RFC-0013-...md (schema v2 signal)
- Foundation: .aai/scripts/aai-friction.mjs (capture v2), .aai/system/FRICTION_PROTOCOL.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: Deterministic pure-function behavior (hard gates, composite scoring,
  fingerprint clustering, fail-closed config) over a brand-new script — guaranteed
  real RED, clean RED/GREEN per property. It is the trust input to the later
  network surface, so correct gating/scoring is worth TDD per the strategy rule.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Self-contained new-file scope (one engine + one wrapper +
  config section + tests + classification); reversible; dedicated branch; no
  protected_paths_l3.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/aai-feedback-triage.mjs, .aai/SKILL_FEEDBACK_TRIAGE.prompt.md, .aai/feedback.yaml (triage section), .aai/system/PROFILES.yaml (new entries), tests/skills/test-aai-feedback-triage.sh, tests/skills/lib/prompt-diet-ledger.sh + tests/skills/test-aai-prompt-diet.sh (companion)

## Acceptance Criteria Mapping
- Spec-AC-01 (AC-001): all hard gates enforced — schema_version in {1,2}; failure_class
  in the taxonomy set; only persisted-allowlist keys present (sanitization). A per-gate
  bad fixture is dropped WITH a named reason; a valid one kept. Verification: per-gate fixtures.
- Spec-AC-02 (AC-002): the report is DETERMINISTIC — same spool bytes -> byte-identical
  report (no wall-clock, clusters sorted by fingerprint). Verification: run twice, diff empty.
- Spec-AC-03 (AC-003): scoring uses v2 signals — two observations identical but impact
  high vs low yield a strictly higher score for high; a v1 record (no v2 fields) scores
  via the recurrence fallback with no error. Verification: paired fixtures + a v1 fixture.
- Spec-AC-04 (AC-004): clustering groups by `fingerprint` — two same-fingerprint rows ->
  one cluster, recurrence 2. Verification: two-row fixture.
- Spec-AC-05 (AC-005): per-cluster decision honors `thresholds.review_candidate`; NO
  cluster is `auto_publishable` in this slice (every cluster's auto_publishable=false).
  Verification: threshold fixtures + assert no true anywhere in the report.
- Spec-AC-06 (AC-006): NO network I/O, no token — static grep (no net/gh/token/http)
  + a runtime run under an unroutable proxy still writes the report, exit 0. Verification: static + runtime.
- Spec-AC-07 (AC-007): `local` mode emits the local report only, NO sendable issue
  payload file; `review`/`auto` are parsed but have no network side effect here
  (absent by construction, grep-assertable). Verification: local-mode fixture + grep.
- Spec-AC-08 (AC-008): fail-closed config — a malformed feedback.yaml runs in `local`
  mode (never review/auto). Verification: malformed-config fixture.
- Spec-AC-09 (AC-009): companion — 2 new `.aai/**` files classified once in PROFILES.yaml;
  the new wrapper prompt corpus growth trued up in the prompt-diet ledger
  (JUSTIFIED_ADDITIONS + TEST-012 bump); layer-profiles + prompt-diet green. Verification: both suites green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                             | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | hard gates drop with named reason; valid kept          | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-02 | deterministic byte-identical report                    | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-03 | v2-signal scoring + v1 recurrence fallback             | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-04 | fingerprint clustering                                 | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-05 | threshold decision; nothing auto_publishable           | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-06 | no network / no token (static + runtime)               | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-07 | local-mode summarize-only; no sendable payload         | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-08 | fail-closed config to local                            | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |
| Spec-AC-09 | companion PROFILES + prompt-diet true-up               | done    | docs/ai/tdd/green-20260725T114833Z-triage.log | —         | GREEN |

## Implementation plan
- `.aai/scripts/aai-feedback-triage.mjs` (node stdlib only): parseArgs (--spool
  --config --out --help) -> loadConfig (fail-closed local; reuse the scoped
  YAML-read discipline from aai-friction) -> readSpool (tolerate bad lines) ->
  gate() per obs {ok,reason} -> score() composite [impact 1/2/3 + confidence 1/2/3
  + reproducible +2 + recurrence bonus; v1 fallback = recurrence only] ->
  clusterByFingerprint -> decide() per cluster (auto_publishable:false always;
  review_candidate iff score>=threshold) -> writeReport(triage-report.json) +
  stdout summary. No network imports.
- `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md`: thin wrapper (explicit /aai-feedback-triage;
  degrade to local-only; no daemon).
- `.aai/feedback.yaml`: add `triage: { mode: local, thresholds: { review_candidate: <n> } }`.
- Classification: 2 PROFILES.yaml `extended` entries.

## Seam analysis (6a)
- SEAM 1 (capture -> triage): triage consumes the exact v1/v2 spool schema. If the
  schema drifts, triage mis-reads. INTEGRATION TEST-011: produce real records via
  `aai-friction.mjs record` (a v2 and a v1), then run triage over that real spool and
  assert gate+score+cluster end-to-end — crossing the capture->triage seam.
- SEAM 2 (config -> mode): `mode` governs whether a network path could ever run.
  TEST covers malformed->local and an explicit review/auto value parsed with no
  network side effect in this slice.
- Residual risk: no real GitHub write exists yet (Slice C) — recorded.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                          | Status  |
|----------|------------|-------------|---------------------------------------------|----------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-feedback-triage.sh    | each hard gate (schema/taxonomy/sanitization) drops with named reason | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-feedback-triage.sh    | a fully-valid observation is kept                                     | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-feedback-triage.sh    | same spool run twice -> byte-identical report                        | green |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-feedback-triage.sh    | impact high scores strictly higher than impact low (else equal)      | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-feedback-triage.sh    | a v1 record scores via recurrence fallback, no error                 | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-feedback-triage.sh    | two same-fingerprint rows -> one cluster, recurrence 2               | green |
| TEST-007 | Spec-AC-05 | unit        | tests/skills/test-aai-feedback-triage.sh    | decision honors threshold; NO cluster auto_publishable               | green |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-feedback-triage.sh    | static: no network/gh/token in the source                           | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-feedback-triage.sh    | runtime under unroutable proxy -> exit 0, report written             | green |
| TEST-010 | Spec-AC-07 | unit        | tests/skills/test-aai-feedback-triage.sh    | local mode: report written, no sendable payload; no send code path   | green |
| TEST-011 | Spec-AC-01 | integration | tests/skills/test-aai-feedback-triage.sh    | real aai-friction v2+v1 records -> triage gates/scores/clusters them  | green |
| TEST-012 | Spec-AC-08 | unit        | tests/skills/test-aai-feedback-triage.sh    | malformed feedback.yaml -> runs in local mode                       | green |
| TEST-013 | Spec-AC-09 | integration | tests/skills/test-aai-layer-profiles.sh     | 2 new .aai files classified once; layer-profiles green               | green |
| TEST-014 | Spec-AC-09 | integration | tests/skills/test-aai-prompt-diet.sh        | prompt-diet ledger trued up for the wrapper prompt; green            | green |

RED-proof: TEST-001..012 written first, observed FAILING against the absent
engine before GREEN. TEST-013/014 RED until classification + ledger true-up land.

## Verification
- `bash tests/skills/test-aai-feedback-triage.sh` (green; RED first)
- `node .aai/scripts/aai-feedback-triage.mjs --help` documents the offline contract
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS: all TEST-xxx green AND all Spec-AC terminal (done + evidence)

## Evidence contract
Per artifact: ref_id feedback-triage-offline; Spec-AC + TEST links; command/scope;
exit code/verdict; evidence path (docs/ai/tdd/*.log); commit SHA when available.

Notes: This document defines HOW, not WHAT/WHY. It does not define workflow.

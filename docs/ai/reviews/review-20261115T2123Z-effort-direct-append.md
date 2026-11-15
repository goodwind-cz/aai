# Code Review — effort-direct-append

Reviewer: claude-opus-5-5 (dispatched independent subagent; report returned inline and saved verbatim in substance by the orchestrator, the subagent writes no files)
Started 2026-11-15T21:17:23Z, ended 2026-11-15T21:23:14Z.

```yaml
review:
  scope: "git diff origin/main (16773cdf, uncommitted worktree changes) -- .aai/scripts/state.mjs .aai/scripts/metrics-report.mjs .aai/ROLE_COMMON.md .aai/SKILL_LOOP.prompt.md tests/skills/test-aai-model-effort.sh tests/skills/suite-map.yaml tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-pr-preflight.sh tests/skills/test-aai-retired-loop-runner.sh docs/product/telemetry.md CHANGELOG.md + docs/issues/ISSUE-0117-effort-direct-append.md docs/specs/SPEC-0294-spec-effort-direct-append.md"
  spec: docs/specs/SPEC-0294-spec-effort-direct-append.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "state.mjs EFFORT_APPLIED_VALUES gains direct; schema enum reuses the constant; TEST-3790 PASS, mutation RED" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-report.mjs appliedOf/APPLIED_ORDER/groupKey/applied column; TEST-3791 + updated TEST-3640/3641 PASS; mutation RED" }
      - { ac: Spec-AC-03, call: compliant, citation: "ROLE_COMMON.md direct-append command; SKILL_LOOP step 4; ledger 210+51=261 B measured; TEST-3792 PASS; prompt-diet exit 0; mutation RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "telemetry.md names direct and the applied column; one CHANGELOG per-entry heading; TEST-3793 PASS; mutation RED" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/SKILL_LOOP.prompt.md, line: 362,
          issue: "not_supported-when-harness_effort-null and direct-when-in-session can both match one run; no precedence stated",
          failure_scenario: "harness_effort null + no-subagent fallback: agent may record not_supported for an in-session run, mixing the buckets D1 keeps apart" }
  cannot_verify:
    - { claim: "agents running a role directly follow the new ROLE_COMMON line (spec R1)", closes_with: "post-merge direct-run METRICS lines carrying effort_applied: direct" }
    - { claim: "rest of the repository unaffected (protected-L3 FULL_RUN)", closes_with: "one full sweep before close plus CI green on the PR head" }
    - { claim: "no out-of-repo consumer parses the --by-effort table by column position", closes_with: "downstream check; in-repo only metrics-report.mjs and test-aai-model-effort.sh" }
  overall: pass
```

security_relevant: false

## Deviations from the frozen spec (reasonable, disclosed)
1. suite-map aai-model-effort globs also add docs/product/telemetry.md (TEST-3793 reads it).
2. test-aai-retired-loop-runner.sh TEST-3410 baseline moves with the SKILL_LOOP growth; not named in the spec's scope list.
3. test-aai-prompt-diet.sh TEST-2824 adds the 210 B ROLE_COMMON share that lies outside the .aai/*.prompt.md glob; exact equality kept.
4. metrics-report comparator maps out-of-vocabulary values to the unset rank with lexical tie-breaks (was: first). Deterministic, untested.

No existing pin weakened. ROLE_COMMON text fits all five pointing roles (direct path only; dispatched roles cannot append-run through state_update_commands).

## Findings
- NON-BLOCKING N1 (SKILL_LOOP:362): state precedence, e.g. "`direct` when the role ran in this session, else `not_supported` when `harness_effort` is null". Disposition: remediate in-tree (preferred), else follow-up fu-effort-direct-precedence (P3).
- INFO I1: docs/ai/tdd/effort-direct-append/green-suite.log is a stale intermediate run (uncited, gitignored).
- INFO I2: TEST-2824's +210 is a hard-coded share; a later change fails loudly.
- INFO I3: passing a literal null --requested-effort exits 2 loudly.

## Suites rerun by the reviewer (all rc 0)
test-aai-model-effort, prompt-diet, pr-preflight, retired-loop-runner, downstream-autopilot, validator-isolation, token-capture; mutation-gate --spec GATE PASS 4 rows.

```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Validation
  status: FAIL
  started_utc: 2026-10-07T20:57:48Z
  ended_utc: 2026-10-07T21:11:33Z
  duration_seconds: 825
  actual_model: unknown
  requested_model: gpt-6-astra
  evidence:
    - command: "Canonical wrapped affected suites: preflight, platform, profiles, diet, ride-select, hygiene"
      exit_code: 0
      output_snippet: "Six suites PASS; preflight8/8; timeout1512ms, child gone; all reapers0. Complete local logs retained."
    - command: "bash .aai/scripts/aai-run-tests.sh node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md"
      exit_code: 0
      output_snippet: "8/8 behavioral RED, zero inconclusive, zero restamped."
    - command: "bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr434-validation-scratch/pushurl-repro.cjs"
      exit_code: 0
      output_snippet: "Defect reproduced: actual CLI READ_VERIFIED fetch GitHub despite Azure pushurl; multiple distinct pushurls also accepted; no push executed."
    - command: "Inspect current full CI run37685852367 four complete job logs"
      exit_code: 1
      output_snippet: "Synthetic b54ef374 of60983274:104 suites=97PASS6FAIL1SKIP(aai-state),104isolated/seeded,0degraded."
    - command: "Inspect current native CI run37685852381 Linux and WSL job logs"
      exit_code: 1
      output_snippet: "Linux Pester156/0/0; WSL TEST007 whole-CLI harness timeout, Pester151/1/4; TEST008 unreached. Windows sibling pending."
    - command: "node .aai/scripts/docs-audit.mjs --gate spec-pr-capability-preflight; canonical global AC table scan"
      exit_code: 0
      output_snippet: "GatePASS;214specs/208opted,2other deferred,0overdue or scope14day violations; spec lint0."
    - command: "node .aai/scripts/docs-audit.mjs --check --no-event"
      exit_code: 0
      output_snippet: "Exit0 but NEEDS-TRIAGE(1), scope probable-false-open; not CLEAN."
    - command: "node .aai/scripts/validation-outcome-check.mjs --report docs/ai/reports/VALIDATION-20261007T205748Z-pr-capability-preflight-final-ci.md --ref pr-capability-preflight --since 2026-10-07T20:57:48Z --root /private/tmp/aai-pr-capability-preflight --intake docs/issues/CHANGE-0204-pr-capability-preflight.md --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md"
      exit_code: 1
      output_snippet: "Expected PASS-admissibility refusal only: OUT004 violated, OUT005 unknown, OUT006 unknown; no schema/hash error."
  files_changed:
    - docs/ai/reports/VALIDATION-20261007T205748Z-pr-capability-preflight-final-ci.md
    - docs/ai/reports/RESULT-20261007T205748Z-pr-capability-preflight-final-ci.md
    - docs/ai/tdd/pr-capability-preflight-validation-20261007T205748Z/
  blockers:
    - "B1 P1: origin fetch readiness does not bind divergent or multiple actual push destinations; independent real CLI reproduction."
    - "B2: current native WSL TEST007 harness timeout; required TEST008 platform proof missing."
    - "B3: current full104=97PASS6FAIL1SKIP; lifecycle audit reports probable-false-open."
  state_update_commands:
    - node .aai/scripts/state.mjs set-validation --status fail --ref pr-capability-preflight --evidence docs/ai/reports/VALIDATION-20261007T205748Z-pr-capability-preflight-final-ci.md --notes "FAIL at60983274: reproduced divergent and multiple origin.pushurl readiness escape; current WSL TEST007 harness timeout; full10497PASS6FAIL1SKIP with lifecycle audit NEEDS-TRIAGE. Six local affected suites and eight mutation bites pass but do not resolve blockers."
    - node .aai/scripts/state.mjs set-phase --ref pr-capability-preflight --phase remediation --status in_progress
```

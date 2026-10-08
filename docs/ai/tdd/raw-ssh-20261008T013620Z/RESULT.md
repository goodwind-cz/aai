```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Remediation
  status: PASS
  started_utc: 2026-10-08T01:36:20Z
  ended_utc: 2026-10-08T01:48:56Z
  duration_seconds: 756
  evidence:
    - command: bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh
      exit_code: 0
      output_snippet: Final source TEST001–008 PASS; raw path refusals call zero providers.
    - command: node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md
      exit_code: 0
      output_snippet: Clean replay 8/8 RED, zero inconclusive, zero restamps.
    - command: node .aai/scripts/tdd-evidence-check.mjs --red docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red.log
      exit_code: 0
      output_snippet: Actual product assertion RED accepted.
  files_changed:
    - .aai/scripts/pr-preflight.mjs
    - docs/ai/decisions.jsonl
    - docs/ai/reports/REMEDIATION-20261008T013620Z-pr434-raw-path.md
    - docs/ai/tdd/raw-ssh-20261008T013620Z/RESULT.md
    - docs/ai/tdd/raw-ssh-20261008T013620Z/amend-strict.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/authority-amend.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/authority-red-check.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/authority-red.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/authority-red.raw.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/boundary-before.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/contract-amend.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/diff-check.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/files.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/final-audit.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/final-preflight.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/full-5685-run.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/manifest.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-before.sh
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-final.sh
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red-2.raw.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red-3.raw.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red-check.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/matrix-red.raw.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/measurement-amend.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/mutation-clean.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/mutation-gate.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/mutation-restamp.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/native-5685-jobs.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/native-5685-run.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/native-5685-windows.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/preflight-green.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/01.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/02.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/03.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/04.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/05.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/06.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/07.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/08.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/09.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/10.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/11.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/12.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/13.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/14.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/15.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/16.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/17.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/18.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/19.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/20.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/21.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/22.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/23.patch
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/24.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/prior-mutations/map.json
    - docs/ai/tdd/raw-ssh-20261008T013620Z/product-before.mjs
    - docs/ai/tdd/raw-ssh-20261008T013620Z/product-final.mjs
    - docs/ai/tdd/raw-ssh-20261008T013620Z/red-check.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/result-check-infra.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/result-check.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/sealing-infra.txt
    - docs/ai/tdd/raw-ssh-20261008T013620Z/selector-2-infra.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/selector-infra.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/spec-lint.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/transport-green.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/transport-red.log
    - docs/ai/tdd/raw-ssh-20261008T013620Z/transport-red.raw.log
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-001.txt
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-002.txt
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-003.txt
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-004.txt
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-005.txt
    - docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-007.txt
    - docs/specs/SPEC-0210-spec-pr-capability-preflight.md
    - tests/skills/test-aai-pr-preflight.sh
  blockers: []
  requested_model: gpt-5 unavailable; inherited
  actual_model: unknown
  usage_capture: none
  maker_report: docs/ai/reports/REMEDIATION-20261008T013620Z-pr434-raw-path.md
  state_update_commands:
    - node .aai/scripts/state.mjs reset-block code_review
    - node .aai/scripts/state.mjs set-phase --ref pr-capability-preflight --phase code_review --status in_progress
```

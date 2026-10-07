```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Remediation
  status: PASS
  started_utc: 2026-10-07T20:42:34Z
  ended_utc: 2026-10-07T20:53:06Z
  duration_seconds: 632
  evidence:
    - command: "AAI_ROLE=subagent AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-remediation-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh"
      exit_code: 0
      output_snippet: "PASS TEST001 through TEST008; benign_note_captured=true; genuine_clone_failure_throws=true"
    - command: "AAI_ROLE=subagent bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-ride-select.sh"
      exit_code: 0
      output_snippet: "ALL TESTS PASSED; deterministic related proposal and independent shipped counts"
    - command: "AAI_ROLE=subagent bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh"
      exit_code: 0
      output_snippet: "All tests passed; TEST012 55539; measured prompt37717 bytes; growth1287 bytes"
    - command: "AAI_ROLE=subagent node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md"
      exit_code: 0
      output_snippet: "8/8 attempted records still redden; 0 inconclusive; 0 re-stamped"
    - command: "AAI_ROLE=subagent node .aai/scripts/docs-audit.mjs --ac-flip-check spec-pr-capability-preflight"
      exit_code: 0
      output_snippet: "AC-FLIP PASS"
  files_changed:
    - ".aai/SKILL_PR.prompt.md"
    - "tests/skills/test-aai-pr-preflight.sh"
    - "tests/skills/test-aai-ride-select.sh"
    - "tests/skills/lib/prompt-diet-ledger.sh"
    - "tests/skills/test-aai-prompt-diet.sh"
    - "docs/specs/SPEC-0210-spec-pr-capability-preflight.md"
    - "docs/ai/decisions.jsonl"
    - "docs/ai/reports/REMEDIATION-20261007T204234Z-pr-capability-preflight-final-ci.md"
    - "docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-006.patch"
    - "docs/ai/tdd/spec-pr-capability-preflight/mutation-TEST-006.txt"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/ac-gate.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/clone-control-red.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/clone-red.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/diet-green.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/historical-mutation-TEST-006.patch"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/historical-mutation-TEST-006.txt"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/mutation-replay-final.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/mutation-replay.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/mutation006.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/native-ci-red.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/platform-green.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/preflight-green.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/remote-red.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/ride-green.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/ride-red.log"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/source-hashes.json"
    - "docs/ai/tdd/pr-capability-preflight-remediation-20261007/summary-red.log"
  blockers: []
  state_update_commands:
    - node .aai/scripts/state.mjs reset-block last_validation
    - node .aai/scripts/state.mjs set-phase --ref pr-capability-preflight --phase validation --status in_progress
```

Root-owned metrics append (outside state_update_commands because the role-output checker forbids append-run in that allowlist):

```sh
node .aai/scripts/state.mjs append-run --ref pr-capability-preflight --role Remediation --model unknown --started 2026-10-07T20:42:34Z --verdict none --prompt-hash 06c890067c284f9f361c6818b6159ff052cfbc395574b962598b2e930d2ee620 --note "Scoped CI harness and origin binding corrections; maker local proof only, native PS5.1 and independent checks pending; actual model unavailable to dispatched agent."
```

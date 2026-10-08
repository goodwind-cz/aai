Implemented the scoped GitHub case-identity fix. Case-insensitive comparison is ASCII-only and applies at the input-to-remote and provider-result checks; fetch/push endpoint bytes and the resolved spelling passed to `gh` remain unchanged. Independent Validation and Review are still pending.

```yaml
subagent_result:
  scope: pr-github-case-identity
  role: TDD Implementation
  status: PASS
  started_utc: 2026-10-08T11:22:10Z
  ended_utc: 2026-10-08T11:32:51Z
  duration_seconds: 641
  evidence:
    - command: "Pre-fix TEST-001 and TEST-007 in named scratch copy via aai-run-tests.sh"
      exit_code: 1
      output_snippet: "Product RED: TEST-001 returned IDENTITY_INVALID; TEST-007 returned PROVIDER_RESULT_INVALID after three provider calls."
    - command: "AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-case-maker-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_001"
      exit_code: 0
      output_snippet: "PASS: TEST-001 pr-capability-preflight; case-only endpoint difference refused with zero provider calls."
    - command: "AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-case-maker-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh test_007"
      exit_code: 0
      output_snippet: "PASS: TEST-007 pr-capability-preflight; case-equivalent provider identities pass and true mismatches refuse."
    - command: "AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-case-maker-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh"
      exit_code: 0
      output_snippet: "All eight rows passed, TEST-001 through TEST-008."
    - command: "AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-case-maker-scratch/fixtures node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0212-spec-pr-github-case-identity.md"
      exit_code: 0
      output_snippet: "2/2 mutations still RED; 0 inconclusive; 0 restamped."
    - command: "Mutation gate, SPEC-0212 docs gate and AC-flip check, spec-amend list --strict, git diff --check, manifest hash verification"
      exit_code: 0
      output_snippet: "All gates passed; 14 manifest path hashes matched."
    - command: "node .aai/scripts/check-role-output.mjs --file <checked result block>"
      exit_code: 0
      output_snippet: "Typed TDD Implementation result block accepted."
  files_changed:
    - .aai/scripts/pr-preflight.mjs
    - tests/skills/test-aai-pr-preflight.sh
    - docs/specs/SPEC-0212-spec-pr-github-case-identity.md
    - docs/ai/tdd/pr-github-case-identity-red.log
    - docs/ai/tdd/pr-github-case-identity-green.log
    - docs/ai/tdd/pr-github-case-identity-full8row.log
    - docs/ai/tdd/pr-github-case-identity-refactor.log
    - docs/ai/tdd/pr-github-case-identity-mutation-replay.log
    - docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.txt
    - docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-001.patch
    - docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.txt
    - docs/ai/tdd/spec-pr-github-case-identity/mutation-TEST-007.patch
    - docs/ai/tdd/spec-pr-github-case-identity/maker-manifest.json
  blockers: []
  state_update_commands:
    - node .aai/scripts/state.mjs set-phase --ref pr-github-case-identity --phase implementation --status in_progress --spec-path docs/specs/SPEC-0212-spec-pr-github-case-identity.md
    - node .aai/scripts/state.mjs set-tdd-cycle --status RED --test-id TEST-001 --spec-path docs/specs/SPEC-0212-spec-pr-github-case-identity.md --test-path tests/skills/test-aai-pr-preflight.sh --red docs/ai/tdd/pr-github-case-identity-red.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status GREEN --test-id TEST-001 --spec-path docs/specs/SPEC-0212-spec-pr-github-case-identity.md --test-path tests/skills/test-aai-pr-preflight.sh --green docs/ai/tdd/pr-github-case-identity-green.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status REFACTOR_COMPLETE --test-path tests/skills/test-aai-pr-preflight.sh --refactor docs/ai/tdd/pr-github-case-identity-refactor.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status RED --test-id TEST-007 --spec-path docs/specs/SPEC-0212-spec-pr-github-case-identity.md --test-path tests/skills/test-aai-pr-preflight.sh --red docs/ai/tdd/pr-github-case-identity-red.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status GREEN --test-id TEST-007 --spec-path docs/specs/SPEC-0212-spec-github-case-identity.md --test-path tests/skills/test-aai-pr-preflight.sh --green docs/ai/tdd/pr-github-case-identity-green.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status REFACTOR_COMPLETE --test-path tests/skills/test-aai-pr-preflight.sh --refactor docs/ai/tdd/pr-github-case-identity-refactor.log
    - node .aai/scripts/state.mjs set-tdd-cycle --status IDLE
```
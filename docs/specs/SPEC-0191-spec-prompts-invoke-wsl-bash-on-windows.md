---
id: spec-prompts-invoke-wsl-bash-on-windows
type: spec
number: 191
status: implementing
mutation_gate: v1
frozen_sha256: e8aad8fa92fdcbd2bdc0d368ae0760e641f2b94e48242b17989ac6da8fa8f2ce
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-0085-prompts-invoke-wsl-bash-on-windows.md
  rfc: null
  pr: []
  commits: []
---

# Spec — skill prompts must not tell a Windows agent to invoke bash for tests

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-0085-prompts-invoke-wsl-bash-on-windows.md
- Related done work, not this defect: ISSUE-0009, CHANGE-0133 (wrapper fallback), CHANGE-0139 (TEST-024 POSIX bash-prefix pin)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: owner invoked `/aai-ship` with TDD. The defect is prompt-layer drift against a live pin (TEST-024 currently REQUIRES the bash-only shape). Only a RED observed against that pin, then a GREEN after the contract revision, proves the new Windows-safe wording cannot regress to bash-only.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: dedicated branch; prompt + one test file; no parallel session competes.
- User decision: inline
- Base ref: main
- Worktree branch/path: cursor/prompts-invoke-wsl-bash-on-windows-a7ce (inline)
- Inline review scope: `.aai/VALIDATION.prompt.md`, `.aai/SKILL_LOOP.prompt.md`, `.aai/SKILL_VERIFY.prompt.md`, `.aai/SKILL_TEST_SKILLS.prompt.md`, `.aai/SKILL_BOOTSTRAP.prompt.md`, `.aai/SKILL_DESLOP.prompt.md`, `.aai/SKILL_TDD.prompt.md`, `.aai/system/DYNAMIC_SKILLS.md`, `tests/skills/test-aai-win-fallback.sh`, `tests/skills/lib/prompt-diet-ledger.sh`, `docs/issues/ISSUE-0085-prompts-invoke-wsl-bash-on-windows.md`, `docs/specs/SPEC-0191-spec-prompts-invoke-wsl-bash-on-windows.md`

## Acceptance Criteria Mapping
- Maps to: docs/issues/ISSUE-0085-prompts-invoke-wsl-bash-on-windows.md Expected Behavior

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN TEST-024 runs THEN TECHNOLOGY.md, TECHNOLOGY_TEMPLATE.md and AGENTS.md SHALL still carry both canonical literals, the repo-root rule and the prohibition (CHANGE-0139 unchanged) | done | docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/green-TEST-024.log | — | trio pin |
| Spec-AC-02 | WHEN TEST-024 walks the seven CHANGE-0139 prompt files plus SKILL_TDD.prompt.md THEN each file SHALL name the Windows `.ps1` literal or the phrase Canonical test invocation with `.aai/AGENTS.md`, and SHALL NOT carry a bare `.aai/scripts/aai-run-tests.sh` after both prefixed literals are stripped | done | docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/green-TEST-024.log | — | Windows-safe prompt contract |
| Spec-AC-03 | WHEN a listed prompt names the POSIX `bash .aai/scripts/aai-run-tests.sh` prefix THEN it SHALL also name the Windows `.ps1` literal in the same file (so a Windows agent is never left with bash-only) | done | docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/green-TEST-024.log | — | no bash-only Windows instruction |
| Spec-AC-04 | WHEN `tests/skills/test-aai-win-fallback.sh` runs in full THEN it SHALL exit 0 | done | docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/green-TEST-027.log | — | CHANGE-0139 suite stays green |
| Spec-AC-05 | WHEN the prompt-diet suite TEST-010/TEST-012 run THEN they SHALL exit 0 after any JUSTIFIED_ADDITIONS true-up for this scope | done | docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/green-TEST-028.log | — | companion obligation |

## Implementation plan
1. Revise `test_024` in `tests/skills/test-aai-win-fallback.sh`: keep the trio pin; extend the prompt list with SKILL_TDD; require Windows literal OR AGENTS.md Canonical test invocation; require Windows literal whenever the POSIX bash prefix is present; keep the residue bare-path strip (strip BOTH prefixes).
2. Observe RED on the current corpus (SKILL_TDD missing; prompts bash-only).
3. GREEN: edit each listed prompt so it carries the AGENTS.md pair (both literals) or an AGENTS.md Canonical test invocation pointer plus the Windows literal when bash remains.
4. True-up `tests/skills/lib/prompt-diet-ledger.sh` JUSTIFIED_ADDITIONS for measured `.aai/*.prompt.md` growth.
5. Wrapper WSL-denial / NUL sanitization stays out of scope (ISSUE-0009 / CHANGE-0133 already shipped the `.ps1` Git Bash path).

## Test Plan

| Test ID  | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|----------|---------|------|----------------------|-------------|----------|--------|
| TEST-024 | Spec-AC-01, Spec-AC-02, Spec-AC-03 | integration | tests/skills/test-aai-win-fallback.sh | trio pin plus Windows-safe prompt contract including SKILL_TDD | sed:s/powershell -NoProfile -File \.aai\/scripts\/aai-run-tests\.ps1/powershell -NoProfile -File .aai\/scripts\/aai-run-tests.PS1/ | green |
| TEST-027 | Spec-AC-04 | integration | tests/skills/test-aai-win-fallback.sh | ALL_TESTS still includes 024 | sed:s/ALL_TESTS="007 009 013 014 015 016 017 018 019 020 021 022 023 024 025 026"/ALL_TESTS="007"/ | green |
| TEST-028 | Spec-AC-05 | integration | tests/skills/test-aai-prompt-diet.sh | TEST-010 and TEST-012 stay green after ledger true-up | sed:s/"802 prompts-invoke-wsl/"0 prompts-invoke-wsl/ | green |

## Verification
- RED: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-win-fallback.sh 024` fails on the current bash-only corpus before prompt edits. Store `docs/ai/tdd/spec-prompts-invoke-wsl-bash-on-windows/red-TEST-024.log`.
- GREEN: same command plus full `test-aai-win-fallback.sh` and `test-aai-prompt-diet.sh` TEST-010/012 exit 0.

## Evidence contract
- ref_id: prompts-invoke-wsl-bash-on-windows
- Strategy: tdd — stored RED artifact per AC-gating test plus GREEN runs.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|----------|-------------------------------|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## Registry items closed by this scope
none

## Out of scope
- Re-implementing `aai-run-tests.ps1` WSL/Git Bash fallback (ISSUE-0009 / CHANGE-0133)
- NUL sanitization of WSL denial text (wrapper, not prompts)
- Native cmd.exe-only Windows (no Git Bash)

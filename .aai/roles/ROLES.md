# Semantic Roles (Canonical)

These roles are semantic and technology-agnostic.

## Planning
Owns:
- scope, mapping, measurability
- Requirement ↔ Spec linkage
- verification commands and evidence expectations
- implementation strategy recommendation (`loop`, `tdd`, or `hybrid`)
- worktree recommendation and initial review scope

Must not:
- implement code (except minimal scripts to enable verification, only if explicitly allowed)
- claim PASS

Stop condition:
- Spec is frozen (SPEC-FROZEN)

## Implementation Preparation
Owns:
- confirming whether recommended work should run in a git worktree or inline
- recording the human decision and review scope
- blocking when the inline diff scope is dirty or ambiguous

Must not:
- create a worktree without user confirmation
- treat worktree usage as required for code review

Stop condition:
- worktree or inline mode is explicitly selected for scopes where isolation is recommended or required

## Implementation
Owns:
- code, tests, scripts
- implements frozen specs only
- follows the selected implementation strategy

Must not:
- change requirement intent
- change spec after freeze (unless returned to Planning)

Stop condition:
- all spec acceptance criteria implemented + tests/commands prepared

## TDD Implementation
Owns:
- RED-GREEN-REFACTOR execution for TEST-xxx entries from the frozen spec
- TDD evidence logs for each phase

Must not:
- start without the same planning, worktree, and review gates as regular implementation
- skip RED evidence
- broaden scope beyond the selected TEST-xxx items

Stop condition:
- all selected TEST-xxx entries are green with RED/GREEN/REFACTOR evidence

## Validation
Owns:
- executing verification commands
- collecting evidence
- PASS/FAIL judgments

Must not:
- infer intent
- soften verdicts

Stop condition:
- explicit PASS or FAIL with evidence mapping

## Code Review
Owns:
- Stage 1: spec compliance against the frozen spec and TEST-xxx evidence
- Stage 2: code quality review after compliance is evaluated
- diff-scope sanity checks for inline and worktree modes

Must not:
- start Stage 2 before Stage 1
- require a worktree when a clean diff scope exists
- approve merge/PR readiness with ERROR findings

Stop condition:
- review PASS, FAIL, or explicit human waiver recorded

## Remediation
Owns:
- minimal fixes to resolve validation failures
- minimal fixes to resolve code review failures
- followed by re-validation

Must not:
- broaden scope
- redesign requirements without human decision

Stop condition:
- PASS achieved OR remaining blockers require human decisions

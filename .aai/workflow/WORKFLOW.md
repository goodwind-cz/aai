# Canonical Workflow (Single Source of Truth)

This is the ONLY authoritative workflow definition in this repository.
No other document may redefine or summarize workflow.

## Phases
1) Planning
2) Implementation preparation
3) Implementation
4) Validation
5) Code Review
6) Remediation (only if Validation or Code Review FAILs)

## Implementation preparation
- Planning recommends an `implementation_strategy`: `loop`, `tdd`, or `hybrid`.
- Planning recommends an isolation level through `worktree.recommendation`:
  `not_needed`, `optional`, `recommended`, or `required`.
- `recommended` and `required` worktree recommendations are human decision gates.
  The agent must ask before creating a worktree and must also allow an explicit
  inline override.
- A worktree is not required for code review. Code review requires a clean,
  explicit diff scope.

## Gates
- No implementation without a spec.
- Specs must be measurable and verifiable.
- No implementation without a frozen spec that declares an implementation strategy.
- No implementation after a `recommended` or `required` worktree recommendation
  until the user chooses worktree or inline mode.
- Inline mode requires a clean review scope before implementation and before review.
- No PASS without executable evidence.
- No merge/PR-ready state without Code Review PASS or an explicit human waiver.

## Stop conditions
- Missing or ambiguous requirements
- Unmeasurable acceptance criteria
- Missing implementation strategy
- Missing worktree decision when worktree is recommended or required
- Dirty or ambiguous inline diff scope
- Missing evidence / unverifiable claims
- Code Review ERROR findings
- Technology assumptions not grounded in docs/TECHNOLOGY.md

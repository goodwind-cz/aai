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
- Closeout PR ceremony: after Code Review PASS, the agent opens the PR via
  /aai-pr (.aai/SKILL_PR.prompt.md); the agent never merges — merging is
  operator-only.
- Close-policy (resolve-or-promote): a doc MUST NOT transition to `status: done`
  while unresolved decisions remain as free-text WARNINGs in its body. Resolve
  them before close, or promote each to a tracked item (a per-AC `blocked`/
  `deferred` row with a future `Review-By`, or a follow-up tracked doc). Never
  close `done` with buried WARNING decisions. (`docs-audit` surfaces these in its
  "Open decisions on done docs" report. Pre-commit enforcement is controlled by
  the `close_gate` and `body_lint` keys in `docs/ai/docs-audit.yaml`;
  report-only by default.)

## Ceremony levels (RFC-0009 / spec-scale-adaptive-ceremony)

Planning declares `ceremony_level: 0..3` in the spec frontmatter at freeze
(.aai/PLANNING.prompt.md step 10). An absent field is implicit level 2 (legacy
specs: zero migration), and every mechanical consumer FAILS CLOSED: the
deterministic dispatch maps an absent or unparseable value to 2 (full
ceremony), so a bad declaration can only ever add ceremony, never remove it.
Levels 0 and 1 additionally REQUIRE a body line starting with the literal
`Ceremony justification: ` (level-inflation guard; the docs-audit close gate
checks it — enforcement rides the `close_gate` dial in docs/ai/docs-audit.yaml,
report-only by default). Review may re-classify a level UPWARD as a recorded
finding. Gates prune by THIS table only, never silently:

| Gate / dispatch rule        | L0 (typo/docs-only)                                  | L1 (S fix, single surface)          | L2 (default)   | L3 (protected surfaces)                                          |
|-----------------------------|------------------------------------------------------|-------------------------------------|----------------|------------------------------------------------------------------|
| Spec artifact               | tech-note in the CHANGE doc (carries SPEC-FROZEN, level, justification; STATE spec_path names it) | lean SPEC (AC table only) + justification | full SPEC | full SPEC                                                        |
| Freeze proxy (rule 6)       | SPEC-FROZEN marker only (frontmatter-status arm pruned) | full                              | full           | full                                                             |
| Worktree gate (rule 8)      | on recommendation                                    | on recommendation                   | on recommendation | REQUIRED semantics — an explicit user_decision must be RECORDED for ANY recommendation (house 'required' rule: operator may still record an inline override with rationale; the decision, not the isolation, is what rule 8 mandates)      |
| Validation (rules 10/11)    | required — suite run                                 | required — suite re-run + targeted probe | required — full independent validation | required — full independent validation |
| Code review (rule 13)       | OPTIONAL — operator may set required:false or waive (recorded) | required (single dual-verdict)  | required       | MANDATORY on the most capable tier; a waiver is flagged to the operator (needs_llm), never auto-accepted |
| Close gate (docs-audit)     | justification line required                          | justification line required         | —              | —                                                                |
| PR ceremony                 | unchanged                                            | unchanged                           | unchanged      | + operator checkpoint before merge (explicit final-diff sign-off) |

Protected surfaces (L3 canonical defaults; project-owned override/extension:
`protected_paths_l3` in docs/ai/docs-audit.yaml):
- state engine: .aai/scripts/state.mjs, .aai/scripts/lib/state-engine.mjs,
  .aai/scripts/lib/state-core.mjs
- allocator: .aai/scripts/allocate-doc-number.mjs
- guards: .aai/scripts/pre-commit-checks.sh, .aai/scripts/pre-commit-checks.ps1
- workflow canon: .aai/workflow/WORKFLOW.md, docs/CONSTITUTION.md

A spec whose scope touches a protected surface MUST declare level 3.
Evidence-before-claims holds at EVERY level: validation and the
no-PASS-without-executable-evidence gate are never pruned — levels scale the
artifact weight and review optionality, not the evidence bar.

## Re-runnable Maintenance Skills

These skills are not workflow roles. They are agent-invocable entry points that
can be re-run at any time, independent of the workflow phase.

| Skill | Description | Source |
|-------|-------------|--------|
| `aai-docs-canon` | Consolidate layered docs into canonical per-domain layer in `docs/canonical/`; archive originals to `docs/_archive/` with back-links; two-phase with HUMAN gate. | `.aai/SKILL_DOCS_CANON.prompt.md` (RFC-0003 / SPEC-0002) |
| `aai-test-canon` | Consolidate fragmented tests into canonical per-domain layer in `tests/canonical/`; archive originals to `tests/_archive/` with back-links; scaffold RED stubs for uncovered criteria; two-phase with HUMAN gate. | `.aai/SKILL_TEST_CANON.prompt.md` (RFC-0006 / SPEC-0008) |
| `aai-docs-audit` | Docs hygiene and drift audit — orphan/false-done/stale detection. | `.aai/SKILL_DOCS_AUDIT.prompt.md` (RFC-0002) |

## Stop conditions
- Missing or ambiguous requirements
- Unmeasurable acceptance criteria
- Missing implementation strategy
- Missing worktree decision when worktree is recommended or required
- Dirty or ambiguous inline diff scope
- Missing evidence / unverifiable claims
- Code Review BLOCKING findings (code_quality verdict fail)
- A `done` transition requested while open decisions remain buried as free-text
  WARNINGs (resolve-or-promote to a tracked item first)
- Technology assumptions not grounded in docs/TECHNOLOGY.md

---
id: implementation-mode-choice
type: change
number: null
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — surface an implementation-mode choice at intake (TDD / direct+tests / no-tests)

## Summary
- After a full intake, AAI silently routes work through Planning's strategy pick,
  which for small changes tends to be the full TDD loop. A comparable small change
  through the full TDD loop burns roughly 3-5% of a weekly token limit, so the
  owner has to manually intervene and steer to direct implementation.
- This change surfaces the implementation mode to the user at the END of intake as
  an explicit 3-way choice with a recommendation, and honors the chosen lane all
  the way through Planning, Implementation, TDD, and Validation.

## Motivation / Business Value
- Verbatim owner feedback (real downstream AAI project): "Jakym zpusobem budes
  implementovat? Neni to tak velka zmena a nechci pouzivat TDD, aby to nespalilo
  tolik tokenu." and "AAI by mohl davat rovnou na vyber, jakym zpusobem
  implementovat - jestli kompletni TDD smycka, prima implementace s jednoduchymi
  testy, prima implementace bez testu (napr. tuning skript pro spousteni
  nepotrebuje testy - i v tomhle pripade mi AAI udelalo testy na tuning, kdyz se
  mu to explicitne nereklo)".
- Value: trivial scopes stop paying the full-TDD token tax; the expensive lane is
  never silently forced, and the cheap lane is never a silent downgrade of rigor —
  it is the user's explicit choice or an explicit recommendation they accept.

## Scope
- In scope:
  - Extend the strategy enum with `direct` (implement + targeted regression tests,
    no RED/GREEN ceremony) and `untested` (implement only, NO tests; rationale
    REQUIRED).
  - Present the 3-way choice with a signal-derived recommendation at the end of the
    intake flow (single-sourced in .aai/INTAKE_COMMON.md, applied from SKILL_INTAKE).
  - Honor the chosen lane in PLANNING (respect a pre-recorded intake choice),
    IMPLEMENTATION / SKILL_TDD (lane behavior), and VALIDATION (strategy-conditional
    evidence).
- Out of scope:
  - Any change to the `tdd`/`hybrid`/`loop` lanes' rigor. Auto-detection of scope
    size (a new detection script would be a separate, larger scope).

## Affected Area
- .aai/scripts/state.mjs (strategy enum + untested rationale guard — protected L3),
  .aai/scripts/orchestration-dispatch.mjs (enum seam), .aai/INTAKE_COMMON.md,
  .aai/SKILL_INTAKE.prompt.md, .aai/PLANNING.prompt.md, .aai/IMPLEMENTATION.prompt.md,
  .aai/SKILL_TDD.prompt.md, .aai/VALIDATION.prompt.md. Operator-facing: it changes
  the intake flow the operator sees, hence user_visible: true.

## Desired Behavior (To-Be)
- At the end of intake the user is offered: full TDD loop / direct + targeted tests
  / direct without tests, WITH a recommendation derived from deterministic signals.
- If the user chooses, the choice is recorded via `set-strategy --source intake`
  and honored downstream. `untested` cannot be recorded without a rationale.
- If the user does not choose, behavior is UNCHANGED (Planning decides) — back-compat.

## Acceptance Criteria
- AC-001: `set-strategy` accepts `direct` and `untested`; all legacy values
  (`loop`/`tdd`/`hybrid`/`undecided`) still work unchanged.
- AC-002: `set-strategy --selected untested` WITHOUT a non-empty `--rationale` is
  rejected (exit 2) and writes nothing; `direct` needs no rationale.
- AC-003: the 3-way implementation-mode choice with a recommendation is surfaced at
  the end of the intake flow, recorded via `set-strategy --source intake`, and is a
  no-op (planner decides) when the user does not choose.
- AC-004: the chosen lane is honored downstream — PLANNING respects a pre-recorded
  intake choice; IMPLEMENTATION/SKILL_TDD run the `direct`/`untested` lanes;
  VALIDATION's RED-proof demand is strategy-conditional and never weakens tdd/hybrid.

## Verification
- bash tests/skills/test-aai-state.sh
- bash tests/skills/test-aai-implementation-mode.sh
- bash tests/skills/test-aai-hitl-propagation.sh
- bash tests/skills/test-aai-prompt-diet.sh
- node .aai/scripts/docs-audit.mjs --check --strict --no-event

## Constraints / Risks
- .aai/scripts/state.mjs is a `protected_paths_l3` surface; this ride is ceremony
  level 3 and is authorized by a frozen ceremony_level:3 spec (TEST-014 gate).
- No secret referenced; SECRETS PREFLIGHT skipped.

## Notes
- Design principle: the cheap lane must be an explicit user choice or an accepted
  recommendation; the expensive lane must never be silently forced on trivial scopes.

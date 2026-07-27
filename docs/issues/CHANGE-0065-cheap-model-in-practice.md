---
id: cheap-model-in-practice
number: 65
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Cheap-model delegation in practice: Haiku for mechanical roles, tier-appropriate validation

## Summary
- MODEL_ROUTING exists but the cheapest tier is never exercised: session
  telemetry (now visible via SPEC-0089 reporting) shows every role ran on
  sonnet/opus/fable — mechanical work included. Bind mechanical roles to
  claude-haiku-4-5 via MODEL_ROUTING roles overrides, route L0/L1-lane
  validation to sonnet, and codify the orchestrator practice of dispatching
  mechanical ceremony steps (DRAFT-ref sweeps, CHANGELOG entry drafting,
  close bookkeeping checks) to haiku-tier subagents.

## Motivation / Business Value
- Original operator mandate: "dusledne deleguj na jine modely, ktere ti
  usetri kredity/tokeny/cas". Industry baseline routes ~70% of calls to
  small models; the factory routes ~0% despite deterministic binding
  infrastructure being in place since CHANGE-0058's sibling (MODEL_ROUTING).
- Per-role rollup (metrics-report) now makes the effect measurable —
  before/after comparison becomes possible for the first time.

## Scope
- In scope:
  - .aai/system/MODEL_ROUTING.yaml roles overrides: Metrics Flush ->
    claude-haiku-4-5 (already mechanical tier — make it explicit),
    Technology extraction / Bootstrap / Worktree decision -> haiku (tier
    default already covers; verify binding resolves), and a new
    documented convention block for ceremony micro-tasks.
  - Ceremony-lane validation routing: dispatch rule-11 lightweight lane
    (L0/L1, lane.validation_depth == declared_scope) gets suggested_model
    claude-sonnet-5 instead of the standard-tier default when routing is
    bound — mechanical change in orchestration-dispatch.mjs suggestModel
    (lane-aware role override key, e.g. roles["Validation@lightweight"]).
  - Tests: dispatch suite stanzas for the lane-aware resolution (bound vs
    unbound, lightweight vs full); MODEL_ROUTING parse of the new key form.
  - Documentation: MODEL_ROUTING comment block + USER_GUIDE routing note.
- Out of scope: changing tier defaults (mechanical/standard/premium map
  stays); any harness-side model selection mechanics; PRICING changes.

## Affected Area
- .aai/system/MODEL_ROUTING.yaml, .aai/scripts/orchestration-dispatch.mjs
  (suggestModel lane-aware lookup only — NOT the decide() rule table),
  tests/skills/test-aai-orchestration-dispatch.sh, docs.

## Desired Behavior (To-Be)
- Dispatch for a mechanical role emits suggested_model claude-haiku-4-5;
  rule-11 dispatch on an L0/L1 lane emits claude-sonnet-5; full-lane
  validation keeps the existing behavior (standard tier + independence
  swap). Unbound repos (no MODEL_ROUTING file) unchanged.

## Acceptance Criteria
- AC-001: with the shipped MODEL_ROUTING, a Metrics Flush dispatch resolves
  suggested_model claude-haiku-4-5 (suite-verified via fixture root).
- AC-002: rule-11 dispatch with lane lightweight resolves the lane-aware
  override; full lane resolves the existing default; both suite-verified.
- AC-003: absent MODEL_ROUTING file => suggested_model null everywhere
  (regression pin, existing TEST-019 arm still green).
- AC-004: validator-independence swap still wins over lane override when
  models collide (suite-verified).
- AC-005: no regression — dispatch suite green locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-orchestration-dispatch.sh
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected: orchestration-dispatch.mjs is NOT on
  protected_paths_l3 (verify at planning); suggestModel is CLI-layer
  annotation, decide() rule table untouched.
- Risk: haiku under-delivers on a mechanical task — mitigation: binding is
  a per-repo config file, one-line revert; the affected roles produce
  script-verified outputs (flush/close run deterministic CLIs).

## Notes
- Session evidence: per-role rollup 2026-07-26 shows 0 haiku tokens across
  15.9M+ recorded. Operator mandate for diligent delegation (original
  assignment) + run-level autonomy 2026-07-27. Autopilot intake: metrics
  question skipped, human_time_minutes null.

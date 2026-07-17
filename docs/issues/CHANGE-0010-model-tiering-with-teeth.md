---
id: model-tiering-with-teeth
type: change
number: 10
status: done
links:
  research: RES-0001
  pr:
    - 54
  commits:
    - c245241
---

# Change — Model Tiering With Teeth (dispatch contract, mechanical checks, live cost data)

## Summary
- Turn the MODEL SELECTION guidance (one paragraph in ORCHESTRATION, enforced
  nowhere) into mechanism: model declared per dispatch, validator independence
  checked mechanically, PRICING.yaml refreshed, token counts recorded.

## Motivation / Business Value
- RES-0001 finding F2: no MODEL field in the SUBAGENT_PROTOCOL contract, no
  `model:` in the 27 skill wrappers, zero tiering in ORCHESTRATION_PARALLEL;
  PRICING.yaml stale/wrong (opus-4-6 listed $15/$75 vs actual $5/$25) and has
  never priced a run because tokens_in/out are null in 100% of METRICS.jsonl.
  One recorded independence violation (RFC-0006, all roles one model) was
  caught only post-hoc. Premium models routinely do mechanical work.

## Scope
- In scope:
  1. SUBAGENT_PROTOCOL.md: add mandatory MODEL (or TIER) field to the dispatch
     contract; ORCHESTRATION_PARALLEL gets the same tiering text as single.
  2. `state.mjs set-validation`: warn/fail (configurable) when the validator's
     recorded model equals the implementer's recorded model for the scope.
  3. PRICING.yaml: refresh to the current Claude family (fable-5, opus-4-8,
     sonnet-5, sonnet-4-6, haiku-4-5), normalize `[1m]`-suffix lookup, stamp
     last_verified_utc; prune never-used vendor entries.
  4. `state.mjs append-run`: accept and encourage --tokens-in/--tokens-out
     (warn when null) so METRICS_FLUSH can finally compute cost_usd.
  5. Skill wrappers: add `model:` frontmatter where a cheap tier is safe
     (intake router, check-state, flush/report wrappers) — harmlessly ignored
     by non-Claude readers.
- Out of scope: mechanizing the orchestrator tick (separate change);
  auto-routing logic beyond declaration + verification.

## Affected Area
- .aai/SUBAGENT_PROTOCOL.md, .aai/ORCHESTRATION_PARALLEL.prompt.md,
  .aai/scripts/state.mjs, .aai/system/PRICING.yaml, .claude/skills/*/SKILL.md.

## Desired Behavior (To-Be)
- Every dispatch names its model/tier; independence is verified by a script,
  not memory; a completed work item has non-null tokens and a computed cost.

## Acceptance Criteria
- AC-001: dispatch contract documents MODEL as required; grep-wiring test
  confirms presence in SUBAGENT_PROTOCOL + both orchestration prompts.
- AC-002: `set-validation` with validator model == implementer model emits a
  warning by default and non-zero exit under an `independence: enforce` config
  key; different models pass silently.
- AC-003: PRICING.yaml resolves every model id recorded in METRICS.jsonl
  history (including `[1m]` suffix normalization); last_verified_utc set.
- AC-004: append-run with --tokens-in/--tokens-out persists values; flush
  computes non-null cost_usd for such runs; null tokens produce a visible
  warning in the flush report.
- AC-005: at least 3 wrappers carry `model:` frontmatter; docs-audit and
  existing suites stay green.

## Verification
- New test stanzas: independence check (same/different model), pricing lookup
  incl. suffix, append-run token persistence + flush cost computation.

## Constraints / Risks
- Model ids churn; keep PRICING.yaml update policy (30-day) and make lookup
  tolerant (prefix match) rather than exact-only. Independence enforcement must
  not block single-model environments — default warn, config to enforce.

## Notes
- Source: RES-0001 recommendation P1.2; steal noted from Superpowers
  ("always specify the model when dispatching").

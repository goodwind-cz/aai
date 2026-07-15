---
id: mechanize-deterministic-ticks
type: change
number: 9
status: draft
links:
  research: RES-0001
  pr: []
  commits: []
---

# Change — Mechanize Deterministic Ticks (orchestration dispatch, metrics flush/report as scripts)

## Summary
- Move fully deterministic agent work into scripts: the orchestrator's 14-rule
  dispatch decision, metrics flush arithmetic, and metrics report aggregation.
  Reserve LLM ticks for judgment, not switch statements.

## Motivation / Business Value
- RES-0001 finding F2/dispatch-granularity: the ORCHESTRATION decision logic is
  a first-match table over structured STATE enums — today a premium-model agent
  context (~10.7KB prompt + 27.6KB STATE) computes what a script determines;
  `orchestration-mode.mjs` (RFC-0005) already proved the pattern. METRICS_FLUSH
  is deterministic arithmetic + guarded cleanup; METRICS_REPORT forbids
  narrative in its own rules ("jq in a trench coat"). Each avoided LLM tick
  saves tokens, latency, and a nondeterminism surface.

## Scope
- In scope:
  1. New `.aai/scripts/orchestration-dispatch.mjs`: evaluates the 14 rules
     against STATE (same fail-closed philosophy as orchestration-mode.mjs),
     emits the dispatch block (role, scope, inputs, stop condition, suggested
     tier) or a NO-ACTION verdict; exit codes for branching. The LLM
     orchestrator prompt becomes: run the script, relay/execute its dispatch,
     and handle only auto-repair edge cases the script flags.
  2. `state.mjs flush` (or metrics-flush.mjs): implements METRICS_FLUSH steps
     (criteria check, cost computation via PRICING.yaml, append, work-item
     cleanup) with the existing transactional guarantees; METRICS_FLUSH.prompt
     reduces to invoking it.
  3. metrics-report.mjs: aggregates METRICS.jsonl into the report table;
     METRICS_REPORT.prompt reduces to invoking it.
- Out of scope: SKILL_LOOP redesign; parallel orchestration lock choreography
  (already scripted via docs-lock.mjs); removing the LLM orchestrator entirely
  (it still owns repair/ambiguity).

## Affected Area
- .aai/scripts/ (3 new/extended scripts), .aai/ORCHESTRATION.prompt.md,
  .aai/METRICS_FLUSH.prompt.md, .aai/METRICS_REPORT.prompt.md, tests/skills.

## Desired Behavior (To-Be)
- A loop tick's dispatch decision costs one node invocation; flush/report are
  reproducible script outputs; prompts shrink to thin wrappers; LLM effort is
  spent only where rules cannot decide.

## Acceptance Criteria
- AC-001: orchestration-dispatch.mjs reproduces the documented rule table:
  fixture STATEs for each of the 14 rules yield the expected dispatch (table-
  driven test), including post-remediation reset routing (SPEC-0012 G3).
- AC-002: unknown/invalid STATE degrades fail-closed: script exits non-zero
  with a named reason and the prompt path takes over (degrade-and-report).
- AC-003: flush computes cost_usd from PRICING.yaml when tokens are present,
  matches the documented flush criteria, and preserves the transactional
  guarantees (check-state green after flush; original preserved on failure).
- AC-004: report output is byte-deterministic for a fixed ledger fixture.
- AC-005: ORCHESTRATION/METRICS_* prompts shrink to wrappers (each ≤40 lines);
  existing suites green.

## Verification
- Table-driven dispatch fixtures (14 rules + 3 reset-routing cases); flush and
  report golden-file tests; end-to-end: one loop tick driven by the script
  produces the same dispatch as the prompt-driven path on the same STATE.

## Constraints / Risks
- The rule table now lives in two places during transition (script + prompt
  fallback) — make the script the single source and the prompt reference it;
  gate with a config key if needed. Keep Codex/Gemini path working (they can
  run node scripts the same way).

## Notes
- Source: RES-0001 recommendation P1.4 (findings F2, dispatch granularity).
- Complements (does not replace) CHANGE model-tiering-with-teeth: fewer LLM
  ticks and cheaper remaining ticks are independent wins.

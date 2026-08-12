---
id: validation-cost-calibration
number: 132
type: change
status: draft
user_visible: true
ceremony_level: 2
---

# Change — Validation cost calibration: lane-scaled depth + harness-aware role isolation (capability-detected, never hardcoded)

## Summary
- Downstream owner report (Codex-driven AAI project, 2026-08-12): on a
  medium TDD ride (~40 min wall) the independent validation took ~10:45 and
  consumed the most tokens of any phase. AAI-repo telemetry corroborates:
  Validation median 99k tokens/run, 18% share (Validation+Review = 37%).
- Owner-corrected harness facts (2026-08-12, source-level): current Codex
  CLI HAS native sub-agents — `spawn_agent(task_name, message, fork_turns,
  model, reasoning_effort)`; `fork_turns="none"` passes NO surrounding
  context (fresh eyes), model override per child,
  `agents.default_subagent_model` in config.toml; children can spawn
  children. Known instability: subagent model catalog is narrower than
  top-level and explicit overrides have historically been dropped
  (CLI ~0.145.0 reports), and MultiAgentV1 vs V2 differ — so capabilities
  MUST be detected at runtime and the granted model verified, never
  assumed.
- Goal: reduce validation cost where work is DUPLICATED, never where it
  thinks — validator independence (fresh context + different model where
  grantable) and adversarial probing stay untouched. Pre-registered KPI:
  Validation median tokens/run decreases while ride remediation rate does
  not increase (Role consumption section, SPEC-0117, is the instrument);
  regression = rollback.

## Acceptance Criteria
- AC-001 (universal lever, all harnesses): VALIDATION canon becomes
  lane-scaled — L0/L1: declared scope re-run + adversarial probes on the
  seams, NO blanket full-suite re-execution (close-before-CI ordering
  already guarantees the full-suite proof lands in CI); L2/L3: full depth
  unchanged. The lane rule is stated in the validation canon and the
  dispatch surfaces it (rule 11 lane reasons already exist).
- AC-002 (capability detection, never a harness table): the subagent
  protocol gains a capability-detection contract — fields
  multi_agent_backend, spawn_agent_available, spawn_model_catalog,
  fork_turns_supported — resolved AT RUNTIME by the orchestrating agent;
  behavior keyed on detected capabilities, explicitly NOT on
  harness == codex/claude string matching.
- AC-003 (Codex-native isolation): SUBAGENT_PROTOCOL documents the
  owner-specified fallback hierarchy for role isolation on Codex:
  (1) native spawn_agent with different model + fork_turns="none" for the
  validator, (2) spawn_agent with an available alternate catalog model
  when the requested one is rejected, (3) role-per-invocation
  `codex exec -m <model>` as hard-isolation fallback, (4) in-parent-session
  execution as LAST resort with a recorded residual risk. The existing
  "Codex has no subagents" style assumptions are removed wherever they
  appear in the corpus.
- AC-004 (telemetry honesty for routing): agent-run recording gains
  requested_model vs actual_model semantics — when a model override is
  requested for a role, the run note records both (grammar extension of
  the existing usage-note conventions), so a silently-dropped override is
  visible in METRICS instead of assumed; validator-independence claims in
  reports must cite actual_model.
- AC-005 (governance + measurement): prompt-corpus edits ride the diet
  ledger with measured bytes; the pre-registered KPI (Validation median
  down, remediation rate not up, read from the Role consumption section
  after ~5 rides) is recorded in the spec as the flip/rollback rule.

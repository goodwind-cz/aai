---
id: model-effort-routing
type: change
number: null
status: draft
capability: model-effort-routing
links:
  pr: []
  commits: []
---

# Change: every dispatch carries an explicit effort tier the harness can apply, and its token effect is measurable

## Summary
- Give every dispatched role an explicit reasoning-effort tier (low, medium or
  high) in the existing routing table, translate the tier into the native
  value of the detected harness, and record the requested tier, whether it was
  applied, and the cache read and cache creation tokens per role in METRICS.
- Add a deterministic evidence digest for Validation (AC-table walk and gate
  triage). It is off by default and can run in shadow mode, so its false-pass
  rate is measured before anyone may switch it on.
- Make the gain measurable: a per-role and per-effort METRICS report with a
  before and after split.

## Motivation / Business Value
- Owner priority (2026-11-12): visible speed and token-cost gains in AAI that
  reach downstream projects through a release.
- Measured on this repository's METRICS.jsonl, the last 30 flushed work items
  (from `slim-standing-role-context` to `release-corpus-hermetic`):
  87.4 M harness-total tokens and 391.67 USD recorded cost. Validation is 103
  runs and 41.2 M tokens (47 percent), Code Review 12.3 M, TDD Implementation
  13.8 M, Remediation 11.3 M, Planning 8.4 M. Only 50 of 1412 recorded runs
  carry decomposed in and out tokens; 524 carry a harness total. No run
  records an effort or a cache creation figure.
- `suggested_effort` already exists (SPEC-0110) but is advisory text: the
  shipped table resolves Planning, Implementation, TDD Implementation and
  Remediation to `default`, no canon tells the orchestrator to pass the value
  to the harness, and nothing records it. Its effect cannot be measured.
- External evidence (research-agentic-efficiency-2026-11 ideas A2, A3, A6, A8),
  checked against primary docs on 2026-11-12:
  - Claude Code sub-agents doc: an `effort` frontmatter field and a
    per-invocation `effort` parameter (low, medium, high, xhigh, max; v2.1.292
    or later); `CLAUDE_CODE_EFFORT_LEVEL` takes precedence over both.
  - Claude Code changelog 2.1.316 (2026-10-31): `CLAUDE_CODE_SUBAGENT_EFFORT`
    sets the subagent level when nothing else names one. 2.1.317: a subagent
    on another model uses that model's saved effort, not the session's.
  - Codex config reference: `model_reasoning_effort` and
    `agents.default_subagent_reasoning_effort` (an explicit spawn effort wins).
  - Gemini thinking doc: `thinking_level` is low or high on Gemini 3 Pro;
    minimal, low, medium or high on Gemini 3 Flash.
  - Prompt-caching prices and the claim that effort changes invalidate the
    cache come from the research report; not re-verified here.

## Scope
- In scope:
  1. Effort per role: a closed effort vocabulary, explicit rows for every
     dispatched role, a per-harness translation section, an env-override
     signal, and canon that passes the value through the harness's own
     per-dispatch knob.
  2. Telemetry: `append-run` and `log-tick` record requested effort, how it
     was applied, and cache read and cache creation tokens where the harness
     reports them. `metrics-flush` carries them to METRICS.
  3. Measurement: `metrics-report.mjs` gains a per-role and per-effort view
     with a before and after split by date.
  4. Evidence digest (opt-in, measured): a deterministic script that walks the
     frozen spec's AC table and runs the mechanical gates, a project dial
     `off | shadow | on` (default off), a shadow record paired with the
     validator's verdict, and a score that says when it may be promoted.
  5. Cache-friendly dispatch: pin that the assembled role payload is
     byte-identical across refs up to its scope section, which comes last.
- Out of scope: cache pricing in cost computation, refreshing model ids in the
  routing table (Haiku 5.5 and others), a cheap-tier LLM step, the Batch API,
  1-hour cache TTL, changing who owns the routing table.

## Affected Area
- `.aai/system/MODEL_ROUTING.yaml`, `.aai/scripts/orchestration-dispatch.mjs`,
  `.aai/scripts/state.mjs` (append-run, log-tick), `.aai/scripts/metrics-flush.mjs`,
  `.aai/scripts/metrics-report.mjs`, `.aai/scripts/append-event.mjs`, a new
  evidence-digest script, canon prompts that dispatch roles (SKILL_LOOP,
  ORCHESTRATION_PARALLEL, SUBAGENT_PROTOCOL, SKILL_SHIP, VALIDATION).

## Desired Behavior (To-Be)
- A dispatch verdict names the effort tier and the harness-native value. The
  loop passes the value through the harness knob (Claude Code Agent `effort`,
  Codex spawn `reasoning_effort`) and records what it asked for and how it was
  applied.
- METRICS shows tokens and cost per role and per effort, before and after a
  given date.
- With the dial on `shadow`, each Validation round records a digest beside
  its verdict; the score command reports the false-pass candidates.

## Acceptance Criteria
- AC-001: every dispatched role resolves an explicit effort in the shipped
  table (high for Planning, Validation and Code Review; medium for
  Implementation, TDD Implementation and Remediation; low for mechanical roles).
- AC-002: on Claude Code, Codex and Gemini the verdict carries the harness-native
  value; on cursor and unknown harnesses, or without the new section, it
  carries null and the rest of the output is unchanged.
- AC-003: `append-run` and `metrics-flush` carry requested effort, how it was
  applied, and cache read and creation tokens into METRICS; absent flags stay
  absent.
- AC-004: `metrics-report.mjs` prints a deterministic per-role and per-effort
  table with a before and after split.
- AC-005: the evidence digest is off by default; in shadow mode it records one
  line per Validation round, and its score names the false-pass candidates and
  whether promotion is allowed.
- AC-006: the assembled payload of each role is byte-identical across two refs
  up to its scope section, which is last.

## Verification
- Command(s) and expected results: the new suite and the existing suites
  `aai-orchestration-dispatch`, `aai-state`, `aai-metrics`, `aai-canon`,
  `aai-prompt-diet`, `aai-pr-preflight` exit 0; one green full sweep.

## Constraints / Risks
- `state.mjs` is an L3 protected surface; ceremony is L3.
- Raising Planning and Code Review to `high` may raise their cost; the effect
  is measured, not assumed.
- Most runs record only a harness total; cache figures will be sparse.
- Secrets preflight: no secret referenced.

## Notes
- Implementation mode (autopilot): Planning decides.
- Assumption: "cheapest tier" for mechanical verification is a deterministic
  script, which costs no model tokens and can be measured exactly. A cheap
  model step is left for a follow-up once a job remains for it.

---
id: validation-cost-calibration
type: product
capability: validation-cost-calibration
status: current
delivered_by:
  - CHANGE-0132
spec: docs/specs/SPEC-DRAFT-spec-validation-cost-calibration.md
updated: 2026-08-12
---

# Validation stops re-running the whole suite twice

## What it does

Independent validation used to re-run the ENTIRE discovered test suite on
every ride, even the small ones — a proof that CI produced again minutes
later on the same commit. Now, on a small/typo-fix ride (the two lightest
ceremony levels), the validator runs only the tests the change actually
declares plus targeted probes on the seams it touches, instead of the whole
repository's suite. Bigger, riskier rides keep the full independent
re-run exactly as before — nothing about their depth changed. Alongside
that, the factory's rule for running validation in a separate, unbiased
agent no longer depends on which AI harness you're using — it detects what
that harness can actually do (does it support spawning a sub-agent? with a
different model? with no shared context?) and picks the strongest isolation
it can, falling back gracefully rather than guessing from a name. And when
a validation run asks for a different model than the implementer used, the
factory now records both "what model we asked for" and "what model we
actually got" — so if a platform silently substitutes a different model
than requested, that's visible in the numbers instead of being mistaken for
genuine independence.

## How to use it

Nothing to configure. The lighter validation depth follows automatically
from a scope's declared ceremony level (set at planning time, same as
before); nothing changes for scopes at the two heavier levels. The
isolation and model-tracking behavior runs automatically every time a
validation role is dispatched — there is no flag to turn it on.

## Data model

No new files or records. The "requested model" / "actual model" pair rides
inside the existing free-text run note already stored per agent run
(`docs/ai/STATE.yaml`, flushed into `docs/ai/METRICS.jsonl`) — no new
STATE field, no schema change.

## Interfaces and contracts

- The validation canon (`.aai/VALIDATION.prompt.md`) states the lighter-lane
  rule: on the two lightest ceremony levels, run the declared scope plus
  adversarial probes on the seams, never a blanket full-suite re-run; on the
  two heaviest levels, behavior is unchanged. An unreadable or missing
  ceremony level always falls back to the heavier, full-suite behavior —
  never the lighter one.
- The subagent protocol (`.aai/SUBAGENT_PROTOCOL.md`) documents the runtime
  capability fields it detects and the four-step fallback order it tries
  when spawning an independent validator, from a native isolated sub-agent
  down to running in the same session as a documented last resort.
- Run notes can carry `requested_model=<id>` and `actual_model=<id>` markers
  side by side; a mismatch between the two is a visible sign that a
  requested model override did not take.

## Limits and non-goals

- The token-savings goal is not measured inside this change — it is a
  post-merge measurement taken over the next several rides, with a defined
  rollback if validation cost does not fall or if rework increases.
- This does not add a mechanical checker that verifies the AI orchestrator
  actually followed the capability-detection steps — it is process guidance
  the orchestrator follows, backstopped after the fact by the
  requested/actual model markers when a model override was involved.

## Links

- Request: docs/issues/CHANGE-0132-validation-cost-calibration.md
- Spec: docs/specs/SPEC-DRAFT-spec-validation-cost-calibration.md
- Validation evidence: docs/ai/reports/

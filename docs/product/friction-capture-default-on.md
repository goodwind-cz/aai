---
id: friction-capture-default-on
type: product
capability: friction-capture-default-on
status: current
delivered_by:
  - friction-capture-default-on
spec: docs/specs/SPEC-0088-spec-friction-capture-default-on.md
updated: 2026-07-26
---

# Friction feedback loop, activated (default-on capture + wrap-up triage)

## What it does

The factory's self-improvement loop (RFC-0012) had complete infrastructure
and zero data: capturing a friction observation depended on an agent
remembering to do it mid-failure. Capture is now the DEFAULT action at four
deterministic hook points — a validation FAIL, a remediation dispatch, a
canon-file gate/lint/CI failure, and a canon-surface check failure during
implementation. Session wrap-up then turns any captured observations into a
triage report with proposed intake one-liners, so recurring friction becomes
backlog instead of folklore.

## How to use it

Nothing to configure — hooks are on by default and never block:

- Work normally; when an AAI-owned failure fires at a hook point, one
  schema-v2 line lands in the local spool `docs/ai/friction/observations.jsonl`.
- Run `/aai-wrap-up` at session end: a non-empty spool always produces the
  offline triage report and lists top clusters as proposed intakes; an empty
  spool stays silent.
- Publishing anything externally stays review-mode (`/aai-feedback-upsert`,
  `--publish <fp> --confirm` only).

## Data model

No schema change — existing friction observation schema v2 (redacted,
allowlisted fields), local-only spool, gitignored.

## Interfaces and contracts

- Hook contract (FRICTION_PROTOCOL.md "Deterministic hook points"): ATTEMPT,
  not recall; taxonomy/exclusions unchanged; capture is best-effort and NEVER
  changes the primary step's exit code.
- Wired owners: VALIDATION (5h + 8), REMEDIATION (1/2), SKILL_PR (5d),
  IMPLEMENTATION (post-verification), SKILL_WRAP_UP (step 6 triage feed).

## Limits and non-goals

- Hooks are prompt-instruction deterministic, not runtime-enforced (an agent
  ignoring its prompt still captures nothing).
- A monitor stall that recovers without a FAIL verdict is not yet a hook
  (recorded residual risk; follow-up candidate).
- No new network behavior; triage and spool stay offline.

## Links

- Request: docs/issues/CHANGE-0062-friction-capture-default-on.md
- Spec: docs/specs/SPEC-0088-spec-friction-capture-default-on.md
- Validation evidence: docs/ai/reports/VALIDATION-friction-capture-default-on-20260726.md
  (local runtime artifact; summarized in the PR)

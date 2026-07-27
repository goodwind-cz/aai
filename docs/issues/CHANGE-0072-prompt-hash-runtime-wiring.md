---
id: prompt-hash-runtime-wiring
number: 72
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — prompt-hash runtime wiring: the orchestrator actually records the hash dispatch already computes

## Summary
- PR #170 (CHANGE-0070/SPEC-0096) delivered the producer end: dispatch
  computes `prompt_hash` (content-addressed identity of the effective
  instruction stack) and `state.mjs append-run --prompt-hash` accepts it.
  Nothing CONSUMES it yet: no orchestration practice tells the operator/
  orchestrator to carry the hash from the dispatch output into append-run,
  so METRICS still lands with prompt_hash null on every run. Close the loop
  with a SKILL_LOOP pointer (the canonical append-run boilerplate) — small,
  prompt-corpus-governed ride.

## Motivation / Business Value
- The whole point of content-addressed prompt identity (Promptbook adoption
  3) is correlating metric regressions with instruction changes; a computed-
  but-never-recorded hash answers nothing. One pointer sentence in the
  canonical loop prompt turns the dormant flag into live telemetry.

## Scope
- In scope:
  - .aai/SKILL_LOOP.prompt.md: in the append-run/metrics boilerplate, a
    single instruction — when the dispatch block printed `Prompt hash:`,
    pass it through as `--prompt-hash <hex>` on append-run for that role's
    run row.
  - Prompt-corpus governance for that edit: prompt-diet ledger JUSTIFIED_
    ADDITIONS entry + TEST-012 expected-total bump (exact bytes).
  - A pinned test asserting the pointer exists (grep contract in the
    existing prompt-corpus/loop suite — no new suite file).
- Out of scope: ORCHESTRATION.prompt.md (hard 40-line cap, already at
  40/40 — dispatch output already carries the hash, no second pointer
  needed); bundle inheritance provenance markers (separate follow-up);
  metrics-report per-run hash display (recorded follow-up, additivity
  renegotiation).

## Affected Area
- .aai/SKILL_LOOP.prompt.md, tests/skills/lib/prompt-diet-ledger.sh,
  the prompt-corpus byte-pin test, one grep-contract test.

## Desired Behavior (To-Be)
- An orchestrator following SKILL_LOOP verbatim records prompt_hash on
  every append-run whose dispatch printed one; METRICS rows gain non-null
  prompt_hash from the next ride onward.

## Acceptance Criteria
- AC-001: SKILL_LOOP append-run boilerplate names --prompt-hash pass-through
  from the dispatch `Prompt hash:` line (grep-contract test green).
- AC-002: prompt-corpus governance holds — diet ledger entry for the exact
  added bytes, TEST-012 expected total updated, suite green (RED first on
  the stale pin).
- AC-003: no regression — prompt-corpus + loop-related targeted suites
  green locally; docs-audit --check clean.

## Verification
- bash tests/skills/test-aai-prompt-diet.sh (TEST-010/TEST-012)
- targeted grep-contract suite for SKILL_LOOP
- node .aai/scripts/docs-audit.mjs --check

## Constraints / Risks
- No secrets referenced. Ceremony L2 (prompt corpus governed, no L3 path).
- Risk: byte-pin churn — mitigated by exact-byte ledger entry (established
  checklist).

## Notes
- Autopilot intake (blanket run authorization 2026-07-27): metrics question
  skipped, human_time_minutes null. Queue position: after
  ci-test-impact-selection (merged PR #171), before universality-proof.

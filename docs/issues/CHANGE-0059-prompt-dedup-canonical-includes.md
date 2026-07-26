---
id: prompt-dedup-canonical-includes
number: 59
type: change
status: done
links:
  pr:
    - 159
  commits:
    - bd4142d7bdbb316f4fd329b7d45698be435c7356
---

# Change — Prompt dedup: single canonical sources for ceremony rules, AC gate, and role boilerplate

## Summary
- Remove the three highest-cost duplications in the prompt corpus by replacing
  re-narrated copies with thin pointers to their single canonical source:
  (1) the ceremony-level rules table exists in 4 places (WORKFLOW.md 45-79,
  PLANNING.prompt.md ~109-121, VALIDATION.prompt.md ~94-108, plus the
  orchestration-dispatch.mjs implementation which is the only mechanical
  consumer); (2) VALIDATION.prompt.md's prose AC STATUS GATE (~lines 47-92)
  re-implements as LLM prose what `docs-audit.mjs --gate` computes
  deterministically for Rules 1/2/4-format (terminal-status check,
  empty-Evidence check, schema-invalid Review-By) — the script is already
  invoked later in the same prompt. Planning correction: the gate does NOT
  compute Rule 3 (repo-wide overdue interrupt) or the 14-day anti-cheat
  window; that prose is intentionally RETAINED (SPEC-0086 wins over this
  intake's original premise); (3) the ~15-line metrics/append-run
  "Subagent-mode carve-out (D5)" boilerplate is repeated at the foot of
  five prompts: PLANNING, IMPLEMENTATION, VALIDATION, REMEDIATION, and
  SKILL_TDD.

## Motivation / Business Value
- Every loop tick pays these duplicated bytes in context, on every role spawn
  (WORKFLOW.md declares itself "the ONLY authoritative workflow definition"
  yet its ceremony table is re-narrated downstream).
- Redundant LLM gate logic risks DIVERGENCE: for an unattended pipeline the
  validation verdict must not depend on which of two gate definitions the
  LLM happens to trust (auditor report 2026-07-26, roadmap item 2; prompt
  inventory: ceremony 4x duplication, VALIDATION 2612 words heaviest role).
- The prompt-diet floor (TEST-010) rewards net reduction: this scope REDUCES
  corpus bytes — no ledger credit needed, headroom grows.

## Scope
- In scope:
  - VALIDATION.prompt.md: replace the prose AC STATUS GATE rules with a
    mandatory `docs-audit.mjs --gate <ref>` invocation + verdict-consumption
    contract (the script is the gate; the prompt only runs it and honors the
    exit code), keeping only judgment residue that is not mechanical.
  - PLANNING.prompt.md + VALIDATION.prompt.md: replace their ceremony-level
    rule restatements with a pointer to the WORKFLOW.md table (single
    source) plus the one-line role-specific consequence each needs.
  - Extract the repeated D5 metrics/append-run carve-out into ONE canonical
    block (new .aai/system/ROLE_COMMON.md or reuse INTAKE_COMMON.md pattern)
    referenced by PLANNING / IMPLEMENTATION / VALIDATION / REMEDIATION.
  - Prompt-diet ledger: no growth expected; record the measured net
    reduction in the scope notes (floor test stays green by construction).
  - Update affected test stanzas that pin the removed prose (grep-pinned
    contracts in tests/skills/*) to pin the new pointer form instead.
- Out of scope:
  - Any change to WORKFLOW.md itself (L3 workflow canon — pointer target
    only, byte-identical).
  - Any change to orchestration-dispatch.mjs ceremony logic.
  - SUBAGENT_PROTOCOL slimming (separate roadmap item 3).
  - Behavior changes to docs-audit.mjs --gate.

## Affected Area
- Prompt corpus: .aai/VALIDATION.prompt.md, .aai/PLANNING.prompt.md,
  .aai/IMPLEMENTATION.prompt.md, .aai/REMEDIATION.prompt.md, one new shared
  block under .aai/system/; tests/skills stanzas pinning removed prose;
  prompt-diet ledger notes.

## Desired Behavior (To-Be)
- Exactly ONE canonical statement of the ceremony table (WORKFLOW.md), the
  AC-status gate (docs-audit.mjs --gate), and the D5 carve-out (shared
  block); role prompts carry pointers plus role-specific residue only.
- VALIDATION's gate step: run the script, consume the exit code; the prompt
  contains NO ISO date arithmetic and NO restated gate rules.
- Full suite green; measured corpus byte count strictly lower than before.

## Acceptance Criteria
- AC-001: grep proves single-source: the ceremony gate table rows exist only
  in WORKFLOW.md; PLANNING/VALIDATION contain a pointer line naming
  WORKFLOW.md and no table copy (fixture-verified greps).
- AC-002: VALIDATION.prompt.md delegates the mechanically-computed gate arms
  (Rules 1/2/4-format) to the docs-audit --gate invocation contract (names
  the script, honors its exit code) and RETAINS Rule 3 + the 14-day
  anti-cheat window as prose — the script does not compute those (per
  SPEC-0086; supersedes this intake's original blanket-removal wording).
- AC-003: the D5 carve-out text exists in exactly one file; the five role
  prompts reference it (grep-verified) and byte-shrink vs HEAD.
- AC-004: prompt corpus total bytes strictly decrease (wc -c over the
  TEST-010 glob, before vs after recorded); prompt-diet suite green with
  unchanged ledger constants.
- AC-005: full skill test framework passes (no pinned-prose stanza left
  asserting removed text).

## Verification
- bash tests/skills/test-aai-prompt-diet.sh
- bash tests/skills/test-framework.sh (full)
- Recorded before/after byte counts of the affected prompts.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Risk: over-pruning judgment residue from VALIDATION — mitigation: only
  text provably duplicating the script/table may move; anything else stays.
- Several test suites grep-pin prompt prose; each removed pin must be
  re-pointed, never deleted without a replacement contract.
- Ceremony L2 expected (no protected surface in scope; WORKFLOW.md is
  explicitly out of scope).

## Notes
- Source: independent-audit session report roadmap item 2
  (docs/project-sessions/2026-07-26-independent-audit-autonomy-pack.md);
  duplication inventory from the 2026-07-26 functionality audit.
- Autopilot intake (/aai-ship): metrics question skipped, human_time_minutes
  intake recorded as null.

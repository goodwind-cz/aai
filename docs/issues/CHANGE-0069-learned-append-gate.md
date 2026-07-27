---
id: learned-append-gate
number: 69
type: change
status: implementing
user_visible: true
links:
  pr: []
  commits: []
---

# Change — Learned-append gate: structurally enforced append-only self-learning

## Summary
- Adopt Promptbook's self-learning safety mechanism (analysis extension
  2026-07-27, candidate 2): any automated append to docs/knowledge/
  LEARNED.md must pass a structural gate — the new content must equal the
  old content plus a pure append (startswith check, byte-exact) — via a new
  .aai/scripts/learned-append.mjs; and every proposed rule is reviewed by a
  Teacher/critic step before landing. No self-improvement step can silently
  rewrite prior rules.

## Motivation / Business Value
- The friction loop (CHANGE-0062) now produces data and proposes intakes;
  its natural next step is proposing LEARNED rules. Without a structural
  gate, an automated writer could "improve" rules by rewriting them —
  the classic self-improvement failure mode. Promptbook's persist-only-if-
  pure-append guarantee is cheap and hard.

## Scope
- In scope:
  - .aai/scripts/learned-append.mjs: input = proposed rule text (+ target
    section flag); reads LEARNED.md, verifies the resulting file ==
    original + append (byte-exact startswith), appends with the house
    format (date + source), exit 0; ANY other transformation → exit 1 with
    a diff summary, nothing written. --dry-run prints the would-be append.
  - Teacher/critic wiring: SKILL_WRAP_UP step 6 and the friction-triage
    path route every proposed rule through a compact reviewer (the
    existing review subagent convention) BEFORE invoking the append
    script; prompt wording pointer-thin.
  - Tests: pure-append accepted; rewrite/reorder/mid-insert rejected with
    nothing written (tree-hash identical); dry-run zero-write; house
    format stamping.
  - PROFILES: learned-append.mjs -> core. Ledger true-up if prompt bytes
    grow (measure).
- Out of scope: retroactive LEARNED.md restructure; auto-generation of
  rules from friction clusters (stays proposal-only).

## Affected Area
- New .aai/scripts/learned-append.mjs, .aai/SKILL_WRAP_UP.prompt.md,
  .aai/system/FRICTION_PROTOCOL.md (pointer), tests/skills (new suite),
  PROFILES, possibly ledger.

## Desired Behavior (To-Be)
- The only sanctioned path to LEARNED.md for automation is the gate
  script; a rewrite attempt fails loudly with nothing written; humans
  editing by hand are unaffected.

## Acceptance Criteria
- AC-001: pure append accepted and stamped (date + source line, house
  format) (suite-verified).
- AC-002: any non-append transformation (rewrite, reorder, mid-insert,
  deletion) exits 1 with tree byte-identical (suite-verified).
- AC-003: dry-run prints the append and writes nothing (suite-verified).
- AC-004: wrap-up/triage prompts route proposals through the critic step
  and invoke the gate script (grep contracts); ledger true-up recorded if
  in-glob bytes grew.
- AC-005: no regression — new suite + friction-wiring + hygiene green
  locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-learned-append.sh (new)
- bash tests/skills/test-aai-friction-wiring.sh; bash tests/skills/test-aai-hygiene-pack.sh
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected (LEARNED.md/wrap-up not protected — verify).
- The gate protects the AUTOMATED path only; hand edits remain free
  (document honestly — this is a guardrail, not a security boundary,
  mirroring the AAI_OPERATOR_MERGE framing).

## Notes
- Source: Promptbook analysis extension, adoption candidate 2
  (specs/agents/self-learning.md persist-only-if-pure-append + Teacher).
  Autopilot intake: metrics question skipped, human_time_minutes null.

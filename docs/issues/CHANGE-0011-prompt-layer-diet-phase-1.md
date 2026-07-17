---
id: prompt-layer-diet-phase-1
type: change
number: 11
status: done
links:
  research: RES-0001
  pr:
    - 53
  commits:
    - 06cffb5
---

# Change — Prompt-Layer Diet, Phase 1 (dedupe, delete fiction, fix caching order, STATE digest)

## Summary
- Cut the highest-confidence ~30% of the ~434KB prompt corpus: shared intake
  include, remove fictional/dead content, correct SKILL_LOOP's inverted caching
  guidance, and inject a STATE digest instead of the whole file.

## Motivation / Business Value
- RES-0001 finding F3: 59 files / 9,571 lines ≈ 115k tokens; the 8 INTAKE_*
  files are ~67% identical boilerplate (4 blocks repeated verbatim ×8);
  SKILL_PROFILE (737 lines) is ~85% mock transcripts + inline JS for a script
  that does not exist; "FALLBACK if state.mjs is absent" + STATE-WRITE SAFETY
  footers repeat in ≥6 prompts; a minimal tick re-reads ~17–20k tokens; and
  SKILL_LOOP's CACHING DISCIPLINE puts STATE.yaml (27.6KB, mutates every tick)
  in the "stable prefix", guaranteeing a cache break per tick. Every duplicated
  policy edit currently requires 8–10 hand-synchronized file changes (drift
  already observed).

## Scope
- In scope:
  1. Extract the 4 duplicated intake blocks (language policy, SPEC-0015
     durable-identity, post-save check, metrics question) into one shared
     include (e.g. .aai/INTAKE_COMMON.md) referenced by all 8 INTAKE_* files.
  2. SKILL_PROFILE: delete the fictional Profiler content — either implement
     the real script or reduce the prompt to what exists today.
  3. Remove hand-edit fallback blocks + STATE-WRITE SAFETY footers from role
     prompts; replace with one line pointing to a single shared reference doc
     (progressive disclosure — load only when state.mjs is actually absent).
  4. SKILL_LOOP: fix the caching order (frozen canon first, volatile STATE +
     dispatch last) and switch the orchestrator payload from full STATE.yaml
     to the loop-digest.mjs output (~1KB decision-relevant slice).
- Out of scope: restructuring the top-10 SKILL_* prompts into step-files
  (BMAD-style, P2/P3); profiles/core-vs-extended install sets; AGENTS.md
  triple-listing cleanup (separate change if desired).

## Affected Area
- .aai/INTAKE_*.prompt.md (8), .aai/SKILL_INTAKE.prompt.md, SKILL_PROFILE,
  SKILL_LOOP, role prompts carrying the duplicated footers, loop-digest.mjs
  (consumer wiring only).

## Desired Behavior (To-Be)
- One canonical copy of each shared policy block; a policy change edits one
  file. Loop ticks carry a ~1KB STATE digest. Cache-stable prefix ordering
  documented correctly.

## Acceptance Criteria
- AC-001: the 4 shared blocks exist in exactly one file; INTAKE_* files
  reference it; total intake-file line count drops ≥50%; intake behavior
  unchanged (an intake dry-run still produces a compliant DRAFT artifact).
- AC-002: SKILL_PROFILE contains no references to non-existent scripts/APIs;
  file size reduced ≥60% (or the referenced script exists and is tested).
- AC-003: hand-edit fallback text appears in at most one shared reference doc;
  role prompts reference it in ≤2 lines each.
- AC-004: SKILL_LOOP instructs canon-first/STATE-last ordering and digest
  injection; grep-wiring test confirms; loop-digest output documented.
- AC-005: docs-audit --check --strict CLEAN repo-wide; existing skill tests
  green; measured corpus reduction reported in the PR body (before/after KB).

## Verification
- wc -c before/after; grep-wiring tests for include references and caching
  order; one end-to-end intake dry-run producing a valid DRAFT.

## Constraints / Risks
- Include mechanism must stay plain-file (agents just Read the referenced
  path) — no templating engine. Keep Codex/Gemini compatibility (they follow
  the same "read this file" instruction).

## Notes
- Source: RES-0001 recommendation P1.3 (findings F3).

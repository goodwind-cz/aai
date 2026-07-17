---
id: advisory-skills
type: change
number: 20
status: done
links:
  research: RES-0001
  pr:
    - 79
  commits:
    - 0b4ce55
---

# Change — Three Optional Advisory Skills: scout, deslop, plan-interrogate

## Summary
- Bundle of three small OPTIONAL pre/post skills from the pro-workflow sweep
  (RES-0001 P3): SKILL_SCOUT (pre-implementation readiness score 0-100 over 5
  dimensions, GO/HOLD advisory at 70 — never blocks); SKILL_DESLOP
  (diff-scoped AI-slop removal pass before review: obvious comments,
  defensive try/catch on trusted paths, premature abstractions — verify
  behavior unchanged via suite run); SKILL_INTERROGATE (plan decision-walk,
  one question at a time each with a recommended answer, codebase-first
  resolution, decision-ledger output to decisions.jsonl).

## Scope
- In scope: 3 prompts <=100 lines each (house style, cross-linked to
  VERIFY/DEBUG gates where natural), wrappers x3 trees each, catalog rows,
  grep suite. All three ADVISORY: no gate wiring, no dispatch rules changed.
- Out of scope: mandatory adoption anywhere; scoring persistence.

## Acceptance Criteria
- AC-001: each prompt exists <=100 lines with its core mechanism literal
  (scout: 5 named dimensions + GO/HOLD line; deslop: slop-class table >=5 +
  behavior-unchanged rule; interrogate: one-question rule + recommended-
  answer rule + ledger output format).
- AC-002: 9 wrappers + catalog rows; no gate/dispatch file touched.
- AC-003: suite + sweep green; prompt-diet floor holds; audit CLEAN.

---
id: verification-before-completion
type: change
number: 16
status: done
links:
  research: RES-0001
  pr:
    - 68
  commits:
    - 05f9208
---

# Change — Verification-Before-Completion Gate Skill

## Summary
- Operationalize AAI's one-line rule "no PASS without executable evidence"
  against its actual failure modes, as a named gate skill (Superpowers
  pattern, RES-0001 P2 recommendation 7a): no completion claim without FRESH
  verification evidence from the current tree state.

## Motivation / Business Value
- The rule exists but nothing enumerates the rationalizations it must defeat
  (stale runs, partial checks, trusting subagent self-reports, "tests passed
  earlier"). RES-0001 F1: behavioral-layer failures happen exactly where
  discipline is prompt-only and unstructured.

## Scope
- In scope: new .aai/SKILL_VERIFY.prompt.md (compact — gate function:
  IDENTIFY the claim -> RUN the check -> READ the output -> VERIFY it matches
  the claim -> only then CLAIM; a rationalization table naming the concrete
  dodges and their counters; verify-subagent-reports-via-diff rule); wiring
  references from IMPLEMENTATION/VALIDATION/SKILL_TDD completion steps (1-2
  lines each — prompts are freshly dieted); wrapper SKILL.md in the three
  agent trees; grep-wired test stanza.
- Out of scope: any script/enforcement machinery (behavioral skill, phase 1);
  REMEDIATION (already has systematic root-cause duty in its own scope).

## Acceptance Criteria
- AC-001: SKILL_VERIFY.prompt.md exists, <=120 lines, carries the gate
  function and a rationalization table with >=6 concrete entries.
- AC-002: IMPLEMENTATION, VALIDATION and SKILL_TDD completion steps reference
  the gate in <=2 lines each; prompt-diet byte budget stays over floor.
- AC-003: wrappers present in .claude/.codex/.gemini trees; grep test stanza
  wired; all suites green; repo audit strict CLEAN.

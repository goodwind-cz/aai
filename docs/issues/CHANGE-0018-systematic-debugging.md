---
id: systematic-debugging
type: change
number: 18
status: draft
links:
  research: RES-0001
  pr: []
  commits: []
---

# Change — Systematic-Debugging Discipline for Remediation

## Summary
- Give Remediation a root-cause-first debugging protocol (Superpowers
  pattern, RES-0001 P2 rec 7b): NO FIXES WITHOUT ROOT CAUSE — read errors
  fully, reproduce, check recent changes, instrument component boundaries,
  trace data flow backward.

## Motivation / Business Value
- REMEDIATION fixes named findings but has no debugging discipline — a
  remediator can symptom-patch (this session's fieldSpan finding was nearly
  missed for exactly this reason; the validator's probe forced the deeper
  root cause). Codify the discipline that made today's remediations good.

## Scope
- In scope: new .aai/SKILL_DEBUG.prompt.md (<=120 lines: 4-phase protocol —
  READ (full error, no tail-only) -> REPRODUCE (minimal, before any edit) ->
  ISOLATE (recent changes via git, boundary instrumentation, backward data
  trace) -> FIX-AT-CAUSE (never at symptom; the fix must make the
  reproduction pass); rationalization table >=5 rows ("just add a null
  check", "the test is flaky", "works on my run", ...); links to SKILL_VERIFY
  for the completion side); <=2-line wiring from REMEDIATION step flow;
  wrappers in 3 trees; grep test stanza.
- Out of scope: TDD/Implementation phases (RED discipline already covers
  them); scripts.

## Acceptance Criteria
- AC-001: SKILL_DEBUG.prompt.md exists, <=120 lines, 4-phase protocol literal,
  rationalization table >=5 data rows, SKILL_VERIFY cross-link.
- AC-002: REMEDIATION references the protocol in <=2 lines before its fix
  step; no obligation lost from its existing flow.
- AC-003: wrappers x3, grep test stanza wired, suites green, prompt-diet
  floor holds, repo audit strict CLEAN.

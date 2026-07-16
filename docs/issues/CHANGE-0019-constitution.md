---
id: constitution
type: change
number: 19
status: draft
links:
  research: RES-0001
  pr: []
  commits: []
---

# Change — Project Constitution With Justified-Exception Tracking

## Summary
- One short, ratified principles document (spec-kit pattern, RES-0001 P2
  rec 10) whose articles Planning checks at spec freeze, with any deviation
  DOCUMENTED AND JUSTIFIED in the spec rather than silently ignored
  (spec-kit's "Complexity Tracking" accountable-deviation pattern).

## Motivation / Business Value
- AAI's principles are scattered (AGENTS.md Rules + Engineering Best
  Practices, WORKFLOW gates, LEARNED). Scattered rules can't be checked at a
  gate; a single ratified article list can — and justified exceptions become
  auditable artifacts instead of silent drift.

## Scope
- In scope: docs/CONSTITUTION.md (<=60 lines, numbered articles distilled
  from AGENTS.md Rules — evidence-before-claims, simplicity/KISS+YAGNI,
  file-based portability, degrade-and-report, additive-first, single-writer
  state, operator-only merge; ratified-by + version header); PLANNING freeze
  step gains an article-check with a "Constitution deviations" spec section
  (none | justified list); SPEC_TEMPLATE gains the optional section;
  docs-audit close gate unchanged (report-only surface first); grep test
  stanza; AGENTS.md canonical-sources line.
- Out of scope: mechanizing the article check (phase 2 if the manual section
  proves valuable); rewriting AGENTS.md (articles POINT to it, dedupe later).

## Acceptance Criteria
- AC-001: docs/CONSTITUTION.md exists (<=60 lines, >=6 numbered articles,
  ratification header naming the owner).
- AC-002: PLANNING freeze step requires the deviations section; SPEC_TEMPLATE
  carries it; existing specs unaffected (section optional for pre-existing).
- AC-003: grep stanza wired; suites green; prompt-diet floor holds; repo
  audit strict CLEAN.

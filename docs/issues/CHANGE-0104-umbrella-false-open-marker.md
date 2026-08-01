---
id: umbrella-false-open-marker
number: 104
type: change
status: done
user_visible: false
links:
  pr:
    - 207
  commits:
    - 5bc44d1563d62b2d564509635bbe8d873df3e5ec
---

# Change — umbrella marker: deliberately-open multi-phase parents stop re-tripping the false-open heuristic

## Summary
- Recurring operator toil (3x this week, recorded in session memory): the
  false-open drift heuristic (SPEC-0039) re-flags a deliberately-open
  multi-phase parent (RFC-0012) after EVERY child-phase delivery commit that
  mentions its ref; the only remedy was re-suppressing with a fresh
  doc_lifecycle event, which the next child delivery invalidates again. This
  broke CI runs via the docs-audit CLEAN backstop repeatedly.
- Fix: an explicit frontmatter marker `umbrella: true` declares the open
  state intentional. While the doc stays open, the false-open probe is
  skipped ENTIRELY for it — and the suppression is VISIBLE (a reason line on
  the doc + an "Umbrella (deliberately open...)" count in the summary,
  emitted only when at least one umbrella exists, so repos without umbrellas
  keep byte-identical output).
- Abuse guard: the marker affects ONLY the false-open heuristic; stale-open,
  AC-table gates, orphan and every other audit class apply unchanged, and the
  umbrella count keeps the state visible in every report.

## Acceptance Criteria
- AC-001: an umbrella-marked open doc with child-delivery commits mentioning
  its ref is NOT flagged probable-false-open; the summary carries the
  umbrella count (suite-verified in an isolated fixture repo).
- AC-002: an UNMARKED doc in the same repo with the same delivery-commit
  shape stays flagged (heuristic untouched; positive control).
- AC-003: repos with zero umbrella docs produce byte-identical summary
  output (no new line).

## Verification
- tests/skills/test-aai-docs-audit.sh TEST-015 (new; fixture umbrella parent
  + unmarked positive control in one isolated repo); live proof on this repo:
  docs-audit CLEAN with RFC-0012 marked and NO fresh suppression event.

## Constraints / Risks
- Ceremony L1, strategy direct (deterministic 2-file heuristic change +
  marker + test). docs-audit-core.mjs is under .aai/scripts/lib/** — the
  SPEC-0097 shared-lib trigger — so this ride takes the HEAVY CI lane by
  design despite its size (the fast-lane gate correctly refuses it; honest
  note: the first fast-lane proof ride must be one that touches no shared
  lib).

## Notes
- Closes the "umbrella false-open toil" item from the 2026-08-01 weakness
  audit; replaces the memory-recorded manual suppression dance.

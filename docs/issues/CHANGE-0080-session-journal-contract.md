---
id: session-journal-contract
number: 80
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — session-journal: reconcile prompt contract with actual practice

## Summary
- Skill-sweep finding (group A): SKILL_SESSION_JOURNAL mandates
  SESSION-<slug>.md filenames, a 6-column INDEX and a 14-element template;
  actual practice is date-prefixed free-form files with a 3-column INDEX,
  and the newest session file is missing from INDEX entirely. Decide the
  canonical contract (strict vs. current loose convention), align the
  prompt AND the existing files, and add a cheap INDEX-completeness pin.

## Acceptance Criteria
- AC-001: one documented contract; prompt matches practice.
- AC-002: INDEX lists every docs/project-sessions/*.md (pinned test).
- AC-003: existing files conform or are grandfathered explicitly.

## Constraints / Risks
- Ceremony L1-L2 (prompt edit -> diet ledger if bytes grow).

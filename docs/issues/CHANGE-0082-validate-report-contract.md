---
id: validate-report-contract
number: 82
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — validate-report: reconcile the promised artifacts with the real validation path

## Summary
- Skill-sweep finding (group A): SKILL_VALIDATE_REPORT promises
  docs/ai/reports/LATEST.md (absent despite 20+ real reports), STATE
  last_validation sync, a screenshots/ dir (never created) and a filename
  pattern nothing on disk matches — the real reports come from
  VALIDATION.prompt.md via the loop. Either fold the useful bits
  (LATEST.md pointer, screenshot gallery) into VALIDATION.prompt.md and
  retire the separate contract, or make the skill actually produce them.

## Acceptance Criteria
- AC-001: exactly one canonical report contract documented and exercised.
- AC-002: LATEST.md exists and points at the newest report (pinned), or
  the promise is removed.
- AC-003: no divergent naming conventions remain in the prompts.

## Constraints / Risks
- Ceremony L1-L2 (prompt edits; diet ledger on growth).

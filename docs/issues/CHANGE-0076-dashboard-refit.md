---
id: dashboard-refit
number: 76
type: change
status: done
user_visible: false
links:
  pr:
    - 179
  commits:
    - b695885524506ef91065b5cd2085ea27924b434b
---

# Change — dashboard + test-skills prompts: drop dead source dump, fix schema docs, decide --publish

## Summary
- Skill-sweep finding (group A): SKILL_DASHBOARD.prompt.md is 19 KB/652
  lines; ~330 lines are a stale duplicate implementation dump of
  generate-dashboard.mjs (which exists and has diverged); the documented
  METRICS.jsonl schema is the old flat shape, not the real work-item
  ledger; a documented --publish flag is not implemented. Also (group C):
  SKILL_TEST_SKILLS.prompt.md (9.2 KB) carries stale illustrative content
  (hardcoded 11-skill example, pytest/cargo CI snippet). Rewrite both to
  thin script-first wrappers; either implement --publish or drop it.

## Acceptance Criteria
- AC-001: SKILL_DASHBOARD.prompt.md ~100 lines, script-first, real ledger
  schema documented (both supported shapes), --publish resolved.
- AC-002: SKILL_TEST_SKILLS.prompt.md trimmed of stale examples.
- AC-003: prompt-diet ledger reflects reductions; TEST-012 pin RED-first.

## Constraints / Risks
- Ceremony L2; prompt-corpus governance triggered (reductions).

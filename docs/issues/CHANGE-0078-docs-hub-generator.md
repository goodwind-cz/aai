---
id: docs-hub-generator
number: 78
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — docs-hub: deterministic generate-docs-hub.mjs (catalog is 8/35 skills stale)

## Summary
- Skill-sweep finding (group A): docs/SKILL_CATALOG.html (2026-07-07) is
  missing 8 of 35 current skills; SKILL_DOCS_HUB requires a ~70-file LLM
  fan-out per regen for mechanically parseable frontmatter. Add
  .aai/scripts/generate-docs-hub.mjs (mirrors generate-overview.mjs),
  regen at close ceremony best-effort like overview.

## Acceptance Criteria
- AC-001: generator emits the searchable catalog from SKILL.md frontmatter
  + prompt Goal sections; all current skills present (pin: count equals
  live .claude/skills listing).
- AC-002: byte-idempotent; close ceremony regenerates best-effort.
- AC-003: PROFILES classification for the new script.

## Constraints / Risks
- Ceremony L2.

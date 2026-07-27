---
id: decapod-prune
number: 77
type: change
status: done
user_visible: false
links:
  pr:
    - 177
  commits:
    - 070a61638556d5eddf534bcf887bf90ff810d6eb
---

# Change — prune the decapod integration surface (dead since March, CLI never built)

## Summary
- Skill-sweep finding (group C): SKILL_DECAPOD delegates entirely to an
  external `decapod` CLI that does not exist anywhere (no binary, no
  .decapod/, no test suite, 0 EVENTS, untouched since 2026-03-19); ~55 KB
  across the prompt, 4 wrapper copies, docs/ai/DECAPOD_INTEGRATION.md,
  docs/ai/compliance/* and a config example. Archive (docs/_archive/) or
  delete; drop the AGENTS.md listing line; PROFILES row removal.

## Acceptance Criteria
- AC-001: no decapod references remain in live trees (.aai, .claude/.agents/
  .codex/.gemini skills, AGENTS.md, PROFILES.yaml) — grep-pinned.
- AC-002: archived copies (if archive chosen) live under docs/_archive/
  with a provenance note; INDEX regenerated.
- AC-003: prompt-diet ledger reflects the corpus reduction; TEST-012 pin
  RED-first; layer-profiles 100% invariant holds.

## Constraints / Risks
- Ceremony L2 (multi-tree removal); reversible via git history.

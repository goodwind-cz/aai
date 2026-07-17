---
name: aai-scout
description: Use optionally before starting implementation to score readiness 0-100 over five dimensions (scope clarity, pattern familiarity, dependency awareness, edge cases, test strategy) with a GO/HOLD advisory at 70. Advisory only — never blocks.
---

Read the file `.aai/SKILL_SCOUT.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-scout`.

If `.aai/SKILL_SCOUT.prompt.md` does not exist, say: "SKILL_SCOUT not found — are you in an AAI project? Expected: .aai/SKILL_SCOUT.prompt.md"

---
name: aai-ship
description: Use when the user states a need and wants the factory to take it end-to-end autonomously — intake, planning, implementation, validation, review, product docs — pausing only at one ship checkpoint that opens the PR. Never merges.
---

Read the file `.aai/SKILL_SHIP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-ship <need>`.

If `.aai/SKILL_SHIP.prompt.md` does not exist, say: "SKILL_SHIP not found — are you in an AAI project? Expected: .aai/SKILL_SHIP.prompt.md"

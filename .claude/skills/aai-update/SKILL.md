---
name: aai-update
description: Use when AAI vendored files need refreshing after upstream changes, or to preview what an update would change in a target project.
---

Read the file `.aai/SKILL_UPDATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-update`.

If `.aai/SKILL_UPDATE.prompt.md` does not exist, say: "SKILL_UPDATE not found — are you in an AAI project? Expected: .aai/SKILL_UPDATE.prompt.md"

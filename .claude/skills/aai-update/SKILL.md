---
name: aai-update
description: Update or resync the AAI layer in a project from the canonical git repository main branch. Use when Claude needs to refresh vendored AAI files after upstream changes, re-sync a target project, or preview what an AAI update would do.
---

Read the file `.aai/SKILL_UPDATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-update`.

If `.aai/SKILL_UPDATE.prompt.md` does not exist, say: "SKILL_UPDATE not found — are you in an AAI project? Expected: .aai/SKILL_UPDATE.prompt.md"

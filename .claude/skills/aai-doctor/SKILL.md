---
name: aai-doctor
description: AAI environment health check. Validates core files, skills, knowledge, STATE.yaml, git status, and dependencies. Reports HEALTHY / DEGRADED / BROKEN with actionable diagnostics.
---

Read the file `.aai/SKILL_DOCTOR.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-doctor`.

If `.aai/SKILL_DOCTOR.prompt.md` does not exist, say: "SKILL_DOCTOR not found — are you in an AAI project? Expected: .aai/SKILL_DOCTOR.prompt.md"

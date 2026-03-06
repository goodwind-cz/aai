---
name: aai-check-state
description: STATE.yaml health check. Validates all invariants (enums, locks, evidence, HITL gate, timestamp). Reports HEALTHY / DEGRADED / BROKEN. Add prefix REPAIR: to auto-fix FAIL invariants.
---

Read the file `.aai/SKILL_CHECK_STATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-check-state`.

If `.aai/SKILL_CHECK_STATE.prompt.md` does not exist, say: "SKILL_CHECK_STATE not found — are you in an AAI project? Expected: .aai/SKILL_CHECK_STATE.prompt.md"

---
name: aai-check-state
description: STATE.yaml health check. Validates all invariants (enums, locks, evidence, HITL gate, timestamp). Reports HEALTHY / DEGRADED / BROKEN. Add prefix REPAIR: to auto-fix FAIL invariants.
---

Read the file `ai/SKILL_CHECK_STATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-check-state`.

If `ai/SKILL_CHECK_STATE.prompt.md` does not exist, say: "SKILL_CHECK_STATE not found — are you in an AI-OS project? Expected: ai/SKILL_CHECK_STATE.prompt.md"

---
name: aai-check-state
description: "Use when STATE.yaml may be invalid, after unexpected loop failures, or before starting a new loop. Add prefix REPAIR: to auto-fix detected invariant violations."
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_CHECK_STATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-check-state`.

If `.aai/SKILL_CHECK_STATE.prompt.md` does not exist, say: "SKILL_CHECK_STATE not found — are you in an AAI project? Expected: .aai/SKILL_CHECK_STATE.prompt.md"

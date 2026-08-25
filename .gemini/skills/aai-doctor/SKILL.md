---
name: aai-doctor
description: Use when the AAI environment may be broken, after a fresh install, or to diagnose unexpected failures. Reports HEALTHY / DEGRADED / BROKEN with actionable diagnostics.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_DOCTOR.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-doctor`.

If `.aai/SKILL_DOCTOR.prompt.md` does not exist, say: "SKILL_DOCTOR not found — are you in an AAI project? Expected: .aai/SKILL_DOCTOR.prompt.md"

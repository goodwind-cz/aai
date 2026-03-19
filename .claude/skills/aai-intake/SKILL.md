---
name: aai-intake
description: Use when starting any new work — feature, bug, change, RFC, hotfix, techdebt, or release. Routes automatically to the correct intake template.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_INTAKE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-intake`.

If `.aai/SKILL_INTAKE.prompt.md` does not exist, say: "SKILL_INTAKE not found — are you in an AAI project? Expected: .aai/SKILL_INTAKE.prompt.md"

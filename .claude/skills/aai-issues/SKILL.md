---
name: aai-issues
description: Use when you want open platform issues fetched, triaged and turned into approved intakes
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_ISSUES.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-issues`.

If `.aai/SKILL_ISSUES.prompt.md` does not exist, say: "SKILL_ISSUES not found — are you in an AAI project? Expected: .aai/SKILL_ISSUES.prompt.md"

---
name: aai-routine
description: On-demand instantiation of a vendored, agent-neutral standing routine (e.g. the morning scryer) for a named harness — never runs from bootstrap, sync, or any automatic path.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_ROUTINE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-routine`.

If `.aai/SKILL_ROUTINE.prompt.md` does not exist, say: "SKILL_ROUTINE not found — are you in an AAI project? Expected: .aai/SKILL_ROUTINE.prompt.md"

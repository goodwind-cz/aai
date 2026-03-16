---
name: aai-loop
description: Use when starting or resuming the full autonomous AAI development loop. Runs Planning → Implementation → Validation → Remediation cycles automatically until PASS or human input is required.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level orchestration initiated by the user.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_LOOP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-loop`.

If `.aai/SKILL_LOOP.prompt.md` does not exist, say: "SKILL_LOOP not found — are you in an AAI project? Expected: .aai/SKILL_LOOP.prompt.md"

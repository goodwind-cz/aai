---
name: aai-wrap-up
description: Session wrap-up ritual. Captures learnings, summarizes accomplishments, proposes LEARNED.md rules, checks uncommitted work, and prepares next session context. Trigger phrases: "wrap up", "end session", "done for today", "hotovo", "konec", "bye".
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. Session wrap-up is an operator-initiated or loop-final action only.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_WRAP_UP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-wrap-up`.

If `.aai/SKILL_WRAP_UP.prompt.md` does not exist, say: "SKILL_WRAP_UP not found — are you in an AAI project? Expected: .aai/SKILL_WRAP_UP.prompt.md"

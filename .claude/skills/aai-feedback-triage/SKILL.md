---
name: aai-feedback-triage
description: Use when you want to report AAI-layer problems/friction upstream to the canonical repo — step 1: offline triage that reads the local friction spool, scores and clusters observations, and writes a LOCAL report (no network, no GitHub writes)
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-feedback-triage`.

If `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` does not exist, say: "SKILL_FEEDBACK_TRIAGE not found — are you in an AAI project? Expected: .aai/SKILL_FEEDBACK_TRIAGE.prompt.md"

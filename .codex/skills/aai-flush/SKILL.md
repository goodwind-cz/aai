---
name: aai-flush
description: Flush completed work item metrics from STATE.yaml to METRICS.jsonl and clean up state. Use when the loop didn't complete the flush or after manual validation.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. Metrics flush is an operator-initiated or loop-final action only.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_FLUSH.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-flush`.

If `.aai/SKILL_FLUSH.prompt.md` does not exist, say: "SKILL_FLUSH not found — are you in an AAI project? Expected: .aai/SKILL_FLUSH.prompt.md"

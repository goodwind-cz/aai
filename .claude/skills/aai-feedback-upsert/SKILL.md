---
name: aai-feedback-upsert
description: Use when you want to report AAI-layer problems upstream — step 2: turns triage clusters into redacted, deduplicated, budget-capped GitHub issue drafts for the canonical repo; prepare-only by default; publishing requires explicit --publish --confirm
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-feedback-upsert`.

If `.aai/SKILL_FEEDBACK_UPSERT.prompt.md` does not exist, say: "SKILL_FEEDBACK_UPSERT not found — are you in an AAI project? Expected: .aai/SKILL_FEEDBACK_UPSERT.prompt.md"

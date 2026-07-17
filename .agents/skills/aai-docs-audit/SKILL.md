---
name: aai-docs-audit
description: Use when docs/ may contain orphan, false-done, false-open (delivered but still draft/implementing/accepted), or stale documents, before a release closeout, for a periodic docs hygiene review, or to verify a doc's acceptance criteria against the actual code ("verify <DOC-ID>"). Reports per-doc classification and drift verdicts; edits docs only in the operator-approved remediation/verify modes.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_DOCS_AUDIT.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-docs-audit`.

If `.aai/SKILL_DOCS_AUDIT.prompt.md` does not exist, say: "SKILL_DOCS_AUDIT not found — are you in an AAI project? Expected: .aai/SKILL_DOCS_AUDIT.prompt.md"

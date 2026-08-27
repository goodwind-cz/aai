---
name: aai-docs-canon
description: Use when layered project docs have no single "current state" view per feature — to consolidate intake/specs/RFCs into a canonical, function-categorized layer in docs/canonical/ while preserving and back-linking originals in docs/_archive/. Two phases — Phase 1 analyzes and proposes an AI domain map gated by human approval; Phase 2 auto-synthesizes canonical docs, archives originals, and reports drift on re-run.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_DOCS_CANON.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-docs-canon`.

If `.aai/SKILL_DOCS_CANON.prompt.md` does not exist, say: "SKILL_DOCS_CANON not found — are you in an AAI project? Expected: .aai/SKILL_DOCS_CANON.prompt.md"

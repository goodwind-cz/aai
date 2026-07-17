---
name: aai-bootstrap
description: Use when setting up a new AAI project or when project-specific test/build/validation commands are missing or outdated. Detects project architecture and generates optimized shortcuts.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. This skill is only for top-level use initiated by the user or orchestrator.
</SUBAGENT-STOP>


Read the file `.aai/SKILL_BOOTSTRAP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-bootstrap`.

If `.aai/SKILL_BOOTSTRAP.prompt.md` does not exist, say: "SKILL_BOOTSTRAP not found — are you in an AAI project? Expected: .aai/SKILL_BOOTSTRAP.prompt.md"

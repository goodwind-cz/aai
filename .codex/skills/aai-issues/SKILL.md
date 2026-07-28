---
name: aai-issues
description: Open platform issue fetch, triage, and approved-intake handoff. Reads gh issue list (or az boards work items), never runs automatically, and writes back to the issue only after its ride's PR merges.
---

Read the file `.aai/SKILL_ISSUES.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-issues`.

If `.aai/SKILL_ISSUES.prompt.md` does not exist, say: "SKILL_ISSUES not found — are you in an AAI project? Expected: .aai/SKILL_ISSUES.prompt.md"

---
name: aai-pr
description: Use when a validated, review-passed scope is ready to become a pull request. Derives the scope file-list from STATE/spec, stages ONLY in-scope paths, audits staged-vs-scope, commits with project conventions, pushes, and opens the PR via gh pr create. Never merges — merging is an operator action.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. PR creation is a gated, operator-confirmed ceremony initiated at top level only.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_PR.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-pr`.

If `.aai/SKILL_PR.prompt.md` does not exist, say: "SKILL_PR not found — are you in an AAI project? Expected: .aai/SKILL_PR.prompt.md"

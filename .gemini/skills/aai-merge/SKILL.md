---
name: aai-merge
description: Use when the owner directs you to merge a named pull request, or when a pull request is already merged and its leftovers (draft copies, base checkout, focus, worktree, branch) need safe cleanup. Runs the open-PR gates and prints the one pinned merge command, or the archive-first idempotent cleanup of a merged PR. Merges only on the owner's explicit invocation for that one PR.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent to execute a specific role (Planning, Implementation, Validation, Remediation), skip this skill. A directed merge is a human-invoked, top-level action only; /aai-ship and the loop never invoke it.
</SUBAGENT-STOP>

Read the file `.aai/SKILL_MERGE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-merge <PR>`.

If `.aai/SKILL_MERGE.prompt.md` does not exist, say: "SKILL_MERGE not found — are you in an AAI project? Expected: .aai/SKILL_MERGE.prompt.md"

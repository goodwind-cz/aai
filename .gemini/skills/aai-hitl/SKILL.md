---
name: aai-hitl
description: Use when the autonomous loop pauses with 'Human decision required'. Surfaces the blocked question from STATE.yaml, collects your answer, and unblocks the loop.
---

Read the file `.aai/SKILL_HITL.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-hitl`.

If `.aai/SKILL_HITL.prompt.md` does not exist, say: "SKILL_HITL not found — are you in an AAI project? Expected: .aai/SKILL_HITL.prompt.md"

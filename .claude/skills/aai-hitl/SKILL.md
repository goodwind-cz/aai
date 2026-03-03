---
name: aai-hitl
description: Human-in-the-loop resolver. Run when the autonomous loop pauses with "Human decision required". Surfaces the blocked question from STATE.yaml, collects your answer, saves a decision artifact, and unblocks the loop.
---

Read the file `.aai/SKILL_HITL.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-hitl`.

If `.aai/SKILL_HITL.prompt.md` does not exist, say: "SKILL_HITL not found — are you in an AI-OS project? Expected: .aai/SKILL_HITL.prompt.md"

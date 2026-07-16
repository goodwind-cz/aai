---
name: aai-interrogate
description: Plan decision-walk — one question at a time, each with a recommended answer; decisions appended to docs/ai/decisions.jsonl — never blocks. Inspired by pro-workflow.
---

Read the file `.aai/SKILL_INTERROGATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-interrogate`.

If `.aai/SKILL_INTERROGATE.prompt.md` does not exist, say: "SKILL_INTERROGATE not found — are you in an AAI project? Expected: .aai/SKILL_INTERROGATE.prompt.md"

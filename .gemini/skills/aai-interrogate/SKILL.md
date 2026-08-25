---
name: aai-interrogate
description: Use optionally at spec freeze (or when a plan feels underdetermined) to walk open decisions one question at a time — every question ships a recommended answer, codebase-resolvable ones are inferred silently, and each decision is appended to docs/ai/decisions.jsonl. Advisory only — never blocks.
---

Read the file `.aai/SKILL_INTERROGATE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-interrogate`.

If `.aai/SKILL_INTERROGATE.prompt.md` does not exist, say: "SKILL_INTERROGATE not found — are you in an AAI project? Expected: .aai/SKILL_INTERROGATE.prompt.md"

---
name: aai-replay
description: Surface relevant past learnings for the current work context. Searches LEARNED.md, PATTERNS.md, FACTS.md, and decisions.jsonl. Shows only what matters for the task at hand.
---

Read the file `.aai/SKILL_REPLAY.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-replay`.

If `.aai/SKILL_REPLAY.prompt.md` does not exist, say: "SKILL_REPLAY not found — are you in an AAI project? Expected: .aai/SKILL_REPLAY.prompt.md"

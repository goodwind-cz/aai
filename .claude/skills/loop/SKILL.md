---
name: loop
description: Run the full autonomous multi-tick AI-OS loop inside this session. Reads STATE.yaml, dispatches roles via subagents tick by tick, stops on PASS / human-input-required / paused / max-ticks.
---

Read the file `ai/SKILL_LOOP.prompt.md` from the current project root and follow its instructions exactly.

If `ai/SKILL_LOOP.prompt.md` does not exist, say: "SKILL_LOOP not found — are you in an AI-OS project? Expected: ai/SKILL_LOOP.prompt.md"

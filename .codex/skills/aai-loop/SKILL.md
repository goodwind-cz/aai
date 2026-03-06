---
name: aai-loop
description: Run the full autonomous multi-tick AAI loop inside this session. Reads STATE.yaml, dispatches roles via subagents tick by tick, stops on PASS / human-input-required / paused / max-ticks.
---

Read the file `.aai/SKILL_LOOP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-loop`.

If `.aai/SKILL_LOOP.prompt.md` does not exist, say: "SKILL_LOOP not found — are you in an AAI project? Expected: .aai/SKILL_LOOP.prompt.md"

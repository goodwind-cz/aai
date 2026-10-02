---
name: aai-roadmap
description: Use when the user wants to see, order or change the project's roadmap (the ordered list of capabilities to build next), set up or switch off the maintenance budget, or harvest roadmap candidates from drafts and friction. Every action is a menu with a recommended default; nothing is hand-edited. Trigger phrases - "roadmap", "what is next", "plan the order", "add to the roadmap".
---

Read the file `.aai/SKILL_ROADMAP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-roadmap` (shows the roadmap and offers a menu) or `/aai-roadmap <action>` where action is one of show, add, reorder, harvest, done, drop, budget, off.

If `.aai/SKILL_ROADMAP.prompt.md` does not exist, say: "SKILL_ROADMAP not found — are you in an AAI project? Expected: .aai/SKILL_ROADMAP.prompt.md"

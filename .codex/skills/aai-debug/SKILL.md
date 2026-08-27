---
name: aai-debug
description: Use when fixing any failing test, bug, or validation finding — applies the systematic-debugging root-cause gate: READ, REPRODUCE, ISOLATE, then FIX-AT-CAUSE. No fixes without root cause.
---

Read the file `.aai/SKILL_DEBUG.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-debug`.

If `.aai/SKILL_DEBUG.prompt.md` does not exist, say: "SKILL_DEBUG not found — are you in an AAI project? Expected: .aai/SKILL_DEBUG.prompt.md"

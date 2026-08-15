---
name: aai-deslop
description: AI-slop removal pass before review — diff scope or --all for .aai/'s scripts and system config, not the whole .aai/ tree; neither is a default, ask-and-stop if the scope is not named; behavior unchanged (suite must pass after) — never blocks. Inspired by pro-workflow.
---

Read the file `.aai/SKILL_DESLOP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-deslop`.

If `.aai/SKILL_DESLOP.prompt.md` does not exist, say: "SKILL_DESLOP not found — are you in an AAI project? Expected: .aai/SKILL_DESLOP.prompt.md"

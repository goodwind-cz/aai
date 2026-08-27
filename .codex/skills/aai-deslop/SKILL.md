---
name: aai-deslop
description: Use optionally after implementation and before code review to remove AI slop — diff scope covers the current diff; --all scope runs the class-4 unrequested-surface check over .aai/'s scripts and system config, not the whole .aai/ tree; neither is a default, ask-and-stop if the scope is not named. Classes: obvious comments, defensive try/catch on trusted paths, premature abstraction, unrequested features, annotations on untouched code. Behavior must stay unchanged (suite passes after). Advisory only — never blocks.
---

Read the file `.aai/SKILL_DESLOP.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-deslop`.

If `.aai/SKILL_DESLOP.prompt.md` does not exist, say: "SKILL_DESLOP not found — are you in an AAI project? Expected: .aai/SKILL_DESLOP.prompt.md"

---
name: aai-auto-trigger
description: DEPRECATED — the .Codex/triggers.json mechanism this skill configured has no runtime consumer, so triggers wired there never fire (SPEC-0013 D8). Kept for muscle memory; invoking it explains the deprecation and the real alternative (wrapper-description trigger phrases).
---

Read the file `.aai/SKILL_AUTO_TRIGGER.prompt.md` from the current project root and follow its instructions exactly — it is a deprecation notice: explain it to the user and do NOT create or edit `.Codex/triggers.json`. Invoke this as `/aai-auto-trigger`.

If `.aai/SKILL_AUTO_TRIGGER.prompt.md` does not exist, say: "SKILL_AUTO_TRIGGER not found — are you in an AAI project? Expected: .aai/SKILL_AUTO_TRIGGER.prompt.md"

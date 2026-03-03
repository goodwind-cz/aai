---
name: aai-intake
description: Universal intake router. Detects work type from a description (feature, bug, change, research, RFC, hotfix, techdebt, release) and runs the correct INTAKE_*.prompt.md. Accepts input in any language.
---

Read the file `.aai/SKILL_INTAKE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-intake`.

If `.aai/SKILL_INTAKE.prompt.md` does not exist, say: "SKILL_INTAKE not found — are you in an AI-OS project? Expected: .aai/SKILL_INTAKE.prompt.md"

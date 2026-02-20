---
name: intake
description: Universal intake router. Detects work type from a description (feature, bug, change, research, RFC, hotfix, techdebt, release) and runs the correct INTAKE_*.prompt.md. Accepts input in any language.
---

Read the file `ai/SKILL_INTAKE.prompt.md` from the current project root and follow its instructions exactly.

If `ai/SKILL_INTAKE.prompt.md` does not exist, say: "SKILL_INTAKE not found — are you in an AI-OS project? Expected: ai/SKILL_INTAKE.prompt.md"

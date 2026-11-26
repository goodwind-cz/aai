---
name: aai-test-skills
description: Use when verifying all AAI skills work correctly after upstream changes, a fresh install, or to diagnose skill failures. Run by reading .aai/SKILL_TEST_SKILLS.prompt.md first.
---

Read the file `.aai/SKILL_TEST_SKILLS.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-test-skills`.

If `.aai/SKILL_TEST_SKILLS.prompt.md` does not exist, say: "SKILL_TEST_SKILLS not found — are you in an AAI project? Expected: .aai/SKILL_TEST_SKILLS.prompt.md"

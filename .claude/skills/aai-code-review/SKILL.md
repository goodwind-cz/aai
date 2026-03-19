---
name: aai-code-review
description: Use when reviewing committed or staged code changes for security, performance, and style issues. Supports git diffs and GitHub PR review with structured severity comments.
---

Read the file `.aai/SKILL_CODE_REVIEW.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-code-review`.

If `.aai/SKILL_CODE_REVIEW.prompt.md` does not exist, say: "SKILL_CODE_REVIEW not found — are you in an AAI project? Expected: .aai/SKILL_CODE_REVIEW.prompt.md"

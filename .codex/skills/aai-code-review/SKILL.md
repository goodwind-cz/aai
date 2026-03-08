---
name: aai-code-review
description: Automated code review for git diffs and GitHub PRs. Checks security, performance, style issues with severity levels. Can post structured review comments to GitHub PRs.
---

Read the file `.aai/SKILL_CODE_REVIEW.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-code-review`.

If `.aai/SKILL_CODE_REVIEW.prompt.md` does not exist, say: "SKILL_CODE_REVIEW not found — are you in an AAI project? Expected: .aai/SKILL_CODE_REVIEW.prompt.md"

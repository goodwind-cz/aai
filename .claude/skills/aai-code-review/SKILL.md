---
name: aai-code-review
description: Use when reviewing committed or staged code changes. One dual-verdict pass returning spec_compliance (AC-table walk) and code_quality (BLOCKING/NON-BLOCKING findings) plus a mandatory cannot_verify list. Supports git diffs and GitHub PR review.
---

Read the file `.aai/SKILL_CODE_REVIEW.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-code-review`.

If `.aai/SKILL_CODE_REVIEW.prompt.md` does not exist, say: "SKILL_CODE_REVIEW not found — are you in an AAI project? Expected: .aai/SKILL_CODE_REVIEW.prompt.md"

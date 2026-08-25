---
name: aai-release
description: Use when a validated scope is ready to ship a release — rolls CHANGELOG.md [unreleased] into a versioned section, commits, tags, publishes a GitHub release, and pushes, behind an operator-gated confirm with a safe default dry-run.
---

Read the file `.aai/SKILL_RELEASE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-release`.

If `.aai/SKILL_RELEASE.prompt.md` does not exist, say: "SKILL_RELEASE not found — are you in an AAI project? Expected: .aai/SKILL_RELEASE.prompt.md"

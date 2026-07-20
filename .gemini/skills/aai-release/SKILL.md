---
name: aai-release
description: Cut a release — roll CHANGELOG.md [unreleased] into a versioned section, commit, tag, publish a GitHub release, and push. Use when Gemini needs to cut or preview a release for the current project. Operator-gated confirm with a safe default dry-run.
---

Read the file `.aai/SKILL_RELEASE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-release`.

If `.aai/SKILL_RELEASE.prompt.md` does not exist, say: "SKILL_RELEASE not found — are you in an AAI project? Expected: .aai/SKILL_RELEASE.prompt.md"

---
name: aai-canonicalize
description: Use when legacy files exist in unsupported directories, telemetry is still in YAML, or validation evidence is fragmented. Canonicalizes AAI repository structure.
---

Read the file `.aai/SKILL_CANONICALIZE.prompt.md` from the current project root and follow its instructions exactly. Invoke this as `/aai-canonicalize`.

If `.aai/SKILL_CANONICALIZE.prompt.md` does not exist, say: "SKILL_CANONICALIZE not found — are you in an AAI project? Expected: .aai/SKILL_CANONICALIZE.prompt.md"

---
name: aai-flush
description: Use when the loop exited without flushing metrics, or after manual validation, to move completed work item data from STATE.yaml to METRICS.jsonl.
---

Read the file `.aai/SKILL_FLUSH.prompt.md` from the current project root and follow its instructions exactly.

If `.aai/SKILL_FLUSH.prompt.md` does not exist, say: "SKILL_FLUSH not found — are you in an AAI project? Expected: .aai/SKILL_FLUSH.prompt.md"

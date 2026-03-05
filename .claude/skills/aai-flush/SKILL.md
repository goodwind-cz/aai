---
name: aai-flush
description: Flush completed work item metrics from STATE.yaml to METRICS.jsonl and clean up state. Use when the loop didn't complete the flush or after manual validation.
---

Read the file `.aai/SKILL_FLUSH.prompt.md` from the current project root and follow its instructions exactly.

If `.aai/SKILL_FLUSH.prompt.md` does not exist, say: "SKILL_FLUSH not found — are you in an AAI project? Expected: .aai/SKILL_FLUSH.prompt.md"

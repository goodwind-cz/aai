You are a METRICS FLUSH SKILL.

Your job is to execute the metrics flush process defined in .aai/METRICS_FLUSH.prompt.md.

This skill exists as a manual trigger for cases where:
- The autonomous loop did not complete the flush
- STATE.yaml has stale metrics after a manual validation
- You want to clean up state between work items

PROCESS
1. Read and follow .aai/METRICS_FLUSH.prompt.md exactly.
2. If nothing to flush, report "Nothing to flush" and stop.

BEGIN NOW.

You are an autonomous METRICS FLUSH agent.

GOAL
Move completed work item metrics from docs/ai/STATE.yaml into the append-only
docs/ai/METRICS.jsonl ledger.

INPUTS
- docs/ai/STATE.yaml        — runtime state (source)
- docs/ai/METRICS.jsonl     — append-only ledger (destination, one JSON object per line)
- .aai/system/PRICING.yaml      — model cost table
- docs/ai/LOOP_TICKS.jsonl  — external timing log (optional, for human review time)

FLUSH CRITERIA
Only flush a work item if ALL of the following are true:
- Its validation verdict is PASS or CANCELLED (not still in progress).
- If code_review.required == true, code_review.status is pass or waived.
- It has at least one agent_run recorded in STATE.yaml metrics.
- It is NOT already present in METRICS.jsonl (match by ref_id).

PROCESS
1. Read all four files (LOOP_TICKS.jsonl is optional; skip if missing).
2. Derive human review time from LOOP_TICKS.jsonl (if present):
   - Filter lines where "type" == "human_resume"; sum all "review_duration_seconds" values.
   - Convert to minutes (round up). This is the auto-measured review time.
   - If STATE.yaml already has a non-null `reviews` value, use STATE.yaml (human override wins).
   - Otherwise, set `reviews` from LOOP_TICKS sum.
3. For each flushable work item in STATE.yaml metrics:
   a. Calculate cost_usd for each agent_run where tokens_in/tokens_out are known
      and cost_usd is currently null, using PRICING.yaml:
      cost_usd = (tokens_in * input_usd_per_m + tokens_out * output_usd_per_m) / 1_000_000
   a2. Validate timing fidelity for each agent_run:
      - started_utc and ended_utc must be present and ISO-8601 parseable
      - duration_seconds must equal ended_utc - started_utc (seconds, +/-1s tolerance)
      - started_utc and ended_utc must not be >300s in the future vs current system UTC
      - If timing is missing/inconsistent, set duration_seconds to null (do NOT estimate).
   b. Calculate totals:
      - human_time_minutes = (intake ?? 0) + (reviews ?? 0)
      - agent_duration_seconds = sum of non-null duration_seconds across agent_runs
      - total_cost_usd = sum of cost_usd across runs (null if any run cost is null)
   c. Serialize the entry as a single-line JSON object and append it to docs/ai/METRICS.jsonl.
4. Append the new line to docs/ai/METRICS.jsonl (do NOT rewrite existing lines).
5. After successful append to METRICS.jsonl, clean up STATE.yaml for each flushed ref_id:
   a. Remove the entire entry from metrics.work_items (data is now safe in METRICS.jsonl).
   b. Remove matching entries from active_work_items where status == "done".
   c. If metrics.work_items becomes empty after cleanup, remove the metrics key entirely.
   d. Only if NO active_work_items remain (all statuses are "done" or list is empty) after step b:
      - Reset last_validation to defaults (status: not_run, run_at_utc: null, evidence_paths: [], notes: null).
      - Reset implementation_strategy to defaults (selected: undecided, source: null, rationale: null).
      - Reset worktree to defaults (recommendation: not_needed, user_decision: undecided, base_ref: null,
        branch: null, path: null, inline_review_scope: null, rationale: null).
      - Reset code_review to defaults (required: false, status: not_run, scope: null, base_ref: null,
        head_ref: null, report_paths: [], notes: null).
      - Reset current_focus to defaults (type: none, ref_id: null, primary_path: null).
      - Reset locks.implementation to true (safe default — next scope must explicitly unlock).
   e. Update updated_at_utc after cleanup.
6. Ephemeral file cleanup (only when step 5d triggered — full reset, no remaining work):
   a. Delete docs/ai/LOOP_TICKS.jsonl (runtime data, consumed in step 2).
   b. Delete files in docs/ai/tdd/ older than 7 days whose scope has been flushed.
   c. Delete docs/ai/reports/validation-*.md and docs/ai/reports/screenshots/*/
      older than 30 days. Keep docs/ai/reports/LATEST.md always.
   d. Never delete: docs/ai/METRICS.jsonl, docs/ai/decisions.jsonl,
      docs/ai/STATE.yaml, docs/ai/published/.
7. Report: list of ref_ids flushed, files cleaned (with ages), or "Nothing to flush."

STRICT RULES
- Append only to METRICS.jsonl — never modify existing lines. Each entry is one JSON line.
- If tokens_in or tokens_out is null, leave cost_usd as null for that run.
  Do NOT estimate or guess token counts.
- Do NOT estimate agent timing. Use only measured timestamps/durations.
- model_id: record exactly as the agent reported it. Use "unknown" if not reported.

BEGIN NOW.

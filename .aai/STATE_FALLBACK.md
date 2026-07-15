# STATE.yaml hand-edit fallback (single source — CHANGE-0011)

This file's hand-edit procedures apply when `.aai/scripts/state.mjs` is absent
(an older vendored AAI layer) or fails. Some prompts also reference specific
sections here on their primary path (e.g. METRICS_FLUSH whole-block removals,
check-state WRITER RULE) — follow those references regardless of CLI presence.
On the primary path every other STATE write goes through the
transactional CLI (`node .aai/scripts/state.mjs <command>`), which validates
enums, writes atomically, self-stamps timestamps, and bumps `updated_at_utc`.
When the CLI is absent, edit docs/ai/STATE.yaml by hand per the field lists
below, then ALWAYS validate:

  node .aai/scripts/check-state.mjs docs/ai/STATE.yaml

## Legacy field list (hand-edit surface per write kind)

Edit only the fields your role's primary-path command would have written, plus
`updated_at_utc` (ISO 8601 UTC) on every edit:

- focus (`set-focus`): current_focus.type / ref_id / primary_path
- phase (`set-phase`): active_work_items entry phase/status (create the entry
  for the scope if missing); spec_path where the command took --spec-path
- strategy (`set-strategy`): implementation_strategy.selected / source / rationale
- worktree (`set-worktree`): worktree.recommendation / user_decision / base_ref /
  branch / path / inline_review_scope / rationale
- code review (`set-code-review`): code_review.required / status / scope /
  base_ref / head_ref / report_paths / notes
- validation (`set-validation`): last_validation.status / run_at_utc /
  evidence_paths / notes (real measured run_at_utc only)
- human input (`set-human-input`): human_input.required / question (question_ref) /
  blocking_reason
- TDD cycle (`set-tdd-cycle`): tdd_cycle.status / test_id / spec_path /
  test_path / evidence.red / evidence.green / evidence.refactor
  (REFACTOR_COMPLETE may add refactoring_summary; `--status IDLE` equivalent:
  status IDLE and all other fields null)
- remediation reset (`reset-block`): set ONLY the failed block's `status:` from
  `fail` to `not_run`; leave run_at_utc/evidence_paths/report_paths as audit
  history; touch nothing else
- flush resets (METRICS_FLUSH step 5d — apply ALL by hand):
  - last_validation → status: not_run, run_at_utc: null, evidence_paths: [], notes: null
  - implementation_strategy → selected: undecided, source: null, rationale: null
  - worktree → recommendation: not_needed, user_decision: undecided, base_ref: null,
    branch: null, path: null, inline_review_scope: null, rationale: null
  - code_review → required: false, status: not_run, scope: null, base_ref: null,
    head_ref: null, report_paths: [], notes: null
  - current_focus → type: none, ref_id: null, primary_path: null
  - locks.implementation → true (safe default — next scope must explicitly unlock)
  (partial flush, step d2: only the last_validation and code_review resets above)

## agent_runs hand-append (all roles' `append-run` fallback)

Append under metrics.work_items[<ref_id>].agent_runs (auto-create the work_items
entry with `human_time_minutes: {intake: null, reviews: null}` and
`agent_runs: []` if missing):

  role:             <Planning | Implementation | Validation | Remediation | TDD | ...>
  model_id:         <your model identifier, e.g. claude-sonnet-4-5, gemini-2.0-flash>
  started_utc:      <ISO 8601 UTC, real measured start>
  ended_utc:        <ISO 8601 UTC, real measured end>
  duration_seconds: <integer, ended_utc - started_utc>
  tokens_in:        <integer if your platform exposes it, otherwise null>
  tokens_out:       <integer if your platform exposes it, otherwise null>
  cost_usd:         null
  tdd_tests:        <count of TEST-xxx completed — TDD runs only>

Do NOT estimate any timing or token values. Only record measured/platform values.

## Tick-line hand-append (SKILL_LOOP `log-tick` fallback)

Append one `type: tick` (or `type: recovery`) JSON line to
docs/ai/LOOP_TICKS.jsonl with:
  tick, started_utc, ended_utc, duration_seconds, exit_code,
  focus_ref_id_before, focus_ref_id_after, validation_status_before,
  validation_status_after, harness_version.
Optional, ONLY with real runtime usage: input_tokens, output_tokens,
cache_read_tokens, est_cost_usd. On test-running ticks also lingering_procs and
free_memory (SPEC-0009). Never fabricate or estimate; use system-clock
timestamps only.

## STATE-WRITE SAFETY (ISSUE-0004 / INV-14)

Primary path: `node .aai/scripts/state.mjs append-run ...` appends under the
single top-level `metrics:` key by construction (it refuses to write a
duplicate-key file). On the hand-edit path:
When appending your agent_runs entry, append into the EXISTING
metrics.work_items.<ref_id>.agent_runs list under the single top-level
`metrics:` key; never emit a second top-level `metrics:` key.
A duplicate top-level `metrics:` silently drops the first block's work_items
and agent_runs on a lenient YAML load (ISSUE-0004). After editing, validate:

  node .aai/scripts/check-state.mjs docs/ai/STATE.yaml

REPAIR merges a duplicate `metrics:` with zero data loss:

  node .aai/scripts/check-state.mjs --repair docs/ai/STATE.yaml

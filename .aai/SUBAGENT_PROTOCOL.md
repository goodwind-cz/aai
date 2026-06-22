# Subagent Protocol

This document defines the contract for spawning, running, and merging subagent work.
All agents that support parallelism MUST follow this protocol.

## When to decompose

An agent MAY spawn subagents when:
- Work items are independent (no shared mutable state between units)
- Parallelism reduces wall-clock time meaningfully (≥3 independent units)
- Each unit can produce a self-contained, verifiable output

An agent MUST NOT spawn subagents when:
- Units share mutable state or depend on each other's output
- The platform does not support concurrent task execution (fall back to sequential)
- The scope is already at minimum granularity (single file/single requirement)

## Subagent call contract

Each subagent call MUST specify all of the following:

| Field | Description |
|---|---|
| `ROLE` | Implementation \| Validation \| Planning \| Research |
| `SCOPE` | Single file / module / requirement group — never overlapping with other subagents |
| `INPUT` | All context the subagent needs — do NOT rely on inherited ambient state |
| `EXPECTED_OUTPUT` | A result block (see below) |
| `SYSTEM_PROMPT` | The canonical role prompt from `ai/<ROLE>.prompt.md` |

## Spawning a validator in a separate agent

The Validation role must run in an agent that did NOT produce the implementation
(maker≠checker is contextual). The mechanism depends on the host, but the contract
is identical everywhere: a NEW agent receives `SYSTEM_PROMPT = .aai/VALIDATION.prompt.md`
and `INPUT = { requirement/spec path, implementation diff or changed paths, evidence
paths, docs/ai/STATE.yaml }` — and NOT the implementer's conversation/working context.
Prefer a model different from the implementer's.

- **In-session agentic harness (e.g. Claude Code):** call the host's agent/task
  tool to spawn a subagent. Pass the validation prompt + INPUT as the task, and set
  the per-subagent model override to a model other than the implementer's. The
  subagent runs in its own fresh context by construction and returns the result
  block below. The parent loop only merges the verdict — it does not re-judge.
- **Other in-session hosts (Codex, Gemini, …):** use that host's subagent/task
  primitive with the same INPUT contract and a distinct model where available.
- **Headless / CLI runner:** run validation as a SEPARATE process — ideally a
  different binary or model than the build step — e.g.
  `claude -p --prompt-file .aai/VALIDATION.prompt.md` (or `codex`/`gemini`
  equivalent) executed against the same repo. A fresh process is a fresh context.
- **No subagent/process isolation available (fallback):** clear/reset context, then
  run validation re-reading ONLY the artifacts above. Record "validator shared
  context with implementer" as a residual risk that lowers confidence in the PASS.

## Result block (mandatory subagent output)

Every subagent MUST return a result block in this exact YAML format:

```yaml
subagent_result:
  scope: <scope id or path>
  role: <Implementation | Validation | Planning | Research>
  status: PASS | FAIL | BLOCKED
  started_utc: <ISO 8601 UTC captured from system clock>
  ended_utc: <ISO 8601 UTC captured from system clock>
  duration_seconds: <integer = ended_utc - started_utc>
  evidence:
    - command: <shell command or verification step>
      exit_code: <int>
      output_snippet: <first 200 chars of relevant output>
  files_changed:
    - <relative path>
  blockers:
    - <description of any blocker; empty list if none>
```

Timing capture rules:
- Capture `started_utc` and `ended_utc` from the runtime system clock (`date -u` / `Get-Date ...ToUniversalTime()`), never from model estimation.
- Use UTC ISO-8601 with explicit `Z` or `+00:00`.
- `duration_seconds` MUST match `ended_utc - started_utc` (tolerance +/-1s).

## Merge protocol (orchestrator responsibility)

After all subagents complete, the orchestrator MUST:

1. Collect ALL subagent result blocks — do not proceed with a partial set.
2. Evaluate overall status:
   - `PASS` only if every subagent returned `PASS`
   - `FAIL` if any subagent returned `FAIL` — trigger Remediation for that scope only
   - `BLOCKED` if any subagent returned `BLOCKED` — set `human_input.required: true` in STATE.yaml
   - `BLOCKED` if any subagent timing is invalid:
     missing/unparseable timestamps, duration mismatch, or timestamp > 300 seconds in the future vs orchestrator system UTC.
3. Write merged summary to `docs/ai/STATE.yaml`:
   - `last_validation.status` (or equivalent phase field)
   - `last_validation.evidence_paths`
   - `active_work_items` updated for each affected scope
   - `metrics.work_items[ref_id].agent_runs` with measured timing fields from accepted subagent results
   - `updated_at_utc`
4. Only after STATE.yaml is updated: proceed to deliver result to user.

## Delivery gate (mandatory)

DO NOT report completion to the user until ALL of the following are true:
- All subagent result blocks collected
- Merge protocol applied
- `docs/ai/STATE.yaml` updated with merged evidence
- Overall verdict is explicit (PASS / FAIL / BLOCKED)

Partial or optimistic reporting ("looks like it worked") is prohibited.

## Platform fallback

If the runtime platform does not support concurrent subagent spawning:
- Execute units sequentially in priority order (FAIL > VALIDATION > IMPLEMENTATION > PLANNING)
- Apply the same result block format and merge protocol
- Do not skip the delivery gate

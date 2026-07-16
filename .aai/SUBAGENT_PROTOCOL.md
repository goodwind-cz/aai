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
| `MODEL` | REQUIRED (CHANGE-0010 D1) — an explicit model id (preferred, e.g. `claude-haiku-4-5`) or a tier (`mechanical \| standard \| premium`) when the platform maps tiers itself. Right-size per the MODEL SELECTION tiering in the orchestration prompts. For a Validation dispatch it MUST differ from the implementer's recorded model (see "Spawning a validator" below) |
| `INPUT` | All context the subagent needs — do NOT rely on inherited ambient state |
| `EXPECTED_OUTPUT` | A result block (see below) |
| `SYSTEM_PROMPT` | The canonical role prompt from `ai/<ROLE>.prompt.md` |

### Work-item brief handoff (default INPUT)

When Planning has emitted a brief at `docs/ai/briefs/<ref>.md` (from
`.aai/templates/BRIEF_TEMPLATE.md`, PLANNING step 11), the dispatch `INPUT`
DEFAULTS to the brief path plus the diff scope — the brief is self-contained
(scope & why, AC ↔ task map, canon POINTERS, evidence contract), so the
subagent does not re-read the full spec + canon cold. Degrade clause: when no
brief exists for the ref, fall back to the spec path + requirement/intake
paths as before — never block a dispatch on a missing brief. The brief's
Return Record section is the "Result block (mandatory subagent output)" below,
verbatim (single source: that section wins on any divergence); the subagent
fills it instead of inventing its own report format. Briefs are gitignored
runtime artifacts — cite them in dispatches, never commit them.

## Review dispatch anti-gaming rules (RFC single-dual-verdict-review)

These rules bind every Code Review dispatch at the same tier as the `MODEL`
field above. They exist so the orchestrator — who wrote or merged the code
under review — cannot steer the verdicts it is buying.

1. **No coaching.** The dispatching orchestrator
   MUST NOT characterize expected findings,
   MUST NOT pre-rate severity, and
   MUST NOT scope-exclude areas for the reviewer ("skip the tests", "the
   config change is trivial").
   The dispatch names the scope and the spec; the reviewer decides
   what it finds and how severe it is. A reviewer that detects coaching in
   its dispatch prompt records the attempt in the report and reviews the
   full scope anyway.
2. **Reviewer context is read-only on implementation files.** The review
   subagent reads code, specs, tests, and STATE, and writes ONLY its report
   under `docs/ai/reviews/` (STATE `code_review` updates follow the
   single-writer rule below — the orchestrator merges the verdict, or the
   reviewer records it via `state.mjs set-code-review` when it is the sole
   agent). A reviewer never edits the code it reviews.
3. **Diff handoff by ref/path list, never pasted inline.** The dispatch
   passes base/head refs, a PR number, or an explicit path list; the
   reviewer runs the git/gh commands itself. Pasting diff hunks into the
   dispatch prompt invites pre-filtering (the orchestrator choosing what the
   reviewer gets to see) and bloats the expensive context.

## Spawning a validator in a separate agent

The Validation role must run in an agent that did NOT produce the implementation
(maker≠checker is contextual). The mechanism depends on the host, but the contract
is identical everywhere: a NEW agent receives `SYSTEM_PROMPT = .aai/VALIDATION.prompt.md`
and `INPUT = { requirement/spec path, implementation diff or changed paths, evidence
paths, docs/ai/STATE.yaml }` — and NOT the implementer's conversation/working context.

Validator model rule (CHANGE-0010 D1): the dispatch MUST record the validator
model (the `MODEL` contract field), and it MUST differ from the implementer's
recorded model — the `model_id` of the last Implementation/TDD Implementation
run in `metrics.work_items[<ref>].agent_runs` — whenever the platform supports
model selection. A context-window variant (`claude-opus-4-8[1m]`) is the SAME
model as its base id: same weights, same blind spots. Single-model environments
record the reuse as a residual risk on the verdict. The mechanical backstop is
`state.mjs set-validation --model <validator-model>` (warns by default; refuses
the write under `independence: enforce` in docs/ai/docs-audit.yaml).

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

## Single-writer rule (HARD — RFC-0004 / SPEC-0004 D7)

A dispatched subagent **MUST NOT write `docs/ai/STATE.yaml`**. The orchestrator
is the **SOLE STATE writer**. A subagent returns its result block (below) and
nothing more; the orchestrator merges that block and performs every mutation of
`docs/ai/STATE.yaml` through the merge protocol. This closes the lost-update race
that occurs the moment K >= 2 subagents touch `STATE.yaml` directly.

What a subagent MAY write: its own scoped source/test files, append-only evidence
under `docs/ai/tdd/`, and `docs/ai/EVENTS.jsonl` via `append-event.mjs` (the
append-only, commutative audit log). What it MUST NOT write: `docs/ai/STATE.yaml`
(orchestrator-only). The orchestrator additionally serializes scope ownership with
the atomic lock CLI `.aai/scripts/docs-lock.mjs` (acquire before dispatch, release
after merge) so two orchestrators cannot drive the same scope concurrently.

Honesty note: this is a protocol rule binding an LLM subagent, so it is partly
process, not a hard runtime guard. The mechanically enforced core is (a) the
`docs-lock.mjs` acquire/release exit-code contract the orchestrator branches on
and (b) the merge protocol. A runtime `git diff`-based STATE-mutation guard is a
recommended follow-up (residual risk R-GUARD), not yet built.

### Single-writer rationalization table (stop and correct any of these)

| Rationalization                                          | Reality                                                                 |
|---------------------------------------------------------|-------------------------------------------------------------------------|
| "My update to STATE.yaml is tiny, I'll just write it"   | Subagents MUST NOT write `docs/ai/STATE.yaml`. Return a result block; the orchestrator is the sole writer. |
| "I'll write STATE so the orchestrator doesn't have to"  | Direct subagent STATE writes race and lose updates at K >= 2. That is exactly the bug this rule removes. |
| "I acquired nothing, the scope was obviously free"      | Always `docs-lock acquire <scope> <owner>` before working a scope; a free-looking scope can be claimed concurrently. |
| "I'm done, I'll leave the lock for cleanup/TTL"         | Release explicitly after merge (`docs-lock release <scope> <owner>`); TTL reclaim is a crash safety net, not the normal path. |

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

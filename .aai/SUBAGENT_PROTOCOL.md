# Subagent Protocol

This document defines the contract for spawning, running, and merging subagent work.
All agents that support parallelism MUST follow this protocol.

`.aai/SUBAGENT_CONTRACT.md` is the per-dispatch payload — the ~60-line duty
sheet (result block, timing, single-writer core) every spawned subagent
actually receives. This document is the ORCHESTRATOR-side material: read it
if you are the dispatching side, not a dispatched unit.

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
| `EXPECTED_OUTPUT` | A result block (see `.aai/SUBAGENT_CONTRACT.md`) |
| `SYSTEM_PROMPT` | The canonical role prompt from `ai/<ROLE>.prompt.md` |
| `ENV` | The subagent MUST run with `AAI_ROLE=subagent` exported in its environment/instructions (R-GUARD S1, SPEC-0113). This makes any `state.mjs` STATE mutation it attempts refuse with exit 3 — the single-writer rule enforced at the CLI chokepoint, not merely in prose. The orchestrator MUST NOT carry this marker for its OWN STATE writes: keep it unset (or set to a non-`subagent` value) in orchestrator context, or the merge writes are blocked. `log-tick` (LOOP_TICKS) and `append-event.mjs` (EVENTS.jsonl) stay allowed under the marker. HONESTY: this is a guardrail against the honest/accidental subagent write, NOT a security boundary — an agent that unsets the marker defeats it; the flush-time forensic check (metrics-flush.mjs S2) is the after-the-fact backstop. |

### Work-item brief handoff (default INPUT)

When Planning has emitted a brief at `docs/ai/briefs/<ref>.md` (from
`.aai/templates/BRIEF_TEMPLATE.md`, PLANNING step 11), the dispatch `INPUT`
DEFAULTS to the brief path plus the diff scope — the brief is self-contained
(scope & why, AC ↔ task map, canon POINTERS, evidence contract), so the
subagent does not re-read the full spec + canon cold. Degrade clause: when no
brief exists for the ref, fall back to the spec path + requirement/intake
paths as before — never block a dispatch on a missing brief. The brief's
Return Record section is `.aai/SUBAGENT_CONTRACT.md`'s "Result block (mandatory
subagent output)" section, verbatim (single source: that section wins on any
divergence); the subagent fills it instead of inventing its own report format.
Briefs are gitignored runtime artifacts — cite them in dispatches, never
commit them.

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

## Capability detection (runtime, never a harness table)

Before spawning ANY subagent (a validator above all), the orchestrating agent
resolves four capability fields from the ACTUAL host, at runtime — never from
a table that keys behavior on a literal harness-name string (Claude, Codex,
Gemini):

| Field | Meaning |
|---|---|
| `multi_agent_backend` | which subagent backend the current host exposes (e.g. MultiAgentV1, MultiAgentV2, none) |
| `spawn_agent_available` | whether a native `spawn_agent(task_name, message, fork_turns, model, reasoning_effort)` primitive is callable in THIS session |
| `spawn_model_catalog` | the models the subagent backend can actually grant (can be narrower than the top-level model catalog) |
| `fork_turns_supported` | whether `fork_turns="none"` (a child spawned with no surrounding parent context) is honored by this backend |

Resolution rules: resolve all four fields AT RUNTIME before the ride's first
dispatch — never assumed from a prior ride, a harness name, or a version
string; they are re-resolved when a spawn call is refused (a rejected model,
a refused `fork_turns`, a hard spawn failure — the catalog and backend can
change mid-session); an UNKNOWN capability fails closed to the NEXT
isolation tier below, never assumed present. Isolation tier selection below
is keyed on these DETECTED capabilities, not on harness name equality.

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

Isolation tiers, resolved from the detected capabilities above, IN ORDER —
attempt tier 1 first, fall through only when the tier's own precondition is
absent or its spawn attempt is refused:

1. **Native `spawn_agent`, different model, `fork_turns="none"`** — when
   `spawn_agent_available` is true AND `fork_turns_supported` is true: call
   the host's native `spawn_agent` with `fork_turns="none"` (the child
   receives NO surrounding parent context) and `model` set to an id other
   than the implementer's recorded model. The subagent runs in its own
   fresh context by construction and returns the result block
   (`.aai/SUBAGENT_CONTRACT.md`); the parent loop only merges the verdict,
   it does not re-judge. `fork_turns_supported` false or unknown means a
   spawned child may inherit the parent's context, so tier 1 does not apply
   — fall to tier 3.
2. **`spawn_agent` retried against an available `spawn_model_catalog`
   model** — when tier 1's requested model is REJECTED (the subagent
   backend's model catalog is narrower than the top level, or an explicit
   override is silently dropped, CLI ~0.145.0 history): retry `spawn_agent`
   with a model actually present in the detected `spawn_model_catalog`,
   still distinct from the implementer's model where the catalog offers one.
3. **Separate role-per-invocation process, hard isolation** — when no
   `spawn_agent` primitive is available (`spawn_agent_available` false or
   unknown), OR when `fork_turns_supported` is false or unknown (tier 1 does
   not apply per its own precondition, and tier 2 only covers a rejected
   model, not an unsupported fork_turns): run validation as a SEPARATE
   process, e.g. `claude -p --prompt-file .aai/VALIDATION.prompt.md` or
   `codex exec -m <model>` (or the host-equivalent headless invocation)
   against the same repo — a fresh process is a fresh context by
   construction.
4. **In-parent-session execution, LAST RESORT** — only when tiers 1-3 are
   all unavailable: clear/reset context, then run validation re-reading
   ONLY the artifacts above. Record "validator shared context with
   implementer" as a residual risk that lowers confidence in the PASS; this
   tier is the fallback of last resort, never the first choice.

Whichever tier fires, the orchestrator MUST VERIFY the granted model from the
subagent's own returned/observed identity — never assume a requested
override took. A silently-dropped override is detectable after the fact via
the `requested_model=`/`actual_model=` note markers below; a validator that
ends up sharing the implementer's model, whether via tier-4 fallback or a
dropped override, is a residual risk to record, not a silent pass.

## Harness-reported usage capture

Token usage is captured ONLY from the harness-level result visible to the dispatching parent (Agent-tool completion, headless `--output-format json`, etc.) — never from a subagent's own self-report (D1); a subagent cannot observe its own usage, so any figure it produced would be fabricated.

- Decomposed shape (`usage.input_tokens`/`usage.output_tokens`/
  `usage.cache_read_input_tokens`, `total_cost_usd`): pass values through the
  existing flags — `append-run --tokens-in N --tokens-out N`; `log-tick --tokens-in N --tokens-out N [--cache-read N] [--cost X]` (`--cost` only
  when the runtime itself reports a real cost figure) (D2).
- Undecomposed total (a single combined count, e.g. the in-session Agent
  tool's completion total, no in/out split): record it VERBATIM in
  `append-run --note` using the fixed grammar `usage_total_tokens=<N>`
  (recommended full form: `usage_total_tokens=<N> (harness total; in/out not
  exposed)`). This `usage_total_tokens=<N>` note is MANDATORY whenever a
  harness total is visible — see "Merge protocol" below; it must never be
  treated as optional, so "no usage signal" can only mean the harness
  exposed nothing. Numeric token flags are OMITTED. NEVER split a total into
  in/out components, and NEVER relabel it as `tokens_out`/`tokens_in` —
  input and output prices differ, so a mislabeled total would poison
  `cost_usd`. The flush now classifies this as undecomposed-note and emits an INFO line, not the capture-missing WARNING — cost stays unattributable by design (D3, reclassified: token-capture-canary).
- Nothing exposed: omit all usage flags — the existing null/never-fabricate
  behavior is preserved byte-for-byte; no estimation path exists (D4).
- Prompt hash (SPEC-0098 consumer wiring): when the dispatch JSON carried a
  `prompt_hash` field, pass the FULL hex through as `--prompt-hash` on that
  role's append-run. The dispatch human block's `Prompt hash:` line is a
  truncated 12-char display — never copy it; the JSON field is the value.
  No dispatch hash (no_action/needs_llm, older dispatcher) = omit the flag.
- Requested vs. actual model (validation-cost-calibration Spec-AC-04):
  `append-run --model <id>` always records `model_id` as the GRANTED model —
  the one the subagent actually ran on, never the one merely asked for.
  Whenever a model override was REQUESTED for a role (a validator dispatch
  above all — see the isolation tiers), both markers are recorded
  together in the SAME `--note` — `requested_model=<id>` AND
  `actual_model=<id>` — even when they are equal: an equal pair is the
  positive evidence the override took, and its absence must not be
  readable as either outcome. A silently-dropped
  override then shows up as `requested_model` != `actual_model`
  (`lib/usage-note.mjs` `modelOverrideDropped()`) instead of being read as
  independence that never happened. Any claim of validator independence
  (maker≠checker, "Spawning a validator" above) MUST cite `actual_model`,
  never `requested_model` — the request is not proof the isolation landed.

| Rationalization                                  | Reality                                                                                                          |
|---------------------------------------------------|--------------------------------------------------------------------------------------------------------------------|
| "I'll estimate the in/out split from the total"   | Never — record the total in the note (`usage_total_tokens=<N>`) or record nothing; splitting fabricates a component claim and would poison cost_usd. |

## Single-writer rule (HARD — RFC-0004 / SPEC-0004 D7)

The orchestrator is the SOLE writer of `docs/ai/STATE.yaml`; a subagent returns
its result block and nothing more, and the orchestrator merges that block and
performs every mutation of `docs/ai/STATE.yaml` through the merge protocol
below. This closes the lost-update race that occurs the moment K >= 2
subagents touch `STATE.yaml` directly. The subagent-facing core of this rule
(the no-write duty, the allowed-write list, its rationalization rows) is in
`.aai/SUBAGENT_CONTRACT.md`. The orchestrator additionally serializes scope
ownership with the atomic lock CLI `.aai/scripts/docs-lock.mjs` (acquire
before dispatch, release after merge — see ORCHESTRATION_PARALLEL "SCOPE
LOCKING") so two orchestrators cannot drive the same scope concurrently.

Honesty note: this is a protocol rule binding an LLM subagent, so it is partly
process, not a hard runtime guard. The mechanically enforced core is (a) the
`docs-lock.mjs` acquire/release exit-code contract the orchestrator branches on,
(b) the merge protocol, and (c) R-GUARD S1 (SPEC-0113): `state.mjs` refuses
every STATE mutation with exit 3 when `AAI_ROLE=subagent` is set (see the `ENV`
row in the call contract above). S1 is a guardrail against the honest/
accidental subagent write, NOT a security boundary — an agent that unsets or
never inherits the marker defeats it. The after-the-fact backstop is the
flush-time forensic check (`metrics-flush.mjs` S2/3): a WARN on a strategy
whose provenance is not intake/spec-path, plus an EVENTS.jsonl append-only
predicate. A git-diff post-subagent STATE guard remains an optional
defence-in-depth follow-up (R-GUARD option (a)), not yet built.

### Orchestrator lock-serialization rationalization table (stop and correct any of these)

| Rationalization                                          | Reality                                                                 |
|-----------------------------------------------------------|-------------------------------------------------------------------------|
| "I acquired nothing, the scope was obviously free"      | Always `docs-lock acquire <scope> <owner>` before working a scope; a free-looking scope can be claimed concurrently. |
| "I'm done, I'll leave the lock for cleanup/TTL"         | Release explicitly after merge (`docs-lock release <scope> <owner>`); TTL reclaim is a crash safety net, not the normal path. |

## Merge protocol (orchestrator responsibility)

After all subagents complete, the orchestrator MUST:

1. Collect ALL subagent result blocks — do not proceed with a partial set.
   Before any STATE.yaml merge, run the mandatory deterministic checker on
   each collected block: `node .aai/scripts/check-role-output.mjs --file
   <path>` (or pipe the block via stdin). A clean run (exit 0) proceeds to
   step 2. A violating run (exit 1, `ROLE-OUTPUT-VIOLATION:` lines) is
   reject-and-re-prompt-ONCE — re-dispatch that subagent with the printed
   violation lines and nothing else merges for that scope until it returns
   a clean block or a second violating return, which is treated as a
   BLOCKED result for step 2 below. If `.aai/scripts/check-role-output.mjs`
   is absent, degrade-and-report (prose) rather than hard-crash — never
   block the merge on missing tooling.
   OPT-IN PLANNING GATES (CHANGE-0113 probes R04/R09): the same checker also
   accepts `--base-ref <ref>` (a Planning run may write only docs/specs/**,
   docs/ai/** and docs/INDEX.md) and `--worktree-baseline <path>` /
   `--worktree-guard` (a Planning run may create no git worktree). Step 1 does
   NOT pass them by default — they need a base ref and a pre-dispatch
   `git worktree list --porcelain` capture the merge step does not hold — so a
   live ride is gated only when the operator adds them. The gates themselves
   are proven by tests/skills/test-aai-planning-probes.sh.
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
   - `metrics.work_items[ref_id].agent_runs` with measured timing fields from
     accepted subagent results, attaching harness-reported usage per
     "Harness-reported usage capture" above (D5: subagent-mode role runs are
     appended HERE at merge time, never self-appended by the role). The
     `usage_total_tokens=<N>` note is MANDATORY on this append whenever the
     harness result exposed a total (decomposed or undecomposed) — the
     orchestrator MUST NOT skip it as optional (token-capture-canary);
     likewise `--prompt-hash <full hex>` whenever the dispatch JSON carried
     `prompt_hash` (see "Harness-reported usage capture" above)
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

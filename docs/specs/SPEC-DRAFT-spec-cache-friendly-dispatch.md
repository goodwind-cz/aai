---
id: spec-cache-friendly-dispatch
type: spec
number: null
status: draft
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-cache-friendly-dispatch.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — token economics: cache-friendly dispatch ordering + effort routing

SPEC-FROZEN: true

## Summary

Token-economics ride continuing CHANGE-0100's cost line. Three deliverables:
(1) a stable-first/variable-last cache-ordering AUDIT of every dispatch-assembled
prompt surface, plus fixes for any surface found mis-ordered; (2) an advisory
`suggested_effort` reasoning-effort hint per role in
`.aai/system/MODEL_ROUTING.yaml`, surfaced by `orchestration-dispatch.mjs`
exactly like `suggested_model`; (3) a grep-pinned no-mid-session-flip rule so a
future edit cannot silently regress cache behavior. Prompt caching bills a
repeated stable prefix at ~10% of base rate, but only while that prefix is
byte-identical across calls and the effort/model cache key is unchanged.

## Links
- Requirement: docs/issues/CHANGE-DRAFT-cache-friendly-dispatch.md
- Technology contract: docs/TECHNOLOGY.md
- Reuses: docs/specs/SPEC-0096 (prompt-hash telemetry, byte-identity machinery)

## Cache-ordering audit (AC-001 evidence — core deliverable)

Every dispatch-assembled prompt surface was classified stable (role prompt,
CONTRACT, LEARNED refs, canon pointers, schema) vs variable (ref ids, scope
text, paths, timestamps, STATE) and its current order recorded. A surface is a
CACHE surface only when it assembles the actual prompt a subagent runs under;
the dispatch JSON and the `--human` block are diagnostic RECORDS the
orchestrator/human read, not cached subagent-prompt prefixes.

| Surface | Location | Stable vs variable order found | Verdict |
|---------|----------|-------------------------------|---------|
| Dispatch decision JSON | orchestration-dispatch.mjs dispatchFor() | machine-consumed decision record; system_prompt PATH is stable, ref_id/inputs are variable and interleaved, but it is not a cached prompt prefix | ok |
| Human dispatch block | orchestration-dispatch.mjs humanBlock() | stderr human diagnostic; state_summary (volatile) leads by design; not a cached prompt prefix | ok |
| Subagent call contract | SUBAGENT_PROTOCOL.md "Subagent call contract" table | static canon listing REQUIRED fields (ROLE, SCOPE, MODEL, INPUT, EXPECTED_OUTPUT, SYSTEM_PROMPT); a spec of fields, not the literal assembly order | ok |
| Dispatched-role assembly (single) | SKILL_LOOP.prompt.md step 4 RUN DISPATCHED ROLE + CACHING DISCIPLINE | role prompt (stable) FIRST, then dispatch block plus STATE (variable) LAST; the invariant is already pinned in the CACHING DISCIPLINE section | ok |
| Dispatched-role assembly (parallel) | ORCHESTRATION_PARALLEL.prompt.md SUBAGENT EXECUTION | canonical role prompt (stable) first, then Model, then scope plus inputs plus SUBAGENT_CONTRACT (variable then fixed canon) | ok |
| Work-item brief handoff | BRIEF_TEMPLATE.md + PLANNING step 11 | brief is entirely per-scope variable INPUT by design; canon is POINTERS only (no bodies); appended after the stable role prompt | ok |
| Shared role blocks | ROLE_COMMON.md | canonical stable blocks referenced by role prompts; no variable content | ok |

Finding: ZERO reorders required. Every surface that assembles a real dispatched
prompt (SKILL_LOOP step 4, ORCHESTRATION_PARALLEL SUBAGENT EXECUTION) already
orders the stable role prompt and canon FIRST and variable scope/STATE LAST,
and SKILL_LOOP's CACHING DISCIPLINE section already pins the invariant. This is
a legitimate AC-001 outcome (the intake anticipated it): AC-001 documents the
audit as evidence and AC-002 pins the byte-identity invariant so it cannot
regress.

## Implementation strategy
- Strategy: direct
- Rationale: audit yields zero reorders; the effort-routing work mirrors the
  proven config-driven suggested_model pattern byte-for-byte (loadModelRouting
  parse + a suggestEffort resolver + one main/humanBlock wiring line); the pin
  is a documentation-only header addition. RED-first TDD ceremony would outweigh
  a scope that is audit + config + mirror-of-existing-pattern + targeted
  regression tests. Owner chose "Let Planning decide" (CHANGE-0100 intake
  option 4); intake recommendation was `direct`. Targeted tests were written
  after the code (TEST-030..034) and all observed passing; no AC-gating test is
  tautological because each asserts a value the pre-change code could not emit
  (suggested_effort did not exist).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound change touching the deterministic dispatch script
  and a shared config; isolation keeps the shared checkout stable. This ride
  already runs in an isolated worktree.
- User decision: worktree
- Base ref: feat/cache-friendly-dispatch
- Inline review scope: .aai/scripts/orchestration-dispatch.mjs, .aai/system/MODEL_ROUTING.yaml, tests/skills/test-aai-orchestration-dispatch.sh

## Acceptance Criteria Mapping
- AC-001 -> Spec-AC-01: every audited dispatch surface orders stable content
  before variable content; the audit table above records surface then order then
  verdict; zero reorders needed. Verification: the audit table (this spec) plus
  the hostile prompt pins staying green (hygiene-pack, friction-wiring).
- AC-002 -> Spec-AC-02: the stable prefix of a role dispatch is byte-identical
  across two consecutive same-role dispatches on the same repo state.
  Verification: test-aai-orchestration-dispatch.sh TEST-033.
- AC-003 -> Spec-AC-03: MODEL_ROUTING.yaml carries suggested_effort per role;
  dispatch emits it (text plus --json) alongside suggested_model; absent
  file/field degrades to null. Verification: TEST-030, TEST-031, TEST-032.
- AC-004 -> Spec-AC-04: the no-mid-session-flip rule is present and grep-pinned;
  documentation-only, no behavioral surface changed. Verification: TEST-034.
- AC-005 -> Spec-AC-05: no prompt-corpus regression. Verification: test-aai-prompt-diet.sh TEST-010 headroom 0/2048 and TEST-012 unchanged at -4378 (no .aai/*.prompt.md or extra-accounted file touched; all growth landed in scripts/system/tests which carry no ledger cost).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Every dispatch-assembled prompt surface orders stable content before variable; audit recorded; zero reorders needed | done | audit table in this spec; hygiene-pack + friction-wiring green | — | legitimate zero-reorder outcome |
| Spec-AC-02 | Stable prefix byte-identical across two consecutive same-role dispatches | done | TEST-033 pass | — | reuses SPEC-0096 prompt-hash machinery |
| Spec-AC-03 | suggested_effort per role emitted in JSON and --human; absent file or field degrades to null | done | TEST-030, TEST-031, TEST-032 pass | — | mirrors suggested_model contract |
| Spec-AC-04 | No-mid-session-flip rule present and grep-pinned; docs-only | done | TEST-034 pass | — | pin in MODEL_ROUTING.yaml header |
| Spec-AC-05 | No prompt-corpus regression within cap | done | TEST-010 headroom 0/2048; TEST-012 == -4378 | — | zero corpus bytes added |

## Implementation plan
- Components affected: .aai/scripts/orchestration-dispatch.mjs (loadModelRouting
  effort sections, suggestEffort resolver, main + humanBlock wiring);
  .aai/system/MODEL_ROUTING.yaml (effort_tiers/effort_roles rows + header pin);
  tests/skills/test-aai-orchestration-dispatch.sh (TEST-030..034).
- Data flow: dispatch verdict -> loadModelRouting(root) once -> suggestModel and
  suggestEffort resolve from the same routing object -> both attached to the out
  object -> JSON stdout plus --human stderr.
- Edge cases: absent MODEL_ROUTING.yaml (routing null -> effort null); routing
  present but no effort sections (empty maps -> null); non-dispatch verdict
  (no_action/needs_llm -> null); a role with no effort_roles row (falls through
  to effort_tiers[tier]).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---------|---------|------|----------------------|-------------|--------|
| TEST-030 | Spec-AC-03 | unit | tests/skills/test-aai-orchestration-dispatch.sh | pure suggestEffort resolution order role override then tier default then null, plus degenerate fixtures | green |
| TEST-031 | Spec-AC-03 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI emits suggested_effort in JSON and --human; Validation high (role override), Metrics Flush low (tier default) | green |
| TEST-032 | Spec-AC-03 | integration | tests/skills/test-aai-orchestration-dispatch.sh | absent file and absent effort sections both degrade suggested_effort to null; suggested_model path unchanged | green |
| TEST-033 | Spec-AC-02 | integration | tests/skills/test-aai-orchestration-dispatch.sh | two consecutive same-role dispatches carry byte-identical stable prefix (equal prompt_hash plus inherits) | green |
| TEST-034 | Spec-AC-04 | unit | tests/skills/test-aai-orchestration-dispatch.sh | MODEL_ROUTING.yaml carries grep-pinned no-mid-session-flip rule plus effort sections and rows | green |

Notes:
- Spec-AC-01 is verified by the audit table plus the existing hostile prompt
  pins (hygiene-pack, friction-wiring) staying green — no new ordering test
  because the audit found zero reorders. Spec-AC-05 is verified by the
  prompt-diet suite (TEST-010 headroom, TEST-012 ledger sum), unchanged.

## Verification
- node --check .aai/scripts/orchestration-dispatch.mjs
- bash tests/skills/test-aai-orchestration-dispatch.sh (TEST-030..034 plus the full suite)
- bash tests/skills/test-aai-prompt-diet.sh (TEST-010 headroom 0/2048, TEST-012 == -4378)
- bash tests/skills/test-aai-hygiene-pack.sh; test-aai-friction-wiring.sh; test-aai-implementation-mode.sh; test-aai-layer-profiles.sh
- node .aai/scripts/docs-audit.mjs --check --strict --no-event
- node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-cache-friendly-dispatch.md
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
- ref_id: cache-friendly-dispatch
- Spec-AC and TEST links: per the Test Plan and AC Status tables above
- command / verdict / exit code / evidence path: recorded in the hand-off
  return record and the work-item brief
- commit SHA: recorded at commit time on branch feat/cache-friendly-dispatch

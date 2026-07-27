---
id: spec-prompt-hash-telemetry
type: spec
number: 96
status: done
ceremony_level: 3
links:
  requirement: docs/issues/CHANGE-0070-prompt-hash-telemetry.md
  rfc: null
  pr:
    - 170
  commits:
    - 1c2f602f7533fe80ccffd221778ae213a53e9970
---

# Implementation Spec — Prompt-hash telemetry: content-addressed identity of effective role instructions

SPEC-FROZEN: true

Ceremony justification: N/A (level 3 — no justification line required; the
scope touches a protected surface, `.aai/scripts/state.mjs` append-run, which
mandates level 3 per the WORKFLOW "Ceremony levels" protected-surfaces rule).

## Links
- Requirement: docs/issues/CHANGE-0070-prompt-hash-telemetry.md
- Decision records: intake body (Promptbook analysis extension 2026-07-27, adoption candidate 3 — computeAgentHash content-addressing)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: The change touches a level-3 protected surface (state.mjs append-run)
  under a strict additive-only, byte-identical-when-absent contract. Every one of
  those obligations is a regression trap that only a RED-first test can prove is
  actually held (a golden that was never observed failing proves nothing). Hash
  determinism and input-sensitivity are integrity properties that demand RED
  proof. The report-grouping and dispatch advisory line are lighter glue, but
  the L3 surface and the byte-identical proof obligations make one disciplined
  RED-GREEN pass across the whole scope the safer choice than a hybrid split.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: state.mjs is a level-3 protected surface (state engine).
  RFC-0009 rule 8 gives protected surfaces REQUIRED semantics — an explicit
  user_decision must be RECORDED for the recommendation regardless of whether a
  physical worktree is created. The operator recorded a blanket run-level
  authorization on 2026-07-27 (intake Constraints), so the recorded decision may
  be `inline` with that rationale; the mandate is the recorded decision, not the
  isolation. Planning does not create the worktree — the decision is recorded at
  Implementation Preparation / orchestration.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/prompt-hash-telemetry (current branch)
- Inline review scope: .aai/scripts/lib/prompt-hash.mjs, .aai/scripts/state.mjs, .aai/scripts/metrics-flush.mjs, .aai/scripts/metrics-report.mjs, .aai/scripts/orchestration-dispatch.mjs, .aai/system/PROFILES.yaml, tests/skills/test-aai-prompt-hash.sh, tests/skills/test-aai-state.sh, tests/skills/test-aai-metrics.sh, tests/skills/test-aai-orchestration-dispatch.sh, tests/skills/test-aai-layer-profiles.sh, docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md, docs/issues/CHANGE-0070-prompt-hash-telemetry.md

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: AC-001 (intake)
- Spec-AC-01: `.aai/scripts/lib/prompt-hash.mjs` exports `computeEffectivePromptHash(rolePromptPath)` returning a lowercase 64-char sha256 hex over the concatenation of role-prompt bytes, `.aai/SUBAGENT_CONTRACT.md` bytes, and `docs/knowledge/LEARNED.md` bytes (each section prefixed by a stable filename separator); a missing input contributes the literal `ABSENT` marker in place of its bytes and never throws; a short-form helper returns the first 12 hex chars. Hash is byte-deterministic across repeated calls and changes when ANY of the three inputs changes.
- Verification: `bash tests/skills/test-aai-prompt-hash.sh` (TEST-001) exit 0.

- Maps to: AC-002 (intake)
- Spec-AC-02: `state.mjs append-run` accepts a new OPTIONAL `--prompt-hash` flag validated as 12-to-64 lowercase hex chars; a valid value is stored on the run entry as a `prompt_hash` scalar; a non-hex or out-of-range value exits 2 with a usage error and leaves STATE byte-identical (no write); when the flag is absent the `prompt_hash` field is omitted entirely (never fabricated) and every existing append-run golden and byte-identical-fixture assertion in test-aai-state.sh stays green.
- Verification: `bash tests/skills/test-aai-state.sh` (TEST-002, TEST-003, TEST-004) exit 0.

- Maps to: AC-003 (intake)
- Spec-AC-03: `metrics-flush.mjs buildEntry` passes a run's `prompt_hash` through to the METRICS.jsonl ledger entry byte-unchanged when present; runs without it produce ledger entries with no `prompt_hash` key; the existing happy-path golden ledger line (TEST-006 in test-aai-metrics.sh) stays byte-identical.
- Verification: `bash tests/skills/test-aai-metrics.sh` (TEST-005, TEST-006, TEST-007) exit 0.

- Maps to: AC-004 (intake)
- Spec-AC-04: `metrics-report.mjs` shows each run's short 12-hex `prompt_hash` where present, and emits a "Prompt versions" grouping section counting runs by hash per role ONLY when a role has more than one distinct hash; when every role has at most one hash the report gains no new section (output otherwise unchanged).
- Verification: `bash tests/skills/test-aai-metrics.sh` (TEST-008, TEST-009) exit 0.

- Maps to: AC-005 (intake)
- Spec-AC-05: `orchestration-dispatch.mjs --human` prints one advisory line carrying the effective prompt hash for the dispatched role (computed via the lib); the emitted stdout JSON gains a `prompt_hash` field on dispatch verdicts (additive-only) and the existing TEST-002 key-set assertion is EXTENDED to include it, never broken; no-action and needs-llm verdicts are unaffected.
- Verification: `bash tests/skills/test-aai-orchestration-dispatch.sh` (TEST-010, TEST-011) exit 0.

- Maps to: AC-006 (intake)
- Spec-AC-06: no regression — the state, metrics, and orchestration-dispatch suites are green locally; the full framework suite runs on PR CI.
- Verification: the three targeted suites exit 0 locally (TEST-012, TEST-013, TEST-014); PR CI full run green.

- Maps to: Companion obligation (Planning step 3a — new .aai/** file)
- Spec-AC-07: the new `.aai/scripts/lib/prompt-hash.mjs` is classified in `.aai/system/PROFILES.yaml` under the `core:` list (it is in the import closure of the core state and dispatch engines), keeping the layer-profiles 100%-classified invariant intact.
- Verification: `bash tests/skills/test-aai-layer-profiles.sh` (TEST-015) exit 0.

## Constitution deviations

None.

## Companion obligations (Planning step 3a)
- Prompt-corpus diet ledger: NOT triggered. This change adds no bytes to
  `.aai/*.prompt.md` or `.aai/AGENTS.md` (the new file is a `.mjs` script; the
  spec and change docs live under `docs/`). No prompt-diet ledger true-up.
- New `.aai/**` file classification: TRIGGERED. `.aai/scripts/lib/prompt-hash.mjs`
  is a new file under `.aai/`. It MUST be added to `.aai/system/PROFILES.yaml`
  `core:` (Spec-AC-07 / TEST-015) or test-aai-layer-profiles.sh TEST-001 fails
  the 100%-classified invariant.

## Implementation plan
- Components/modules affected:
  - NEW `.aai/scripts/lib/prompt-hash.mjs` — `computeEffectivePromptHash(rolePromptPath)`
    and a short-form helper. Node stdlib only (`node:crypto`, `node:fs`) — zero
    new dependencies (TECHNOLOGY.md hard constraint). Inputs, in fixed order:
    the role prompt file, `.aai/SUBAGENT_CONTRACT.md`, `docs/knowledge/LEARNED.md`.
    Each section is framed by a stable filename separator so a byte moving
    between files still changes the digest; a missing file contributes the
    literal `ABSENT` marker instead of throwing.
  - `.aai/scripts/state.mjs` cmdAppendRun (PROTECTED L3) — add an OPTIONAL
    hex-validated `--prompt-hash` flag; when present push a `prompt_hash` line
    onto `runLines` AFTER the existing conditional `tdd_tests` push, so absent
    -> zero delta and present-with-tdd_tests -> existing lines unmoved. Reuse the
    existing flag-parsing + fail() usage-error path for the 12-64 hex validation
    so a bad value exits 2 before any write.
  - `.aai/scripts/metrics-flush.mjs` buildEntry — one additive line:
    `if (typeof r.prompt_hash === 'string') out.prompt_hash = r.prompt_hash;`
    after the `tdd_tests` passthrough (line ~469). parseMetricsEntries already
    captures arbitrary string run keys (prompt_hash is non-numeric so it stays a
    string) — no parser change needed. The JSON round-trip guard covers it.
  - `.aai/scripts/metrics-report.mjs` — per-run short-hash display + a
    conditional "Prompt versions" section (grouped by role, counted by hash,
    emitted only when a role has >1 distinct hash).
  - `.aai/scripts/orchestration-dispatch.mjs` — compute the dispatched role's
    effective hash via the lib; add `prompt_hash` to the dispatchFor output
    object (additive) and one advisory line in humanBlock().
  - `.aai/system/PROFILES.yaml` — classify the new lib file under `core:`.
- Data flows:
  - Producer -> STATE: the loop/orchestrator computes the hash and passes
    `--prompt-hash` to `state.mjs append-run`, which stores it on the run entry.
  - STATE -> ledger: `metrics-flush` copies `prompt_hash` into METRICS.jsonl.
  - ledger -> report: `metrics-report` groups runs by hash.
  - lib -> dispatch: `orchestration-dispatch --human` prints the hash it expects
    the dispatched role to run under (advisory; observability only).
- Edge cases:
  - `--prompt-hash` absent: field omitted end-to-end; all goldens byte-identical.
  - malformed hex / wrong length: exit 2, no write.
  - missing LEARNED / CONTRACT / role file: ABSENT marker; never throws.
  - single hash per role: no "Prompt versions" section.
  - no-action / needs-llm dispatch (no role): no prompt_hash on JSON.
- Honest limitation (intake Constraints): the hash covers ONLY the durable
  instruction layer (role prompt + CONTRACT + LEARNED). Dispatch-time extra
  context (brief, scope inputs, per-run injected text) is deliberately NOT
  included. No enforcement anywhere — observability only; no historical backfill.

## Design decisions
- D1 — Field placement in append-run runLines: `prompt_hash` is pushed AFTER the
  conditional `tdd_tests` push. Proof obligation: with `--prompt-hash` absent,
  the produced STATE bytes are identical to today for every combination
  (with/without note, with/without tdd_tests). TEST-004 pins this.
- D2 — Dispatch JSON additivity: `prompt_hash` is added to dispatch-verdict JSON
  only (from dispatchFor); no-action / needs-llm outputs are untouched. The
  TEST-002 key-set assert uses `.every(k => k in o)`, so extending its key array
  with `prompt_hash` is the sanctioned extension and adding a key never breaks
  the existing every-check. TEST-011 pins additivity.
- D3 — flush passthrough is a pure copy (`typeof === 'string'` guard), so a
  malformed/absent value simply never appears in the ledger; no re-validation at
  flush time (validation is append-run's job at the write boundary).

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                       | Status | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | prompt-hash lib determinism, input-sensitivity, ABSENT marker    | done   | tests/skills/test-aai-prompt-hash.sh TEST-001; docs/ai/tdd/green-20260727T115839Z-TEST-001.log | — | — |
| Spec-AC-02 | append-run --prompt-hash validate, store, omit, goldens intact    | done   | tests/skills/test-aai-state.sh TEST-002/003/004; docs/ai/tdd/green-20260727T120356Z-TEST-002-003-004-012.log | — | — |
| Spec-AC-03 | flush passthrough byte-unchanged, absent omits field             | done   | tests/skills/test-aai-metrics.sh TEST-005/006/007; docs/ai/tdd/green-20260727T120748Z-TEST-005-006-007-008-009-013.log | — | — |
| Spec-AC-04 | report groups by hash only when a role has more than one hash    | done   | tests/skills/test-aai-metrics.sh TEST-008/009; same green log as Spec-AC-03 | — | — |
| Spec-AC-05 | dispatch --human hash line, JSON additive, TEST-002 extended     | done   | tests/skills/test-aai-orchestration-dispatch.sh TEST-010/011; docs/ai/tdd/green-20260727T120954Z-TEST-010-011-014.log | — | — |
| Spec-AC-06 | no regression across state, metrics, dispatch suites and CI      | done   | wrapper run of all 5 targeted suites; docs/ai/tdd/green-20260727T121401Z-all-targeted-suites.log; PR CI pending | — | full framework run deferred to PR CI per Evidence Contract |
| Spec-AC-07 | new lib classified in PROFILES core, layer-profiles invariant OK | done   | tests/skills/test-aai-layer-profiles.sh TEST-001; docs/ai/tdd/green-20260727T115919Z-TEST-015.log | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Seam analysis
- SEAM-1 (state.mjs append-run -> metrics-flush): append-run WRITES `prompt_hash`
  into STATE metrics.work_items.*.agent_runs; metrics-flush READS it into the
  ledger. Covered end-to-end by TEST-007 (integration): produce a run carrying a
  hash via `state.mjs append-run`, run the real `metrics-flush`, assert the
  emitted ledger line carries the exact hash — not two mocked unit halves.
- SEAM-2 (metrics-flush -> metrics-report): flush WRITES `prompt_hash` into
  METRICS.jsonl; report READS the ledger and groups by hash. Covered by TEST-008
  (multi-hash ledger fixture -> grouping section) and TEST-009 (single-hash -> no
  section) exercising the real report against a real ledger fixture.
- SEAM-3 (prompt-hash lib -> orchestration-dispatch): the lib is consumed by
  dispatch to print the advisory line. TEST-010 exercises the real dispatch
  --human path (which calls the real lib) and asserts the hash line appears.
- Residual risk: the loop/orchestrator that actually CALLS `append-run
  --prompt-hash` at runtime is not itself modified in this scope (the producer
  side is a follow-on wiring concern). The pipeline is proven end-to-end from the
  append-run boundary onward; runtime population of the flag is out of scope and
  recorded here as a known gap (observability plumbing lands first, wiring later).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                                | Description                                                                                  | Status  |
|----------|------------|-------------|-----------------------------------------------------|----------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-prompt-hash.sh                | Hash deterministic on double-run; changes when role/CONTRACT/LEARNED bytes change; ABSENT marker used for a missing LEARNED; short form is first 12 hex | green   |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh                      | append-run stores a valid --prompt-hash as a prompt_hash scalar on the run entry             | green   |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh                      | append-run with non-hex or out-of-range --prompt-hash exits 2, usage error, STATE byte-identical (no write) | green   |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-state.sh                      | append-run without --prompt-hash omits the field; existing append-run goldens stay byte-identical (with and without tdd_tests) | green   |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-metrics.sh                    | flush copies prompt_hash into the ledger entry byte-unchanged when present                    | green   |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-metrics.sh                    | flush of a run without prompt_hash produces a ledger entry with no prompt_hash key; happy-path golden line byte-identical | green   |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-metrics.sh                    | SEAM-1: append-run --prompt-hash then real flush; assert the emitted ledger line carries the exact hash | green   |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-metrics.sh                    | SEAM-2: multi-hash ledger fixture yields a Prompt versions section grouping run counts by hash per role | green   |
| TEST-009 | Spec-AC-04 | unit        | tests/skills/test-aai-metrics.sh                    | single-hash-per-role ledger yields NO Prompt versions section (report otherwise unchanged)    | green   |
| TEST-010 | Spec-AC-05 | integration | tests/skills/test-aai-orchestration-dispatch.sh     | SEAM-3: dispatch --human prints an advisory prompt-hash line for the dispatched role (real lib) | green   |
| TEST-011 | Spec-AC-05 | unit        | tests/skills/test-aai-orchestration-dispatch.sh     | dispatch stdout JSON carries prompt_hash on a dispatch verdict; TEST-002 key-set assert extended, no-action verdict unaffected | green   |
| TEST-012 | Spec-AC-06 | integration | tests/skills/test-aai-state.sh                      | full state suite green (no regression)                                                        | green   |
| TEST-013 | Spec-AC-06 | integration | tests/skills/test-aai-metrics.sh                    | full metrics suite green (no regression)                                                      | green   |
| TEST-014 | Spec-AC-06 | integration | tests/skills/test-aai-orchestration-dispatch.sh     | full dispatch suite green (no regression)                                                     | green   |
| TEST-015 | Spec-AC-07 | integration | tests/skills/test-aai-layer-profiles.sh             | layer-profiles TEST-001 green with the new lib file classified under core (100% classified)   | green   |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED-proof obligation (all AC-gating tests, regardless of strategy): each test
  above must be observed FAILING before the change lands (goldens included — a
  byte-identical assertion that never went RED proves nothing).
- Test IDs are stable — do not renumber after freeze.

## Verification
- Commands to run:
  - `bash tests/skills/test-aai-prompt-hash.sh`
  - `bash tests/skills/test-aai-state.sh`
  - `bash tests/skills/test-aai-metrics.sh`
  - `bash tests/skills/test-aai-orchestration-dispatch.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - PR CI: full framework suite via `.aai/scripts/aai-run-tests.sh`.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status AND the full suite green on PR CI.

## Evidence contract
For each artifact, record: ref_id; Spec-AC and TEST-xxx links; command or review
scope; exit code or review verdict; evidence path; commit SHA or diff range.

- L3 review discipline (intake Constraints / WORKFLOW ceremony table):
  code_review is MANDATORY on the most-capable tier; a waiver is flagged to the
  operator (needs_llm), never auto-accepted. Operator final-diff sign-off is
  required at PR ceremony before merge (operator checkpoint).

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

---
id: spec-prompt-hash-runtime-wiring
type: spec
number: 98
status: draft
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0072-prompt-hash-runtime-wiring.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Prompt-hash runtime wiring: the orchestrator actually records the hash dispatch already computes

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0072-prompt-hash-runtime-wiring.md
- Decision records: intake body (PR #170 / CHANGE-0070 / SPEC-0096 producer side; this scope wires the consumer)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: the change touches the shared prompt-diet governance gate
  (`tests/skills/lib/prompt-diet-ledger.sh`, `tests/skills/test-aai-prompt-diet.sh`
  TEST-012) whose whole purpose is to catch un-credited prompt-corpus growth —
  a golden that was never observed failing proves nothing. RED-first evidence
  is required for both the new grep-contract test (TEST-016) and the ledger
  pin bump (TEST-012), even though the scope is small.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single small prose pointer in one prompt file plus a
  matching test/ledger true-up in two files — no protected L3 surface
  (`.aai/scripts/state.mjs` itself is unmodified), no schema/migration risk,
  three files touched total.
- User decision: waived
- Base ref: main
- Worktree branch/path: feat/prompt-hash-runtime-wiring (current branch)
- Inline review scope: .aai/SKILL_LOOP.prompt.md, tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh, docs/specs/SPEC-0098-spec-prompt-hash-runtime-wiring.md, docs/issues/CHANGE-0072-prompt-hash-runtime-wiring.md

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: AC-001 (intake)
- Spec-AC-01: `.aai/SKILL_LOOP.prompt.md` step 4 (the append-run/metrics
  boilerplate around harness-usage capture) names a `--prompt-hash`
  pass-through instruction: when the dispatch block printed a `Prompt hash:`
  line, the loop passes the full hex (the dispatch JSON `prompt_hash` field)
  through as `--prompt-hash` on that role's append-run call. A grep-contract
  test asserts both the `Prompt hash:` reference and the `--prompt-hash` flag
  name are present in the file.
- Verification: `bash tests/skills/test-aai-prompt-diet.sh` (TEST-016) exit 0.

- Maps to: AC-002 (intake)
- Spec-AC-02: prompt-corpus governance holds for the SKILL_LOOP edit — the
  shared `JUSTIFIED_ADDITIONS` ledger (`tests/skills/lib/prompt-diet-ledger.sh`)
  carries a new itemized entry for the exact measured byte growth, and
  `tests/skills/test-aai-prompt-diet.sh` TEST-012's hardcoded expected total is
  bumped to match the ledger's independently-summed `JUSTIFIED_GROWTH_BYTES`.
  The mismatch between the pre-bump hardcoded pin and the post-ledger-entry sum
  is observed as a real failure (RED) before the pin is corrected (GREEN).
- Verification: `bash tests/skills/test-aai-prompt-diet.sh` (TEST-012) exit 0;
  RED evidence at docs/ai/tdd/red-20260727T180302Z-TEST-012.log, GREEN evidence
  at docs/ai/tdd/green-20260727T180325Z-TEST-012.log.

- Maps to: AC-003 (intake)
- Spec-AC-03: no regression — the full `tests/skills/test-aai-prompt-diet.sh`
  suite (TEST-001..016) and `tests/skills/test-aai-verify-gate.sh` (which
  sources the same shared ledger library and independently re-derives the
  prompt-diet floor) both exit 0 locally, and
  `node .aai/scripts/docs-audit.mjs --check` exits 0 (the only open item is this scope's own expected pre-close self-reference, which clears at the close ceremony).
- Verification: `bash tests/skills/test-aai-prompt-diet.sh` exit 0;
  `bash tests/skills/test-aai-verify-gate.sh` exit 0;
  `node .aai/scripts/docs-audit.mjs --check` exit 0 (verdict clears to CLEAN at the close ceremony).

## Constitution deviations

None.

## Companion obligations (Planning step 3a)
- Prompt-corpus diet ledger: TRIGGERED. `.aai/SKILL_LOOP.prompt.md` grew by
  131 bytes (a single pointer sentence in the step-4 append-run boilerplate).
  Folded into scope: `tests/skills/lib/prompt-diet-ledger.sh` gained a new
  `JUSTIFIED_ADDITIONS` entry (`"131 prompt-hash-runtime-wiring ..."`) and
  `tests/skills/test-aai-prompt-diet.sh` TEST-012's expected total was bumped
  30894 -> 31025 (see Spec-AC-02 / Test Plan).
- New `.aai/**` file classification: NOT triggered. No new file was added
  under `.aai/` — only existing prompt/test/library files were edited.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                      | Status | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | SKILL_LOOP names --prompt-hash pass-through, grep-contract green | done   | tests/skills/test-aai-prompt-diet.sh TEST-016; docs/ai/tdd/red-20260727T180217Z-TEST-016.log; docs/ai/tdd/green-20260727T180241Z-TEST-016.log | — | — |
| Spec-AC-02 | prompt-corpus governance: ledger entry + TEST-012 pin bump, RED first | done | tests/skills/test-aai-prompt-diet.sh TEST-012; docs/ai/tdd/red-20260727T180302Z-TEST-012.log; docs/ai/tdd/green-20260727T180325Z-TEST-012.log | — | — |
| Spec-AC-03 | no regression: prompt-diet + verify-gate green, docs-audit clean | done | bash tests/skills/test-aai-prompt-diet.sh exit 0; bash tests/skills/test-aai-verify-gate.sh exit 0; node .aai/scripts/docs-audit.mjs --check exit 0 (verdict clears at close ceremony) | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - `.aai/SKILL_LOOP.prompt.md` — one new sentence in step 4 (dispatched-role
    completion / harness-usage capture area), immediately after the existing
    `usage_total_tokens` bullet: pass the dispatch's full-hex `prompt_hash`
    through as `--prompt-hash` on the role's append-run when the dispatch
    block printed a `Prompt hash:` line.
  - `.aai/ORCHESTRATION.prompt.md` — explicitly UNTOUCHED (hard 40-line cap,
    already at 40/40; the dispatch output already carries the hash — SKILL_LOOP
    is the single pointer, no second one needed there).
  - `tests/skills/lib/prompt-diet-ledger.sh` — new `JUSTIFIED_ADDITIONS`
    itemized entry (131 bytes, exact measured growth of the SKILL_LOOP edit).
  - `tests/skills/test-aai-prompt-diet.sh` — new `test_016_skill_loop_prompt_hash_pointer`
    grep-contract test (asserts `Prompt hash:` and `--prompt-hash` both present
    in `.aai/SKILL_LOOP.prompt.md`); TEST-012's hardcoded expected total bumped
    30894 -> 31025 to match the ledger's new independently-summed total.
- Data flows: none (documentation/governance-prose change only; no runtime
  code path is added or altered). The instruction, once followed by an
  orchestrator running the loop, causes `state.mjs append-run --prompt-hash`
  to be invoked with a real value instead of never — that is a behavior change
  in *operator/orchestrator practice*, not in any script.
- Edge cases:
  - Dispatch prints no `Prompt hash:` line (no-action / needs-llm verdicts,
    or an older `orchestration-dispatch.mjs` without prompt-hash support) —
    the instruction is conditional ("Dispatch printed ... ?"), so nothing is
    passed and append-run behaves exactly as before (optional flag, already
    proven byte-identical-when-absent by SPEC-0096 TEST-004).
  - `.aai/*.prompt.md` glob growth without a ledger entry would silently erode
    headroom scope-by-scope; the ledger entry keeps the reduction accounting
    honest (Spec-AC-02).

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description                                                                                   | Status |
|----------|------------|------|------------------------------------------------|-------------------------------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-prompt-diet.sh (TEST-016) | SKILL_LOOP.prompt.md contains both a `Prompt hash:` reference and a `--prompt-hash` flag name    | green  |
| TEST-002 | Spec-AC-02 | unit | tests/skills/test-aai-prompt-diet.sh (TEST-012) + tests/skills/lib/prompt-diet-ledger.sh | JUSTIFIED_GROWTH_BYTES == 31025 == independent re-sum of the ledger array (includes the new 131 B entry) | green  |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-prompt-diet.sh (full) + tests/skills/test-aai-verify-gate.sh + docs-audit --check | Full targeted suites exit 0; repo-wide docs-audit exit 0; verdict clears at close                                  | green  |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- RED-proof obligation: TEST-001 (TEST-016) was observed FAILING before the
  SKILL_LOOP edit (docs/ai/tdd/red-20260727T180217Z-TEST-016.log); TEST-002
  (TEST-012) was observed FAILING after the ledger entry was added but before
  the hardcoded pin was bumped (docs/ai/tdd/red-20260727T180302Z-TEST-012.log)
  — a real mismatch, not a tautology.
- Test IDs are stable — do not renumber after freeze.

## Seam analysis
- SEAM-1 (SKILL_LOOP prose -> tests/skills/lib/prompt-diet-ledger.sh's
  JUSTIFIED_GROWTH_BYTES -> test-aai-prompt-diet.sh TEST-010/TEST-012 ->
  test-aai-verify-gate.sh TEST-006): a byte-count change in the live
  `.aai/*.prompt.md` glob is shared by three independent gates that must never
  drift from each other (DEBT-0002 "two copies of one gate" pattern). Covered
  end-to-end by running all three real suites against the real edited files
  (TEST-002/TEST-003 above), not mocked byte counts.
- Residual risk: this scope wires the *instruction* an orchestrator follows,
  not a runtime enforcement mechanism — no script verifies at merge time that
  a given append-run actually carried `--prompt-hash` when the dispatch
  printed one. Verification that METRICS.jsonl rows gain non-null
  `prompt_hash` values requires observing a real subsequent loop run, which is
  outside this scope's evidence window (recorded as a known gap, consistent
  with the SPEC-0096 pattern of the same residual risk on the producer side).

## Verification
- Commands to run:
  - `bash tests/skills/test-aai-prompt-diet.sh`
  - `bash tests/skills/test-aai-verify-gate.sh`
  - `node .aai/scripts/docs-audit.mjs --check`
- Evidence artifacts:
  - docs/ai/tdd/red-20260727T180217Z-TEST-016.log
  - docs/ai/tdd/green-20260727T180241Z-TEST-016.log
  - docs/ai/tdd/red-20260727T180302Z-TEST-012.log
  - docs/ai/tdd/green-20260727T180325Z-TEST-012.log
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: prompt-hash-runtime-wiring
- Spec-AC and TEST-xxx links: as in the Test Plan table above
- command or review scope: as in Verification above
- exit code: 0 for all commands (see logs)
- evidence path: docs/ai/tdd/*-TEST-016.log, docs/ai/tdd/*-TEST-012.log
- commit SHA or diff range: uncommitted at time of writing (single-writer:
  orchestrator commits); diff range = working tree vs `main` on
  `feat/prompt-hash-runtime-wiring`

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

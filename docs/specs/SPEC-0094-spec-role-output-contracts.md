---
id: spec-role-output-contracts
type: spec
number: 94
status: draft
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0068-role-output-contracts.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — Role output contracts: deterministic EXPECT validation of subagent result blocks

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0068-role-output-contracts.md
- Decision records: adopts Promptbook's EXPECT/EXAMPLE mechanism (session
  journal analysis extension 2026-07-27, adoption candidate 1). Reuses the
  repo's zero-dependency line-based parsing convention (state.mjs engine;
  PROFILES.yaml line parser).
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: per template semantics

## Implementation strategy
- Strategy: hybrid
- Rationale: The checker (.aai/scripts/check-role-output.mjs) is new executable
  behavior — parse the LAST result-block fence, validate six deterministic
  postconditions, emit machine-parseable violations — and deserves
  RED-GREEN-REFACTOR against fixtures observed FAILING before the script exists
  (Spec-AC-01/02/03). The canon wiring (CONTRACT EXPECT pointer, PROTOCOL merge
  step-1 invocation prose, PROFILES.yaml classification) is mechanical
  grep-verified glue where RED-GREEN adds little signal (Spec-AC-04). RED-proof
  still binds every AC-gating test regardless of arm.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: One cohesive additive feature — a new zero-dep script, a
  new test suite, committed fixtures, and additive edits to two canon docs plus
  PROFILES.yaml. It touches canon (SUBAGENT_CONTRACT.md / SUBAGENT_PROTOCOL.md)
  but NONE of the protected L3 surfaces (state engine, allocator, guards,
  WORKFLOW.md, CONSTITUTION.md — verified against docs/ai/docs-audit.yaml
  protected_paths_l3). Additive and PR-bound, so isolation is useful but not
  required for safety. Inline is acceptable with the explicit review scope below.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/role-output-contracts (branch already checked out)
- Inline review scope: .aai/scripts/check-role-output.mjs, tests/skills/test-aai-role-output.sh, tests/fixtures/role-outputs/, .aai/SUBAGENT_CONTRACT.md, .aai/SUBAGENT_PROTOCOL.md, .aai/system/PROFILES.yaml, docs/specs/SPEC-0094-spec-role-output-contracts.md, docs/issues/CHANGE-0068-role-output-contracts.md

## Acceptance Criteria Mapping
For each requirement AC:

- Maps to: PRD-AC-001 (checker accepts valid / rejects violating fixtures)
- Spec-AC-01: `.aai/scripts/check-role-output.mjs` reads a role's final message
  text from stdin or `--file <path>`, extracts the LAST fenced
  `subagent_result` YAML block, and validates the six EXPECT postconditions
  (see Implementation plan). It exits 0 with no violation lines for a
  conforming block, and exits 1 emitting one machine-parseable violation line
  per failed postcondition. Extra extension fields on the block are IGNORED
  (required core validated only). Every valid fixture passes; every violating
  fixture is rejected with its expected violation code.
- Verification: `bash tests/skills/test-aai-role-output.sh` (exit 0)

- Maps to: PRD-AC-002 (deterministic, LLM-free, zero-dependency)
- Spec-AC-02: The checker runs under a plain `node` invocation with no network
  access, no model call, and no package manifest/dependency; two consecutive
  runs on identical input produce byte-identical stdout and identical exit code.
- Verification: suite runs the checker twice on one input and diffs the output
  (exit 0); `grep` proves no network/model imports and no new package.json.

- Maps to: PRD-AC-003 (timing/duration rule with tolerance; future-started rejection)
- Spec-AC-03: The checker enforces `duration_seconds == ended_utc - started_utc`
  within a +/-1s tolerance (mirroring the CONTRACT timing rule), rejects a
  `started_utc` more than 300 seconds in the future relative to the `--now`
  reference (default: current UTC) — mirroring the PROTOCOL merge-protocol
  step-2 rule — and rejects timestamps that are not parseable ISO-8601 UTC.
- Verification: fixtures for over-tolerance duration, future-started, and
  malformed-timestamp each rejected with the expected code (suite, exit 0).

- Maps to: PRD-AC-004 (wiring + classification present)
- Spec-AC-04: `.aai/SUBAGENT_CONTRACT.md` carries a grep-able EXPECT pointer
  naming `check-role-output.mjs` while STAYING at or under 60 lines (hard cap,
  hygiene-pack TEST-080); `.aai/SUBAGENT_PROTOCOL.md` merge-protocol step 1
  carries the mandatory checker invocation with reject-and-re-prompt-once before
  any STATE merge; `.aai/system/PROFILES.yaml` `core:` list classifies
  `.aai/scripts/check-role-output.mjs`.
- Verification: grep the two canon docs for the required tokens; the CONTRACT
  line count is at or under 60; `bash tests/skills/test-aai-layer-profiles.sh`
  passes (PROFILES union equals live tree).

- Maps to: PRD-AC-005 (no regression)
- Spec-AC-05: The new suite plus the CONTRACT/PROTOCOL/PROFILES pin suites
  (docs-lock, hygiene-pack, layer-profiles) pass locally; the full framework
  passes on PR CI.
- Verification: `bash tests/skills/test-aai-role-output.sh`;
  `bash tests/skills/test-aai-docs-lock.sh`;
  `bash tests/skills/test-aai-hygiene-pack.sh`;
  `bash tests/skills/test-aai-layer-profiles.sh`; PR CI skill-suite green.

## Constitution deviations

None.

<!-- Checked each article of docs/CONSTITUTION.md against the scope:
  (1) Evidence before claims — honored: fixtures + suite produce executable
  evidence. (2) Simplicity — honored: one zero-dep line-based script, no new
  abstraction; postconditions validate required core only. (3) Portability —
  honored: plain node stdlib, git-diffable committed fixtures. (4) Degrade and
  report — honored: machine-parseable violation lines; absent-checker degrade
  handled by orchestrator prose. (5) Additive first — honored: new script/suite,
  additive CONTRACT pointer + PROTOCOL step + PROFILES entry; the result-block
  schema is explicitly NOT changed. (6) Single-writer state — honored: the
  checker never writes STATE.yaml; this planning dispatch itself writes no STATE.
  (7) Operator-only merge — honored. -->

## Implementation plan

### The six EXPECT postconditions (authoritative source)
The postconditions are declared HERE and ENCODED in
`.aai/scripts/check-role-output.mjs`; the script is the single executable source
of truth. Each carries a stable violation code emitted on `stdout` as
`ROLE-OUTPUT-VIOLATION: <CODE> <detail>` (one line per failure; machine-parseable
prefix). Codes:

1. E-NO-BLOCK — a parseable `subagent_result` YAML block is present. The checker
   extracts the LAST ```yaml (or bare) fence whose body starts with
   `subagent_result:`; absence or unparseable body fails.
2. E-MISSING-FIELD — all required core fields present: scope, role, status,
   started_utc, ended_utc, duration_seconds, evidence, files_changed, blockers.
   Extra extension fields are ignored (validate required core only).
3. E-BAD-STATUS — `status` is one of PASS / FAIL / BLOCKED.
4. E-NO-EVIDENCE — at least one `evidence` entry with an INTEGER `exit_code`.
5. E-BAD-TIMESTAMP — `started_utc` and `ended_utc` are parseable ISO-8601 UTC
   (explicit `Z` or `+00:00`).
6. E-BAD-DURATION — `duration_seconds` equals `ended_utc - started_utc` within
   +/-1s; AND `started_utc` is not more than 300s in the future vs `--now`
   (default current UTC) — the E-FUTURE-STARTED sub-code mirrors the PROTOCOL
   merge-protocol step-2 300s rule.

### Components / modules affected
- NEW `.aai/scripts/check-role-output.mjs`: stdin/`--file` input; optional
  `--now <ISO>` for deterministic testing of the future-timestamp rule; a
  dependency-free line-based YAML-subset parser (consistent with state.mjs and
  the PROFILES.yaml parser — no YAML library); exit 0 clean / 1 on any violation.
- NEW `tests/fixtures/role-outputs/`: one VALID + one VIOLATING fixture per role
  class (implementation, validation, review, planning). Committed test data (NOT
  gitignored) so a fresh CI checkout has them (LEARNED 2026-07-17: fresh CI
  lacks per-dev gitignored runtime files).
- NEW `tests/skills/test-aai-role-output.sh`: `#!/usr/bin/env bash`, bash-3.2
  safe; auto-discovered by `tests/skills/test-framework.sh`
  (`find -name 'test-aai-*.sh'`) so no CI manifest edit is required.
- EDIT `.aai/SUBAGENT_CONTRACT.md`: add a single EXPECT pointer line naming the
  checker. HARD CONSTRAINT: the file is 58 lines today and hygiene-pack TEST-080
  caps it at 60 — the pointer must be at most ~1-2 lines. The six declarations
  do NOT go inline (they live in the checker + this spec).
- EDIT `.aai/SUBAGENT_PROTOCOL.md`: merge-protocol step 1 gains the mandatory
  checker invocation (reject-and-re-prompt once before any STATE merge). No line
  cap on this file.
- EDIT `.aai/system/PROFILES.yaml`: add `.aai/scripts/check-role-output.mjs` to
  the `core:` list (it is a merge-protocol gate — core per the classification
  rule). The suite and fixtures live under `tests/`, OUTSIDE the PROFILES tree,
  so they are NOT classified here.

### Data flows
Role final message text -> checker (LAST fence extraction -> subset parse ->
six postcondition checks) -> exit code + violation lines -> orchestrator
merge-protocol step 1 branches on exit code (0 = proceed to merge; 1 = reject
and re-prompt once).

### Edge cases
- Multiple `subagent_result` fences: only the LAST is validated (roles may echo
  the template skeleton earlier in their message).
- Extra extension fields (rides add scope-specific fields): ignored.
- `blockers: []` empty list is valid (field present, no blocker).
- `--now` unset: default to current UTC (the 300s-future rule still applies).
- Missing checker at merge time: orchestrator degrade-and-report (prose), not a
  hard crash — mirrors the single-writer honesty note.

### Companion-obligations findings (PLANNING step 3a — measured, not assumed)
- Prompt-diet ledger true-up: DOES NOT APPLY. Measured: the only corpus-shaped
  edits land in `.aai/SUBAGENT_CONTRACT.md` and `.aai/SUBAGENT_PROTOCOL.md`,
  both `.aai/*.md` NON-prompt files. TEST-010's live glob is literally
  `cat .aai/*.prompt.md` (tests/skills/test-aai-prompt-diet.sh:327), and the
  step-3a prompt corpus is `.aai/*.prompt.md` + `.aai/AGENTS.md`. Neither canon
  doc matches, so there is NO measured deficit and NO ledger entry. This
  CORRECTS the intake's "prompt-diet ledger true-up for corpus bytes" scope line
  and the ledger clause of intake AC-004 — dropped here as unwarranted.
- PROFILES.yaml classification: APPLIES. The scope adds a NEW `.aai/**` file
  (`.aai/scripts/check-role-output.mjs`), so a `core:` classification entry is
  folded into scope and the Test Plan (TEST-011 via test-aai-layer-profiles.sh).
  The intake's "and suite" is imprecise: the suite/fixtures under `tests/` are
  outside the PROFILES `.aai/` tree and are NOT classified.

### Seam analysis (PLANNING step 6a)
- SEAM-1 (doc contract <-> executable checker): the checker's required-field set
  must match the result-block schema documented in `.aai/SUBAGENT_CONTRACT.md`,
  which is ALSO mirrored byte-identically into `BRIEF_TEMPLATE.md` Return Record
  (hygiene-pack pins that byte-identity). If the checker requires a field the
  canonical skeleton lacks (or vice versa), real subagents produce blocks the
  checker rejects. Crossed end-to-end by TEST-014: extract the canonical
  `subagent_result` skeleton from SUBAGENT_CONTRACT.md, fill it with valid
  sample values, pipe it through the checker, assert exit 0.
- SEAM-2 (checker 300s rule <-> PROTOCOL merge-protocol step-2 timing rule):
  both must use the SAME 300s future-timestamp threshold. Crossed by TEST-013
  (checker rejects >300s future) plus a grep asserting PROTOCOL still documents
  300s — so the two cannot silently diverge.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Checker validates LAST fence vs six postconditions; ignores extras | done | docs/ai/tdd/green-role-output-contracts-full-suite-20260727T094804Z.log (TEST-001..004,009,014) | — | — |
| Spec-AC-02 | Deterministic, LLM-free, zero-dependency                          | done | docs/ai/tdd/green-role-output-contracts-full-suite-20260727T094804Z.log (TEST-005,006) | — | — |
| Spec-AC-03 | Duration +/-1s tolerance; 300s-future + malformed timestamp rejected | done | docs/ai/tdd/green-role-output-contracts-full-suite-20260727T094804Z.log (TEST-007,008,013) | — | — |
| Spec-AC-04 | CONTRACT EXPECT pointer (<=60 lines); PROTOCOL step-1 wiring; PROFILES core | done | docs/ai/tdd/green-role-output-contracts-full-suite-20260727T094804Z.log (TEST-010); tests/skills/test-aai-layer-profiles.sh (TEST-011) | — | — |
| Spec-AC-05 | No regression: new suite + docs-lock + hygiene-pack + layer-profiles green | deferred | tests/skills/test-aai-role-output.sh, test-aai-docs-lock.sh, test-aai-hygiene-pack.sh, test-aai-layer-profiles.sh all exit 0 locally (TEST-012 done); TEST-015 (PR CI full framework) not yet run | 2026-08-10 | PR CI leg (TEST-015) verifies on push; local legs all green |

Status values: planned / implementing / done / deferred / blocked / rejected

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type        | File path (expected)                    | Description                                                             | Status  |
|----------|------------|-------------|-----------------------------------------|------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-role-output.sh    | Every VALID fixture (4 classes) -> exit 0, zero violation lines        | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-role-output.sh    | Every VIOLATING fixture -> exit 1 with its expected ROLE-OUTPUT-VIOLATION code | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-role-output.sh    | Valid block carrying EXTRA unknown fields still passes (core-only)     | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-role-output.sh    | Two fences present: LAST wins (last-valid passes; last-invalid fails)  | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-role-output.sh    | Two consecutive runs on same input -> byte-identical stdout + exit     | green |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/test-aai-role-output.sh    | No network/model import in checker; no package.json added; runs on plain node | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-role-output.sh    | Duration within +/-1s accepted; beyond tolerance -> E-BAD-DURATION      | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-role-output.sh    | Malformed (non-ISO-8601) timestamp -> E-BAD-TIMESTAMP                   | green |
| TEST-009 | Spec-AC-01 | unit        | tests/skills/test-aai-role-output.sh    | Missing required field -> E-MISSING-FIELD; bad status -> E-BAD-STATUS; no integer exit_code -> E-NO-EVIDENCE | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-role-output.sh    | CONTRACT at/under 60 lines AND carries EXPECT pointer naming check-role-output.mjs; PROTOCOL step 1 names the mandatory checker invocation + reject-and-re-prompt-once | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-layer-profiles.sh | PROFILES core classifies .aai/scripts/check-role-output.mjs (union equals live tree) | green |
| TEST-012 | Spec-AC-05 | integration | tests/skills/test-aai-docs-lock.sh + tests/skills/test-aai-hygiene-pack.sh | CONTRACT/PROTOCOL pins survive the EXPECT-pointer + step-1 edits        | green |
| TEST-013 | Spec-AC-03 | integration | tests/skills/test-aai-role-output.sh    | started_utc >300s ahead of --now -> E-FUTURE-STARTED; PROTOCOL still documents 300s (SEAM-2) | green |
| TEST-014 | Spec-AC-01 | integration | tests/skills/test-aai-role-output.sh    | SEAM-1: canonical subagent_result skeleton extracted from SUBAGENT_CONTRACT.md, filled with valid values, passes the checker | green |
| TEST-015 | Spec-AC-05 | e2e         | .github/workflows/skill-suite.yml       | Full framework green on PR CI (auto-discovered suite runs)              | pending |

Test status values: pending / red / green

Notes:
- Every Spec-AC has at least one TEST-xxx entry (AC-01: 001/002/003/004/009/014;
  AC-02: 005/006; AC-03: 007/008/013; AC-04: 010/011; AC-05: 012/015).
- SEAM-1 -> TEST-014; SEAM-2 -> TEST-013. Both crossed end-to-end.
- RED-proof: TEST-001..009,013,014 must be observed FAILING before the checker
  exists (no `.aai/scripts/check-role-output.mjs`), TEST-010/011/012 before the
  canon/PROFILES edits, so a passing state is real evidence, not a tautology.
- Test IDs are stable — do not renumber after freeze.

## Verification
- Commands to run (derived from Test Plan above):
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0094-spec-role-output-contracts.md` (structural, report-only)
  - `bash tests/skills/test-aai-role-output.sh`
  - `bash tests/skills/test-aai-docs-lock.sh`
  - `bash tests/skills/test-aai-hygiene-pack.sh`
  - `bash tests/skills/test-aai-layer-profiles.sh`
  - `node .aai/scripts/docs-audit.mjs --check` (docs hygiene)
  - PR CI: skill-suite.yml (full `tests/skills/` framework) + self-hosting smoke
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: role-output-contracts
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ for RED-GREEN evidence; suite logs)
- commit SHA or diff range when available

## Residual risks
- R-1 (process, not runtime): the orchestrator's reject-and-re-prompt-once on a
  failing check is PROSE binding an LLM orchestrator, not a hard runtime guard —
  mirroring the existing single-writer honesty note. The checker itself
  (exit-code contract) IS mechanically enforced and CI-pinned; the re-prompt
  discipline is the non-mechanical part.
- R-2 (fixtures): fixtures must be committed (not gitignored) so a fresh CI
  checkout has them (LEARNED 2026-07-17). Mitigated by placing them under the
  tracked tests/fixtures/role-outputs/.
- R-3 (CONTRACT 60-line cap): the EXPECT addition to SUBAGENT_CONTRACT.md must
  stay within the 2-line headroom (58 -> at most 60). Mitigated by design D1 —
  a single pointer line; the six declarations live in the checker + this spec,
  not inline in the contract.

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

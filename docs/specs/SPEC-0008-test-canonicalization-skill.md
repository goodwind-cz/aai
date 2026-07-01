---
id: SPEC-0008
type: spec
status: done
links:
  requirement: RFC-0006
  rfc: RFC-0006
  pr: []
  commits: []
---

# SPEC-0008 — Test Canonicalization & Aggregation Skill (aai-test-canon)

SPEC-FROZEN: true

## Links
- Decision record: docs/rfc/RFC-0006-test-canonicalization-skill.md
- Technology contract: docs/TECHNOLOGY.md
- Prior art (structural twin): docs/specs/SPEC-0002-docs-canonicalization-skill.md
- Canonical domain map authority: docs/ai/docs-canon.map.json

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in RFC-0006)
Tests have no canonicalization equivalent to `aai-docs-canon` (RFC-0003 / SPEC-0002).
They stay fragmented per change/issue, scattered across `tests/skills/`,
`tests/self-hosting/`, etc. — anchored to changes that get archived. There is no
single "what is the tested current state of domain X" view, and no systematic
check that the aggregated, canonically-described functionality is actually covered.
After docs canonicalization runs, the canonical domain map (`docs/ai/docs-canon.map.json`)
becomes the natural backbone to synchronize tests against: each
`docs/canonical/<domain>.md` carries the live acceptance criteria / intent for
that domain, so tests should be (a) mapped to those domains, (b) checked for
coverage gaps against the aggregated functionality, and (c) consolidated into a
canonical, per-domain test layer rather than left split by now-archived changes.

## Design decisions (load-bearing — read before implementing)
1. **Two-phase design twins aai-docs-canon.** Phase 1 (analyze & propose, HUMAN
   gate) builds a traceability matrix and coverage gap report, writes a
   machine-readable proposal, and HALTS. Phase 2 (synthesize & canonicalize) runs
   only after operator approval, consolidates tests into `tests/canonical/`,
   archives originals to `tests/_archive/` with back-links, scaffolds RED stubs
   for uncovered criteria, and hands off to `aai-tdd`. Phase 1 NEVER moves or
   writes test files.

2. **Proposal format mirrors docs-canon.map.json.** Phase 1 writes
   `docs/ai/test-canon.proposal.json` with `"approved": false`. Phase 2 reads
   from `docs/ai/test-canon.map.json` with `"approved": true`. The two files may
   be the same file with an updated approval flag, or separate files — the
   implementation MUST gate Phase 2 on an explicit `"approved": true` marker.

3. **Coverage gap report is machine-readable and human-readable.** Phase 1 emits
   both a JSON matrix (`docs/ai/test-canon.proposal.json`) and a human-readable
   report (location: `docs/ai/reports/test-canon-coverage-<timestamp>.md` or
   similar). The report lists, per canonical domain, which acceptance criteria
   have covering tests and which are uncovered.

4. **Drift detection mirrors docs-canon.** Source test hashes and canonical-doc
   criteria hashes are recorded in the map file. Re-running reports drift
   (changed source test or changed canonical doc criteria) without silently
   overwriting. A `--drift` / `--resync` mode re-synthesizes from archived
   sources, preserving the same contract as docs-canon.

5. **Stubs are RED, tagged, and bridge to aai-tdd.** For each uncovered
   acceptance criterion, Phase 2 scaffolds a failing/pending test stub (RED)
   tagged to domain + criterion. The stub MUST be syntactically valid so the
   runner can invoke it (and observe RED). The tag schema links stub → domain →
   criterion so the gap report can reference it. Phase 2 does NOT implement GREEN;
   it hands off to `aai-tdd` for that.

6. **Runner compatibility preserved.** After canonicalization, tests in
   `tests/canonical/` must be discoverable by the project's existing runners
   (Pester `.Tests.ps1`, bash `test-*.sh`, `tests/skills/test-framework.sh`
   harness). Phase 2 verifies the canonical suite still runs via existing runners
   before archiving originals. Originals in `tests/_archive/` are never deleted;
   bidirectional back-links are preserved (mirroring docs-canon's archive format).

7. **Soft prerequisite on docs/canonical/.** If `docs/canonical/` is absent
   (docs-canon hasn't run), Phase 1 degrades gracefully: it reports the absence
   and maps against raw `docs/` docs instead, never blocking the run.

8. **Unclear domain mapping bucket.** Tests that cannot be confidently mapped to
   a canonical domain are placed in an `unclear` bucket in the proposal. The
   operator reviews these during HITL approval. Phase 2 does not move `unclear`
   tests; they stay in place until the operator assigns a domain.

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD for the core analysis engine (Phase 1 matrix builder, Phase 2
  consolidator/move logic, drift detection) because these touch shared artifacts
  (canonical domain map, test files, git history) and carry real regression risk
  (wrong domain assignment moves tests incorrectly, drift mis-detection silently
  overwrites). Loop for the prompt file (`.aai/SKILL_TEST_CANON.prompt.md`),
  proposal file format, and documentation, which are low-risk glue verified by
  grep/assertion.
- RED-proof obligation (all AC-gating tests, any strategy): every gating test
  must be observed FAILING without the change. Negative assertions (Spec-AC-01
  Phase-1-never-moves, Spec-AC-02 Phase-2-gates-on-approved, Spec-AC-03
  drift-reports-without-silent-overwrite) embed a positive control in the same
  fixture so the RED is genuine.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: This skill touches multiple independent modules (new
  `.aai/scripts/test-canon.mjs`, new `.aai/SKILL_TEST_CANON.prompt.md`, test
  directory restructuring via `tests/canonical/` and `tests/_archive/`, and
  potential git move operations). It adds a new role/skill to the workflow and
  modifies test runner discovery paths. Isolation protects against accidentally
  destabilizing the existing test layout or git history during development. The
  user should decide before implementation begins.
- User decision: undecided
- Base ref: main
- Worktree branch/path: n/a (pending user decision)
- Inline review scope: (to be set after user decision on worktree)

## Acceptance Criteria Mapping

- Maps to: RFC-0006 Proposal / Phase 1
  - Spec-AC-01: Phase 1 parses existing tests and the canonical domain map
    (`docs/ai/docs-canon.map.json`), builds a traceability matrix mapping each
    test → canonical domain(s) → acceptance criteria it exercises, emits a
    coverage gap report listing criteria in `docs/canonical/<domain>.md` with no
    covering test, clusters a proposed per-domain test map, and writes a
    machine-readable proposal file (`docs/ai/test-canon.proposal.json`) with
    `"approved": false`. Phase 1 NEVER moves or writes test files. Tests that
    cannot be confidently mapped are placed in an `unclear` bucket.
  - Verification: TEST-001, TEST-002.

- Maps to: RFC-0006 Proposal / Phase 2
  - Spec-AC-02: Phase 2 runs only when the operator has set `"approved": true`
    in the map file (`docs/ai/test-canon.map.json`). It consolidates contributing
    tests into a canonical per-domain test layer (`tests/canonical/<domain>.*`),
    MOVES (tracked git move) originals to `tests/_archive/` with a back-link,
    scaffolds a failing/pending test stub (RED) for each uncovered acceptance
    criterion tagged to domain + criterion, and hands off to `aai-tdd`. Phase 2
    does NOT implement GREEN. The `unclear` bucket tests are NOT moved.
  - Verification: TEST-003, TEST-004, TEST-005.

- Maps to: RFC-0006 Consequences / Drift awareness
  - Spec-AC-03: The skill records source test hashes and canonical-doc criteria
    hashes in the map file. Re-running with no changes is idempotent (same output
    byte-identical modulo timestamps). When a source test or canonical doc
    criterion has changed, `--drift` / `--resync` reports the drift without
    silently overwriting — the operator must approve before re-synthesis.
  - Verification: TEST-006, TEST-007.

- Maps to: RFC-0006 Consequences / Runner compatibility
  - Spec-AC-04: After Phase 2 canonicalization, tests in `tests/canonical/` are
    discoverable and executable by the project's existing runners (Pester
    `.Tests.ps1`, bash `test-*.sh`, `tests/skills/test-framework.sh` harness).
    Phase 2 verifies the canonical suite still runs green via existing runners
    before archiving originals. Originals in `tests/_archive/` are never deleted;
    bidirectional back-links are present (archive → canonical and canonical →
    archive).
  - Verification: TEST-008.

- Maps to: RFC-0006 Open Questions / Soft prerequisite
  - Spec-AC-05: When `docs/canonical/` is absent (docs-canon hasn't run),
    Phase 1 degrades gracefully: it reports the absence to stderr, maps against
    raw `docs/` docs instead, and does NOT block or abort. The proposal file
    notes the degraded mode.
  - Verification: TEST-009.

- Maps to: RFC-0006 Consequences / Coverage matrix report
  - Spec-AC-06: Phase 1 produces a human-readable coverage matrix report
    (location: `docs/ai/reports/test-canon-coverage-<timestamp>.md`) showing,
    per canonical domain, which acceptance criteria have covering tests and which
    are uncovered, plus the `unclear` bucket contents. This report is also
    embedded in the machine-readable proposal.
  - Verification: TEST-010.

- Maps to: RFC-0006 Risks / Stub lifecycle
  - Spec-AC-07: Scaffolded stubs carry a stable tag linking stub → domain →
    criterion (e.g. a file-naming convention or inline metadata). The tag is
    referenced in the coverage gap report so stubs cannot silently rot. Stubs are
    syntactically valid (the runner can invoke them and observe RED/fail).
  - Verification: TEST-011.

- Maps to: RFC-0006 Open Questions / Drift mode
  - Spec-AC-08: `--drift` mode compares current hashes against recorded hashes
    and reports any mismatch (changed source test or changed canonical doc
    criteria) without modifying any files. `--resync` mode re-synthesizes
    drifted domains from archived sources + re-baselines hashes, mirroring
    docs-canon's `--resync` contract.
  - Verification: TEST-012.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | Phase 1: parse, matrix, gap report, proposal with `"approved": false`; never moves tests; unclear bucket | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-001/TEST-002); node --phase1 produces proposal with approved:false; originals not moved | — | — |
| Spec-AC-02 | Phase 2: runs only on `"approved": true`; canonical test layer; git-tracked move + archive + back-links; RED stubs per uncovered criterion; unclear NOT moved | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-003/TEST-004/TEST-005); node --phase2 blocked on approved:false; --phase2 succeeds on approved:true; stubs RED; unclear not moved | — | — |
| Spec-AC-03 | Drift recording + idempotency; re-run idempotent; drift reports without silent overwrite | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-006/TEST-007); re-run byte-identical; modified source triggers drift without silent overwrite | — | — |
| Spec-AC-04 | Runner compatibility: canonical tests discoverable by existing runners; verification before archive; back-links bidirectional | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-008); canonical tests discoverable; archive has canonical: back-links | — | — |
| Spec-AC-05 | Soft prerequisite: degrade gracefully when `docs/canonical/` absent | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-009); node --phase1 without docs/canonical/ exits 0, reports degrade, writes proposal | — | — |
| Spec-AC-06 | Human-readable coverage matrix report per domain | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-010); report at docs/ai/reports/test-canon-coverage-*.md with per-domain coverage | — | — |
| Spec-AC-07 | Scaffolded stubs tagged (domain + criterion), syntactically valid, referenced in gap report | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-011); stubs have domain tag + AC- criterion tag; bash -n validates syntax; gap report references domain | — | — |
| Spec-AC-08 | `--drift` reports mismatches without modifying; `--resync` re-synthesizes from archived sources | done | bash tests/skills/test-aai-test-canon.sh exit 0 (TEST-012); --drift exits 1 with no file timestamp changes; --resync re-synthesizes and re-baselines hashes | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/test-canon.mjs` — deterministic CLI for Phase 1 (parse,
    matrix, proposal) and Phase 2 (consolidate, move, scaffold, drift). Twins
    the architecture of `.aai/scripts/docs-canon.mjs`.
  - `.aai/SKILL_TEST_CANON.prompt.md` — skill prompt that invokes
    `test-canon.mjs` with the appropriate phase flags and handles the HITL gate.
  - `docs/ai/test-canon.proposal.json` / `docs/ai/test-canon.map.json` —
    machine-readable proposal/map files with `approved` flag.
  - `tests/canonical/` — canonical per-domain test layer.
  - `tests/_archive/` — archived originals with back-links.
  - `docs/ai/reports/` — coverage matrix report location.
  - `.aai/workflow/WORKFLOW.md` — add the skill as a re-runnable maintenance
    skill (not a workflow role).
  - `tests/skills/test-aai-test-canon.sh` — test suite for SPEC-0008.
- Data flows:
  - Phase 1 reads `docs/ai/docs-canon.map.json` + existing test files in
    `tests/skills/`, `tests/self-hosting/`, etc. → produces matrix → writes
    proposal + coverage report. No writes to test directories.
  - Phase 2 reads approved map → git mv originals → write canonical tests →
    scaffold stubs → verify runner → record hashes.
  - Drift: compare current hashes vs recorded hashes; `--resync` re-reads
    archived sources and re-synthesizes.
- Edge cases:
  - Test file that maps to multiple domains → appears in both canonical test
    layers with cross-reference.
  - Test that maps to zero domains → `unclear` bucket; Phase 2 does not move it.
  - `docs/canonical/` absent → degrade mode; Phase 1 maps against raw docs.
  - Runner verification fails in Phase 2 → Phase 2 aborts before archiving;
    error message names the failing test.
  - Stale proposal file (operator approved but criteria changed since) →
    drift check re-runs Phase 1 before Phase 2.

## Seam analysis
- SEAM-1 (Phase 2 canonical tests → existing runners): The canonical test layer
  (`tests/canonical/`) must be discoverable by Pester, bash `test-*.sh`, and
  `tests/skills/test-framework.sh`. If path/glob changes break discovery, tests
  silently vanish. TEST-008 crosses this seam end-to-end: run Phase 2, then
  invoke each existing runner over `tests/canonical/` and assert discovery +
  execution.
- SEAM-2 (Drift detection → canonical docs layer): Drift mode reads canonical
  doc criteria hashes. If the canonical doc format changes, drift may mis-report
  or fail to detect actual drift. TEST-006 crosses this seam: modify a canonical
  doc criterion → drift is detected; modify an unrelated doc section → no drift.
- SEAM-3 (Phase 2 scaffolded stubs → aai-tdd): Stubs are consumed by aai-tdd
  for GREEN implementation. If stubs are mis-tagged or malformed, aai-tdd may
  produce wrong tests or fail. TEST-011 crosses this seam: verify stub tag
  schema is parseable by aai-tdd's convention. TEST-004 verifies stubs are RED
  (failing) before handoff.
- SEAM-4 (Phase 1 proposal → operator approval gate): The proposal file
  (`"approved": false`) is the handoff point. If the format changes or approval
  check is bypassed, Phase 2 may run without approval. TEST-002 crosses this
  seam: produce a proposal with `"approved": false`, attempt Phase 2 → blocked;
  set `"approved": true` → Phase 2 runs.
- Residual risk (recorded): Mapping tests → acceptance criteria is inherently
  fuzzy. Mitigated by the `unclear` bucket + HITL review of the matrix before
  Phase 2. The drift `--resync` re-synthesizes from archived originals, so
  mistaken moves are reversible by operator re-approval.

## Test Plan

| Test ID  | Spec-AC    | Type       | File path (expected)                     | Description | Status |
|----------|------------|------------|------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-test-canon.sh | Phase 1: given a fixture with known tests + canonical domain map, produces `docs/ai/test-canon.proposal.json` with `"approved": false`, coverage gap report listing uncovered criteria, and `unclear` bucket for unmappable tests. No test files are moved or written. RED: Phase 1 with a naive stub that writes a test file → the stub must fail (test file appears). | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-test-canon.sh | Seam-4: A proposal with `"approved": false` blocks Phase 2 (exit ≠0 or error). Setting `"approved": true` allows Phase 2 to proceed. RED: a Phase-2 call that ignores the approval flag and proceeds anyway → must fail (approval gate bypass detected). | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-test-canon.sh | Phase 2 with approved map consolidates tests into `tests/canonical/<domain>.*`, git-moves originals to `tests/_archive/` with back-links, scaffolds RED stubs for uncovered criteria. Verify git log shows the move (tracked). `unclear` bucket tests are NOT moved. RED: Phase 2 that does not git-move (just copies) → must fail (originals not archived). | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-test-canon.sh | Seam-3: Scaffolded stubs are RED — the runner can invoke them and observes failure (non-zero exit or pending/skip). Verify by running the stub before implementation. RED: a stub that passes (GREEN without implementation) → must fail. | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-test-canon.sh | Phase 2 verifies the canonical suite still runs via existing runners before archiving originals. If runner verification fails (e.g., a stub is syntactically invalid), Phase 2 aborts before archiving and reports the failure. RED: Phase 2 that archives before runner check → must fail (originals archived despite runner failure). | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-test-canon.sh | Seam-2: Drift detection — modify a source test in `tests/canonical/` or a canonical doc criterion in `docs/canonical/<domain>.md`, re-run skill → drift is reported without silent overwrite. Unchanged run is idempotent (output byte-identical modulo timestamps). RED: a drift-blind stub that silently overwrites on re-run → must fail (output differs without drift report). | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-test-canon.sh | `--drift` mode reports mismatches but modifies no files. `--resync` mode re-synthesizes drifted domains from archived sources + re-baselines hashes. RED: `--drift` that modifies files → must fail (files changed). | green |
| TEST-008 | Spec-AC-04 | integration | tests/skills/test-aai-test-canon.sh | Seam-1: After Phase 2, each existing runner (Pester, bash `test-*.sh`, `tests/skills/test-framework.sh`) discovers and executes tests in `tests/canonical/`. Originals in `tests/_archive/` have bidirectional back-links. RED: a runner that does NOT discover canonical tests → must fail (runner exit ≠0 or zero tests found). | green |
| TEST-009 | Spec-AC-05 | integration | tests/skills/test-aai-test-canon.sh | When `docs/canonical/` is absent, Phase 1 degrades gracefully: reports absence to stderr, maps against raw `docs/` docs, does not abort. The proposal file notes the degraded mode. RED: a hard-block stub that exits ≠0 when `docs/canonical/` absent → must fail (degrade mode not triggered). | green |
| TEST-010 | Spec-AC-06 | integration | tests/skills/test-aai-test-canon.sh | Phase 1 produces a human-readable coverage matrix report at `docs/ai/reports/test-canon-coverage-<timestamp>.md` showing per-domain criteria coverage status and `unclear` bucket contents. RED: a stub that does not produce the report → must fail (report absent). | green |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-test-canon.sh | Seam-3: Scaffolded stubs carry a stable tag linking stub → domain → criterion (file-naming or inline metadata). The tag is referenced in the gap report. Stubs are syntactically valid (runner can invoke them and observe RED). RED: a stub with incorrect or missing tag → must fail (tag validation fails). | green |
| TEST-012 | Spec-AC-08 | integration | tests/skills/test-aai-test-canon.sh | `--drift` reports mismatches without modifying files (file timestamps unchanged). `--resync` re-synthesizes from archived sources and re-baselines hashes. RED: `--drift` that touches files → must fail. RED: `--resync` that does not update hashes → must fail (hashes stale). | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test
IDs are stable; do not renumber after freeze.

## Verification
- `bash tests/skills/test-aai-test-canon.sh` — TEST-001..012 all green.
- `node .aai/scripts/test-canon.mjs --phase1` over a fixture produces
  `docs/ai/test-canon.proposal.json` with `"approved": false`.
- `node .aai/scripts/test-canon.mjs --phase2` over an unapproved proposal exits
  ≠0 (blocked); over an approved map it consolidates, archives, scaffolds stubs.
- `node .aai/scripts/test-canon.mjs --drift` over a changed fixture reports
  mismatches and exits 0 without modifying files.
- `node .aai/scripts/test-canon.mjs --resync` re-synthesizes drifted domains
  from archived sources.
- `node .aai/scripts/test-canon.mjs --phase1` with absent `docs/canonical/`
  exits 0, reports degraded mode, maps against raw docs.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (RFC-0006 / SPEC-0008)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (RFC-0006 owns WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.

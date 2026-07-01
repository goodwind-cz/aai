---
id: RFC-0006
type: rfc
status: done
links:
  spec: SPEC-0008
  pr: []
  commits: []
---

# RFC (Decision Proposal): Test Canonicalization & Aggregation Skill (aai-test-canon)

Frontmatter status values: draft | proposed | accepted | implementing | done | deferred | rejected | superseded

## Context
- Problem or opportunity:
  - `aai-docs-canon` (RFC-0003 / SPEC-0002) consolidates layered docs into a
    single canonical "current state" layer in `docs/canonical/`, one canonical
    doc per functional domain, archiving and back-linking the originals. Tests
    have no equivalent. They stay fragmented per change/issue, scattered across
    `tests/skills/`, `tests/self-hosting/`, etc. — anchored to changes that get
    archived. There is no single "what is the tested current state of domain X"
    view, and no systematic check that the aggregated, canonically-described
    functionality is actually covered.
  - After docs canonicalization runs, the canonical domain map becomes the
    natural backbone to synchronize tests against: each `docs/canonical/<domain>.md`
    carries the live acceptance criteria / intent for that domain, so tests
    should be (a) mapped to those domains, (b) checked for coverage gaps against
    the aggregated functionality, and (c) consolidated into a canonical, per-
    domain test layer rather than left split by now-archived changes.
- Drivers/constraints:
  - Reuse existing infra, not a parallel system: the canonical domain map
    (`docs/ai/docs-canon.map.json`), frontmatter/provenance model, docs-audit,
    index generator, HITL gate, and `aai-tdd` RED-GREEN-REFACTOR cycle.
  - Idempotent, re-runnable, drift-aware — same contract as docs-canon.
  - Human-owned domain boundaries; tool proposes, operator approves.
  - Tests must remain runnable by the project's existing runners (Pester `.Tests.ps1`,
    bash `test-*.sh`, the `tests/skills/test-framework.sh` harness).

## Proposal
- Recommended option: **Two-phase test canonicalization skill (`aai-test-canon`),
  structurally twinning `aai-docs-canon`, anchored on the canonical domain map.**
  - **Phase 1 — Analyze & propose (HUMAN gate).** Parse existing tests and the
    canonical domain layer. Build a **traceability matrix**: map each existing
    test → canonical domain(s) → acceptance criteria/intent it exercises. Emit a
    **coverage gap report**: criteria described in `docs/canonical/<domain>.md`
    with no covering test. Cluster a proposed per-domain test map. Write a
    machine-readable proposal (e.g. `docs/ai/test-canon.proposal.json`) and HALT
    for operator approval. Phase 1 NEVER moves or writes tests.
  - **Phase 2 — Synthesize & canonicalize (auto, after approval).** Against the
    approved map (`docs/ai/test-canon.map.json`, `"approved": true`):
    consolidate the contributing tests into a canonical per-domain test layer
    (e.g. `tests/canonical/<domain>.*`), MOVE (tracked git move) the originals
    into an archive (e.g. `tests/_archive/`) with a back-link, and for each
    uncovered acceptance criterion **scaffold a failing/pending test stub (RED)**
    tagged to the domain + criterion, then hand off to `aai-tdd` to implement
    GREEN. Record source hashes for drift; re-run is idempotent and reports
    drift (changed source test or changed canonical doc criteria) without
    silently overwriting.
- Rationale:
  - Mirrors a design the project already trusts and has tooling for, minimizing
    new concepts and review surface.
  - The matrix-first phase gives an immediate, low-risk win (coverage visibility)
    even before any test is moved; the layer phase delivers the actual
    consolidation once boundaries are approved.
  - Scaffolding failing stubs (vs. report-only or full synthesis) bridges cleanly
    into the existing TDD workflow: the tool guarantees a RED for every gap and
    hands authorship of GREEN to `aai-tdd`, keeping the tool from inventing
    plausible-but-wrong assertions.

## Alternatives Considered
- Option A — Traceability matrix + gap report only (no test moves):
  - Pros: lowest risk, fast; never touches test files; pure visibility.
  - Cons: tests stay fragmented and change-anchored; no canonical test layer;
    doesn't realize the "aggregate + sync with canonical docs" goal.
- Option B — Canonical test layer only (skip the matrix phase):
  - Pros: directly produces the consolidated layer.
  - Cons: no HITL-gated coverage view before moving files; harder to trust
    domain assignment; weaker parallel with docs-canon's two-phase gate.
- Gap handling — Report only vs. Scaffold failing stubs vs. Full synthesis:
  - Report only: human writes every test; safe but slow, no enforcement.
  - **Scaffold failing stubs (chosen):** guarantees a RED per gap, integrates
    with `aai-tdd`, no fabricated assertions.
  - Full synthesis: agent authors complete tests; highest power but high risk of
    confidently-wrong tests passing/failing for the wrong reasons.

## Consequences
- Technical impact:
  - New skill `aai-test-canon` + prompt (`.aai/SKILL_TEST_CANON.prompt.md`) and a
    deterministic CLI (e.g. `.aai/scripts/test-canon.mjs`) for parse/cluster/
    move/drift, paralleling `docs-canon.mjs`.
  - New artifacts: `tests/canonical/`, `tests/_archive/`, `docs/ai/test-canon.{proposal,map}.json`,
    a coverage matrix report (location TBD — likely `docs/ai/reports/`).
  - Depends on `docs/canonical/` existing → soft prerequisite that `aai-docs-canon`
    has run (degrade-and-report if absent).
- Operational impact:
  - New role/skill in the workflow; HITL gate between phases; `aai-tdd` consumes
    scaffolded stubs.
  - CI may gate on the coverage matrix (e.g. fail on new uncovered criteria) —
    out of scope for this RFC, noted as a follow-up.
- Migration/compatibility notes:
  - Moving tests into `tests/canonical/` must keep them discoverable by existing
    runners (`test-framework.sh`, Pester discovery, ps1-quality workflow). Path/
    glob updates may be required; tracked git moves preserve history.
  - Originals archived, never deleted; bidirectional back-links as in docs-canon.

## Risks
- Primary risks and mitigations:
  - **Mapping tests → acceptance criteria is fuzzy.** Mitigate: HITL approval of
    the matrix before any move; conservative `unclear` bucket.
  - **Breaking test discovery on move.** Mitigate: Phase 2 verifies the canonical
    suite still runs green via existing runners before archiving originals; gate
    on the runner exit code.
  - **Scaffolded stubs left perpetually pending.** Mitigate: stubs are tagged and
    surfaced in the matrix/gap report and (optionally) CI, so they can't silently
    rot.
  - **Drift between canonical docs and canonical tests.** Mitigate: drift mode
    keyed on both source-test hashes and canonical-doc criteria hashes, mirroring
    docs-canon `--drift` / `--resync`.

## Open Questions
- Items requiring decision or clarification:
  - Exact location/format of the canonical test layer (`tests/canonical/<domain>/`
    vs. single file per domain) and how it coexists with `tests/skills/` runner
    conventions.
  - How acceptance criteria are extracted from `docs/canonical/<domain>.md` for
    coverage matching (structured frontmatter vs. parsing the five layer sections).
  - Stub format per runner (Pester `It ... -Skip` / `-Pending` vs. bash skip
    convention) and the tag schema linking stub → domain → criterion.
  - Whether CI gating on the coverage matrix is in-scope for the first spec or a
    follow-up.
  - Should this hard-require `docs/canonical/` (block if docs-canon hasn't run) or
    degrade to mapping against raw docs?

## Approvals
- Required approvers (roles/names): Project maintainer (ales@holubec.net).

## Notes
- This skill reuses existing docs/test infra (canonical domain map, frontmatter
  model, docs-audit, index generator, HITL, `aai-tdd`) rather than inventing a
  parallel system. It does not define workflow; it is a re-runnable maintenance
  skill, the test-side twin of `aai-docs-canon`.

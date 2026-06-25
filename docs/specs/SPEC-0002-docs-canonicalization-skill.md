---
id: SPEC-0002
type: spec
status: done
links:
  requirement: RFC-0003
  rfc: RFC-0003
  pr: []
  commits: []
---

# SPEC-0002 — Docs Canonicalization Skill (`aai-docs-canon`) — RFC-0003 implementation

## Links
- Requirement / decision: docs/rfc/RFC-0003-docs-canonicalization-skill.md
- Related decision: docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md (hygiene model this extends)
- Predecessor spec (infra this extends): docs/specs/SPEC-0001-docs-hygiene-and-drift-audit.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: as per template

## Scope summary

Deliver a new re-runnable AAI skill `aai-docs-canon` that consolidates layered
project documentation into a canonical, function-categorized "current state"
layer in `docs/canonical/`, while preserving and back-linking the originals in
`docs/_archive/`. The skill runs as a two-phase, idempotent pipeline:

- Phase 1 (analyze + propose, HUMAN gate): parse a target doc set, build a
  supersession/dependency graph, and emit an AI-proposed domain map for human
  approval (HITL). No file writes/moves before approval.
- Phase 2 (synthesize + canonicalize, AUTO): for each approved domain, synthesize
  one canonical doc with FIXED layer sections, move contributing originals to
  `docs/_archive/` with a forward `canonical:` pointer, then regenerate the index
  and run the strict docs audit on all outputs.

The change has two parts:
1. A shared-library / schema extension to the existing docs infra
   (`docs-model.mjs`, `docs-audit-core.mjs`, `generate-docs-index.mjs`) so the
   new doc types (`canonical`, `archived`) and frontmatter fields
   (`domain`, `sources`, `canonical`) are first-class and validated.
2. A deterministic skill harness: helper script(s) under `.aai/scripts/`, the
   skill manifest `.claude/skills/aai-docs-canon/SKILL.md`, the role prompt
   `.aai/SKILL_DOCS_CANON.prompt.md`, and a persisted approved domain map.

Scope boundary: the AI/LLM-driven *prose synthesis* of a canonical doc's body is
performed by the agent following the prompt, NOT by deterministic code, and is
therefore verified at the contract/structure level (required sections present,
provenance complete, no superseded content leaked) rather than by asserting exact
generated prose. All graph-building, classification, file-move, frontmatter
rewrite, drift-detection, and validation logic IS deterministic code and is
unit/integration tested.

## Out of scope (this spec)
- A `--review` per-doc merge-diff approval mode (RFC Open Question). Recorded as a
  fast-follow; not gating freeze. See Residual risks.
- Splitting an oversized domain into child files under `docs/canonical/<domain>/`
  (RFC Open Question). v1 emits a single doc per domain; the threshold-split is
  deferred. See Residual risks.
- Modifying the external reference corpus at
  `/Users/ales/Projects/FiledHockey/fh-workspace/docs` (READ-ONLY example only).

## Implementation strategy
- Strategy: hybrid
- Rationale: The schema/graph/file-move/frontmatter-rewrite/drift code touches
  data integrity (irreversible-feeling git moves, machine-readable supersession,
  shared parser consumed by two existing validated scripts) and must be authored
  TDD with observed RED states — a parser or move bug silently corrupts the docs
  layer. The skill manifest, role prompt, conventional directories, and INDEX
  wiring are low-risk glue/config better delivered in a focused loop pass. Hybrid
  lets the risky deterministic core be RED-GREEN-REFACTOR while the wiring is not
  ceremonially test-first. Per-test discipline is recorded in the Test Plan
  (TDD-gated tests are marked; loop tests are marked).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: This modifies the SHARED, already-shipped docs schema
  (`docs-model.mjs` enums consumed by both `docs-audit.mjs` and
  `generate-docs-index.mjs`, the SPEC-0001 surface) and adds a new skill plus
  new conventional directories — a multi-module change (schema lib + audit core +
  index generator + new skill harness + tests) with a destructive-feeling file
  move stage. Isolation protects `main`'s green docs-audit gate while the schema
  churns, and the work is PR-bound. Not `required` because the changes are
  additive (new enum members, new scan dirs) rather than a migration of existing
  data, and can be reverted cleanly.
- User decision: undecided
- Base ref: main
- Worktree branch/path: <set at implementation preparation if worktree chosen>
- Inline review scope (if inline chosen instead): `.aai/scripts/lib/docs-model.mjs`,
  `.aai/scripts/lib/docs-audit-core.mjs`, `.aai/scripts/generate-docs-index.mjs`,
  `.aai/scripts/docs-canon.mjs` (+ any new lib under `.aai/scripts/lib/`),
  `.claude/skills/aai-docs-canon/SKILL.md`, `.aai/SKILL_DOCS_CANON.prompt.md`,
  `tests/skills/test-aai-docs-canon.sh`, `docs/specs/SPEC-0002-*.md`,
  `docs/ai/STATE.yaml`.

## Acceptance Criteria Mapping

RFC-0003 has no numbered AC list; its binding requirements are the Phase 1/2
pipeline steps (RFC steps 1-9), the technical-impact bullets, and the explicit
intake decisions in Notes. Each is mapped below to a measurable Spec-AC.

- Maps to: RFC-0003 Technical impact (new doc type + frontmatter fields) and step 7/8
  - Spec-AC-01: The docs schema recognizes doc types `canonical` and `archived`
    (added to `DOC_TYPE_ENUM` in `.aai/scripts/lib/docs-model.mjs`), and the
    audit's type validation treats them as known (no type warning / no
    `--strict-types` violation) for docs carrying those types.
  - Verification: unit test asserts `DOC_TYPE_ENUM` contains both; integration
    test runs `docs-audit.mjs --check --strict --strict-types` over a fixture
    `docs/canonical/x.md` (`type: canonical`) and a `docs/_archive/y.md`
    (`type: archived`) and asserts exit 0 with no type-warning lines for them.

- Maps to: RFC-0003 step 7 (canonical provenance frontmatter)
  - Spec-AC-02: A canonical doc requires frontmatter `type: canonical`,
    `domain: <slug>` (non-empty, lowercased, matches `^[a-z0-9][a-z0-9-]*$`), and
    `sources:` (a non-empty list of contributing original doc paths). A canonical
    doc missing `domain` or with an empty `sources` list is reported as a schema
    violation by `docs-audit.mjs` (counts toward hardFail under `--strict`).
  - Verification: unit tests for the canonical-frontmatter validator (valid;
    missing domain; bad domain slug; empty sources). Integration test:
    `docs-audit.mjs --check --strict` exits 1 and prints a violation line naming
    the bad canonical fixture; exits 0 on the valid one.

- Maps to: RFC-0003 step 8 (originals moved + machine-readable back-pointer)
  - Spec-AC-03: Phase 2 moves each contributing original into `docs/_archive/`
    preserving its relative path, sets its frontmatter `status: archived`, and
    adds `canonical: docs/canonical/<domain>.md`. The forward pointer resolves to
    an existing canonical file, and every path in that canonical's `sources:`
    list resolves to an existing archived file (bidirectional integrity).
  - Verification: integration test on a fixture corpus runs Phase 2 and asserts:
    (a) each original now lives under `docs/_archive/<orig-rel-path>`, (b) its
    `status` == `archived` and `canonical` points to an existing file, (c) every
    `sources:` entry in the canonical resolves to an existing archived file. A
    link-integrity unit test asserts a dangling `canonical:` or `sources:` entry
    is flagged.

- Maps to: RFC-0003 step 2 (supersession/dependency graph)
  - Spec-AC-04: A deterministic graph builder ingests a doc set and produces, for
    each node: the umbrella-ID group (N files sharing one `id`), `status:
    superseded` membership, detected free-text markers (`SUPERSEDED BY`,
    `DEPRECATED`, `addendum`), and cross-references (PRD/SPEC/ISSUE IDs found in
    body). The builder is pure (no writes) and deterministic (same input ⇒
    byte-identical graph output).
  - Verification: unit tests over fixtures: (a) 3 files sharing `id: SPEC-X` are
    grouped under one umbrella node; (b) a body line `SUPERSEDED BY SPEC-Y` adds a
    supersession edge; (c) `status: superseded` is recorded; (d) cross-ref IDs in
    body become dependency edges; (e) running the builder twice on the same input
    yields identical serialized output (determinism).

- Maps to: RFC-0003 steps 3-4 (AI-proposed domain map, HUMAN approval gate / HITL)
  - Spec-AC-05: Phase 1 emits a domain-map proposal artifact (machine-readable,
    written under `docs/ai/`) listing proposed domains, the source docs assigned
    to each, a confidence note, and an explicit `unclear` bucket; and HALTS for
    human approval. No file under `docs/canonical/` or `docs/_archive/` is
    created or moved during Phase 1 (gate enforced).
  - Verification: integration test runs Phase 1 against a fixture and asserts:
    (a) the proposal artifact exists and parses (contains `domains`, each with
    `sources` + `confidence`, plus an `unclear` key); (b) `docs/canonical/` and
    `docs/_archive/` are unchanged/empty (no writes pre-approval); (c) the run
    reports a "human approval required" status / non-completed Phase-1 exit
    signal. Unit test asserts the gate refuses to enter Phase 2 without an
    `approved: true` map.

- Maps to: RFC-0003 step 5 + Notes (fixed hybrid layer sections) + step 6 (harvest)
  - Spec-AC-06: Each synthesized canonical doc contains, in order, the five fixed
    layer sections as level-2 headings — `## Overview / Intent`, `## UI`,
    `## Processes / Behavior`, `## Data model`, `## Superseded decisions` — and
    the `## Superseded decisions` section contains, for every superseded
    contributing source, a back-link to that source (harvested audit trail). No
    body content classified `superseded` appears outside the
    `## Superseded decisions` section.
  - Verification: integration test: after Phase 2 over a fixture whose domain
    includes one superseded doc, assert the canonical doc contains all five
    section headings in order, and that the superseded source's ID appears as a
    link only within `## Superseded decisions`. Unit test on the section-contract
    validator (all five present/ordered ⇒ ok; missing one ⇒ violation).

- Maps to: RFC-0003 "Re-run / incremental mode" + drift reporting
  - Spec-AC-07: On re-run, a domain whose sources are byte-unchanged since last
    synthesis is left untouched (its canonical file is not rewritten — verified by
    unchanged mtime/content hash), and any source doc that changed after its
    canonical was last synthesized is reported as DRIFT (source-vs-canonical
    divergence) without silently overwriting. A re-run with zero changes is a
    no-op (idempotent: second run produces byte-identical canonical files and
    archive set).
  - Verification: integration test: run Phase 2, snapshot canonical files; re-run
    with no source changes ⇒ assert byte-identical canonical files (idempotence).
    Then mutate one archived/source doc and re-run ⇒ assert that domain is flagged
    DRIFT in the report and the canonical is NOT silently rewritten. Unit test on
    the drift comparator (changed-source ⇒ drift; unchanged ⇒ clean).

- Maps to: RFC-0003 step 9 (index surfaces canonical layer; archive preserved-not-active)
  - Spec-AC-08: `generate-docs-index.mjs` indexes `docs/canonical/` (canonical
    docs appear in INDEX with their `domain` and `sources` count) and treats
    `docs/_archive/` as preserved-but-not-active (archived docs are NOT listed in
    the Active/Drafts sections; they appear in a dedicated Archived/Canonical
    grouping or are explicitly excluded from active counts). INDEX generation
    remains idempotent (second run byte-identical).
  - Verification: integration test: with fixture canonical + archived docs
    present, run `generate-docs-index.mjs` and assert (a) the canonical doc's ID
    appears in INDEX, (b) the archived doc does NOT appear in Active/Drafts, (c) a
    second run produces a byte-identical INDEX.md. Unit test asserts the scan-dir
    set includes `docs/canonical` and that the archive dir is classified
    not-active.

- Maps to: RFC-0003 step 9 (strict audit gates outputs) + EXCLUDE_DIRS seam
  - Spec-AC-09: After a Phase 2 run, `docs-audit.mjs --check --strict` over the
    produced `docs/canonical/` and `docs/_archive/` trees exits 0 (CLEAN): no new
    orphans, no schema violations, archived docs are not mis-classified as
    orphans/false-done. The audit core's directory handling is reconciled so the
    chosen archive directory name (`_archive`) is consistently treated as
    preserved (either excluded from active scan or classified as `superseded`/
    archived, not orphan).
  - Verification: integration test runs the full Phase-2 pipeline then
    `docs-audit.mjs --check --strict --no-event` and asserts exit 0 and verdict
    CLEAN. A targeted unit/integration test asserts an `archived` doc in
    `docs/_archive/` is NOT counted as a new orphan (this exercises the
    `EXCLUDE_DIRS`/`_archive` reconciliation seam explicitly).

- Maps to: RFC-0003 Technical impact (new skill following existing skill pattern)
  - Spec-AC-10: The skill ships following the existing pattern: manifest
    `.claude/skills/aai-docs-canon/SKILL.md` with valid frontmatter
    (`name: aai-docs-canon`, non-empty `description`) and a `<SUBAGENT-STOP>`
    block, delegating to `.aai/SKILL_DOCS_CANON.prompt.md`, which exists and
    documents both phases, the HITL gate, the target-glob input (default
    `{issues,requirements,specs,rfc}`), and the re-run/drift behavior. The skill
    name does not collide with any existing skill.
  - Verification: test asserts both files exist; SKILL.md frontmatter parses with
    the correct `name`; the prompt references Phase 1, Phase 2, HITL approval, the
    default target glob, and drift; and `.claude/skills/aai-docs-canon/` is the
    only directory with that name.

- Maps to: RFC-0003 Test/quality expectation (skill behavior covered by suite)
  - Spec-AC-11: A shell test suite `tests/skills/test-aai-docs-canon.sh` exists,
    follows the repo convention (isolated fixture repo; exit codes 0 pass / 1 fail
    / 42 skip), exercises Phase 1 (proposal + gate), Phase 2 (synthesis + move +
    back-links), re-run idempotence, drift, and the audit/index integration, and
    passes end-to-end.
  - Verification: run `bash tests/skills/test-aai-docs-canon.sh`; assert exit 0
    and PASS lines covering Phase 1 gate, Phase 2 move/back-link, idempotence,
    drift, and index/audit integration.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | `canonical` + `archived` doc types known to schema; no type warnings        | done | TEST-101/102 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-02 | Canonical frontmatter (`domain` slug + non-empty `sources`) validated       | done | TEST-103/104 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-03 | Originals moved to `docs/_archive/`, `status: archived` + `canonical:` ptr  | done | TEST-105/106/305 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-04 | Deterministic supersession/dependency graph builder (pure, repeatable)      | done | TEST-107/108/109/110 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-05 | Phase 1 emits domain-map proposal + HALTS on HITL gate; no pre-approval writes | done | TEST-111/112/113 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-06 | Fixed five layer sections present/ordered; superseded harvested + isolated  | done | TEST-114/115 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-07 | Re-run idempotent; changed source ⇒ DRIFT, never silent overwrite           | done | TEST-116/117/118 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-08 | Index surfaces `docs/canonical/`; `docs/_archive/` preserved-not-active     | done | TEST-301/302/306 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-09 | Strict audit CLEAN over outputs; `_archive` not mis-classified as orphan    | done | TEST-303/304 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-10 | Skill manifest + role prompt ship per existing pattern; no name collision   | done | TEST-201/202 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |
| Spec-AC-11 | `tests/skills/test-aai-docs-canon.sh` covers the pipeline and passes        | done | TEST-203 PASS; suite exit 0 (2026-06-25T15:05Z); docs/ai/tdd/green-20260625T150223Z.log | — | Confirmed by Validation (claude-sonnet-4-6) |

Status values: planned | implementing | done | deferred | blocked | rejected
(gate semantics per template — done requires non-empty Evidence).

## Implementation plan

Components/modules affected:
- `.aai/scripts/lib/docs-model.mjs` — add `canonical`, `archived` to
  `DOC_TYPE_ENUM`; add a canonical-frontmatter validator (domain slug + non-empty
  `sources` list parse); list-valued frontmatter parsing for `sources:`.
- `.aai/scripts/lib/docs-audit-core.mjs` — reconcile archive-directory handling
  (`_archive`) so archived docs are preserved-not-orphan; validate canonical/
  archived provenance; surface `canonical:`/`sources:` link-integrity.
- `.aai/scripts/generate-docs-index.mjs` — add `docs/canonical` to scan dirs;
  classify `docs/_archive` as preserved-not-active; render a canonical grouping.
- `.aai/scripts/docs-canon.mjs` (new) + optional `.aai/scripts/lib/docs-canon-core.mjs`
  — graph builder (Spec-AC-04), Phase 1 proposal emitter + gate (Spec-AC-05),
  Phase 2 move/back-link/section-contract writer (Spec-AC-03/06), drift comparator
  + idempotent re-run (Spec-AC-07).
- `.claude/skills/aai-docs-canon/SKILL.md` (new), `.aai/SKILL_DOCS_CANON.prompt.md`
  (new) — skill harness (Spec-AC-10).
- `tests/skills/test-aai-docs-canon.sh` (new) — suite (Spec-AC-11).
- Persisted approved domain map (e.g. `docs/ai/docs-canon.map.yaml` or equivalent)
  — stable across re-runs (Spec-AC-05/07).

Data flows:
- Phase 1: target glob ⇒ parse frontmatter+body ⇒ graph builder ⇒ cluster ⇒
  write proposal artifact ⇒ HALT (HITL).
- Approval: human edits/approves map ⇒ persisted approved map (`approved: true`).
- Phase 2: approved map ⇒ per-domain synthesis (agent prose, code-enforced
  sections) ⇒ write `docs/canonical/<domain>.md` ⇒ move sources to
  `docs/_archive/` + rewrite frontmatter ⇒ regenerate index ⇒ strict audit.
- Re-run: hash sources vs last-synthesis ⇒ unchanged domains skipped, changed ⇒
  DRIFT report.

Edge cases:
- Umbrella IDs (N files, one `id`) must all map into the same domain group.
- A source assigned to two domains (ambiguous) ⇒ must go to `unclear`, not be
  silently duplicated/moved twice.
- `_archive` vs `archive` directory-name mismatch with current `EXCLUDE_DIRS`
  (this is a known seam — see Seam analysis).
- Re-run must not re-append `## Superseded decisions` content (idempotence).
- A source already under `docs/_archive/` must not be re-archived.

## Seam analysis

This change shares state with features it does not own. Each seam below has at
least one INTEGRATION test that crosses it end-to-end (produce on one side,
assert the real result on the other), not two mocked unit tests.

- SEAM-1 (schema enum ⇄ two consumers): `DOC_TYPE_ENUM` in `docs-model.mjs` is
  read by BOTH `docs-audit.mjs` and `generate-docs-index.mjs`. Adding
  `canonical`/`archived` must not break either consumer. Crossed by TEST-301
  (audit accepts new types) and TEST-302 (index renders canonical) — same enum
  change asserted on both real consumers.
- SEAM-2 (Phase 2 writer ⇄ docs-audit gate): Phase 2 produces files that the
  audit then judges. A move/frontmatter bug surfaces only when the real audit runs
  over real produced output. Crossed by TEST-303: run full Phase 2, then real
  `docs-audit.mjs --check --strict` ⇒ exit 0 CLEAN.
- SEAM-3 (`_archive` directory ⇄ audit `EXCLUDE_DIRS`): the RFC chose
  `docs/_archive/` but the audit core excludes `archive` (no underscore). An
  archived doc could be scanned and mis-flagged as an orphan. Crossed by TEST-304:
  place a real `archived` doc in `docs/_archive/` and assert the real audit does
  NOT count it as a new orphan.
- SEAM-4 (canonical ⇄ archive back-links): the canonical's `sources:` list and
  each archived doc's `canonical:` pointer are produced by Phase 2 and consumed by
  link-integrity / future tooling. Crossed by TEST-305: after Phase 2, assert
  every `sources:` entry resolves to an archived file AND every archived
  `canonical:` resolves to the canonical (bidirectional, end-to-end).
- SEAM-5 (Phase 2 writer ⇄ index generator): canonical docs produced by Phase 2
  must appear in the regenerated INDEX and archived docs must drop out of active
  sections. Crossed by TEST-306: run Phase 2 then `generate-docs-index.mjs` and
  assert canonical present / archived not in Active.

## Test Plan

Type legend: unit (pure function), int (integration: real scripts/files/git),
e2e (full skill suite). Discipline: TDD = RED-proof required before GREEN; loop =
covered in focused pass (still RED-proofed where it gates an AC).

| Test ID  | Spec-AC    | Type | File path (expected)                      | Description                                                                 | Discipline | Status  |
|----------|------------|------|-------------------------------------------|-----------------------------------------------------------------------------|------------|---------|
| TEST-101 | Spec-AC-01 | unit | tests/skills/test-aai-docs-canon.sh       | `DOC_TYPE_ENUM` contains `canonical` and `archived`                         | tdd        | green   |
| TEST-102 | Spec-AC-01 | int  | tests/skills/test-aai-docs-canon.sh       | `docs-audit --check --strict --strict-types` over canonical+archived fixtures ⇒ exit 0, no type warnings | tdd  | green   |
| TEST-103 | Spec-AC-02 | unit | tests/skills/test-aai-docs-canon.sh       | canonical-frontmatter validator: valid / missing domain / bad slug / empty sources | tdd | green   |
| TEST-104 | Spec-AC-02 | int  | tests/skills/test-aai-docs-canon.sh       | `docs-audit --check --strict` exits 1 + violation line on bad canonical; 0 on valid | tdd | green   |
| TEST-105 | Spec-AC-03 | int  | tests/skills/test-aai-docs-canon.sh       | Phase 2 moves originals to `docs/_archive/`, sets `status: archived`         | tdd        | green   |
| TEST-106 | Spec-AC-03 | unit | tests/skills/test-aai-docs-canon.sh       | dangling `canonical:` or `sources:` entry flagged by link-integrity check    | tdd        | green   |
| TEST-107 | Spec-AC-04 | unit | tests/skills/test-aai-docs-canon.sh       | umbrella-ID grouping: 3 files, one `id` ⇒ one node                          | tdd        | green   |
| TEST-108 | Spec-AC-04 | unit | tests/skills/test-aai-docs-canon.sh       | body `SUPERSEDED BY` / `DEPRECATED` / `addendum` markers ⇒ supersession edges | tdd      | green   |
| TEST-109 | Spec-AC-04 | unit | tests/skills/test-aai-docs-canon.sh       | cross-ref IDs in body ⇒ dependency edges; `status: superseded` recorded      | tdd        | green   |
| TEST-110 | Spec-AC-04 | unit | tests/skills/test-aai-docs-canon.sh       | graph builder is deterministic: two runs ⇒ byte-identical serialized output  | tdd        | green   |
| TEST-111 | Spec-AC-05 | int  | tests/skills/test-aai-docs-canon.sh       | Phase 1 writes domain-map proposal (domains+sources+confidence+unclear)      | tdd        | green   |
| TEST-112 | Spec-AC-05 | int  | tests/skills/test-aai-docs-canon.sh       | Phase 1 gate: `docs/canonical/` and `docs/_archive/` untouched pre-approval  | tdd        | green   |
| TEST-113 | Spec-AC-05 | unit | tests/skills/test-aai-docs-canon.sh       | Phase 2 refuses to run without `approved: true` map                          | tdd        | green   |
| TEST-114 | Spec-AC-06 | unit | tests/skills/test-aai-docs-canon.sh       | section-contract validator: all five ordered ⇒ ok; missing one ⇒ violation   | tdd        | green   |
| TEST-115 | Spec-AC-06 | int  | tests/skills/test-aai-docs-canon.sh       | synthesized canonical has 5 ordered sections; superseded source linked ONLY in `## Superseded decisions` | tdd | green   |
| TEST-116 | Spec-AC-07 | int  | tests/skills/test-aai-docs-canon.sh       | re-run with no source change ⇒ byte-identical canonical files (idempotent)   | tdd        | green   |
| TEST-117 | Spec-AC-07 | int  | tests/skills/test-aai-docs-canon.sh       | mutate one source ⇒ domain flagged DRIFT, canonical NOT silently rewritten   | tdd        | green   |
| TEST-118 | Spec-AC-07 | unit | tests/skills/test-aai-docs-canon.sh       | drift comparator: changed-source ⇒ drift; unchanged ⇒ clean                  | tdd        | green   |
| TEST-119 | Spec-AC-03 | unit | tests/skills/test-aai-docs-canon.sh       | post-review WARNING-1: unsafe map (source in 2 domains / dest collision / pre-existing dest) ⇒ `runPhase2` aborts BEFORE any mutation, no partial tree | tdd | green   |
| TEST-120 | Spec-AC-07 | int  | tests/skills/test-aai-docs-canon.sh       | post-review WARNING-2: `--phase2 --resync` re-synthesizes a drifted domain from current archived sources and re-baselines hashes ⇒ `--drift` clean after | tdd | green   |
| TEST-301 | Spec-AC-08 | int  | tests/skills/test-aai-docs-canon.sh       | SEAM-1: index includes `docs/canonical`; canonical doc ID appears in INDEX   | tdd        | green   |
| TEST-302 | Spec-AC-08 | int  | tests/skills/test-aai-docs-canon.sh       | archived doc NOT in Active/Drafts; INDEX 2nd run byte-identical (idempotent)  | loop       | green   |
| TEST-303 | Spec-AC-09 | int  | tests/skills/test-aai-docs-canon.sh       | SEAM-2: full Phase 2 then `docs-audit --check --strict --no-event` ⇒ exit 0 CLEAN | tdd   | green   |
| TEST-304 | Spec-AC-09 | int  | tests/skills/test-aai-docs-canon.sh       | SEAM-3: `archived` doc in `docs/_archive/` NOT counted as new orphan         | tdd        | green   |
| TEST-305 | Spec-AC-03 | int  | tests/skills/test-aai-docs-canon.sh       | SEAM-4: bidirectional links resolve (`sources:`↔`canonical:`) end-to-end     | tdd        | green   |
| TEST-306 | Spec-AC-08 | int  | tests/skills/test-aai-docs-canon.sh       | SEAM-5: Phase 2 output appears in regenerated INDEX                          | tdd        | green   |
| TEST-201 | Spec-AC-10 | int  | tests/skills/test-aai-docs-canon.sh       | SKILL.md exists, frontmatter `name: aai-docs-canon`, `<SUBAGENT-STOP>` present | loop      | green   |
| TEST-202 | Spec-AC-10 | int  | tests/skills/test-aai-docs-canon.sh       | role prompt exists; references Phase 1/2, HITL, default glob, drift; no name collision | loop | green   |
| TEST-203 | Spec-AC-11 | e2e  | tests/skills/test-aai-docs-canon.sh       | post-review WARNING-3: self-contained e2e asserts real artifacts — 5 ordered sections, superseded harvested, originals archived w/ back-pointer, index surfaces canonical, strict audit CLEAN, links resolve | tdd | green   |

Notes:
- Every Spec-AC has at least one TEST entry (AC-01:101/102, AC-02:103/104,
  AC-03:105/106/305, AC-04:107-110, AC-05:111-113, AC-06:114/115, AC-07:116-118,
  AC-08:301/302/306, AC-09:303/304, AC-10:201/202, AC-11:203).
- All five seams (SEAM-1..5) have a crossing integration test (301,303,304,305,306).
- RED-proof obligation: every `tdd`-disciplined test must be observed FAILING
  before its passing counts as evidence. `loop` tests that gate an AC
  (201,202,203,302) must also be RED-proofed (e.g. run before the file exists).
- Test IDs are stable; do not renumber after freeze. The suite is a single shell
  file per repo convention, but logical units/integration cases are tracked by ID.
- Post-review remediation (code review, 2026-06-25):
  - WARNING-1 — the Phase-2 archive-move stage gained a fail-fast pre-flight
    (`validatePhase2Plan`) and an `archiveSource` overwrite guard so a malformed
    operator-approved map (one source under two domains, archive-destination
    collision, or a pre-existing destination) aborts before any filesystem
    mutation instead of crashing mid-loop with a partially archived tree.
    Covered by TEST-119 (RED-proofed).
  - WARNING-2 — added a CLI `--resync` mode (`runPhase2({ resync })`) that
    re-synthesizes a DRIFTED domain from its current archived sources and
    re-baselines the drift hashes, so a drift is resolvable from the CLI without
    hand-editing the map JSON. The first synthesis now persists
    `supersededArchived` so resync can re-harvest superseded links. Covered by
    TEST-120.
  - WARNING-3 — TEST-203 (AC-11 e2e gate) replaced its assertion-free
    reachability marker with a self-contained end-to-end run that asserts real
    artifacts (five ordered sections, superseded harvest, archived back-pointer,
    index surfacing, strict-audit CLEAN, link integrity).

## Verification
- Primary command: `bash tests/skills/test-aai-docs-canon.sh` (exit 0; PASS lines
  per logical TEST-xxx).
- Schema/infra regression: `bash tests/skills/test-aai-docs-audit.sh` (exit 0 —
  proves the enum/scan changes did not break SPEC-0001).
- Self-check on this spec + outputs:
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0002-docs-canonicalization-skill.md` ⇒ CLEAN.
- Index regen: `node .aai/scripts/generate-docs-index.mjs` ⇒ exit 0; canonical
  fixtures (when present) surfaced, archived not in Active.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  non-empty Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: RFC-0003 / SPEC-0002
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

## Residual risks (seams/AC not fully covered by automated tests)
- Merge fidelity of the LLM-synthesized prose (auto-synthesis losing/inventing
  content) cannot be asserted as exact prose. Mitigation tested instead:
  `sources:` provenance completeness, preserved archived originals, the
  `## Superseded decisions` harvest, section-contract enforcement, and strict
  audit gating. The `--review` per-doc diff mode is deferred (out of scope) as the
  human-facing safety net for this residual.
- Domain-map LLM clustering quality is human-gated (HITL) and the approved map is
  persisted for re-run stability; the *correctness* of the human's chosen
  boundaries is not machine-verifiable and is accepted as operator responsibility.
- Oversized-domain child-file split is deferred; if a real domain exceeds a sane
  single-doc size in v1 it is emitted as one large doc (acceptable per RFC lean).

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.
SPEC-FROZEN: true

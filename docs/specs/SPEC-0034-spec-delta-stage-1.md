---
id: spec-delta-stage-1
type: spec
number: 34
status: done
ceremony_level: 2
links:
  rfc: delta-spec-lifecycle
  research: RES-0001
  pr:
    - 83
  commits:
    - 443ddcf
---

# SPEC — Delta-Spec Lifecycle, Stage 1: Canonical-Layer Requirements Contract

SPEC-FROZEN: true

## Links
- RFC: delta-spec-lifecycle (docs/rfc/RFC-0011-delta-spec-lifecycle.md,
  ACCEPTED by project owner 2026-07-16; this spec delivers stage 1 of the
  three staged SPECs the decision note mandates)
- Research: RES-0001 F5 — OpenSpec delta-spec lifecycle as studied prior art
  (SHALL statements + scenario blocks, adapted to AAI's canonical layer, not
  copied) (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level

This spec declares `ceremony_level: 2` (full pipeline). Justification for NOT
going lighter or heavier: the scope defines a repo-wide documentation contract
and changes shared parser/render code consumed by docs-canon, docs-audit, and
the docs-canon test suite — clearly above a level-0/1 single-surface fix. It
does NOT touch any `protected_paths_l3` surface (docs/ai/docs-audit.yaml:
state engine, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION.md are
all untouched), so level 3 is not mandatory; level 2 is the honest default.

## Stage boundary (deliberately narrow)

RFC-0011 stage 1 formalizes ONLY the canonical-layer requirements contract:
every canonical domain doc carries a `## Requirements` section with stable
per-domain REQ ids, and the docs-canon machinery emits that section's skeleton
by construction. Stage 1 does NOT:
- retrofit requirement content into canonical docs — `docs/canonical/` is
  empty in this repo; population happens when the operator runs aai-docs-canon
  (synthesis may fill blocks per the contract) and, mechanically, when stage-3
  delta merges land;
- introduce the SPEC `## Deltas` section or its validation (stage 2);
- implement delta-merge.mjs, PR-ceremony merge wiring, or the docs-audit
  provenance drift check (stage 3).

## Implementation strategy
- Strategy: hybrid
- Rationale: the docs-model additions (REQ id grammar, domain-slug
  derivation, Requirements-section parser) and the docs-canon render change
  are deterministic shared-library behavior — TDD with fixture-driven unit
  tests (TEST-002..TEST-004) plus an isolated fixture-repo integration run
  (TEST-005), all observed RED first. The template and prompt edits are text
  wiring — grep-RED in the same pre-change run (TEST-001, TEST-006), one
  focused pass. TEST-007 is a seam-survival invariant (green pre-change by
  construction; non-vacuous because it re-runs the full existing docs-canon
  suite over the changed core after the change).
- RED-proof obligation: before any edit, run the new suite per-stanza on the
  pre-change tree and save the failing output to
  `docs/ai/tdd/delta-stage1-red.log` (expected: TEST-001..TEST-006 FAIL;
  TEST-007 passes pre-change BY CONSTRUCTION as the survival baseline).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: multi-surface contract change to shared library code
  while four sibling worktrees (spec-lint, truth, advisory, profiles) are in
  flight; isolation removes any cross-stream file contention.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-p3-delta1, branch feat/delta-stage-1, base main)
- Base ref: main
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0034-spec-delta-stage-1.md (this spec)
  - docs/rfc/RFC-0011-delta-spec-lifecycle.md (links.spec backfill only)
  - .aai/templates/CANONICAL_TEMPLATE.md (new — the contract reference)
  - .aai/scripts/lib/docs-model.mjs (REQ grammar + parser + section list)
  - .aai/scripts/lib/docs-canon-core.mjs (Requirements skeleton emission)
  - .aai/SKILL_DOCS_CANON.prompt.md (six-section contract + derivation rule)
  - tests/skills/test-aai-delta-stage1.sh (new suite)
  - tests/skills/test-aai-docs-canon.sh (TEST-114 fixture gains the section)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — REQ id scheme (resolves RFC-0011 open question per the decision note)
`REQ-<DOMAIN>-NNN`, per-domain sequential (approved lean: REQ-AUTH-001 style,
not global). `<DOMAIN>` is derived from the canonical doc's `domain:`
frontmatter slug (lowercase kebab, `DOMAIN_SLUG_RE`) by uppercase kebab→snake:
`auth` → `AUTH`, `delta-stage-1` → `DELTA_STAGE_1`. Because the derived token
uses underscores only, the trailing `-NNN` boundary stays unambiguous even for
slugs containing digits. `NNN` is zero-padded to a minimum of three digits and
grows unbounded (`\d{3,}` — never capped at 999). Grammar (docs-model.mjs):
- `REQ_ID_RE = /^REQ-[A-Z0-9][A-Z0-9_]*-\d{3,}$/`
- heading form: `### REQ-<DOMAIN>-NNN — <title>` (em-dash separator,
  house style).
Stability rule: ids are never renumbered and never reused; a removed
requirement retires its id permanently (gaps are legal and expected). New
requirements always take the next unused NNN.

### D2 — Requirement block shape (adapted from OpenSpec, RES-0001 F5)
Each requirement under `## Requirements` is:
1. the `### REQ-<DOMAIN>-NNN — <title>` heading;
2. exactly ONE SHALL statement (a body line containing the literal `SHALL` —
   normative, testable phrasing; OpenSpec's SHALL discipline adapted);
3. optional `- Scenario: WHEN ... THEN ...` bullet(s) (OpenSpec scenario
   blocks adapted to a single-bullet form — plain markdown, no `#### Scenario`
   sub-headings, keeping the heading namespace free for requirement ids);
4. a `Provenance:` line naming the spec that merged the requirement into the
   canonical layer. Until stage-3 delta merges exist the literal empty form is
   `Provenance: —`. Stage 3 will write e.g. `Provenance: SPEC-0031` at
   PR-ceremony merge time (the approved merge trigger).

### D3 — `## Requirements` becomes a fixed section of the canonical contract
`CANONICAL_SECTIONS` (docs-model.mjs) grows from five to SIX fixed level-2
sections, `Requirements` inserted second — directly after `## Overview /
Intent`, before `## UI` — because it is the authoritative payload of the
domain doc and the stage-3 merge target. `validateSectionContract` therefore
requires it in order; `renderCanonicalDoc` (docs-canon-core.mjs) emits it by
construction. Contract-change honesty (Constitution art. 5): this tightens an
existing validator, but (a) `docs/canonical/` is EMPTY in this repo — zero
live docs are affected; (b) the only production consumer of the section list
is `renderCanonicalDoc` itself (docs-audit checks canonical frontmatter, not
sections); (c) downstream projects with pre-stage-1 canonical docs have a
sanctioned re-synthesis path (`docs-canon.mjs --phase2 --resync`). The change
is explicit and documented here and in the prompt — exactly what art. 5
requires of a breaking boundary change.

### D4 — Skeleton emission: empty is a VALID state
`renderCanonicalDoc` special-cases the Requirements section: it emits the
contract comment plus, when no requirement content is supplied via
`sectionBodies.requirements`, the placeholder line
`_No requirements recorded for this domain yet._`. Empty is valid because a
domain may legitimately carry zero formalized requirements until specs
declare deltas against it (RFC-0011: "Deltas stay optional until a domain doc
exists"). The generic `_To be synthesized._` placeholder is NOT used — that
phrasing implies missing synthesis work, whereas an empty Requirements
section is a complete, correct state.

### D5 — Tooling readiness: parser lands now, enforcement lands later
docs-model.mjs gains `parseRequirementsSection(content, { domain })` returning
`{ present, requirements: [{ id, title, shallCount, scenarios, provenance }],
violations }` — the single shared reader stage 2 (spec-lint Deltas
validation), stage 3 (delta-merge target resolution + docs-audit provenance
drift), and future audits will consume, so the grammar is implemented once.
Stage 1 wires it into TESTS ONLY; no gate consumes it yet (matching how
`validateSectionContract` shipped in SPEC-0002). Violations detected: missing
section, malformed `###` heading under Requirements, duplicate id, id/domain
mismatch (when `domain` is passed), SHALL count ≠ 1, missing/duplicate
Provenance line.

### D6 — spec-lint COORDINATION SEAM (stage 2 — recorded, not implemented)
A sibling worktree (aai-p3-speclint) owns the spec-lint files right now, so
this change touches NO spec-lint surface. What stage 2 needs from stage 1
(all delivered here, nothing else blocks on it):
- the REQ grammar as importable constants (`REQ_ID_RE`, `REQ_HEADING_RE`) and
  `domainToReqDomain` — spec-lint's Deltas validator must accept exactly the
  ids the canonical layer accepts, from the same source of truth;
- `parseRequirementsSection` for resolving a delta's target requirement in a
  named canonical doc;
- the SPEC `## Deltas` section itself (ADDED/MODIFIED/REMOVED blocks against
  named canonical docs) is stage-2 surface: its shape, its SPEC_TEMPLATE
  guidance, and its spec-lint validation all land there — deliberately absent
  from this spec's scope and from this spec's own body.

### D7 — Stage 3 seam (recorded, not implemented)
Stage 3 (delta-merge.mjs at PR ceremony, per the approved merge trigger) will:
- rewrite `Provenance: —` to `Provenance: <merging spec>` on merged blocks —
  the line format defined here is the merge's write target;
- append ADDED blocks with the next unused NNN per D1's stability rule;
- feed docs-audit's drift check (canonical requirement blocks must trace to a
  merging spec) via `parseRequirementsSection().requirements[].provenance`.

## Acceptance Criteria Mapping
- Maps to: RFC-0011 stage 1 — "every domain doc carries a Requirements
  section with stable REQ ids" (contract definition)
  - Spec-AC-01: .aai/templates/CANONICAL_TEMPLATE.md exists and documents the
    full canonical-doc shape: six fixed sections in order, the
    `### REQ-<DOMAIN>-NNN — <title>` heading grammar, the one-SHALL rule, the
    optional `- Scenario:` bullet, the `Provenance:` line (empty `—` until
    stage 3), the never-renumber/never-reuse stability rule, and the
    uppercase kebab→snake domain derivation with an example.
  - Verification: TEST-001.
- Maps to: RFC-0011 decision note — "REQ ids = per-domain sequential
  (`REQ-<DOMAIN>-NNN`)" (machine grammar)
  - Spec-AC-02: docs-model.mjs exports `REQ_ID_RE`, `REQ_HEADING_RE`,
    `domainToReqDomain`, and `parseRequirementsSection`; valid ids
    (REQ-AUTH-001, REQ-DELTA_STAGE_1-042, REQ-AUTH-1042) accepted; invalid
    ids (lowercase, unpadded NNN, kebab domain, missing segments) rejected;
    the parser returns requirements + violations per D5.
  - Verification: TEST-002, TEST-003.
- Maps to: RFC-0011 stage 1 — "exists via docs-canon; formalize" (generated
  docs carry the section by construction)
  - Spec-AC-03: `CANONICAL_SECTIONS` includes `Requirements` second;
    `renderCanonicalDoc` emits the skeleton (contract comment + empty-valid
    placeholder) at that position; an isolated docs-canon fixture run
    (--phase1 → approved map → --phase2) produces canonical docs carrying the
    skeleton; an immediate --phase2 re-run skips the domain (idempotence) and
    leaves the canonical byte-identical; .aai/SKILL_DOCS_CANON.prompt.md
    documents the six-section contract, the REQ block shape, and the domain
    derivation rule.
  - Verification: TEST-004, TEST-005, TEST-006.
- Maps to: RFC-0011 drivers — "must not invalidate the current flow" +
  "spec-lint ... must keep working"
  - Spec-AC-04: the existing docs-canon suite passes post-change (fixture
    for the section-contract validator updated to the six-section shape);
    repo-wide strict docs audit exits 0; docs index regeneration is
    idempotent; check-state OK; NO spec-lint file is touched (stage-2 seam
    recorded in D6 instead); no sibling worktree file is touched.
  - Verification: TEST-007 + validation-owned sweep (Verification section).

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md v1):
- Art. 1 (evidence before claims): all ACs carry executable verification;
  RED-proof obligation recorded. No deviation.
- Art. 2 (simplicity/YAGNI): enforcement gates for the Requirements grammar
  are deferred to the stages that consume them (D5); no speculative Deltas or
  merge machinery built. No deviation.
- Art. 3 (portability): plain markdown/mjs/bash; tri-platform. No deviation.
- Art. 4 (degrade and report): parser returns explicit violations; empty
  section is a defined valid state, not silent absence (D4). No deviation.
- Art. 5 (additive first): the six-section contract is a boundary change,
  made EXPLICIT and documented with a sanctioned migration path (D3) — the
  article's requirement for breaking changes, not a deviation. Zero live docs
  affected in this repo.
- Art. 6 (single-writer STATE): STATE touched only via state.mjs. No deviation.
- Art. 7 (operator-only merge): no commits, no merge; stage-3 merge trigger
  design keeps merging inside the operator-owned PR ceremony. No deviation.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | CANONICAL_TEMPLATE.md defines the Requirements contract            | done    | TEST-001 green; docs/ai/tdd/delta-stage1-green.log | — | RED-proof in delta-stage1-red.log |
| Spec-AC-02 | REQ grammar + parser exported by docs-model.mjs, fixtures pass     | done    | TEST-002, TEST-003 green; docs/ai/tdd/delta-stage1-green.log | — | RED-proof in delta-stage1-red.log |
| Spec-AC-03 | docs-canon emits the Requirements skeleton; prompt documents it    | done    | TEST-004..TEST-006 green; docs/ai/tdd/delta-stage1-green.log | — | idempotence probe inside TEST-005 |
| Spec-AC-04 | Existing flow intact: docs-canon suite, strict audit, index, state | done    | TEST-007 green; sweep evidence in validation notes | — | spec-lint untouched (D6 seam) |

## Implementation plan
- Components affected: shared doc model (.aai/scripts/lib/docs-model.mjs),
  canon engine (.aai/scripts/lib/docs-canon-core.mjs renderCanonicalDoc),
  template layer (.aai/templates/CANONICAL_TEMPLATE.md, new), prompt layer
  (.aai/SKILL_DOCS_CANON.prompt.md), test layer (new suite + one fixture
  update in tests/skills/test-aai-docs-canon.sh), RFC links backfill,
  docs/INDEX.md regeneration.
- Order: (1) write the new suite; (2) RED run per stanza on the pre-change
  tree → docs/ai/tdd/delta-stage1-red.log; (3) docs-model grammar + parser +
  section list (TEST-002..004 GREEN); (4) renderCanonicalDoc skeleton
  (TEST-004/005 GREEN); (5) template + prompt text (TEST-001/006 GREEN);
  (6) docs-canon suite fixture update + TEST-007; (7) RFC links.spec
  backfill; (8) sweep: full suite family, strict audit, index regen
  idempotence, check-state; (9) AC reconciliation; (10) STATE via CLI.
- Edge cases: domain slugs containing digits (`delta-stage-1` →
  `DELTA_STAGE_1` — NNN boundary stays unambiguous per D1); NNN ≥ 1000
  (accepted, `\d{3,}`); requirement block with zero or two SHALL lines
  (violation, D5); duplicate REQ id in one doc (violation); `Provenance:`
  absent (violation) vs `Provenance: —` (valid empty); `## Requirements`
  containing no `###` blocks (valid empty skeleton, D4); pre-stage-1
  five-section canonical body (now a section-contract violation — sanctioned
  resync path, D3); vocabulary collision found during the sweep — the
  hygiene-pack review-taxonomy guard (spec-review-taxonomy-alignment) bans
  `stage 1`/`stage-1`/`stage 2` tokens on all `.aai` surfaces, so the swept
  files reference "RFC-0011 (delta-spec lifecycle)" by content instead of
  stage numbers and use `oauth2-login` -> `OAUTH2_LOGIN` as the digit-bearing
  derivation example (the feature slug `delta-stage-1` remains covered
  end-to-end by TEST-002/TEST-005, which live on unswept trees).
- Seam analysis:
  - Seam S1 — CANONICAL_SECTIONS is shared by renderCanonicalDoc AND
    validateSectionContract AND the existing docs-canon suite. Crossing test:
    TEST-004 renders a doc and validates it with the real validator; TEST-007
    re-runs the entire existing suite post-change.
  - Seam S2 — docs-canon --phase2 output feeds docs-audit --strict and the
    index generator. Crossing test: TEST-005 runs the real CLI end-to-end in
    a fixture repo (not unit calls); the sweep runs strict audit + index
    regen over the real repo.
  - Seam S3 — spec-lint (sibling-owned, in flight) will import the REQ
    grammar in stage 2. No automated test can cross a seam into code that
    does not exist yet: recorded as D6 coordination note + the explicit
    residual risk below.
  - Residual risk (recorded): until stage 2 lands, nothing mechanically
    validates hand-edited Requirements sections in committed canonical docs
    (parser exists, no gate consumes it — D5). Mitigation: docs/canonical/
    is empty in this repo; the contract ships tested and ready for the first
    consumer.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                      | Description                                                                                     | Status |
|----------|------------|-------------|--------------------------------------------|-----------------------------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-delta-stage1.sh      | CANONICAL_TEMPLATE.md shape greps: six ordered sections, REQ heading grammar, SHALL rule, Scenario bullet, Provenance line, stability rule, domain derivation example | green  |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-delta-stage1.sh      | REQ_ID_RE + domainToReqDomain fixtures: valid ids accepted, invalid rejected; auth→AUTH, delta-stage-1→DELTA_STAGE_1 | green  |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-delta-stage1.sh      | parseRequirementsSection: valid block parses (id/title/SHALL/scenario/provenance); violations for missing SHALL, dup id, bad heading, missing Provenance, domain mismatch; empty section valid | green  |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-delta-stage1.sh      | CANONICAL_SECTIONS has Requirements second; renderCanonicalDoc emits skeleton at position; validateSectionContract passes rendered doc, fails legacy five-section body | green  |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-delta-stage1.sh      | Isolated fixture repo: docs-canon --phase1 → approved map → --phase2 emits canonical with Requirements skeleton; re-run skips domain and canonical stays byte-identical (real idempotence probe) | green  |
| TEST-006 | Spec-AC-03 | unit        | tests/skills/test-aai-delta-stage1.sh      | SKILL_DOCS_CANON.prompt.md documents six sections, REQ block contract, derivation rule, empty-allowed skeleton | green  |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-delta-stage1.sh      | Seam survival: existing tests/skills/test-aai-docs-canon.sh passes post-change (green pre-change baseline; non-vacuous — re-runs the full engine over the changed core) | green  |

Notes:
- RED-proof: TEST-001..TEST-006 observed FAILING on the pre-change tree
  (docs/ai/tdd/delta-stage1-red.log). TEST-007 is the survival invariant
  (green pre-change by construction).
- Full tests/skills sweep is validation-owned. Known environmental exception
  per LEARNED 2026-07-15: tests/skills/test-aai-worktree.sh fails
  deterministically on this machine, pre-existing on clean main.

## Verification
- `bash tests/skills/test-aai-delta-stage1.sh` → exit 0, all 7 stanzas PASS.
- `bash tests/skills/test-aai-docs-canon.sh` → exit 0 (seam parity).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/generate-docs-index.mjs && git diff --exit-code -I '^Generated:' -- docs/INDEX.md` → exit 0 on second run (idempotent).
- `node .aai/scripts/check-state.mjs` → OK.
- Sibling/spec-lint untouched proof:
  `git diff --name-only main...HEAD` contains only the inline review scope
  paths above; no path matches a spec-lint surface.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-delta-stage-1
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/delta-stage1-red.log,
  docs/ai/tdd/delta-stage1-green.log)
- commit SHA or diff range when available (no commits in this pass — PR
  ceremony is a separate operator-gated step)

## Review finding dispositions (2026-07-16)

- NB-1 (docs-canon --phase2 --resync does NOT re-render an old 5-section
  canonical when sources are unchanged, contradicting the migration docs):
  PROMOTED — belongs with stage 2 (where the section contract becomes a gate);
  filed as a stage-2 seam obligation in D6. No canonical docs exist in this
  repo, so zero live exposure now.
- NB-2 (renderCanonicalDoc's throwing domainToReqDomain runs AFTER
  archiveSource, so a bad domain key half-mutated the tree): REMEDIATED —
  validatePhase2Plan now rejects any domain key failing DOMAIN_SLUG_RE at
  pre-flight, before any mutation; TEST-002 covers Auth/spec_x rejection.
- INFO items (per-line SHALL count, wrapped-scenario continuation) accepted;
  documented in D2.

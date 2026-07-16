---
id: spec-delta-stage-2
type: spec
number: 37
status: implementing
ceremony_level: 2
links:
  change: delta-stage-2
  rfc: delta-spec-lifecycle
  pr: []
  commits: []
---

# SPEC — Delta-Spec Lifecycle, Stage 2: SPEC `## Deltas` Section + Shape Validation

SPEC-FROZEN: true

## Links
- RFC: delta-spec-lifecycle (docs/rfc/RFC-0011-delta-spec-lifecycle.md,
  ACCEPTED 2026-07-16; this delivers the second of the three staged SPECs).
- Change: delta-stage-2 (docs/issues/CHANGE-0025-delta-stage-2.md)
- Builds on: spec-delta-stage-1 (docs/specs/SPEC-0034-spec-delta-stage-1.md) —
  consumes its `REQ_ID_RE`, `REQ_HEADING_RE`, `domainToReqDomain`,
  `DOMAIN_SLUG_RE` exports (D6 seam of that spec).
- Technology contract: docs/TECHNOLOGY.md

## Ceremony level
`ceremony_level: 2` (full pipeline). The scope adds a shared parser and a
spec-lint validator consumed repo-wide and edits template/prompt surfaces —
above a level-0/1 single-surface fix. It touches no `protected_paths_l3`
surface (state engine, allocator, pre-commit guards, WORKFLOW.md, CONSTITUTION
untouched), so level 3 is not mandatory. Level 2 is the honest default.

Ceremony justification: not applicable at level 2 (justification line is the
level-0/1 lean-close requirement).

## Stage boundary (deliberately narrow)
This delivers the PRODUCER side only: a SPEC declares intended requirement
changes, and spec-lint checks their SHAPE. It does NOT:
- resolve a delta against the live canonical doc (does the target REQ id exist?
  is the domain doc present?) — cross-doc resolution is the delta merge's job;
- apply anything into `docs/canonical/` or write `Provenance:` — that is
  `delta-merge.mjs` at PR ceremony;
- add the docs-audit provenance drift check.
Those are the third staged SPEC. A spec with no `## Deltas` section is
completely unaffected (the section is optional).

## Implementation strategy
- Strategy: tdd
- Rationale: a new grammar + validator on a governance surface (spec-lint)
  needs RED-proven regression both ways — valid shapes accepted, every malformed
  shape rejected with a precise code, and legacy (no-Deltas) specs untouched.
- RED-proof obligation: before any edit, add the new suite stanzas and the
  spec-lint stanzas and run them on the pre-change tree; save the failing output
  to `docs/ai/tdd/delta-stage2-red.log` (new `parseDeltasSection` tests and the
  spec-lint `delta-*` finding tests FAIL; the legacy-spec-unaffected control and
  the existing-suite survival stanza pass pre-change by construction).

## Isolation and review
- Worktree: /Users/ales/Projects/aai-delta2, branch feat/delta-stage-2, base main.
- Base ref: main (742ff56 at branch creation).
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0037-spec-delta-stage-2.md (this spec)
  - docs/issues/CHANGE-0025-delta-stage-2.md
  - .aai/scripts/lib/docs-model.mjs (new `reqDomainToSlug` + `parseDeltasSection`)
  - .aai/scripts/spec-lint.mjs (new `## Deltas` validation branch)
  - .aai/templates/SPEC_TEMPLATE.md (optional `## Deltas` section + example)
  - .aai/PLANNING.prompt.md (one-paragraph Deltas guidance)
  - tests/skills/test-aai-delta-stage2.sh (new suite) OR new stanzas in
    tests/skills/test-aai-delta-stage1.sh + tests/skills/test-aai-spec-lint.sh
    (implementer's call; both are acceptable — see Test Plan)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — The `## Deltas` block grammar
A SPEC may carry at most one optional `## Deltas` section (exact level-2 heading
text `Deltas`; nothing else on the line, so `## Deltas Rationale` never matches).
It contains zero or more level-3 delta blocks, each an operation on ONE canonical
requirement:

- `### ADDED REQ-<DOMAIN> — <title>` — proposes a NEW requirement. The heading
  carries NO `-NNN` number: stage 3 assigns the next unused NNN per domain at
  merge (SPEC-0034 D1/D7 stability rule). Body: exactly ONE `SHALL` line;
  optional `- Scenario: WHEN … THEN …` bullet(s).
- `### MODIFIED REQ-<DOMAIN>-NNN — <title>` — replaces the body of an EXISTING
  requirement id. Body: exactly ONE `SHALL` line; optional scenario bullet(s).
- `### REMOVED REQ-<DOMAIN>-NNN` — retires an EXISTING requirement id. No title,
  no `SHALL`, no scenarios (an empty block; the id is retired permanently).

`<DOMAIN>` is the uppercase-snake REQ domain token (SPEC-0034 grammar). The
target canonical domain slug is DERIVED from it — no separate `Canonical:`/
`Target:` line — because a domain slug is kebab with no underscores, so the
snake→kebab reverse (`OAUTH2_LOGIN` → `oauth2-login`) is unambiguous
(`reqDomainToSlug`, the inverse of `domainToReqDomain`). The target file is
`docs/canonical/<slug>.md` (existence checked in stage 3, not here).

### D2 — spec-lint validates SHAPE only (single source of truth for ids)
spec-lint gains a `## Deltas` branch that reuses SPEC-0034's `REQ_ID_RE` /
`REQ_HEADING_RE` / `domainToReqDomain` / `DOMAIN_SLUG_RE` (imported, not
re-expressed — the delta ids MUST be exactly the ids the canonical layer
accepts). A spec with no `## Deltas` section produces ZERO new findings (the
section is optional; legacy specs untouched). When present, each block is
checked and any breach is a precise finding (codes, most-specific first):
- `delta-op-invalid`: a `###` heading under `## Deltas` whose first token is not
  one of `ADDED` / `MODIFIED` / `REMOVED`, or that is otherwise unparseable.
- `delta-added-numbered`: an `ADDED` heading whose id carries a `-NNN` (the
  number is assigned at merge, never authored).
- `delta-id-malformed`: a `MODIFIED`/`REMOVED` id that fails `REQ_ID_RE`, or an
  `ADDED` id that is not `REQ-<DOMAIN>` with a `domainToReqDomain`-valid token.
- `delta-domain-underivable`: the `<DOMAIN>` token does not reverse to a
  `DOMAIN_SLUG_RE`-valid slug (`reqDomainToSlug` rejects it).
- `delta-shall-count`: an `ADDED`/`MODIFIED` block whose `SHALL`-line count ≠ 1,
  or a `REMOVED` block carrying any `SHALL` line, scenario bullet, or title.
- `delta-scenario-malformed`: a `- Scenario:` bullet not matching `WHEN … THEN …`.
- `delta-duplicate`: the same `REQ-<DOMAIN>-NNN` targeted by more than one block,
  or an `ADDED` `<title>` colliding case-insensitively with another ADDED in the
  same domain (best-effort authoring guard; NNN-level dedupe is stage 3's job).

### D3 — One shared reader in docs-model.mjs (stage 3 reuse)
Mirroring SPEC-0034 D5, the parser lands in docs-model.mjs as
`parseDeltasSection(content)` returning
`{ present, deltas: [{ op, id, domain, slug, title, shallCount, scenarios }],
violations }` — `op` ∈ ADDED|MODIFIED|REMOVED; `id` is the full `REQ-…` string
as authored (no NNN for ADDED); `domain` the snake token; `slug` the reversed
kebab slug (null when underivable); `title` null for REMOVED. spec-lint renders
`violations` into findings; stage 3's `delta-merge.mjs` consumes the SAME
`deltas` to resolve merge targets. Grammar implemented ONCE. `reqDomainToSlug`
also lands here beside `domainToReqDomain`.

`parseDeltasSection` strips HTML-comment regions (newline-preserving, via the
shared `stripHtmlComments`) BEFORE scanning: commented content is INACTIVE by
author intent. This matters because SPEC_TEMPLATE ships the `## Deltas` example
commented — without stripping, every template-derived spec would parse as
`present:true` with the example blocks as phantom deltas (a delta-merge landmine)
and a delta an author comments out to disable would still be linted. After
stripping, a commented example → `present:false`; a commented-out block → absent.

### D4 — Template + planning wiring (taxonomy-guard clean)
`.aai/templates/SPEC_TEMPLATE.md` gains a commented, OPTIONAL `## Deltas` section
showing one ADDED, one MODIFIED, one REMOVED example and the one-SHALL rule.
`.aai/PLANNING.prompt.md` gains one paragraph: when a change alters canonical
requirements, declare the intended changes as `## Deltas` so the merge is
mechanical. Both reference "RFC-0011 (delta-spec lifecycle)" by content — the
review-taxonomy guard bans `stage 1`/`stage-1`/`stage 2` tokens on `.aai`
surfaces (SPEC-0034 edge-case note). The digit-bearing derivation example uses
`oauth2-login` → `OAUTH2_LOGIN`.

### D5 — Legacy and empty are valid states
A spec with no `## Deltas` section is valid and unlinted for deltas. A present
but EMPTY `## Deltas` section (no `###` blocks) is valid (a spec may add the
heading before authoring blocks) — no finding. This mirrors SPEC-0034 D4
(empty Requirements is valid).

### D6 — Stage 3 seam (recorded, not implemented)
Cross-doc resolution is deliberately absent here and belongs to the third staged
SPEC: does the `MODIFIED`/`REMOVED` id exist in the target canonical doc; does
`docs/canonical/<slug>.md` exist; assigning the ADDED NNN; writing `Provenance:`;
the docs-audit drift check that every canonical requirement traces to a merging
spec. Stage 2 gives stage 3 the parsed `deltas[]` and the reversible domain
mapping; it asserts nothing about canonical content (which is empty in this repo).

FAIL-CLOSED CONSUMPTION CONTRACT (binds stage 3): `parseDeltasSection` emits one
`deltas[]` entry per recognized-op block EVEN when that block has a violation (a
malformed id yields `{ domain:null, slug:null }`), so spec-lint can report every
block. A downstream consumer (the delta merge) therefore MUST treat a non-empty
`violations` as fail-closed — refuse to merge ANY delta from a spec with a delta
violation — and MUST NOT act on a `slug:null` entry. Stage 3 owns enforcing this;
recorded here so the contract is explicit at the seam.

## Acceptance Criteria Mapping
- Maps to CHANGE AC-001 (shared reader)
  - Spec-AC-01: docs-model.mjs exports `reqDomainToSlug` (inverse of
    `domainToReqDomain`; `OAUTH2_LOGIN`→`oauth2-login`, rejects tokens that do
    not reverse to a `DOMAIN_SLUG_RE` slug) and `parseDeltasSection(content)`
    returning the D3 shape; ADDED/MODIFIED/REMOVED blocks parse with correct
    op/id/domain/slug/title/shallCount/scenarios; malformed blocks surface as
    `violations`; absent section → `{ present:false, deltas:[], violations:[] }`;
    empty section → `{ present:true, deltas:[], violations:[] }`.
  - Verification: TEST-001, TEST-002.
- Maps to CHANGE AC-002 (spec-lint shape validation)
  - Spec-AC-02: spec-lint emits each D2 finding code on the matching malformed
    block and NONE on a well-formed `## Deltas` section; a spec with no `##
    Deltas` section yields zero new findings; the delta ids are validated with
    the imported SPEC-0034 grammar (a lowercase/kebab/unpadded id is rejected).
  - Verification: TEST-003, TEST-004.
- Maps to CHANGE AC-003 (wiring + existing flow intact)
  - Spec-AC-03: SPEC_TEMPLATE and PLANNING.prompt document the optional section
    (RFC-0011 by content, no stage token — verified by a taxonomy-guard-clean
    grep); the existing spec-lint, delta-stage1, docs-audit, and ceremony-levels
    suites pass; repo-wide `--check --strict` CLEAN; index regen idempotent;
    check-state OK.
  - Verification: TEST-005, TEST-006.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | reqDomainToSlug + parseDeltasSection shared reader in docs-model   | done    | TEST-001, TEST-002 green; docs/ai/tdd/delta-stage2-green.log | — | RED-proof in docs/ai/tdd/delta-stage2-red.log |
| Spec-AC-02 | spec-lint validates the Deltas shape; legacy specs unaffected      | done    | TEST-003, TEST-004 green; docs/ai/tdd/delta-stage2-green.log | — | RED-proof in docs/ai/tdd/delta-stage2-red.log |
| Spec-AC-03 | template/prompt wired (taxonomy-clean); existing flow intact       | done    | TEST-005, TEST-006 green; docs/ai/tdd/delta-stage2-green.log | — | taxonomy grep clean; spec-lint/stage1/audit/index all green |

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                        | Description                                                                                          | Status  |
|----------|------------|-------------|----------------------------------------------|----------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-delta-stage2.sh        | reqDomainToSlug fixtures: OAUTH2_LOGIN->oauth2-login, AUTH->auth; rejects lowercase/leading-underscore/empty (inverse round-trips domainToReqDomain) | planned |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-delta-stage2.sh        | parseDeltasSection: ADDED (no NNN)/MODIFIED/REMOVED parse with op/id/domain/slug/title/shallCount/scenarios; violations for bad op, ADDED-with-NNN, malformed id, underivable domain, SHALL!=1, REMOVED-with-body, dup id; absent vs empty section states; HTML-comment stripping (commented section inert, commented block not parsed) | planned |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh           | spec-lint on a spec with a well-formed `## Deltas` section: zero delta findings; each malformed variant emits exactly its D2 code naming the block | planned |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh           | legacy control: a spec with NO `## Deltas` section produces zero new findings (byte-identical finding set to pre-change); the whole corpus stays LINT PASS | planned |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-delta-stage2.sh        | SPEC_TEMPLATE + PLANNING.prompt document the optional section, the three ops, the one-SHALL rule, the derivation example; NO `stage N` token present on either `.aai` surface (taxonomy guard); the real SPEC_TEMPLATE commented example parses present:false (no phantom deltas) | planned |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-delta-stage2.sh        | seam survival: existing spec-lint + delta-stage1 suites pass post-change; strict audit CLEAN over the real repo (regression seam) | planned |

Seam analysis:
- Seam S1 — `parseDeltasSection` (new) sits beside `parseRequirementsSection`
  and imports the SPEC-0034 REQ grammar. Crossing test: TEST-002 drives the real
  parser; TEST-001 proves the reversible mapping round-trips `domainToReqDomain`.
- Seam S2 — spec-lint's `lintContent` gains a branch; it must not perturb any
  existing finding on any existing spec. Crossing test: TEST-004 asserts a
  no-Deltas spec's finding set is unchanged and the corpus stays LINT PASS;
  TEST-006 re-runs the full spec-lint suite.
- Seam S3 — stage 3 (`delta-merge.mjs`, does not exist yet) will consume
  `parseDeltasSection().deltas`. No test can cross into absent code: recorded as
  the D6 seam + residual risk.
- Residual risk (recorded): until stage 3 lands, nothing merges declared deltas
  into `docs/canonical/`; a `## Deltas` section is authored-and-validated intent
  only. Mitigation: `docs/canonical/` is empty in this repo; the producer side
  ships tested and ready for the merge consumer.

## Constitution deviations
None.

Honest per-article check (docs/CONSTITUTION.md v1): Art. 1 — every AC carries
executable verification, RED-proof obligation recorded; Art. 2 — no merge/gate
machinery built ahead of its consuming stage (shape validation only); Art. 3 —
plain mjs/markdown/bash; Art. 4 — the parser returns explicit violations, empty
and absent are defined valid states; Art. 5 — additive: a new optional section +
a new validator branch; legacy specs byte-identical; Art. 6 — no STATE writes
from the parser or linter; Art. 7 — no commits, no merge; the merge trigger
stays inside the operator-owned PR ceremony (delivered by the next stage).

## Verification
- `bash tests/skills/test-aai-delta-stage2.sh` → exit 0 (all stanzas).
- `bash tests/skills/test-aai-spec-lint.sh` → exit 0 (Deltas stanzas + seam).
- `bash tests/skills/test-aai-delta-stage1.sh` → exit 0 (grammar reuse intact).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0 CLEAN.
- `node .aai/scripts/generate-docs-index.mjs` twice → content idempotent.
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` → OK.
- Taxonomy-guard grep: no `stage 1`/`stage-1`/`stage 2`/`stage-2` token on the
  edited `.aai` surfaces.

## Evidence contract
For each artifact record: ref_id delta-stage-2, Spec-AC and TEST-xxx links,
command, exit code, evidence path (docs/ai/tdd/delta-stage2-red.log,
docs/ai/tdd/delta-stage2-green.log), diff range when available.

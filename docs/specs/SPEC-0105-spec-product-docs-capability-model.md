---
id: spec-product-docs-capability-model
type: spec
number: 105
status: draft
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0088-product-docs-capability-model.md
  rfc: null
  pr: []
  commits: []
---

# Spec — product docs as a capability-keyed SECOND DOC FAMILY on the shared doc-engine primitives (fixes #189)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0088-product-docs-capability-model.md
- Decision records: operator architecture decision 2026-07-28 (recorded in the intake)
- Technology contract: docs/TECHNOLOGY.md
- GitHub issue: #189 (product `type:product` / `status:current` invisible to the doc engines)

## Summary

Product docs today are per-ride, hand-authored `docs/product/<ride>.md` files
that BOTH doc engines silently ignore: `generate-docs-index.mjs` `SCAN_DIRS`
omits `docs/product` (walk never sees them) and `docs-audit-core.mjs`
`scanAuditDocs` admits only ID-prefixed / `-DRAFT-` / `docs/canonical/`
basenames, so a slug-named product doc is dropped with no error. Grounded
repro (read-only, this branch): `node .aai/scripts/docs-audit.mjs --check
--no-event --path docs/product/issues-skill.md` reports **"Scanned: 0 docs"**
(silent omission, a Constitution art. 4 / no-silent-truncation violation — the
#189 issue mis-labels it "active rejection"), and `grep -c docs/product/
docs/INDEX.md` == 0. The frontmatter `type: product` / `status: current`
(PRODUCT_TEMPLATE.md, all 12 live docs) is in NEITHER `DOC_TYPE_ENUM` nor
`DOC_STATUS_ENUM` (docs-model.mjs ~60 / ~23).

This spec rebuilds the product layer as a **SECOND DOC FAMILY** on the SAME
shared library primitives the canonical family already uses — NOT a new engine
and NOT folded into `docs/canonical`. Concretely it GENERALIZES the existing
`inCanonical` slug-admit special-case (`docs-audit-core.mjs:555`) into a
reusable doc-family registry that BOTH families configure, routes
`docs/product` through the SAME `generate-docs-index` scan + placement-section
machinery canonical uses, and keys product docs by USER CAPABILITY (separate
axis from canonical's requirement domains). Producing a parallel
`generate-product-docs.mjs` with its own scan/index/drift loop is an explicit
ANTI-goal.

## Architecture constraint (operator-decided, non-negotiable)

One scan mechanism, two configured families:
- canonical family: `docs/canonical/<domain>.md`, keyed on requirement DOMAIN
  (`validateCanonicalFrontmatter`: domain + sources), produced by
  `docs-canon-core.mjs runPhase2` (one file per domain slug).
- product family: `docs/product/<capability>.md`, keyed on user CAPABILITY
  (validateProductFrontmatter: capability + delivered_by), authored by the
  ship flow (prose) and provenance-maintained by the close ceremony.

The axes stay SEPARATE (canon clusters internal SHALL statements; product
clusters user value) so the model works on any target project where
requirement-domain != user-capability.

## Design decisions (grounded, with code citations)

### D1 — the shared doc-family scan-admit primitive (SEAM-1)

Add to `.aai/scripts/lib/docs-model.mjs` (the shared lib imported by BOTH
engines):

```
export const DOC_FAMILIES = [
  { type: 'canonical', dir: 'docs/canonical/', indexSection: 'Canonical layer' },
  { type: 'product',   dir: 'docs/product/',   indexSection: 'Product' },
];
export function slugFamilyForPath(rel) {          // rel is POSIX (toPosix)
  return DOC_FAMILIES.find(f => rel.startsWith(f.dir)) ?? null;
}
```

`docs-audit-core.mjs scanAuditDocs` (~547-559): replace the hardcoded
`const inCanonical = rel.startsWith('docs/canonical/');` with
`const inFamily = !!slugFamilyForPath(rel);` and
`if (!m && !isDraft && !inFamily) continue;`. This is the ONLY scan change —
product rides the identical single scan loop; the ID/DRAFT/family admit fork
becomes one registry-driven predicate. `docs/product` is NOT in `EXCLUDE_DIRS`
(docs-audit-core.mjs:34), so the directory is already visited; only the file
was being dropped.

`generate-docs-index.mjs`: derive family handling from the SAME registry —
(a) `SCAN_DIRS` includes each `DOC_FAMILIES[].dir` (adds `docs/product`);
(b) generalize the hardcoded `isCanonical` predicate (:339-343) to
`familyOf(d)` from `DOC_FAMILIES` so family docs are excluded from the generic
`byStatus` sections; (c) render ONE placement section per family entry (the
existing "Canonical layer" section becomes the canonical instance; "Product"
is the product instance) and add each family's members to `placementMembers`
(:366) so the data-driven zero-section coverage invariant (:373-390) covers
them automatically.

Anti-duplication proof (Spec-AC-02): there remains exactly one scan loop
(`scanAuditDocs`) and one `walk`/section renderer (`generate-docs-index main`);
`git grep generate-product-docs` returns nothing; deleting the `product`
registry entry makes BOTH engines drop `docs/product` in lockstep (one config,
two consumers).

### D2 — status + type enum decision

DECISION: `DOC_TYPE_ENUM += 'product'` and `DOC_STATUS_ENUM += 'current'` (a
NEW status; reuse the existing `superseded` for a retired capability doc).
Chosen over reusing `done`:
- `current` matches the template and all 12 live docs already on disk — closes
  #189 with ZERO changes to any product doc's `type`/`status` field (additive,
  Constitution art. 5).
- Traced through `docs-audit-core.mjs runAudit`: a `status: current` doc is not
  `superseded`/`rejected` (:956), not in `FALSE_OPEN_STATUSES` (:46, :964), not
  in `OPEN_STATUSES` (:42, :1041), not `done` (:986) — so it falls straight to
  `verdict = 'aligned'`, `cls = 'tracked-open'` (:1052-1065): CLEAN, no drift
  heuristic fires, and `missingCloseTelemetry` (:909, `done`-only) is skipped.
  Reusing `done` would instead drag every product doc into the false-done /
  git-mention heuristics designed for specs/changes — the wrong fit.
- Placement: product docs are placed by TYPE (the D1 "Product" family section),
  so the new `current` status needs NO status-section and produces NO coverage
  gap. A NON-product doc that mis-uses `status: current` correctly surfaces as
  a coverage gap (surfaced, never silent) — a desirable property.

`validateProductFrontmatter(fm)` is added to docs-model.mjs (mirroring
`validateCanonicalFrontmatter`, docs-model.mjs:722): requires
`type === 'product'`, a `capability` matching `DOMAIN_SLUG_RE`
(docs-model.mjs:84, reused), and a non-empty `delivered_by` list. Wired into
`docs-audit-core.mjs runAudit` in a `type === 'product'` branch parallel to the
canonical branch (:934) so violations are hard schema failures under
`--check --strict` (audited by construction).

### D3 — capability declaration, ship/close wiring (SEAM-2, SEAM-3)

- A user_visible intake (change/issue/prd) carries `capability: <kebab-slug>`
  (`DOMAIN_SLUG_RE`) naming the user-facing capability it delivers/extends.
  Multiple work items may share one slug — they UPDATE that capability's one
  doc, never spawn a new file. `user_visible: true` is the existing gate
  trigger (`close-work-item.mjs truthyUserVisible`, :173).
- Storage: one doc per capability at `docs/product/<capability>.md`.
  Frontmatter: `type: product`, `capability: <slug>`, `status: current`,
  `delivered_by: [<ref>...]` (generated provenance), `spec` (optional),
  `updated`. Prose (What it does / How to use it / Data model / Interfaces and
  contracts / Limits and non-goals / Links) is authored by the ship flow and
  PRESERVED byte-for-byte across regen.
- Gate re-key: `close-work-item.mjs evaluateProductDocGate` (:185) resolves the
  product doc by the PRIMARY intake's `capability` field — `docs/product/
  <capability>.md` — instead of `primaryDoc.fmId` (:187). Legacy fallback:
  absent `capability` -> `fmId` (back-compat with a doc whose capability equals
  its ride slug, i.e. every migrated doc). The exit-3 refuse path
  (`product_doc_gate: enforce`) and warn-by-default are preserved verbatim.
- Provenance maintenance (create-else-update): the ship flow (SKILL_SHIP step
  4) AUTHORS `docs/product/<capability>.md` from the template if absent (prose);
  `close-work-item.mjs`, after the gate passes and inside the existing snapshot
  /rollback transaction (:629-673), UPSERTS the closing ref into the capability
  doc's `delivered_by` (append-if-absent, deduped — reusing the same
  line-surgical frontmatter mutator pattern as `stampLink`, :287) and stamps
  `updated`, leaving all prose byte-identical. Re-running close for the same ref
  is a no-op (byte-idempotent), mirroring the existing `hasLinkValue`
  idempotency probes (:277). A failed self-verify rolls the product-doc edit
  back with everything else.
- USER_GUIDE rollup: `generate-userguide-rollup.mjs` already keys per file slug
  (`slug = fm.id ?? file`, :107) and reads `docs/product/*.md` — since the
  filename IS the capability after migration, it renders per-capability with NO
  change. It stays the read-only reader of the SAME `lib/product-doc.mjs`
  identity/placeholder predicate the gate uses (SEAM-4, unchanged).

No NEW `.aai/**` file is introduced (all logic folds into existing shared-lib
and core scripts) — so the PLANNING step-3a PROFILES.yaml companion is N/A.

### D4 — FROZEN capability set + migration map (the load-bearing table)

DECISION: a strictly ADDITIVE, zero-prose-loss migration. Each of the 12 live
docs is already a distinct, non-duplicate user-facing capability; the FROZEN
initial capability slug = the doc's current filename slug for ALL 12. Migration
is therefore purely additive frontmatter (`capability:` + `delivered_by:`) with
ZERO file renames and ZERO prose bytes touched — trivially satisfying "zero
user-facing content loss" and byte-idempotence, and removing all taxonomy
ambiguity from the critical path. The "multiple rides -> one doc" merge path
is EXERCISED by AC-002 synthetically and reserved for FUTURE same-capability
rides (e.g. the in-flight dashboard-refit -> `dashboard`, doctor-determinize ->
`doctor`), which have no product doc yet and are out of THIS migration's scope.

Migration map (all 12; capability == current slug; delivered_by seeded with the
originating ride ref from the doc's own `spec`/Links provenance):

| Product doc (current) | FROZEN capability slug | delivered_by (seed) | Action |
|---|---|---|---|
| ci-test-impact-selection.md | ci-test-impact-selection | ci-test-impact-selection | add capability + delivered_by |
| dev-progress-hub.md | dev-progress-hub | dev-progress-hub | add capability + delivered_by |
| docs-hub-generator.md | docs-hub-generator | docs-hub-generator | add capability + delivered_by |
| friction-capture-default-on.md | friction-capture-default-on | friction-capture-default-on | add capability + delivered_by |
| issues-skill.md | issues-skill | issues-skill | add capability + delivered_by |
| learned-append-gate.md | learned-append-gate | learned-append-gate | add capability + delivered_by |
| platform-portable-pr.md | platform-portable-pr | platform-portable-pr | add capability + delivered_by |
| product-docs-enforced.md | product-docs-enforced | product-docs-enforced | add capability + delivered_by |
| prompt-hash-telemetry.md | prompt-hash-telemetry | prompt-hash-telemetry | add capability + delivered_by |
| role-output-contracts.md | role-output-contracts | role-output-contracts | add capability + delivered_by |
| token-capture-canary.md | token-capture-canary | token-capture-canary | add capability + delivered_by |
| token-economics-end-to-end.md | token-economics-end-to-end | token-economics-end-to-end | add capability + delivered_by |

Verification of zero prose loss: `git diff` on each of the 12 shows ONLY added
frontmatter lines (body hunk count == 0). All 12 must then pass
`docs-audit --check --strict` CLEAN and appear in INDEX.md "Product".

### D5 — companion obligations (PLANNING step 3a)

- prompt corpus: SKILL_SHIP.prompt.md step 4 is re-keyed on `capability` (it is
  a `.aai/*.prompt.md` file inside TEST-010's live glob). IF its net byte delta
  is positive, add ONE `JUSTIFIED_ADDITIONS` entry to
  `tests/skills/lib/prompt-diet-ledger.sh` (the sum auto-recomputes; no manual
  constant bump) and keep `tests/skills/test-aai-prompt-diet.sh` green. PLANNING
  step 3a companion #1 obligation.
- new `.aai/**` file: NONE added (D3) — PLANNING step 3a companion #2
  (PROFILES.yaml classification) is N/A. `lib/product-doc.mjs` already exists
  and is classified `core` (PROFILES.yaml:116).
- suite-map: the new suite `tests/skills/test-aai-product-docs.sh` needs a
  `suites.aai-product-docs` row in `tests/skills/suite-map.yaml` or
  `tests/skills/test-aai-hygiene-pack.sh` (AC-003 hygiene pin) fails. Shared-lib
  edits (docs-model.mjs, docs-audit-core.mjs) already escalate to FULL_RUN via
  `full_run_triggers.shared_lib_globs` (suite-map.yaml).

## Acceptance Criteria Mapping

- AC-001 (intake) -> Spec-AC-01, Spec-AC-02
- AC-002 (intake) -> Spec-AC-03
- AC-003 (intake) -> Spec-AC-04
- AC-004 (intake) -> Spec-AC-05
- companion (PLANNING 3a) -> Spec-AC-06

- Spec-AC-01: DOC_TYPE_ENUM contains `product` and DOC_STATUS_ENUM contains
  `current`; a capability-keyed product doc (type product, status current,
  valid capability slug, non-empty delivered_by) passes `docs-audit --check
  --strict` classified tracked-open/aligned (no orphan, no type warning, no
  schema violation) AND appears in docs/INDEX.md under a "Product" section — the
  exact #189 repro (create-from-template, audit, index) now succeeds.
  - Verification: `node .aai/scripts/docs-audit.mjs --check --strict --no-event
    --path <fixture>` exit 0 + classified tracked-done-or-open aligned; grep the
    fixture path under "## Product" in generated INDEX.md.
- Spec-AC-02: docs-model.mjs exports DOC_FAMILIES + slugFamilyForPath;
  scanAuditDocs admits docs/product via that predicate (no hardcoded
  `inCanonical` literal remains); generate-docs-index derives SCAN_DIRS AND the
  per-family placement section from the SAME registry; no parallel product
  scan/index/drift code exists.
  - Verification: unit assert slugFamilyForPath admits both a canonical and a
    product path; `git grep -c generate-product-docs` == 0; deleting the product
    registry entry drops the product doc from BOTH engines (integration).
- Spec-AC-03: a user_visible intake carrying `capability: <slug>` drives
  close-work-item.mjs to resolve docs/product/<capability>.md; two work items
  sharing one capability slug UPDATE ONE doc (both refs in delivered_by);
  authored prose survives the delivered_by/updated upsert byte-identically; a
  repeat close is a no-op; the exit-3 refuse path is preserved.
  - Verification: fixture repo, close ref A then ref B (same capability) ->
    one docs/product/<cap>.md, delivered_by == [A, B], body byte-diff == 0;
    second close of A exits 0 "nothing to do"; enforce dial + missing doc ->
    exit 3.
- Spec-AC-04: all 12 docs/product/*.md carry capability + delivered_by (body
  byte-diff == 0 each); PRODUCT_TEMPLATE.md carries capability + delivered_by;
  post-migration `docs-audit --check --strict` is CLEAN repo-wide, all 12 appear
  under INDEX.md "Product", and generate-userguide-rollup renders one entry per
  capability.
  - Verification: `git diff --stat docs/product` shows frontmatter-only hunks;
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0; count
    12 rows under "## Product"; userguide-rollup output lists 12 features.
- Spec-AC-05: a fresh user_visible ride (capability on intake + product doc
  authored from the updated template) produces a clean, indexed, audited
  capability doc out of the box — audit clean, indexed under Product, gate
  satisfied, delivered_by stamped at close (the inverse of #189).
  - Verification: end-to-end fixture: template -> docs/product/<cap>.md ->
    audit --check --strict clean + INDEX Product row + close gate pass +
    delivered_by populated.
- Spec-AC-06: SKILL_SHIP step 4 keys product-doc authoring on capability;
  prompt-diet ledger trued-up if SKILL_SHIP net-grows (test-aai-prompt-diet.sh
  green); suite-map carries an aai-product-docs row (test-aai-hygiene-pack.sh
  green); no new .aai/** file (PROFILES companion N/A).
  - Verification: `bash tests/skills/test-aai-prompt-diet.sh` +
    `bash tests/skills/test-aai-hygiene-pack.sh` green; `git status` shows no
    new .aai/** file.

## Constitution deviations

None.

- Art. 1 (evidence): every AC names an executable command + expected evidence.
- Art. 2 (simplicity/YAGNI): reuses the shared scan/index/drift primitives; a
  parallel product engine is an explicit anti-goal; capability set kept 1:1.
- Art. 3 (portability): plain git-diffable Markdown + Node-stdlib scripts only.
- Art. 4 (degrade/report): this change FIXES the silent-omission of product docs
  (aligned, not deviating).
- Art. 5 (additive-first): enum additions, a new registry, a new frontmatter
  field with a legacy fallback, and additive INDEX section — all backward
  compatible; no existing doc's type/status changes.
- Art. 6 (single-writer state): no STATE.yaml writes in this scope.
- Art. 7 (operator-only merge): unaffected.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state.

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | product/current enums land; a capability product doc audits clean and indexes under Product (the #189 repro succeeds) | done | docs/ai/tdd/red-20260728T000000Z-product-docs.log + docs/ai/tdd/green-20260728T000100Z-product-docs.log | tdd | TEST-001..003 |
| Spec-AC-02 | shared DOC_FAMILIES scan-admit primitive both engines consume; no parallel product scan/index/drift code | done | docs/ai/tdd/red-20260728T000000Z-product-docs.log + docs/ai/tdd/green-20260728T000100Z-product-docs.log | tdd | TEST-004..005, TEST-016 |
| Spec-AC-03 | capability-keyed close gate plus transactional byte-idempotent delivered_by upsert; refuse path preserved | done | docs/ai/tdd/red-20260728T000200Z-close-work-item-capability.log + docs/ai/tdd/green-20260728T000300Z-close-work-item-capability.log | tdd | TEST-006..009 |
| Spec-AC-04 | 12 docs migrated additively with zero prose loss; audit strict clean; rollup per-capability | done | docs/ai/tdd/green-20260728T000100Z-product-docs.log (TEST-012) + tests/skills/test-aai-docs-audit.sh test_pdcm_product_family_repo_wide_clean + tests/skills/test-aai-userguide-rollup.sh test_019_capability_migrated_docs_render | tdd | TEST-010..012 |
| Spec-AC-05 | fresh user_visible ride yields a clean indexed audited capability doc out of the box | done | docs/ai/tdd/green-20260728T000100Z-product-docs.log (TEST-013) | tdd | TEST-013 |
| Spec-AC-06 | companion obligations: prompt-diet ledger, suite-map row, no new .aai file | done | tests/skills/test-aai-prompt-diet.sh (green, headroom 502/2048) + tests/skills/test-aai-hygiene-pack.sh (green) | tdd | TEST-014..015 |

Status values: planned | implementing | done | deferred | blocked | rejected.

## Implementation strategy
- Strategy: tdd
- Rationale: touches shared doc-engine core logic (docs-model enums + the
  scan-admit primitive both engines consume), the deterministic close ceremony
  (transaction/rollback), and a data migration where "zero prose loss" and the
  enum->section invariant are data-integrity properties. New behavior + a live
  #189 regression that must be observed RED first. RED-proof is mandatory for
  every AC-gating test regardless of strategy.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: spans 3+ shared modules (docs-model.mjs,
  docs-audit-core.mjs, generate-docs-index.mjs, close-work-item.mjs) plus a
  12-doc migration + template + skill prompt + governance ledger — larger,
  PR-bound work touching shared doc-engine surfaces used by many suites. NOT
  `required`: none of the touched paths are in `protected_paths_l3`
  (docs/ai/docs-audit.yaml — state engine, allocator, pre-commit guards,
  WORKFLOW.md, CONSTITUTION.md; verified none match). Already on a dedicated
  branch (feat/product-docs-capability-model).
- User decision: undecided (Implementation Preparation asks; recommended does
  not auto-decide)
- Base ref: main
- Worktree branch/path: feat/product-docs-capability-model (current checkout)
- Inline review scope (if inline chosen): .aai/scripts/lib/docs-model.mjs,
  .aai/scripts/lib/docs-audit-core.mjs, .aai/scripts/generate-docs-index.mjs,
  .aai/scripts/lib/product-doc.mjs, .aai/scripts/close-work-item.mjs,
  .aai/templates/PRODUCT_TEMPLATE.md, .aai/SKILL_SHIP.prompt.md,
  docs/product/*.md, tests/skills/test-aai-product-docs.sh,
  tests/skills/suite-map.yaml, tests/skills/lib/prompt-diet-ledger.sh,
  docs/INDEX.md, CHANGELOG.md

## Seam analysis (cross-feature integration)

- SEAM-1: DOC_FAMILIES (docs-model.mjs) is consumed by BOTH docs-audit-core
  scanAuditDocs AND generate-docs-index. Integration test: ONE product fixture
  must be BOTH audited clean AND indexed under "Product" from a single scan
  (TEST-004) — not two isolated unit mocks.
- SEAM-2: `capability` on the intake frontmatter is PRODUCED by intake and READ
  by close-work-item's gate AND its delivered_by upsert. Integration test: close
  a user_visible ref with capability C -> assert docs/product/C.md gate passes
  AND delivered_by carries the ref (TEST-006).
- SEAM-3: docs/product/<cap>.md is MAINTAINED by close-work-item and READ by
  generate-userguide-rollup. Integration test: after close upserts delivered_by,
  userguide-rollup renders the capability entry over the mutated doc (TEST-010).
- SEAM-4: lib/product-doc.mjs missingProductSections is shared by the close gate
  and the rollup (existing). Regression: capability-keying must not change its
  placeholder verdict (TEST-011).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Status |
|---|---|---|---|---|---|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-product-docs.sh | DOC_TYPE_ENUM has product and DOC_STATUS_ENUM has current (import assert) | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-product-docs.sh | #189 repro: template-shaped product doc -> docs-audit --check --strict exit 0, classified tracked-open aligned (no orphan/type-warning/violation) | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-product-docs.sh | product fixture appears under docs/INDEX.md "## Product" after generate-docs-index | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-product-docs.sh | slugFamilyForPath admits both a canonical and a product path; same fixture is BOTH audited-clean and indexed (SEAM-1) | green |
| TEST-005 | Spec-AC-02 | unit | tests/skills/test-aai-product-docs.sh | anti-duplication: git grep generate-product-docs == 0 and removing the product registry entry drops it from both engines | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh | close user_visible ref with capability C -> gate resolves docs/product/C.md and passes (SEAM-2) | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh | two refs sharing capability C -> one docs/product/C.md, delivered_by == both refs | green |
| TEST-008 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh | delivered_by/updated upsert leaves prose byte-identical; repeat close is a no-op (byte-idempotent) | green |
| TEST-009 | Spec-AC-03 | integration | tests/skills/test-aai-close-work-item.sh | product_doc_gate enforce + missing capability doc -> exit 3 refuse (preserved) | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-userguide-rollup.sh | rollup renders one entry per capability over migrated docs (SEAM-3) | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | post-migration docs-audit --check --strict CLEAN repo-wide; all 12 product docs classified aligned | green |
| TEST-012 | Spec-AC-04 | unit | tests/skills/test-aai-product-docs.sh | each migrated doc's body byte-diff == 0 vs pre-migration (frontmatter-only change) | green |
| TEST-013 | Spec-AC-05 | e2e | tests/skills/test-aai-product-docs.sh | fresh user_visible ride: template -> capability doc -> audit clean + INDEX Product + gate pass + delivered_by stamped (inverse of #189) | green |
| TEST-014 | Spec-AC-06 | integration | tests/skills/test-aai-prompt-diet.sh | prompt-diet ledger green after SKILL_SHIP re-key (JUSTIFIED_ADDITIONS entry if net-positive) | green |
| TEST-015 | Spec-AC-06 | integration | tests/skills/test-aai-hygiene-pack.sh | suite-map carries aai-product-docs row; hygiene pin green | green |
| TEST-016 | Spec-AC-02 | integration | tests/skills/test-aai-layer-profiles.sh | PROFILES union still 100% classified (no new .aai file); regression | green |

Every Spec-AC has >= 1 TEST-xxx. RED-proof obligation: TEST-002 (the live #189
repro) MUST be observed failing against the pre-change engines before its pass
counts; every other AC-gating test likewise observed RED first.

## Implementation plan
- Components: docs-model.mjs (enums + DOC_FAMILIES + slugFamilyForPath +
  validateProductFrontmatter); docs-audit-core.mjs (scan-admit generalization +
  product schema branch); generate-docs-index.mjs (registry-driven SCAN_DIRS +
  per-family section + placementMembers); product-doc.mjs (capability resolution
  helper if needed; existing predicate unchanged); close-work-item.mjs
  (capability-keyed gate + transactional delivered_by/updated upsert);
  PRODUCT_TEMPLATE.md (frontmatter); SKILL_SHIP.prompt.md (step 4 re-key);
  docs/product/*.md x12 (migration); suite-map.yaml; prompt-diet-ledger.sh.
- Data flows: intake.capability -> product doc path (gate + upsert) ->
  scan-admit (both engines) -> INDEX Product section + audit clean -> rollup.
- Edge cases: legacy product doc without capability (fallback to fmId);
  non-product doc with status current (surfaces as coverage gap, by design);
  a product doc failing validateProductFrontmatter under --strict (hard fail);
  bodyLint over newly-scanned product docs (verified: the 12 carry no all-caps
  `<PLACEHOLDER>` tokens outside inline code, so no false bodyLint under --strict).

## Verification
- Commands: the per-AC commands above, plus full-framework CI (shared-lib
  changes escalate to FULL_RUN). Read-only during planning:
  `node .aai/scripts/docs-audit.mjs --check --no-event --path docs/product/...`.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal; live #189 repro
  clean; docs-audit --check --strict CLEAN repo-wide.

## Evidence contract
For each implementation/validation/TDD/review artifact record: ref_id, Spec-AC
+ TEST-xxx links, command/scope, exit code/verdict, evidence path, commit SHA or
diff range.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

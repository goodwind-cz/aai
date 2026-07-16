---
id: spec-slug-refs-across-tooling
type: spec
number: 16
status: done
links:
  change: CHANGE-0012
  research: RES-0001
  rfc: null
  pr:
    - 51
  commits:
    - 58757fd
---

# SPEC — Accept slug refs across the tooling family (state.mjs, docs-audit scan + --gate)

SPEC-FROZEN: true

## Links
- Change: CHANGE-0012 (docs/issues/CHANGE-0012-slug-refs-across-tooling.md)
- Research: RES-0001 finding F6 / recommendation P1.1
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Identity contract: SPEC-0015 D1/D2 (docs/specs/SPEC-0015-parallel-safe-doc-numbering.md)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: as per template

## Problem (evidence-verified 2026-07-15)
SPEC-0015 made docs slug-first until merge (`id: <slug>`, `number: null`,
`<TYPE>-DRAFT-<slug>.md` filename), but two tooling surfaces still require the
`TYPE-000N` shape:
1. `state.mjs` `refFlag` (REF_RE `/^[A-Z]+-\d+$/`, .aai/scripts/state.mjs:102)
   rejects slug refs with exit 2 for `set-focus --ref`, `set-phase --ref`, and
   `append-run --ref` — DRAFT-era docs cannot be focused, phased, or metered.
2. `docs-audit.mjs --gate <slug>` exits 2 ("no scanned doc resolves to id").
   Root cause found by code reading + probe: `scanAuditDocs`
   (.aai/scripts/lib/docs-audit-core.mjs:190) admits only basenames matching
   `DOC_ID_RE` (requires digits), so `<TYPE>-DRAFT-<slug>.md` files are
   INVISIBLE to the entire audit — `--gate` cannot resolve them, and
   `--check --strict --path <DRAFT-file>` passes VACUOUSLY (probe output:
   `Scanned: 0 docs`, exit 0). The gate-resolution loop itself
   (docs-audit-core.mjs:796) already matches frontmatter `id`, so the scan
   gap is the actual defect, plus a latent first-file-wins ambiguity when two
   docs share an id.

Consumer sweep (what does NOT need changing): `check-state.mjs` parses
work-item keys as `[\w-]+` (slug-compatible, verified); `append-event.mjs`
takes `--ref` free-form; `loop-digest.mjs` and `generate-dashboard.mjs` pass
ref_ids through untyped; `generate-docs-index.mjs:220` is already
DRAFT-aware (`(?:DRAFT|\d{1,5})`); `state.mjs set-validation --ref` is a
plain strFlag (already accepts slugs); `docs-lock.mjs` and
`orchestration-mode.mjs` treat scopes as opaque strings.

## Design decisions

### D1 — Accepted ref shapes (closed set of two, case-sensitive, disjoint)
- DISPLAY shape: the existing `REF_RE = /^[A-Z]+-\d+$/`, unchanged (regression
  contract; compound display ids like `DECISION-RFC-002` stay out of scope —
  they are rejected today and widening them is not this change).
- SLUG shape: `SLUG_RE = /^(?=[a-z0-9-]{3,53}$)[a-z0-9]+(?:-[a-z0-9]+)*$/` —
  aligned with SPEC-0015 D1 `deriveSlug` output: lowercase ASCII alnum,
  kebab-case, no leading/trailing/double hyphen; max 48 chars base slug plus
  an optional `-xxxx` 4-char base36 collision suffix = 53 total; min 3 as a
  typo guard (matches the CHANGE-0012 draft regex intent, tightened to
  exclude `-lead`/`trail-`/`a--b` shapes deriveSlug can never emit).
- The two shapes are DISJOINT by construction (uppercase vs lowercase
  requirement, no case folding anywhere), so no single ref can match both. A
  ref matching neither shape fails closed: exit 2 with a usage message naming
  BOTH accepted shapes.

### D2 — Gate resolution order (validates CHANGE-0012 proposal, amended)
`docs-audit --gate <ref>` resolves in two passes over the scanned docs:
1. exact frontmatter `id` match (the durable PK per SPEC-0015 D2; this also
   covers legacy docs whose frontmatter carries `id: TYPE-000N`);
2. only if pass 1 found nothing: filename-derived display id match
   (`extractDocIds` primary / fileId).
Amendment to the CHANGE proposal: within a pass, MORE THAN ONE match is an
ERROR — exit 2 with a message listing every candidate path. Rationale: the
current per-file first-match-wins loop silently gates whichever file sorts
first (docs/issues/ before docs/specs/), which would gate the WRONG DOC when
two docs share an id; ambiguity must fail loud, not resolve by directory
sort order. This is also why THIS spec's own id is
`spec-slug-refs-across-tooling`, not CHANGE-0012's `slug-refs-across-tooling`:
a duplicate PK would make the slug unresolvable via `--gate` under this very
decision.

### D3 — Scan set: DRAFT basenames become first-class audit citizens
`scanAuditDocs` admits `<TYPE>-DRAFT-<slug>.md` basenames (widen the filename
gate to the `(?:DRAFT|\d{1,5})` form already used by
generate-docs-index.mjs:220 and allocate-doc-number.mjs
`prefixFromBasename`). A DRAFT doc's audit id is its frontmatter `id` (slug);
`fileId` stays null. This fixes BOTH halves of F6's gate symptom and closes
the vacuous-pass hole: `--check --strict --path <DRAFT>` must actually scan
the doc (Scanned: 1) so frontmatter violations in DRAFT docs hard-fail like
numbered docs.

### D4 — Allocation-time durability: no migration
Slug-keyed STATE entries stay valid across merge-time allocation by
construction: the allocator keeps `id: <slug>` unchanged forever (SPEC-0015
D2), so a slug ref written into `current_focus.ref_id`,
`active_work_items[].ref_id`, or `metrics.work_items.<slug>` resolves to the
same doc before and after the `TYPE-000N` rename. `check-state.mjs` already
parses slug keys (`[\w-]+`). No STATE rewrite at allocation; slug is the
durable PK.
- Residual risk (recorded, out of scope): STATE `spec_path`/`primary_path`
  values pointing at the DRAFT path go stale after the allocator rename —
  `rewriteReferences` (allocate-doc-number.mjs:266) sweeps only
  docs/{rfc,specs,issues,requirements,releases}/*.md, not docs/ai/STATE.yaml.
  Path-level staleness, not a ref-resolution defect; follow-up candidate for
  a separate change (extend the allocator sweep or have /aai-pr refresh
  spec_path). Not automatable inside this scope without touching the
  allocator, which CHANGE-0012 keeps out of scope.

### D5 — Fail-closed contract unchanged
Invalid shapes exit 2 before any write, STATE byte-identical, usage message
updated to name both shapes. Exit-code contract of both CLIs is otherwise
untouched (state.mjs 0/1/2; --gate 0/1/2).

## Implementation strategy
- Strategy: tdd
- Rationale: small diff, high blast radius — the ref contract of the
  transactional STATE writer (every role prompt's write path) and the audit
  scan set (repo-wide classification) change together. A widened regex that
  over-accepts corrupts STATE keys silently; a widened scan that
  misclassifies floods the audit. Every AC has a natural RED today (slug
  refs exit 2; DRAFT docs scan as 0), so RED-proof is cheap and
  non-tautological. Bug fix requiring regression proof + core workflow logic
  => tdd per the planning contract.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: S-sized, additive, reversible — 2 code files
  (.aai/scripts/state.mjs, .aai/scripts/lib/docs-audit-core.mjs; possibly
  usage text in .aai/scripts/docs-audit.mjs) plus 2 test suites; no schema
  migration, no irreversible step, no pre-commit-hook surface. Isolation is
  still USEFUL (state.mjs is the loop's live write path — a broken working
  tree blocks STATE writes mid-loop), hence optional rather than not_needed.
  The operator decides; inline with the explicit review scope below is safe.
- User decision: undecided
- Base ref: main
- Worktree branch/path: n/a unless selected
- Inline review scope: .aai/scripts/state.mjs,
  .aai/scripts/lib/docs-audit-core.mjs, .aai/scripts/docs-audit.mjs,
  tests/skills/test-aai-state.sh, tests/skills/test-aai-docs-audit.sh,
  docs/specs/SPEC-0016-spec-slug-refs-across-tooling.md, docs/INDEX.md (generated)
- code_review.required: true (workflow/state tooling change)

## Acceptance Criteria Mapping
- CHANGE AC-001 -> Spec-AC-01 (state.mjs slug acceptance) — verify:
  `node .aai/scripts/state.mjs set-focus/set-phase/append-run --ref <slug>`
  exit 0 on a scratch STATE; `node .aai/scripts/check-state.mjs` exit 0.
- CHANGE AC-002 -> Spec-AC-02 + Spec-AC-05 (gate resolves slug; DRAFT docs
  scanned) — verify: `--gate <slug>` exit 0/1 per fixture table state (never
  2); `--check --strict --path <DRAFT>` reports Scanned: 1.
- CHANGE AC-003 -> Spec-AC-03 (invalid shapes exit 2 + usage) — verify:
  each invalid shape exits 2, STATE byte-identical, message names both shapes.
- CHANGE AC-004 -> Spec-AC-04 (TYPE-000N regression) — verify: existing
  suites green; numbered refs behave byte-identically.
- Constraints (ambiguity order) -> Spec-AC-06 — verify: fixture with a
  frontmatter-id doc and a display-id doc sharing the token; duplicate-id
  fixture exits 2 listing candidates.
- Desired Behavior (allocation durability) -> Spec-AC-07 — verify: simulate
  the allocator rename on a fixture; slug still gates the same doc, slug-keyed
  STATE still passes check-state.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `state.mjs set-focus/set-phase/append-run --ref <slug>` succeed for a SLUG_RE ref (written verbatim as ref_id/work-item key) and the resulting STATE passes check-state.mjs | done | docs/ai/tdd/green-20260715T174902Z-change0012-state-test001-005.log | tdd | TEST-001..003 |
| Spec-AC-02 | `docs-audit --gate <slug>` resolves a `<TYPE>-DRAFT-<slug>.md` doc by frontmatter id and evaluates the gate content (exit 0 reconciled / 1 unreconciled — never 2 for an existing DRAFT) | done | docs/ai/tdd/green-20260715T175254Z-change0012-audit-test006-011.log | tdd | TEST-006 |
| Spec-AC-03 | Refs matching neither REF_RE nor SLUG_RE (uppercase-mixed, spaces, >53 chars, leading/trailing/double hyphen, <3 chars, empty) exit 2 before any write with a usage message naming both shapes; STATE byte-identical | done | docs/ai/tdd/green-20260715T174902Z-change0012-state-test001-005.log | tdd | TEST-004 |
| Spec-AC-04 | Existing `TYPE-000N` refs work byte-identically (REF_RE unchanged); full state + docs-audit suites green; real-repo `--check --strict` exits 0 with zero orphans/violations after the scan widening (pre-existing report-only RES-0001 drift out of scope) | done | docs/ai/tdd/red-20260715T174836Z-change0012-state-test005-mutation.log; docs/ai/tdd/red-20260715T175311Z-change0012-audit-test011-mutation.log; docs/ai/tdd/green-20260715T175254Z-change0012-audit-test006-011.log | tdd | TEST-005, TEST-011 (RED by mutation) |
| Spec-AC-05 | `scanAuditDocs` includes `<TYPE>-DRAFT-<slug>.md`: `--check --strict --path <DRAFT>` scans 1 doc (non-vacuous) and hard-fails on a schema-violating DRAFT | done | docs/ai/tdd/red-20260715T175127Z-change0012-audit-test006-011.log (raw `Scanned: 0 docs` vacuous pass); docs/ai/tdd/green-20260715T175254Z-change0012-audit-test006-011.log | tdd | TEST-007 |
| Spec-AC-06 | Gate resolution order: frontmatter-id pass first, display-id pass second; >1 match in a pass exits 2 listing every candidate path | done | docs/ai/tdd/green-20260715T175254Z-change0012-audit-test006-011.log | tdd | TEST-008, TEST-009 |
| Spec-AC-07 | After a simulated merge-time rename (DRAFT -> `TYPE-000N-<slug>.md`, `number` stamped, `id` unchanged) the same slug gates the same doc with the same verdict, and slug-keyed STATE entries still pass check-state (no migration) | done | docs/ai/tdd/green-20260715T175254Z-change0012-audit-test006-011.log | tdd | TEST-010 |

## Implementation plan
- `.aai/scripts/state.mjs`: add `SLUG_RE` beside `REF_RE`; `refFlag` accepts
  either shape; failure message names both. Consumers (set-focus, set-phase,
  append-run) need no other change — slug chars `[a-z0-9-]` are safe in the
  `new RegExp` item/entry matchers already used for TYPE-000N refs.
- `.aai/scripts/lib/docs-audit-core.mjs`:
  - `scanAuditDocs`: admit DRAFT basenames (D3); keep `fileId: null` for them.
  - `gateDoc`: replace the per-file first-match loop with the two-pass
    resolution + ambiguity error (D2).
- `.aai/scripts/docs-audit.mjs`: no logic change expected; usage comment only
  if needed.
- Tests: extend tests/skills/test-aai-state.sh (unit, scratch STATE fixtures)
  and tests/skills/test-aai-docs-audit.sh (integration, temp fixture repos).
- Edge cases owned by tests: 53-char slug with suffix accepted / 54 rejected;
  pure-digit slug (`2026-07`) accepted as slug (lowercase, never collides
  with REF_RE); slug that looks like a lowercased display id (`spec-0042`)
  resolves via frontmatter pass only; DRAFT doc without frontmatter id
  (violation, hard fail); legacy doc with `id: TYPE-000N` still gates via
  pass 1.

## Seam analysis (cross-feature integration)
- Seam 1: STATE.yaml written by state.mjs, consumed by check-state.mjs /
  loop-digest / dashboard. Crossed end-to-end by TEST-003 (write a slug-keyed
  run via the real CLI, validate with the real check-state) — not mocked.
- Seam 2: the docs scan set shared by docs-audit and generate-docs-index
  (index already DRAFT-aware; audit joins it). Crossed by TEST-011 running
  the real audit + index over the live repo (CLEAN, no new orphans).
- Seam 3: allocator rename (allocate-doc-number.mjs) vs slug-keyed refs in
  STATE and gate resolution. Crossed by TEST-010 simulating the rename on a
  fixture and asserting gate verdict + check-state on both sides.
- Residual risk (explicit): STATE spec_path staleness after allocator rename
  (see D4) — recorded for follow-up, not covered by an automated test in
  this scope because the allocator is out of scope per CHANGE-0012.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Status |
|----------|------------|-------------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-state.sh | `set-focus --type intake_change --ref <slug> --path <p>` exits 0 on a scratch STATE; ref_id written verbatim (RED today: exit 2) | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-state.sh | `set-phase --ref <slug> --phase planning --status in_progress --spec-path docs/specs/SPEC-DRAFT-<slug>.md` upserts the work item; DRAFT spec-path accepted (it is a path, not a ref) | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | `append-run --ref <slug> ...` auto-inits `metrics.work_items.<slug>` and appends; `check-state.mjs` exits 0 on the result (crosses Seam 1 with the real validator) | green |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-state.sh | Each invalid shape — `Mixed-Case`, `has space`, 54-char, `-lead`, `trail-`, `a--b`, `ab`, `""` — exits 2, STATE byte-identical, message names both accepted shapes | green |
| TEST-005 | Spec-AC-04 | regression  | tests/skills/test-aai-state.sh | `TYPE-000N` refs still accepted on all three subcommands; full pre-existing state suite green (REF_RE untouched) | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | Fixture repo with `docs/specs/SPEC-DRAFT-<slug>.md` (frontmatter id = slug): `--gate <slug>` exits 0 when the AC table is reconciled and 1 when a row is non-terminal — proving evaluation, not mere resolution (RED today: exit 2 both ways) | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | `--check --strict --no-event --path <DRAFT-file>` reports `Scanned: 1` and exits 0 for a compliant DRAFT; a DRAFT with a schema violation hard-fails (RED today: Scanned: 0, vacuous exit 0) | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | Order: doc A frontmatter `id: spec-0042` vs doc B filename `SPEC-0042-*.md` — `--gate spec-0042` gates A (frontmatter pass), `--gate SPEC-0042` gates B (display pass) | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | Two docs sharing frontmatter `id` — `--gate <id>` exits 2 and the message lists BOTH candidate paths (RED today: silent first-file-wins) | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | Allocation durability: gate a DRAFT by slug, simulate the merge-time rename (`TYPE-0001-<slug>.md`, `number: 1`, id unchanged), re-gate by the SAME slug — same doc, same verdict; slug-keyed STATE from TEST-003 still passes check-state | green |
| TEST-011 | Spec-AC-04 | regression  | tests/skills/test-aai-docs-audit.sh | `--gate` on an existing numbered doc and `--gate-file` unchanged; full docs-audit suite green; real-repo `--check --strict --no-event` CLEAN (scan widening introduces no new orphans/violations) | green |

RED-proof obligation: every TEST above must be observed FAILING against the
current code before its pass counts (TEST-001..004 and 006..009 fail
naturally today; TEST-005/011 are regression anchors whose RED is proven by
mutation — e.g. deleting REF_RE acceptance — if never otherwise red).

## Verification
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-state.sh`
- `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-docs-audit.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` (real repo CLEAN)
- `node .aai/scripts/generate-docs-index.mjs` (idempotent)
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation/TDD/validation/review artifact record: ref_id
(CHANGE-0012 / spec-slug-refs-across-tooling), Spec-AC + TEST-xxx links,
command, exit code, evidence path (docs/ai/tdd/*.log for RED/GREEN),
commit SHA or diff range.

## Review warning dispositions (2026-07-15)

- W1 (YAML-keyword slugs re-typed when written unquoted): REMEDIATED — refFlag
  refuses bare `null/true/false/yes/off` (exit 2, pre-write); longer slugs
  containing a keyword stay valid. Covered by the TEST-004/W1 stanza in
  tests/skills/test-aai-state.sh. (`no`/`on` are already rejected by min-3.)
- W2 (deriveSlug can emit 1-2-char slugs that SLUG_RE min-3 rejects as --ref):
  PROMOTED as a documented limitation — the mismatch fails loud (exit 2 with a
  usage message) at STATE-write time, never silently; a sub-3-char topic slug
  is a degenerate intake input. If it ever occurs in practice, align by adding
  a min-length pad to deriveSlug (follow-up candidate, not in scope).
- W3 (pre-existing RES-0001 probable-false-done drift blocked 5 real-repo
  CLEAN test assertions): REMEDIATED outside this spec's code scope — RES-0001
  closeout metadata completed (links.pr 49, links.commits 0f9960e, ac_evidence
  event referencing the slug id), restoring repo-wide Verdict: CLEAN.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

---
id: SPEC-0015
type: spec
status: implementing
links:
  requirement: null
  rfc: RFC-0007
  pr: []
  commits: []
---

# SPEC-0015 — Parallel-safe doc numbering: slug-primary identity + merge-time number allocation (RFC-0007)

SPEC-FROZEN: true

## Links
- Decision record (WHAT/WHY): docs/rfc/RFC-0007-parallel-safe-doc-numbering.md (accepted; Option C)
- New allocator engine: .aai/scripts/allocate-doc-number.mjs (created by this spec)
- Index generator being extended: .aai/scripts/generate-docs-index.mjs
- Shared model lib (read-only reference): .aai/scripts/lib/docs-model.mjs (parseFrontmatter, walk, toPosix)
- Guard host: .aai/scripts/pre-commit-checks.sh / .ps1 and the installed hook (.aai/scripts/install-pre-commit-hook.sh, marker AAI:INDEX-AUTOGEN); CI mirror in .github/workflows/
- Prompt/template wiring: .aai/SKILL_INTAKE.prompt.md, .aai/INTAKE_*.prompt.md, .aai/SKILL_PR.prompt.md, .aai/templates/RFC_TEMPLATE.md + SPEC_TEMPLATE.md + peers
- Test suites extended: tests/skills/test-aai-doc-numbering.sh (new), run via .aai/scripts/aai-run-tests.sh
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, zero deps; bash-3.2 test floor; STATE only via state.mjs)

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the allocator engine, the two guards, and the
  index display-id resolution — these are the collision-safety core where a tautological
  test is worthless and a real RED is natural and cheap: no allocator exists today (its
  tests fail at "command not found" / unknown-flag), and the concurrency test fails against
  any working-tree-only stub (the exact bug RFC-0007 fixes). Loop (grep-wiring, RED-proven
  against pre-change text) for the mechanical prompt/template/CI wiring edits (SKILL_INTAKE,
  INTAKE_*, SKILL_PR, templates, pre-commit host). Matches the SPEC-0012/0013/0014 posture:
  discipline where behavior is risky, loop where the change is text wiring.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: the scope spans five-plus independent surfaces (a new allocator
  script, the index generator, the intake prompts, the PR skill, the doc templates, and the
  pre-commit/CI guard host) and changes the durable doc-identity contract that every future
  intake depends on, so an isolated branch keeps a half-wired numbering scheme out of the
  live loop while it is built and dogfooded. Not `required`: the change is strictly additive
  and degrade-and-report (existing numbers are preserved, the allocator falls back to the
  legacy scan-and-mint when absent, and the guards start report-only), there is no
  irreversible migration and no STATE/schema rewrite. Not merely `optional`: it touches the
  pre-commit gate and three-plus independent modules and is PR-bound. The operator may
  elevate to a worktree at Preparation given the pre-commit-gate touch.
- User decision: undecided (Implementation Preparation asks the operator; Planning does not create worktrees)
- Base ref: main
- Worktree branch/path: decided at preparation; suggested feat/rfc-0007-parallel-safe-doc-numbering
- Inline review scope (if inline is chosen): .aai/scripts/allocate-doc-number.mjs,
  .aai/scripts/generate-docs-index.mjs, .aai/scripts/pre-commit-checks.sh,
  .aai/scripts/pre-commit-checks.ps1, .aai/scripts/install-pre-commit-hook.sh,
  .aai/SKILL_INTAKE.prompt.md, .aai/INTAKE_RFC.prompt.md (and peer INTAKE_*.prompt.md),
  .aai/SKILL_PR.prompt.md, .aai/templates/RFC_TEMPLATE.md, .aai/templates/SPEC_TEMPLATE.md,
  tests/skills/test-aai-doc-numbering.sh,
  docs/specs/SPEC-0015-parallel-safe-doc-numbering.md, docs/INDEX.md (generated)

## Design decisions (resolved — do not reopen during implementation)

These operationalize RFC-0007 Option C. The RFC option analysis is closed; this section
only fixes the concrete answers to the RFC's Open Questions.

### D1 — Slug derivation rule and the DRAFT filename convention
- Slug = kebab-case of the topic: lowercase; transliterate to ASCII; replace any run of
  non-`[a-z0-9]` with a single hyphen; strip leading/trailing hyphens; collapse repeated
  hyphens; truncate to at most 48 characters at a hyphen boundary (never mid-word). A slug
  that reduces to empty is rejected (the intake must supply a topic).
- Optional collision-defeating suffix: a 4-character lowercase base36 token derived from the
  branch name (or author + intake timestamp) may be appended as `-abcd`. It is applied when
  the intake requests it or when a same-slug file already exists locally. Same inputs yield
  the same suffix (deterministic, testable); different branches yield different suffixes.
- DRAFT filename convention: `docs/<type>/<TYPE>-DRAFT-<slug>.md`, where `<type>` is the
  lowercase doc-type directory (rfc, specs, issues, requirements, releases) and `<TYPE>` is
  the uppercase id prefix (RFC, SPEC, ISSUE, PRD, CHANGE, RELEASE). Example:
  `docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md`. The literal token `DRAFT` in the
  number slot is the machine-detectable marker of an unnumbered doc.

### D2 — Frontmatter contract (RFC-0007 Open Question: which id is canonical)
Resolved: the slug stays the canonical `id` forever; the sequential integer lives in a new
`number` field; the human-facing `TYPE-000N` display id is a derived value computed by the
index generator. This keeps the durable primary key stable across the merge-time rename and
confines the "basename == id" assumption change to one generator.
- At intake, the DRAFT doc carries:
  - `id: <slug>` (e.g. `rfc-parallel-safe-doc-numbering`) — the stable primary key every
    in-branch cross-reference uses.
  - `number: null` — the sequential display number, assigned at merge.
  - `status: draft`.
- After merge-time allocation, the same doc carries `id: <slug>` UNCHANGED, `number: N`
  (integer), and its filename is `<TYPE>-000N-<slug>.md`. The display id `TYPE-000N` is NOT
  stored; it is resolved from `type` + `number` by the index generator (D5), so there is
  exactly one source of truth for it.
- Rejected alternative: promoting `TYPE-000N` to `id` and demoting the slug to `aka`. That
  would break every in-branch reference on rename and forces a broad "basename == id"
  rewrite — the opposite of Option C's decoupling intent.

### D3 — Allocator CLI contract (.aai/scripts/allocate-doc-number.mjs)
Node stdlib only (zero deps, plain `node` invocation, per docs/TECHNOLOGY.md).
- Invocation: `node .aai/scripts/allocate-doc-number.mjs [--path <draft-file>] [--type <type>] [--base-ref <ref>] [--all] [--backfill] [--dry-run]`.
  Default `--base-ref` is `origin/main`.
- Behavior (normal allocation):
  1. Fetch the base ref (`git fetch <remote> <branch>`; offline is handled by exit 3).
  2. Select the DRAFT doc(s): the explicit `--path`, else (`--all`) every
     `docs/*/*-DRAFT-*.md` in the working tree.
  3. For each, compute the next number for its type as
     `max(existing TYPE-000N in the base ref's docs/<type>/ (read via git, NOT the working
     tree) ∪ locally-numbered-but-unmerged TYPE-000N) + 1`.
  4. `git mv` the DRAFT file to `<TYPE>-000N-<slug>.md` and stamp `number: N` (leaving `id`
     the slug), then rewrite any in-repo references to the old DRAFT basename to the new one.
  5. Regenerate `docs/INDEX.md` (invoke generate-docs-index.mjs).
- Exit codes:
  - 0 — success: one or more drafts numbered, or nothing to do (no DRAFT present is a
    clean no-op, not an error).
  - 2 — usage error (unknown flag, unknown `--type`, `--path` not a DRAFT doc). No writes.
  - 3 — base ref unreachable (offline / fetch failed): degrade-and-report — prints a WARNING,
    leaves the DRAFT file byte-identical, allocates nothing. `/aai-pr` surfaces this and the
    no-DRAFT-at-merge guard (D6) remains the hard backstop; never a silent pass.
  - 4 — guard failure: the computed number would collide with an existing number on the base
    ref, or a selected DRAFT has malformed frontmatter (no slug `id`). No partial rename;
    target files byte-identical.
- `--dry-run` prints the planned renames + numbers and exits 0 without writing.
- `--backfill` (D7) stamps `number:` from an already-numbered filename without renaming.
- Degrade-and-report when the allocator itself is ABSENT (older AAI layer): intake falls
  back to the legacy scan-and-mint numbering and `/aai-pr` notes the missing script and
  proceeds; the CI/pre-commit duplicate-number guard (D6) is the safety net. Absence must
  never hard-break the single-developer flow.

### D4 — Intake wiring (create DRAFT + slug)
- SKILL_INTAKE.prompt.md and each INTAKE_*.prompt.md create the artifact at the DRAFT path
  (D1) with the D2 frontmatter (`id: <slug>`, `number: null`, `status: draft`) instead of
  scanning for and minting `TYPE-000N`. The legacy scan-and-mint remains documented only as
  the allocator-absent fallback.
- The existing STEP 2.6 index regeneration must tolerate the unnumbered DRAFT (D5): a DRAFT
  doc is a valid, non-violating index entry.
- Intake stays fully local and offline: no fetch, no write to main.

### D5 — generate-docs-index.mjs changes
- Display-id resolution: when `fm.number` is a non-null integer, the doc's display id is
  `<TYPE>-` + the zero-padded (width 4) number (type prefix uppercased from the directory /
  frontmatter type); otherwise fall back to `fm.id` (slug) and then the basename (current
  behavior). This replaces the bare `fm.id ?? basename` id resolution for numbered docs.
- AMENDED 2026-07-16 (ISSUE-0006, PR #55): the fixed width-4 above is superseded.
  The zero-padding WIDTH follows the type's existing convention — inherited from the
  type's highest-numbered doc (base ref preferred); an empty type falls back to the
  PROJECT's dominant width across all numbered governed docs (a vendored project with
  an all-3-digit convention mints 3-digit for its first doc of a new type; amended
  same-day via ISSUE project-dominant-width); a greenfield repo uses per-type defaults
  (PRD: 3-digit, e.g. PRD-001; all other prefixes: 4-digit). A numbered FILENAME
  is the display id verbatim (PRD-001-x.md -> PRD-001, never re-padded); the width-4
  padStart remains only as the fallback for number-in-frontmatter-with-DRAFT-filename.
  Cross-padding duplicates (PRD-001 vs PRD-0001) are detected by numeric equality.
  Contract pinned by tests/skills/test-aai-doc-numbering.sh TEST-016; operative wording
  in .aai/INTAKE_COMMON.md.
- Unnumbered drafts: a doc with `number: null` (or absent) AND a DRAFT filename is placed in
  the Drafts section under its slug id and surfaced distinctly (annotated unnumbered), never
  emitted as a schema violation, coverage gap, or near-miss.
- Idempotence and degrade-and-report posture of the generator are preserved (byte-identical
  on a second run modulo the Generated timestamp line).

### D6 — CI / pre-commit guards (Option D as safety net)
Two predicates added to the pre-commit host (.aai/scripts/pre-commit-checks.sh/.ps1) and
mirrored in CI; both start report-only and are flippable to enforce via a config key like the
existing close_gate / body_lint keys:
- No-DRAFT-at-merge: fail when any `docs/*/*-DRAFT-*.md` (or any frontmatter `number: null`
  on a governed doc) is present in the staged/merged tree. Message names the offending draft
  and points to `/aai-pr` / the allocator.
- Duplicate-number: fail when two governed docs of the same type resolve to the same
  `TYPE-000N` (same `type` + `number`, or two identical numeric filename prefixes). Message
  lists the colliding pair.
A clean numbered tree passes both with exit 0.

### D7 — Migration / backfill policy
- Additive. Existing numbered docs keep their numbers; NOTHING is ever renumbered.
- `--backfill` stamps `number:` on already-numbered docs by reading the `TYPE-000N` prefix
  from the filename (no rename, no fetch). It is idempotent: a doc that already carries the
  correct `number` is left byte-identical; running twice is a no-op.
- Backfill is optional. Legacy docs without a `number` field remain valid (the index falls
  back to the filename/slug id per D5), so the new flow can be adopted for new intakes only
  without touching history.

### D8 — SKILL_PR wiring (run allocator before commit)
- SKILL_PR.prompt.md gains a step, BEFORE staging/commit, that runs the allocator against
  the freshly fetched base ref, then adds the resulting numbered file path to the in-scope
  file list (and drops the DRAFT path). If the allocator is absent, note it and proceed
  (D3 fallback). The hard merge boundary (agent never merges) is unchanged.

## Acceptance Criteria Mapping
For each RFC-0007 Option C obligation:

| RFC-0007 obligation | Spec-AC | Verification (command → expected evidence) |
|---|---|---|
| Slug identity + DRAFT filename (Option C.1) | Spec-AC-01 | TEST-001/002: slug derivation unit cases + DRAFT filename assembly + deterministic collision suffix |
| Frontmatter contract id/number (Open Q) | Spec-AC-02 | TEST-003: intake DRAFT carries id=slug/number:null/status:draft; docs-audit --check --strict on it exit 0; index places it in Drafts, no violation |
| Merge-time allocator (Option C.2) | Spec-AC-03 | TEST-004/005: allocator renames DRAFT→TYPE-000N, stamps number, keeps slug id, regenerates index; exit codes 0/2/3/4 exact |
| Collision-proof by construction (Option C.2) | Spec-AC-04 | TEST-006 (CONCURRENCY): two branches off the same main serialize-merge; the second re-derives the next number, never a duplicate |
| CI duplicate + no-DRAFT guard (Option C.3 / Option D) | Spec-AC-05 | TEST-007/008: no-DRAFT-at-merge rejects a DRAFT tree; duplicate-number guard rejects a colliding pair; clean tree exit 0 |
| Index tolerates/display-resolves (Consequences) | Spec-AC-06 | TEST-009: numbered doc shows TYPE-000N; unnumbered draft shows slug distinctly; index byte-idempotent |
| Degrade-and-report when absent (Migration) | Spec-AC-07 | TEST-010: allocator-absent path — intake falls back, no hard error; guard still catches a resulting collision |
| Additive migration / backfill (Migration) | Spec-AC-08 | TEST-011: backfill stamps number from filename without rename; existing number preserved; twice byte-identical |
| Intake + PR + template + CI wiring | Spec-AC-09 | TEST-012: grep-wiring — SKILL_PR runs allocator pre-commit; intake creates DRAFT+slug; templates carry number + slug-as-PK; guards invoked |
| No regression / repo clean | Spec-AC-10 | TEST-013: new suite exit 0; repo docs-audit --check --strict --no-event CLEAN; index twice byte-idempotent; existing suites unaffected |

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | Slug derivation rule (kebab ≤48, deterministic 4-char collision suffix) and the `<TYPE>-DRAFT-<slug>.md` filename convention per D1 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-02 | Intake DRAFT frontmatter contract per D2: `id`=slug, `number: null`, `status: draft`; passes docs-audit --check --strict; slug canonical, TYPE-000N derived | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-03 | Allocator computes next number from the BASE REF (not the working tree), renames+stamps, regenerates index; exit codes 0/2/3/4 exact per D3 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-04 | Collision-proof by construction: two branches minted from the same main cannot both merge the same number; the second re-derives the next (D3 step 3) | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-05 | No-DRAFT-at-merge guard and duplicate-number guard per D6 fail the offending tree and pass a clean numbered tree | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-06 | Index resolves the display id from `number`, tolerates and distinctly surfaces unnumbered drafts, stays byte-idempotent per D5 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-07 | Allocator-absent degrade-and-report: intake falls back to scan-and-mint, `/aai-pr` proceeds, the guard is the backstop; no hard break per D3 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-08 | Additive migration: existing numbers preserved; `--backfill` stamps `number` from filename without rename, idempotent per D7 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-09 | Wiring present: SKILL_PR runs the allocator pre-commit; intake creates DRAFT+slug; templates carry `number` + slug-as-primary-key; guards invoked per D4/D6/D8 | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |
| Spec-AC-10 | No regression: new suite green; repo docs-audit CLEAN; index byte-idempotent; existing suites unaffected | done | docs/ai/tdd/green-20260715T133821Z.log | TDD | 13/13 TEST green (see Test Plan) |

Status values: planned | implementing | done | deferred | blocked | rejected (gate behavior per template).

## Implementation plan
- New engine (TDD, .aai/scripts/allocate-doc-number.mjs): pure `deriveSlug(topic)` +
  `draftFilename(type, slug, suffix?)` + `nextNumber(type, baseRefListing, localListing)`
  helpers (unit-testable without git), wrapped by a thin CLI that shells `git fetch` /
  `git show <ref>:docs/<type>/` for the base-ref listing, `git mv`, and frontmatter stamping
  (reuse parseFrontmatter shape from lib/docs-model.mjs). Exit-code table per D3.
- Generator (TDD, generate-docs-index.mjs): display-id resolver from `type` + `number`;
  unnumbered-draft tolerance + distinct surface; keep idempotence.
- Guards (TDD, pre-commit-checks.sh + .ps1 predicate + CI mirror): no-DRAFT-at-merge and
  duplicate-number, report-only default, config-flippable.
- Wiring (loop, RED-proven by grep): SKILL_INTAKE, INTAKE_*, SKILL_PR, RFC_TEMPLATE +
  SPEC_TEMPLATE + peers (add `number` field + slug-as-primary-key note).
- Edge cases owned by tests: empty/oversized topic; same-slug collision on one branch;
  offline fetch; malformed DRAFT frontmatter; two DRAFTs of the same type in one PR; a doc
  already numbered (backfill no-op); missing allocator script; number width/zero-padding.

## Seam analysis (cross-feature integration)
- Seam 1: allocator output ↔ generate-docs-index (allocator stamps `number`; the index reads
  it to render `TYPE-000N`). Two features writing/reading the same identity field. Crossed
  end-to-end by TEST-004 (allocate then assert the index shows TYPE-000N) — not two mocked
  unit tests.
- Seam 2: allocator rename ↔ in-branch references (links.rfc/spec, AC-table Notes, INDEX
  rows) that point at the DRAFT basename. Crossed by TEST-004 asserting references are
  rewritten and the index is internally consistent after rename.
- Seam 3: DRAFT frontmatter ↔ docs-audit --check / index schema (an unnumbered DRAFT must
  pass the schema gate, not read as a violation or near-miss). Crossed by TEST-003 running
  the real audit + index over a DRAFT doc.
- Seam 4: allocator/guard ↔ the merge serialization point (two clones writing the same number
  namespace on main). Crossed by TEST-006, the concurrency centerpiece, in a temp git repo
  with two branches off one main and serialized merges.
- Seam 5: guards ↔ the pre-commit/CI runner host (the predicate must actually fire in the
  hook, not just as a standalone script). Crossed by TEST-007/008/012.
- Residual risk (accepted, matches RFC-0007 Risks): the by-construction guarantee holds only
  while merges to main are actually serialized (gated path). If an operator bypasses the gate
  with a direct push, the duplicate-number guard is the sole backstop; documented, not
  automatable from this repo.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Status |
|----------|------------|-------------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-doc-numbering.sh | `deriveSlug` cases: mixed case/punctuation/whitespace → kebab; oversized topic truncated ≤48 at a hyphen boundary; empty-reduced topic rejected; `draftFilename` assembles `docs/<type>/<TYPE>-DRAFT-<slug>.md` | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-doc-numbering.sh | Collision suffix: same topic + same branch → identical 4-char base36 suffix (deterministic); different branches → different suffixes; suffix applied when a same-slug DRAFT already exists locally | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-doc-numbering.sh | A DRAFT doc with `id: <slug>`, `number: null`, `status: draft` passes `docs-audit --check --strict --no-event --path`; `generate-docs-index` places it in Drafts with the slug id, no schema violation / near-miss / coverage gap | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-doc-numbering.sh | Allocator on a DRAFT against a fixture base ref whose max is RFC-0006 → renames to `RFC-0007-<slug>.md`, stamps `number: 7`, leaves `id` the slug, rewrites references, regenerates index showing `RFC-0007`; exit 0 | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-doc-numbering.sh | Allocator exit codes: bad args → 2 (no writes); base ref unreachable → 3 (DRAFT byte-identical, warning printed); malformed DRAFT frontmatter (no slug id) → 4 (no partial rename); `--dry-run` prints plan, exits 0, writes nothing | green |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-doc-numbering.sh | CONCURRENCY (centerpiece): temp git repo, two branches A and B off one main (max RFC-0006). A allocates → RFC-0007, merges to main. B allocates against the updated main → re-derives RFC-0008 (NOT 0007); assert no duplicate number and B's file is `RFC-0008-<slug>.md`. RED-proofed against a working-tree-only stub (which double-mints 0007) | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-doc-numbering.sh | No-DRAFT-at-merge guard: a tree containing `docs/rfc/RFC-DRAFT-*.md` (or `number: null`) → guard exit non-zero naming the draft; a fully-numbered tree → exit 0 | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-doc-numbering.sh | Duplicate-number guard: two RFC docs both resolving to RFC-0007 → guard exit non-zero listing the colliding pair; unique numbers → exit 0 | green |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-doc-numbering.sh | Index display-id: a doc with `number: 7` renders `RFC-0007`; a `number: null` DRAFT renders its slug in a distinct unnumbered surface; `generate-docs-index` twice → byte-identical modulo the Generated line | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-doc-numbering.sh | Allocator-absent fallback: with the script renamed away, the intake path degrades to scan-and-mint without a hard error, `/aai-pr` reports the missing script and proceeds, and the duplicate-number guard still catches a resulting collision (grep-wiring for the fallback clause + functional missing-script probe) | green |
| TEST-011 | Spec-AC-08 | integration | tests/skills/test-aai-doc-numbering.sh | Backfill: `--backfill` stamps `number: 6` on a legacy `RFC-0006-*.md` from its filename, no rename, existing content byte-preserved; second run byte-identical; a doc already carrying the correct number is untouched | green |
| TEST-012 | Spec-AC-09 | integration | tests/skills/test-aai-doc-numbering.sh | Wiring grep: SKILL_PR invokes `allocate-doc-number.mjs` before staging and adds the numbered path to scope; SKILL_INTAKE + INTAKE_* create `*-DRAFT-*` with `number: null`; RFC/SPEC templates carry a `number` field and a slug-as-primary-key note; pre-commit host references both guards | green |
| TEST-013 | Spec-AC-10 | e2e         | tests/skills/test-aai-doc-numbering.sh | Regression backstop: full new suite exit 0; repo `docs-audit --check --strict --no-event` CLEAN exit 0; `generate-docs-index` twice byte-idempotent; existing state/hygiene/docs-audit suites unaffected | green |

Test status values: pending → red → green.

RED-proof obligation (all strategies): TEST-001..006 and TEST-009 are natural TDD — no
allocator or display-id resolver exists today, so their RED is real (command-not-found /
unknown-flag / the slug and next-number helpers are undefined; the display-id resolver still
emits the slug). TEST-006's RED is the RFC-0007 bug itself: a working-tree-only stub
double-mints RFC-0007 for both branches and must be observed FAILING before the base-ref
allocator turns it GREEN. TEST-007/008 RED against the pre-change pre-commit host (no guard
predicate yet). TEST-010/012 grep-wiring RED against the pre-change prompt/template/host text.
TEST-011 RED against the absent `--backfill` mode. TEST-013 is the regression backstop (green
before and after; its failure capability is proven by the other suites' negative controls).
Capture RED/GREEN logs under docs/ai/tdd/ per the evidence contract.

## Verification
- `bash tests/skills/test-aai-doc-numbering.sh` → exit 0 (all TEST-001..013), run via `.aai/scripts/aai-run-tests.sh` (LEARNED: never spawn runners directly)
- `node .aai/scripts/allocate-doc-number.mjs --dry-run --path docs/rfc/RFC-DRAFT-<slug>.md` on a fixture base ref at RFC-0006 → prints "RFC-0007-<slug>.md, number 7", writes nothing
- Concurrency walk-through (temp git repo): two branches off one main, serialized merges → numbers 0007 then 0008, no duplicate (TEST-006)
- `node .aai/scripts/generate-docs-index.mjs` twice → second run byte-identical modulo the Generated line; DRAFT docs surfaced distinctly, numbered docs show TYPE-000N
- Pre-commit guard probes: a DRAFT-bearing tree and a duplicate-number tree each rejected; a clean numbered tree passes
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0, Verdict CLEAN
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0015-parallel-safe-doc-numbering.md` → exit 0 (this spec)
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact record: ref_id
(RFC-0007 / SPEC-0015), Spec-AC + TEST-xxx links, command or review scope, exit code or
verdict, evidence path (docs/ai/tdd/*.log for RED/GREEN; docs/ai/reviews/* for review),
commit SHA or diff range.

## Code review plan (initial)
- code_review.required: true (new engine + guard + generator change on the shared doc-identity path).
- Scope: the inline review scope list above (explicit paths).
- Base ref: main. Review runs after Validation PASS, per WORKFLOW.

Notes:
This document defines HOW, not WHAT/WHY (WHY lives in RFC-0007).
This document does not define workflow.

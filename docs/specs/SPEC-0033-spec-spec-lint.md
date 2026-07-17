---
id: spec-spec-lint
type: spec
number: 33
status: done
ceremony_level: 2
links:
  requirement: spec-lint
  research: RES-0001
  pr:
    - 82
  commits:
    - 18b861f
---

# SPEC — spec-lint.mjs: Deterministic Structural Validation of Spec Documents

SPEC-FROZEN: true

## Links
- Requirement: spec-lint (docs/issues/CHANGE-0022-spec-lint.md)
- Research: RES-0001 P3 — OpenSpec deterministic spec-structure lint pattern
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
This spec declares `ceremony_level: 2` (the default full pipeline): the scope
is M — a new deterministic CLI, edits to two role prompts (.aai/PLANNING.prompt.md,
.aai/VALIDATION.prompt.md), a new test suite, and one governed-spec evidence-
formatting fix. No `protected_paths_l3` surface is touched (the role prompts are
not on the docs/ai/docs-audit.yaml list), so level 3 is not mandatory; the scope
is well above a single-surface level-1 fix.

## Implementation strategy
- Strategy: hybrid
- Rationale: the lint engine (finding classes, table parsing reuse, exit-code
  contract) is core deterministic tooling — fixture-driven TDD (TEST-001..009
  observed RED first: the suite fails on the pre-change tree because the CLI
  does not exist and the real corpus cannot be linted). The prompt wiring
  (PLANNING/VALIDATION advisory lines) is text — grep-RED (TEST-010 in the same
  pre-change RED run), one focused pass. TEST-011 is a survival-invariant seam
  test (strict audit, prompt-diet floor, index double-regeneration stability).
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-spec-lint.sh` on the pre-change tree and save the
  failing output to `docs/ai/tdd/spec-lint-red.log` (expected: TEST-001..010
  FAIL — no `.aai/scripts/spec-lint.mjs`, no advisory wiring; TEST-011 passes
  pre-change BY CONSTRUCTION — it is the survival invariant re-run over the
  grown corpus after the change, non-vacuous because the change adds a new
  governed spec, edits two prompts in the diet corpus, and edits SPEC-0012).

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: edits two workflow role prompts (protected AAI workflow
  surfaces per PLANNING step 8) plus repo tooling under .aai/scripts/.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-p3-speclint, branch feat/spec-lint)
- Base ref: main
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0033-spec-spec-lint.md (this spec)
  - docs/issues/CHANGE-0022-spec-lint.md (links backfill only)
  - .aai/scripts/spec-lint.mjs (new CLI)
  - .aai/PLANNING.prompt.md (post-freeze advisory line, step-10 continuation)
  - .aai/VALIDATION.prompt.md (step-1 advisory line)
  - tests/skills/test-aai-spec-lint.sh (new suite)
  - docs/specs/SPEC-0012-loop-reliability-transactional-state-cli.md
    (evidence-formatting fix: escaped pipes broke the shared AC-row parse)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Boundary: spec-lint owns intra-spec STRUCTURE; docs-audit owns lifecycle/drift
No check is duplicated between the two engines. The authoritative split:

| Concern | spec-lint (this change) | docs-audit / close gate |
|---------|-------------------------|--------------------------|
| Spec-AC ids unique + sequential (01..N, canonical form) | OWNS (`ac-id-duplicate`, `ac-id-gap`, `ac-id-malformed`) | never checks |
| AC row invisible to the shared parser (cell-count break, e.g. escaped pipes) | OWNS (`ac-row-unparseable`) | silently drops the row today |
| Test Plan row references unknown/malformed Spec-AC id | OWNS (`test-ac-unknown`, `test-ac-malformed`) | never parses the Test Plan |
| SPEC-FROZEN body marker vs strategy + AC-table presence | OWNS (`frozen-without-strategy`, `frozen-without-ac-table`) | never checks |
| AC row status token validity | advisory per-spec finding (`ac-status-invalid`) at ANY lifecycle point | schema violation in the corpus scan (hard-fails `--check` in enforced mode) |
| done AC row with empty Evidence | advisory finding (`done-without-evidence`) at ANY lifecycle point — catches it at freeze/mid-flight | drift verdict on `status: done` docs + close-time gate (done-flip refusal path) |
| ceremony_level enum (present, non-null, not 0..3) | advisory finding (`ceremony-level-invalid`) at freeze time | close-gate reason at done-flip; the L0/L1 `Ceremony justification:` line check stays GATE-ONLY |
| Orphans, frontmatter id/status/type schema, staleness, false-done, close telemetry, Review-By claims, body lint, closeout candidates | out of scope | OWNS |

The three shared-concern rows differ by WHEN and HOW they fire (advisory
report-only per-spec at any point vs corpus drift/close-time enforcement); the
underlying token rules are single-sourced through the shared
lib/docs-model.mjs parsers/normalizers, so the engines cannot drift on what a
valid status or evidence cell IS.

### D2 — Reuse the shared parsers; never fork them
spec-lint imports ONLY from `.aai/scripts/lib/docs-model.mjs`
(`parseFrontmatter`, `parseAcTable`, `normalizeAcStatus`, `specFrozenInBody`,
`normalizeNewlines`, `toPosix`) — the exact parsers docs-audit and the index
generator consume, so all three engines see the identical AC table. No import
from docs-audit-core (that module owns lifecycle/git/EVENTS probing, none of
which spec-lint needs). The only new parser is the Test Plan table reader —
nothing in the repo parses `## Test Plan` today, so it is new code, not a
fork. It honors markdown escaped pipes when splitting cells (correct
CommonMark behavior for a NEW parser with no legacy consumers). The Evidence
non-emptiness predicate (empty / em-dash / dash) is a one-line local mirror
of the docs-audit-core rule, documented at the definition site.

### D3 — Finding classes (deterministic, line-anchored where possible)
Over the canonical `Acceptance Criteria Status` table (via shared parseAcTable):
- `ac-id-malformed` — id not matching `Spec-AC-NN` (two digits).
- `ac-id-duplicate` — same id on more than one row.
- `ac-id-gap` — well-formed ids do not cover 1..N exactly (names the missing ids).
- `ac-status-invalid` — status fails the shared normalizeAcStatus canonical
  test (qualified forms like `done (pre-existing)` are canonical and pass).
- `done-without-evidence` — normalized base status `done` with empty Evidence.
- `ac-row-unparseable` — a body line matching `^| Spec-AC-<digit>` inside the
  AC Status section whose id is absent from the parsed rows: the shared parser
  dropped it (cell-count mismatch, e.g. markdown-escaped pipes in a cell), so
  docs-audit, the index, and the close gate are all blind to it. Template
  placeholder rows (`Spec-AC-xx`) are excluded by the digit requirement.
Over the `Test Plan` table (new tolerant parser):
- `test-ac-unknown` — a Spec-AC token (single id, comma/space list, or an
  `NN..MM` range) resolving to an id not present in the AC Status table.
- `test-ac-malformed` — a Spec-AC cell that is empty/dash or carries a token
  not matching the id/range grammar.
Whole-doc consistency:
- `frozen-without-strategy` — SPEC-FROZEN true (shared specFrozenInBody) and
  the `- Strategy:` line is absent or `undecided`. Exempt at effective
  ceremony level 0 and 1 (RFC-0009 lean artifacts carry no strategy section;
  absent level = 2, so legacy specs are fully checked).
- `frozen-without-ac-table` — SPEC-FROZEN true but no canonical AC Status
  gate table. Exempt at level 0 only (the L0 tech-note lives in a CHANGE doc).
- `ceremony-level-invalid` — frontmatter field present and non-null but not
  one of 0|1|2|3 (YAML null counts as absent, matching the close gate).

### D4 — CLI contract (house conventions)
`node .aai/scripts/spec-lint.mjs [--path <file>] [--json]`
- Default scope: every `docs/specs/**/*.md` whose frontmatter `type` is
  `spec` (RES research docs are skipped and reported as skipped); `--path`
  lints exactly one explicit file regardless of type (an operator probing an
  L0 CHANGE tech-note or a staged blob).
- Exit codes: 0 clean / 1 findings / 2 usage error or unreadable `--path`
  (mirrors docs-audit `--gate` and layer-drift conventions).
- `--json` prints one object:
  `{ scanned, skipped, findings: [{ rel, id, rule, detail, line }], clean }`.
- Report-only posture: the CLI never writes any file, never emits EVENTS, and
  is wired ONLY as an advisory line in the role prompts — never a hard gate in
  v1 (enforcement dial is an explicit follow-up after field experience, per
  the intake out-of-scope line).
- Degrade clause (Constitution art. 4): the prompts instruct "if the script is
  absent, note it and continue" — an older vendored layer degrades gracefully.

### D5 — Real-corpus findings are fixed, not whitelisted
Pre-implementation probe of all 30 governed specs found exactly one real
cluster: SPEC-0012's `Spec-AC-08` row uses markdown-escaped pipes in its
Evidence/Notes cells, which breaks the shared cell split (the row parses into
more cells than the header) — parseAcTable silently DROPS the row, so the
close gate and index never saw it, and its TEST-011/TEST-021 mappings dangle.
Fix: reformat the AC row's Evidence parenthetical to carry no raw or escaped
pipe characters, preserving meaning (the Test Plan rows need no edit — the new
Test-Plan parser honors escaped pipes, so their cells align); the row becomes
visible to every engine again (INDEX progress for SPEC-0012 moves 11/11 to
12/12 at regeneration — a truth restoration, not drift). With that fix the
whole corpus lints clean, so NO whitelist mechanism ships in v1 (YAGNI,
Constitution art. 2): the first field need for suppression is the trigger to
design one deliberately. The `ac-row-unparseable` class regression-guards this
exact shape (TEST-007 fixture replicates the pre-fix row).

### D6 — New suite, sourcing-compatible, scratch fixtures
All gating tests land in NEW tests/skills/test-aai-spec-lint.sh (bash 3.2,
exit 0/1/42, per-test functions — same shape as test-aai-layer-drift.sh).
Fixture specs are generated in a mktemp scratch root with its own docs/specs
tree; the CLI runs with the scratch root as cwd, so the real repo docs are
never touched by fixture arms. TEST-009 runs the CLI against the REAL repo
corpus (the all-current-specs-clean arm).

## Acceptance Criteria Mapping
- Maps to: CHANGE spec-lint AC-001 (fixture catches + clean corpus)
  - Spec-AC-01: spec-lint.mjs exists; on fixtures it reports each finding class
    in D3 with exit 1 and correct `--json` shape, and exits 0 on a clean
    fixture, 2 on usage error/unreadable path; negative controls (qualified
    status, list/range Test-Plan refs, absent ceremony field, lean L1 frozen
    spec) produce no findings.
  - Verification: TEST-001..TEST-008.
- Maps to: CHANGE spec-lint AC-001 (real corpus: 0 findings, real findings fixed)
  - Spec-AC-02: the default-scope run over all governed repo specs exits 0 with
    0 findings; the SPEC-0012 escaped-pipe evidence formatting is fixed so its
    Spec-AC-08 row parses (visible to audit/index/gate); the
    `ac-row-unparseable` class catches the pre-fix shape on a fixture.
  - Verification: TEST-007, TEST-009.
- Maps to: CHANGE spec-lint AC-002 (advisory wiring with degrade)
  - Spec-AC-03: .aai/PLANNING.prompt.md (post-freeze, step-10 continuation) and
    .aai/VALIDATION.prompt.md (step 1) each carry an advisory spec-lint
    instruction of at most 2 lines including the absent-script degrade clause;
    no step renumbering in either prompt.
  - Verification: TEST-010.
- Maps to: CHANGE spec-lint AC-003 (hygiene holds)
  - Spec-AC-04: new suite green; full tests/skills sweep green (validation-
    owned; known pre-existing environmental exception per LEARNED 2026-07-15:
    test-aai-worktree.sh fails deterministically on this machine); repo-wide
    strict docs audit exits 0; prompt-diet floor holds; docs index
    regeneration stable (double-regen identical modulo the Generated stamp);
    check-state OK.
  - Verification: TEST-011 + validation-owned full sweep.

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md v1):
- Art. 1 (evidence before claims): the lint ADDS deterministic evidence about
  spec structure; advisory posture never weakens existing gates. No deviation.
- Art. 2 (simplicity/YAGNI): no whitelist mechanism, no enforcement dial in v1
  (D5, intake out-of-scope); new parser only where none exists. No deviation.
- Art. 3 (portability): plain .mjs + markdown; no services. No deviation.
- Art. 4 (degrade and report): absent-script degrade clause in both prompts;
  unreadable path exits 2 with context. No deviation.
- Art. 5 (additive first): prompts gain continuation lines only (no step
  renumbering); shared parsers untouched; new CLI is additive. No deviation.
- Art. 6 (single-writer STATE): the CLI never touches STATE; all STATE writes
  in this change go through state.mjs. No deviation.
- Art. 7 (operator-only merge): no merge; work stays on feat/spec-lint. No
  deviation.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Lint engine: every D3 finding class on fixtures; exit/json contract; negative controls | done | TEST-001..008 green: docs/ai/tdd/spec-lint-green.log; RED-proof: docs/ai/tdd/spec-lint-red.log | — | — |
| Spec-AC-02 | Real corpus 0 findings; SPEC-0012 evidence formatting fixed; unparseable-row class guards regression | done | TEST-007 + TEST-009 green: docs/ai/tdd/spec-lint-green.log (pre-fix corpus run showed the 4-finding SPEC-0012 cluster) | — | — |
| Spec-AC-03 | PLANNING + VALIDATION advisory wiring, at most 2 lines each, with degrade clause | done | TEST-010 green: docs/ai/tdd/spec-lint-green.log | — | — |
| Spec-AC-04 | Hygiene: suite + sweep green, strict audit CLEAN, diet floor, index stable, check-state OK | done | TEST-011 green: docs/ai/tdd/spec-lint-green.log; sweep log in validation notes | — | sweep validation-owned; worktree suite env-fail known pre-existing (LEARNED 2026-07-15) |

## Implementation plan
- Components affected: .aai/scripts/spec-lint.mjs (new), .aai/PLANNING.prompt.md,
  .aai/VALIDATION.prompt.md, tests/skills/test-aai-spec-lint.sh (new),
  docs/specs/SPEC-0012-loop-reliability-transactional-state-cli.md (cell
  reformat), docs/INDEX.md (regenerated).
- Order: (1) write the suite; (2) RED run on the pre-change tree, save
  docs/ai/tdd/spec-lint-red.log; (3) implement spec-lint.mjs (TEST-001..008
  GREEN); (4) fix SPEC-0012 cells (TEST-009 GREEN); (5) prompt wiring
  (TEST-010 GREEN); (6) index regen + TEST-011; (7) full sweep + check-state;
  (8) AC table reconciliation; (9) STATE via CLI.
- Edge cases: qualified AC statuses (`done (pre-existing)`) are canonical and
  never flagged; `ceremony_level: null` is absent semantics; Test-Plan range
  `Spec-AC-01..03` expands before resolution; placeholder rows (`Spec-AC-xx`,
  angle tokens) are skipped exactly as the shared parser skips them; a spec
  with no Test Plan section yields no Test-Plan findings (lean specs); CRLF
  content is normalized once at entry via the shared helper.
- Seam analysis:
  - Seam S1 — shared docs-model parsers are consumed by docs-audit, the index
    generator, AND spec-lint; the SPEC-0012 cell fix changes what those
    engines see. Crossing test: TEST-009 (real corpus through the shared
    parsers) + TEST-011 strict-audit arm + index double-regeneration.
  - Seam S2 — the .aai prompt corpus is shared with the prompt-diet byte
    floor. Crossing test: TEST-011 runs the real prompt-diet suite after the
    two prompt insertions.
  - Seam S3 — this spec itself joins the governed corpus (a new DRAFT spec
    with an AC table). Crossing test: TEST-009 lints it live; TEST-011 audits
    it strictly.
  - Residual risk (recorded): the advisory lines rely on role-prompt
    discipline (LLM consumers) — no mechanical hook runs spec-lint in v1;
    accepted per the intake's report-only posture, enforcement dial deferred.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)               | Description                                                                 | Status  |
|----------|------------|-------------|-------------------------------------|------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | duplicate Spec-AC id fixture -> exit 1 with `ac-id-duplicate` naming the id | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | id gap fixture -> `ac-id-gap` naming missing ids; malformed id -> `ac-id-malformed` | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | done row with empty Evidence -> `done-without-evidence`; qualified `done (pre-existing)` WITH evidence -> clean control | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | Test Plan row naming unknown AC -> `test-ac-unknown`; list + `NN..MM` range forms resolve (control); dash/garbage cell -> `test-ac-malformed` | green |
| TEST-005 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | frozen without strategy -> finding; frozen without AC table -> finding; lean L1 frozen fixture (ceremony_level 1 + justification, AC table only) -> NO strategy finding | green |
| TEST-006 | Spec-AC-01 | unit        | tests/skills/test-aai-spec-lint.sh | ceremony_level `banana`/`7` -> `ceremony-level-invalid`; absent/null -> clean; invalid AC status token -> `ac-status-invalid` | green |
| TEST-007 | Spec-AC-02 | unit        | tests/skills/test-aai-spec-lint.sh | escaped-pipe AC row fixture (pre-fix SPEC-0012 shape) -> `ac-row-unparseable` with line number | green |
| TEST-008 | Spec-AC-01 | integration | tests/skills/test-aai-spec-lint.sh | scratch-root default scan: clean multi-spec fixture exits 0; research type skipped; unknown flag / unreadable --path exit 2; --json shape (scanned/findings/clean) | green |
| TEST-009 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh | REAL corpus: default run at repo root exits 0 with 0 findings (after the SPEC-0012 evidence-formatting fix) | green |
| TEST-010 | Spec-AC-03 | integration | tests/skills/test-aai-spec-lint.sh | wiring greps: PLANNING post-freeze + VALIDATION step-1 advisory lines present, at most 2 lines each, degrade clause included, no step renumbering | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-spec-lint.sh | seam survival: repo-wide strict audit exit 0, prompt-diet suite green, index double-regeneration stable modulo Generated stamp | green |

Notes:
- RED-proof: TEST-001..TEST-010 observed FAILING on the pre-change tree
  (docs/ai/tdd/spec-lint-red.log). TEST-011 is the survival invariant (green
  pre-change by construction; non-vacuous — see Implementation strategy).
- Full tests/skills sweep is validation-owned. Known environmental exception
  per LEARNED 2026-07-15: tests/skills/test-aai-worktree.sh fails
  deterministically on this machine pre-existing on clean main.

## Verification
- `bash tests/skills/test-aai-spec-lint.sh` -> exit 0, all 11 stanzas PASS.
- `node .aai/scripts/spec-lint.mjs` (repo root) -> exit 0, 0 findings.
- `node .aai/scripts/spec-lint.mjs --json` -> parseable object, `clean: true`.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- `node .aai/scripts/generate-docs-index.mjs` twice -> second regeneration
  produces no diff modulo the `Generated:` stamp (stability probe).
- `node .aai/scripts/check-state.mjs` -> OK.
- Full sweep: `for t in tests/skills/test-*.sh; do bash "$t"; done` (worktree
  suite exception noted above).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-lint
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/spec-lint-red.log, docs/ai/tdd/spec-lint-green.log)
- commit SHA or diff range when available

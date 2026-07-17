---
id: spec-constitution
type: spec
number: 28
status: done
links:
  change: constitution
  research: RES-0001
  pr:
    - 74
  commits:
    - 2a36132
---

# SPEC — Project Constitution With Justified-Exception Tracking

SPEC-FROZEN: true

## Links
- Change: constitution (docs/issues/CHANGE-0019-constitution.md, AC-001..AC-003)
- Research: RES-0001 P2 recommendation 10 — spec-kit constitution pattern
  (short ratified article list checked at a gate) plus its Complexity Tracking
  accountable-deviation pattern (gate exceptions must be documented and
  justified in the plan, never silently ignored) —
  docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: docs-and-prompt-text work with deterministic grep-based
  verification, same class as SPEC-0025/SPEC-0027. Every gating test is a
  grep/wc stanza trivially RED-provable by one pre-change run of the new
  suite (the constitution does not exist yet, wiring markers absent).
  RED-GREEN-REFACTOR per test adds no signal over one focused pass plus a
  recorded RED run.
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-constitution.sh` on the pre-change tree and
  save the failing output to `docs/ai/tdd/constitution-red.log` (expected:
  TEST-001..TEST-007 FAIL; TEST-008..TEST-010 pass pre-change by
  construction — they guard invariants that must SURVIVE the change, and are
  non-vacuous because TEST-008 re-audits all legacy specs after the template
  starts requiring the section for new specs, TEST-009 re-runs the
  prompt-diet suite after the PLANNING corpus grows, and TEST-010 re-audits
  the repo after the new docs land).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive new doc + template section + one new suite;
  the only edits to existing protected prompts are additive insertions inside
  PLANNING step 10 and one AGENTS.md list line. Isolation is useful, not
  safety-critical.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-feat-constitution, branch feat/constitution)
- Base ref: main (merge-base 253cd77 at freeze time)
- Inline review scope (explicit paths):
  - docs/CONSTITUTION.md (new)
  - .aai/PLANNING.prompt.md (additive article-check inside step 10)
  - .aai/templates/SPEC_TEMPLATE.md (one new optional section)
  - .aai/AGENTS.md (one canonical-sources line)
  - tests/skills/test-aai-constitution.sh (new)
  - docs/issues/CHANGE-0019-constitution.md (intake, already saved)
  - docs/specs/SPEC-0028-spec-constitution.md (this spec)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Ratified constitution `docs/CONSTITUTION.md` (≤60 lines)
Short numbered-article document (spec-kit pattern), NOT a governed doc (no
TYPE-000N/DRAFT filename, so it sits outside the docs-audit scan set, like
docs/TECHNOLOGY.md). Articles DISTILL .aai/AGENTS.md — each article is ONE
sentence plus a `(see: ...)` pointer to its authoritative source section;
the constitution never copies rule bodies (dedupe stays with AGENTS.md).
Required articles (≥6): evidence-before-claims, simplicity (KISS/YAGNI),
file-based tri-platform portability, degrade-and-report, additive-first /
backward compatibility, single-writer STATE, operator-only merge.
Ratification header, exact literal:
`Proposed for ratification by: project owner (ales@holubec.net) — ratifies by merging the introducing PR; v1, 2026-07-16` — the owner
approved this scope in-session ("pokracuj s P2" covering RES-0001 P2
recommendation 10). Amendments bump the version and re-ratify.

### D2 — PLANNING freeze-step article check (inside step 10, no renumber)
The check lands INSIDE the existing step 10 (SPEC-FROZEN) of
.aai/PLANNING.prompt.md as continuation lines — NOT as a new numbered step —
because CHANGE-0017 (brief emit, step 11) and SPEC-0012 (STATE CLI, step 12)
already consumed one renumber each; a third renumber would churn every
cross-reference again. Freeze now additionally requires: read
docs/CONSTITUTION.md, check each article against the planned scope, and
record a `## Constitution deviations` section in the spec — either the
literal `None.` or a justified list (article number, the deviation, why it
is justified). An unjustifiable deviation blocks freeze (accountable
deviation: exceptions become auditable artifacts, spec-kit Complexity
Tracking).

### D3 — Section optionality: required-new, optional-legacy
The `## Constitution deviations` section is REQUIRED for new specs going
forward (enforced through the PLANNING freeze step + SPEC_TEMPLATE), and
OPTIONAL for pre-existing specs. This is safe by construction: docs-audit's
body lint checks only stray tool markup, unbalanced fences, and template
placeholders (docs-audit-core.mjs lintBody) — it has no required-section
template check, so legacy specs without the section can never be flagged.
TEST-008 proves it non-vacuously (strict audit scoped to all legacy
docs/specs stays CLEAN). Mechanizing the article check is explicitly out of
scope (phase 2 if the manual section proves valuable).

### D4 — SPEC_TEMPLATE + AGENTS.md wiring
SPEC_TEMPLATE gains a `## Constitution deviations` section (default body
`None.`) with the required-new/optional-legacy note. .aai/AGENTS.md
Canonical sources gains one line pointing at docs/CONSTITUTION.md (checked
at spec freeze). Neither edit touches the .aai/*.prompt.md byte corpus;
only D2 does, and the prompt-diet floor holds (pre-change headroom 14,133
bytes; the D2 insertion is <1 KB — TEST-009 re-asserts via the prompt-diet
suite itself).

### D5 — Grep test suite `tests/skills/test-aai-constitution.sh`
New bash-3.2-compatible suite (exit 0/1/42), same shape as
tests/skills/test-aai-debug-gate.sh. Shared-baseline caveat: prompt-diet
byte-floor constants are NOT duplicated here — TEST-009 runs that suite.
TEST-005 proves no-renumber by asserting the check inside the step-10
bounds AND the survival of `11) Emit the work-item brief` and
`12) Update docs/ai/STATE.yaml` with no step 13.

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: docs/CONSTITUTION.md exists, ≤60 lines, ≥6 numbered articles
    each carrying a `(see: ...)` source pointer, all seven mandated
    principles present, ratification header naming the owner, date, and v1.
  - Verification: TEST-001..TEST-004 stanzas in
    tests/skills/test-aai-constitution.sh; expected exit 0 with PASS lines.
- Maps to: CHANGE AC-002
  - Spec-AC-02: PLANNING step 10 requires the `## Constitution deviations`
    section at freeze (inside step 10, steps 11/12 unrenumbered, no step 13);
    SPEC_TEMPLATE carries the section with the optional-for-pre-existing
    note; existing specs unaffected (strict audit over docs/specs CLEAN and
    non-vacuous).
  - Verification: TEST-005, TEST-006, TEST-008 stanzas.
- Maps to: CHANGE AC-003
  - Spec-AC-03: AGENTS.md canonical-sources line present; grep suite wired
    and green; prompt-diet floor holds; repo-wide strict docs audit exits 0;
    full tests/skills sweep green (validation-owned).
  - Verification: TEST-007, TEST-009, TEST-010 stanzas; full suite run at
    validation.

## Constitution deviations

None.

(First spec carrying the section it introduces — Planning checked the seven
articles of docs/CONSTITUTION.md v1 against this scope: additive-only,
evidence via grep-RED logs, no state or merge surface touched.)

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Constitution ≤60 lines, ≥6 pointered articles, ratified | done | TEST-001..004 green; docs/ai/tdd/constitution-green.log | — | docs/CONSTITUTION.md, 36 lines, 7 articles |
| Spec-AC-02 | Freeze-step section required-new/optional-legacy, no renumber | done | TEST-005/006/008 green; docs/ai/tdd/constitution-green.log | — | check inside PLANNING step 10; steps 11/12 intact, no step 13; 28 legacy specs scanned CLEAN |
| Spec-AC-03 | AGENTS line; suites green; diet floor; strict audit CLEAN | done | TEST-007/009/010 green; docs/ai/tdd/constitution-green.log; docs-audit --check --strict --no-event exit 0; 9-suite sweep green (constitution, hygiene, prompt-diet, debug-gate, verify-gate, state, dispatch, docs-audit, doc-numbering) | — | index regen idempotent; check-state HEALTHY |

## Implementation plan
- Components affected: docs layer (docs/CONSTITUTION.md new), prompt layer
  (.aai/PLANNING.prompt.md step-10 insertion), template layer
  (.aai/templates/SPEC_TEMPLATE.md one section), catalog (.aai/AGENTS.md one
  line), test layer (one new suite), docs/INDEX.md regeneration.
- Order: (1) RED run of the new suite on the pre-change tree → save log;
  (2) write CONSTITUTION.md; (3) wire PLANNING step 10; (4) SPEC_TEMPLATE
  section; (5) AGENTS.md line; (6) suite green; (7) sweep; (8) strict audit;
  (9) index regen (idempotent); (10) AC table reconciliation.
- Edge cases: the article check must not add a numbered PLANNING step
  (renumber churn — D2); CONSTITUTION.md must stay outside the governed scan
  set (no ID-prefixed filename); the template's new section ships with a
  filled default (`None.`) so no `<ALLCAPS>` placeholder can leak into new
  specs and trip the body lint.
- Seam analysis:
  - Seam S1 — the `.aai/*.prompt.md` byte corpus is shared with prompt-diet
    TEST-010. Crossing test: TEST-009 runs the real prompt-diet suite
    post-change (no constant duplication).
  - Seam S2 — docs-audit's body lint consumes every governed spec, including
    all legacy specs that will never carry the new section. Crossing test:
    TEST-008 runs the real strict audit over docs/specs and asserts a
    non-vacuous scan count.
  - Seam S3 — PLANNING's step numbering is consumed by cross-references
    (step 11 brief emit per CHANGE-0017, step 12 STATE CLI per SPEC-0012).
    Crossing test: TEST-005 asserts the check INSIDE step 10 bounds plus
    survival of the step-11/12 markers and absence of a step 13.
  - Seam S4 — docs/INDEX.md and the strict audit consume the new spec/change
    docs. Crossing test: TEST-010 (repo-wide strict audit) + index regen.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                   | Status  |
|----------|------------|-------------|---------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-constitution.sh | docs/CONSTITUTION.md exists and `wc -l` ≤ 60                                   | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-constitution.sh | ≥6 numbered articles, every one carrying a `(see: ...)` source pointer         | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-constitution.sh | Ratification header literal (owner, 2026-07-16, v1) present                    | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-constitution.sh | All seven mandated principle literals present                                  | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-constitution.sh | Article check inside PLANNING step 10; steps 11/12 survive; no step 13 (S3)    | green |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/test-aai-constitution.sh | SPEC_TEMPLATE `## Constitution deviations` section + optional-for-pre-existing note | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-constitution.sh | AGENTS.md canonical-sources line points at docs/CONSTITUTION.md                | green |
| TEST-008 | Spec-AC-02 | integration | tests/skills/test-aai-constitution.sh | Strict audit scoped to docs/specs CLEAN and non-vacuous — legacy specs unflagged (S2) | green |
| TEST-009 | Spec-AC-03 | integration | tests/skills/test-aai-constitution.sh | Prompt-diet floor holds post-change: `bash tests/skills/test-aai-prompt-diet.sh` exits 0 (S1) | green |
| TEST-010 | Spec-AC-03 | integration | tests/skills/test-aai-constitution.sh | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 (S4)    | green |

Notes:
- "Suites green" (CHANGE AC-003) is owned by the Validation full tests/skills
  run. Known environmental exception per LEARNED 2026-07-15:
  tests/skills/test-aai-worktree.sh fails deterministically on this machine
  pre-existing on clean main — verify via main comparison, do not chase.
- RED-proof: TEST-001..007 must be observed FAILING on the pre-change tree
  (log: docs/ai/tdd/constitution-red.log). TEST-008..010 are
  survival-invariant tests (see Implementation strategy).

## Verification
- `bash tests/skills/test-aai-constitution.sh` → exit 0, all 10 stanzas PASS.
- Sweep: hygiene-pack, prompt-diet, debug-gate, verify-gate, state, dispatch,
  docs-audit, doc-numbering suites → green.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/generate-docs-index.mjs` run twice → second run is a
  no-op (idempotent).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: constitution
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/constitution-red.log for RED;
  docs/ai/tdd/constitution-green.log for GREEN)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Validation finding disposition (2026-07-16)

- Axis-e judgment finding ("Ratified by" overclaimed a completed article-level
  review): REMEDIATED — header softened to "Proposed for ratification ... —
  ratifies by merging the introducing PR", making the merge itself the
  ratification event. TEST-003 literal updated in lockstep.

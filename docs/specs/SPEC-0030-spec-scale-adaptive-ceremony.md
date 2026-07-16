---
id: spec-scale-adaptive-ceremony
type: spec
number: 30
status: draft
ceremony_level: 2
links:
  rfc: scale-adaptive-ceremony
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Scale-Adaptive Ceremony Levels (right-size the pipeline to the work)

SPEC-FROZEN: true

## Links
- RFC: scale-adaptive-ceremony (docs/rfc/RFC-0009-scale-adaptive-ceremony.md,
  ACCEPTED by project owner 2026-07-16)
- Research: RES-0001 P2 recommendation 6 — BMAD scale-adaptive planning
  (levels 0-4) as studied prior art
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level (dogfood)
This spec declares `ceremony_level: 2` in its own frontmatter. Honest
retroactivity note: this change edits `.aai/workflow/WORKFLOW.md` — a surface
this very spec DEFINES as L3-protected. The L3 tier does not exist until this
change lands, so the spec froze under the pre-RFC-0009 default (L2 = today's
full pipeline); the L3 protections are nevertheless de-facto honored here:
mandatory worktree (executing in /Users/ales/Projects/aai-feat-ceremony), full
independent validation, dual-verdict review, and operator-only merge. Specs
frozen AFTER this change that touch `protected_paths_l3` surfaces MUST declare
level 3.

## Implementation strategy
- Strategy: hybrid
- Rationale: the dispatch changes (snapshot ceremony_level parsing + decide()
  level-aware rules) are core deterministic-orchestration logic — TDD with
  table-driven fixtures per level, including the fail-closed default
  (TEST-001..TEST-006 observed RED first, log:
  docs/ai/tdd/ceremony-levels-red.log). The prompt/template/canon edits
  (PLANNING step 10, SPEC_TEMPLATE, WORKFLOW.md, docs-audit.yaml) are text
  wiring — grep-RED (TEST-007..TEST-009 in the same RED run), one focused
  pass. TEST-010 is a survival-invariant seam test (green pre-change by
  construction, non-vacuous because it re-runs the full dispatch, prompt-diet,
  and strict-audit suites over the grown corpus after the change).
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-ceremony-levels.sh` on the pre-change tree and
  save the failing output to `docs/ai/tdd/ceremony-levels-red.log`
  (expected: TEST-002..TEST-009 FAIL; TEST-001 passes pre-change BY
  CONSTRUCTION — the current level-blind dispatch IS the L2 behavior the
  fail-closed default must preserve, so TEST-001 is a survival invariant
  like TEST-010, non-vacuous because it re-runs against the level-aware
  code after the change with garbage/absent level inputs).

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: edits the deterministic dispatch (orchestration core),
  the workflow canon, and the docs-audit close gate — protected AAI workflow
  surfaces per PLANNING step 8.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-feat-ceremony, branch feat/scale-adaptive-ceremony)
- Base ref: main
- Inline review scope (explicit paths):
  - docs/specs/SPEC-0030-spec-scale-adaptive-ceremony.md (this spec)
  - docs/rfc/RFC-0009-scale-adaptive-ceremony.md (links.spec backfill only)
  - .aai/templates/SPEC_TEMPLATE.md (frontmatter field + guidance comment)
  - .aai/PLANNING.prompt.md (level declaration inside step 10)
  - .aai/workflow/WORKFLOW.md (Ceremony levels section + gate table)
  - .aai/scripts/orchestration-dispatch.mjs (snapshot + decide level-awareness)
  - .aai/scripts/lib/docs-audit-core.mjs (close-gate checks + config key)
  - docs/ai/docs-audit.yaml (protected_paths_l3 defaults)
  - tests/skills/test-aai-ceremony-levels.sh (new suite)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Level source and single point of declaration
`ceremony_level: 0 | 1 | 2 | 3` is an integer frontmatter field of the doc
named by STATE `spec_path` (the SPEC; at L0 the intake CHANGE doc carrying the
tech-note), declared by Planning at spec freeze (.aai/PLANNING.prompt.md,
INSIDE the step-10 block as continuation lines — CHANGE-0019/SPEC-0028
precedent; steps 11/12 keep their numbers, no step 13). Levels 0 and 1
additionally REQUIRE a body line starting with the literal
`Ceremony justification: ` naming why the scope is small/safe (level-inflation
guard per the RFC risk section; review may re-classify upward as a recorded
finding).

### D2 — Legacy specs are implicit L2; fail-closed default everywhere
An ABSENT `ceremony_level` field means level 2 — today's exact pipeline, zero
migration for all 28 existing numbered specs. Every mechanical consumer
fails CLOSED to full ceremony: the dispatch snapshot builder maps absent,
non-integer, or out-of-range values (`banana`, `7`, `null`, missing
frontmatter, missing file) to 2; the pure `decide()` core independently
re-guards (`[0,1,2,3].includes(level) ? level : 2`) so an old or hand-built
snapshot object also degrades to full ceremony. A garbage value is therefore
never able to prune a gate — it can only be reported (D4).

### D3 — Rules-by-level table (which dispatch rules/gates change per level)
The deterministic tick (orchestration-dispatch.mjs `decide()`) changes at
EXACTLY three points; everything else is identical at every level:

| Dispatch rule / gate                  | L0 (typo/docs-only)                                                        | L1 (S fix)      | L2 (default)    | L3 (protected surfaces)                                                                 |
|---------------------------------------|-----------------------------------------------------------------------------|-----------------|-----------------|------------------------------------------------------------------------------------------|
| 1-5, 7, 9a-9c, 10, 11, 12, 14         | unchanged                                                                    | unchanged       | unchanged       | unchanged                                                                                  |
| 6 (freeze proxy)                       | PRUNED to the `SPEC-FROZEN: true` marker only — the frontmatter-status arm is skipped (the tech-note lives in the CHANGE doc, whose status lifecycle is not the spec enum) | unchanged | unchanged | unchanged                                                                                  |
| 8 (worktree gate)                      | unchanged                                                                    | unchanged       | unchanged       | TIGHTENED: `user_decision` must be decided for ANY recommendation (recommendation coerced to `required`); dispatch reason `l3_worktree_mandatory` when the coercion fired |
| 13 (review gate)                       | unchanged mechanically — policy legalizes `code_review.required: false` or an operator waiver (recorded), which the existing rule already honors | unchanged (single dual-verdict review stays required) | unchanged | TIGHTENED: `required` coerced true (reason `l3_review_mandatory` when coerced); a `waived` status is NOT accepted — `needs_llm` with reason `l3_review_waived_requires_operator_checkpoint` (fail-closed to the operator) |
| Validation depth (role guidance)       | suite run                                                                    | suite re-run + targeted probe | full | full                                                                                        |
| Spec artifact (Planning policy)        | tech-note in the CHANGE doc (carries SPEC-FROZEN + level + justification); STATE spec_path names the CHANGE doc | lean SPEC (AC table only) + justification | full SPEC | full SPEC |
| Close gate (docs-audit)                | justification line required                                                  | justification line required | — | — |
| PR ceremony                            | unchanged                                                                    | unchanged       | unchanged       | + operator checkpoint before merge (named in WORKFLOW.md; merge is already operator-only per Constitution art. 7 — the checkpoint makes the L3 review of the final diff an explicit named step) |

Why rules 10/11/12/14 never change: validation is required at EVERY level
(Constitution art. 1 — evidence before claims holds at L0 too; only its DEPTH
is level-scoped role guidance, not a dispatch rule). Rule 13's L0/L1 relief is
deliberately an INPUT-side policy (Planning may set `required: false` at L0;
an operator waiver is recorded state) — the rule's mechanics already honor
both, so no code path forks for L0/L1 and the pruning stays auditable in
STATE rather than hidden in the tick. "Review on the most capable model" at
L3 maps to the existing `suggested_tier: premium` for Code Review dispatches.

### D4 — Enum validation belongs to the docs-audit close gate, NOT check-state
Decision with justification (the RFC said "check-state validates the enum"):
`ceremony_level` lives in SPEC frontmatter — a governed docs surface — while
check-state.mjs / lib/state-engine.mjs validate ONLY docs/ai/STATE.yaml
structure (their whole contract; STATE never stores the level, so there is
nothing for them to check without crossing into doc parsing they were built
to avoid). The enum check therefore lands in the docs-audit close gate
(`gateContent` in .aai/scripts/lib/docs-audit-core.mjs), which already owns
per-doc structural close checks (AC table, Review-By schema):
- a PRESENT `ceremony_level` outside `0|1|2|3` -> gate reason
  `schema-invalid ceremony_level` (a YAML `null` counts as absent, not invalid);
- level 0/1 without a `Ceremony justification: ` body line -> gate reason;
- an ABSENT field -> never flagged (D2 legacy rule).
Enforcement is report-only first per the RFC: the gate reasons ride the
EXISTING `close_gate` dial in docs/ai/docs-audit.yaml (report-only in this
repo), so no new enforcement knob is introduced and `--gate`/`--gate-file`
keep returning the raw predicate. Dispatch never depends on this check — it
fail-closes independently (D2), so an invalid enum degrades to full ceremony
while the audit reports it.

### D5 — L3 protected-surface list: config key with canon defaults
Resolves the RFC open question ("docs-audit.yaml config or workflow canon?"):
BOTH, with distinct jobs. The POLICY (that L3 exists, what it adds, and the
canonical default surface list) lives in .aai/workflow/WORKFLOW.md — policy is
canon and must survive per-project config drift. The PROJECT-OWNED list lives
in docs/ai/docs-audit.yaml under a new `protected_paths_l3` key (parsed by
`loadConfig` as a standard list key), because each downstream project has
different protected surfaces and docs-audit.yaml is the established home for
project-owned gate dials (close_gate, doc_number_guard). Canonical defaults
(also shipped as this repo's config value): the state engine
(.aai/scripts/state.mjs, .aai/scripts/lib/state-engine.mjs,
.aai/scripts/lib/state-core.mjs), the allocator
(.aai/scripts/allocate-doc-number.mjs), the guards
(.aai/scripts/pre-commit-checks.sh, .aai/scripts/pre-commit-checks.ps1), and
the workflow canon (.aai/workflow/WORKFLOW.md, docs/CONSTITUTION.md).
The list is consult-time policy for Planning (declare L3 when the scope
touches a listed path) and review (re-classify upward); a mechanical
diff-vs-list enforcement hook is explicitly out of scope (phase 2 candidate —
YAGNI until level declarations exist in the wild).

### D6 — New suite, no file overlap with sibling streams
All gating tests land in a NEW suite tests/skills/test-aai-ceremony-levels.sh
(bash 3.2, exit 0/1/42, sourcing-compatible for per-test TDD evidence — same
shape as test-aai-orchestration-dispatch.sh). The hygiene-pack suite is NOT
extended (the sibling hooks stream extends it; zero shared-file conflict
surface). Dispatch fixtures are scratch temp-dir repos via --state/--root;
the real runtime files are never touched.

## Acceptance Criteria Mapping
- Maps to: RFC-0009 recommended option — "Planning declares ceremony_level
  0..3 in the spec frontmatter, with a justification line"
  - Spec-AC-01: SPEC_TEMPLATE frontmatter carries `ceremony_level: 2` with a
    guidance comment (levels, justification-line requirement, protected
    surfaces); PLANNING declares the level at freeze INSIDE step 10 (steps
    11/12 unrenumbered, no step 13); WORKFLOW.md gains the "Ceremony levels"
    section with the explicit per-level gate table and the L3
    protected-surface canonical defaults; docs/ai/docs-audit.yaml gains
    `protected_paths_l3` (parsed by loadConfig).
  - Verification: TEST-007, TEST-008, TEST-009.
- Maps to: RFC-0009 — "the gate table prunes BY LEVEL, never silently" +
  "dispatch reads the level from the spec" + drivers ("mechanized dispatch
  must stay deterministic")
  - Spec-AC-02: orchestration-dispatch.mjs snapshot reads `ceremony_level`
    from the spec_path file's frontmatter with fail-closed default 2
    (absent field, garbage token, out-of-range integer, yaml null, missing
    file); decide() prunes per the D3 table only: L0 rule-6 status-arm prune,
    L3 rule-8 coercion, L3 rule-13 coercion + waived->needs_llm; L1/L2
    mechanically byte-identical to today; decide() stays pure/deterministic.
  - Verification: TEST-001..TEST-006 (table-driven per level incl. fail-closed
    default), TEST-010 (existing dispatch suite survives).
- Maps to: RFC-0009 — "docs-audit close gate requires the justification line
  for L0/L1" + "check-state validates the enum" (relocated per D4, justified)
  - Spec-AC-03: gateContent flags (a) schema-invalid ceremony_level values and
    (b) level 0/1 docs lacking a `Ceremony justification: ` body line; absent
    field is never flagged (legacy implicit L2); enforcement report-only via
    the existing close_gate dial (no new knob); the repo-wide strict audit
    stays CLEAN over all legacy specs.
  - Verification: TEST-006 (gate-file fixtures), TEST-010 (strict audit
    clean + non-vacuous legacy scan).
- Maps to: RFC-0009 consequences (M-sized, no regressions)
  - Spec-AC-04: full hygiene holds post-change — new suite green, existing
    dispatch suite green, prompt-diet floor holds, repo-wide strict docs
    audit exits 0, docs index regeneration idempotent, check-state OK.
  - Verification: TEST-010 + validation-owned full tests/skills sweep.

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md v1):
- Art. 1 (evidence before claims): level pruning never touches the evidence
  gates — validation (rules 10/11) and the no-PASS-without-evidence rule hold
  at EVERY level; L0 only shrinks the ARTIFACT (tech-note vs full spec) and
  the review OPTIONALITY, both explicit and recorded. No deviation.
- Art. 2 (simplicity/YAGNI): mechanical protected-path diff enforcement
  deferred to phase 2 (D5) instead of speculatively built. No deviation.
- Art. 3 (portability): everything is plain markdown/yaml/mjs. No deviation.
- Art. 4 (degrade and report): fail-closed level default + flagged
  needs_llm edges. No deviation.
- Art. 5 (additive first): new optional frontmatter field; absent field keeps
  byte-identical legacy behavior; PLANNING step numbering preserved; RULES
  table text extended, no rule renumbered. No deviation.
- Art. 6 (single-writer STATE): STATE.yaml schema untouched — the level lives
  in doc frontmatter precisely so state.mjs stays the sole STATE writer and
  the dispatch stays read-only. No deviation.
- Art. 7 (operator-only merge): the L3 operator checkpoint STRENGTHENS this
  article; L0 review waiver is operator-recorded, and merging stays
  operator-only at every level. No deviation.

## Acceptance Criteria Status

| Spec-AC    | Description                                                       | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Level declaration surfaces: template field, PLANNING step 10, WORKFLOW gate table, protected_paths_l3 | done | TEST-007..009 green; docs/ai/tdd/ceremony-levels-green.log | — | step 10 insertion; steps 11/12 intact, no step 13 |
| Spec-AC-02 | Dispatch level-aware: fail-closed default 2; L0 rule-6 prune; L3 rule-8/13 tightening; L1/L2 unchanged; decide pure | done | TEST-001..005 green; docs/ai/tdd/ceremony-levels-green.log; docs/ai/tdd/ceremony-levels-red.log (RED-proof) | — | garbage/absent/out-of-range/null/missing-file all -> 2 |
| Spec-AC-03 | Close gate: L0/L1 justification + enum check, report-only, legacy never flagged | done | TEST-006 green; TEST-010 strict-audit arm green | — | rides existing close_gate dial (D4) |
| Spec-AC-04 | Hygiene: suites green, diet floor, strict audit CLEAN, index idempotent, check-state OK | done | TEST-010 green; sweep log in validation notes | — | worktree suite env-fail known pre-existing (LEARNED 2026-07-15) |

## Implementation plan
- Components affected: template layer (.aai/templates/SPEC_TEMPLATE.md),
  prompt layer (.aai/PLANNING.prompt.md step-10 continuation lines), workflow
  canon (.aai/workflow/WORKFLOW.md new section), orchestration core
  (.aai/scripts/orchestration-dispatch.mjs snapshot + decide + RULES text),
  audit core (.aai/scripts/lib/docs-audit-core.mjs gateContent + loadConfig),
  config (docs/ai/docs-audit.yaml), test layer (new suite), docs/INDEX.md.
- Order: (1) write the new suite; (2) RED run on the pre-change tree -> save
  docs/ai/tdd/ceremony-levels-red.log; (3) dispatch snapshot + decide (TDD:
  TEST-001..005 GREEN); (4) gateContent + loadConfig + docs-audit.yaml
  (TEST-006 GREEN); (5) template/PLANNING/WORKFLOW text (TEST-007..009
  GREEN); (6) RFC links.spec backfill; (7) full suite + sweep + strict audit
  + index regen + check-state; (8) AC table reconciliation; (9) STATE via CLI.
- Edge cases: `ceremony_level: null` (absent semantics, not invalid);
  `ceremony_level: 03`/`2.0`/quoted `"2"` (non-canonical tokens -> default 2
  in dispatch; gate flags only non-`0|1|2|3` strings — quoted "2" unquotes to
  2 via the shared frontmatter parser, so it is valid at the gate and only
  the dispatch's stricter tokenizer defaults it — both fail SAFE); L0 doc
  missing SPEC-FROZEN marker still dispatches Planning (rule 6 marker arm is
  never pruned); L3 with review status `fail` still routes to Remediation
  (rule 12 fires before 13 — tightening never masks a failure).
- Seam analysis:
  - Seam S1 — the decide() rule table is consumed by ORCHESTRATION wrappers
    and the existing dispatch suite (TEST-001 asserts all-14-rule first-match
    order). Crossing test: TEST-010 runs the REAL
    tests/skills/test-aai-orchestration-dispatch.sh post-change (level-absent
    snapshots must reproduce every legacy case bit-for-bit).
  - Seam S2 — gateContent is shared by gateDoc (worktree file) and gateFile
    (staged blob) and consumed by the pre-commit hook + closeout skills.
    Crossing test: TEST-006 drives the real CLI `--gate-file` end-to-end on
    fixture files (not a unit call), asserting exit codes and reason text.
  - Seam S3 — the `.aai/*.prompt.md` byte corpus is shared with the
    prompt-diet floor. Crossing test: TEST-010 runs the real prompt-diet
    suite after the PLANNING insertion.
  - Seam S4 — every governed doc (incl. this DRAFT spec with its new
    frontmatter field) feeds the strict audit and the index generator.
    Crossing test: TEST-010 strict-audit arm + index regen idempotence.
  - Residual risk (recorded): the L3 protected-path list has no mechanical
    diff-enforcement consumer yet (D5, phase 2) — mitigated by Planning
    consult-time policy + review upward re-classification.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                    | Status  |
|----------|------------|-------------|-------------------------------------------|--------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-02 | unit        | tests/skills/test-aai-ceremony-levels.sh | decide(): level absent / garbage / out-of-range in the snapshot -> treated as 2; legacy baseline rules unchanged; purity holds | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-ceremony-levels.sh | decide() L0: rule-6 frontmatter-status arm pruned (marker still required); same snapshot at L2 dispatches Planning rule 6 | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-ceremony-levels.sh | decide() L3: rule-8 worktree gate fires on ANY recommendation while undecided (reason l3_worktree_mandatory); L2 falls through | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-ceremony-levels.sh | decide() L3: review required coerced (reason l3_review_mandatory); waived -> needs_llm l3_review_waived_requires_operator_checkpoint; L2 waived -> rule 14; L3 review fail still -> rule 12 | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-ceremony-levels.sh | CLI fail-closed proof on fixture repos: absent field / `banana` / `7` / `null` -> state_summary ceremony_level 2; declared 0 prunes rule 6 end-to-end; declared 3 fires rule 8 end-to-end | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-ceremony-levels.sh | docs-audit --gate-file: L1 without justification line -> exit 1 + reason; L1 with line -> exit 0; invalid enum -> exit 1; absent field -> exit 0 (legacy) | green |
| TEST-007 | Spec-AC-01 | unit        | tests/skills/test-aai-ceremony-levels.sh | SPEC_TEMPLATE frontmatter `ceremony_level: 2` + guidance comment naming the justification line and protected surfaces | green |
| TEST-008 | Spec-AC-01 | integration | tests/skills/test-aai-ceremony-levels.sh | PLANNING level declaration INSIDE step-10 bounds; `11) Emit the work-item brief` and `12) Update docs/ai/STATE.yaml` survive; no step 13 (S3-adjacent renumber guard) | green |
| TEST-009 | Spec-AC-01 | unit        | tests/skills/test-aai-ceremony-levels.sh | WORKFLOW.md "Ceremony levels" section: per-level gate table (L0..L3 columns), protected-surface defaults, protected_paths_l3 pointer; docs-audit.yaml carries the key | green |
| TEST-010 | Spec-AC-04 | integration | tests/skills/test-aai-ceremony-levels.sh | Seam survival: dispatch suite green (S1), prompt-diet green (S3), repo-wide strict audit exits 0 non-vacuously (S2/S4) | green |

Notes:
- RED-proof: TEST-002..TEST-009 observed FAILING on the pre-change tree
  (docs/ai/tdd/ceremony-levels-red.log). TEST-001 and TEST-010 are survival
  invariants (green pre-change by construction; non-vacuous — see
  Implementation strategy).
- Full tests/skills sweep is validation-owned. Known environmental exception
  per LEARNED 2026-07-15: tests/skills/test-aai-worktree.sh fails
  deterministically on this machine pre-existing on clean main.

## Verification
- `bash tests/skills/test-aai-ceremony-levels.sh` -> exit 0, all 10 stanzas PASS.
- `bash tests/skills/test-aai-orchestration-dispatch.sh` -> exit 0 (legacy parity).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> exit 0.
- `node .aai/scripts/generate-docs-index.mjs && git diff --exit-code -I '^Generated:' -- docs/INDEX.md` -> exit 0 (idempotent).
- `node .aai/scripts/check-state.mjs` -> OK.
- Fail-closed proof: TEST-005 fixture outputs (absent/garbage/out-of-range ->
  `state_summary.spec.ceremony_level == 2` and legacy rule routing).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: scale-adaptive-ceremony
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/ceremony-levels-red.log,
  docs/ai/tdd/ceremony-levels-green.log)
- commit SHA or diff range when available

## Review finding dispositions (2026-07-16)

- NB-1 (Verification cited a nonexistent generator flag; exit 0 proved
  nothing): REMEDIATED — real probe (regenerate + git diff --exit-code -I
  '^Generated:'); a true --check generator mode noted as follow-up candidate.
- NB-2 (WORKFLOW L3 worktree cell read as usage-mandatory while rule 8
  mandates a RECORDED DECISION): REMEDIATED by clarification — RFC-0009's
  "mandatory worktree" maps to the house 'required' semantics (worktree
  policy section: operator may record an inline override with rationale);
  the recorded decision is the mechanical mandate. INFO items (unreachable
  hand-built snapshot; quoted-example justification false-negative) accepted.

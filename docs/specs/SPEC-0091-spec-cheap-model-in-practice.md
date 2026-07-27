---
id: spec-cheap-model-in-practice
type: spec
number: 91
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0065-cheap-model-in-practice.md
  rfc: null
  pr:
    - 165
  commits:
    - cd140d6f523dcbb97e5e7e34cd161a29657860d0
---

# Spec — Cheap-model delegation in practice: lane-aware model routing

## Links
- Requirement: docs/issues/CHANGE-0065-cheap-model-in-practice.md
- Decision records: MODEL_ROUTING binding introduced with CHANGE-0058 sibling; validator-independence backstop CHANGE-0010 D1
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Summary
Make the cheapest routing tier actually reachable. Two mechanical edits, both
in the CLI annotation layer (`decide()` rule table untouched):

1. `.aai/system/MODEL_ROUTING.yaml` gains two role rows — an explicit
   `Metrics Flush -> claude-haiku-4-5` pin (auditable, even though the
   mechanical tier default already resolves to it) and a lane-aware override
   `Validation@lightweight -> claude-sonnet-5`.
2. `suggestModel()` in `.aai/scripts/orchestration-dispatch.mjs` grows a
   lane-aware lookup step: resolution order becomes
   `roles[role@lane.selected] ?? roles[role] ?? tiers[tier] ?? null`, with the
   validator-independence swap applied AFTER as today.

The line parser (`loadModelRouting`) already accepts an `@` in a role key
(regex `[^:#]+`), so NO parser change is needed — this was verified at planning
and is a deliberate part of the design (the mechanism rides the existing
parser). `decide()`, the rule table, `deriveLane()`, and every dispatch
verdict field except `suggested_model` are byte-unchanged.

## Design notes (validation of the dispatched direction)
- The dispatched direction is adopted as-is. One honest caveat is recorded so
  downstream does not over-claim: with the CURRENT tier map
  (`standard: claude-sonnet-5`), the shipped `Validation@lightweight:
  claude-sonnet-5` row resolves to the SAME model id a full-lane Validation
  already gets via the tier default. Its shipped value is therefore (a) making
  the lightweight-lane choice explicit and auditable, and (b) establishing the
  resolution MECHANISM so a repo can later pin a distinct lightweight model
  without touching tier defaults. The behavioral delta for Validation is zero
  today; that is intentional and stated, not a defect.
- To prove the mechanism is genuinely exercised (not silently falling through
  to an identical tier default), the tests use DISTINCT sentinel model ids in a
  fixture MODEL_ROUTING — a lightweight dispatch must resolve the lane sentinel,
  a full dispatch must resolve the tier sentinel.
- MODEL_ROUTING role rows must NOT carry inline `# comments`: the parser regex
  `^ {2}([^:#]+):\s*(\S+)\s*$` drops any row whose value is followed by a
  comment. Comments go on their own line. Verified at planning.

## Implementation strategy
- Strategy: tdd
- Rationale: This changes the factory's model-routing brain (orchestration
  dispatch annotation layer). The resolution-order precedence (lane over role
  over tier) and the independence-swap-still-wins invariant are exactly the
  kind of ordering logic that rubber-stamps itself if the test is written after
  the code. Each new AC-gating test must be observed RED against the current
  `suggestModel` before its GREEN counts. Codebase precedent for dispatch
  changes (SPEC-0041, SPEC-0042) is test-first.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: Single-module change (one config file, one function, one
  test file, docs). Not a protected surface (orchestration-dispatch.mjs is
  absent from protected_paths_l3 — verified against docs/ai/docs-audit.yaml and
  .aai/workflow/WORKFLOW.md at planning). A feature branch already isolates it;
  a worktree is useful but not required for safety.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/cheap-model-in-practice (current branch)
- Inline review scope: .aai/system/MODEL_ROUTING.yaml, .aai/scripts/orchestration-dispatch.mjs, tests/skills/test-aai-orchestration-dispatch.sh, docs/specs/SPEC-0091-spec-cheap-model-in-practice.md, docs/issues/CHANGE-0065-cheap-model-in-practice.md, USER_GUIDE / docs routing note

## Acceptance Criteria Mapping
- Maps to: AC-001 (intake)
  - Spec-AC-01: With the shipped MODEL_ROUTING, a Metrics Flush dispatch
    resolves suggested_model to claude-haiku-4-5.
  - Verification: fixture-root CLI dispatch asserts suggested_model.
- Maps to: AC-002 (intake)
  - Spec-AC-02: A lightweight-lane (L0/L1) dispatch resolves the
    role@lightweight override; a full-lane dispatch resolves the plain
    role/tier default. Proven with distinct fixture sentinels, end-to-end
    through the file parse (seam: lane produced by deriveLane, consumed by
    suggestModel).
  - Verification: pure suggestModel unit cases plus a CLI end-to-end fixture.
- Maps to: AC-003 (intake)
  - Spec-AC-03: Absent MODEL_ROUTING file yields suggested_model null on every
    verdict; the existing TEST-019 unbound arm stays green (regression pin).
  - Verification: fixture with no MODEL_ROUTING.yaml asserts null.
- Maps to: AC-004 (intake)
  - Spec-AC-04: The validator-independence swap still wins over a lane override
    — when the lane-resolved Validation model equals implementer_model, the
    result is validation_alternate.
  - Verification: pure suggestModel case with colliding sentinels.
- Maps to: AC-005 (intake)
  - Spec-AC-05: No regression — the dispatch suite and the ceremony-levels lane
    stanzas are green locally; the full framework runs on PR CI.
  - Verification: targeted suite run locally; PR CI binding.
- Maps to: scope line "Documentation" (intake Scope)
  - Spec-AC-06: MODEL_ROUTING.yaml carries a comment block documenting the
    role@lane key form and the no-inline-comment rule; the user-facing routing
    doc notes ceremony-lane routing.
  - Verification: grep asserts the documented key form and doc note exist.

## Constitution deviations

None.

<!-- Article-by-article at freeze: (1) Evidence before claims — spec-lint +
docs-audit --check exit codes reported; no PASS claimed in planning. (2)
Simplicity — one lookup step + two config rows, nothing speculative. (3)
Portability — plain YAML/JS/MD files. (4) Degrade and report — absent
MODEL_ROUTING => null (unchanged); absent/garbage lane => falls through to
role/tier (fail-closed). (5) Additive first — the lane key is PREPENDED to the
existing resolution chain; configs without @lane keys resolve byte-identically
(back-compat). (6) Single-writer state — planning writes NO STATE (dispatch
single-writer constraint; recommendations carried in the result block). (7)
Operator-only merge — N/A in planning. -->

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | Metrics Flush dispatch resolves suggested_model claude-haiku-4-5   | done   | TEST-020 green, docs/ai/tdd/green-20260727T064250Z.log | — | Explicit row added; tier default already matched (zero behavioral delta, stated in Design notes) |
| Spec-AC-02 | Lane-aware override wins on lightweight; tier default on full lane | done   | TEST-021/TEST-022 green, docs/ai/tdd/green-20260727T064250Z.log | — | Sentinel fixtures prove genuine lane-key resolution, not tier-default coincidence |
| Spec-AC-03 | Absent MODEL_ROUTING yields suggested_model null everywhere        | done   | TEST-023 green (pre-existing, stayed green through the change), docs/ai/tdd/red-20260727T064201Z.log and green-20260727T064250Z.log | — | Regression pin alongside TEST-019 unbound arm |
| Spec-AC-04 | Validator-independence swap wins over the lane override            | done   | TEST-024 green, docs/ai/tdd/green-20260727T064250Z.log | — | Swap applied after lane resolution, unchanged ordering |
| Spec-AC-05 | No regression across dispatch and ceremony-lane suites            | done   | dispatch suite + ceremony-levels suite both exit 0, docs/ai/tdd/green-20260727T064250Z.log and docs/ai/tdd/green-ceremony-levels-20260727T064320Z.log | — | Both suites run locally; full framework binds on PR CI |
| Spec-AC-06 | Docs record the role@lane key form and ceremony-lane routing note | done   | TEST-026 green, docs/ai/tdd/green-20260727T064250Z.log | — | MODEL_ROUTING.yaml header + docs/USER_GUIDE.md updated |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - .aai/system/MODEL_ROUTING.yaml — add role rows (own-line comments only):
    `Metrics Flush: claude-haiku-4-5` and `Validation@lightweight: claude-sonnet-5`;
    extend the header comment block with the `role@lane` key contract.
  - .aai/scripts/orchestration-dispatch.mjs — suggestModel(): prepend the
    lane-key lookup. Sketch: build laneKey from out.role and out.lane.selected
    when both exist, then `model = roles[laneKey] ?? roles[out.role] ?? (tier
    ? tiers[tier] : null) ?? null`. The independence swap block is unchanged and
    stays AFTER this resolution.
  - tests/skills/test-aai-orchestration-dispatch.sh — extend TEST-019 (or add a
    sibling stanza in the same suite) with the lane-aware cases; reuse the
    existing mk_root / write_dstate / run_dispatch / jassert helpers and the
    fixture-sentinel MODEL_ROUTING pattern already present in TEST-019.
  - Documentation — MODEL_ROUTING header block + the user-facing routing note.
- Data flows: spec frontmatter ceremony_level -> deriveLane() -> verdict.lane
  -> suggestModel() lane key -> MODEL_ROUTING roles lookup -> suggested_model on
  stdout JSON.
- Edge cases: non-dispatch verdicts (lane null) -> suggestModel returns null
  early (unchanged); dispatch with no @lane key present -> identical to today;
  Validation collision on a lightweight lane -> independence swap still applies.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type        | File path (expected)                            | Description                                                                                  | Status  |
|----------|------------|-------------|-------------------------------------------------|---------------------------------------------------------------------------------------------|---------|
| TEST-020 | Spec-AC-01 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Fixture-root Metrics Flush dispatch with shipped-shape MODEL_ROUTING resolves haiku via explicit role row | green |
| TEST-021 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | Pure suggestModel: lightweight lane resolves role@lightweight sentinel; full lane resolves tier sentinel | green |
| TEST-022 | Spec-AC-02 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI end-to-end across the lane seam: L1 spec fixture plus @lightweight MODEL_ROUTING yields the lane sentinel in stdout | green |
| TEST-023 | Spec-AC-03 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Fixture with no MODEL_ROUTING.yaml yields suggested_model null (regression pin alongside existing TEST-019 unbound arm) | green |
| TEST-024 | Spec-AC-04 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | Pure suggestModel: lightweight Validation whose lane model equals implementer_model swaps to validation_alternate | green |
| TEST-025 | Spec-AC-05 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Full dispatch suite plus ceremony-levels lane stanzas green (bash runs both suites) | green |
| TEST-026 | Spec-AC-06 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Grep asserts MODEL_ROUTING documents role@lane key form and the user-facing routing note exists | green |

Test status values: pending -> red -> green

Notes:
- RED-proof obligation: TEST-020/021/022/024 must be observed FAILING against the
  current suggestModel (no lane lookup) before their GREEN counts. TEST-023 is a
  regression pin (already green — it guards the unbound path and must stay green
  through the change). TEST-025/026 gate the no-regression and docs criteria.
- Test IDs continue the suite's existing sequence (TEST-019 is the last defined).

## Seam analysis
- SEAM 1 (internal, module-crossing): `verdict.lane` is PRODUCED by
  `deriveLane()` inside dispatchFor()/decide() and now CONSUMED by
  `suggestModel()` to build the lane key. Covered end-to-end by TEST-022 (a real
  fixture spec frontmatter drives ceremony_level -> lane -> suggested_model
  through the actual file parse), NOT two mocked halves.
- SEAM 2 (cross-file, MODEL_ROUTING <-> PRICING): every routed model id must
  resolve in PRICING.yaml so metrics-flush can cost the run. The two shipped ids
  (claude-sonnet-5, claude-haiku-4-5) already exist in PRICING.yaml — verified at
  planning (grep, 2/2 present). No PRICING change is in scope; residual risk is
  therefore nil for the shipped ids. If a future lane pin introduces a new id,
  the PRICING pairing obligation from the MODEL_ROUTING header applies.

## Verification
- Commands to run:
  - bash tests/skills/test-aai-orchestration-dispatch.sh
  - bash tests/skills/test-aai-ceremony-levels.sh (lane-stanza regression)
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0091-spec-cheap-model-in-practice.md
  - PR CI full framework
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status AND an
  independent validation PASS recorded.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: cheap-model-in-practice
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

SPEC-FROZEN: true

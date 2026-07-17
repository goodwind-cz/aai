---
id: spec-dispatch-new-intake-after-completed-scope
type: spec
number: 42
status: draft
ceremony_level: 2
links:
  change: dispatch-new-intake-after-completed-scope
  rfc: null
  pr: []
  commits: []
---

# SPEC — Deterministic Focus Retarget Off a Completed/Flushed Scope

SPEC-FROZEN: true

## Links
- Change: dispatch-new-intake-after-completed-scope
  (docs/issues/CHANGE-0031-dispatch-new-intake-after-completed-scope.md)
- Consumes (does NOT reopen): spec-loop-ceremony-aware-dispatch
  (docs/specs/SPEC-0041-spec-loop-ceremony-aware-dispatch.md, done — its D5
  documents the composition seam this spec lands on) and
  spec-mechanize-deterministic-ticks (CHANGE-0009 — the decide() rule table)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
`ceremony_level: 2` — full pipeline. This RECLASSIFIES the intake's declared
L1 intent upward, as the intake itself invited ("Planning should explicitly
weigh L2/L3 reclassification"). Recorded reasoning:
- The diff is nominally single-surface (`orchestration-dispatch.mjs` + its
  reserved test suite), which is what made L1 plausible. But unlike
  SPEC-0041's purely additive lane ANNOTATION, this scope changes dispatch
  BEHAVIOR: a new decision arm that changes WHICH role is dispatched and on
  WHICH ref, a changed rule-11 firing predicate, and a new filesystem probe
  in the snapshot builder (docs/issues scan). A wrong retarget is
  self-amplifying — the loop executes its own dispatcher.
- LEARNED 2026-07-16/17 ("two independent gates are not redundant"): for
  deterministic writers, an independent validator that executes adversarial
  multi-run fixtures catches what static review misses. Full lane keeps that
  second gate at full depth.
- L3 is NOT mandatory: verified against `protected_paths_l3` in
  docs/ai/docs-audit.yaml (2026-07-17) — `orchestration-dispatch.mjs` is not
  listed (same verification SPEC-0041 recorded; the intake's "protected
  surface" note remains factually stale), and this scope touches no listed
  path.

## Implementation strategy
- Strategy: tdd
- Rationale: everything in scope is deterministic-orchestration core logic
  provable by table-driven fixtures — pure decide() variants, snapshot-probe
  behavior, CLI exit codes/JSON payloads. There is no prompt-text or glue
  component that would justify a loop/hybrid split (the retarget payload is
  consumed by Planning's EXISTING step-12 set-focus path; no prompt edits).
  RED-GREEN-REFACTOR per TEST-xxx with evidence in docs/ai/tdd/.
- RED-proof obligation: before any product edit, run the new suite functions
  (TEST-001..TEST-005) against the pre-change tree and save the failing
  output to `docs/ai/tdd/dispatch-retarget-red.log` (expected failures: the
  stale rule-6 Planning dispatch, the rule-11 Validation dispatch on a done
  item, missing `retarget` field, missing reasons). TEST-006/TEST-007 are
  survival invariants — green pre-change by construction, non-vacuous
  because they re-run the real gates/suites over the changed tree.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: edits the deterministic dispatcher the loop itself
  executes; PR-bound work on orchestration core.
- User decision: inline — operator-approved and already recorded in STATE
  ("operator-approved: inline on feat/dispatch-new-intake-retarget"); no new
  decision required.
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/scripts/orchestration-dispatch.mjs (rule 4a retarget arm, rule-11
    done-skip, snapshot open-intakes probe, additive `retarget` output field,
    RULES table entries)
  - tests/skills/test-aai-orchestration-dispatch.sh (new stanzas; reserved
    for this scope by SPEC-0041 D5)
  - docs/specs/SPEC-0042-spec-dispatch-new-intake-after-completed-scope.md
    (this spec; number per allocation)
  - docs/issues/CHANGE-0031-dispatch-new-intake-after-completed-scope.md
    (status lifecycle only)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Retarget is a new guarded arm "4a", evaluated before rule 5
A new first-match arm sits AFTER the focus-ref existence check and BEFORE
rule 5 (spec probes), with rule id `4a` and its own RULES table row. Firing
guard — the focus scope must be TERMINALLY complete, defined mechanically as
BOTH:
- `s.work_item.status === 'done'` OR `s.work_item === null` (flushed items
  are removed from active_work_items), AND
- `s.flushed === true` (focus ref present in docs/ai/METRICS.jsonl — the
  existing rule-14 probe, reused as the terminal marker).
Requiring `flushed` prevents hijacking the normal close pipeline: a work
item that is `done` but not yet flushed still walks rules 13/14 to the
metrics-flush arm exactly as today. A `work_item === null` focus that is NOT
flushed keeps today's behavior (rules 5-8 or
`focus_ref_not_in_active_work_items`) — a broken state, not a completed one.

### D2 — Candidate enumeration: docs/issues scan, fail-closed
New READ-ONLY snapshot field `open_intakes`: scan top-level `docs/issues/*.md`
(sorted by filename for determinism), parse frontmatter, keep docs with
`status: draft` or `status: implementing`. Per candidate record
`{ ref_id, primary_path, doc_type, item_status }` where the work-item match
uses `primary_path` equality first, then frontmatter `id` — this bridges the
mixed ref conventions (number-based `CHANGE-0027` vs slug refs). Exclusions:
- the doc matching the focus ref (any of frontmatter id, work-item
  primary_path match, or `TYPE-NNNN` filename prefix equal to the focus ref);
- docs whose matched work item is `status: done` (false-open awaiting close
  ceremony, not a plannable scope).
A doc whose frontmatter cannot be parsed (no id or no status) still COUNTS
as a candidate but is marked unmappable — it can block the deterministic
path, never be silently skipped. If the directory scan itself fails, the
probe records `open_intakes: null`. Scope boundary: only `docs/issues/`
intake classes (change / issue / hotfix). RFC / PRD / release / techdebt
retargeting stays LLM-owned — `techdebt` has no `current_focus.type` enum
member, and the others have their own pipelines (fail-closed: such docs are
counted but unmappable).

### D3 — Decision outcomes of arm 4a (single unambiguous shape only)
When the D1 guard fires:
- EXACTLY ONE candidate, mappable (`doc_type` in {change→intake_change,
  issue→intake_issue, hotfix→intake_hotfix}, parseable id): verdict
  `dispatch`, rule `4a`, role Planning, `ref_id` = the candidate's work-item
  ref if a live item exists else its frontmatter id, inputs = [candidate
  primary_path, docs/TECHNOLOGY.md (+ LOCKS.md when present)], reason
  `focus_completed_retarget_to_open_intake`, plus the D4 `retarget` payload.
  Never `needs_llm`, never a stale rule-5/6 Planning dispatch on the closed
  focus. Planning is dispatched even when the intake has no work item yet:
  the intake DOC existing means intake ceremony already produced it, and
  Planning's own step 12 (`state.mjs set-focus` / `set-phase`) creates the
  work item — no new "Intake" role enters the deterministic table.
- ZERO candidates: verdict `no_action`, rule `4a`, reason
  `scope_complete_no_open_intake` (exit 3 — mirrors the `already_flushed`
  arm; nothing is left to dispatch).
- TWO OR MORE candidates: verdict `needs_llm`, rule `4a`, reason
  `multiple_open_intakes:<ref1>,<ref2>,...` naming every candidate
  (machine-greppable prefix; priority between intakes is a human/LLM call —
  intake out-of-scope line honored).
- Single candidate but unmappable: `needs_llm`, reason
  `open_intake_unmappable:<path>`. Probe failure (`open_intakes: null`):
  `needs_llm`, reason `open_intake_scan_failed`. Fail-closed: ambiguity is
  flagged, never guessed (Constitution art. 4).

### D4 — Read-only contract preserved; retarget is an EMITTED payload
The dispatcher NEVER writes STATE (unchanged invariant). The retarget rides
the dispatch JSON as a new additive top-level field:
`retarget: { from_ref, to_ref, to_type, to_primary_path }` on the 4a
dispatch; `retarget: null` on every other verdict (same additive pattern as
SPEC-0041's `lane`). The authoritative set-focus WRITE is executed by the
dispatched Planning role's existing step 12 (`state.mjs set-focus --type
<to_type> --ref <to_ref> --path <to_primary_path>`) — no ORCHESTRATION /
SKILL_LOOP prompt edit is needed; wrappers relay the JSON as they already
do. The 4a dispatch's `lane` is `deriveLane(null)` = `{selected: 'full',
ceremony_level: 2, validation_depth: 'full'}`: the NEW scope has no spec
yet, so the lane fail-closes to full regardless of the CLOSED scope's spec
frontmatter (composing cleanly with SPEC-0041 D1 instead of leaking the old
scope's ceremony onto the new one).

### D5 — Rule 11 gains an explicit done-status skip
Rule 11's firing predicate adds `s.work_item.status !== 'done'` alongside
the existing phase membership check. A done work item is terminal — its
`validation not_run` residue (the H5 post-flush reset) must never re-offer
Validation. Resulting routing: done + flushed → the 4a arm resolves it
(retarget or `scope_complete_no_open_intake`); done + NOT flushed +
`not_run` residue → falls through rules 12-14 to `needs_llm
no_rule_matched` (fail-closed; this shape is structurally ambiguous and not
mechanically decidable — recorded edge case, not a gap). Rules 10/12
(fail verdicts) are deliberately NOT status-guarded: a recorded `fail` on
any item still routes to Remediation/forensics exactly as today.

### D6 — Composition with SPEC-0041 (honoring its D5 seam)
Edits are confined to the regions SPEC-0041 D5 reserved: (a) the new 4a
guard block before rule 5 plus its RULES row, (b) one additive clause in the
rule-11 predicate, (c) snapshot-builder additions (open-intakes probe; the
work-item status field already exists), (d) the additive `retarget` output
field on the three output constructors. NOT touched: lane derivation
(`deriveLevel`/`deriveLane`), rules 1-4 and 5-10/12-14 predicates and order,
`dispatchFor` role definitions, spec probing. Every lane assertion in
tests/skills/test-aai-ceremony-levels.sh must stay green; new fixtures live
exclusively in tests/skills/test-aai-orchestration-dispatch.sh (the suite
SPEC-0041 deliberately left untouched for this scope).

### D7 — Evidence replay (the two motivating incidents become fixtures)
Two fixtures modeled on the cited real shapes:
- Tick-1 shape (2026-07-17, LOOP_TICKS line 11): focus names a done+flushed
  work item, its spec present with terminal frontmatter status, ONE open
  intake doc (draft, no work item). Pre-change: rule 6 Planning on the
  closed scope. Post-change: 4a retarget dispatch.
- Tick-9 shape (2026-07-16, LOOP_TICKS line 10): focus done+flushed,
  `last_validation.status: not_run` H5-reset residue, zero open intakes.
  Pre-change: rule 11 Validation on a flushed corpse. Post-change:
  `no_action` / `scope_complete_no_open_intake` (deterministic resolution —
  no LLM recovery tick).

## Acceptance Criteria Mapping
- Maps to: CHANGE-0031 AC-001 (retarget instead of stale rule 6 / needs_llm)
  - Spec-AC-01; verification via TEST-001/TEST-004.
- Maps to: CHANGE-0031 AC-002 (rule 11 never fires on a done item)
  - Spec-AC-02; verification via TEST-002/TEST-004.
- Maps to: CHANGE-0031 AC-003 (existing dispatch + ceremony suites green,
  live-focus behavior unchanged)
  - Spec-AC-04; verification via TEST-006.
- Maps to: CHANGE-0031 AC-004 (both real-world shapes replay
  deterministically)
  - Spec-AC-05; verification via TEST-005.
- Fail-closed ambiguity (intake Constraints: single-shape only, Constitution
  art. 4) — Spec-AC-03; verification via TEST-003/TEST-004.
- Hygiene/purity (intake Verification block) — Spec-AC-06; TEST-007.

Spec-AC list (each measurable):
- Spec-AC-01: Given focus whose work item is `status: done` (or absent) AND
  focus ref present in METRICS.jsonl AND exactly one open mappable intake
  doc in docs/issues with no done work item, decide()/CLI emit
  `verdict: "dispatch"`, `rule: "4a"`, `role: "Planning"`, `ref_id` = the
  intake's ref, inputs containing the intake's primary_path, reason
  `focus_completed_retarget_to_open_intake`, `retarget` payload carrying
  `{from_ref, to_ref, to_type, to_primary_path}` with `to_type` the correct
  `intake_*` enum member, `lane.selected == "full"` with
  `lane.ceremony_level == 2`, exit code 0. The output is NOT rule 5/6 on the
  closed focus and NOT `needs_llm`.
- Spec-AC-02: A `status: done` work item with `last_validation.status:
  not_run` NEVER produces a rule-11 Validation dispatch: flushed variants
  resolve via the 4a arm (retarget or `scope_complete_no_open_intake`);
  the done+unflushed+not_run variant degrades to `needs_llm
  no_rule_matched`. Non-done items in eligible phases still fire rule 11
  exactly as today.
- Spec-AC-03: With the D1 guard firing — zero candidates → `no_action`
  rule 4a reason `scope_complete_no_open_intake` exit 3; two or more
  candidates → `needs_llm` exit 4 with one reason matching
  `^multiple_open_intakes:` that names EVERY candidate ref; a single
  unmappable candidate (techdebt/unparseable frontmatter) → `needs_llm`
  reason `open_intake_unmappable:<path>`; probe failure → `needs_llm`
  reason `open_intake_scan_failed`. No arm ever guesses a target.
- Spec-AC-04: `bash tests/skills/test-aai-orchestration-dispatch.sh` exits 0
  including all pre-existing stanzas unchanged; ceremony-suite dispatch
  stanzas (test_011..test_016 and test_017's non-environmental arms) stay
  green; for every fixture whose focus is a live non-done work item the
  output differs from pre-change ONLY by the additive `retarget: null` field
  (rule/role/tier/verdict/reasons/exit code identical).
- Spec-AC-05: The two D7 evidence-replay fixtures resolve deterministically:
  tick-1 shape → 4a retarget dispatch (exit 0); tick-9 shape → `no_action`
  (exit 3). Neither emits `needs_llm`.
- Spec-AC-06: decide() purity holds on retarget snapshots (same input →
  same output, input not mutated); the CLI writes nothing (cksum of STATE
  and the fixture docs/issues tree unchanged across runs);
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exit 0;
  `node .aai/scripts/check-state.mjs` OK.

## Constitution deviations

None.

Honest per-article check at freeze (docs/CONSTITUTION.md):
- Art. 1 (evidence before claims): retarget fires only on executable
  evidence (work-item status, METRICS.jsonl presence, frontmatter status);
  no verdict semantics weakened; RED-proof required. No deviation.
- Art. 2 (simplicity/YAGNI): one guard arm, one predicate clause, one probe;
  multi-intake tie-breaking deliberately NOT built. No deviation.
- Art. 3 (portability): plain Node stdlib mjs + bash-3.2 tests. No deviation.
- Art. 4 (degrade and report): every ambiguous shape flags a named,
  machine-greppable reason; nothing silent. No deviation.
- Art. 5 (additive first): new `retarget` field is additive (null
  elsewhere); no rule renumbering; existing fixtures byte-identical on
  asserted fields. No deviation.
- Art. 6 (single-writer STATE): dispatcher stays read-only; the set-focus
  write remains with Planning via state.mjs. No deviation.
- Art. 7 (operator-only merge): untouched. No deviation.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state.

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | 4a retarget dispatch on done/flushed focus + single open intake    | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-006/TEST-009) | — | — |
| Spec-AC-02 | rule 11 never fires on a done work item                            | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-007) | — | — |
| Spec-AC-03 | fail-closed ambiguity: 0 → no_action; 2+ / unmappable / scan-fail → needs_llm named reasons | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-008/TEST-009) | — | — |
| Spec-AC-04 | regression parity: both suites green; live-focus outputs additive-only diff | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-011); ceremony test_011..016 individually PASS | — | — |
| Spec-AC-05 | tick-1 and tick-9 evidence shapes replay deterministically         | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-010) | — | — |
| Spec-AC-06 | purity + zero writes + strict audit + check-state                  | done | docs/ai/tdd/dispatch-retarget-green.log (TEST-012); `docs-audit --check --strict --no-event` CLEAN; `check-state.mjs` OK | — | — |

## Implementation plan
- Components affected: orchestration core
  (.aai/scripts/orchestration-dispatch.mjs: decide() 4a arm + rule-11
  clause, buildSnapshot() open-intakes probe, output constructors' additive
  `retarget` field, RULES table), test layer
  (tests/skills/test-aai-orchestration-dispatch.sh: new functions
  test_006..test_012 mapped to TEST-001..TEST-007), docs/INDEX.md
  (regenerated).
- Order: (1) write new suite functions; (2) RED run on pre-change tree →
  docs/ai/tdd/dispatch-retarget-red.log; (3) snapshot probe + 4a arm +
  retarget field (TEST-001, TEST-003, TEST-004 GREEN); (4) rule-11 clause
  (TEST-002 GREEN); (5) evidence-replay fixtures (TEST-005 GREEN);
  (6) survival re-runs (TEST-006, TEST-007) → dispatch-retarget-green.log;
  (7) index regen + check-state; (8) AC table reconciliation; (9) STATE via
  CLI.
- Edge cases: done work item NOT yet flushed (validation pass) → rules 13/14
  close pipeline untouched; done + unflushed + not_run residue → `needs_llm
  no_rule_matched`; candidate doc whose work item is done → excluded
  (false-open, not a candidate); focus ref absent from items AND not
  flushed → today's behavior unchanged; candidate with `status:
  implementing` counts (open); techdebt/rfc/prd docs count but are
  unmappable; empty docs/issues dir → zero candidates; `retarget` is null on
  EVERY non-4a verdict including no_action/needs_llm; rule 10/12 fail
  verdicts still fire regardless of item status.

Seam analysis:
- Seam S1 — decide()/RULES shared with SPEC-0041's lane logic and the
  ceremony suite. Crossing test: TEST-006 re-runs the REAL
  tests/skills/test-aai-ceremony-levels.sh dispatch stanzas plus the full
  legacy dispatch suite post-change.
- Seam S2 — the dispatch JSON crosses the CLI boundary to the LOOP /
  ORCHESTRATION wrappers. Crossing test: TEST-004 drives the real CLI
  end-to-end on fixture repos (stdout JSON, exit codes, --human).
- Seam S3 — the retarget payload is consumed by Planning's step-12 set-focus
  (state.mjs enums: `to_type` must be a valid `current_focus.type` member).
  Crossing test: TEST-004 asserts the payload carries a valid enum type +
  ref + path (everything set-focus needs). Residual risk (recorded): wrapper
  compliance is prompt-guidance — a non-compliant runner could ignore the
  payload; the named reason + LOOP_TICKS visibility makes that observable,
  same class as SPEC-0041's residual.
- Seam S4 — the METRICS.jsonl `flushed` probe is shared with rule 14.
  Crossing test: TEST-001/TEST-004 fixtures exercise flushed=true and
  flushed=false; TEST-006 proves the rule-14 arm unchanged.
- Seam S5 — docs/issues frontmatter conventions shared with
  docs-audit/index tooling. Crossing test: TEST-004 fixtures use the
  canonical intake frontmatter shape (id/type/number/status), including one
  mixed-convention fixture (number-based work-item ref vs slug id).

## Test Plan

All rows live in tests/skills/test-aai-orchestration-dispatch.sh (reserved
for this scope by SPEC-0041 D5); bash-3.2 compatible; scratch temp-dir
fixture repos only.

| Test ID  | Spec-AC    | Type        | File path (expected)                            | Description                                                                                     | Status  |
|----------|------------|-------------|--------------------------------------------------|--------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | decide() 4a table: done+flushed (and absent+flushed) focus + one open intake → Planning retarget with payload, reason, lane full; done+unflushed → close pipeline untouched | green (test_006_arm4a_decide_table) |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | rule-11 done-skip: done+not_run never dispatches Validation (flushed → 4a; unflushed → needs_llm no_rule_matched); non-done items still fire rule 11 | green (test_007_rule11_done_skip) |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-orchestration-dispatch.sh | decide() ambiguity outcomes: 0 → no_action scope_complete_no_open_intake; 2+ → needs_llm multiple_open_intakes naming all refs; unmappable single → open_intake_unmappable; open_intakes null → open_intake_scan_failed | green (test_008_arm4a_ambiguity) |
| TEST-004 | Spec-AC-01, Spec-AC-03 | integration | tests/skills/test-aai-orchestration-dispatch.sh | CLI end-to-end on fixture repos with REAL docs/issues files: exit 0/3/4 per shape; retarget payload valid for state.mjs set-focus (enum type, ref, path); mixed ref-convention fixture; retarget null on non-4a verdicts | green (test_009_cli_integration) |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Evidence replay: tick-1 (2026-07-17) shape → 4a retarget; tick-9 (2026-07-16) shape → no_action; neither needs_llm | green (test_010_evidence_replay) |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Seam survival: all legacy dispatch stanzas green unchanged; ceremony-suite dispatch/lane stanzas green; live-focus fixture output additive-only diff (retarget: null) | green (test_011_seam_survival) |
| TEST-007 | Spec-AC-06 | integration | tests/skills/test-aai-orchestration-dispatch.sh | Purity + zero-writes (cksum STATE + fixture issue docs before/after) + `docs-audit --check --strict --no-event` exit 0 + `check-state` OK | green (test_012_purity_and_hygiene) |

Notes:
- RED-proof: TEST-001..TEST-005 must be observed FAILING on the pre-change
  tree (docs/ai/tdd/dispatch-retarget-red.log). TEST-006/TEST-007 are
  survival invariants (green pre-change by construction; non-vacuous — they
  re-run the real gates/suites over the changed tree post-change).
- Known environmental exceptions (verify via stash/main comparison before
  chasing): tests/skills/test-aai-worktree.sh (LEARNED 2026-07-15) and
  prompt-diet TEST-010 byte-budget reached through ceremony test_010
  (LEARNED 2026-07-17, DEBT-0002) fail pre-existing on clean main.

## Verification
- `bash tests/skills/test-aai-orchestration-dispatch.sh` → exit 0, including
  the new TEST-001..TEST-007 stanzas (intake AC-001, AC-002, AC-004).
- `bash tests/skills/test-aai-ceremony-levels.sh test_011` (and
  test_012..test_016 via single-function invocation, per LEARNED 2026-07-17
  masking note) → PASS (intake AC-003, SPEC-0041 lane parity).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/check-state.mjs` → OK.
- `node .aai/scripts/generate-docs-index.mjs && git diff --exit-code -I '^Generated:' -- docs/INDEX.md`
  → exit 0 (idempotent).
- Fail-closed proof: TEST-003/TEST-004 fixture outputs (multiple/unmappable/
  scan-failed → exit 4 with named reasons; zero → exit 3).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: dispatch-new-intake-after-completed-scope
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/dispatch-retarget-red.log,
  docs/ai/tdd/dispatch-retarget-green.log)
- commit SHA or diff range when available

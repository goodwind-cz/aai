---
id: SPEC-0014
type: spec
status: done
links:
  change: CHANGE-0008
  rfc: null
  requirement: null
  pr: []
  commits: []
---

# SPEC-0014 — state.mjs field clearing, set-phase spec_path placement, auto-trigger reality alignment (CHANGE-0008)

SPEC-FROZEN: true

## Links
- Change request (WHAT/WHY): docs/issues/CHANGE-0008-post-release-follow-ups.md
- Engine being extended: .aai/scripts/state.mjs (+ shared lib .aai/scripts/lib/state-core.mjs — read-only for this scope; no primitive changes expected)
- Test suite being extended: tests/skills/test-aai-state.sh (SPEC-0012 TEST-001..025 live there; this spec's ids are SPEC-0014-local)
- F3 targets: .aai/SKILL_AUTO_TRIGGER.prompt.md, .claude/.codex/.gemini aai-auto-trigger wrappers, docs/USER_GUIDE.md ("Automation & Integration" + skills quick list), .aai/AGENTS.md skill-index line, docs/SKILL_CATALOG.html (generated)
- Prior decisions honored: SPEC-0012 D2/D3/D6 (line engine, atomic write, reset-block guards), SPEC-0013 D8 (triggers.json has no runtime consumer; real channel is wrapper-description trigger phrases)
- Live dogfood evidence for F1: docs/ai/STATE.yaml still carries stale CHANGE-0007 worktree.branch/path and code_review.report_paths/notes because no subcommand can null a field
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for F1 and F2 — both change the transactional STATE
  engine, the exact surface where a tautological test is worthless: RED is natural and
  cheap (today `--clear` exits 2 as an unknown flag; today the placement byte-assertion
  fails against the reproduced bug). Loop (grep-wiring, RED-proven against the pre-change
  text) for the mechanical F3 doc/wrapper edits. Matches the SPEC-0012/SPEC-0013 posture.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: small scope — one engine file plus its test suite, one prompt
  rewritten to a short notice, three wrapper descriptions, two USER_GUIDE spots, one
  AGENTS.md line, one regenerated catalog. All engine tests run against scratch temp-dir
  fixtures (`--state` override) and never touch the real STATE.yaml, so blast radius is
  contained; not `not_needed` because state.mjs is the loop's own write path and an
  isolated branch keeps a broken intermediate state out of the live loop. Not
  `recommended`/`required`: fewer than three independent modules, no schema change, no
  migration (SPEC-0013 precedent applied in reverse).
- User decision: undecided (Implementation Preparation asks the operator; Planning does not create worktrees)
- Base ref: main
- Worktree branch/path: decided at preparation; suggested feat/change-0008-follow-ups
- Inline review scope (if inline is chosen): .aai/scripts/state.mjs,
  tests/skills/test-aai-state.sh, tests/skills/test-aai-hygiene-pack.sh,
  .aai/SKILL_AUTO_TRIGGER.prompt.md, .claude/skills/aai-auto-trigger/SKILL.md,
  .codex/skills/aai-auto-trigger/SKILL.md, .gemini/skills/aai-auto-trigger/SKILL.md,
  docs/USER_GUIDE.md, .aai/AGENTS.md, docs/SKILL_CATALOG.html,
  docs/specs/SPEC-0014-state-clear-spec-path-placement-auto-trigger-alignment.md

## Design decisions (resolved — do not reopen during implementation)

### D1 — F1 syntax: `--clear <comma-list>` per subcommand
One new flag, `--clear <field,field,...>`, added to CMD_FLAGS for exactly four
subcommands: `set-worktree`, `set-code-review`, `set-validation`, `set-focus`.
- The value is a comma-separated list of STATE field names as they appear in the YAML
  block (the names the operator sees when the stale value leaks), not flag names.
- `--clear` alone satisfies the existing ">=1 flag" requirement of set-worktree /
  set-code-review.
- `--clear` may be combined with set flags in one invocation, EXCEPT naming the same
  field both ways (see D2 refusals).
- The explicit-null-sentinel alternative from the intake is rejected: a magic value on
  existing flags would make `--branch null` ambiguous (literal string vs clear) and
  break the closed-set discipline; a dedicated flag keeps both channels unambiguous.

### D2 — F1 whitelists, semantics, refusals
Per-subcommand clearable-field whitelists (closed sets, mirrors the enum discipline):
- set-worktree: `branch`, `path`, `base_ref`, `inline_review_scope`, `rationale`
- set-code-review: `scope`, `base_ref`, `head_ref`, `report_paths`, `notes`
- set-validation: `ref_id`, `evidence_paths`, `notes`
- set-focus: `spec_path`
Semantics:
- Scalar and free-text (`>-`) fields clear to a single `field: null` line at the
  block's 2-space indent (same shape `nullFieldIfPresent` already writes).
- List fields (`report_paths`, `evidence_paths`) clear to `field: []` — this also
  unlocks the replace workflow for the append-only `--report` flag (clear, then append).
- A cleared field that is MISSING from the block is created as `field: null` (or `[]`)
  at end of block — consistent with setField's create-at-end normalization.
- Clearing an already-null/already-`[]` field is an idempotent field-level no-op; the
  command still exits 0 and performs its normal write cycle (updated_at_utc bump), the
  same contract as re-running any set-* command with an unchanged value. No dirty
  tracking is introduced.
- Bonus normalization (same leak class, one line): `set-focus --type none` now also
  nulls `spec_path` when present, exactly as it already nulls ref_id/primary_path.
Refusals (exit 2, before any write, file byte-identical):
- Unknown field in the list → error names the offending field AND the full valid
  clearable set for that subcommand (mirrors the W5 unknown-flag message shape).
- Verdict/status/policy fields are NOT in any whitelist by construction:
  `status` (set-validation, set-code-review) → the refusal message must name
  `reset-block` as the sanctioned path; `required` (set-code-review), `recommendation` /
  `user_decision` (set-worktree) have explicit closed-set reset values and stay
  flag-only; `run_at_utc` stays self-stamped. D6 reset-block guard semantics
  (pass/waived refusal, `--force` explicitness, no-op on not_run) are untouched.
- The same field named in `--clear` and set by its flag in one invocation → exit 2
  (contradictory instruction). Flag-to-field mapping for this check: `path`→`path`,
  `inline-scope`→`inline_review_scope`, `report`→`report_paths`,
  `evidence`→`evidence_paths`, `ref`→`ref_id`, `spec-path`→`spec_path`, others 1:1.
- Empty list (`--clear` with no value or `--clear ""`) → exit 2 missing-value error.

### D3 — F2 placement rule for set-phase item fields
Reproduced defect (2026-07-07, scratch fixture): the existing-item extent scan in
cmdSetPhase does not stop at blank lines, so the item end index lands AFTER the blank
line that separates the item from the next top-level block, and a missing `spec_path`
(or `primary_path`) is spliced there — outside the visual block, glued to the next
top-level key. Valid YAML, wrong placement. Fix rules:
- The insertion point for a MISSING item field is always INSIDE the contiguous item
  lines (the run of lines from `  - ref_id:` up to the first blank line, next `  - `
  item, or dedent below 4 spaces).
- `spec_path` is placed directly after the `primary_path` line when that field exists
  in the item; otherwise at the end of the contiguous item lines.
- `primary_path` (when created) also lands at the end of the contiguous item lines,
  never after a blank.
- Existing fields keep updating in place (unchanged behavior).
- The upsert path (new item) already emits ref_id, status, phase, primary_path,
  spec_path in order — unchanged, asserted as a control.
- Idempotence: running the same set-phase twice yields byte-identical files modulo the
  updated_at_utc line.
- No test currently asserts the buggy placement (verified: no existing case passes
  --spec-path to set-phase), so no conscious test rewrite is needed — only new tests.

### D4 — F3 shape: deprecate the auto-trigger skill (option b)
Decision: (b) deprecation, not (a) aspirational labeling. Justification: the skill's
ONLY function is CRUD over `.claude/triggers.json`, which has no runtime consumer
(grep-proven in SPEC-0013 D8; the file does not even exist in this repo). An
"aspirational" label would keep shipping a 500-line manual whose every workflow
produces inert config — exactly the trap the intake names (operators wiring triggers
that never fire). The real auto-invocation channel already exists and is delivered
(wrapper-description trigger phrases, aai-wrap-up precedent). Shape:
- .aai/SKILL_AUTO_TRIGGER.prompt.md → replaced by a short deprecation notice (target
  under ~40 lines): DEPRECATED marker; the no-runtime-consumer evidence with pointer to
  SPEC-0013 D8; the real channel (skill/wrapper description trigger phrases, with the
  aai-wrap-up example); what to do instead (enrich the target skill's wrapper
  description); note that building a real consumer is out of scope (CHANGE-0008).
- Wrappers stay PRESENT in all three trees (.claude/.codex/.gemini — muscle memory,
  intake constraint) but their `description` frontmatter and body say deprecated and
  point to the notice; they no longer claim to manage a working mechanism.
- docs/USER_GUIDE.md: the `/aai-auto-trigger` entry in "Automation & Integration"
  becomes a short deprecated entry (why + the real trigger-phrase channel); the
  "Automation setup" line in the quick skills list is relabeled deprecated.
- .aai/AGENTS.md skill-index line: relabeled deprecated with the same pointer.
- docs/SKILL_CATALOG.html: generated artifact — regenerate via the docs-hub generator
  after the wrapper edits (preferred); a targeted edit of the aai-auto-trigger
  description string is acceptable if regeneration produces unrelated churn.
- .aai/system/SUPERPOWERS_INTEGRATION.md is already reality-aligned (lists
  auto-triggering under "What We Didn't Adopt (Yet)" as a future idea) — left as-is.
- Historical records (docs/releases/REL-0001, docs/specs/SPEC-0013, docs/issues/*,
  docs/ai/**) describe reality and are out of scope for the grep assertion.

### D5 — test residence and id mapping
- F1/F2 cases live in tests/skills/test-aai-state.sh as new functions appended after
  test_025 (file-local ordinals continue test_026..; comments map each function to its
  SPEC-0014 TEST id). Fixtures stay scratch temp-dir copies via `--state`; bash-3.2
  compatible; run through .aai/scripts/aai-run-tests.sh.
- F3 grep-wiring lives in tests/skills/test-aai-hygiene-pack.sh (it already owns the
  SPEC-0013 triggers/wrapper assertions TEST-016..018 and the triple-tree helper
  pattern); one new function.
- TEST ids below are SPEC-0014-local (SPEC-0013 precedent: ids are spec-local, files
  are shared suites).

## Acceptance Criteria Mapping

| Req AC (CHANGE-0008) | Spec-AC | Verification (command → expected evidence) |
|---|---|---|
| AC-001 (clear via CLI) | Spec-AC-01 | TEST-001/TEST-002: `--clear` on stale fixtures → fields become null/[], diff block-local, check-state exit 0 |
| AC-001 (guard preserved) | Spec-AC-02 | TEST-003: `--clear status` refused exit 2 naming reset-block; reset-block suite cases (TEST-011 of SPEC-0012) still green |
| AC-002 (strict clear list) | Spec-AC-03 | TEST-004: unknown field exit 2 naming the valid set; clear+set same field exit 2; byte-identical file |
| AC-001 (idempotence) | Spec-AC-04 | TEST-005: clearing an already-null field exits 0, single null line, twice-run stable, check-state exit 0 |
| AC-003 (spec_path placement) | Spec-AC-05 | TEST-006/TEST-007: byte-level placement assertion (directly after primary_path, inside item block), double-run idempotence, upsert control, no-primary_path fallback |
| AC-004 (no false triggers.json claim) | Spec-AC-06 | TEST-008: grep-wiring — deprecation notice + wrappers + USER_GUIDE + AGENTS.md + catalog assertions; discriminating repo grep clean |
| AC-005 (suites + repo clean) | Spec-AC-07 | TEST-009: full state suite exit 0; hygiene-pack suite exit 0; repo `--check --strict --no-event` exit 0 CLEAN; `--lint-body-file docs/USER_GUIDE.md` exit 0; index idempotent |

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | `--clear <comma-list>` on set-worktree/set-code-review/set-validation/set-focus per D1/D2: scalars→null, lists→[], atomic write, check-state clean | done | docs/ai/tdd/red-20260707T075058Z-spec0014-f1-f2.log + docs/ai/tdd/green-20260707T075338Z-spec0014-f1-f2.log (test_026/test_027) | TDD | Post-review W2 hardening: blank-line block-scalar span (TEST-012, docs/ai/tdd/red-20260707T082540Z-spec0014-remediation-e1-w1-w2.log + green-20260707T082628Z) |
| Spec-AC-02 | Guard ownership preserved: status/verdict fields not clearable, refusal names reset-block; D6 semantics byte-untouched | done | docs/ai/tdd/green-20260707T075338Z-spec0014-f1-f2.log (test_028); SPEC-0012 TEST-011 reset-block cases green in the full-suite run | TDD | — |
| Spec-AC-03 | Strict clear-list validation: unknown field exit 2 naming valid set; clear+set contradiction exit 2; no write on rejection | done | docs/ai/tdd/green-20260707T075338Z-spec0014-f1-f2.log (test_029, byte-identical snapshots) | TDD | Post-review E1/W1 hardening: prototype-name refusal + repeated-flag accumulation (TEST-010/TEST-011, docs/ai/tdd/red-20260707T082540Z-spec0014-remediation-e1-w1-w2.log + green-20260707T082628Z) |
| Spec-AC-04 | Clearing an already-null/[] field is an idempotent no-op exit 0 | done | docs/ai/tdd/green-20260707T075338Z-spec0014-f1-f2.log (test_030, triple-run stable + create-as-null) | TDD | — |
| Spec-AC-05 | set-phase places spec_path directly after primary_path inside the item block per D3; double-run byte-idempotent modulo updated_at_utc | done | docs/ai/tdd/red-20260707T075058Z-spec0014-f1-f2.log + docs/ai/tdd/green-20260707T075409Z-spec0014-f2-placement.log (test_031/test_032 byte-assertions) | TDD | — |
| Spec-AC-06 | Auto-trigger deprecation per D4: notice, three wrappers, USER_GUIDE, AGENTS.md, catalog; no file presents triggers.json as working | done | docs/ai/tdd/red-20260707T075520Z-spec0014-f3-wiring.log + docs/ai/tdd/green-20260707T075654Z-spec0014-f3-wiring.log (hygiene test_030); discriminating repo grep clean | loop | — |
| Spec-AC-07 | All suites green; real-repo audit CLEAN; USER_GUIDE body lint PASS; index idempotent | done | test-aai-state.sh exit 0 (33 tests); test-aai-hygiene-pack.sh exit 0 (11 tests); docs-audit --check --strict --no-event Verdict CLEAN exit 0; --lint-body-file exit 0 on all 7 edited .md; generate-docs-index twice byte-idempotent | loop | Validation independently re-verifies |

Status values: planned | implementing | done | deferred | blocked | rejected (gate behavior per template).

## Implementation plan
- Engine (TDD, .aai/scripts/state.mjs only): parse/validate `--clear` (closed
  per-subcommand whitelists, contradiction check) → apply via a small clearFields
  helper reusing setField/nullFieldIfPresent shapes (scalar null / list `[]`) inside the
  existing editBlock calls of the four subcommands; add the set-focus type-none
  spec_path null. Fix the cmdSetPhase item-extent/insertion rule per D3 (stop the
  contiguous-item scan at blank lines; primary_path-adjacent spec_path insertion).
- Tests: new functions in test-aai-state.sh (fixture diversity per SKILL_TDD checklist:
  stale-populated fixture, already-null fixture, missing-field fixture, guard-bypass
  attempt as negative control, blank-line-separated item for placement, minimal item
  without primary_path, double-run idempotence); one grep function in
  test-aai-hygiene-pack.sh for F3.
- Docs (loop): D4 edits; regenerate catalog; keep every historical mention untouched.
- Edge cases owned by tests: empty clear list, whitespace/unknown field, clear+set same
  field, clear on missing field (created as null), list-field clear then re-append,
  item followed by blank line then next top-level key, item without primary_path,
  upsert path ordering control.

## Seam analysis (cross-feature integration)
- Seam 1: `--clear` output ↔ check-state.mjs invariants (a cleared field must never
  produce a shape the validator rejects). Crossed end-to-end by TEST-001/002/005 running
  check-state after every mutation on the same file.
- Seam 2: `--clear` ↔ reset-block guard ownership (two writers of the same verdict
  blocks; D6). Crossed by TEST-003: the bypass attempt must be refused AND the
  sanctioned reset-block path must still behave per SPEC-0012 TEST-011 (full suite run).
- Seam 3: set-phase spec_path ↔ downstream STATE readers (readScalar consumers, role
  prompts reading the item block). Crossed by TEST-006 asserting check-state exit 0 and
  the field being inside the item block that those readers scan.
- Seam 4: wrapper triple-tree + generated catalog (.claude/.codex/.gemini +
  SKILL_CATALOG.html render of the same description). Crossed by TEST-008 asserting all
  three trees and the catalog string.
- Residual risk (accepted): whether external operators had built private consumers of
  triggers.json cannot be grepped from this repo; the deprecation notice names the
  migration path (wrapper descriptions), which is the best available mitigation.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Status |
|----------|------------|-------------|----------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | `set-worktree --clear branch,path` on a stale fixture → both `null`; strip_block locality (only worktree + updated_at_utc changed); check-state exit 0 | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | `set-code-review --clear head_ref,report_paths,notes` → null/[]/null; `set-validation --clear evidence_paths,ref_id,notes` → []/null/null; `set-focus --clear spec_path` → null; `--clear` combined with a disjoint set flag applies both; `set-focus --type none` nulls spec_path; check-state exit 0 after each | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-state.sh | Guard-bypass negative control: `set-validation --clear status` and `set-code-review --clear status` → exit 2, message names reset-block, file byte-identical; `set-worktree --clear recommendation` → exit 2 | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | `--clear bogus` → exit 2 naming the field and the valid clearable set; `--clear branch --branch x` → exit 2 contradiction; `--clear` without value → exit 2; all leave the file byte-identical | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-state.sh | Clearing an already-null scalar and an already-[] list → exit 0, exactly one field line remains, second run exit 0, check-state exit 0; clearing a MISSING whitelisted field creates `field: null` | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh | Placement byte-assertion on a blank-line-separated item: after `set-phase --spec-path`, the spec_path line sits directly after primary_path inside the item, blank line still trails the item; run twice → byte-identical modulo updated_at_utc; check-state exit 0 | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-state.sh | Fallback + control: item WITHOUT primary_path gets spec_path at end of contiguous item lines (never after the blank); upsert of a NEW item keeps the ref_id/status/phase/primary_path/spec_path order | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-hygiene-pack.sh | F3 grep-wiring: notice carries DEPRECATED + no-runtime-consumer + real-channel pointer and drops the pattern-matching manual; three wrapper descriptions deprecated in all trees; USER_GUIDE entry + quick-list line updated; AGENTS.md line updated; catalog description updated; discriminating grep finds no working-mechanism claim in .aai/ docs/ (historical records excluded per D4) | green |
| TEST-009 | Spec-AC-07 | e2e | tests/skills/test-aai-state.sh | Regression backstop: full test-aai-state.sh exit 0 (SPEC-0012 cases green, incl. reset-block guards); repo `docs-audit --check --strict --no-event` exit 0 CLEAN; `--lint-body-file docs/USER_GUIDE.md` exit 0; generate-docs-index idempotent | green |
| TEST-010 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | Review E1 regression (test_034): JS prototype-chain names (`toString`, `__proto__`, `constructor`, `valueOf`, `hasOwnProperty`, `isPrototypeOf`) refused exit 2 naming the valid clearable set on all four `--clear` subcommands, incl. smuggled into a valid comma-list; file byte-identical, no junk key written | green |
| TEST-011 | Spec-AC-03 | integration | tests/skills/test-aai-state.sh | Review W1 regression (test_035): repeated `--clear a --clear b` accumulates (union of all occurrences, dedupe to one field line); contradiction/unknown/valueless in a LATER occurrence still exit 2 byte-identical | green |
| TEST-012 | Spec-AC-01 | integration | tests/skills/test-aai-state.sh | Review W2 regression (test_036): clearing/overwriting a hand-edited `>-` field containing a blank-line paragraph replaces the WHOLE block-scalar span — no orphaned continuation lines; PyYAML ground truth parses the cleared field as real null; check-state exit 0 | green |

Test status values: pending → red → green.

RED-proof obligation (all strategies): TEST-001..007 follow full TDD against the engine —
their natural RED is real (today `--clear` is rejected as an unknown flag by the W5
strict-args guard, and the TEST-006 byte-assertion fails against the reproduced
insert-after-blank bug; capture both in docs/ai/tdd/red-*.log before touching state.mjs).
TEST-008's RED is observed by running the new grep function against the pre-change
prompt/wrapper text (every assertion must fail today — e.g. the notice's DEPRECATED
marker does not exist and the wrappers still claim the mechanism works). TEST-009 is the
regression backstop (green before and after; its failure capability is proven by the
SPEC-0012 suite's own negative controls).

### Post-review remediation (review-20260707T081303Z: E1 + W1 + W2)

Fixed in the same TDD discipline (RED docs/ai/tdd/red-20260707T082540Z-spec0014-remediation-e1-w1-w2.log,
GREEN docs/ai/tdd/green-20260707T082628Z-spec0014-remediation-e1-w1-w2.log; tests written first,
each failed on exactly the reported defect):

- **E1 (ERROR, Spec-AC-03):** `resolveClearList` tested whitelist membership with plain
  property access, so `Object.prototype` names (`toString`, `__proto__`, …) passed as
  "known" on all four `--clear` subcommands and wrote a junk `field: null` line with
  exit 0. Fix: own-property check via `Object.hasOwn(spec, f)` (Node ≥16.9; repo runs
  on far newer). Regression: TEST-010 (test_034).
- **W1:** repeated `--clear a --clear b` was last-wins — the first instruction silently
  dropped. Fix: `clear` added to `MULTI_FLAGS`; all occurrences merge into one union
  list (deduped). Design choice: ACCUMULATE rather than refuse, because `MULTI_FLAGS`
  (`--evidence`/`--report`) is already this CLI's established semantics for repeatable
  list-valued flags — repeats union, they never error — and accumulation executes the
  operator's full intent while strict validation still spans every occurrence.
  Regression: TEST-011 (test_035).
- **W2:** `fieldSpan` stopped at the first blank line, so clearing/overwriting a
  hand-edited `>-` field containing a blank-line paragraph orphaned the post-blank
  continuation (junk non-null value, invisible to check-state). Fix: a blank run joins
  the span when a more-indented continuation follows it (blank lines are legal inside
  YAML block scalars); the field otherwise still ends at the blank. Regression:
  TEST-012 (test_036) with PyYAML ground truth (`notes` parses as real null).

## Verification
- `bash tests/skills/test-aai-state.sh` → exit 0 (SPEC-0012 TEST-001..025 cases + the new SPEC-0014 functions)
- `bash tests/skills/test-aai-hygiene-pack.sh` → exit 0 (SPEC-0013 cases + the F3 function)
- `node .aai/scripts/state.mjs set-worktree --clear branch,path --state <fixture>` walk-through on a stale-populated fixture → fields null, diff touches only those lines + updated_at_utc, `node .aai/scripts/check-state.mjs <fixture>` exit 0
- `node .aai/scripts/state.mjs set-phase --ref <id> --phase planning --spec-path <p> --state <fixture>` twice → placement + byte-idempotence per D3
- `grep -rn "triggers.json" .aai docs .claude .codex .gemini` → only reality-aligned mentions remain (deprecation notice, historical records per D4)
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0, Verdict CLEAN
- `node .aai/scripts/docs-audit.mjs --lint-body-file docs/USER_GUIDE.md` → exit 0
- `node .aai/scripts/generate-docs-index.mjs` twice → second run byte-idempotent
- Suites via `.aai/scripts/aai-run-tests.sh` (LEARNED: never spawn runners directly)
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal.

## Evidence contract
For each implementation, validation, TDD, and code review artifact record: ref_id
(CHANGE-0008/SPEC-0014), Spec-AC + TEST-xxx links, command or review scope, exit code or
verdict, evidence path (docs/ai/tdd/*.log for RED/GREEN), commit SHA or diff range.

## Code review plan (initial)
- code_review.required: true (engine change on the loop's own STATE write path).
- Scope: the inline review scope list above (explicit paths).
- Base ref: main. Review runs after Validation PASS, per WORKFLOW.

Notes:
This document defines HOW, not WHAT/WHY (WHY lives in CHANGE-0008).
This document does not define workflow.

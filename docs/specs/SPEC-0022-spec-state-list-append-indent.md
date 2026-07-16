---
id: spec-state-list-append-indent
type: spec
number: 22
status: done
links:
  issue: ISSUE-0007
  rfc: null
  requirement: null
  pr:
    - 63
  commits:
    - 26b21b7
---

# SPEC — state list-append indent fidelity + structural list lint (ISSUE-0007)

SPEC-FROZEN: true

## Links
- Issue (WHAT/WHY): docs/issues/ISSUE-0007-state-list-append-indent.md
- Engine being fixed: .aai/scripts/lib/state-engine.mjs (`appendListItems`, extracted
  from state.mjs by CHANGE-0009 / SPEC-0019 D5)
- CLI call sites: .aai/scripts/state.mjs `set-code-review --report` (append),
  `set-validation --evidence` (whole-field write)
- Validator being extended: .aai/scripts/check-state.mjs
- Bundled closeout nits (same 2026-07-15 closeout):
  - .aai/scripts/metrics-flush.mjs ephemeral cleanup vs tracked docs/ai/tdd/.gitkeep
  - .aai/STATE_FALLBACK.md full-reset field list vs `applyFullReset` ref_id parity
    (SPEC-0019 deviation-3 follow-up)
- Test suites extended: tests/skills/test-aai-state.sh,
  tests/skills/test-aai-check-state.sh, tests/skills/test-aai-metrics.sh
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written / frozen for implementation
- implementing: spec frozen, work delivered in the worktree, awaiting
  independent validation + merge (this doc)
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Root cause (established by reproduction before freeze)

`appendListItems` (.aai/scripts/lib/state-engine.mjs:276-295) hardcodes the
appended sibling's indent at key-indent+2 (`${sp}  - ${yq(it)}`) instead of
reading the indent the list's existing items actually use. Whenever a populated
list carries items at any other legal relative indent (observed: items 4 spaces
past the key, e.g. hand-repaired or foreign-writer files), the appended sibling
lands 2 spaces past the key — shallower than its siblings — producing YAML that
PyYAML rejects (`expected <block end>, but found '-'` / `<block sequence
start>`) while check-state.mjs (top-level-keys-only scan) still passes.
Reproduced on a scratch STATE on 2026-07-16 (RED evidence,
docs/ai/tdd/red-issue-0007-*.log). Three field sightings on 2026-07-15:
code_review.report_paths, last_validation.evidence_paths, archived worktree
STATEs.

## Implementation strategy
- Strategy: tdd
- Rationale: the fix lands in the transactional STATE engine — the exact surface
  where a tautological test is worthless and where SPEC-0012/0014/0019 set the
  TDD precedent. RED is natural and cheap: the mis-indent reproduces
  deterministically on a scratch fixture, and the new check-state lint has an
  obvious failing input. All fixtures are scratch temp-dir copies (`--state`
  override); the real per-dev STATE.yaml is never touched.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: state-engine.mjs is the loop's own write path; an isolated
  branch keeps a broken intermediate engine out of the live loop.
- User decision: worktree (already decided and provisioned by the operator)
- Base ref: main
- Worktree branch/path: fix/issue-0007-list-append at /Users/ales/Projects/aai-fix-issue-0007
- Inline review scope: n/a (worktree chosen)

## Design decisions (resolved — do not reopen during implementation)

### D1 — Append matches the list's existing item indent
`appendListItems` derives the sibling indent from the FIRST existing `- ` item
line of the field's span; when the list is empty (`[]` inline form) or the field
is missing, it falls back to the engine convention key-indent+2. No other
call-site behavior changes; creation (`listFieldLines`) keeps writing
key-indent+2 items and stays internally consistent by construction.

### D2 — AC-002 as a structural list-indent lint, NOT a YAML parser
A full YAML parser is not available in the node stdlib and the repo ships no
dependencies (check-state.mjs's own "pure text scan" charter, SPEC-0010 Group
B). Instead check-state.mjs gains a whole-file structural lint: for every block
key whose first significant child is a `- ` item line, every subsequent direct
sibling `- ` item line of that block must share the indent of the first item;
a `- ` line indented strictly between the key and the first item is exactly the
corruption this issue describes and fails LOUD (exit 1, naming the key and line
number). Deeper `- ` lines under nested block keys are validated by their own
key's pass, so agent_runs / active_work_items shapes produce no false
positives. This catches exactly the ISSUE-0007 class without a YAML dependency.
The lint is detection-only (`--repair` does not rewrite list indents — the
engine fix prevents new occurrences; old corruption is a hand repair, as the
three sightings were).

### D3 — Dotfile keepers are protected from ephemeral cleanup
`cleanupEphemeral`'s `rm` guard additionally skips any basename starting with
`.` (dotfile keepers: `.gitkeep` placeholders are TRACKED files that gitignore
carve-outs depend on; the 2026-07-15 closeout saw the >7d sweep delete
docs/ai/tdd/.gitkeep). The PROTECTED hard constant stays as-is; the dotfile
rule is a second belt-and-braces guard inside `rm` so every sweep site
(tdd, reports, screenshots, ticks) is covered at once.

### D4 — STATE_FALLBACK.md ref_id parity
The hand-edit full-reset list gains `ref_id: null` in the last_validation line,
matching what `applyFullReset` (metrics-flush.mjs:415) already writes on the
primary path (SPEC-0019 deviation-3 follow-up). Doc-only; the code is already
correct.

## Acceptance Criteria Mapping
- Maps to: ISSUE-0007 AC-001
  - Spec-AC-01: appending to a populated list field yields a sibling at the
    identical indent of the existing items (first-item derivation, fallback
    key-indent+2); the resulting file passes a PyYAML round-trip.
  - Verification: tests/skills/test-aai-state.sh test_053 (RED on pre-fix
    engine, GREEN after) + python3 yaml.safe_load smoke inside the test.
- Maps to: ISSUE-0007 AC-002
  - Spec-AC-02: check-state.mjs fails loud (exit 1, names key + line) on a
    mis-indented list sibling anywhere in the file; uniform lists (2-space- and
    4-space-relative) and the real repo STATE keep exiting 0.
  - Verification: tests/skills/test-aai-check-state.sh test_list_indent_lint.
- Maps to: ISSUE-0007 AC-003
  - Spec-AC-03: regression stanzas covering code_review.report_paths appends
    and last_validation.evidence_paths writes on lists whose existing items sit
    at a nonstandard (4-space-relative) indent, plus byte-level assertion that
    the engine-convention append output is unchanged.
  - Verification: tests/skills/test-aai-state.sh test_054.
- Maps to: bundled nit (a)
  - Spec-AC-04: a >7-day-old docs/ai/tdd/.gitkeep survives the metrics-flush
    full-reset ephemeral cleanup (any dotfile keeper protected).
  - Verification: tests/skills/test-aai-metrics.sh test_012 extension.
- Maps to: bundled nit (b)
  - Spec-AC-05: .aai/STATE_FALLBACK.md's flush-reset last_validation line
    carries `ref_id: null` (parity with applyFullReset).
  - Verification: tests/skills/test-aai-metrics.sh test_015 (grep wiring test).
- Maps to: validation-ISSUE-0007-20260715T233312Z finding (remediation)
  - Spec-AC-06: `fieldSpan` includes a bare key's ZERO-relative-indent block
    sequence (items at the key's own column — legal YAML, the metrics suite's
    own fixture shape), so whole-field rewrites (setField / listFieldLines /
    nullFieldIfPresent, incl. the metrics-flush full/partial reset writing
    `report_paths: []` / `evidence_paths: []`) consume the whole span instead
    of orphaning the items; appends land at the existing 0-relative indent;
    and check-state.mjs fails loud (exit 1, names key + line) on the orphan
    shape (a `- ` item at the same indent as a key carrying an inline value,
    and a `- ` orphan at a bare key's own indent below a deeper list).
    2-/4-space-relative list behavior is byte-unchanged.
  - Verification: tests/skills/test-aai-state.sh test_055/test_056,
    tests/skills/test-aai-check-state.sh test_orphan_item_lint,
    tests/skills/test-aai-metrics.sh test_016 (the validator's exact probe-d
    repro).

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | append matches existing item indent; PyYAML round-trip | done   | docs/ai/tdd/red-issue-0007-test-001.log -> docs/ai/tdd/green-issue-0007-test-001.log | — | RED: unique indents "4 6"; GREEN: single 6-space indent + PyYAML OK |
| Spec-AC-02 | check-state structural list-indent lint fails loud     | done   | docs/ai/tdd/red-issue-0007-test-002.log -> docs/ai/tdd/green-issue-0007-test-002.log | — | RED: mis-indented sibling exited 0; GREEN: exit 1 naming key+line |
| Spec-AC-03 | report_paths/evidence_paths regression stanzas         | done   | docs/ai/tdd/red-issue-0007-test-003.log -> docs/ai/tdd/green-issue-0007-test-003.log | — | RED: PyYAML ParserError after deep-list append; GREEN: uniform + parseable, engine-convention bytes unchanged |
| Spec-AC-04 | dotfile keepers survive ephemeral cleanup              | done   | docs/ai/tdd/red-issue-0007-test-004-005.log -> docs/ai/tdd/green-issue-0007-test-004-005.log | — | RED: docs/ai/tdd/.gitkeep swept by >7d prune; GREEN: survives |
| Spec-AC-05 | STATE_FALLBACK ref_id: null parity line                | done   | docs/ai/tdd/red-issue-0007-test-005.log -> docs/ai/tdd/green-issue-0007-test-004-005.log | — | RED: fallback line lacked ref_id: null; GREEN: parity with applyFullReset |
| Spec-AC-06 | fieldSpan 0-relative-indent span + orphan-item lint (remediation) | done | docs/ai/tdd/red-issue-0007-rem-fieldspan.log + docs/ai/tdd/red-issue-0007-rem-tests.log -> docs/ai/tdd/green-issue-0007-rem-fieldspan.log | — | RED: full reset orphaned 0-relative items (PyYAML ParserError) while check-state exited 0; append on a 0-relative list inserted BEFORE the orphaned existing item. GREEN: whole span consumed, appends at existing indent, lint names key+line on both orphan shapes; 2-/4-relative bytes unchanged |

Status values: planned | implementing | done | deferred | blocked | rejected
- planned: AC defined, no implementation started
- implementing: work in flight; not allowed at PASS claim time
- done: implementation complete; requires non-empty Evidence (commit SHA or RUN_ID)
- deferred: explicitly postponed; requires Review-By (minimum +14 days) + Notes
- blocked: cannot proceed; requires Review-By + Notes naming blocker
- rejected: will not be implemented; requires Notes with rationale (terminal)

Gate behavior (enforced by .aai/VALIDATION.prompt.md when this column is present):
- Any planned/implementing AC blocks PASS
- Any done AC with empty Evidence blocks PASS
- Any deferred/blocked AC with Review-By in the past blocks any PASS until re-decided
- Review-By must be at least 14 days in the future when set

## Implementation plan
- .aai/scripts/lib/state-engine.mjs — `appendListItems`: derive item indent from
  the first existing `- ` line in the field span (D1).
- .aai/scripts/check-state.mjs — add `listIndentViolations(lines)` structural
  lint + wire into both the check and post-repair validation paths (D2).
- .aai/scripts/metrics-flush.mjs — `cleanupEphemeral` rm guard skips dotfile
  basenames (D3).
- .aai/STATE_FALLBACK.md — add `ref_id: null` to the last_validation flush-reset
  line (D4).
- Edge cases: empty inline `[]` list (fallback indent), field missing (created
  at engine convention), blank/comment lines inside blocks (span logic already
  handles), nested sequences under item keys (lint must not false-positive on
  agent_runs / active_work_items / metrics shapes).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                 | Description                                                          | Status  |
|----------|------------|------|--------------------------------------|----------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-state.sh (test_053_list_append_indent) | append to populated 4-space-relative list -> uniform siblings + PyYAML round-trip | green |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-check-state.sh (test_list_indent_lint) | mixed-indent sibling -> exit 1 naming key+line; uniform 2/4-relative lists + real STATE -> exit 0 | green |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-state.sh (test_054_list_append_regression) | report_paths + evidence_paths regression stanzas; engine-convention bytes unchanged | green |
| TEST-004 | Spec-AC-04 | int  | tests/skills/test-aai-metrics.sh (test_012_full_reset_cleanup) | >7d docs/ai/tdd/.gitkeep survives full-reset cleanup                 | green |
| TEST-005 | Spec-AC-05 | unit | tests/skills/test-aai-metrics.sh (test_015_fallback_ref_id_parity) | STATE_FALLBACK.md last_validation flush-reset line carries ref_id: null | green |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-state.sh (test_055_zero_relative_rewrite) | whole-field rewrite (set-validation --evidence, reset-block) over a 0-relative list consumes the whole span; 2-/4-relative bytes unchanged | green |
| TEST-007 | Spec-AC-06 | int  | tests/skills/test-aai-state.sh (test_056_zero_relative_append) | append to a 0-relative list lands at the existing item indent, after the existing items | green |
| TEST-008 | Spec-AC-06 | int  | tests/skills/test-aai-check-state.sh (test_orphan_item_lint) | orphaned `- ` item after an inline-valued key (and shallower orphan at a bare key's indent) -> exit 1 naming key+line; legal 0-relative lists -> exit 0 | green |
| TEST-009 | Spec-AC-06 | int  | tests/skills/test-aai-metrics.sh (test_016_zero_relative_full_reset) | validator probe-d repro: full reset over the suite's own 0-relative fixture leaves no orphans; PyYAML + check-state clean | green |

Test status values: pending -> red -> green.

## Remediation note (2026-07-16, validation-ISSUE-0007-20260715T233312Z)

The independent validation run of 2026-07-15 returned FAIL on a second,
pre-existing defect in the same fault class this SPEC targets, discovered via
its probe (d): `fieldSpan` (state-engine.mjs) computed a field's span with
strict `indentOf(l) > indent`, so a ZERO-relative-indent block sequence
(items at the key's own column — legal YAML, and exactly the shape the metrics
suite's own `write_flush_state` fixture emits for `report_paths` /
`evidence_paths`) was excluded from the span. Consequences (all reproduced,
RED evidence in docs/ai/tdd/red-issue-0007-rem-fieldspan.log and
red-issue-0007-rem-tests.log):

- Any whole-field rewrite over such a list (setField / listFieldLines /
  nullFieldIfPresent — e.g. the metrics-flush full/partial reset writing
  `report_paths: []`) truncated one line short and left the items ORPHANED
  below the replacement: invalid YAML (PyYAML `expected <block end>, but
  found '-'`).
- The D2 lint missed the corrupted output (its BLOCK_KEY_RE only matches bare
  `key:` lines; the orphan sits under `report_paths: []`, an inline value).
- The D1 append fix also mishandled 0-relative lists: the span excluded the
  existing items, so the appended sibling was inserted at key+2 BEFORE the
  (orphaned) existing item — also invalid YAML.

Fix (Spec-AC-06, delivered in this worktree on 2026-07-16):

- `fieldSpan` now includes trailing `- ` item lines whose indent EQUALS the
  key's indent when the key line is BARE (no inline value) — per YAML that
  sequence IS the key's value. A sibling key at equal indent still terminates
  the span (keys never start with `- `); an equal-indent item can never belong
  to a parent structure there (a parent sequence's dash column is always >= 2
  left of the keys of the mapping it contains), and keys carrying an inline
  value (incl. `>-`/`|` headers) keep the old strict-`>` behavior — all argued
  in the function's comment. This transitively fixes setField,
  listFieldLines-based rewrites, nullFieldIfPresent, --clear, reset-block,
  metrics-flush resets, and makes appendListItems reuse the 0-relative indent.
- check-state.mjs gains `orphanItemViolations` (a `- ` item at the same indent
  as a key that carries an inline value = orphan, exit 1 naming key + line)
  and the existing `listIndentViolations` scan now also flags a `- ` orphan at
  a bare key's own indent below a deeper-indented list (the mid-rewrite
  corruption shape) instead of silently ending the block scan there.
- 2-/4-space-relative behavior byte-unchanged (test_055(c) byte-diffs; the
  pre-existing test_053/054 stanzas re-ran green untouched).

Per SPEC-0012, this remediation records no verdict: last_validation was reset
to not_run and a fresh independent validation follows.

## Verification
- bash tests/skills/test-aai-state.sh — exit 0 (56 tests incl. new 053/054 and
  remediation 055/056), 2026-07-16
- bash tests/skills/test-aai-check-state.sh — exit 0 (incl.
  test_list_indent_lint + remediation test_orphan_item_lint)
- bash tests/skills/test-aai-metrics.sh — exit 0 (incl. test_012 keeper asserts
  + test_015 + remediation test_016)
- Full sweep (all exit 0, 2026-07-16): dispatch suite, docs-audit suite,
  doc-numbering suite, hygiene pack, check-state on the (seeded) worktree
  STATE, repo `docs-audit --check --strict --no-event` Verdict: CLEAN,
  `generate-docs-index.mjs` idempotent (byte-identical modulo the Generated
  timestamp line).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal. Met at the
  implementation gate; independent validation verdict pending (status:
  implementing).

## Evidence contract
Per artifact record: ref_id (ISSUE-0007), Spec-AC/TEST links, command, exit
code, evidence path (docs/ai/tdd/red-*.log / green-*.log), commit SHA or diff
range when available.

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Review disposition (2026-07-16, dual-verdict review)

- NON-BLOCKING-1 (orphan lint misses a deep orphan under an INLINE-valued key
  — third corruption shape, not engine-producible): ACCEPTED as a documented
  detection boundary (decisions.jsonl entry); lint extension deferred until a
  real-world sighting. cannot_verify items tracked: post-merge check-state
  sweep over main's live + archived STATEs (orchestrator errand), token
  accounting (CHANGE-0010 scope).

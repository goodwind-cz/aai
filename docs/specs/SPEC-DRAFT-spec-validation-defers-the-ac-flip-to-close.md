---
id: spec-validation-defers-the-ac-flip-to-close
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: validation-defers-the-ac-flip-to-close
  rfc: null
  pr: []
  commits: []
---

# Spec — the AC flip belongs to the close, and the canon says so at both ends

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-validation-defers-the-ac-flip-to-close.md
- Decision records: none new (design decisions recorded in this spec)
- Technology contract: docs/TECHNOLOGY.md

## Problem in one paragraph

`.aai/VALIDATION.prompt.md` step 8a presumes the validator populates the
spec's AC Evidence column ("Evidence column populated"), which manufactures
exactly the state `docs-audit`'s probable-false-open heuristic correctly
flags: a fully terminal, evidenced AC table under a still-open frontmatter
`status`. Four rides carried the fix as hand-written dispatch prose ("do NOT
populate the Evidence column; the flip happens immediately before the
close") — the measured anti-pattern of CHANGE-0159. This scope makes the
deferral the canon at both ends: validation records per-AC evidence in its
report and never flips a still-open doc's table; the flip to terminal is a
named close-ceremony step ordered immediately before `close-work-item.mjs`.
The heuristic, the close gate, and TEST-013 stay byte-identical.

## Implementation strategy
- Strategy: direct
- Rationale: the deliverables are prompt prose at two ends plus one grep-pin
  test arm. Evidence is grep-level presence/ordering probes, a mutation bite
  proof with an unmutated control in a disposable clone, and the governed
  suites staying green — there is no new module to grow a RED-first cycle
  around.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: prose edits to two prompt files plus one test arm on a
  dedicated branch; mutation proofs run in a disposable detached worktree
  clone, never in the shipping tree.
- User decision: inline (branch docs/ac-flip-belongs-to-close, base main at 528d1d6)
- Base ref: main
- Inline review scope: .aai/VALIDATION.prompt.md, .aai/SKILL_PR.prompt.md,
  tests/skills/test-aai-close-work-item.sh,
  docs/specs/SPEC-DRAFT-spec-validation-defers-the-ac-flip-to-close.md,
  docs/issues/CHANGE-DRAFT-validation-defers-the-ac-flip-to-close.md, and
  tests/skills/lib/prompt-diet-ledger.sh plus
  tests/skills/test-aai-prompt-diet.sh only if the corpus byte floor
  requires a ledger entry at the measured delta.

## Design decisions

- D1 (one statement, not rule+exception): step 8a is rewritten as a single
  named rule — AC-FLIP DEFERRAL — that owns the AC-row flip, the Evidence
  column, and the `ac_evidence` emission on a still-open doc. The old
  standalone `EXCEPTION:` paragraph (which deferred only the event, not the
  column state that trips the heuristic) is absorbed and disappears.
- D2 (gate-timing coherence, instruction not guard): with rows deliberately
  left non-terminal until close, the AC STATUS GATE's mechanical Rule-1
  check against the focus doc's own rows can no longer clear at validation
  time. The deferral statement names the consequence: reconciliation of the
  focus doc's table lands at the close gate (step 8b / SKILL_PR 5c), where
  the flip has just happened; every other gate rule (Rule 2 on flipped
  tables, Rule 3 repo-wide overdue, Rule 4 anti-cheat, other specs' tables)
  binds unchanged. `docs-audit.mjs`, its `--gate`, the heuristic, and
  TEST-013 are not edited — only the prompt instruction moves.
- D3 (close-side home): the close ceremony is specified in
  `.aai/SKILL_PR.prompt.md` step 5c, so the flip gets its home there as an
  explicitly ordered sub-step BEFORE the `close-work-item.mjs` invocation,
  sourcing Evidence cells from the validation report. The close gate
  invocation stays owned by VALIDATION step 8b — no rule sentence is
  duplicated across the two files (spec-subagent-protocol-slim TEST-002
  discipline).
- D4 (arm placement): the pin lives in
  tests/skills/test-aai-close-work-item.sh (the canon-wiring suite for the
  close ceremony, whose suite-map globs already select on both
  .aai/VALIDATION.prompt.md and .aai/SKILL_PR.prompt.md), wired into main()
  so check-test-registration passes. No new suite file, so no suite-map row
  and no PROFILES change is needed.

## Acceptance Criteria Mapping

- Maps to: AC-001
- Spec-AC-01: .aai/VALIDATION.prompt.md step 8a SHALL state the deferral as
  the rule: on a still-open doc (frontmatter `status` `draft`/`implementing`)
  validation MUST NOT flip AC rows terminal or populate the Evidence column;
  per-AC evidence goes in the validation report; the flip happens at the
  close step. The old event-EXCEPTION SHALL be folded into that single
  statement (the literal standalone `EXCEPTION:` paragraph is gone).
- Verification: read the 8a block; /usr/bin/grep -c "AC-FLIP DEFERRAL"
  .aai/VALIDATION.prompt.md returns 1 or more and /usr/bin/grep -c
  "EXCEPTION:" .aai/VALIDATION.prompt.md returns 0.

- Maps to: AC-002
- Spec-AC-02: .aai/SKILL_PR.prompt.md step 5c SHALL name the AC-table flip
  as its own step ordered before the `close-work-item.mjs` invocation, with
  Evidence cells sourced from the validation report.
- Verification: the first line matching "FLIP THE AC TABLE" in
  .aai/SKILL_PR.prompt.md precedes the first line matching
  "close-work-item.mjs --ref" (line-number comparison).

- Maps to: AC-003
- Spec-AC-03: Prompt-corpus governance SHALL hold, measured: the byte delta
  of the corpus is measured before and after; a JUSTIFIED_ADDITIONS ledger
  entry is added at the measured delta only if TEST-010's headroom would
  otherwise go negative (no padded credit); TEST-010 and TEST-012 are green;
  no rule sentence of the new canon is duplicated verbatim across
  .aai/VALIDATION.prompt.md and .aai/SKILL_PR.prompt.md.
- Verification: bash tests/skills/test-aai-prompt-diet.sh exits 0; recorded
  before/after `cat .aai/*.prompt.md | wc -c` numbers in the result
  evidence; a grep for the new rule's marker phrases shows each lives in
  exactly one prompt file.

- Maps to: AC-004
- Spec-AC-04: A test arm SHALL pin the deferral rule at both ends so that
  deleting either end's rule text makes the suite fail; the arm asserts
  content and ordering, not a prose count. Proven by mutation in a
  disposable clone with an unmutated control run.
- Verification: bash tests/skills/test-aai-close-work-item.sh passes on the
  unmutated tree (control); in a detached-worktree clone with the 8a rule
  text removed the suite fails; in a second clone with the 5c flip step
  removed (or reordered after the close invocation) the suite fails.

- Maps to: AC-005
- Spec-AC-05: The probable-false-open heuristic, the close gate, and
  TEST-013 SHALL be untouched: no diff under .aai/scripts/docs-audit.mjs,
  .aai/scripts/lib/, .aai/scripts/close-work-item.mjs, or
  tests/skills/test-aai-doc-numbering.sh.
- Verification: git diff main --name-only contains none of those paths;
  bash tests/skills/test-aai-doc-numbering.sh exits 0.

## Constitution deviations

None.

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                    | Status      | Evidence       | Review-By   | Notes                          |
|------------|--------------------------------|-------------|----------------|-------------|--------------------------------|
| Spec-AC-01 | VALIDATION 8a states the deferral as the rule, event-EXCEPTION folded in | done | DONE c3d9f7d: 8a is one named AC-FLIP DEFERRAL rule absorbing the old EXCEPTION (grep EXCEPTION count 0). Round 1 FAILED as the rule's first live user — the gate's blocking sentence contradicted it — and the MECHANICAL CHECKS carve is now operational: a Rule-1-only exit on a still-open doc is the EXPECTED state; round 2 verified the boundary with three mixed-reason cases, all blocking | — | evidence in the implementation report per this very rule |
| Spec-AC-02 | SKILL_PR 5c names the flip as its own step ordered before close-work-item.mjs | done | DONE: SKILL_PR step 5c FLIP THE AC TABLE FIRST, ordered before close-work-item.mjs; test_050 asserts the ordering by line numbers and its reorder mutation bites | — | — |
| Spec-AC-03 | corpus governance measured: delta recorded, ledger only if owed, TEST-010/012 green, no cross-file duplication | done | DONE, measured twice independently: +815 B then +177 B for the carve; first breach of the corpus cap, paid 1:1 at the measured deficit; TEST-010 headroom 0/2048, TEST-012 pin 859 to 1036 with history, messages interpolate the constant after round 2 caught the second drift of that exact message | — | — |
| Spec-AC-04 | arm pins the rule at both ends; bite proven by mutation with unmutated control | done | DONE: test_050_ac_flip_deferral_canon; three mutations bite (each end's rule text, the ordering), unmutated control green; re-proved independently by round 2 and by review with an un-piped exit code | — | mutations in disposable worktree clones only |
| Spec-AC-05 | heuristic, close gate, TEST-013 untouched; doc-numbering green | done | DONE: git diff main over docs-audit.mjs, lib/, close-work-item.mjs and the doc-numbering suite is empty; doc-numbering 31/31 | — | — |

## Implementation plan
- .aai/VALIDATION.prompt.md: rewrite step 8a as the AC-FLIP DEFERRAL rule
  (D1, D2); every string pinned by existing suites (close-work-item t009,
  docs-audit TEST-005/TEST-010/pdci TEST-003, ceremony-levels, friction
  TEST-009) survives.
- .aai/SKILL_PR.prompt.md: add the "FLIP THE AC TABLE FIRST" sub-step at the
  top of step 5c (D3).
- tests/skills/test-aai-close-work-item.sh: add
  test_050_ac_flip_deferral_canon (D4) — greps AC-FLIP DEFERRAL + absence of
  standalone EXCEPTION in VALIDATION.prompt.md; asserts the SKILL_PR flip
  line number precedes the close-work-item.mjs invocation line number (awk,
  no pipes, bash-3.2 safe).
- Measure corpus bytes before/after; ledger entry only if headroom would go
  negative (measured before state: reduction 29624, headroom 952/2048,
  credit 859).
- Edge cases: already-`done` docs (re-validation) still emit `ac_evidence`
  directly at 8a; numbered-but-open docs get no special carve-out any more —
  the deferral covers every still-open doc, which is strictly safer than the
  old slug-only exception.

## Test Plan

| Test ID  | Spec-AC    | Type       | File path (expected)       | Description                  | Status  |
|----------|------------|------------|----------------------------|------------------------------|---------|
| TEST-001 | Spec-AC-01 | int | tests/skills/test-aai-close-work-item.sh | test_050: VALIDATION 8a carries AC-FLIP DEFERRAL, standalone EXCEPTION gone | pending |
| TEST-002 | Spec-AC-02 | int | tests/skills/test-aai-close-work-item.sh | test_050: SKILL_PR flip step exists and precedes close-work-item.mjs --ref | pending |
| TEST-003 | Spec-AC-03 | int | tests/skills/test-aai-prompt-diet.sh | TEST-010 headroom in range and TEST-012 pin holds after the edits | pending |
| TEST-004 | Spec-AC-04 | int | tests/skills/test-aai-close-work-item.sh | mutation in disposable clone: deleting either end's rule text turns the suite red; unmutated control green | pending |
| TEST-005 | Spec-AC-05 | int | tests/skills/test-aai-doc-numbering.sh | guard paths diff-clean and doc-numbering suite green | pending |

## Verification
- bash tests/skills/test-aai-close-work-item.sh (control, plus mutated
  clones for TEST-004)
- bash tests/skills/test-aai-prompt-diet.sh
- bash tests/skills/test-aai-doc-numbering.sh
- node .aai/scripts/select-suites.mjs --files-from <changed paths>; run what
  it returns
- node .aai/scripts/check-test-registration.mjs
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal at close (per
  the very rule this spec ships, the table flips at the close step)

## Evidence contract
Per artifact: ref_id, Spec-AC/TEST links, command or review scope, exit
code, evidence path, commit SHA when available. Strategy `direct`: targeted
regression tests green (exit codes) plus the scoped diff — no stored RED
artifact demanded.

---
id: spec-learned-append-gate
type: spec
number: 95
status: implementing
ceremony_level: 2
links:
  requirement: CHANGE-0069-learned-append-gate
  rfc: null
  pr: []
  commits: []
---

# SPEC — Learned-append gate: structurally enforced append-only self-learning

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0069-learned-append-gate.md
- House format reference: docs/knowledge/LEARNED.md (header comment)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: the entire deliverable's value is a structural REJECTION guarantee
  (a rewrite/reorder/mid-insert/deletion attempt must fail closed with nothing
  written). A test suite that never observed that rejection fail is a
  tautology — TDD forces the RED (mutation accepted, or script absent) before
  the GREEN (mutation rejected, tree byte-identical). Low mechanical risk
  otherwise (single new zero-dependency script + pointer-thin wiring).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single new script, one test suite, and pointer-thin
  edits to two existing prompt/system docs plus PROFILES.yaml — small,
  reversible, already isolated on branch feat/learned-append-gate. No
  protected_paths_l3 surface touched.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/learned-append.mjs (new), tests/skills/test-aai-learned-append.sh (new), .aai/SKILL_WRAP_UP.prompt.md (step 3 gate wiring + step 6 pointer), .aai/system/FRICTION_PROTOCOL.md (new pointer section), .aai/system/PROFILES.yaml (one classification line), tests/skills/lib/prompt-diet-ledger.sh (JUSTIFIED_ADDITIONS entry), docs/product/learned-append-gate.md (new), docs/issues/CHANGE-0069-learned-append-gate.md (user_visible flag)

## Acceptance Criteria Mapping
- Spec-AC-01 (maps CHANGE AC-001): rule-text mode — given rule text and a
  `--source`, the script appends a house-format bullet
  (`- [YYYY-MM-DD] <text> (source: <source>)`) at the true end of the target
  file (or under a brand-new `--section` heading, also at end of file), exits
  0, and the resulting file is byte-exactly the original plus that bullet.
  Verification: TEST-001..003.
- Spec-AC-02 (AC-002): any candidate that is not byte-exactly original-plus-
  suffix is rejected — covering all four named transformation classes
  (rewrite, reorder, mid-insert, deletion) — exit 1, a diff summary on
  stderr, and the on-disk target file unchanged (same bytes before and
  after the call). Verification: TEST-004..007.
- Spec-AC-03 (AC-003): `--dry-run` prints the would-be appended text (or a
  no-op notice) and never writes, on BOTH an accept-shaped and a
  reject-shaped candidate (dry-run never bypasses the gate). Verification:
  TEST-008..009.
- Spec-AC-04 (AC-004): the wrap-up flow never edits LEARNED.md directly —
  `.aai/SKILL_WRAP_UP.prompt.md` step 3 routes a confirmed rule through a
  compact critic review and then the exact gate-script invocation, step 6
  carries a one-line cross-reference back to that flow, and
  `.aai/system/FRICTION_PROTOCOL.md` carries a one-line pointer to the gate.
  `.aai/system/PROFILES.yaml` classifies the new script (core). Any measured
  growth of the live `.aai/*.prompt.md` corpus is trued up in the prompt-diet
  ledger. Verification: TEST-013..016 (grep contracts + companion suites).
- Spec-AC-05 (AC-005): no regression — the new suite plus
  test-aai-friction-wiring.sh plus test-aai-hygiene-pack.sh are green
  locally. Verification: TEST-017.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                | Status | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | Rule-text mode pure append accepted and house-stamped        | done   | docs/ai/tdd/green-20260727T105431Z-learned-append.log | — | GREEN |
| Spec-AC-02 | Rewrite, reorder, mid-insert, deletion all rejected, tree unchanged | done | docs/ai/tdd/green-20260727T105431Z-learned-append.log | — | GREEN |
| Spec-AC-03 | Dry-run prints the would-be append, never writes             | done   | docs/ai/tdd/green-20260727T105431Z-learned-append.log | — | GREEN |
| Spec-AC-04 | Critic-then-gate wiring plus ledger and PROFILES true-up      | done   | docs/ai/tdd/green-20260727T105431Z-learned-append.log | — | GREEN |
| Spec-AC-05 | No regression across companion suites                        | done   | docs/ai/tdd/green-20260727T105431Z-learned-append.log | — | GREEN |

## Implementation plan
- Components affected:
  - `.aai/scripts/learned-append.mjs` (new) — the gate. Two modes: rule-text
    (default; formats and appends a house bullet) and `--full` (generic
    structural verifier for an already-assembled candidate document, the only
    way to exercise rewrite/reorder/deletion transformation classes since
    rule-text mode can only ever insert new bytes). Both modes funnel through
    one `isPureAppend(original, candidate)` check; construction never bypasses
    it (the mid-insert case is deliberately constructed rather than
    special-cased, so the same generic gate proves it rejects mid-file work).
  - `.aai/SKILL_WRAP_UP.prompt.md` step 3 "PROPOSE NEW LEARNED RULES" — the
    only place this repo's own wrap-up flow writes LEARNED.md today (a
    hand-edit after per-rule user confirmation). Replaced with: confirm ->
    compact critic pass (reuse the existing review-subagent convention, no
    new role) -> invoke the gate script; direct edits are no longer
    sanctioned. Step 6 "FRICTION FEEDBACK NUDGE" gets one cross-reference
    sentence (a future triage-surfaced rule proposal routes through the same
    step-3 flow) — no behavior change there, so no new grep contract beyond
    the sentence itself.
  - `.aai/system/FRICTION_PROTOCOL.md` — one new trailing `## ` section
    (co-located pointer only; system/, not prompt corpus, no ledger cost).
    Placed AFTER the existing "## Skill wiring (shadow capture)" section so
    it stays outside that section's own extraction boundary in the existing
    friction-wiring suite (which stops at the first following `## `).
  - `.aai/system/PROFILES.yaml` — one new `core` entry for the script.
  - `tests/skills/test-aai-learned-append.sh` (new) — house-style suite.
  - `tests/skills/lib/prompt-diet-ledger.sh` — one new `JUSTIFIED_ADDITIONS`
    entry sized to the measured `.aai/*.prompt.md` corpus growth from the
    step 3/6 edits (FRICTION_PROTOCOL.md growth is free, system/ not corpus).
  - `docs/product/learned-append-gate.md` (new) — required because
    `docs/issues/CHANGE-0069-learned-append-gate.md` gets `user_visible: true`.
- Data flow: no runtime data flow beyond a single whole-file read plus an
  atomic temp-write-then-rename on accept; nothing is read-modify-write
  across processes (single invocation, single writer per call).
- Edge cases: empty/no-op candidate (identical to current file) accepted as a
  degenerate zero-byte append; missing target file, conflicting/missing input
  sources, and `--full` combined with `--source`/`--section` are usage errors
  (exit 2, nothing written, distinct from a structural rejection).

## Seam analysis (6a)
- SEAM 1 (prompt prose -> real CLI contract): `.aai/SKILL_WRAP_UP.prompt.md`
  documents an exact invocation of a script owned elsewhere. A prose-only
  assertion would pass even if the documented flags drifted from the real
  CLI. TEST-013 greps the exact flag names the script actually implements
  (`--source`, `learned-append.mjs`) so the two cannot silently diverge.
- SEAM 2 (new `.aai/**` file -> PROFILES.yaml classification, shared with
  every other AAI file): TEST-015 runs the real
  `tests/skills/test-aai-layer-profiles.sh` end-to-end rather than asserting
  the classification line exists in isolation — that suite is the actual
  100%-covered-tree authority this change must not break.
- SEAM 3 (prompt-corpus byte accounting, shared by every prompt-touching
  scope): TEST-016 runs the real `tests/skills/test-aai-prompt-diet.sh`
  end-to-end so the ledger true-up is proven against the live corpus, not a
  hand-computed number that could drift from the actual bytes added.
- Residual risk: this spec does not prove a human or agent actually ROUTES a
  real session's confirmed rule through the critic step before calling the
  gate (that discipline lives in the prompt text, not in code) — the gate
  only guarantees that IF the script is the write path, the result is
  append-only. Recorded explicitly, consistent with the CHANGE doc's own
  framing ("a guardrail, not a security boundary").

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                                    | Status |
|----------|------------|-------------|-------------------------------------------|--------------------------------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-learned-append.sh   | Pure append, no --section: file grows by exactly the stamped bullet, exit 0                      | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-learned-append.sh   | --section naming the file's current LAST heading behaves identically to no --section              | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-learned-append.sh   | --section naming a brand-new heading creates heading and bullet at end of file, exit 0            | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-learned-append.sh   | --full mode rewrite (one existing byte changed) rejected exit 1, tree byte-identical              | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-learned-append.sh   | --full mode reorder (two existing section blocks swapped) rejected exit 1, tree byte-identical    | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-learned-append.sh   | Rule-text mode mid-insert (--section names an existing, non-last heading) rejected, tree unchanged | green |
| TEST-007 | Spec-AC-02 | integration | tests/skills/test-aai-learned-append.sh   | --full mode deletion (an existing line removed) rejected exit 1, tree byte-identical               | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-learned-append.sh   | --dry-run on an accept-shaped input prints the would-be append, file byte-identical to before      | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/test-aai-learned-append.sh   | --dry-run on a reject-shaped input still exits 1 (dry-run never bypasses the gate)                 | green |
| TEST-010 | Spec-AC-01 | unit        | tests/skills/test-aai-learned-append.sh   | Negative control: missing --source, conflicting --text plus --file, missing --target all exit 2, nothing written | green |
| TEST-011 | Spec-AC-01 | integration | tests/skills/test-aai-learned-append.sh   | Two sequential real appends onto the same file each succeed; the second builds on the first's on-disk result | green |
| TEST-012 | Spec-AC-01 | unit        | tests/skills/test-aai-learned-append.sh   | --full mode candidate identical to the current file is accepted as a zero-byte no-op, exit 0       | green |
| TEST-013 | Spec-AC-04 | unit        | tests/skills/test-aai-learned-append.sh   | SKILL_WRAP_UP.prompt.md step 3 names the critic-then-gate flow and the exact script invocation      | green |
| TEST-014 | Spec-AC-04 | unit        | tests/skills/test-aai-learned-append.sh   | FRICTION_PROTOCOL.md carries a one-line pointer naming the gate script                             | green |
| TEST-015 | Spec-AC-04 | integration | tests/skills/test-aai-layer-profiles.sh   | PROFILES.yaml classifies the new script under core; the real layer-profiles suite stays green      | green |
| TEST-016 | Spec-AC-04 | integration | tests/skills/test-aai-prompt-diet.sh      | Prompt-diet ledger trued up: the real prompt-diet suite (TEST-012 checkpoint) stays green          | green |
| TEST-017 | Spec-AC-05 | integration | tests/skills/test-aai-friction-wiring.sh, tests/skills/test-aai-hygiene-pack.sh | Companion suites still green after the SKILL_WRAP_UP and FRICTION_PROTOCOL edits | green |

RED-proof obligation: TEST-001..014 and TEST-017 were written first and
observed FAILING against the pre-change tree (script absent for
TEST-001..012; the wiring/pointer text absent for TEST-013/014; TEST-017's
companion suites were run unaffected as a baseline, not re-proven RED, since
they test pre-existing surfaces this change only extends). TEST-015/016 were
RED against the pre-change tree (script not yet classified; corpus growth not
yet trued up).

Fixture diversity checklist (SPEC-0013 H7), mapped:
- degenerate/empty: TEST-012 (zero-byte no-op candidate).
- fully-covered/zero-remainder: TEST-012 (nothing left to append).
- multi-source/multi-writer: TEST-011 (two sequential real appends).
- mid-operation failure: TEST-004..007 (a rejected candidate leaves nothing
  partially written — asserted via tree byte-identity, not just exit code).
- negative control: TEST-010 (usage errors) and TEST-009 (dry-run does not
  bypass the gate).

## Verification
- `bash tests/skills/test-aai-learned-append.sh` (new suite green)
- `bash tests/skills/test-aai-friction-wiring.sh` (companion, green)
- `bash tests/skills/test-aai-hygiene-pack.sh` (companion, green)
- `bash tests/skills/test-aai-layer-profiles.sh` (classification, green)
- `bash tests/skills/test-aai-prompt-diet.sh` (ledger true-up, green)
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0095-spec-learned-append-gate.md` (report-only)
- `node .aai/scripts/docs-audit.mjs --check` (repo-wide, no hard fail)
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal (done with evidence)

## Evidence contract
For each implementation, TDD, validation, and code review artifact record:
- ref_id: learned-append-gate
- Spec-AC and TEST-xxx links
- command or review scope
- exit code or review verdict
- evidence path (docs/ai/tdd/*.log, run logs)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

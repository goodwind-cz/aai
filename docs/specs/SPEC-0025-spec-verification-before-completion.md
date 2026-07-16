---
id: spec-verification-before-completion
type: spec
number: 25
status: done
links:
  change: verification-before-completion
  research: RES-0001
  pr:
    - 68
  commits:
    - 05f9208
---

# SPEC — Verification-Before-Completion Gate Skill

SPEC-FROZEN: true

## Links
- Change: verification-before-completion
  (docs/issues/CHANGE-0016-verification-before-completion.md, AC-001..AC-003)
- Research: RES-0001 P2 recommendation 7a — Superpowers
  verification-before-completion pattern (Iron Law, gate function,
  rationalization table, verify-subagent-reports-via-VCS-diff) —
  docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md (F1)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: prompt-text and wrapper work with deterministic grep-based
  verification. Every gating test is a grep/wc stanza that is trivially
  RED-provable by running the new suite once on the pre-change tree (the
  target file does not exist yet, wiring markers absent). RED-GREEN-REFACTOR
  per test adds no signal over one focused pass plus a recorded pre-change
  failing run.
- RED-proof obligation: before any edit, run
  `bash tests/skills/test-aai-verify-gate.sh` on the pre-change tree and save
  the failing output to `docs/ai/tdd/verify-gate-red.log` (expected: TEST-001,
  TEST-002, TEST-003, TEST-004, TEST-005, TEST-007 FAIL; TEST-006 and TEST-008
  pass pre-change by construction — they guard invariants that must SURVIVE
  the change, and are non-vacuous because TEST-006 re-measures the byte
  formula after the corpus grows and TEST-008 re-audits the repo after new
  docs land).

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive new prompt file + wrapper files + one new test
  suite; the only edits to existing files are a 6-to-2-line replacement in
  IMPLEMENTATION and two ≤2-line insertions (VALIDATION, SKILL_TDD) plus one
  catalog row each in SKILLS.md and .aai/AGENTS.md. No state/schema/script
  changes, no migrations, single scope, trivially revertible. Isolation is
  useful (protected workflow prompts are touched) but not important for
  safety. Recommendation `optional` does not gate implementation on a user
  decision.
- User decision: undecided
- Base ref: main (HEAD 0cadd9f at freeze time)
- Worktree branch/path: n/a unless the user opts in
- Inline review scope (explicit paths):
  - .aai/SKILL_VERIFY.prompt.md (new)
  - .aai/IMPLEMENTATION.prompt.md
  - .aai/VALIDATION.prompt.md
  - .aai/SKILL_TDD.prompt.md
  - .claude/skills/aai-verify/SKILL.md (new)
  - .codex/skills/aai-verify/SKILL.md (new)
  - .gemini/skills/aai-verify/SKILL.md (new)
  - tests/skills/test-aai-verify-gate.sh (new)
  - SKILLS.md
  - .aai/AGENTS.md
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — New gate prompt `.aai/SKILL_VERIFY.prompt.md` (≤120 lines)
Compact, self-contained gate. Required content:
1. Iron Law: NO COMPLETION CLAIM WITHOUT FRESH VERIFICATION EVIDENCE FROM THE
   CURRENT TREE STATE. "Fresh" = produced after the last edit to any file in
   scope; evidence from before the latest change is void.
2. Gate function, exactly this chain and order:
   IDENTIFY → RUN → READ → VERIFY → CLAIM
   - IDENTIFY the specific claim about to be made (which test/build/behavior).
   - RUN the command that can falsify it (via .aai/scripts/aai-run-tests.sh
     for test suites, per LEARNED rule).
   - READ the full output, not just the exit code banner.
   - VERIFY the output actually matches the claim (right suite, right tree,
     zero exit, no skipped-as-passed).
   - Only then CLAIM — with command, exit code, and evidence path.
3. Rationalization table with ≥6 concrete entries naming the dodge and the
   counter. Minimum set: "tests passed earlier this session"; "I only changed
   docs/comments"; "the subagent reported success"; "the diff looks right, no
   need to run it"; "I ran part of the suite, the rest can't be affected";
   "exit code was 0, no need to read the output" (plus any further entries;
   6 is the floor, not the target).
4. Verify-subagent-reports-via-diff rule: a subagent's self-reported
   completion is a claim, not evidence. Before accepting it, inspect the real
   tree state (`git status --porcelain`, `git diff`) to confirm the reported
   files actually changed as described, then re-run the gating check in the
   accepting context.
5. Applicability line: this gate binds every completion boundary —
   Implementation hand-off, TDD GREEN/completion claims, Validation verdicts.

### D2 — Wiring references (≤2 lines each; prompt-diet safe)
- `.aai/IMPLEMENTATION.prompt.md`: REPLACE the existing 6-line
  "VERIFICATION-BEFORE-COMPLETION RULE" block (its body moves into
  SKILL_VERIFY) with a ≤2-line pointer to `.aai/SKILL_VERIFY.prompt.md`
  (net negative bytes). The old block's marker line "Forbidden language in
  completion reports" must no longer appear in IMPLEMENTATION.
- `.aai/VALIDATION.prompt.md`: ≤2-line pointer at the verdict step (PROCESS
  step 8 area): apply the SKILL_VERIFY gate before producing PASS/FAIL.
- `.aai/SKILL_TDD.prompt.md`: ≤2-line pointer at the completion boundary
  (Phase 4 validation/hand-off area): no completion claim without the
  SKILL_VERIFY gate.
- "≤2 lines" is measured as: number of lines containing the literal
  `SKILL_VERIFY` in each file is ≥1 and ≤2.
- Byte budget (measured 2026-07-16, pre-change): prompt-diet TEST-010 floor
  is a net reduction ≥28,672 bytes vs baseline 357,457; current measured
  reduction is 51,248 bytes → headroom 22,576 bytes. SKILL_VERIFY at ≤120
  lines is ≤~7 KB and the wiring is net ~0; post-change reduction stays over
  the floor with ≥15 KB margin. TEST-006 re-asserts this by re-measurement.

### D3 — Wrappers in the three agent trees
New `aai-verify` wrapper SKILL.md in `.claude/skills/`, `.codex/skills/`,
`.gemini/skills/`, following the existing pointer convention (frontmatter
`name` + `description`; body: "Read the file `.aai/SKILL_VERIFY.prompt.md`
... follow its instructions exactly", plus the not-found fallback line).
No `model:` pin — the gate runs in whatever model the claiming role runs.
Catalog wiring: one row in SKILLS.md Quick Reference; one
`Follow .aai/SKILL_VERIFY.prompt.md` line in .aai/AGENTS.md (neither file
counts toward the prompt-diet corpus).

### D4 — Grep test suite `tests/skills/test-aai-verify-gate.sh`
New bash-3.2-compatible suite (exit 0 pass / 1 fail / 42 skip), same shape as
tests/skills/test-aai-prompt-diet.sh. Discovered automatically by the
tests/skills runner. Out of scope: any script/enforcement machinery and
REMEDIATION changes (per CHANGE draft).

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/SKILL_VERIFY.prompt.md` exists, is ≤120 lines, contains
    the literal ordered chain `IDENTIFY → RUN → READ → VERIFY → CLAIM`, a
    rationalization table with ≥6 data rows, and the
    verify-subagent-reports-via-diff rule (names both `git diff` and
    subagent reports).
  - Verification: TEST-001..TEST-004 stanzas in
    tests/skills/test-aai-verify-gate.sh; expected exit 0 with PASS lines.
- Maps to: CHANGE AC-002
  - Spec-AC-02: IMPLEMENTATION, VALIDATION and SKILL_TDD each reference
    `SKILL_VERIFY` on ≥1 and ≤2 lines; IMPLEMENTATION's old 6-line rule body
    is removed (marker absent); prompt-diet net byte reduction stays ≥28,672
    bytes (TEST-010 formula re-measured).
  - Verification: TEST-005, TEST-006 stanzas; plus full
    tests/skills/test-aai-prompt-diet.sh green at validation.
- Maps to: CHANGE AC-003
  - Spec-AC-03: `aai-verify/SKILL.md` exists in all three agent trees, each
    with `name: aai-verify` frontmatter and a pointer to
    `.aai/SKILL_VERIFY.prompt.md`; repo-wide strict docs audit exits 0; all
    tests/skills suites green (validation-owned full run).
  - Verification: TEST-007, TEST-008 stanzas; full suite run + repo audit at
    validation.

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Gate prompt ≤120 lines with chain + table + diff rule  | done    | TEST-001..004 green; docs/ai/tdd/verify-gate-green.log | —         | .aai/SKILL_VERIFY.prompt.md, 71 lines |
| Spec-AC-02 | ≤2-line wiring x3 prompts; diet floor holds            | done    | TEST-005/006 green; docs/ai/tdd/verify-gate-green.log; prompt-diet net reduction 47668 bytes (floor 28672) | —         | old 6-line rule replaced by 2-line pointer in IMPLEMENTATION (move, not loss) |
| Spec-AC-03 | Wrappers x3 trees; strict audit CLEAN; suites green    | done    | TEST-007/008 green; docs/ai/tdd/verify-gate-green.log; docs-audit --check --strict --no-event exit 0; full tests/skills sweep green modulo pre-existing test-aai-pricing.sh/test-aai-worktree.sh (reproduced identically on clean main) | —         | wrappers in .claude/.codex/.gemini/skills/aai-verify/SKILL.md |

## Implementation plan
- Components affected: prompt layer (.aai/*.prompt.md x4, one new), skill
  wrapper trees (x3, one new dir each), test layer (one new suite), catalogs
  (SKILLS.md, .aai/AGENTS.md), docs/INDEX.md regeneration.
- Order: (1) RED run of the new suite on pre-change tree → save log;
  (2) write SKILL_VERIFY; (3) wire the three prompts; (4) wrappers +
  catalogs; (5) suite green; (6) prompt-diet suite green; (7) strict audit;
  (8) index regen; (9) AC table reconciliation + close-gate self-check.
- Edge cases: keep SKILL_VERIFY comfortably under both caps (120 lines AND
  the byte headroom); do not touch REMEDIATION (out of scope); do not break
  prompt-diet TEST-007 (any new "state.mjs is absent" text must use the
  pointer form — simplest: SKILL_VERIFY needs no STATE fallback text at all,
  it writes no STATE).
- Seam analysis (integration seams and their crossing tests):
  - Seam S1 — the `.aai/*.prompt.md` byte corpus is shared with prompt-diet
    TEST-010 (another feature's gate reads what this change grows). Crossing
    test: TEST-006 re-runs the exact TEST-010 formula post-change; plus the
    real tests/skills/test-aai-prompt-diet.sh run at validation.
  - Seam S2 — wrapper trees are consumed wholesale by aai-sync/aai-update
    (directory copy, no per-file manifest — verified in
    .aai/scripts/aai-sync.sh; no manifest edit needed). Crossing test: none
    required; residual risk: none (dir-copy is shape-agnostic).
  - Seam S3 — IMPLEMENTATION's completion rule is consumed by every
    implementation run; replacing it with a pointer must not delete the
    obligation. Crossing test: TEST-005 asserts both the new pointer AND the
    old marker's absence (move, not loss); the moved body is asserted present
    in SKILL_VERIFY by TEST-002/TEST-003.
  - Seam S4 — docs/INDEX.md and strict audit consume the new spec/draft docs.
    Crossing test: TEST-008 (repo-wide strict audit) + index regeneration.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                 | Status  |
|----------|------------|-------------|---------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-verify-gate.sh | SKILL_VERIFY.prompt.md exists and `wc -l` ≤ 120                              | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-verify-gate.sh | Gate chain literal `IDENTIFY → RUN → READ → VERIFY → CLAIM` present          | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-verify-gate.sh | Rationalization table has ≥6 data rows (pipe-rows minus header/separator)    | green |
| TEST-004 | Spec-AC-01 | unit        | tests/skills/test-aai-verify-gate.sh | Subagent-diff rule present: a line block naming subagent reports + `git diff`| green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-verify-gate.sh | Each of IMPLEMENTATION/VALIDATION/SKILL_TDD has ≥1 and ≤2 `SKILL_VERIFY` lines; old marker "Forbidden language in completion reports" absent from IMPLEMENTATION (S3) | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-verify-gate.sh | Prompt-diet byte formula re-measured post-change: net reduction ≥ 28,672 bytes (S1) | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-verify-gate.sh | `aai-verify/SKILL.md` in .claude/.codex/.gemini trees, each with `name: aai-verify` + pointer to .aai/SKILL_VERIFY.prompt.md | green |
| TEST-008 | Spec-AC-03 | integration | tests/skills/test-aai-verify-gate.sh | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 (S4)  | green |

Notes:
- "All suites green" (CHANGE AC-003) is owned by the Validation full
  tests/skills run, not duplicated as a stanza here (same convention as
  prompt-diet TEST-010). Known environmental exception: LEARNED 2026-07-15
  records tests/skills/test-aai-worktree.sh failing deterministically on this
  machine pre-existing on clean main; verify via stash/main comparison, do
  not chase.
- RED-proof: TEST-001..005, 007 must be observed FAILING on the pre-change
  tree (log: docs/ai/tdd/verify-gate-red.log). TEST-006/008 are
  survival-invariant tests (see Implementation strategy).

## Verification
- `bash tests/skills/test-aai-verify-gate.sh` → exit 0, all 8 stanzas PASS.
- `bash tests/skills/test-aai-prompt-diet.sh` → exit 0 (S1 backstop).
- Full suite: `bash .aai/scripts/aai-run-tests.sh` over tests/skills (per
  runner conventions) → green modulo the recorded worktree environmental
  failure.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: verification-before-completion
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/verify-gate-red.log for RED; suite output logs)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

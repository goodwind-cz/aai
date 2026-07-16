---
id: spec-advisory-skills
type: spec
number: 31
status: draft
ceremony_level: 2
links:
  change: advisory-skills
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Three Optional Advisory Skills: scout, deslop, interrogate

SPEC-FROZEN: true

## Links
- Change: advisory-skills
  (docs/issues/CHANGE-0020-advisory-skills.md, AC-001..AC-003)
- Research: RES-0001 P3 recommendation 15 — pro-workflow patterns: scout
  readiness score, deslop pass, plan-interrogate decision ledger
  (docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md)
- House exemplars: .aai/SKILL_VERIFY.prompt.md (SPEC-0025),
  .aai/SKILL_DEBUG.prompt.md (SPEC-0027) — tone, length, wrapper style
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Ceremony level
Declared `ceremony_level: 2` (full pipeline). Rationale: additive-only work,
but it spans four surfaces at once (3 new `.aai/*.prompt.md`, 9 wrapper files
across three agent trees, 2 catalogs, 1 new test suite) — above L1's "small
single-surface fix". It touches NO path in `protected_paths_l3`
(docs/ai/docs-audit.yaml), and no gate/dispatch/workflow file at all (that is
AC-002, asserted negatively by TEST-012), so L3 is not triggered. No
justification line needed at L2.

## Implementation strategy
- Strategy: loop
- Rationale: prompt-text, wrapper, and catalog work with deterministic
  grep-based verification — the same class as SPEC-0025/SPEC-0027. Every
  gating test is a grep/wc stanza RED-provable by one pre-change run of the
  new suite. RED-GREEN-REFACTOR per test adds no signal over one focused
  pass plus a recorded RED run.
- RED-proof obligation: before any prompt/wrapper/catalog edit, run
  `bash tests/skills/test-aai-advisory-skills.sh` on the pre-change tree and
  save the failing output to `docs/ai/tdd/advisory-skills-red.log`
  (expected: TEST-001..TEST-012 FAIL — target files absent, catalog rows and
  disclaimer literals missing; TEST-013/TEST-014 pass pre-change by
  construction — survival invariants that must hold AFTER the corpus grows
  and the new docs land, re-run post-change so they are non-vacuous).

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: parallel P3 batch — three sibling scopes in flight
  (speclint, truth, profiles); isolation prevents cross-scope diff pollution.
- User decision: worktree (already executing in
  /Users/ales/Projects/aai-p3-advisory, branch feat/advisory-skills)
- Base ref: main
- Inline review scope (explicit paths):
  - .aai/SKILL_SCOUT.prompt.md (new)
  - .aai/SKILL_DESLOP.prompt.md (new)
  - .aai/SKILL_INTERROGATE.prompt.md (new)
  - .claude/skills/aai-scout/SKILL.md, .codex/skills/aai-scout/SKILL.md,
    .gemini/skills/aai-scout/SKILL.md (new)
  - .claude/skills/aai-deslop/SKILL.md, .codex/skills/aai-deslop/SKILL.md,
    .gemini/skills/aai-deslop/SKILL.md (new)
  - .claude/skills/aai-interrogate/SKILL.md, .codex/skills/aai-interrogate/SKILL.md,
    .gemini/skills/aai-interrogate/SKILL.md (new)
  - tests/skills/test-aai-advisory-skills.sh (new)
  - SKILLS.md, .aai/AGENTS.md (three catalog rows/lines each)
  - docs/issues/CHANGE-0020-advisory-skills.md, this spec, docs/INDEX.md (regenerated)

## Design decisions

### D1 — Three advisory prompts, ≤100 lines each, shared ADVISORY contract
House tone/structure of SKILL_VERIFY/SKILL_DEBUG, but advisory, not gate:
each prompt carries the literal disclaimer line
`ADVISORY ONLY — this skill never blocks, gates, or dispatches anything;`
(followed by "skipping or overriding it is always a valid outcome"). None of
them writes STATE, so no state.mjs fallback text is needed (keeps the
prompt-diet floor safe). Byte budget: floor is net reduction ≥28,672 bytes
vs baseline 357,457; pre-change measured reduction is 40,964 → headroom
12,292 bytes. Three prompts at ≤100 lines ≈ ≤3.6 KB each, ≤10.5 KB total —
the floor holds with ≥1.7 KB margin (TEST-013 re-asserts via the prompt-diet
suite itself).

### D2 — SKILL_SCOUT: pre-implementation readiness score (pro-workflow scout)
Score 0–100 as the sum of five named dimensions, 0–20 each, each with a
one-line scoring anchor: Scope clarity, Pattern familiarity, Dependency
awareness, Edge cases, Test strategy. Verdict line: GO when score ≥ 70,
HOLD below 70 — advisory in both directions (a HOLD lists the weakest
dimensions and what evidence would raise them; it never blocks dispatch).

### D3 — SKILL_DESLOP: diff-scoped slop-removal pass (pro-workflow deslop)
Operates ONLY on the current diff scope (never repo-wide). Slop-class table
with ≥5 data rows: obvious/narrating comments; defensive try/catch on
trusted internal paths; premature abstraction; unrequested features;
annotations/reformatting on untouched code. Behavior-unchanged rule: the
full test suite must pass AFTER the pass, run through
`.aai/scripts/aai-run-tests.sh`; the completion claim is handed to
`.aai/SKILL_VERIFY.prompt.md` (cross-link required).

### D4 — SKILL_INTERROGATE: plan decision-walk with ledger (pro-workflow)
Three literal rules: (1) ONE QUESTION AT A TIME — never a questionnaire;
(2) EVERY question ships a recommended answer the human can accept with one
word; (3) codebase-first resolution — before asking, attempt to resolve from
repo evidence and record the source as `inferred: <path>` (only unresolved
decisions reach the human). Each resolved decision appends one line to
`docs/ai/decisions.jsonl` (append-only, echo-append per that file's header):
`{"v":1,"ts":"<ISO8601Z>","actor":"interrogate","type":"planning_decision",`
`"ref":"<REF-ID>","question":"...","answer":"...","source":"inferred: <path>|human|recommended-default"}`.

### D5 — Wrappers ×9 and catalog rows; NO gate/dispatch/workflow wiring
New `aai-scout` / `aai-deslop` / `aai-interrogate` wrapper SKILL.md in
`.claude/skills/`, `.codex/skills/`, `.gemini/skills/`, mirroring the
aai-verify/aai-debug wrapper shape (frontmatter `name` + `description`;
body: read the `.aai/SKILL_*.prompt.md` and follow exactly; not-found
fallback line; no `model:` pin). Catalogs: one Quick Reference row each in
SKILLS.md, one `Follow .aai/SKILL_*.prompt.md` line each in .aai/AGENTS.md.
Unlike SPEC-0025/0027 there is NO role-prompt wiring: no ORCHESTRATION*,
orchestration-dispatch.mjs, orchestration-mode.mjs, or
.aai/workflow/WORKFLOW.md file is touched or may reference these skills
(CHANGE AC-002 "no gate/dispatch file touched", asserted by TEST-012).

### D6 — Grep suite tests/skills/test-aai-advisory-skills.sh
Bash-3.2-compatible suite (exit 0/1/42), same shape as
tests/skills/test-aai-debug-gate.sh. Prompt-diet byte-floor constants are
NOT duplicated — the floor is asserted by running the real prompt-diet suite
(TEST-013). Strict audit asserted by TEST-014.

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/SKILL_SCOUT.prompt.md` exists, ≤100 lines, names all
    five dimensions, states the 0–100 scale and the GO/HOLD threshold at 70,
    and carries the ADVISORY disclaimer literal.
  - Verification: TEST-001..TEST-003 stanzas.
  - Spec-AC-02: `.aai/SKILL_DESLOP.prompt.md` exists, ≤100 lines, slop-class
    table ≥5 data rows naming the five classes, behavior-unchanged rule
    (suite must pass after, via aai-run-tests.sh), cross-link to
    `.aai/SKILL_VERIFY.prompt.md`, ADVISORY disclaimer literal.
  - Verification: TEST-004..TEST-006 stanzas.
  - Spec-AC-03: `.aai/SKILL_INTERROGATE.prompt.md` exists, ≤100 lines, states
    the one-question rule, the recommended-answer rule, `inferred: <path>`
    codebase-first resolution, ledger output to docs/ai/decisions.jsonl,
    ADVISORY disclaimer literal.
  - Verification: TEST-007..TEST-009 stanzas.
- Maps to: CHANGE AC-002
  - Spec-AC-04: 9 wrappers exist (3 skills × .claude/.codex/.gemini) with
    `name:` + pointer; SKILLS.md has 3 rows; .aai/AGENTS.md has 3 Follow
    lines; no orchestration/dispatch/workflow surface references the new
    skills (negative grep over ORCHESTRATION*.prompt.md,
    orchestration-dispatch.mjs, orchestration-mode.mjs, workflow/WORKFLOW.md).
  - Verification: TEST-010..TEST-012 stanzas; review confirms untouched files
    via git diff scope.
- Maps to: CHANGE AC-003
  - Spec-AC-05: new suite green; prompt-diet floor holds; repo-wide strict
    docs audit exits 0; full tests/skills sweep green (validation-owned);
    docs/INDEX.md regeneration idempotent (consecutive runs identical modulo
    the self-stamped Generated timestamp line).
  - Verification: TEST-013..TEST-014 stanzas; full sweep + idempotence probe
    at validation.

## Constitution deviations

None. (1 evidence: grep suite + RED log; 2 simplicity: three small prompts,
no persistence, mandated by an existing requirement; 3 portability: plain
markdown + wrappers in all three trees; 4 degrade: skills are optional by
construction and each wrapper carries the not-found fallback; 5 additive:
no existing prompt line changed; 6 single-writer: STATE only via state.mjs;
7 operator-only merge: no merge in scope.)

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | SKILL_SCOUT ≤100 lines, 5 dimensions, GO/HOLD@70, advisory | done | TEST-001..003 green; docs/ai/tdd/advisory-skills-green.log | — | .aai/SKILL_SCOUT.prompt.md, 59 lines, 3,085 bytes |
| Spec-AC-02 | SKILL_DESLOP ≤100 lines, ≥5-row slop table, suite-pass rule, VERIFY link | done | TEST-004..006 green; docs/ai/tdd/advisory-skills-green.log | — | .aai/SKILL_DESLOP.prompt.md, 56 lines, 2,928 bytes, 5 table rows |
| Spec-AC-03 | SKILL_INTERROGATE ≤100 lines, one-question + recommended-answer + ledger | done | TEST-007..009 green; docs/ai/tdd/advisory-skills-green.log | — | .aai/SKILL_INTERROGATE.prompt.md, 65 lines, 3,041 bytes |
| Spec-AC-04 | 9 wrappers + catalog rows; no gate/dispatch file touched | done | TEST-010..012 green; git status confirms zero edits to ORCHESTRATION*/dispatch/WORKFLOW surfaces | — | wrappers in .claude/.codex/.gemini skills/aai-{scout,deslop,interrogate}/SKILL.md |
| Spec-AC-05 | Suite + sweep green; diet floor holds; audit CLEAN; index idempotent | done | 14/14 stanzas green; sweep 25/26 (sole fail = LEARNED environmental aai-worktree fixture); diet net reduction 31,910 B ≥ 28,672 B floor; strict audit exit 0; index runs identical modulo Generated line | — | evidence logs docs/ai/tdd/advisory-skills-{red,green}.log |

## Implementation plan
- Components affected: prompt layer (3 new .aai/SKILL_*.prompt.md), wrapper
  trees (×3 dirs in each of 3 trees), catalogs (SKILLS.md, .aai/AGENTS.md),
  test layer (1 new suite), docs (CHANGE draft already present, this spec),
  docs/INDEX.md regeneration.
- Order: (1) write the suite; (2) RED run on pre-change tree → save log;
  (3) write the three prompts (byte-budgeted per D1); (4) wrappers ×9;
  (5) catalog rows; (6) suite green; (7) sweep incl. prompt-diet + strict
  audit; (8) index regen ×2 (idempotence probe); (9) AC table reconciliation;
  (10) STATE phase/append-run.
- Edge cases: prompts write no STATE (no fallback text needed); deslop must
  never expand scope beyond the diff (stated in-prompt); interrogate ledger
  lines are append-only and must not edit existing lines (per the file's own
  header rules).
- Seam analysis:
  - Seam S1 — `.aai/*.prompt.md` byte corpus shared with prompt-diet
    TEST-010. Crossing test: TEST-013 runs the real prompt-diet suite
    post-change.
  - Seam S2 — wrapper trees consumed wholesale by aai-sync/aai-update
    (directory copy, shape-agnostic). No crossing test; residual risk none.
  - Seam S3 — orchestration/dispatch surfaces must stay untouched AND
    reference-free (the advisory contract). Crossing test: TEST-012 negative
    grep over the six gate/dispatch/workflow surfaces.
  - Seam S4 — docs/INDEX.md and strict audit consume the new CHANGE/SPEC
    docs. Crossing test: TEST-014 (strict audit) + index-regen idempotence
    probe at validation.
  - Seam S5 — docs/ai/decisions.jsonl is a shared append-only ledger (read
    by aai-replay; written by HITL and review dispositions). INTERROGATE
    defines an additive line type (`"type":"planning_decision"`) and obeys
    the file's append-only header rules. No automated crossing test (the
    writer is an LLM following a prompt, not a script) — recorded as
    residual risk, mitigated by the in-prompt literal format.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                     | Description                                                                 | Status  |
|----------|------------|-------------|------------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-advisory-skills.sh | SKILL_SCOUT.prompt.md exists and `wc -l` ≤ 100                              | green |
| TEST-002 | Spec-AC-01 | unit        | tests/skills/test-aai-advisory-skills.sh | All 5 dimension literals + 0–100 scale + GO/HOLD threshold-70 line present  | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-advisory-skills.sh | ADVISORY disclaimer literal present (never blocks)                          | green |
| TEST-004 | Spec-AC-02 | unit        | tests/skills/test-aai-advisory-skills.sh | SKILL_DESLOP.prompt.md exists and `wc -l` ≤ 100                             | green |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-advisory-skills.sh | Slop-class table ≥5 data rows naming the five classes                       | green |
| TEST-006 | Spec-AC-02 | unit        | tests/skills/test-aai-advisory-skills.sh | Behavior-unchanged rule (suite pass via aai-run-tests.sh) + SKILL_VERIFY cross-link + ADVISORY literal | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-advisory-skills.sh | SKILL_INTERROGATE.prompt.md exists and `wc -l` ≤ 100                        | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-advisory-skills.sh | One-question rule + recommended-answer rule literals present                | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/test-aai-advisory-skills.sh | `inferred: <path>` resolution + decisions.jsonl ledger format + ADVISORY literal | green |
| TEST-010 | Spec-AC-04 | unit        | tests/skills/test-aai-advisory-skills.sh | 9 wrappers exist (3 skills × 3 trees), each with `name:` + prompt pointer   | green |
| TEST-011 | Spec-AC-04 | unit        | tests/skills/test-aai-advisory-skills.sh | SKILLS.md 3 rows + .aai/AGENTS.md 3 Follow lines                            | green |
| TEST-012 | Spec-AC-04 | integration | tests/skills/test-aai-advisory-skills.sh | Advisory isolation: no gate/dispatch/workflow surface references the new skills (S3) + all three prompts carry the disclaimer | green |
| TEST-013 | Spec-AC-05 | integration | tests/skills/test-aai-advisory-skills.sh | Prompt-diet floor holds post-change: `bash tests/skills/test-aai-prompt-diet.sh` exits 0 (S1) | green |
| TEST-014 | Spec-AC-05 | integration | tests/skills/test-aai-advisory-skills.sh | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 (S4) | green |

Notes:
- "Suites green" (CHANGE AC-003) is owned by the Validation full tests/skills
  sweep. Known environmental exception per LEARNED 2026-07-15:
  tests/skills/test-aai-worktree.sh fails deterministically on this machine
  pre-existing on clean main — verify via main comparison, do not chase.
- RED-proof: TEST-001..012 must be observed FAILING on the pre-change tree
  (log: docs/ai/tdd/advisory-skills-red.log). TEST-013/014 are
  survival-invariant tests (see Implementation strategy).

## Verification
- `bash tests/skills/test-aai-advisory-skills.sh` → exit 0, all 14 stanzas PASS.
- `bash tests/skills/test-aai-verify-gate.sh` and
  `bash tests/skills/test-aai-debug-gate.sh` → exit 0 (sibling gates intact).
- Full sweep via `bash tests/skills/test-framework.sh` (framework already
  reaps per-suite) → green modulo the recorded environmental failure.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/generate-docs-index.mjs` run twice → consecutive runs
  byte-identical modulo the self-stamped `Generated:` timestamp line
  (idempotence probe; the generator stamps wall-clock time on every run).
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: advisory-skills
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/advisory-skills-red.log for RED; suite logs)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

## Validation finding disposition (2026-07-16)

- NB (interrogate ledger line keyed "ref" — inherited from decisions.jsonl's
  stale header comment — while every real line uses "ref_id"): REMEDIATED —
  prompt aligned to the file's actual convention.

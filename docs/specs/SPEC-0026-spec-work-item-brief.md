---
id: spec-work-item-brief
type: spec
number: 26
status: draft
links:
  change: work-item-brief
  research: RES-0001
  pr: []
  commits: []
---

# SPEC — Self-Contained Work-Item Brief as Subagent Handoff

SPEC-FROZEN: true

## Links
- Change: work-item-brief (docs/issues/CHANGE-0017-work-item-brief.md,
  AC-001..AC-003)
- Research: RES-0001 P2 recommendation 9 — BMAD story-file pattern
  (self-contained 500–1,000-word handoff: AC↔task links, embedded context,
  Return Record) adapted to AAI with canon POINTERS instead of copies —
  docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md (F3)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Implementation strategy
- Strategy: loop
- Rationale: template + prompt-text + protocol-prose + gitignore work with
  deterministic grep/diff verification. Every gating check is a stanza in the
  existing hygiene suite, trivially RED-provable in one pre-change run (the
  template does not exist, the PLANNING step and protocol paragraph are
  absent, the gitignore entry is missing). RED-GREEN-REFACTOR per test adds
  no signal over one focused pass plus a recorded pre-change failing run.
- RED-proof obligation: add the new hygiene stanza FIRST, run it against the
  pre-change tree, and save the failing output to
  `docs/ai/tdd/work-item-brief-red.log` (expected: TEST-001..TEST-005 FAIL;
  TEST-006/TEST-007 are survival invariants that pass pre-change by
  construction — non-vacuous because TEST-006 re-measures the ORCHESTRATION
  line count after this change adds handoff prose nearby, and TEST-007
  re-measures the prompt-diet byte floor after PLANNING grows).

## Isolation and review
- Worktree recommendation: recommended (already satisfied — work runs in the
  dedicated worktree /Users/ales/Projects/aai-feat-brief, branch
  feat/work-item-brief)
- Worktree rationale: protected AAI workflow surfaces are touched (PLANNING,
  SUBAGENT_PROTOCOL); parallel sibling scopes are in flight in other
  worktrees.
- User decision: worktree
- Base ref: main
- Worktree branch/path: feat/work-item-brief / /Users/ales/Projects/aai-feat-brief
- Inline review scope (explicit paths):
  - .aai/templates/BRIEF_TEMPLATE.md (new)
  - .aai/PLANNING.prompt.md
  - .aai/SUBAGENT_PROTOCOL.md
  - .gitignore
  - docs/ai/briefs/.gitkeep (new)
  - tests/skills/test-aai-hygiene-pack.sh
  - docs/specs/SPEC-0026-spec-work-item-brief.md (this spec)
  - docs/INDEX.md (regenerated)

## Design decisions

### D1 — Brief template `.aai/templates/BRIEF_TEMPLATE.md` (≤60 lines)
Exactly 5 sections, in this order:
1. `## Scope & Why` — one-paragraph mission + business reason (from the
   CHANGE/requirement), ref ids, spec path.
2. `## AC ↔ Task Map` — table mapping each Spec-AC to its TEST-xxx ids and
   the concrete task; lifted from the frozen spec's Test Plan.
3. `## Constraints & Canon Pointers` — repo paths ONLY (spec, requirement,
   TECHNOLOGY, LEARNED, protocol sections), NEVER pasted canon bodies —
   prompt-diet discipline (RES-0001 F3): the brief replaces cold re-reads
   with targeted pointers, it must not become a second copy of the canon.
4. `## Evidence Contract` — per-AC verification command(s) + expected
   evidence path, lifted from the spec's Verification section.
5. `## Return Record` — the result-block skeleton the subagent fills (D2).

### D2 — Return Record = the SUBAGENT_PROTOCOL result block, verbatim
Single source of truth: the fenced `subagent_result:` YAML skeleton in
`.aai/SUBAGENT_PROTOCOL.md` § "Result block (mandatory subagent output)".
The template embeds that skeleton BYTE-IDENTICAL (mechanically diffed by
TEST-002) and cites the section; it does NOT invent a competing format.
If the protocol block ever changes, the template must be re-synced — the
diff test turns RED, which is the desired coupling alarm. The protocol's
`MODEL` contract field and the review anti-gaming rules are untouched.

### D3 — PLANNING emit step (numbered, after freeze, before STATE)
New numbered step 11 in `.aai/PLANNING.prompt.md` PROCESS, between the
SPEC-FROZEN step (10) and the STATE-update step (old 11, renumbered 12):
emit `docs/ai/briefs/<REF-ID>.md` from the template once the spec is frozen
(skip while SPEC-FROZEN is false), fill sections 1–4 from the frozen spec,
leave the Return Record skeleton blank for the subagent, and note that
briefs are gitignored runtime artifacts regenerated on re-plan. No test
couples to PLANNING step numbers (verified by repo grep), so renumbering
is safe. Corpus cost: ~10 lines in a `.aai/*.prompt.md` file — covered by
the prompt-diet floor headroom (TEST-007 re-measures).

### D4 — SUBAGENT_PROTOCOL handoff paragraph (default + degrade)
New subsection under "Subagent call contract": when
`docs/ai/briefs/<ref>.md` exists, the dispatch `INPUT` DEFAULTS to the
brief path + the diff scope (the brief is self-contained). Explicit degrade
clause: when no brief exists for the ref, fall back to the spec path +
requirement/intake paths as before — a missing brief never blocks a
dispatch. The paragraph states the brief's Return Record is the result
block below, verbatim, and that the subagent fills it rather than inventing
its own format.

### D5 — ORCHESTRATION wrapper deliberately unchanged
The CHANGE scope says the wrapper's dispatch inputs "mention the brief when
it exists", but the wrapper is EXACTLY 40 lines against a tested ≤40-line
cap (prompt-diet TEST-011) — zero headroom; any added mention breaks the
cap, and compressing existing lines risks the wrapper's own grep anchors
(test-aai-state.sh, test-aai-orchestration-mode.sh). The mention therefore
lives ONLY in SUBAGENT_PROTOCOL (D4), which the wrapper already routes
every dispatch through at its step 2 ("spawn the named role per
.aai/SUBAGENT_PROTOCOL.md (... inputs ...)") — so dispatch inputs DO pick
up the brief without editing the wrapper. AC-002's "wrapper unchanged in
behavior, cap preserved" is the binding clause; TEST-006 guards it.

### D6 — Gitignore + placeholder (runtime artifact class, like reports)
`.gitignore` gains the same three-line pattern used for
`docs/ai/reports/`: ignore `docs/ai/briefs/**`, un-ignore the directory and
its `.gitkeep`; add `docs/ai/briefs/.gitkeep`. Briefs are per-dev runtime
artifacts — never committed, regenerated by Planning.

### D7 — Grep test stanza in the hygiene suite
One new function `test_060_work_item_brief` in
`tests/skills/test-aai-hygiene-pack.sh`, wired into `main()`, following the
suite's conventions (log_pass/log_fail, TEST-id comments, sourcing-safe).
It carries the TEST-001..TEST-006 assertions below, including the
mechanical extraction + `diff` proving D2.

## Acceptance Criteria Mapping
- Maps to: CHANGE AC-001
  - Spec-AC-01: `.aai/templates/BRIEF_TEMPLATE.md` exists, `wc -l` ≤ 60,
    carries the 5 D1 section anchors and the pointers-not-copies rule; its
    Return Record YAML is byte-identical to the SUBAGENT_PROTOCOL result
    block; PLANNING emits `docs/ai/briefs/<REF-ID>.md` as a numbered step
    after the freeze step and before the STATE step; `.gitignore` ignores
    `docs/ai/briefs/**` but not the committed `.gitkeep` (verified
    behaviorally via `git check-ignore`).
  - Verification: TEST-001..TEST-004 stanzas in
    tests/skills/test-aai-hygiene-pack.sh; expected exit 0 with PASS lines.
- Maps to: CHANGE AC-002
  - Spec-AC-02: SUBAGENT_PROTOCOL names the brief as the DEFAULT dispatch
    INPUT when present, carries the explicit degrade-to-spec-path clause,
    cites the result block as the Return Record's single source, and keeps
    the MODEL contract row + anti-gaming rules intact; ORCHESTRATION
    wrapper stays ≤40 lines with its existing anchors (mention lives in
    SUBAGENT_PROTOCOL only — D5 rationale).
  - Verification: TEST-005, TEST-006 stanzas; plus existing
    test_041_anti_gaming_protocol and prompt-diet TEST-011 at validation.
- Maps to: CHANGE AC-003
  - Spec-AC-03: hygiene suite green including the new stanza; full
    tests/skills sweep green (modulo the LEARNED-recorded environmental
    worktree failure); prompt-diet floor holds (TEST-010 re-measured — the
    template is OUTSIDE the `.aai/*.prompt.md` corpus glob, verified);
    repo-wide strict docs audit exits 0; docs index regeneration
    idempotent; check-state valid.
  - Verification: TEST-007 (existing prompt-diet TEST-010 re-run) + full
    suite run + `node .aai/scripts/docs-audit.mjs --check --strict
    --no-event` + double index regen at validation.

## Acceptance Criteria Status

| Spec-AC    | Description                                              | Status  | Evidence | Review-By | Notes |
|------------|----------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Template ≤60 lines, 5 sections, verbatim Return Record; PLANNING emit step; gitignore + .gitkeep | done | TEST-001..004 green; docs/ai/tdd/work-item-brief-green.log | — | template 55 lines; PLANNING step 11 |
| Spec-AC-02 | Protocol default+degrade handoff; wrapper cap preserved  | done    | TEST-005/006 green; docs/ai/tdd/work-item-brief-green.log; ORCHESTRATION 40 lines | — | mention in SUBAGENT_PROTOCOL only (D5) |
| Spec-AC-03 | Suites green; diet floor holds; strict audit CLEAN       | done    | hygiene+prompt-diet+state+dispatch+metrics+docs-audit+doc-numbering suites exit 0; docs-audit --check --strict --no-event exit 0; index idempotent; check-state VALID | — | worktree suite failure is the LEARNED 2026-07-15 environmental one |

## Implementation plan
- Components affected: template layer (new BRIEF_TEMPLATE.md), prompt layer
  (PLANNING), protocol layer (SUBAGENT_PROTOCOL), .gitignore + placeholder,
  test layer (hygiene suite stanza), docs/INDEX.md regeneration.
- Order: (1) this spec + strict audit; (2) new stanza → RED run saved;
  (3) template; (4) PLANNING step; (5) protocol paragraph; (6) gitignore +
  .gitkeep; (7) stanza GREEN; (8) full sweep + audit + index + check-state;
  (9) AC table reconciliation.
- Edge cases: keep the template comfortably under 60 lines including the
  17-line verbatim skeleton; do not renumber anything a grep anchors on;
  new PLANNING text must not use raw sed/node STATE-edit phrasing
  (test-aai-state.sh TEST-014 negative grep).
- Seam analysis:
  - Seam S1 — the Return Record skeleton is shared text between the
    template and SUBAGENT_PROTOCOL (two files, one contract). Crossing
    test: TEST-002 extracts both fenced blocks and `diff`s them
    byte-for-byte.
  - Seam S2 — PLANNING is inside the prompt-diet byte corpus consumed by
    TEST-010 of another feature's gate. Crossing test: TEST-007 (the real
    prompt-diet suite re-run post-change).
  - Seam S3 — the ORCHESTRATION wrapper's ≤40-line cap is consumed by
    prompt-diet TEST-011. Crossing test: TEST-006 re-measures the wc -l
    and asserts the brief mention is reachable via the wrapper's
    SUBAGENT_PROTOCOL route instead.
  - Seam S4 — .gitignore semantics are consumed by git itself. Crossing
    test: TEST-004 uses `git check-ignore` behaviorally (a path under
    docs/ai/briefs/ is ignored; the .gitkeep is not), not a text grep only.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                  | Description                                                                 | Status |
|----------|------------|-------------|---------------------------------------|-----------------------------------------------------------------------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh | BRIEF_TEMPLATE.md exists, `wc -l` ≤ 60, all 5 D1 section anchors + pointers-not-copies rule present | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-hygiene-pack.sh | Return Record fenced YAML in the template is byte-identical (`diff`) to the SUBAGENT_PROTOCOL result-block skeleton, and the template cites the protocol section as single source (S1) | green |
| TEST-003 | Spec-AC-01 | unit        | tests/skills/test-aai-hygiene-pack.sh | PLANNING carries a numbered emit step: `docs/ai/briefs/` + template path + skip-unless-frozen + gitignored-runtime note, positioned after the SPEC-FROZEN step and before the STATE-update step | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-hygiene-pack.sh | `.gitignore` carries the briefs block; `git check-ignore` confirms docs/ai/briefs/x.md ignored and docs/ai/briefs/.gitkeep NOT ignored; .gitkeep exists (S4) | green |
| TEST-005 | Spec-AC-02 | unit        | tests/skills/test-aai-hygiene-pack.sh | SUBAGENT_PROTOCOL: brief named as DEFAULT INPUT when present + explicit degrade-to-spec-path clause + Return-Record-is-the-result-block sentence; MODEL row and anti-gaming section intact | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-hygiene-pack.sh | ORCHESTRATION.prompt.md ≤40 lines AND still routes dispatch through .aai/SUBAGENT_PROTOCOL.md (the brief mention's reachability path — S3) | green |
| TEST-007 | Spec-AC-03 | integration | tests/skills/test-aai-prompt-diet.sh  | Existing TEST-010/TEST-011 re-run post-change: strict audit CLEAN, net byte reduction ≥ floor with PLANNING grown, wrapper caps hold (S2) | green |

Notes:
- "All suites green" (CHANGE AC-003) is owned by the full tests/skills
  sweep at validation, not duplicated as a stanza (SPEC-0025 convention).
  Known environmental exception: LEARNED 2026-07-15 records
  tests/skills/test-aai-worktree.sh failing deterministically on this
  machine pre-existing on clean main.
- RED-proof: TEST-001..TEST-005 observed FAILING on the pre-change tree
  (log: docs/ai/tdd/work-item-brief-red.log). TEST-006/TEST-007 are
  survival-invariant tests (see Implementation strategy).

## Verification
- `bash tests/skills/test-aai-hygiene-pack.sh` → exit 0, all stanzas PASS.
- `bash tests/skills/test-aai-prompt-diet.sh` → exit 0 (S2/S3 backstop).
- Full sweep per runner conventions (hygiene, prompt-diet, state, dispatch,
  metrics, docs-audit, doc-numbering) → green modulo the recorded
  environmental worktree failure.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → exit 0.
- `node .aai/scripts/generate-docs-index.mjs` twice → second run yields no
  diff (idempotent).
- `node .aai/scripts/check-state.mjs docs/ai/STATE.yaml` → VALID.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: work-item-brief
- Spec-AC and TEST-xxx links where applicable
- command or review scope, exit code or review verdict
- evidence path (docs/ai/tdd/work-item-brief-red.log for RED;
  docs/ai/tdd/work-item-brief-green.log for GREEN)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

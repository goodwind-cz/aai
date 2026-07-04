---
id: CHANGE-0007
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change Request: Workflow hygiene pack — body lint, PR ceremony, review-response, warnings policy, fixture diversity, trigger/wrapper cleanup

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Bundle of independent, individually small workflow-hygiene improvements
  surfaced by the 2026-07-04 skills audit and the CHANGE-0005/RFC-0006 sessions:
  artifact body linting, a PR creation/merge ceremony with scope-only staging,
  a codified external-review-response flow, committing review-report artifacts,
  partial-flush state reset, a warnings policy with teeth, a fixture-diversity
  checklist for test-writing roles, and small wrapper/trigger cleanups.

## Motivation / Business Value
- Every item below corresponds to a defect observed live:
  - Stray tool markup (`</content>`, `</invoke>`) shipped inside an intake body
    (CHANGE-0005) — caught only by an external PR bot; `docs-audit --check`
    validates frontmatter/structure, nothing lints bodies.
  - PR scoping was improvised: an unrelated in-flight file
    (`test-canon-core.mjs`) was nearly bundled into a feature commit; scope-only
    staging exists only as prose in AGENTS.md:253, owned by no prompt.
  - The external-review-response flow (fetch comments → fix with RED-proofed
    tests → reply inline → push) was improvised twice (PR #27, #29) and worked
    well — worth codifying so it is repeatable.
  - 11 orphaned code-review reports sat untracked across sessions because
    SKILL_CODE_REVIEW writes to `docs/ai/reviews/` but nothing stages them.
  - METRICS_FLUSH resets `last_validation`/`code_review` only when NO active
    work items remain — a partial flush leaks the previous item's verdicts into
    the next scope.
  - Code-review PASS requires only "no ERROR"; WARNINGs "require a recorded
    decision" with no location and no gate — in practice carried at model
    judgment (BP-001 was remediated only by operator choice).
  - test-canon shipped 12/12 green while the engine was broken: fixtures never
    produced a fully-covered domain, so the zero-stub path was structurally
    untestable — a fixture-diversity failure class.
  - `.claude/triggers.json` does not exist, so SKILL_WRAP_UP's advertised
    auto-triggers ("hotovo", "konec", "bye") are inert documentation;
    SUBAGENT-STOP guards are missing on the two most loop-adjacent maintenance
    skills (`aai-wrap-up`, `aai-flush`); 6 wrappers lack the standard
    "Invoke this as /aai-…" line; `SKILL_META.prompt.md` is the only prompt
    with no wrapper and no verified loader.

## Scope
- In scope:
  - **H1 — body lint.** `docs-audit.mjs --lint-body` (also folded into
    `--check`): flag unbalanced code fences, residual tool markup
    (`</content>`, `</invoke>`, `<result>`), and unfilled template placeholders
    in governed docs. Wire into intake POST-SAVE and the pre-commit hook
    (report-only by default, consistent with `close_gate`).
  - **H2 — PR ceremony prompt.** New `SKILL_PR.prompt.md` (+ wrapper `aai-pr`):
    derive the scope file-list from STATE/spec, stage ONLY in-scope paths,
    verify nothing unrelated is staged (diff --cached audit), commit with the
    project message conventions, push branch, `gh pr create` with a body
    template; explicitly never merges without operator action.
  - **H3 — review-response flow.** Extend SKILL_CODE_REVIEW with an
    "external review response" section: fetch PR review threads (`gh api`),
    triage findings (real/stale/duplicate), remediate with RED-proofed
    regression tests, reply inline per thread citing commit + test id, push.
  - **H4 — review artifacts committed.** SKILL_CODE_REVIEW instructs staging
    the written report with the scope's commit; SKILL_WRAP_UP's uncommitted-work
    check calls out orphaned `docs/ai/reviews/` files explicitly.
  - **H5 — partial-flush reset.** METRICS_FLUSH resets `last_validation` /
    `code_review` blocks whenever the flushed item was the current focus, not
    only when active_work_items becomes empty.
  - **H6 — warnings policy.** SKILL_CODE_REVIEW: a PASS with open WARNINGs
    requires each WARNING promoted to a `decisions.jsonl` entry or a tracked
    follow-up ref before closeout; the closeout path (VALIDATION step 8b /
    wrap-up advisory) warns on unrecorded ones.
  - **H7 — fixture-diversity checklist.** SKILL_TDD (and SKILL_TEST_CANON):
    required checklist when authoring fixtures — degenerate/empty collections,
    fully-covered/zero-remainder cases, multi-source, mid-operation failure —
    with the RED-proof rule extended to "would this suite stay green if the
    happy path were the only path?".
  - **H8 — wrapper/trigger cleanup.** Create `.claude/triggers.json` via the
    documented aai-auto-trigger flow for wrap-up patterns (or delete the
    auto-trigger promise from SKILL_WRAP_UP); add SUBAGENT-STOP to `aai-wrap-up`
    and `aai-flush`; add the missing "Invoke this as /aai-…" line to the 6
    wrappers lacking it; resolve `SKILL_META.prompt.md` (wire a documented
    loader or remove).
- Out of scope:
  - CHANGE-0006 items (state.mjs, transition reset, implementer AC-table gate).
  - Auto-merge of PRs (operator-only by design).
  - Retro-linting historical docs (report-only surfacing is enough).

## Affected Area
- `.aai/scripts/docs-audit.mjs` (+ lib) — H1.
- `.aai/scripts/install-pre-commit-hook.sh/.ps1` — H1 wiring.
- New `.aai/SKILL_PR.prompt.md`, `.claude/skills/aai-pr/SKILL.md` — H2.
- `.aai/SKILL_CODE_REVIEW.prompt.md` — H3, H4, H6.
- `.aai/SKILL_WRAP_UP.prompt.md` — H4, H8.
- `.aai/METRICS_FLUSH.prompt.md` — H5.
- `.aai/SKILL_TDD.prompt.md`, `.aai/SKILL_TEST_CANON.prompt.md` — H7.
- `.claude/triggers.json`, `.claude/skills/*/SKILL.md` (6 wrappers + 2 guards),
  `.aai/SKILL_META.prompt.md` — H8.
- Tests: docs-audit suite (H1), grep-wiring tests for prompt changes.

## Desired Behavior (To-Be)
- A governed doc with stray tool markup, an unclosed fence, or a template
  placeholder is flagged at intake save time and in the audit (report-only),
  not discovered by an external PR bot.
- Opening a PR is a scripted ceremony: only in-scope files staged (verified),
  conventional message, PR body from template; unrelated in-flight files can
  no longer be bundled by accident.
- External review comments are handled by a documented, repeatable flow ending
  with inline replies citing commit + regression test.
- Review reports never orphan; partial flushes never leak verdicts across
  scopes; PASS-with-WARNINGs leaves an auditable decision trail.
- Test-writing roles must demonstrate fixture diversity, so an all-happy-path
  green suite no longer counts as evidence by itself.
- Advertised auto-triggers actually exist; wrapper set is uniform and guarded.

## Acceptance Criteria
- AC-001: `docs-audit.mjs --lint-body` flags a doc containing `</content>`, an
  unbalanced ``` fence, or `<PLACEHOLDER>`-style residue (distinct warning,
  report-only; exit 0 unless `--strict`); a clean doc produces no warning; the
  intake POST-SAVE step and pre-commit hook reference it.
- AC-002: `SKILL_PR.prompt.md` + `aai-pr` wrapper exist; the prompt derives the
  scope list, stages only it, includes a staged-vs-scope audit step, and forbids
  merge without operator action (grep-verified); wrapper follows the standard
  shim template incl. SUBAGENT-STOP.
- AC-003: SKILL_CODE_REVIEW contains the external-review-response section
  (fetch → triage → RED-proofed fix → inline reply → push) and the
  report-staging instruction (grep-verified).
- AC-004: METRICS_FLUSH resets the focus item's `last_validation`/`code_review`
  on partial flush (prompt wording + fixture walk-through in the test).
- AC-005: SKILL_CODE_REVIEW's warnings policy names the artifact
  (`decisions.jsonl` entry or follow-up ref) and the closeout check that
  surfaces unrecorded WARNINGs (grep-verified).
- AC-006: SKILL_TDD and SKILL_TEST_CANON contain the fixture-diversity
  checklist (grep-verified).
- AC-007: `.claude/triggers.json` exists with the wrap-up patterns (or the
  auto-trigger promise is removed from SKILL_WRAP_UP — one of the two,
  decided at implementation); `aai-wrap-up` and `aai-flush` wrappers carry
  SUBAGENT-STOP; the 6 wrappers gain the invocation line; SKILL_META is either
  referenced by a documented loader or removed.
- AC-008: docs-audit suite extended for H1 stays green; all existing suites
  green; `--check --strict` CLEAN on the real repo (i.e. current docs carry no
  body-lint violations — or violations fixed as part of this change).

## Verification
- New H1 cases in `tests/skills/test-aai-docs-audit.sh` (positive fixture with
  stray tag / unbalanced fence / placeholder; negative control) — green.
- Grep-wiring assertions for H2–H7 prompt changes (TEST-01x style).
- `node .aai/scripts/docs-audit.mjs --check --strict` CLEAN; index regeneration
  idempotent; full skills suites green.
- Manual: run `/aai-pr` ceremony in a fixture repo with one in-scope and one
  out-of-scope dirty file — out-of-scope file must not be staged.

## Constraints / Risks
- H1 must be report-only by default (RFC-0002 posture; `--strict` promotes) so
  mid-migration repos with legacy bodies are not blocked; code fences inside
  legitimate example blocks must not false-positive (lint only governed doc
  types, tolerate fences inside fences conservatively).
- H2 must never auto-merge; merging stays an operator action (matches the
  session's permission-classifier boundary).
- H8 trigger wiring must not auto-invoke wrap-up mid-loop (SUBAGENT-STOP +
  trigger scoping).
- Items are independent; implementation may land them as separate commits under
  one spec to keep review tractable.

## Notes
- Sourced from the 2026-07-04 skills audit (defect classes 4, 6, 8 and the
  wrapper/trigger findings) and live evidence: CHANGE-0005 stray-markup escape,
  the near-bundling of `test-canon-core.mjs`, 11 orphaned review reports,
  BP-001 warning handled by operator judgment, and the test-canon
  green-but-broken fixture gap.
- Companion loop-reliability items are CHANGE-0006.

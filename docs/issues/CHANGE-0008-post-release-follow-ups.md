---
id: CHANGE-0008
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0014
  pr:
    - 46
  commits:
    - 8a690f8
---

# Change Request: Post-release follow-ups — state.mjs field clearing, spec_path placement, auto-trigger reality alignment

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- Three small, recorded follow-ups from the v2026.07.04 wave, bundled as one
  scope (CHANGE-0007 precedent for small-item packs):
  - F1: `state.mjs` cannot null a field — add explicit clearing support.
  - F2: `state.mjs set-phase --spec-path` inserts the key at an ugly (though
    valid) position — fix placement.
  - F3: `SKILL_AUTO_TRIGGER` and USER_GUIDE still document a
    `.claude/triggers.json` mechanism that nothing consumes — align docs (and
    the skill) with reality.

## Motivation / Business Value
- All three were observed live and recorded during the CHANGE-0006/0007 loops:
  - **F1 (SPEC-0013 Planning dogfood feedback):** stale CHANGE-0006
    `worktree.branch/path` and `code_review.head_ref/report_paths` leaked into
    the CHANGE-0007 blocks because no subcommand can set a field back to
    `null`; the planner needed guarded manual edits + check-state — exactly
    the hand-edit class SPEC-0012 exists to eliminate.
  - **F2 (same feedback):** `set-phase --spec-path` appended `spec_path` after
    the blank line following the work-item list entry — valid YAML, wrong
    block visually; cosmetic but erodes trust in the CLI's edits.
  - **F3 (SPEC-0013 D8, deferred):** H8 grep-proved no runtime consumer of
    `.claude/triggers.json` exists and removed the promise from SKILL_WRAP_UP,
    but `SKILL_AUTO_TRIGGER.prompt.md` (the whole skill), its wrapper, and the
    USER_GUIDE "Automation & Integration" section still document the
    consumer-less mechanism as if it worked — the next operator will wire
    triggers that never fire.

## Scope
- In scope:
  - F1: clearing support in `state.mjs` for nullable fields (e.g. a `--clear
    <field-list>` flag or an explicit `null` sentinel value on set-worktree /
    set-code-review / set-validation / set-focus), with the same strict-flag
    and closed-set discipline as the rest of the CLI; tests.
  - F2: `set-phase --spec-path` places `spec_path` inside the work-item block
    (directly after `primary_path`), not after the trailing blank line; tests
    (byte-level placement assertion).
  - F3: align `SKILL_AUTO_TRIGGER.prompt.md` + `.claude/skills/aai-auto-trigger`
    wrapper (+ `.codex`/`.gemini` mirrors) + USER_GUIDE "Automation &
    Integration" with reality. Planning decides the shape: either (a) mark the
    mechanism explicitly as not-consumed/aspirational with the wrapper-description
    trigger-phrase channel as the real alternative, or (b) deprecate the skill.
    Grep-wiring tests.
- Out of scope:
  - Building a real triggers.json consumer (separate feature if ever wanted).
  - Any other state.mjs surface changes (log-tick legacy fields etc.).

## Affected Area
- `.aai/scripts/state.mjs` (+ `lib/state-core.mjs` if placement logic lives
  there), `tests/skills/test-aai-state.sh` — F1, F2.
- `.aai/SKILL_AUTO_TRIGGER.prompt.md`, `.claude/.codex/.gemini`
  `aai-auto-trigger` wrappers, `docs/USER_GUIDE.md` — F3.

## Desired Behavior (To-Be)
- F1: an operator/role can clear a stale field to `null` via the CLI (no
  manual YAML edit), with refusal semantics consistent with reset-block
  (clearing a verdict field on a `pass` block still requires the reset-block
  path — clearing must not become a guard bypass).
- F2: after `set-phase --ref X --spec-path Y`, the `spec_path` line sits
  within X's list-item block adjacent to `primary_path`; repeated invocations
  stay idempotent.
- F3: no AAI doc or skill claims `.claude/triggers.json` is consumed; the
  auto-trigger story is either honestly labeled aspirational or the skill is
  deprecated with a pointer to wrapper-description trigger phrases.

## Acceptance Criteria
- AC-001: a nullable field set by a prior scope can be cleared via the CLI;
  the write is atomic, `check-state.mjs` exits 0 after, and clearing a
  guarded verdict field without the sanctioned path is refused (exit 2).
- AC-002: unknown fields in the clear list are rejected (exit 2, naming the
  valid set) — same strict discipline as flags.
- AC-003: `set-phase --spec-path` places `spec_path` inside the work-item
  block; a byte-level test asserts placement and idempotence.
- AC-004: no file in `.aai/` or `docs/` presents `.claude/triggers.json` as a
  working mechanism (grep-verified); the auto-trigger skill/wrapper text
  matches the decided shape (aspirational label or deprecation).
- AC-005: full `test-aai-state.sh` suite green including new cases; repo-wide
  `docs-audit --check --strict` CLEAN; USER_GUIDE body-lint PASS.

## Verification
- `state.mjs set-worktree --clear branch,path` (or decided syntax) on a
  fixture with stale values → fields become `null`, diff touches only those
  lines, check-state exit 0.
- `state.mjs set-phase --ref X --spec-path Y` on a fixture → placement
  assertion; run twice → byte-identical.
- `grep -r "triggers.json" .aai docs .claude .codex .gemini` → only
  reality-aligned mentions remain.
- Suites via `.aai/scripts/aai-run-tests.sh`; RED-proof for each new test.

## Constraints / Risks
- F1 must not weaken D6 guard semantics (reset-block remains the only way to
  clear verdict statuses; --force stays explicit).
- F2 placement change must not break existing tests that assert current
  output (update them consciously, not silently).
- F3: if deprecation is chosen, keep the wrapper present but pointing to the
  explanation (removing a wrapper breaks muscle memory and mirrors).

## Notes
- Sources: SPEC-0013 Planning dogfood feedback (F1, F2); SPEC-0013 D8
  deferred follow-up (F3); `last_session.next_focus` records F1+F3.
- Related: SPEC-0012 (state.mjs), SPEC-0013 (H8 trigger cleanup).

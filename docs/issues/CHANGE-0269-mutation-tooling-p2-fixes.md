---
id: mutation-tooling-p2-fixes
type: change
number: 269
status: done
capability: mutation-tooling-p2-fixes
user_visible: false
links:
  pr: []
  commits: []
---

# Mutation tooling: close the ten open P2 follow-ups

## Summary
- The owner asked (2026-11-25) to close the ten open P2 follow-ups that
  name defects in the mutation tooling, `.aai/scripts/mutation-run.mjs` and
  `.aai/scripts/mutation-gate.mjs`. The full records are in
  `docs/ai/decisions.jsonl`; read them with
  `node .aai/scripts/follow-ups.mjs list --status open --json`.
- In scope, one item each:
  1. `fu-mutation-target-symlink-unchecked`: `--sed` never lstats
     `--target`, so a symlinked target writes through to its destination
     and can forge a RED.
  2. `fu-mutation-sed-drops-multiline-flag`: `applySedExpr` honours only the
     `g` flag, so a per-line anchored expression (`^...$`) can never match a
     single line.
  3. `fu-mutation-selector-vs-bare-dispatch`: suites whose `main()`
     dispatches on `declare -f test_$t` expect a bare suffix, so a full
     `test_*` selector returns INCONCLUSIVE. Named suites still untriaged:
     `test-aai-branch-guard.sh`, `test-aai-run-tests.sh`,
     `test-aai-session-lock.sh`, `test-aai-win-fallback.sh`.
  4. `fu-mutation-patch-consumes-own-source`: `--patch` whose source is the
     record's own canonical `mutation-TEST-<id>.patch` crashes with ENOENT
     after rotating its own source away.
  5. `fu-mutation-sed-replacement-unescaped`: the `--sed` replacement is
     used as a literal `String.replace` substitution while the pattern is a
     RegExp; an escaped replacement inserts real backslashes, the mutated
     module fails to parse, and a FALSE RED results.
  6. `fu-mutation-gate-absent-tree-passes`: on a checkout without the
     gitignored evidence tree the gate degrades to exit 0, and nothing in
     CI runs it.
  7. `fu-mutation-run-patch-self-rotate`: same mechanism as item 4, seen
     from `rotateExisting()`; one fix closes both.
  8. `fu-mutation-overlay-tracked-deletes`: the overlay skips ENOENT, so a
     tracked file deleted in the working tree survives in the clone.
  9. `fu-mutation-rotation-colon-path`: rotated record names carry an ISO
     timestamp with colons, which Windows forbids in a path.
  10. `fu-frozen-mutation-cells-unusable`: frozen Mutation cells are
      written at spec freeze without ever being executed.

## Motivation / Business Value
- The mutation gate is the layer that proves a test can fail. Items 1, 2,
  5 and 10 let it record a RED that proves nothing, or make a stated
  mutation inexpressible. Items 4, 7 and 9 destroy or poison evidence
  records. Item 3 makes whole suites silently unmutatable. Item 6 means
  the gate's PASS is never re-derived outside the authoring worktree.

## Scope
- In scope: items 1 to 10, a RED-then-GREEN test for each fix, a
  CHANGELOG entry, and closing each follow-up with this ride's ref.
- An item may be dropped or deferred instead of fixed only when a fix is
  wrong or out of reach; the reason is then stated in the spec and in the
  ledger close note.
- Out of scope: PR #535 and its work; the two sibling rides
  (`secrets-gate-false-positives`, `issue-577-index-noise`); changing the
  gitignore status of the evidence tree (tracked separately as
  `fu-mutation-evidence-is-gitignored`, P3).

## Affected Area
- `.aai/scripts/mutation-run.mjs`, `.aai/scripts/mutation-gate.mjs`,
  `tests/skills/test-aai-mutation-gate.sh`, and possibly the four suites
  named in item 3 and the planning or TDD prompt text that governs frozen
  Mutation cells (item 10).
- `.github/workflows` only if item 6 truly needs it; that makes the ride
  ceremony 3 (owner-merged). The smallest correct fix is preferred.

## Desired Behavior (To-Be)
- `--target` that is not a regular file inside the clone is refused.
- `--sed` supports the flags a spec needs (at least `m`), and its
  replacement follows the same escaping rules as its pattern, or a mutated
  file that no longer parses is refused as INCONCLUSIVE, not counted RED.
- A selector works for both dispatch idioms.
- Re-recording a patch row from its own canonical record works and never
  loses the record.
- Rotated record names are valid on Windows.
- Tracked deletes in the working tree are reproduced in the clone.
- A frozen Mutation cell is dry-run (or otherwise checked) before freeze.
- The gate cannot report a green verdict on a tree that holds no evidence
  in a context that treats its verdict as a merge criterion.

## Acceptance Criteria
- AC-001: each of the ten follow-ups is either fixed with a test that
  fails before the fix and passes after it, or dropped/deferred with a
  stated reason in the spec and the ledger.
- AC-002: each of the ten follow-ups is closed in the ledger with
  resolved-by set to this ride's ref.
- AC-003: `tests/skills/test-aai-mutation-gate.sh` and every other touched
  suite pass.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh`
  exits 0.
- `node .aai/scripts/follow-ups.mjs list --status open --json` lists none
  of the ten ids.

## Constraints / Risks
- Mutation tests never touch real docker, real repositories or anything
  outside their own temporary clones. An empty filter is a hard failure.
  Every test cleans up what it creates.
- Existing frozen specs may pin behaviour changed here; any such change is
  recorded with spec-amend.
- No secret is referenced.

## Notes
- Assumption (autopilot): the ride runs in its own worktree,
  `/Users/ales/Projects/aai-worktrees/p2-mutation-tooling`, branch
  `fix/p2-mutation-tooling`, decided by the owner's brief.
- Assumption (autopilot): Planning decides the implementation mode.
- New findings during the ride become P3 follow-ups.

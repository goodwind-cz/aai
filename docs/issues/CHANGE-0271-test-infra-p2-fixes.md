---
id: test-infra-p2-fixes
type: change
number: 271
status: done
capability: test-infra-p2-fixes
user_visible: false
links:
  pr: []
  commits: []
---

# Test infrastructure: close the nine open P2 follow-ups

## Summary
- The owner asked (2026-11-25) to close the open P2 follow-ups of the
  test-infrastructure cluster, plus one new item filed by this ride. The
  full records are in `docs/ai/decisions.jsonl`; read them with
  `node .aai/scripts/follow-ups.mjs list --status open --json`.
- In scope, one item each:
  1. `fu-prompt-diet-fixture-real-root-race`: `tests/skills/test-aai-prompt-diet.sh`
     creates and deletes a draft in the REAL project root when run bare, and
     a concurrent docs-audit corpus walk crashes on the vanished file
     instead of degrading.
  2. `fu-suite-fail-text-blocks-attribution`: a suite whose failure wrapper
     prints no literal FAIL text (`test-aai-intake.sh`) can never have a
     redden attributed by mutation-run; nothing checks suites against the
     attribution contract.
  3. `fu-docs-audit-suite-has-no-selector`: `tests/skills/test-aai-docs-audit.sh`
     runs every arm on every invocation, so a mutation on a shared file
     crashes an earlier arm and comes back INCONCLUSIVE.
  4. `fu-runtests-capture-is-unscored-noise`: `aai-run-tests.sh` records a
     friction observation with `confidence: low` and no impact on every
     non-zero exit, including every deliberate TDD RED run.
  5. `fu-framework-discover-exit-swallowed`: in `test-framework.sh --skill`
     a missing test file makes `discover_tests` exit 2 inside a process
     substitution; the exit is lost and the run goes green with fewer suites.
  6. `fu-lib-graph-narrowing-after-sharding`: the shared-lib FULL_RUN rule
     of CI test selection is not narrowed by the lib reverse-import graph,
     and the selected-mode job is not sharded.
  7. `fu-assertions-pinned-to-one-world`: nothing detects a suite assertion
     bound to a moving ref, a last-index ledger position or an
     `[unreleased]` heading.
  8. `fu-reuse-docs-closure-suites`: the expensive docs/-closure suites
     (docs-content, hygiene-pack, spec-lint) can never be reused because
     their declared inputs are too broad.
  9. `fu-tests-share-real-pwsh-cache` (new, filed by this ride): suites that
     launch pwsh without a fresh `XDG_CACHE_HOME` write the owner's real
     `~/.cache/powershell/StartupProfileData-NonInteractive`; concurrent
     suites corrupted it twice (2026-11-08, 2026-11-25), after which pwsh
     crashes at startup with an AssemblyName parse error.

## Motivation / Business Value
- Items 5 and 9 are the most serious: 5 turns a deleted suite into a green
  run with silent coverage loss; 9 lets the test suite corrupt the owner's
  own shell environment. Items 1, 2 and 3 make suites unreliable or
  unmutatable. Items 4, 6 and 8 waste CI time or bury real friction in
  noise. Item 7 is a class of brittle assertion that has broken main three
  times.

## Scope
- In scope: items 1 to 9, a RED-then-GREEN test for each fix, a CHANGELOG
  entry, and closing each follow-up with this ride's ref.
- An item may be dropped or deferred instead of fixed only when a fix is
  wrong or out of reach; the reason is then stated in the spec and in the
  ledger close note.
- Out of scope: PR #535 and its work; the sibling ride
  `secrets-gate-false-positives`.

## Affected Area
- `.aai/scripts/aai-run-tests.sh`, `tests/skills/test-framework.sh` and its
  sharding/selection helpers, `tests/skills/test-aai-prompt-diet.sh`,
  `tests/skills/test-aai-docs-audit.sh`, `tests/skills/test-aai-intake.sh`,
  `.aai/scripts/docs-audit.mjs`, the suite-evidence-reuse input
  declarations, and the suites that cover them.
- `.github/workflows` only if item 6 truly needs it; that makes the ride
  ceremony 3 (owner-merged). The smallest correct fix is preferred, and an
  item that needs a workflow change may be deferred instead.

## Desired Behavior (To-Be)
- Every suite launched by the shared runner gets a private temporary
  `XDG_CACHE_HOME` that the runner removes afterwards; no suite run writes
  the real `~/.cache/powershell`.
- A missing test file in selected mode fails the run.
- A suite never writes the shipping project root; docs-audit degrades on a
  file that vanishes mid-walk.
- Suites are checked against the mutation attribution contract; the
  docs-audit suite can run one arm.
- The wrapper records a friction observation only when it carries signal.
- A lint catches one-world assertions.
- The shared-lib rule escalates only the suites that import the changed lib.
- The docs-closure suites declare inputs narrow enough to be reused.

## Acceptance Criteria
- AC-001: each of the nine follow-ups is either fixed with a test that
  fails before the fix and passes after it, or dropped/deferred with a
  stated reason in the spec and the ledger.
- AC-002: each of the nine follow-ups is closed in the ledger with
  resolved-by set to this ride's ref.
- AC-003: a test proves a suite run through the shared runner never
  touches the real pwsh cache path, using a fake HOME and XDG directory.
- AC-004: every touched suite passes.

## Verification
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`
  exits 0.
- `node .aai/scripts/follow-ups.mjs list --status open --json` lists none
  of the nine ids.

## Constraints / Risks
- Tests never touch real docker, real repositories or the owner's home
  files, and never read, modify or delete the owner's real
  `~/.cache/powershell`. An empty filter is a hard failure. Every test
  cleans up what it creates.
- Existing frozen specs may pin behaviour changed here; any such change is
  recorded with spec-amend.
- No secret is referenced.

## Notes
- Assumption (autopilot): the ride runs in its own worktree,
  `/Users/ales/Projects/aai-worktrees/p2-test-infra`, branch
  `chore/p2-test-infra`, decided by the owner's brief.
- Assumption (autopilot): Planning decides the implementation mode.
- New findings during the ride become P3 follow-ups.

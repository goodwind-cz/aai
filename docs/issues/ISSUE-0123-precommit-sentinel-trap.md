---
id: precommit-sentinel-trap
type: issue
capability: docs-close-gate
number: 123
status: done
links:
  pr: []
  commits: []
---

# Pre-commit parse sentinel trusts the environment, and the trap fd close is untested

## Summary
Two P3 follow-ups left by PR #570 (DEBT-0016 / SPEC-0301), confirmed by the
independent code review r2 of that PR (R2-NB-1, R2-NB-2):

1. `fu-precommit-sentinel-env-init`: `.aai/scripts/pre-commit-checks.sh`
   never initialises `PCC_PARSED`, so `PCC_PARSED=1` inherited from the
   environment satisfies the parse-completion sentinel that runs after the
   batched staged-content parse block. The sentinel exists only to block a
   commit when that block aborts part-way, and the environment can switch it
   off.
2. `fu-precommit-trap-fd-close-untested`: the EXIT trap closes descriptors 3
   and 4 in the `rm -rf` child (`3<&- 4<&-`) so the scratch directory, which
   holds copies of the staged blobs, can be removed under a nearly full
   descriptor table. No test covers it: a mutant without the close leaves the
   scratch directory behind at `ulimit -n 5` on bash 3.2, while TEST-3875,
   TEST-3880 and TEST-3882 stay green.

Also checked in the same small scope, folded in only if each is small and
safe: `fu-precommit-check3-open-window`, `fu-precommit-index-race-block`,
`fu-pcc-other-builtin-redir`.

## Type
bug

## Impact
- Every project that vendors the layer and runs `pre-commit-checks.sh`
  before a commit. CHECK 2 (secrets) is the one blocking check; the sentinel
  is its backstop against a parse that stops early and leaves the checks
  scanning fewer files than were staged.
- (1) is defence in depth: the shipped script has no reachable abort, but a
  future edit that adds one would pass silently under an exported
  `PCC_PARSED=1`.
- (2) is a regression guard: without it a later edit can again leave staged
  secret content in `TMPDIR` after a blocked run.
- Severity: P3 each, on an L3 protected surface.

## Current Behavior
- (1) With the size check's leading-zero rejection removed (a mutant) and
  `git cat-file` answering a zero-padded size, the run exits 1 with "parse
  did not complete"; the same run with `PCC_PARSED=1` in the environment
  exits 0 and the staged secret is not reported.
- (2) A mutant whose EXIT trap is `rm -rf "$PCC_TMP"` leaves
  `aai-pre-commit.*` in `TMPDIR` after a blocked run at `ulimit -n 5` on bash
  3.2; the suite stays green.

## Expected Behavior
- (1) `PCC_PARSED` (and any other flag of the same kind in the staged-content
  block and CHECKs 2-4) is set by the script before it is read, so no
  inherited value can satisfy a check. The same mutant blocks the commit with
  `PCC_PARSED=1` in the environment.
- (2) A suite case fails when the trap stops closing descriptors 3 and 4: a
  blocked run at a low descriptor limit leaves no scratch directory behind.

## Steps to Reproduce (if applicable)
1) (1) Copy `pre-commit-checks.sh` with the `0?*` size pattern removed; put
   a `git` wrapper in `PATH` that rewrites the `cat-file --batch` header size
   `28` to `028`; stage a file holding an api_key assignment with a quoted 15-character
   value; run the
   copy with `PCC_PARSED=1` exported: exit 0.
2) (2) Copy the script with the trap reduced to `rm -rf "$PCC_TMP"`; stage
   the same secret; run it under `ulimit -n 5` with a private `TMPDIR` on
   bash 3.2: exit 1, and `aai-pre-commit.*` remains in `TMPDIR`.

## Verification
- Failing-first cases in `tests/skills/test-aai-pre-commit-checks.sh`, each
  proven RED against a mutant or fault injection and recorded as a mutation.
- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
  passes.

## Constraints / Risks
- `.aai/scripts/pre-commit-checks.sh` is an L3 protected surface: ceremony
  level 3, the owner merges.
- Bash 3.2 compatible; GNU and BSD userland.
- Secrets preflight: no secret referenced.

## Notes
- Assumption (autopilot): the audit of "other sentinels/flags" covers every
  variable the staged-content block and CHECKs 2-4 read before they assign
  it; a flag found there is initialised in this scope.
- Assumption (autopilot): each of the three optional follow-ups is decided in
  Planning; one that needs a design decision or a rewrite outside the
  staged-content block stays open.

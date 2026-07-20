---
id: test-canon-stat-portability
number: 19
type: issue
status: done
links:
  pr:
    - 121
  commits:
    - fb69fdef0280f5776e6a005f62303f8f4949fffc
---

# test-aai-test-canon.sh reads wrong mtime on Linux (`stat -f` tried before `stat -c`)

## Summary
- `tests/skills/test-aai-test-canon.sh` reads file mtimes with
  `stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null` at four sites
  (lines 516, 536, 722, 735). This is the RC4 bug class already fixed elsewhere:
  on GNU/Linux `stat -f` SUCCEEDS (it means `--file-system`, printing filesystem
  info, not the file mtime), so the `|| stat -c %Y` fallback never runs and the
  suite reads a wrong/garbage value on Linux. Swap to GNU `stat -c` first, BSD
  `stat -f` fallback — matching the already-correct
  `tests/skills/test-aai-update.sh:245`.

## Type
- bug

## Impact
- Correctness / portability hygiene: the four sites read a wrong mtime on the
  Linux CI runner. Deterministic (not the source of the intermittent test-canon
  flake — that remains undiagnosed pending a CI red that names the failing test),
  but it is the same latent RC4 bug class we removed from `aai-update`/
  `aai-sync`/`validate-skills`; leaving it here is an inconsistency. Severity: low
  (test-only, deterministic).

## Current Behavior
- `stat -f %m "$f" 2>/dev/null || stat -c %Y "$f" 2>/dev/null` — on Linux
  `stat -f %m` does not error out to the fallback the way BSD-vs-GNU intent
  assumes; the GNU `--file-system` path is taken and the fallback is skipped.

## Expected Behavior
- The mtime read is correct on BOTH macOS (BSD) and Linux (GNU): try GNU
  `stat -c %Y` first, fall back to BSD `stat -f %m` — identical to the RC4 fix in
  `test-aai-update.sh`.

## Steps to Reproduce (if applicable)
1) On Linux, `stat -f %m <file>` returns filesystem info (exit 0), so
   `stat -f %m <file> || stat -c %Y <file>` never reaches the correct mtime read.

## Verification
- All four sites in `test-aai-test-canon.sh` read mtime via
  `stat -c %Y … || stat -f %m …` (GNU-first); no `stat -f`-first mtime read
  remains (`grep -nE 'stat -f [^|]*\|\| *stat -c' tests/skills/test-aai-test-canon.sh`
  returns nothing).
- `./tests/skills/test-aai-test-canon.sh` exits 0 on macOS (non-regression).
- The `skill-suite` CI job stays green on Ubuntu (authoritative for the GNU path).

## Constraints / Risks
- Behavior-preserving on macOS: BSD `stat -c` fails → falls back to `stat -f %m`
  → same value as today. Pure operand-order swap; no logic change.
- This does NOT claim to fix the intermittent test-canon flake (that is a separate,
  still-undiagnosed nondeterminism; the framework now dumps failing-suite tails so
  the next CI red will name the failing test). This issue is correctness hygiene
  only — do not conflate.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- Same class as CHANGE-0043 RC4 (`stat -f` vs `stat -c` on GNU) and LEARNED
  2026-07-19. This finishes cleaning the RC4 class repo-wide (grep confirms these
  four are the only remaining `stat -f`-first mtime reads in code).

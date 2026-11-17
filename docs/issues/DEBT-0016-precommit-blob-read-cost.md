---
id: precommit-blob-read-cost
type: techdebt
number: 16
status: done
links:
  pr: []
  commits: []
---

# Tech Debt: pre-commit checks read the staged blobs in one batched index read

## Debt Summary
- Since PR #569 (ISSUE-0122 / SPEC-0300), `.aai/scripts/pre-commit-checks.sh`
  CHECKs 2, 3 and 4 each run `git cat-file -e ":0:<path>"` and then
  `git show ":0:<path>"` for every staged file. That is up to six git
  processes per staged file.
- On 600 staged `.js` files the hook takes 29-31 s. Before #569 it took
  7.8-8 s, so it is about 3.7-3.9x slower (review r1 of the previous ride,
  and VALIDATION r4 `probe-colon-perf.out`).
- Follow-up `fu-precommit-blob-read-cost` (P3) tracks this. It replaced
  `fu-precommit-staged-blob-process-count`, whose recorded figures came from a
  reverted variant.

## Root Cause
- #569 changed the checks to judge the staged content (the index) instead of
  the working tree, and did it the simplest safe way: one git process for the
  existence test and one for the read, per check, per file.
- A scratch-copy variant was tried in that ride and reverted. Validation r3
  of `hook-gate-staged-content` failed it because it failed OPEN on
  truncation: a 300 KB file with the secret on its last line, written under
  `ulimit -f 200`, was scanned as a truncated copy and passed.

## Current Cost / Risk
- Every commit with many staged files (a vendored-layer sync, a
  rename sweep, generated fixtures) waits several times longer than before.
  A slow hook pushes people toward `--no-verify`, which skips every guard.
- A commit of a handful of files is not affected in practice.

## Target State
- One batched index read per hook run. The staged blobs for CHECKs 2-4 are
  read with ONE `git cat-file --batch` call (or `--batch-check` plus
  `--batch`), whose output is consumed whole and parsed by the size each
  header declares. The number of git processes the script starts no longer
  grows with the number of staged files.
- Wall-clock time on the 600-file benchmark is back near the pre-#569 cost
  (about 8 s on the reference machine), not 29-31 s.
- The staged-content semantics are exactly what #569 left:
  - a staged deletion (no stage-0 index entry) is skipped;
  - every path for which the index holds a stage-0 file is checked;
  - the staged list is read NUL-separated, so a name git would quote is
    checked under its real path;
  - CHECKs 2-4 scan the staged blob content, never the working tree.
- FAIL CLOSED on every read problem. A non-zero exit of the batch reader, a
  short read, a header that does not parse, a response count that differs
  from the request count, a size that does not match the bytes present, a
  scratch file that cannot be created or written: each of these blocks the
  commit (exit 1) with one clear line that says the staged content could not
  be read completely. None of them may let the commit through unscanned.

## Scope
- In scope:
  - `.aai/scripts/pre-commit-checks.sh` CHECKs 2-4 (the staged list read, the
    index existence test and the content reads).
  - `tests/skills/test-aai-pre-commit-checks.sh`: new tests, and the pins that
    the change moves (TEST-3454 numstat, TEST-3461 line counts).
  - `CHANGELOG.md`: one `## [unreleased] — <title>` entry (a faster
    pre-commit hook is visible to consumers).
- Out of scope:
  - CHECK 7 (its own `--diff-filter=ACM` list) and CHECKs 1, 5, 6, 8, 9.
  - The installed hook template `.aai/templates/git-hooks/pre-commit-index.sh`
    and `docs-audit.mjs` (unchanged).
  - What the checks look for (the patterns and messages stay as they are).

## Plan / Migration
- Planning chooses the exact shape. Constraints it has to meet are listed
  under Verification and Constraints.
- Rollback: revert the commit; the #569 script is correct, only slow.

## Verification
- RED-first fail-closed test: a staged file whose batch read is truncated
  (for example a `git` wrapper on PATH that cuts the `cat-file --batch` output
  short, or drops the last response, while exiting 0) makes the script exit 1
  with the fail-closed message. The script at origin/main does not print
  that message, so the test is red there.
- RED-first cost test that does not depend on wall-clock time: a `git` wrapper
  on PATH counts the git processes the script starts. With 5 and with 40
  staged files the count is the same, and the content is read by exactly one
  `cat-file` call with no `git show`. The script at origin/main fails this.
- TEST-3860..3870 (docs-audit and pre-commit suites) stay green, and so does
  every existing pre-commit suite case: TEST-3454 small-input parity with
  byte-identical output, TEST-3864 (staged then deleted from the working
  tree), TEST-3866 (non-ASCII names).
- Moved pins are re-pinned in the same change: TEST-3454 numstat against
  `3e6b52d5`, TEST-3461 line and code-line counts.
- Benchmark: 600 staged `.js` files, origin/main script against the new
  script, wall-clock recorded in the validation evidence (informational, not
  a test).
- Bash 3.2 (`/bin/bash` 3.2.57 on macOS) under `set -euo pipefail`, GNU and
  BSD userland.

## Constraints / Risks
- L3 protected surface: `.aai/scripts/pre-commit-checks.sh` is listed in
  `protected_paths_l3`. The owner merges.
- Fail-open on truncation is the known failure of the reverted variant
  (validation r3). The design must not trust a scratch copy it has not
  checked against the sizes git reported.
- The `git cat-file --batch` input is one object name per line, and git
  strips a trailing CR from each line. A path that holds a newline or a
  carriage return cannot be named on that protocol. Such paths need their
  own read, and they must still be checked.
- No new runtime dependency: CHECKs 1-7 run without Node, so the parser is
  bash plus POSIX tools (`dd`, not GNU-only flags).
- The pipe-grep-q ratchet (TEST-3455) must stay at 0 sites, and the
  cd-subshell-leak baseline must not grow.
- Secrets preflight: no secret is referenced by this scope.

## Notes
- Sources: `docs/ai/reviews/review-hook-gate-staged-content-r2-20261117T112846Z.md`
  NB-1; `docs/ai/validation/VALIDATION-hook-gate-staged-content-r4.md`
  (performance and fail-open sections); docs/issues/ISSUE-0122-hook-gate-staged-content.md;
  docs/specs/SPEC-0300-spec-hook-gate-staged-content.md (D4, D5).
- Autopilot (/aai-ship): metrics question skipped (human_time_minutes null);
  implementation mode left to Planning.
- Worktree: owner directive in the dispatch brief (L3 surface), at
  /Users/ales/Projects/aai-worktrees/precommit-blob-read-cost.

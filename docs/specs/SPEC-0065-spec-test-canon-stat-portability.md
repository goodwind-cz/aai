---
id: spec-test-canon-stat-portability
type: spec
number: 65
status: done
ceremony_level: 1
links:
  requirement: docs/issues/ISSUE-0019-test-canon-stat-portability.md
  rfc: null
  pr:
    - 121
  commits:
    - fb69fdef0280f5776e6a005f62303f8f4949fffc
---

# Implementation Spec — test-canon mtime read: GNU-first `stat` portability

SPEC-FROZEN: true

Ceremony justification: single file (`tests/skills/test-aai-test-canon.sh`),
4 occurrences, pure operand-order swap (`stat -c %Y … || stat -f %m …`
replacing `stat -f %m … || stat -c %Y …`) matching an already-reviewed,
already-shipped pattern (`tests/skills/test-aai-update.sh:245`, RC4 class,
Session 2026-07-19 LEARNED rule). No production code, no schema, no logic
change — behavior-preserving on macOS (BSD `stat -c` fails, falls back to
`stat -f %m`, same value read today), correctness fix on Linux (GNU `stat -f`
would otherwise silently succeed on the wrong flag meaning and skip the
fallback). Not on `protected_paths_l3` (docs/ai/docs-audit.yaml).

## Links
- Requirement: docs/issues/ISSUE-0019-test-canon-stat-portability.md
- Decision records: n/a
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: loop
- Rationale: Mechanical, behavior-preserving operand-order swap at 4 sites in
  one file, copying a pattern already reviewed and shipped elsewhere in the
  same file family (`test-aai-update.sh:245`). No new logic, no design
  decision, no RED-GREEN-REFACTOR signal to gain from TDD — a `loop` pass
  applying the swap and running the suite is sufficient.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Single-file, 4-line, low-risk test-infra fix in the
  current branch (fix/test-canon-stat-portability already checked out for
  this scope); no cross-cutting or irreversible risk that isolation would
  mitigate.
- User decision: undecided
- Base ref: fix/test-canon-stat-portability
- Worktree branch/path: n/a (inline)
- Inline review scope: tests/skills/test-aai-test-canon.sh (lines 516, 536,
  722, 735 only)

## Acceptance Criteria Mapping
- Maps to: ISSUE-test-canon-stat-portability Verification bullet 1 (no
  `stat -f`-first mtime read remains)
- Spec-AC-01: All four mtime reads in `tests/skills/test-aai-test-canon.sh`
  (originally lines 516, 536, 722, 735) use GNU-first ordering
  `stat -c %Y "$f" 2>/dev/null || stat -f %m "$f" 2>/dev/null`, matching
  `tests/skills/test-aai-update.sh:245`.
- Verification: `grep -nE 'stat -f %m[^|]*\|\| *stat -c %Y' tests/skills/test-aai-test-canon.sh`
  returns no matches (exit 1 / empty output).

- Maps to: ISSUE-test-canon-stat-portability Verification bullet 2
  (non-regression on macOS)
- Spec-AC-02: The swap is behavior-preserving on macOS/BSD — the suite still
  passes locally after the change.
- Verification: `./tests/skills/test-aai-test-canon.sh` exits 0 on a macOS
  host.

- Maps to: ISSUE-test-canon-stat-portability Verification bullet 3
  (Linux/CI authoritative path)
- Spec-AC-03: The GNU-first read is exercised and green on the Ubuntu CI
  runner (the `skill-suite` job), which is authoritative for the Linux
  `stat -c` path this fix targets.
- Verification: `skill-suite` CI job status is `success` on the PR's Ubuntu
  run (GitHub Actions check).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                          | Status  | Evidence | Review-By | Notes |
|------------|-------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | 4 sites GNU-first stat -c, BSD stat -f fallback         | done | grep: 0 `stat -f`-first mtime reads, 4 GNU-first (commit on branch) | — | RC4 class |
| Spec-AC-02 | macOS non-regression                                   | done | `./tests/skills/test-aai-test-canon.sh` exit 0 on macOS | — | behavior-preserving swap |
| Spec-AC-03 | Linux CI (`skill-suite`) green                         | done | PR #121 skill-suite job success on Ubuntu (7m45s) | — | authoritative GNU-path check |

## Implementation plan
- Components/modules affected: `tests/skills/test-aai-test-canon.sh` only —
  4 mtime-read expressions inside TEST-011/TEST-012 drift-detection helpers
  (original lines 516, 536, 722, 735).
- Data flows: none — pure test-harness read of filesystem mtimes for
  drift-comparison assertions; no production code path touched.
- Edge cases: none beyond the existing BSD/GNU dual-path the pattern already
  handles; the swap only reorders which branch is tried first, so no new
  edge case is introduced. GNU `stat -f` on Linux means `--file-system`
  (succeeds with unrelated output) rather than erroring, which is exactly
  the bug this fix removes by trying `stat -c` first.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type | File path (expected)                     | Description                                                                 | Status  |
|----------|------------|------|-------------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | unit | tests/skills/test-aai-test-canon.sh       | `grep -nE 'stat -f %m[^\|]*\|\| *stat -c %Y' tests/skills/test-aai-test-canon.sh` returns no matches | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-test-canon.sh | `./tests/skills/test-aai-test-canon.sh` exits 0 on macOS after the swap | green |
| TEST-003 | Spec-AC-03 | integration | .github/workflows (skill-suite job) | `skill-suite` CI job on the PR's Ubuntu run reports `success` | green |

RED-proof note: TEST-001 is observably RED before the fix — the same grep
pattern (`stat -f %m[^|]*\|\| *stat -c %Y`) currently MATCHES all four sites
(confirmed: lines 516, 536, 722, 735); after the swap the pattern no longer
matches (GREEN). TEST-002/TEST-003 are non-regression checks on already-passing
suites (loop strategy — no new behavior to RED-prove; the fix is a pure
operand reorder verified equivalent on BSD by inspection and identical to the
already-shipped `test-aai-update.sh:245` pattern).

## Verification
- Commands to run:
  - `grep -nE 'stat -f %m[^|]*\|\| *stat -c %Y' tests/skills/test-aai-test-canon.sh` → expect empty/no matches
  - `./tests/skills/test-aai-test-canon.sh` → expect exit 0 (macOS)
  - CI `skill-suite` job on the PR → expect `success` (Ubuntu)
- Evidence artifacts: command output/log for each of the above, captured at
  Implementation hand-off and Validation.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status (done).

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: test-canon-stat-portability
- Spec-AC and TEST-xxx links where applicable
- command or review scope: tests/skills/test-aai-test-canon.sh (lines 516,
  536, 722, 735)
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

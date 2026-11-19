---
id: spec-precommit-sentinel-trap
type: spec
number: 302
status: done
mutation_gate: v1
frozen_sha256: 1448c9fcff69989f7f14f18311e360fb07ba7528108d1a428809bd9ca53f2b54
ceremony_level: 3
links:
  requirement: precommit-sentinel-trap
  rfc: null
  pr: []
  commits: []
---

# Pre-commit parse sentinel ignores the environment; trap fd close and the CHECK 3 window are pinned

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0123-precommit-sentinel-trap.md
  (follow-ups `fu-precommit-sentinel-env-init`,
  `fu-precommit-trap-fd-close-untested`, `fu-precommit-check3-open-window`;
  P3 each).
- Prior scope this one builds on (closed, not edited):
  docs/specs/SPEC-0301-spec-precommit-blob-read-cost.md (D5 scratch directory
  and EXIT trap, D13 parse-completed sentinel, TEST-3871 to TEST-3882).
- Sources: the independent code review r2 of PR #570 (R2-NB-1, R2-NB-2, kept
  out of the repository in the session scratchpad);
  docs/ai/validation/VALIDATION-precommit-blob-read-cost-r5.md NB-1, NB-2;
  VALIDATION-precommit-blob-read-cost-r3.md NB-A.
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: a guard on an L3 protected surface. The two sentinel defects
  are seen failing on the unchanged script (TEST-3883 and TEST-3884 exit 0
  with the staged secret unreported); the trap and CHECK 3 cases guard
  behaviour the script already has, so their failing observation is the
  mutation record, as the owner's brief asks. Not chosen at intake
  (autopilot); Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (`.aai/scripts/pre-commit-checks.sh`
  is in `protected_paths_l3`); the main checkout carries other sessions'
  uncommitted files.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: origin/main at 59ca96e2
- Worktree branch/path: fix/precommit-sentinel-trap at
  /Users/ales/Projects/aai-worktrees/precommit-sentinel-trap
- Review required: true
- Review scope (explicit paths): .aai/scripts/pre-commit-checks.sh;
  tests/skills/test-aai-pre-commit-checks.sh;
  docs/issues/ISSUE-0123-precommit-sentinel-trap.md;
  docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md.

## Decisions

- D1 (initialise the sentinel). `PCC_PARSED=0` is set next to `PCC_LIST=0`,
  before the staged-content block, so a value inherited from the
  environment never reaches the check. The check reads `"$PCC_PARSED"`
  without a `:-0` default (it is always set).
- D2 (key the sentinel on the repository, not on the list flag). The
  sentinel line becomes
  `[ "$IN_REPO" -eq 0 ] OR [ "$PCC_PARSED" -eq 1 ] OR staged_read_fail "parse did not complete"`
  (shell `||`). Keyed on `PCC_LIST`, an abort of the first block (scratch
  directory, list read) before `PCC_LIST=1` left `PCC_LIST` at 0, skipped the
  parse block and passed with no staged files: a mutant that aborts an
  arithmetic expansion just before `PCC_LIST=1` exits 0 with a staged secret
  on bash 3.2.57 and on bash 5.2.15 (Planning probe). `IN_REPO` is set by the
  script before any staged read, so every abort inside either block, from
  the scratch directory to the copy count, now blocks.
- D3 (audit of the same class). Every variable the staged-content block and
  CHECKs 2 to 4 read was checked for a read before an assignment in the
  script: `IN_REPO`, `PCC_TMP`, `PCC_LIST`, the four `STAGED*` arrays, `meta`,
  `nrec`, `size`, `sep`, `extra`, `ncopy`, `SECRETS_FOUND`, `DEBUG_FOUND`,
  `TODO_COUNT` and `name_check` are assigned first; `f`, `hdr`, `nul`,
  `nnames`, `hits`, `matches`, `count` are assigned by the command that reads
  them or fail closed when it fails. `PCC_PARSED` was the only one. The
  assignments `IN_REPO=0` and `PCC_LIST=0` are pinned by TEST-3875: without
  either, its non-repository run reads an unset variable under `set -u` and
  exits 1. TEST-3883 also exports `PCC_LIST=0` and `IN_REPO=0`; those equal
  the assigned values, so they show only that the inherited flags change
  nothing (amended after code review r1 NB-1).
- D4 (trap pin). The EXIT trap stays `rm -rf "$PCC_TMP" 3<&- 4<&-`. A blocked
  run at `ulimit -n 4`, `5` and `6` with a private `TMPDIR` must leave that
  directory empty; on bash 3.2.57 the mutant without the close leaves the
  scratch directory at 5 (Planning probe; bash 5.2.15 cleans up either way,
  so the case also pins the trap line by its text, and the behavioural
  assertion carries the kill on macOS).
- D5 (CHECK 3 window). `fu-precommit-check3-open-window` is closed by
  showing it cannot let a commit through, not by changing CHECK 3: every file
  CHECK 3 scans is also scanned by CHECK 4 (CHECK 3 skips `.md .yaml .yml
  .json .jsonl .txt .sh .ps1 .gitignore`, CHECK 4 skips `.md .yaml .yml .txt
  .sh .ps1`, a subset), and CHECK 4 re-tests the same copy with `-f`/`-r`
  and a numeric `grep -c`. A copy removed while CHECK 3 reads it therefore
  blocks the commit in CHECK 4 with `copy failed for <file>`. TEST-3886 pins
  that seam; a CHECK 4 that stops scanning `.js` reddens it.
- D6 (not folded in). `fu-precommit-index-race-block` asks for a retry
  policy (a design decision, not a defect) and stays open.
  `fu-pcc-other-builtin-redir` is a rewrite of CHECKs 1, 5, 6 and 9 outside
  the staged-content block and stays open.
- D7 (no consumer record). The change is internal hardening: no message,
  exit code or option changes for a run whose parse completes, so no
  CHANGELOG entry and no product doc.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to intake (1): an inherited `PCC_PARSED` cannot satisfy
  the sentinel (D1, D3).
- Spec-AC-02 maps to intake (1), the audit of the same class: an abort
  before the list flag is set still blocks (D2).
- Spec-AC-03 maps to intake (2): the trap's descriptor close is pinned (D4).
- Spec-AC-04 maps to the optional `fu-precommit-check3-open-window` (D5).
- Spec-AC-05 maps to preservation and the moved pins.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a copy of pre-commit-checks.sh without its leading-zero size check runs on a fixture staging a.txt and b.txt holding the api_key line, with a git wrapper that zero-pads the first cat-file header size and with PCC_PARSED=1, PCC_LIST=0 and IN_REPO=0 in the environment, the script SHALL exit 1, print no ALL CHECKS PASS or PASS WITH WARNINGS line, and its last stdout line SHALL be the single Staged content could not be read completely line naming parse did not complete | done | TEST-3883 red docs/ai/tdd/precommit-sentinel-trap/red-test_3883_sentinel_ignores_the_environment.log; TEST-3883 green docs/ai/tdd/precommit-sentinel-trap/green-test_3883_sentinel_ignores_the_environment.log and docs/ai/tdd/precommit-sentinel-trap/green-full-suite.log, mutation docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3883.txt; validation docs/ai/validation/VALIDATION-precommit-sentinel-trap-r1.md | — | D1, D3 |
| Spec-AC-02 | WHEN a copy of pre-commit-checks.sh whose first staged-content block aborts on an arithmetic expansion just before it sets PCC_LIST=1 runs on the same fixture, once with no extra environment and once with PCC_PARSED=1 in it, each run SHALL exit 1 with no passing summary and the single fail-closed line naming parse did not complete as its last stdout line | done | TEST-3884 red docs/ai/tdd/precommit-sentinel-trap/red-test_3884_sentinel_covers_an_abort_before_the_list.log; TEST-3884 green docs/ai/tdd/precommit-sentinel-trap/green-test_3884_sentinel_covers_an_abort_before_the_list.log and docs/ai/tdd/precommit-sentinel-trap/green-full-suite.log, mutation docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3884.txt; validation docs/ai/validation/VALIDATION-precommit-sentinel-trap-r1.md | — | D2 |
| Spec-AC-03 | WHEN a fixture staging a clean a.txt and b.txt holding the api_key line is checked under ulimit -n 4, 5 and 6 with TMPDIR set to an empty suite-owned directory, each run SHALL exit 1 with no passing summary and the directory SHALL hold no entry afterwards; the script SHALL contain the trap line trap 'rm -rf "$PCC_TMP" 3<&- 4<&-' EXIT | done | TEST-3885 green docs/ai/tdd/precommit-sentinel-trap/green-test_3885_trap_closes_descriptors_before_cleanup.log and docs/ai/tdd/precommit-sentinel-trap/green-full-suite.log, mutation docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3885.txt; validation docs/ai/validation/VALIDATION-precommit-sentinel-trap-r1.md | — | D4 |
| Spec-AC-04 | WHEN a grep shim on PATH removes the scratch copy of a staged app.js holding console.log at the moment CHECK 3 scans it, the script SHALL exit 1 with no passing summary and its last stdout line SHALL be the single fail-closed line naming copy failed for app.js | done | TEST-3886 green docs/ai/tdd/precommit-sentinel-trap/green-test_3886_check3_copy_removed_still_blocks.log and docs/ai/tdd/precommit-sentinel-trap/green-full-suite.log, mutation docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3886.txt; validation docs/ai/validation/VALIDATION-precommit-sentinel-trap-r1.md | — | D5 |
| Spec-AC-05 | bash tests/skills/test-aai-pre-commit-checks.sh SHALL exit 0, with TEST-3454 giving the 3e6b52d5 baseline's output on its seven fixtures and its numstat pin, and the TEST-3461 line-count pin, naming the new measured values; TEST-3873, TEST-3875, TEST-3880 and TEST-3882 SHALL stay green | done | TEST-3887 green docs/ai/tdd/precommit-sentinel-trap/green-test_3887_preservation_and_moved_pins.log and docs/ai/tdd/precommit-sentinel-trap/green-full-suite.log, mutation docs/ai/tdd/spec-precommit-sentinel-trap/mutation-TEST-3887.txt; validation docs/ai/validation/VALIDATION-precommit-sentinel-trap-r1.md | — | preservation |

## Implementation plan

- `.aai/scripts/pre-commit-checks.sh`:
  - after `PCC_LIST=0`: `PCC_PARSED=0` (D1);
  - the sentinel line keyed on `IN_REPO` and reading `"$PCC_PARSED"` (D2);
  - the comment above `staged_read_fail` and above the sentinel says what
    the sentinel compares (an initialised flag, keyed on the repository);
  - a comment at CHECK 4's skip list states that it must stay a subset of
    CHECK 3's (D5).
- `tests/skills/test-aai-pre-commit-checks.sh`: TEST-3883 to TEST-3887 wired
  into `main()`; TEST-3883 and TEST-3884 reuse the `sizepad` wrapper mode and
  `run_with`'s `VAR=value` arguments; TEST-3885 uses `RUN_ULIMIT_N`; TEST-3886
  uses a grep shim like TEST-3882. Re-pin TEST-3454 numstat and TEST-3461
  counts to the measured values and extend their history comments; update
  the suite header's TEST range.
- Seams crossed: the environment of the committing process reaches the
  script (the installed hook and `hook-gate.mjs` both run it with the
  caller's environment, so TEST-3883 sets the flags exactly where a caller
  would); CHECK 3 and CHECK 4 read the same scratch copy (TEST-3886).
- Bash 3.2 under `set -euo pipefail`; GNU and BSD userland; no new external
  command in the script.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3883 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | TEST-3873's leading-zero mutant and sizepad wrapper, run with PCC_PARSED=1 PCC_LIST=0 IN_REPO=0 in the environment: exit 1, no summary, the single fail-closed line names parse did not complete; RED on the unchanged script (exit 0, PASS WITH WARNINGS) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\nPCC_PARSED=0(?=\n)//` removes the initialisation so the inherited value satisfies the sentinel and the case must fail | green |
| TEST-3884 | Spec-AC-02 | integration | tests/skills/test-aai-pre-commit-checks.sh | a copy of the script with `: $((08));` inserted before `PCC_LIST=1`, run without and with PCC_PARSED=1: each exits 1 with the single fail-closed line naming parse did not complete; RED on the unchanged script (exit 0 both times) | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\[ "\$IN_REPO" -eq 0 \] (?=\x7c\x7c \[ "\$PCC_PARSED")/[ "$PCC_LIST" -eq 0 ] /` keys the sentinel on the list flag again and the case must fail | green |
| TEST-3885 | Spec-AC-03 | integration | tests/skills/test-aai-pre-commit-checks.sh | blocked runs (staged secret) at ulimit -n 4, 5 and 6 with a private TMPDIR leave it empty; the trap line is in the script; green on the unchanged script by design, the failing observation is the mutation record | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/ 3<&- 4<&-' EXIT/' EXIT/` drops the descriptor close from the trap and the case must fail | green |
| TEST-3886 | Spec-AC-04 | integration | tests/skills/test-aai-pre-commit-checks.sh | a grep shim removes every scratch copy on its first call whose pattern is CHECK 3's (console.log); the staged app.js holds console.log: exit 1, single fail-closed line naming copy failed for app.js; green on the unchanged script by design (CHECK 4 re-checks the copy), the failing observation is the mutation record | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/(\*\.txt\x7c\*\.sh\x7c)\*\.ps1\) continue/$1*.ps1) continue ;; *.js) continue/` makes CHECK 4 skip .js files and the case must fail | green |
| TEST-3887 | Spec-AC-05 | integration | tests/skills/test-aai-pre-commit-checks.sh | runs TEST-3454 (parity and re-pinned numstat), TEST-3461 (re-pinned line counts), TEST-3873, TEST-3875, TEST-3880 and TEST-3882 by selector; each exits 0 | target `tests/skills/test-aai-pre-commit-checks.sh`; `sed:s/\[\[ "\$numstat" == "/[[ "$numstat" == "9/` breaks the moved numstat pin and the case must fail | green |

RED observations: TEST-3883 and TEST-3884 are written first and run against
the unchanged script; their failing runs are stored as
`red-<selector>.log` under `docs/ai/tdd/precommit-sentinel-trap/`.
TEST-3885, TEST-3886 and TEST-3887 guard behaviour the script already has;
their failing observation is the mutation record under
`docs/ai/tdd/spec-precommit-sentinel-trap/`.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
- `/bin/bash -n .aai/scripts/pre-commit-checks.sh`; the new cases run under
  `/bin/bash` 3.2.57 on macOS; GNU userland and bash 5 through CI (Ubuntu).
- `node .aai/scripts/mutation-run.mjs --replay --spec docs/specs/SPEC-0302-spec-precommit-sentinel-trap.md`
- One full sweep before close (`AAI_TEST_TIMEOUT=3600`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `precommit-sentinel-trap`, Spec-AC and TEST-xxx,
command, exit code, evidence path under
`docs/ai/tdd/precommit-sentinel-trap/` (RED and GREEN logs) and
`docs/ai/tdd/spec-precommit-sentinel-trap/` (mutation records), commit SHA
once committed.

Registry items closed by this scope: fu-precommit-sentinel-env-init, fu-precommit-trap-fd-close-untested, fu-precommit-check3-open-window

## Residual risks

- The trap mutant is killed by behaviour only on bash 3.2 (macOS); on bash 5
  the text pin is what kills it, because bash 5 removes the scratch directory
  either way.
- TEST-3886 uses `.js`; a later CHECK 4 skip-list change for another
  extension that CHECK 3 scans would not be caught by it. The subset
  relation is stated in a comment next to CHECK 4's skip list.
- Windows (Git Bash) runs of the suite are not part of CI.

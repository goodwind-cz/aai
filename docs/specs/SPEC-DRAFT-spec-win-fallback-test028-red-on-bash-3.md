---
id: spec-win-fallback-test028-red-on-bash-3
type: spec
number: null
status: implementing
frozen_sha256: 61a574eb216b82f85d904ef20a5c7a3829204cfe8f350f2b5dd25c6e6bb098e9
ceremony_level: 1
links:
  requirement: null
  rfc: null
  intake: docs/issues/ISSUE-DRAFT-win-fallback-test028-red-on-bash-3.md
  pr: []
  commits: []
---

# Spec — TEST-028 skips only its execution arm on a bash older than 4

SPEC-FROZEN: true

Ceremony justification: test-only change to one function and one new pin in one bash suite (tests/skills/test-aai-win-fallback.sh); no product code, no protected path, no schema; a wrong guard fails closed to the existing behaviour (the arm runs).

## Links
- Requirement: docs/issues/ISSUE-DRAFT-win-fallback-test028-red-on-bash-3.md (issue id `win-fallback-test028-red-on-bash-3`)
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md (bash suites under `tests/skills/`)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: direct
- Rationale: one test function in one suite plus one pin. The ACs are decided by the suite's own exit code and output on this host (bash 3.2.57) and by a stubbed-version pin that runs on any host. A stored RED artifact buys nothing beyond the issue's reproduction, which is already on record; the Mutation cells are a targeted regression check.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride under /aai-ship; the orchestrator already created the worktree.
- User decision: worktree
- Base ref: origin/main (ebc5d72b)
- Worktree branch/path: fix/win-fallback-test028-red-on-bash-3 at /Users/ales/Projects/aai-fix-win-fallback-test028-red-on-bash-3
- Inline review scope: tests/skills/test-aai-win-fallback.sh, docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md

## Design decisions

- D1. The bash major is read from the interpreter the wrapper will invoke: the helper `win_fallback_invoked_bash_major` runs `bash -c 'printf %s "${BASH_VERSINFO[0]}"'` with the same environment and PATH word `bash` that `test_028` hands to `aai-run-tests.sh` (`bash "$RUN_TESTS_SCRIPT" bash "$suite"`). It never reads `BASH_VERSINFO` of the test process.
- D2. The decision is a separate helper `win_fallback_exec_arm_decision <major>` that prints `skip` when the argument is all digits and below 4, and `run` in every other case (4 or more, empty, non-numeric). An unreadable version fails closed to `run`: the arm is never skipped on a guess.
- D3. Only the execution arm is gated. The four in-process translation asserts (git-bash path, windows path, `C:/` spelling, plain token) run on every host before the gate. On `skip`, `test_028` prints a line starting `SKIP: TEST-028 execution arm` that names the invoked bash version and the reason (bash older than 4 has no `command_not_found_handle`; Git Bash and CI are bash 5), cleans nothing it did not create, and returns 0. It does not call `log_skip`, which exits 42 and would end the whole suite. This is the pattern of the pwsh-absent named skips in the same file.
- D4. On `run`, the existing execution arm and its pass line `TEST-028 Windows Python path translated in-process and executed under Git Bash` stay byte for byte unchanged.
- D5. No environment override is added. The bash 4 or newer arm is proven on a bash 3 host by redefining the two helpers inside a subshell in the new pin (functions of the sourced suite are overridable in-process); the full green of the real arm is proven by CI (Ubuntu, bash 5) and by any host with Homebrew bash first on PATH.

## Seams this change crosses

- SEAM-1: the version the guard reads versus the interpreter that actually runs the sentinel suite. Crossed by TEST-002: a stub `bash` first on PATH reporting a different major is read by the helper, and `test_028` under that stub takes the matching branch.
- SEAM-2: the guard versus the pass line CI and the sweep depend on. Crossed by TEST-001 (this host prints the SKIP line, not the pass line) and by the CI run on this PR (bash 5 prints the pass line, no SKIP line).

## Acceptance Criteria Mapping
- Maps to: intake Expected Behavior bullet 1 and Verification bullet 1. Spec-AC-01, verified by TEST-001.
- Maps to: intake Expected Behavior bullets 2 and 3, Verification bullets 2 and 3, and Constraints (narrow skip). Spec-AC-02 and Spec-AC-03, verified by TEST-002 and TEST-003.
- Maps to: intake Constraints (no product code change). Spec-AC-04, verified by TEST-004.

Spec-AC-01: WHEN `test-aai-win-fallback.sh 028` runs on a host whose PATH bash is older than 4, the suite exits 0, its output contains a line starting `SKIP: TEST-028 execution arm` with the bash version, and it does not contain `FAIL python path`.
Verification: `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028; echo rc=$?` on this host (bash 3.2.57) prints rc=0 and the SKIP line; `grep -c 'executed under Git Bash'` of the output is 0.

Spec-AC-02: WHEN the invoked bash major is 4 or more, or cannot be read, `test_028` runs the execution arm unchanged and prints no `SKIP: TEST-028` line; WHEN it is below 4 it prints the SKIP line and runs no wrapper.
Verification: the new pin `test_042` redefines `win_fallback_invoked_bash_major` to print 3, 4, 5 and empty in turn inside a subshell and captures `test_028` output; for 3 the exit code is 0 and the SKIP line is present; for 4, 5 and empty the SKIP line is absent (the arm was reached; on this bash 3 host it then fails with the wrapper message, which the pin tolerates only by checking the SKIP line, not the exit code). A stub `bash` first on PATH printing 5 makes the real helper return 5.

Spec-AC-03: WHEN the guard is skipped or the arm is skipped unconditionally, the suite goes red on every host: the translation asserts run before the gate on every branch.
Verification: `test_042` asserts that with the version forced to 3 the output carries the line `PASS` of no execution arm and that a deliberately broken `aai_to_git_bash_path` (redefined to echo its input) makes `test_028` exit 1 even on the skip branch.

Spec-AC-04: WHEN the diff of this scope is read, no file under `.aai/` and no file other than tests/skills/test-aai-win-fallback.sh and this spec's own docs is changed.
Verification: `git diff --name-only origin/main...HEAD` lists only tests/skills/test-aai-win-fallback.sh, docs/specs/SPEC-*-spec-win-fallback-test028-red-on-bash-3.md, the intake and generated index and telemetry files; none under `.aai/`.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description | Status  | Evidence | Review-By | Notes |
|------------|-------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN the PATH bash is older than 4 the suite exits 0 and prints the named TEST-028 execution-arm SKIP line | done | `docs/ai/tdd/spec-win-fallback-test028-red-on-bash-3/mutation-TEST-001.txt` (regression check) + `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` exit 0 | — | — |
| Spec-AC-02 | WHEN the invoked bash major is 4 or more or unreadable the arm runs unchanged, WHEN below 4 it is skipped by name | done | `docs/ai/tdd/spec-win-fallback-test028-red-on-bash-3/mutation-TEST-002.txt` (regression check) + `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` exit 0 | — | — |
| Spec-AC-03 | WHEN the arm is skipped the in-process translation asserts still ran and still fail the suite on a break | done | `docs/ai/tdd/spec-win-fallback-test028-red-on-bash-3/mutation-TEST-003.txt` (regression check) + `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` exit 0 | — | — |
| Spec-AC-04 | WHEN the diff is read only the one suite and spec docs changed, no product code | done | `docs/ai/tdd/spec-win-fallback-test028-red-on-bash-3/mutation-TEST-004.txt` (regression check) + `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` exit 0 | — | TEST-004 mutation expression in the Test Plan cell is not valid in the runner grammar (unescaped slash); recorded with `s/\^\\\.aai\//^\\.nothing\//` |

## Implementation plan
- tests/skills/test-aai-win-fallback.sh: add the two helpers `win_fallback_invoked_bash_major` and `win_fallback_exec_arm_decision` directly above `test_028`; in `test_028` insert the gate after the translation asserts and before the `root`/`exe`/`suite` fixture; keep the arm and pass line unchanged; add `test_042` after `test_041` and append `042` to `ALL_TESTS`.
- Edge cases: PATH has no `bash` (the file's `check_deps` already stops); the probe prints nothing or noise (D2 fails closed to run); the sentinel arm leaves no temp files on the skip branch because the fixture is created after the gate.
- Companion obligations: adds no prompt-corpus bytes and no new `.aai/**` file; neither applies.

## Test Plan

Every row is a function in `tests/skills/test-aai-win-fallback.sh`, run as `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh <NNN>`. Under the `direct` strategy the mutation observation is a targeted regression check; storing it is optional.

| Test ID  | Spec-AC    | Type        | File path (expected) | Description | Mutation | Status  |
|----------|------------|-------------|----------------------|-------------|----------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-win-fallback.sh | test_028 on the real host: exit 0 on bash 3, SKIP line with version present, pass line absent; on bash 4 or newer the pass line present and no SKIP line | sed:s/== skip \]\]/== never ]]/ | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-win-fallback.sh | test_042: forced majors 3, 4, 5 and empty through the subshell redefinition; SKIP line only for 3; a stub bash printing 5 first on PATH is read by the real helper | sed:s/-lt 4/-lt 99/ | green |
| TEST-003 | Spec-AC-03 | unit        | tests/skills/test-aai-win-fallback.sh | test_042: with the version forced to 3 and aai_to_git_bash_path redefined to echo its input, test_028 exits 1 (translation asserts precede the gate) | sed:s/\[\[ "\$gb" == "\/c\/proj\/.venv\/Scripts\/python.exe" \]\]/true/ | green |
| TEST-004 | Spec-AC-04 | unit        | tests/skills/test-aai-win-fallback.sh | test_042: git diff --name-only against origin/main, when that ref exists, names no path under .aai/; absent ref is a named skip | sed:s/\^\\.aai\\//^\\.nothing\\// | green |

Test status values: pending → red → green

Counts: 4 rows, all in one file. Unit 3 (TEST-002 to TEST-004), integration 1 (TEST-001). Seams crossed: SEAM-1 by TEST-002, SEAM-2 by TEST-001 and the CI run.

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh 028 042` exits 0 on this host.
- `env -u AAI_ROLE bash tests/skills/test-aai-win-fallback.sh` (whole suite) exits 0 on this host.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-win-fallback-test028-red-on-bash-3.md` shows no errors.
- PASS: TEST-001 to TEST-004 green and Spec-AC-01 to Spec-AC-04 done; CI (bash 5) prints the TEST-028 pass line.

## Evidence contract
For each implementation, validation and code review artifact, record: ref_id, the Spec-AC and TEST links, the command, the exit code, the evidence path, and the commit SHA or diff range.

### Evidence by strategy

| Strategy     | Evidence this spec may demand |
|--------------|-------------------------------|
| direct       | targeted regression tests green (exit codes) plus the scoped diff, no stored RED artifact |

## Registry items closed by this scope

Source: `node .aai/scripts/follow-ups.mjs list`, read on 2026-10-10 and scanned for win-fallback, test028, bash and macOS subjects.

Closes: `fu-win-fallback-test028-local-macos` (P3).

NOT CLOSED: `fu-msys-direct-run-misses-exec-grandkids` (P3) names the same wrapper family but a different subject (Job Object on a direct Git Bash run); not touched.

## Residual risks
- The bash 4 or newer arm is not executed to green on this host (no Homebrew bash). It is proven by CI on bash 5 and by the stubbed-version pin that shows the arm is reached; a defect that only shows when the real arm runs under bash 4 is caught by CI, not here.
- The probe reads the first `bash` on PATH; a wrapper that resolves its command word differently from the test would read the wrong interpreter. Today both use the bare word `bash` on the same PATH.

Notes:
This document defines HOW, not WHAT/WHY.

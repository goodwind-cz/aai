---
id: SPEC-0009
type: spec
status: done
links:
  requirement: null
  rfc: null
  issue: ISSUE-0002
  pr: []
  commits: []
---

# SPEC-0009 — Test Process-Group Reaping, Bounded Forks, and Leak Accounting (aai-loop hardening)

SPEC-FROZEN: true

## Links
- Parent issue (WHAT/WHY + observed symptom + proven root cause + prioritized 5-part fix): docs/issues/ISSUE-0002-aai-loop-leaks-hung-vitest-process-trees.md
- Framework invariant operationalized here: docs/knowledge/LEARNED.md (2026-07-01 — every externally-spawned process must be in a killable group, resource-bounded, reaped on the step boundary, and accounted for)
- Wiring points made leak-safe: .aai/SKILL_LOOP.prompt.md, .aai/VALIDATION.prompt.md, .aai/system/DYNAMIC_SKILLS.md, .aai/SKILL_BOOTSTRAP.prompt.md, .aai/scripts/aai-bootstrap.sh
- Style reference for the bash test harness: tests/skills/test-aai-docs-lock.sh, tests/skills/test-aai-orchestration-mode.sh
- Technology contract: docs/TECHNOLOGY.md (this repo: no manifest; own tests are bash/Pester — the wrapper/reaper are POSIX sh, unit-testable cross-platform)

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in ISSUE-0002)
A long `/aai-loop` orphans hung `vitest` process trees (~40 trees / ~5.6 GB observed
after a 17+ tick run). Root cause (proven in ISSUE-0002): `vitest run` does not exit
when a suite leaves open handles; the launching agent's `Bash` call returns with output
captured, but nothing kills the spawned process GROUP, so the hung tree is orphaned.
Compounded by fork-pool workers sized to CPU count (~150 MB each). The leak is silent
(no error surfaced) and grows unbounded across ticks.

This spec operationalizes the LEARNED framework invariant: every externally-spawned
process must be (a) in its own killable process group, (b) resource-bounded, (c) reaped
on the step boundary (scoped to `$PWD`+etime, NEVER global), and (d) accounted for in
the tick log. It ships fixes #1–#4 from ISSUE-0002 (all in THIS AAI-framework repo).
Fix #5 (fixing the open-handle suites) is TARGET-PROJECT-specific — this repo has no
vitest — and is explicitly OUT OF SCOPE here.

## Design decisions (load-bearing — read before implementing)

### D1 — Wrapper lives at `.aai/scripts/aai-run-tests.sh` (NOT top-level `scripts/`)
ISSUE-0002 wrote the shorthand `scripts/aai-run-tests.sh`. Planning overrides the
location to `.aai/scripts/aai-run-tests.sh` because `aai-sync` vendors ONLY `.aai/`
subtrees into target projects and actively REMOVES a legacy top-level `scripts/`
(see .aai/scripts/aai-sync.sh lines 36–45 and the legacy-cleanup block ~123–145). A
top-level `scripts/aai-run-tests.sh` would never reach a bootstrapped target project, so
fix #2 (bootstrap routing generated commands through the wrapper) could not work. Placing
it under `.aai/scripts/` matches every other AAI script (`docs-lock.mjs`,
`orchestration-mode.mjs`, `aai-bootstrap.sh`) and guarantees it is vendored/synced.

### D2 — Wrapper contract (`.aai/scripts/aai-run-tests.sh <cmd> [args...]`)
POSIX `sh`, macOS + Linux (NO GNU `timeout` on macOS — inline watchdog only). It:
1. Starts a NEW process group (`set -m`) so the child and all its descendants share one
   killable process-group id (pgid).
2. Runs the given command (`"$@"`) as that group leader in the background; captures its
   pgid.
3. Arms an inline watchdog: after `AAI_TEST_TIMEOUT` seconds (default 300) it sends
   `TERM` to the whole group `-<pgid>`.
4. `wait`s for the command; records its REAL exit status.
5. Kills the watchdog, then ALWAYS sends `TERM` (then, after a short grace, `KILL`) to the
   whole group `-<pgid>` on EVERY exit path (success / failure / timeout), reaping hung
   descendants (vitest workers, esbuild).
6. Exits with the command's real exit code on normal completion; exits `124` (GNU-timeout
   convention) when the watchdog fired. A leaky child that backgrounds work and exits 0
   yields exit 0 AND no survivors.
Invariant: a command launched via the wrapper can NEVER outlive the wrapper call — on
return, no descendant of the spawned group is still resident.

### D3 — Reaper contract (`.aai/scripts/aai-reap-tests.sh`) — workspace-scoped, etime-guarded
POSIX defence-in-depth reaper the loop runs AFTER a test-running tick. It kills ONLY
this-workspace survivors and NEVER reaps globally:
- Match set: processes whose command line matches `vitest`/`esbuild` AND contains the
  current workspace path (`$PWD`, overridable via `AAI_REAP_WORKSPACE` for testability).
- Concurrency guard: under concurrent subagents it reaps only trees OLDER than the step's
  start time — the caller passes a start threshold (`AAI_REAP_MIN_AGE_SECS` or an
  explicit start-epoch); a matching process younger than the threshold (a sibling's
  in-flight run) is NEVER killed.
- It is a no-op (exit 0) when nothing matches; it prints the count of reaped trees so the
  loop can log it. It uses only workspace+etime-scoped matching — never a bare
  `pkill -f vitest`.

### D4 — Loop/skill routing + accounting (fix #4)
The loop and every test-running role route test/build commands THROUGH the wrapper and
never invoke `vitest`/`tsc`/dev-servers directly:
- `.aai/SKILL_LOOP.prompt.md`: (a) a PRE-FLIGHT count of workspace `vitest`/`esbuild`
  procs at loop start — if over a threshold (default 5) `log()` a warning and run the
  scoped reaper (a prior run's leak must not compound); (b) after each test-running tick,
  run the scoped reaper; (c) record `lingering_procs` and `free_memory` in the tick log
  line (LOOP_TICKS.jsonl), mirroring the existing token/cost discipline so a leak is
  visible, not silent.
- `.aai/VALIDATION.prompt.md`: discovered test commands run through the wrapper; reap on
  the step boundary.
- `.aai/system/DYNAMIC_SKILLS.md`: documents that generated `aai-test-*` skills route
  through the wrapper.
This half is partly PROCESS (a live LLM loop actually invoking the wrapper); the testable
core is the wrapper/reaper scripts (D2/D3) plus the presence of this wiring text, asserted
by grep exactly as SPEC-0004/SPEC-0005 handled their prompt wiring.

### D5 — Bootstrap emits leak-safe defaults (fix #2)
This repo has no vitest, so #2 is (a) a change to `.aai/scripts/aai-bootstrap.sh` so
GENERATED projects are leak-safe by construction, and (b) documented guidance:
- The generated `aai-test-unit` / `aai-test-e2e` SKILL.md command is WRAPPED — the
  detected command (e.g. `npm exec vitest run`) is emitted as
  `.aai/scripts/aai-run-tests.sh npm exec vitest run` (the wrapper is vendored by
  aai-sync, so the path resolves in the target). Prefer safe-by-construction over
  post-hoc remediation.
- When a vitest project is detected, bootstrap emits documented leak-safe vitest guidance
  (`pool: 'forks'`, `poolOptions.forks.maxForks: 2, minForks: 1`, `teardownTimeout:
  10_000`) so a single run is bounded to ~300–400 MB instead of ~1.5 GB. Bootstrap does
  NOT overwrite an existing user vitest config (safety rule); guidance is emitted in the
  generated skill/marker, and applying it to the config is the operator's action.

### D6 — What is deliberately OUT OF SCOPE
- Fix #5 (repairing open-handle suites; `test.dangerouslyIgnoreUnhandledErrors=false`) is
  target-project work — no vitest exists in this repo. The LEARNED candidate rule is
  already recorded; landing #5 belongs to a target project's own loop.
- The wrapper/reaper do NOT parse STATE or specs, hold no clock beyond the watchdog, and
  make no network calls — they are pure process-lifecycle utilities, fully unit-testable.

## Implementation strategy
- Strategy: hybrid
- Rationale: the wrapper (`aai-run-tests.sh`) and reaper (`aai-reap-tests.sh`) are the
  load-bearing safety core — their invariant is "a spawned test process can never outlive
  the step, and a reap is workspace+etime scoped, never global." That demands TDD with a
  REAL RED: the no-survivor and scope tests must be observed FAILING against a deliberately
  naive stub — a wrapper that just runs `"$@"` without group-kill LEAVES the leaky child
  resident; a reaper that does a bare `pkill -f vitest` kills a NON-matching sibling — before
  the real scripts turn them GREEN (a safety test never seen failing proves nothing; mirrors
  SPEC-0004 TEST-003's non-O_EXCL stub and SPEC-0005 TEST-003's overlap-blind stub). So
  Spec-AC-01..06 (TEST-001..006) are TDD. The loop/validation/dynamic-skills/bootstrap/docs
  wiring (Spec-AC-07..11, TEST-007..011) is low-risk prose + generator wiring where
  RED-GREEN adds little beyond a grep assertion (TEST-010 still carries a RED-proof: the
  pre-change bootstrap emits a BARE, unwrapped command), so it runs as a loop segment.
  Hybrid = TDD for the two scripts, loop for the wiring/bootstrap/docs.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: additive change — two new POSIX scripts
  (`.aai/scripts/aai-run-tests.sh`, `.aai/scripts/aai-reap-tests.sh`), one new bash test
  harness (`tests/skills/test-aai-run-tests.sh`), a generator edit
  (`.aai/scripts/aai-bootstrap.sh`), and by-addition edits to protected workflow prompts
  (`SKILL_LOOP`, `VALIDATION`, `DYNAMIC_SKILLS`, `SKILL_BOOTSTRAP`) plus a user-doc note.
  No STATE migration, no schema-breaking change, no cross-cutting refactor. The work
  already sits on the dedicated feature branch `fix/issue-0002-test-process-leaks` off
  main, which isolates it; every edit is trivially reversible and the scripts are new
  files. A separate git worktree would add ceremony without added safety, so isolation is
  useful-but-not-required. It touches protected workflow prompts, but only by addition —
  hence `optional` rather than `not_needed`.
- User decision: inline (recommendation is `optional`, so no blocking user decision;
  proceed inline on `fix/issue-0002-test-process-leaks`)
- Base ref: main
- Worktree branch/path: n/a (inline on fix/issue-0002-test-process-leaks)
- Inline review scope:
  - `.aai/scripts/aai-run-tests.sh`
  - `.aai/scripts/aai-reap-tests.sh`
  - `tests/skills/test-aai-run-tests.sh`
  - `.aai/scripts/aai-bootstrap.sh`
  - `.aai/SKILL_LOOP.prompt.md`
  - `.aai/VALIDATION.prompt.md`
  - `.aai/system/DYNAMIC_SKILLS.md`
  - `.aai/SKILL_BOOTSTRAP.prompt.md`
  - `docs/USER_GUIDE.md`
  - `docs/specs/SPEC-0009-test-process-group-reaping-and-leak-accounting.md`

## Acceptance Criteria Mapping

- Maps to: ISSUE-0002 fix #1 (wrapper — load-bearing) + Expected Behavior (real exit code)
  - Spec-AC-01: `.aai/scripts/aai-run-tests.sh <cmd...>` exists as a POSIX sh wrapper that
    runs the command in its own process group and returns the command's REAL exit code —
    a succeeding command yields exit 0, a failing command yields its non-zero code.
  - Verification: TEST-001.

- Maps to: ISSUE-0002 fix #1 + Verification (leaky suite → no survivors) — the SAFETY core
  - Spec-AC-02: a deliberately-leaky command (backgrounds a long-lived `sleep`/open handle
    then exits) launched via the wrapper returns PROMPTLY and leaves NO descendant of the
    spawned group resident (`pgrep` for the child's marker is empty after the wrapper
    exits). RED-proofed against a group-kill-less stub wrapper (leaky child survives).
  - Verification: TEST-002 (RED-proofed vs a no-group-kill stub).

- Maps to: ISSUE-0002 fix #1 + Verification (timeout path)
  - Spec-AC-03: a never-exiting command under a short `AAI_TEST_TIMEOUT` is killed at the
    timeout — the wrapper returns within ~timeout, exits non-zero (`124`), and leaves no
    survivors.
  - Verification: TEST-003.

- Maps to: ISSUE-0002 Expected Behavior (exit-code fidelity distinguishes fail vs timeout)
  - Spec-AC-04: exit-code fidelity — success → 0; a command exiting `N` (N≠0) → wrapper
    exits `N`; a timeout → wrapper exits `124` (distinct from an ordinary test failure so
    the loop can tell "hung" from "failed").
  - Verification: TEST-004.

- Maps to: ISSUE-0002 fix #3 (scoped reaper) + Constraints (workspace-scoped, never global)
  - Spec-AC-05: `.aai/scripts/aai-reap-tests.sh` kills ONLY processes matching
    `vitest`/`esbuild` AND the current workspace path; a matching process in the workspace
    is reaped, a NON-matching process (different marker / different workspace) SURVIVES.
    RED-proofed against a bare `pkill -f vitest` stub (kills the non-matching sibling too).
  - Verification: TEST-005 (RED-proofed vs a global-pkill stub).

- Maps to: ISSUE-0002 fix #3 (etime guard under concurrent subagents)
  - Spec-AC-06: the reaper's concurrency guard reaps only trees OLDER than the supplied
    step-start threshold — a fresh matching process younger than the threshold (a sibling's
    in-flight run) is NOT killed; an older matching process IS reaped.
  - Verification: TEST-006.

- Maps to: ISSUE-0002 fix #4 (loop routing, pre-flight count, tick accounting)
  - Spec-AC-07: `.aai/SKILL_LOOP.prompt.md` routes test commands through
    `aai-run-tests.sh` (never vitest/tsc directly), performs a pre-flight workspace
    `vitest`/`esbuild` count with a warn+reap over threshold, runs the scoped reaper after
    a test-running tick, and records `lingering_procs`/`free_memory` in the tick log.
  - Verification: TEST-007 (grep SKILL_LOOP).

- Maps to: ISSUE-0002 fix #4 (validation routes through wrapper + reaps on boundary)
  - Spec-AC-08: `.aai/VALIDATION.prompt.md` runs discovered test commands through
    `aai-run-tests.sh` and reaps workspace survivors on the step boundary.
  - Verification: TEST-008 (grep VALIDATION).

- Maps to: ISSUE-0002 fix #4 (dynamic test skills route through wrapper)
  - Spec-AC-09: `.aai/system/DYNAMIC_SKILLS.md` documents that generated `aai-test-*`
    skills route their command through `.aai/scripts/aai-run-tests.sh`.
  - Verification: TEST-009 (grep DYNAMIC_SKILLS).

- Maps to: ISSUE-0002 fix #2 (bootstrap emits leak-safe, wrapper-routed defaults)
  - Spec-AC-10: `.aai/scripts/aai-bootstrap.sh` emits generated `aai-test-*` SKILL
    commands WRAPPED via `.aai/scripts/aai-run-tests.sh`, and emits documented leak-safe
    vitest guidance (`pool: 'forks'`, `maxForks: 2`, `teardownTimeout`) when vitest is
    detected — without overwriting an existing user vitest config. RED-proofed: the
    pre-change generator emits a BARE `npm exec vitest run`.
  - Verification: TEST-010 (RED-proofed against the pre-change bare command).

- Maps to: ISSUE-0002 Notes / LEARNED invariant (make the four-part contract discoverable)
  - Spec-AC-11: user-facing docs (`docs/USER_GUIDE.md` and/or `SKILL_BOOTSTRAP` guidance)
    document the leak-safe test contract — wrapper (killable group + timeout), bounded
    forks, scoped reaper (workspace+etime, never global), and tick-log accounting.
  - Verification: TEST-011 (grep USER_GUIDE / SKILL_BOOTSTRAP).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | aai-run-tests.sh exists; runs cmd in own process group; returns REAL exit code (0 on success, N on failure) | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z (sonnet-4-6, exit 0); indep-repro: exit 0 and exit 7 both correct | — | TDD |
| Spec-AC-02 | leaky child launched via wrapper → prompt return AND no descendant survives (SAFETY) | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: leaky bash -c '(exec -a marker sleep 600)&exit 0' → pgrep empty after return (PASS) | — | TDD; RED-proof vs no-group-kill stub |
| Spec-AC-03 | never-exiting cmd killed at AAI_TEST_TIMEOUT → wrapper exits non-zero (124), no survivors | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: AAI_TEST_TIMEOUT=3 → exit 124, no survivors (PASS) | — | TDD |
| Spec-AC-04 | exit-code fidelity: 0 / passthrough N / 124 on timeout (fail distinguishable from hung) | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: 0/7/124 all correct (PASS) | — | TDD |
| Spec-AC-05 | reaper kills only vitest/esbuild matching $PWD; non-matching survives (SAFETY) | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: matching pid reaped, other-workspace sibling survived (PASS); no bare pkill in script | — | TDD; RED-proof vs global-pkill stub |
| Spec-AC-06 | reaper etime guard: fresh sibling (younger than step-start) NOT reaped; older IS | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: old pid reaped, fresh sibling survived (PASS) | — | TDD; concurrency safety |
| Spec-AC-07 | SKILL_LOOP routes via wrapper + preflight count/warn/reap + tick-log lingering_procs/free_memory | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; grep confirms all 5 strings in SKILL_LOOP.prompt.md | — | loop; partly process (D4) |
| Spec-AC-08 | VALIDATION runs discovered tests via wrapper + reaps on step boundary | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; grep confirms aai-run-tests.sh + aai-reap-tests.sh in VALIDATION.prompt.md | — | loop; partly process |
| Spec-AC-09 | DYNAMIC_SKILLS documents generated aai-test-* route through the wrapper | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; grep confirms aai-run-tests.sh in DYNAMIC_SKILLS.md | — | loop |
| Spec-AC-10 | bootstrap emits wrapper-routed test command + leak-safe vitest guidance; no config overwrite | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; indep-repro: bootstrap on vitest fixture → wrapped cmd + maxForks + pool:forks + teardownTimeout; user config unchanged | — | loop; RED-proof vs pre-change bare command |
| Spec-AC-11 | USER_GUIDE / SKILL_BOOTSTRAP document the 4-part leak-safe test contract | done | docs/ai/tdd/green-spec0009-20260701T100103Z.log; val:2026-07-01T10:06:39Z; grep confirms all 6 required strings in USER_GUIDE.md | — | loop |

Status values: planned | implementing | done | deferred | blocked | rejected (per template).

## Implementation plan
- Components/modules affected:
  - NEW `.aai/scripts/aai-run-tests.sh`: POSIX sh. `set -m`; `AAI_TEST_TIMEOUT` (default
    300); run `"$@"` as background group leader; inline watchdog sends `TERM -<pgid>` at
    timeout; `wait` captures real status; always `TERM` then grace then `KILL` the whole
    group on every exit path; exit real status, or `124` on timeout. Header usage block +
    `set -eu` discipline consistent with existing `.sh` scripts. Must portably derive the
    child's pgid on macOS + Linux (no `setsid` on macOS — use `set -m` job control / a
    subshell group).
  - NEW `.aai/scripts/aai-reap-tests.sh`: POSIX sh. Inputs: workspace path
    (`AAI_REAP_WORKSPACE`, default `$PWD`), age threshold
    (`AAI_REAP_MIN_AGE_SECS`/start-epoch). Enumerate procs via `ps axo pid,etime,command`,
    filter to `vitest`/`esbuild` AND workspace match AND age>threshold, `kill -TERM`
    (then `KILL`) each; print reaped count. Never a bare global `pkill`.
  - EDIT `.aai/scripts/aai-bootstrap.sh`: in the render path for `aai-test-unit`/
    `aai-test-e2e`, wrap the chosen command with `.aai/scripts/aai-run-tests.sh`; when a
    vitest project is detected, append leak-safe vitest guidance to the generated skill /
    marker. Do not overwrite existing user vitest config (respect existing safety rules).
  - EDIT `.aai/SKILL_LOOP.prompt.md`: pre-flight workspace proc count + warn/reap over
    threshold; route test commands through the wrapper; post-tick scoped reap; add
    `lingering_procs`/`free_memory` to the tick-log line.
  - EDIT `.aai/VALIDATION.prompt.md`: run discovered test commands via the wrapper; reap on
    the step boundary.
  - EDIT `.aai/system/DYNAMIC_SKILLS.md`: note generated skills route through the wrapper.
  - EDIT `.aai/SKILL_BOOTSTRAP.prompt.md` and/or `docs/USER_GUIDE.md`: document the 4-part
    contract.
  - NEW `tests/skills/test-aai-run-tests.sh`: bash harness mirroring
    `tests/skills/test-aai-docs-lock.sh` (`set -euo pipefail`, isolated tmp,
    `log_pass`/`log_fail`/`log_skip`, exit 0/1/42). `AAI_RUN_TESTS_SCRIPT` /
    `AAI_REAP_SCRIPT` overridable so TEST-002/005 can RED-proof against naive stubs.
    Uses unique process markers (`pgrep -f`) and `ps ... etime` so no real vitest is
    needed — a `sh -c 'sleep 600 & exit 0'` leaky child and a marked `sleep` stand in.
- Data flows: the loop/validation build the test command, hand it to the wrapper, and the
  wrapper owns the process group's whole lifecycle; the reaper is a post-step sweep; the
  tick log records the accounting. The scripts hold no shared state.
- Edge cases:
  - command not found / empty args → wrapper exits non-zero with usage; no group leaked.
  - child ignores `TERM` → escalate to `KILL` after a short grace.
  - `AAI_TEST_TIMEOUT=0` or non-integer → coerce to default (300) rather than never/instant.
  - reaper on a host with BSD vs GNU `ps` etime formats → parse both (`MM:SS`,
    `HH:MM:SS`, `D-HH:MM:SS`).
  - reaper with no matches → exit 0, count 0 (no-op).
  - two concurrent siblings in the SAME workspace → etime guard protects the younger tree.

## Seam analysis
A SEAM is any place this change shares state with, or is consumed by, a feature it does
not own.

- SEAM-1 (wrapper `aai-run-tests.sh` ⟷ every caller that launches tests: SKILL_LOOP,
  VALIDATION, generated aai-test-* skills). The mechanically automatable half is the
  wrapper's process-group invariant, crossed end-to-end by TEST-002/003 (a real leaky /
  hung child on one side, `pgrep` empty on the other — NOT a mock). TEST-007/008/009
  assert the callers actually route through it. RESIDUAL RISK R-WIRE: that a live LLM loop
  actually invokes the wrapper is process, grep-asserted not runtime-enforced (same honesty
  as SPEC-0004/0005 R-WIRE).
- SEAM-2 (reaper `aai-reap-tests.sh` ⟷ SKILL_LOOP pre-flight/post-tick sweep + tick log).
  Reaper's scope/etime half is crossed by TEST-005/006 (real matching + non-matching
  processes). RESIDUAL RISK R-REAP-INVOKE: the loop actually running the reaper and logging
  its count is prose (TEST-007 grep), not runtime-enforced.
- SEAM-3 (bootstrap-generated command ⟷ wrapper PRESENCE in the target). The generator
  emits `.aai/scripts/aai-run-tests.sh <cmd>`; the wrapper resolves only because aai-sync
  vendors `.aai/scripts/` (D1). TEST-010 asserts the generated command is wrapper-prefixed;
  the vendoring is covered by aai-sync's existing tests. RESIDUAL RISK R-VENDOR: a target
  that never ran aai-sync after this change would reference a missing wrapper — mitigated
  because bootstrap presupposes a synced `.aai/`.
- SEAM-4 (tick-log `lingering_procs`/`free_memory` fields ⟷ any dashboard/digest reading
  LOOP_TICKS.jsonl). Additive fields; consumers ignoring them are unaffected. Covered by
  TEST-007's grep on the field names. RESIDUAL RISK: none material (additive, non-breaking).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description | Status |
|----------|------------|-------------|--------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-run-tests.sh         | wrapper exists; `aai-run-tests.sh sh -c 'exit 0'` → exit 0; `... sh -c 'exit 7'` → exit 7 (real exit code passthrough) | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-run-tests.sh         | leaky child `sh -c 'sleep 600 & exit 0'` (unique marker) via wrapper → wrapper returns promptly, exit 0, AND `pgrep -f <marker>` EMPTY afterwards. RED-proofed against a no-group-kill stub wrapper (marker survives) | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-run-tests.sh         | `AAI_TEST_TIMEOUT=2 aai-run-tests.sh sh -c 'sleep 600'` → returns within ~timeout, exit 124, no survivors | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-run-tests.sh         | exit-code fidelity: success→0, failing cmd→its code (N), timeout→124 (fail distinguishable from hung) | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-run-tests.sh         | reaper kills a marked `sleep` matching `vitest`-pattern + workspace; a NON-matching marked `sleep` (other workspace/name) SURVIVES. RED-proofed against a bare `pkill -f vitest` stub that also kills the non-matching one | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-run-tests.sh         | reaper etime guard: a fresh matching process younger than the step-start threshold is NOT reaped; an older matching process IS reaped | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-run-tests.sh         | grep SKILL_LOOP: routes test commands via aai-run-tests.sh, pre-flight vitest/esbuild count with warn+reap over threshold, post-tick scoped reap, tick-log lingering_procs/free_memory fields | green |
| TEST-008 | Spec-AC-08 | integration | tests/skills/test-aai-run-tests.sh         | grep VALIDATION: discovered test commands run via aai-run-tests.sh + reap on the step boundary | green |
| TEST-009 | Spec-AC-09 | integration | tests/skills/test-aai-run-tests.sh         | grep DYNAMIC_SKILLS: generated aai-test-* skills route their command through .aai/scripts/aai-run-tests.sh | green |
| TEST-010 | Spec-AC-10 | integration | tests/skills/test-aai-run-tests.sh         | bootstrap dry-run on a synthetic vitest fixture → generated unit-test command is prefixed by `.aai/scripts/aai-run-tests.sh` AND leak-safe vitest guidance (maxForks/pool/teardownTimeout) is emitted; existing config not overwritten. RED-proofed: pre-change generator emits bare `npm exec vitest run` | green |
| TEST-011 | Spec-AC-11 | integration | tests/skills/test-aai-run-tests.sh         | grep USER_GUIDE / SKILL_BOOTSTRAP: document the 4-part leak-safe contract (killable group + timeout, bounded forks, scoped reaper never global, tick-log accounting) | green |

RED-proof obligation (all AC-gating tests, regardless of strategy):
- TEST-001 fails before `aai-run-tests.sh` exists (no script).
- TEST-002 is the wrapper SAFETY test — RED-proofed by first standing up a naive stub
  wrapper that runs `"$@"` WITHOUT process-group kill: the backgrounded `sleep 600`
  survives the wrapper, so "no descendant survives" fails RED; the real group-killing
  wrapper turns it GREEN. A safety test never seen failing proves nothing — this stub step
  is mandatory.
- TEST-003/004 fail RED before the inline watchdog + exit-code mapping exist (a stub never
  times out / mis-maps the code).
- TEST-005 is the reaper SAFETY test — RED-proofed against a bare `pkill -f vitest` stub
  that ALSO kills the non-matching sibling (over-reap): "non-matching survives" fails RED;
  the workspace+etime-scoped reaper turns it GREEN.
- TEST-006 fails RED before the etime guard exists (a stub reaps the fresh sibling).
- TEST-007..009/011 fail RED before the SKILL_LOOP / VALIDATION / DYNAMIC_SKILLS /
  USER_GUIDE edits land (grep finds none of the required strings).
- TEST-010 fails RED against the pre-change bootstrap, which emits a BARE unwrapped
  `npm exec vitest run` with no leak-safe guidance.

## Verification
- `bash tests/skills/test-aai-run-tests.sh` — TEST-001..011 (exit 0; 42 if a required tool
  such as `pgrep`/`ps` is missing).
- Manual smoke (wrapper): `AAI_TEST_TIMEOUT=2 .aai/scripts/aai-run-tests.sh sh -c 'sleep
  600'; echo $?` prints `124` within ~2s and leaves no `sleep 600` survivor.
- Manual smoke (leaky): `.aai/scripts/aai-run-tests.sh sh -c 'sleep 600 & exit 0'; pgrep -f
  "sleep 600"` returns empty.
- Manual smoke (reaper scope): start a marked matching + non-matching sleep, run
  `.aai/scripts/aai-reap-tests.sh`, assert only the matching one is gone.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path
  docs/specs/SPEC-0009-test-process-group-reaping-and-leak-accounting.md` reports CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with non-empty
  Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (ISSUE-0002 / SPEC-0009)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (e.g. docs/ai/tdd/red-*.log, green-*.log)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (ISSUE-0002 owns WHAT/WHY).
This document does not define workflow.

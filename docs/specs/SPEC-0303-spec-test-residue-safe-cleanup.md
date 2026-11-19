---
id: spec-test-residue-safe-cleanup
type: spec
number: 303
status: done
mutation_gate: v1
frozen_sha256: 267dea49fcdd13c98f235a1de3227cddc65318e687e1c0dfc4ce678d326a45dc
ceremony_level: 3
links:
  requirement: test-residue-safe-cleanup
  rfc: null
  pr: []
  commits: []
---

# Test runs remove their own container residue, behind per-object ownership checks, and never reach a daemon unless they opt in

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0259-test-residue-safe-cleanup.md (the
  owner's need and the eight required safeguards A to H from the ride brief).
- Incident this design answers: 2026-11-19, an earlier unmerged draft of this
  cleanup deleted 80 containers, 70 volumes and 4 networks on the owner's real
  Docker daemon when a mutation test dropped its only safety, the label filter
  of a listing whose output was removed blindly. That draft is reference only;
  its mutation record is quarantined and is never replayed.
- Prior scope this builds on (closed, not edited): SPEC-0009 / ISSUE-0002 (the
  wrapper's process group and always-reap), the disposable-checkout isolation
  of `aai-run-tests.sh` and `test-framework.sh`.
- Technology contract: docs/TECHNOLOGY.md (POSIX sh wrapper, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: the code deletes shared machine resources (L3). Every safeguard
  is written as a test first and observed failing on the unchanged tree, then
  each test gets a mutation record produced by `mutation-run.mjs` with the
  daemon unreachable. No test, mutation run or replay may reach a real daemon:
  every case uses a stub CLI written into the test's own scratch directory.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 deletion code in the vendored wrapper every role and
  downstream project runs; the main checkout carries other sessions' work.
- User decision: worktree (the owner's decision in the ride brief: a fresh
  worktree from origin/main)
- Base ref: origin/main at 73ef7e83
- Worktree branch/path: chore/test-residue-safe at
  /Users/ales/Projects/aai-worktrees/test-residue-safe
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/test-residue.sh;
  .aai/scripts/aai-run-tests.sh; tests/skills/test-framework.sh;
  .aai/scripts/mutation-run.mjs; tests/skills/test-aai-test-residue.sh;
  .aai/system/PROFILES.yaml; tests/skills/suite-map.yaml;
  tests/skills/suite-weights.tsv; docs/TECHNOLOGY.md; CHANGELOG.md;
  docs/product/test-residue-safe-cleanup.md

## Decisions

- D1 (one library, one funnel that deletes). `.aai/scripts/lib/test-residue.sh`
  (POSIX sh, sourced) holds every container CLI call this change makes. Only
  `aai-run-tests.sh` calls its cleanup. `test-framework.sh` and
  `mutation-run.mjs` never clean; they only isolate.
- D2 (isolation is the default, deletion is opt-in). Without
  `AAI_TEST_DOCKER=1` the wrapper exports `DOCKER_HOST` and `CONTAINER_HOST`
  as `unix:///nonexistent/aai-test-no-docker.sock`, `CONTAINERD_ADDRESS` as
  `/nonexistent/aai-test-no-containerd.sock` and `DOCKER_CONTEXT=default`
  (DOCKER_HOST outranks a context in the docker CLI), and runs no cleanup and
  prints nothing for it. The framework exports the same four for every suite
  and unsets `AAI_TEST_DOCKER`, `AAI_TEST_RUN_ID` and `AAI_TEST_RUN_START`:
  AAI's own suites have no opt-in, because none needs a daemon (measured: no
  suite under tests/skills calls a container CLI; `docker` appears only as a
  detection keyword in test-aai-expert-fetch.sh). `mutation-run.mjs` gives the
  suite it spawns the same four, deletes the three opt-in variables and sets
  `AAI_RESIDUE_IN_TEST=1`.
- D3 (ownership). With the opt-in, the wrapper that finds `AAI_TEST_RUN_ID`
  unset mints `aai-<epoch>-<pid>-<8 hex>`, records `AAI_TEST_RUN_START`
  (epoch seconds) before the command starts, exports both, and owns the
  cleanup. A nested wrapper inherits the id and makes no CLI call. Tests
  label what they create `aai.test.run=$AAI_TEST_RUN_ID`.
- D4 (per-object proof, A). The listing returns candidates only. Each one is
  then inspected by its own id; it is removed only when the inspected label
  `aai.test.run` equals the run id byte for byte AND the inspected creation
  time (RFC 3339, any offset, parsed in awk) is at or after the run start.
  An inspection that fails, returns more than one line, or carries an
  unreadable time skips the object. A listed token that is not an id shape
  (64 hex for containers and networks, a docker volume name) is skipped.
- D5 (no "all", B). `aai_residue_list <kind> <run id>` builds
  `--filter label=aai.test.run=<run id>` itself; it has no parameter for a raw
  filter, and refuses (exit 2, message, no CLI call) an empty or malformed id.
  `aai_residue_cleanup` refuses the same way, and also a run start that is not
  an integer.
- D6 (verbs, C). Mutating calls: `rm -f <id>`, `volume rm <name>`,
  `network rm <id>`, each on one verified object, stdin closed. `-f` stops the
  one verified container being removed. The listing uses `ps -a` (stopped
  containers included); that is a read. No prune, no `--all` removal, no
  compose, no `system` subcommand exists in the library.
- D7 (cap, D). More than 25 candidates for one run (all three kinds together)
  removes nothing and prints a refusal naming the count and the cap (exit 4).
  The cap is a constant, not an environment knob.
- D8 (test context, E). `AAI_RESIDUE_IN_TEST` set to anything but empty or 0
  marks a test context. The wrapper exports `AAI_RESIDUE_IN_TEST=1` to every
  command it runs, so every nested wrapper is in a test context; the
  framework and the mutation runner export it too. In a test context the
  cleanup calls nothing unless the resolved CLI is a regular file whose first
  five lines carry `AAI-RESIDUE-STUB-SENTINEL-v1` (read, never executed). The
  wrapper judges its OWN context by the value it inherited, not the one it
  gives its command.
- D9 (exit codes). The cleanup never changes a failing command's code or the
  watchdog's 124. A refusal of class B or E (cleanup exit 2 or 3) turns a
  command's 0 into 13; the cap refusal and per-object skips are reported
  only. The cleanup runs after the process-group reap on the normal path and
  in the INT, TERM and HUP traps.
- D10 (no daemon, H). With the opt-in: no CLI found, or any listing that
  fails, prints one NOTE and deletes nothing (cleanup exit 0).
- D11 (report, G). One stderr line per deleted object, one per skipped object
  with its reason, one summary line `run <id>: deleted N, skipped M, failed K`.
  `AAI_RESIDUE_DRY_RUN=1` prints `would delete ...` lines and a dry-run
  summary and removes nothing.
- D12 (out of scope). Temporary files and leftover processes are not part of
  this change: the process-group reap already covers processes, and a temp
  check needs edits across many suites. Follow-up filed at close.
- D13 (consumer record). Consumer-visible: downstream test runs lose daemon
  access unless they set `AAI_TEST_DOCKER=1`, and gain the cleanup and exit
  13. CHANGELOG per-entry heading, docs/TECHNOLOGY.md wrapper contract line,
  docs/product/test-residue-safe-cleanup.md. The new library is classified
  core in .aai/system/PROFILES.yaml (it ships wherever the wrapper does).

## Acceptance Criteria Mapping

- Spec-AC-01 maps to intake AC-001 (A).
- Spec-AC-02 maps to intake AC-002 (B).
- Spec-AC-03 maps to intake AC-003 (C).
- Spec-AC-04 maps to intake AC-004 (D).
- Spec-AC-05 maps to intake AC-005 (E).
- Spec-AC-06 maps to intake AC-006 (F).
- Spec-AC-07 maps to intake AC-007 (G).
- Spec-AC-08 maps to intake AC-008 (H).
- Spec-AC-09 maps to the intake's Desired Behavior (the wrapper seam: the id
  the wrapper exports is the label the command writes and the cleanup reads).
- Spec-AC-10 maps to the intake's Scope (layer classification and the
  consumer record).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the stub listing returns, regardless of its filter, a container, a volume and a network labelled with the run id and created after the run start, plus an unlabelled object, an object labelled with another run id, an object labelled with the run id but created before the run start and one whose inspection fails, the cleanup SHALL remove exactly the three owned objects, print one skipped line with its reason for each other object, leave each other object in the stub, and every listing call SHALL carry --filter label=aai.test.run=<run id>; WHEN creation times use Z, fractional seconds or a numeric offset, an object created at the run start SHALL be removed and one created a second before it or with an unreadable time SHALL be skipped | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D4 |
| Spec-AC-02 | WHEN aai_residue_cleanup gets an empty run id, a malformed one or a non-integer run start, and WHEN aai_residue_list gets an empty or malformed run id, each SHALL exit 2 with a REFUSED line and the stub SHALL record no call | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D5 |
| Spec-AC-03 | WHEN a cleanup removes one container, one volume and one network, the stub SHALL record exactly the mutating calls rm -f <id>, volume rm <name> and network rm <id>; the library's non-comment lines SHALL contain no prune, no compose, no --all and no system subcommand, and exactly three mutating call lines | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D6 |
| Spec-AC-04 | WHEN 26 objects carry the run's label the cleanup SHALL exit 4, print a REFUSED line naming 26 and the cap 25, and the stub SHALL record no rm call; WHEN 25 do, all 25 SHALL be removed | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D7 |
| Spec-AC-05 | WHEN AAI_RESIDUE_IN_TEST is set and the CLI is a recorder without the sentinel, the cleanup SHALL exit 3 with a REFUSED line and the recorder SHALL record no call, and with the stub it SHALL proceed; WHEN an outer wrapper (started without AAI_RESIDUE_IN_TEST) runs an inner opted-in wrapper pointed at the recorder, the inner SHALL exit 13 and the recorder SHALL record no call; WHEN the wrapper runs without the opt-in its command SHALL see the four unreachable daemon variables even if the caller set DOCKER_HOST, and with the opt-in the caller's DOCKER_HOST; WHEN the framework runs a suite with AAI_TEST_DOCKER=1 and DOCKER_HOST set by the caller, the suite SHALL see the four unreachable variables, AAI_RESIDUE_IN_TEST=1 and no AAI_TEST_DOCKER | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D2, D8 |
| Spec-AC-06 | WHEN the library's listing filter is dropped (the shape that caused the incident) the filter check of the stub suite SHALL fail and the per-object check SHALL still remove no unlabelled and no foreign stub object; WHEN the cleanup passes an empty run id to the listing it SHALL exit 2 and remove nothing; WHEN mutation-run.mjs runs a suite whose caller exported AAI_TEST_DOCKER=1 and a DOCKER_HOST, the suite SHALL see the unreachable DOCKER_HOST, AAI_RESIDUE_IN_TEST=1 and no AAI_TEST_DOCKER | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D2, D4, D5 |
| Spec-AC-07 | WHEN a cleanup removes owned objects and skips others it SHALL print one deleted line per removed object, one skipped line with a reason per skipped object and one summary line with the three counts; WHEN AAI_RESIDUE_DRY_RUN=1 it SHALL print would delete lines and a dry-run summary, record no rm call and leave every object in the stub | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D11 |
| Spec-AC-08 | WHEN the wrapper runs with the opt-in and the CLI is absent, or the stub daemon is down, it SHALL print exactly one AAI-RESIDUE NOTE line, record no rm call, and exit with the command's own code (0 and 3 checked) | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D9, D10 |
| Spec-AC-09 | WHEN an opted-in wrapper runs a command that creates objects labelled with the AAI_TEST_RUN_ID it received and exits 1, the wrapper SHALL exit 1 and those objects SHALL be gone while a pre-existing unlabelled object and a pre-existing object of another run remain; WHEN the watchdog fires it SHALL exit 124 and the labelled object SHALL be gone; WHEN AAI_TEST_RUN_ID is inherited the wrapper SHALL make no CLI call | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D3, D9 |
| Spec-AC-10 | .aai/system/PROFILES.yaml SHALL list .aai/scripts/lib/test-residue.sh exactly once, under core; docs/TECHNOLOGY.md SHALL name AAI_TEST_DOCKER and exit 13; CHANGELOG.md SHALL carry an unreleased per-entry heading for this change | done | docs/ai/tdd/test-residue-safe-cleanup/green-full-suite.log; docs/ai/tdd/spec-test-residue-safe-cleanup/ | — | D13 |

## Implementation plan

- `.aai/scripts/lib/test-residue.sh` (new): `aai_residue_runid_new`,
  `aai_residue_runid_valid`, `aai_residue_epoch`, `aai_residue_guard`,
  `aai_residue_list`, `aai_residue_verify`, `aai_residue_rm`,
  `aai_residue_id_shape`, `aai_residue_cleanup`; constants
  `AAI_RESIDUE_CAP=25`, `AAI_RESIDUE_STUB_SENTINEL`.
- `.aai/scripts/aai-run-tests.sh`: header (environment and exit 13); the
  isolation block before the launch (D2), the run id and start for an owning
  opted-in wrapper (D3), `AAI_RESIDUE_IN_TEST=1` exported to the command
  (D8); `aai_residue_finish` after the reap on the normal path and in the
  three signal traps; exit 13 (D9).
- `tests/skills/test-framework.sh`: `aai_isolate_container_daemon`, called
  once at startup (D2).
- `.aai/scripts/mutation-run.mjs`: `runSuite`'s environment (D2).
- `tests/skills/test-aai-test-residue.sh` (new): TEST-3900 to TEST-3914 with
  a stateful stub CLI (sentinel line, call log, objects as files, a `lie`
  mode that ignores the filter, a `down` mode) written into the suite's own
  scratch directory. No case invokes a real container CLI.
- `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`,
  `tests/skills/suite-weights.tsv`; docs/TECHNOLOGY.md; CHANGELOG.md;
  docs/product/test-residue-safe-cleanup.md.
- Seams crossed: the run id the wrapper exports is the label the command
  writes and the cleanup lists and verifies (TEST-3913); the marker the outer
  wrapper exports is what makes the inner wrapper's guard refuse (TEST-3906);
  the framework's and the mutation runner's exported environment is what the
  suite they spawn sees (TEST-3908, TEST-3910).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3900 | Spec-AC-01 | integration | tests/skills/test-aai-test-residue.sh | stub in lie mode lists every object: three owned objects removed, unlabelled, foreign, old and inspect-failing objects skipped with reasons and still present; every listing call carried the run-id label filter | target `.aai/scripts/lib/test-residue.sh`; `sed:s/ --filter "\$rl_filter"//g` drops the label filter from every listing (the incident's shape) and the case must fail | green |
| TEST-3901 | Spec-AC-01 | integration | tests/skills/test-aai-test-residue.sh | creation-time boundaries and formats: created at the run start (Z) removed, a second before (numeric offset) skipped, fractional seconds with an offset after the start removed, an unreadable time skipped | target `.aai/scripts/lib/test-residue.sh`; `sed:s/\[ "\$rv_epoch" -ge "\$4" \]/[ "$rv_epoch" -ge 0 ]/` removes the creation-time check and the case must fail | green |
| TEST-3902 | Spec-AC-02 | integration | tests/skills/test-aai-test-residue.sh | empty, malformed and newline-carrying run ids and a non-integer start: cleanup and listing exit 2 with REFUSED and the stub records no call | target `.aai/scripts/lib/test-residue.sh`; `sed:s/aai_residue_runid_valid\(\) \{/aai_residue_runid_valid() { return 0;/` accepts every id and the case must fail | green |
| TEST-3903 | Spec-AC-03 | integration | tests/skills/test-aai-test-residue.sh | the recorded mutating calls are exactly rm -f <id>, volume rm <name>, network rm <id>; the library has no prune, compose, --all or system subcommand and exactly three mutating call lines | target `.aai/scripts/lib/test-residue.sh`; `sed:s/ volume rm / volume rm --force /` widens the volume removal and the case must fail | green |
| TEST-3904 | Spec-AC-04 | integration | tests/skills/test-aai-test-residue.sh | 26 labelled volumes: exit 4, REFUSED naming 26 and 25, no rm call, all present; 25: all removed | target `.aai/scripts/lib/test-residue.sh`; `sed:s/AAI_RESIDUE_CAP=25/AAI_RESIDUE_CAP=99/` raises the cap and the case must fail | green |
| TEST-3905 | Spec-AC-05 | integration | tests/skills/test-aai-test-residue.sh | test context with a recorder CLI lacking the sentinel: exit 3, REFUSED, no recorded call; any non-empty non-zero marker value counts; the stub proceeds | target `.aai/scripts/lib/test-residue.sh`; `sed:s/case "\$\{AAI_RESIDUE_IN_TEST:-0\}" in/case 0 in/` ignores the test-context marker and the case must fail | green |
| TEST-3906 | Spec-AC-05 | integration | tests/skills/test-aai-test-residue.sh | outer wrapper started without the marker runs an inner opted-in wrapper pointed at the recorder: inner exits 13 with REFUSED, recorder has no call, the command saw AAI_RESIDUE_IN_TEST=1 | target `.aai/scripts/aai-run-tests.sh`; `sed:s/\nAAI_RESIDUE_IN_TEST=1(?=\n)//` stops the wrapper marking its command as a test and the case must fail | green |
| TEST-3907 | Spec-AC-05 | integration | tests/skills/test-aai-test-residue.sh | wrapper without the opt-in: the command sees the four unreachable daemon variables despite a caller DOCKER_HOST; with the opt-in it sees the caller's DOCKER_HOST | target `.aai/scripts/aai-run-tests.sh`; `sed:s/if \[ "\$\{AAI_TEST_DOCKER:-0\}" != "1" \]; then/if false; then/` disables the isolation and the case must fail | green |
| TEST-3908 | Spec-AC-05 | integration | tests/skills/test-aai-test-residue.sh | a byte copy of test-framework.sh in a fixture repo runs a fixture suite with the caller's AAI_TEST_DOCKER=1 and DOCKER_HOST: the suite sees the four unreachable variables, AAI_RESIDUE_IN_TEST=1 and no AAI_TEST_DOCKER | target `tests/skills/test-framework.sh`; `sed:s/\naai_isolate_container_daemon(?=\n)//` drops the framework's isolation call and the case must fail | green |
| TEST-3909 | Spec-AC-06 | integration | tests/skills/test-aai-test-residue.sh | scratch copies of the library with the filter dropped and with an empty id passed to the listing: the first fails the filter check yet removes only owned objects (unlabelled and foreign remain), the second exits 2 and removes nothing; the unmutated copy passes the filter check | target `.aai/scripts/lib/test-residue.sh`; `sed:s/\[ "\$rv_label" = "\$3" \]/true/` removes the per-object label check so the filter-dropped copy deletes foreign objects and the case must fail | green |
| TEST-3910 | Spec-AC-06 | integration | tests/skills/test-aai-test-residue.sh | mutation-run.mjs over a fixture repo whose wrapper only passes its environment through: the fixture suite's FAIL line, kept in the record, shows the unreachable DOCKER_HOST, AAI_RESIDUE_IN_TEST=1 and AAI_TEST_DOCKER unset although the caller set both | target `.aai/scripts/mutation-run.mjs`; `sed:s/env\.AAI_RESIDUE_IN_TEST = '1';//` stops marking the spawned suite as a test and the case must fail | green |
| TEST-3911 | Spec-AC-07 | integration | tests/skills/test-aai-test-residue.sh | report: deleted lines, skipped lines with reasons, a summary with deleted, skipped and failed counts; dry run prints would delete, records no rm call and removes nothing | target `.aai/scripts/lib/test-residue.sh`; `sed:s/if \[ "\$\{AAI_RESIDUE_DRY_RUN:-0\}" = "1" \]; then(?=\n      aai_residue_say "would delete)/if false; then/` deletes during a dry run and the case must fail | green |
| TEST-3912 | Spec-AC-08 | integration | tests/skills/test-aai-test-residue.sh | opted-in wrapper with an absent CLI and with the stub daemon down: one NOTE line each, no rm call, exit 0 and 3 kept | target `.aai/scripts/lib/test-residue.sh`; `sed:s/(?<=\(exit \$rc_st\); nothing deleted\."\n      )return 0/return 2/` turns an unanswering daemon into a refusal and the case must fail | green |
| TEST-3913 | Spec-AC-09 | integration | tests/skills/test-aai-test-residue.sh | opted-in wrapper end to end on the stub: the command labels a container, a volume and a network with the id it received and exits 1, the wrapper exits 1, they are gone, pre-existing unlabelled and other-run objects remain; watchdog exit 124 still removes the labelled object; an inherited id makes no CLI call | target `.aai/scripts/aai-run-tests.sh`; `sed:s/\naai_residue_finish(?=\n)//` drops the cleanup on the normal path and the case must fail | green |
| TEST-3914 | Spec-AC-10 | integration | tests/skills/test-aai-test-residue.sh | PROFILES lists the library once under core; TECHNOLOGY names AAI_TEST_DOCKER and exit 13; CHANGELOG has the unreleased per-entry heading | target `.aai/system/PROFILES.yaml`; `sed:s/\n  - \.aai\/scripts\/lib\/test-residue\.sh//` drops the classification and the case must fail | green |

RED observations: TEST-3900 to TEST-3914 are written first and run against
the unchanged tree (origin/main 73ef7e83 plus the new suite file); the log is
stored at `docs/ai/tdd/test-residue-safe-cleanup/red-full-suite.log`. Mutation
records under `docs/ai/tdd/spec-test-residue-safe-cleanup/`, produced only by
`mutation-run.mjs` for this spec with the daemon unreachable in the calling
shell.

## Verification

- `env -u AAI_ROLE DOCKER_HOST=unix:///nonexistent/aai-no-docker.sock bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh`
- `sh -n` and `dash -n` (when present) on the wrapper and the library.
- `node .aai/scripts/mutation-run.mjs` once per Test Plan row, then
  `node .aai/scripts/mutation-gate.mjs --spec <this spec>`.
- Selected suites plus CORE between rounds; one full sweep before close
  (`AAI_TEST_TIMEOUT=3600`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal; no command of
  the ride reached a real daemon (the calling shell's DOCKER_HOST is
  unreachable and `docker ps` fails in it).

## Evidence contract

Per artifact: ref_id `test-residue-safe-cleanup`, Spec-AC and TEST-xxx,
command, exit code, evidence path under
`docs/ai/tdd/test-residue-safe-cleanup/` (RED and GREEN logs) and
`docs/ai/tdd/spec-test-residue-safe-cleanup/` (mutation records), commit SHA
once committed.

Registry items closed by this scope: none

## Residual risks

- A tool that ignores `DOCKER_HOST` and opens `/var/run/docker.sock` itself,
  and rootless podman on Linux (it runs containers without a socket), are not
  stopped by the isolation. They still cannot make this cleanup delete
  anything they did not label with this run's id after its start.
- An object a test creates without the label is never removed: it cannot be
  attributed. Downstream tests must label what they create.
- Clock skew between the daemon and the host can make a fresh object look
  older than the run start; it is then skipped and reported, never deleted.
- A daemon that hangs (rather than refusing) holds the cleanup until it
  answers; the listing is not time-bounded.
- Windows-native `aai-run-tests.ps1` without WSL or Git Bash is not covered
  (it exits 78 there before reaching the POSIX wrapper).

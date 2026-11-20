---
id: test-residue-files-and-processes
type: change
number: 260
status: done
capability: test-residue-safe-cleanup
user_visible: true
links:
  pr: []
  commits: []
---

# Change: test runs remove the temp files and leftover processes they provably created

## Summary
- A test run gets a private temporary root; when the run ends, the wrapper removes that root after proving, at the moment of removal, that this run created it. A temp entry created outside the root is reported, never removed.
- A process a test leaves running after the run is terminated only when it still holds the run's own marker descriptor and passes a per-process check right before each signal. Anything the wrapper cannot prove is reported or left alone.
- This finishes the owner's need "tests must not leave residue" (follow-up `fu-test-residue-temp-and-processes`). The container part shipped in CHANGE-0259 / SPEC-0303.

## Motivation / Business Value
- The owner's need, verbatim: "pokud to nekdy neco testuje, tak to po sobe nesmi zanechavat zbytky, treba volume v dockeru" (a test must not leave residue behind, for example a Docker volume).
- The same discipline as the container part applies, because on 2026-11-19 an earlier attempt's mutation test, with its filter removed, deleted the owner's production containers and volumes. No single check may be the only thing between a cleanup and an object the run does not own.

## Scope
- In scope:
  - `.aai/scripts/lib/test-residue.sh`: the run temp root (create, verify, remove), the report of temp entries outside it, the process listing by the marker descriptor, the per-process check and the signals;
  - `.aai/scripts/aai-run-tests.sh`: the wrapper that owns a run creates the root, gives the command `TMPDIR=<root>` and the marker on descriptor 9, and runs the process and temp cleanup after the command (normal exit, watchdog, signals);
  - tests in `tests/skills/test-aai-test-residue.sh` that act only on objects they create inside a disposable sandbox;
  - the consumer record (CHANGELOG, docs/TECHNOLOGY.md wrapper contract, the product doc).
- Out of scope:
  - deleting any temp entry outside the run's root (reported only);
  - processes that closed the marker descriptor (a Node or Python child spawned with closed descriptors): not provable, so not touched;
  - the Git Bash (MSYS) path: no process cleanup there (no `lsof` contract), noted once;
  - containers (shipped).

## Affected Area
- The vendored test wrapper every role and every downstream project runs.

## Desired Behavior (To-Be)
- The wrapper that does not inherit `AAI_TEST_OWNER` owns the run: it mints an owner id (`aai-<epoch>-<pid>-<8 hex>`), records the start, creates `<TMPDIR>/aai-tr-<8 hex>` (mode 700) holding a marker file with the id and start, exports `AAI_TEST_OWNER`, `AAI_TEST_OWNER_START` and `TMPDIR=<root>` to the command, and opens the marker on descriptor 9 for it. A nested wrapper inherits the owner and does none of this.
- After the command, the wrapper terminates the processes that still hold the marker on descriptor 9. It lists them through `lsof` restricted to descriptor 9 and the marker. It re-checks each one by pid right before every signal: same uid, started at or after the run start, not pid 1, not the wrapper or any of its ancestors, still holding the marker on descriptor 9, and the same start time as when first seen. It sends TERM, then KILL after a grace period, with the check repeated before each signal.
- It then reports temp entries created in the original `TMPDIR` during the run outside the root, and removes the root only after verifying it is exactly `<base>/aai-tr-<this run's suffix>`, not a symlink, owned by the current uid, under an absolute base that is not `/` or `$HOME`, holding a regular marker file that names this run, with a modification time at or after the run start.
- An empty or malformed id, a missing marker, more than 25 process candidates, or any failed check acts on nothing and says why. `AAI_RESIDUE_DRY_RUN=1` reports and acts on nothing.
- Inside a test (`AAI_RESIDUE_IN_TEST` set by the caller) none of this runs unless a sandbox (`AAI_RESIDUE_SANDBOX`, a directory the test created) is named. In that case the temp base must be the sandbox, and only pids the test listed in the sandbox may be signalled.

## Acceptance Criteria
- AC-001: the owning wrapper gives the command a private temp root and removes it after a pass, a failure and a watchdog kill; a nested wrapper and a test-context wrapper without a sandbox create none.
- AC-002: every tampered root (wrong name, symlink, missing or foreign marker, base `/`, empty or relative base, base equal to `$HOME`, marker older than the start) is kept, with the reason reported; an empty or malformed id or a non-integer start is refused with exit 2.
- AC-003: a temp entry created in the base outside the root during the run is reported by name and kept.
- AC-004: a detached process that holds the marker descriptor is terminated; one that closed it survives; a dry run signals nothing.
- AC-005: pid 1, the wrapper, its ancestors, a process started before the run, a process whose start time changed and, in a test, a pid outside the sandbox list are never signalled, even when listed.
- AC-006: the process listing always carries descriptor 9 and the marker path; with no marker it refuses without calling `lsof`; more than 25 candidates signal nothing.
- AC-007 (two independent layers): with the listing filter removed, the filter check fails and the per-process check still spares a foreign sandbox process; with the root name check removed, the marker check still spares a decoy, and the reverse.
- AC-008: the CHANGELOG, docs/TECHNOLOGY.md and the product doc describe the behaviour.

## Verification
- `env -u AAI_ROLE DOCKER_HOST=unix:///nonexistent/aai-no-docker.sock CONTAINER_HOST=unix:///nonexistent/aai-no-docker.sock bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh`
- Mutation records through `mutation-run.mjs` for this spec only, with the daemon unreachable in the calling shell.

## Constraints / Risks
- Tests and mutation runs act only on files and processes the tests themselves create inside a sandbox; no test may signal a process it did not start or remove a path outside its sandbox.
- POSIX sh (dash on Linux, bash 3.2 on macOS); `lsof` present on macOS and the Ubuntu runners.
- A redirected `TMPDIR` lengthens temp paths by 16 bytes, 24 on macOS where the base becomes its physical `/private/var/...` path (Unix socket path limits); `AAI_TEST_TMPDIR=keep` keeps the caller's `TMPDIR`.
- A filesystem mounted inside the run's root (by a test that was killed before unmounting) keeps the root: `rm -rf` would delete the mounted data.
- Secrets preflight: no secret referenced.

## Notes
- Assumption (autopilot): ownership of a process is proven by an inherited descriptor, not by environment variables, because macOS does not expose another process's environment.
- Assumption (autopilot): ceremony level 3, owner merges (owner directive).

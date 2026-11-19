---
id: test-residue-safe-cleanup
type: change
number: 259
status: done
capability: test-residue-safe-cleanup
user_visible: true
links:
  pr: []
  commits: []
---

# Change: test runs remove their own container residue, behind hard safeguards

## Summary
- A test run that opts into a container daemon removes the containers, volumes and networks its tests created and labelled, and nothing else.
- Every removal is guarded per object: the object is re-inspected by id at delete time and removed only when its run label and its creation time prove that this run created it.
- Test runs that do not opt in can no longer reach a container daemon at all: the test runner points the container CLIs at an unreachable socket.

## Motivation / Business Value
- The owner's need, verbatim: "pokud to nekdy neco testuje, tak to po sobe nesmi zanechavat zbytky, treba volume v dockeru" (a test must not leave residue behind, for example a Docker volume).
- An earlier attempt at this need (never merged, never pushed) removed objects from a LIST that one label filter produced. Its mutation test replaced the filtered listing with an unfiltered one and ran through the outer test runner against the owner's real Docker daemon, which deleted 80 containers, 70 volumes and 4 networks of production systems on 2026-11-19. The data is lost.
- The owner chose "delete with hard safeguards", not report-only. This change is that design: deletion survives any single broken layer, and tests can never reach the real daemon.

## Scope
- In scope:
  - a POSIX sh library `.aai/scripts/lib/test-residue.sh` holding run-id minting and validation, the filtered listing, the per-object ownership check, the creation-time parser, the single-object removals and the cleanup report;
  - `.aai/scripts/aai-run-tests.sh`: daemon isolation for every wrapped command by default, the `AAI_TEST_DOCKER=1` opt-in, the run id and run start exported to the command, the cleanup after the command (normal exit, watchdog and signals);
  - `tests/skills/test-framework.sh`: daemon isolation for every AAI suite, with no opt-in (no AAI suite needs a daemon);
  - `.aai/scripts/mutation-run.mjs`: the suite it spawns gets the same isolation and the test-context marker;
  - a new suite `tests/skills/test-aai-test-residue.sh` that runs only against a stub container CLI;
  - the consumer record (CHANGELOG, docs/TECHNOLOGY.md wrapper contract, product doc) and the layer classification of the new library.
- Out of scope:
  - temporary files, directories and leftover processes. The wrapper's process-group reap (SPEC-0009) already covers processes; a temp-file check is a separate ride (follow-up), because it touches dozens of suites and adds no safety to this one;
  - any bulk or prune verb, any `-a`/`--all` removal, `compose down`;
  - containers, volumes or networks that do not carry this run's label (they are never removed, whoever created them);
  - the Windows-native `aai-run-tests.ps1` path beyond what it delegates to the POSIX wrapper.

## Affected Area
- The vendored test wrapper every role and every downstream project runs, the AAI test framework CI runs, and the mutation runner.

## Desired Behavior (To-Be)
- Without `AAI_TEST_DOCKER=1`, a wrapped command and every AAI suite see `DOCKER_HOST`, `CONTAINER_HOST` and `CONTAINERD_ADDRESS` pointing at a socket that does not exist and `DOCKER_CONTEXT=default`, so the docker, podman and nerdctl CLIs cannot reach a daemon. No cleanup runs and nothing is printed for it.
- With `AAI_TEST_DOCKER=1`, the outermost wrapper mints a run id and records the run start, exports both to the command (`AAI_TEST_RUN_ID`, `AAI_TEST_RUN_START`), and after the command lists the objects labelled `aai.test.run=<run id>`, re-inspects each one by id, and removes it only when the label equals the run id exactly and its creation time is at or after the run start. It prints one line per deleted and per skipped object (with the reason) and a summary.
- Any doubt removes nothing: a missing or malformed run id, a listing without the label filter, an inspection that fails, a label or time that does not match, or more candidates than the cap.

## Acceptance Criteria
- AC-001 (A, per-object ownership): an object is removed only when an inspection BY ID made just before the removal shows label `aai.test.run` equal to the run id and a creation time at or after the run start; an unlabelled object, an object with another run's label, an object created before the run start and an object whose inspection fails are skipped, reported with the reason, and still exist afterwards.
- AC-002 (B, no "all"): an empty, missing or malformed run id, and a listing call without a valid run-id filter, fail hard with a non-zero status and a message naming the refusal; the listing function cannot be called without the filter.
- AC-003 (C, single-object verbs only): the only mutating CLI calls the code can make are `rm -f <id>`, `volume rm <name>` and `network rm <id>` on one verified object each; no prune, no `-a`/`--all` removal, no compose call exists in the code.
- AC-004 (D, cap): more than 25 candidates for one run removes nothing and prints a refusal naming the count and the cap.
- AC-005 (E, test isolation): the code refuses (non-zero, no container CLI call) to run its cleanup in a test context (`AAI_RESIDUE_IN_TEST=1`, exported by the wrapper to its command, by the test framework and by the mutation runner) unless the CLI is the stub that carries the sentinel; this holds through the outer wrapper; the wrapper and the framework point every command and suite at an unreachable socket unless the wrapper's opt-in is set, and the framework has no opt-in.
- AC-006 (F, two independent layers under mutation): the stub-based suite catches a mutation that drops the label filter from the listing and a mutation that passes an empty run id to it; with the filter-dropping mutation applied, the per-object check still removes no unlabelled or foreign stub object; the mutation runner gives the suite it spawns the isolation and the test-context marker.
- AC-007 (G, report): the cleanup prints one line per deleted object, one line per skipped object with its reason, and one summary line; `AAI_RESIDUE_DRY_RUN=1` prints what it would delete and deletes nothing.
- AC-008 (H, downstream default): with the opt-in set, an absent CLI or a daemon that does not answer makes the cleanup a no-op with one note, and the wrapper keeps the command's own exit code.

## Verification
- `env -u AAI_ROLE DOCKER_HOST=unix:///nonexistent/aai-no-docker.sock bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh` — every case runs against the stub CLI only.
- Mutation records through `mutation-run.mjs` for this spec only, with the daemon unreachable in the calling shell.

## Constraints / Risks
- L3: the change deletes shared machine resources. The owner reviews it before merge, and it is never executed against a real daemon while it is built.
- Clock skew between the daemon and the host can make a freshly created object look older than the run start; it is then skipped and reported (fail-closed), never deleted.
- A tool that talks to `/var/run/docker.sock` directly and ignores `DOCKER_HOST` is outside the isolation; the per-object check and the label filter still protect anything it did not label.
- Downstream projects whose tests need a daemon must now set `AAI_TEST_DOCKER=1`; this is a consumer-visible behaviour change.
- Secrets preflight: no secret referenced.

## Notes
- Requirements A to H come from the owner's ride brief after the 2026-11-19 incident; each maps to one AC above.
- Assumption: `-f` on `rm -f <id>` is allowed (it stops the one verified container being removed; it is not a bulk verb).
- Assumption: `ps -a` in the LISTING (stopped containers included) is a read, not a removal, and is allowed.
- The old attempt's drafts and worktree are reference only; its mutation record is quarantined and never replayed.

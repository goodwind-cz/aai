---
id: test-residue-safe-cleanup
type: product
capability: test-residue-safe-cleanup
status: current
delivered_by:
  - test-residue-safe-cleanup
spec: docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md
updated: 2026-11-19
---

# Tests cannot touch a container daemon unless they opt in, and clean up only what they provably created

## What it does

Tests run through the AAI test wrapper can no longer reach a Docker, podman
(remote) or nerdctl daemon by default: the wrapper points every command at
daemon addresses that do not exist. A project whose tests genuinely need a
daemon sets `AAI_TEST_DOCKER=1`. Its tests then label the containers, volumes
and networks they create with the run id the wrapper hands them, and when the
command ends (normally, on a failure, a timeout or Ctrl-C) the wrapper removes
exactly those objects. Every object is re-checked one by one before it is
removed, so nothing the run did not create, and nothing that existed before
the run, is ever deleted. This replaces an earlier, never-merged draft whose
own mutation test wiped a real daemon.

**Behaviour change for downstream projects:** tests that talk to a daemon
through `aai-run-tests.sh` must now set `AAI_TEST_DOCKER=1`, or they will see
"cannot connect to the daemon".

## How to use it

```sh
AAI_TEST_DOCKER=1 bash .aai/scripts/aai-run-tests.sh npm test
```

In the tests, label everything you create:

```sh
docker run -d --label "aai.test.run=$AAI_TEST_RUN_ID" ...
docker volume create --label "aai.test.run=$AAI_TEST_RUN_ID" my-test-volume
docker network create --label "aai.test.run=$AAI_TEST_RUN_ID" my-test-net
```

Preview what would be removed without removing anything:
`AAI_RESIDUE_DRY_RUN=1 AAI_TEST_DOCKER=1 bash .aai/scripts/aai-run-tests.sh ...`.
Recommended for the first opted-in run on any machine.

## Data model

None. The only state is the label `aai.test.run=<run id>` that tests put on
their own objects; the run id has the form `aai-<epoch>-<pid>-<8 hex>`.

## Interfaces and contracts

- `AAI_TEST_DOCKER=1` (env, opt-in): daemon access for the wrapped command and
  the cleanup afterwards. Unset: `DOCKER_HOST`, `CONTAINER_HOST` =
  `unix:///nonexistent/aai-test-no-docker.sock`, `CONTAINERD_ADDRESS` =
  `/nonexistent/aai-test-no-containerd.sock`, `DOCKER_CONTEXT=default`.
- `AAI_TEST_RUN_ID`, `AAI_TEST_RUN_START` (env, exported to the command when
  opted in): the label value to use and the run start in epoch seconds.
- `AAI_RESIDUE_DRY_RUN=1` (env): report only.
- `AAI_RESIDUE_DOCKER` (env, default `docker`): the container CLI used for the
  cleanup.
- `AAI_RESIDUE_IN_TEST=1` (env, set by the wrapper for every command, by the
  AAI test framework and by the mutation runner): marks a test context; inside
  one, the cleanup refuses any CLI other than the AAI test stub.
- Output: `AAI-RESIDUE:` lines on stderr: one per deleted object, one per
  skipped object with its reason, a summary, or one NOTE when no CLI or daemon
  answers.
- Exit codes: the command's own code is kept (124 for a watchdog kill); a
  refusal of the cleanup itself (malformed run id, a non-stub CLI inside a
  test) turns an exit 0 into 13. More than 25 labelled objects removes
  nothing and is reported.

## Limits and non-goals

- An object a test creates without the label is never removed.
- An object is removed only if its label equals the run id exactly and it was
  created at or after the run start; clock skew between daemon and host can
  make a fresh object look older, and it is then left in place and reported.
- Removal uses only `rm -f <id>`, `volume rm <name>` and `network rm <id>`;
  never a prune, `--all` or compose.
- A tool that ignores `DOCKER_HOST` and opens the default socket itself, and
  rootless podman on Linux, are not stopped by the isolation (the per-object
  check still protects everything they did not label for this run).
- A daemon that hangs (rather than refusing) holds the cleanup until it
  answers.
- Temporary files and leftover processes are not part of this feature (the
  wrapper's process-group reap already covers processes).
- Windows without WSL or Git Bash is not covered.

## Links

- Request: docs/issues/CHANGE-0259-test-residue-safe-cleanup.md
- Spec: docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md
- Validation evidence: docs/ai/reports/VALIDATION-test-residue-safe-cleanup-20261119T205353Z.md

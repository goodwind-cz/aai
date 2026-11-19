# Code Review — test-residue-safe-cleanup

```yaml
review:
  scope: "git diff origin/main (73ef7e83) plus intent-to-add files in worktree chore/test-residue-safe (uncommitted)"
  spec: docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:129-155,232-243; TEST-3900, TEST-3901 green" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:109-113,184-193; TEST-3902 green" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:159-166; TEST-3903 green" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:36,224-227; TEST-3904 green" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:94-104; .aai/scripts/aai-run-tests.sh:801-833; tests/skills/test-framework.sh:39-54; TEST-3905..3908 green" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/mutation-run.mjs:789-802; TEST-3909, TEST-3910 green" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:234-263; TEST-3911 green" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:195-213; TEST-3912 green" }
      - { ac: Spec-AC-09, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:808-818,953-962 and traps 836-838; TEST-3913 green" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/system/PROFILES.yaml:222-225; docs/TECHNOLOGY.md:162-177; CHANGELOG.md:33; TEST-3914 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/test-residue.sh, line: 206,
          issue: "cleanup reads ANY listing exit 2 as the listing's own id refusal; after the cleanup validated the id itself (184-187), exit 2 can only come from the CLI",
          failure_scenario: "opted-in run (AAI_TEST_DOCKER=1) whose container CLI exits 2 on the listing (a usage error, a shim, an unsupported flag on some CLI): cleanup returns 2 with 'the container listing refused this run's id', and the wrapper turns the command's exit 0 into 13 — against D10/Spec-AC-08 (a failing listing is one NOTE, exit kept). Nothing is deleted (fails safe). Reproduced with a scratch stub that exits 2: cleanup rc=2, wrapper rc=13." }
  cannot_verify:
    - { claim: "the three inspect Go templates and the ps/volume ls/network ls flags behave as the stub assumes on real docker, podman and nerdctl (e.g. nerdctl 'network ls --no-trunc' support; empty label rendering)",
        closes_with: "one AAI_RESIDUE_DRY_RUN=1 opted-in run per CLI on a DISPOSABLE daemon (never the owner's), recording that owned objects are recognised and foreign ones skipped" }
    - { claim: "real-daemon creation times (container .Created, volume .CreatedAt, network .Created) parse with aai_residue_epoch",
        closes_with: "same disposable-daemon dry run; a mismatch fails closed (skip), so the risk is non-cleanup, not over-deletion" }
    - { claim: "the opt-in survives the Windows aai-run-tests.ps1 -> WSL hop (WSLENV may not forward AAI_TEST_DOCKER)",
        closes_with: "a WSL-leg run with AAI_TEST_DOCKER=1 printing AAI_TEST_RUN_ID from the command; failure direction is isolation (safe)" }
    - { claim: "the full sweep result (137 suites, 0 FAIL) cited by the validation report",
        closes_with: "docs/ai/validation/test-residue-safe-cleanup/full-sweep.log was read, not re-run by this reviewer (no full sweep per dispatch)" }
  overall: pass
```

security_relevant: true

## Scope and spec

- Worktree `/Users/ales/Projects/aai-worktrees/test-residue-safe`, branch
  `chore/test-residue-safe`, HEAD = origin/main `73ef7e83`; the change is
  uncommitted. Scope = `git diff origin/main` (18 files, +1452/-9) including
  the intent-to-add files `.aai/scripts/lib/test-residue.sh`,
  `tests/skills/test-aai-test-residue.sh`, the CHANGE and SPEC drafts.
- Spec: `docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md` (frozen,
  ceremony 3). Intake: `docs/issues/CHANGE-0259-test-residue-safe-cleanup.md`.
- Coaching check: the dispatch prompt gave operating safety rules and evidence
  paths; it did not characterise findings, pre-rate severity or exclude areas.
  None recorded.

## Safety of this review

Every command ran with `DOCKER_HOST`/`CONTAINER_HOST` at
`unix:///nonexistent/aai-no-docker.sock`, `CONTAINERD_ADDRESS` nonexistent,
`DOCKER_CONTEXT=default`, `AAI_RESIDUE_DOCKER=/nonexistent/aai-no-container-cli`,
`AAI_TEST_DOCKER`/`AAI_TEST_RUN_ID` unset; `docker ps` failed (rc=1) in that
environment. The only container CLI invoked was a scratch stub (exit-2
repro) and the suite's own stubs. No `mutation-run.mjs` run or replay was
made; `mutation-gate.mjs` (read-only) was run.

## Checks run

| Command | Result |
|---|---|
| `sh -n` / `dash -n` on `.aai/scripts/lib/test-residue.sh` and `.aai/scripts/aai-run-tests.sh` | ok |
| `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh` | rc 0, 15/15 PASS |
| `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md` | GATE PASS, 15 rows |
| scratch stub exiting 2 on the listing, library and wrapper (opt-in, no test marker) | cleanup rc 2, wrapper rc 13 (finding NB-1) |

## AC walk

All ten Spec-ACs compliant (table above). TEST-3900..3914 exist in
`tests/skills/test-aai-test-residue.sh`, pass in this reviewer's run, and each
has a mutation record that the gate accepts; the validator's replay log
(`docs/ai/validation/test-residue-safe-cleanup/mutation-replay.log`) shows
15/15 still redden.

Design points checked against the spec decisions:
- D4: verification by id with byte-equal label and floor(created) >= start;
  verify validates its own run id/start inputs, so an empty id cannot equal
  a missing label (`test-residue.sh:133-136`). Multi-line inspect skipped.
- D5/D6: the only listing builds its filter from a validated id; exactly
  three mutating lines, stdin closed; no prune/compose/--all/system (pinned
  by TEST-3903's 3-mutating / 9-call-line count).
- D7: cap counted across kinds before any removal.
- D8: the wrapper captures its caller's marker before exporting `AAI_RESIDUE_IN_TEST=1`
  and restores it only inside `aai_residue_finish`; three independent layers in
  the suite (unreachable sockets, PATH-shadowed docker/podman/nerdctl, recorder
  default CLI) plus the stub sentinel guard.
- D9: cleanup after `aai_reap_group` and `aai_iso_cleanup`, before the
  tripwire and final exit; 124 still outranks (TIMED_OUT checked first at the
  exit sequence); refusal 2/3 maps only a 0 to 13; `AAI_RES_OWN` reset before
  the cleanup so a signal during it cannot re-run it.

### Deviations from the frozen spec (recorded, not non-compliance)

1. `docs/product/test-residue-safe-cleanup.md` (spec D13 and the Review scope
   list) does not exist in the worktree. No Spec-AC requires it (AC-10 names
   PROFILES, TECHNOLOGY and CHANGELOG only); the ship convention writes
   product docs after LOOP COMPLETE. It must exist before close or D13 is
   unmet.
2. The AC Status table is already `done` with Evidence while frontmatter is
   `implementing` (same as validator NB-3); reconcile at close.
3. Additional in-scope files not in the spec's review-scope list:
   `tests/skills/test-aai-hygiene-pack.sh` (suite-map row pin 136 -> 137),
   `tests/skills/lib/cd-subshell-leak-baseline.tsv` (generated ratchet row for
   the new suite, 4 occurrences, all `cd` inside subshell fixture setup),
   `docs/ai/roadmap.yaml` (capability active), and ledger files. All are the
   mechanical companions of adding a suite / starting a ride.

## Findings

### NB-1 (NON-BLOCKING, P3) — CLI exit 2 masquerades as an id refusal

`.aai/scripts/lib/test-residue.sh:204-209`. `aai_residue_cleanup` validates
the run id itself (184-187), so `aai_residue_list` can never refuse the id
afterwards; a return of 2 there can only be the CLI's own exit status. The
code reads it as "the listing refused this run's id" and returns 2, which
`.aai/scripts/aai-run-tests.sh:957-961` turns into exit 13 for a passing
command. Failure scenario: an opted-in downstream run whose CLI exits 2 on
`ps`/`volume ls`/`network ls` (usage error, unsupported flag, a shim). The
command passed, the wrapper reports 13 with a false reason, contrary to D10
and Spec-AC-08 ("any listing that fails prints one NOTE and deletes nothing,
cleanup exit 0"). Fails safe (nothing deleted). Backed by a scratch-stub
repro (cleanup rc 2, wrapper rc 13).
Recommended disposition: remediate-in-tree (give the listing's refusal a code
no CLI uses, or treat any non-zero listing status after the cleanup's own
validation as the NOTE path, plus a stub case exiting 2). Alternative:
promote-to-follow-up-ref at P3.

### INFO

- `test_3902_no_run_id_never_means_all` names a universal negative. It is
  backed for all paths: both entry points (cleanup and the sole listing
  function) are asserted, TEST-3903 pins that the only listing call lines are
  inside `aai_residue_list`, and the validator is an exact-match regex. Not a
  finding.
- `aai_residue_epoch` accepts day 29-31 for any month (normalises, e.g.
  Feb 31 -> Mar 3). Daemons do not emit such times; no failure mode for
  ownership. Not a finding.

## cannot_verify

See the YAML block: real-CLI template/flag behaviour (docker, podman,
nerdctl), real creation-time formats, the WSL opt-in hop, and the full sweep
(read from the validator's log, not re-run here). Every one of these fails
in the safe direction (skip / isolate), never toward over-deletion.

## Warning dispositions (H6)

- NB-1: recommended remediate-in-tree; the orchestrator records the chosen
  artifact (decision id or follow-up ref) in `code_review.notes`.

## Next steps

1. Orchestrator decides NB-1 disposition (fix in tree or `fu-` P3 follow-up).
2. Write `docs/product/test-residue-safe-cleanup.md` at the ship step (D13).
3. Before the first opted-in downstream use, a dry run on a disposable daemon
   (validator NB-2).

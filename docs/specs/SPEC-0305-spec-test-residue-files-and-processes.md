---
id: spec-test-residue-files-and-processes
type: spec
number: 305
status: done
frozen_sha256: bb03ffedca45e0adfd6cd96eb4386ad77f572eae2f2daaede38313b3c55870b1
mutation_gate: v1
ceremony_level: 3
links:
  requirement: test-residue-files-and-processes
  rfc: null
  pr: []
  commits: []
---

# Test runs remove the temp root and the leftover processes they provably own, and nothing else

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0260-test-residue-files-and-processes.md
  (follow-up `fu-test-residue-temp-and-processes`, P3).
- Prior scope this builds on (closed, not edited):
  docs/specs/SPEC-0303-spec-test-residue-safe-cleanup.md (the library, the
  run id format, the test-context marker, D12 which left this part out).
- Incident the design answers: on 2026-11-19 a mutation test with its only
  filter removed deleted the owner's real containers and volumes. Every
  removal and every signal here is guarded by more than one independent
  check, and tests act only inside a sandbox they create.
- Technology contract: docs/TECHNOLOGY.md (POSIX sh wrapper; bash 3.2
  suites through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: code that deletes paths and signals processes on a shared
  machine. Every safeguard is a test first, observed failing on the
  unchanged tree, then a mutation record. Not chosen at intake (autopilot);
  Planning chose it.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: deletion and kill code in the vendored wrapper; L3 by
  owner directive; the main checkout carries other sessions' work.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: origin/main at daf88f69
- Worktree branch/path: feat/test-residue-files-and-processes at
  /Users/ales/Projects/aai-worktrees/test-residue-files-and-processes
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/test-residue.sh;
  .aai/scripts/aai-run-tests.sh; tests/skills/test-aai-test-residue.sh;
  tests/skills/lib/cd-subshell-leak-baseline.tsv;
  tests/skills/lib/install-parity.mjs; tests/skills/lib/install-parity.test.mjs;
  tests/skills/test-aai-install-parity.sh;
  docs/TECHNOLOGY.md; CHANGELOG.md; docs/product/test-residue-safe-cleanup.md;
  docs/ai/roadmap.yaml;
  docs/issues/CHANGE-0260-test-residue-files-and-processes.md;
  docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md.

## Decisions

- D1 (owner and modes). A wrapper that does not inherit `AAI_TEST_OWNER`
  owns the run's temp root and processes. It mints an owner id with
  `aai_residue_runid_new` (same format as the container run id) and records
  `AAI_TEST_OWNER_START` (epoch seconds) before it launches the command.
  `aai_residue_tree_mode` decides from the wrapper's OWN test context (the
  `AAI_RESIDUE_IN_TEST` it inherited) and prints one of three modes:
  - `real` outside a test;
  - `sandbox` inside a test that names `AAI_RESIDUE_SANDBOX`, a directory
    that is not a symlink;
  - `off` inside a test without one.
  In `off` the wrapper mints nothing, creates nothing, scans nothing and
  prints nothing about it. The Git Bash (MSYS) path is `off` too. An owning
  wrapper outside a test whose library is missing prints one NOTE that the
  temp and process cleanup is unavailable (Codex P2 on PR #574). A nested
  wrapper inherits the owner and does nothing.
- D2 (temp root). The owner creates `<base>/aai-tr-<8 hex>`, where `<base>`
  is the physical `${TMPDIR:-/tmp}` and the 8 hex are the owner id's random
  tail. It uses `mkdir` under `umask 077` (no reuse of an existing path) and
  writes the marker `.aai-test-run` holding `<owner id> <start>`. Creation
  applies the removal's base rules (absolute, not `/`, not `$HOME`, its own
  physical path), so no root is made that the cleanup would then refuse to
  remove (Codex P2 on PR #574). The
  command gets `TMPDIR=<root>`, `AAI_TEST_OWNER` and `AAI_TEST_OWNER_START`;
  the wrapper's own `TMPDIR` is restored right after the launch.
- D3 (root removal: two layers plus context).
  `aai_residue_tmp_verify <id> <start> <base> <root>` passes only when all of
  the following hold:
  - the id is valid and the start is an integer;
  - the base is absolute, not `/`, not `$HOME` (literally or as HOME's
    physical path), and its own physical path;
  - in `sandbox` mode, the base is the sandbox;
  - the root is exactly `<base>/aai-tr-<this id's tail>` (the name layer);
  - the root is a directory, not a symlink, owned by the current uid;
  - the marker is a regular file, not a symlink, whose first line is exactly
    `<id> <start>` (the marker layer);
  - the marker's modification time is at or after the start.
  Only then is the root removed, with `rm -rf`, which never follows a
  symlink inside it. The removal is pinned (Codex P1 on PR #574, tenth
  review): the directory's device and inode are read before any check, the
  root is renamed to a fresh `<root>.removing.<pid>` name and probed again,
  and the deletion then goes through the pinned directory itself: a subshell
  changes into it, re-reads the identity of `.` and the marker, and removes
  the entries with `find . -xdev -mindepth 1 -delete`, which pins the device
  of `.` and never enters a filesystem mounted after the probes (Codex P1 on
  PR #574, twelfth review); a `find` that fails is reported (thirteenth
  review); only the then-empty directory is removed by name, with `rmdir`
  (eleventh review), and only while the name still has the pinned identity;
  otherwise the name is left alone (fourteenth review). A directory
  swapped into either name while the checks ran is never emptied. Residual:
  a same-uid process can still move entries around inside the run's own
  root while it is removed. Post-freeze amendment (code review r1 BLOCKING-1):
  before the removal, `find <root>` and `find <root> -xdev` must list the
  same number of entries; when they differ, a filesystem is mounted inside
  the root (a disk image or bind mount a killed test left) and the root is
  kept with that reason, because `rm -rf` would delete the mounted data.
  Both walks must exit 0; a walk that fails keeps the root too (Codex P1 on
  PR #574, fourth review). Restructured after the fifth Codex finding on the
  same check into one function, `aai_residue_tmp_mount_free`, that fails
  closed by construction: every probe's own exit status is checked, the walk
  and mount-table comparisons are made in the shell (no awk or grep whose
  failure could read as "no match"), and any failure keeps the root. The
  outside scan reports when its `find` fails; a host without `lsof` skips
  the process check silently (a machine constant; Spec-AC-11). A
  bind mount of a same-device directory keeps the device number, so the
  root is also kept when the `mount` table lists any mount point at
  `<root>` itself or under `<root>/` (the exact-root match after Codex P1 on
  PR #574, third review) (amendment after validation r2 NB-3), and when the mount table
  cannot be read at all (Codex P1 on PR #574: fail closed). A root whose
  marker cannot be written is rolled back at creation (Codex P2 on PR #574). Anything else keeps the root and prints the reason.
  An empty or malformed id, a non-integer start, or an empty base or root
  refuses with exit 2 before any check.
- D4 (outside the root: report only). Before the removal, `find <base>
  -mindepth 1 -maxdepth 1 -user <uid> -newer <marker> ! -name 'aai-tr-*'`
  names temp entries changed since the run started outside the root, by the
  run or by any other process (the base is shared). One NOTE line gives the
  count and the first five names. Nothing outside the root is ever removed.
- D5 (process ownership proof). The command inherits the marker opened on
  descriptor 9; the wrapper closes its own copy right after the launch. A
  process proves it belongs to this run by still holding the marker on
  descriptor 9. The only listing is `aai_residue_proc_list <marker>`, which
  runs `lsof -a -d 9 -F p -- <marker>`. It refuses (exit 2, no `lsof` call)
  unless the marker is an existing `.aai-test-run` file under an absolute
  path, and refuses the same way when the marker's first field is not the
  owner id passed to the cleanup (post-freeze amendment after validation
  r1 NB-3). The listing is trusted only whole (post-merge-review amendment,
  Codex P2 on PR #574): exit 0 with only pid and descriptor records, or exit
  1 with no output; any other exit, error text or a part-way listing prints
  one NOTE and signals nothing. Because lsof exits 1 both for "nothing found"
  and for an error whose warning `-w` hides, the listing runs in a subshell
  that itself holds the marker on descriptor 9 (a positive control): only
  exit 0 with at least one pid record counts, and pids gone by the time the
  cleanup looks (the control, lsof) are dropped (Codex P2 on PR #574, ninth
  review). `AAI_RESIDUE_LSOF` names the `lsof` command; tests point it at a
  logging shim that runs the real one. No `lsof`: one NOTE, nothing
  signalled.
- D6 (per-process check, re-run right before each signal).
  `aai_residue_proc_verify <pid> <marker> <start>` passes only when all of
  the following hold:
  - the pid is an integer above 1;
  - it is not the wrapper or any of its ancestors (ppid chain to 1);
  - it is owned by the current uid;
  - it started at or after the run start, measured as now minus `etime`,
    with one second of slack; uid, `etime` and `lstart` are read by one ps
    call each and each is checked against its own grammar (`etime` exactly
    `[[dd-]hh:]mm:ss` with hh 0-23, mm and ss 0-59; `lstart` the five
    fields of a date), so a blank or shifted sample leaves the process
    unverified (Codex P2 on PR #574, fourteenth review; Spec-AC-13);
  - in `sandbox` mode, its pid is listed in `$AAI_RESIDUE_SANDBOX/pids`;
  - `lsof -a -p <pid> -d 9 -F f -- <marker>` exits 0 and shows it still
    holds the marker on descriptor 9 (an lsof that fails is not a check;
    Codex P2 on PR #574).
  The check prints the pid's `lstart` as its identity.
  `aai_residue_proc_signal` re-runs the check and signals only when the
  identity is unchanged, with `kill -s <SIG> <pid>`: one positive pid,
  never a group, never a name pattern. TERM goes first; after up to two
  seconds, KILL goes to any pid still alive, with the check re-run first.
- D7 (cap, dry run, report). More than 25 listed pids signals nothing and
  prints a refusal (exit 4). `AAI_RESIDUE_DRY_RUN=1` reports `would
  terminate` and `would delete` and acts on nothing. A clean run (root
  removed, no process listed, nothing outside) prints nothing. Every action,
  skip, kept root and refusal prints one `AAI-RESIDUE:` line. None of this
  changes the wrapper's exit code.
- D8 (order). On every exit path (normal, watchdog, INT, TERM, HUP) the
  wrapper runs the steps in this order:
  1. the group reap;
  2. the process cleanup;
  3. the outside report and root removal;
  4. the disposable-checkout cleanup and the container cleanup, as before.
- D9 (tests act only on what they create). Every case runs with the daemon
  variables unreachable. Every case that removes or signals anything runs in
  `sandbox` mode on a directory and processes the case created itself, and
  records those pids in the sandbox. The mutation cases build mutated copies
  of the library in the suite's scratch directory and run them in the same
  sandbox.
- D11 (opt-out of the redirect; post-freeze amendment after code review r1
  NB-1). `AAI_TEST_TMPDIR=keep` leaves the command's `TMPDIR` as the caller
  set it, so a cache keyed on `TMPDIR` survives runs; the root is still made
  and still carries the marker, so the process check and the root removal
  run unchanged.
- D10 (consumer record). One CHANGELOG `## [unreleased] — feat: ...`
  heading, the wrapper contract in docs/TECHNOLOGY.md, and the product doc
  docs/product/test-residue-safe-cleanup.md. No new `.aai/` file: the library
  is already classified core.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to AC-001 (D1, D2, D8).
- Spec-AC-02 maps to AC-002 (D3).
- Spec-AC-03 maps to AC-003 (D4).
- Spec-AC-04 maps to AC-004 (D5, D6, D7).
- Spec-AC-05 maps to AC-005 (D6).
- Spec-AC-06 maps to AC-006 (D5, D7).
- Spec-AC-07 maps to AC-007 (D3, D5, D6, D9).
- Spec-AC-08 maps to AC-008 (D10).
- Spec-AC-09 maps to code review r1 BLOCKING-1 (D3, amendment).
- Spec-AC-10 maps to code review r1 NB-1 (D11, amendment).
- Spec-AC-11 maps to Codex P2 on PR #574 and the WSL1 CI leg (D3, D5).
- Spec-AC-13 maps to Codex P2 on PR #574 (fourteenth review) (D6).
- Spec-AC-12 maps to the Windows install-parity CI leg: the pre-existing
  random wide-character root directories (fu-parity-win-odd-root-dirs)
  sometimes have no UTF-8 name, and the driver's snapshot crashed on them
  (two of five heads of PR #574); the driver now records them for the
  existing allowlist row, and names it on stderr as not compared (Codex P2
  on PR #574: an uninspectable subtree is reported, never silently cut).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the wrapper runs with AAI_RESIDUE_IN_TEST=1, AAI_RESIDUE_SANDBOX and TMPDIR set to the same sandbox directory and no AAI_TEST_OWNER, the command SHALL see TMPDIR equal to the sandbox path plus /aai-tr- and eight hex digits, holding a .aai-test-run marker that names AAI_TEST_OWNER and AAI_TEST_OWNER_START; after a command that exits 0, one that exits 3 and one killed by the watchdog, that root SHALL no longer exist and the exit codes SHALL be 0, 3 and 124; a wrapper nested in that command SHALL create no second root; a wrapper with AAI_RESIDUE_IN_TEST=1 and no sandbox SHALL leave TMPDIR unchanged and print no AAI-RESIDUE line | done | TEST-3923 red docs/ai/tdd/test-residue-files-and-processes/red-test_3923_owner_temp_root_lifecycle.log; TEST-3923 green docs/ai/tdd/test-residue-files-and-processes/green-test_3923_owner_temp_root_lifecycle.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3923.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D1, D2, D8 |
| Spec-AC-02 | WHEN aai_residue_tmp_cleanup is called in sandbox mode on a root that has the wrong name, is a symlink to a directory holding a valid marker, has no marker, has a marker naming another id, has a marker older than the start, or sits under a base that is the empty string, a relative path, slash, or equal to HOME, each such directory and its contents SHALL still exist afterwards and the output SHALL name the reason; WHEN the id is empty or malformed or the start is not an integer, the call SHALL exit 2 and remove nothing | done | TEST-3924 red docs/ai/tdd/test-residue-files-and-processes/red-test_3924_tampered_roots_are_kept.log; TEST-3924 green docs/ai/tdd/test-residue-files-and-processes/green-test_3924_tampered_roots_are_kept.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3924.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D3 |
| Spec-AC-03 | WHEN a command run by the owning wrapper in sandbox mode creates a file directly in the sandbox outside its root, the wrapper output SHALL name that file in one NOTE line and the file SHALL still exist, while the root is removed | done | TEST-3925 red docs/ai/tdd/test-residue-files-and-processes/red-test_3925_outside_entries_reported_and_kept.log; TEST-3925 green docs/ai/tdd/test-residue-files-and-processes/green-test_3925_outside_entries_reported_and_kept.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3925.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D4 |
| Spec-AC-04 | WHEN a command run by the owning wrapper in sandbox mode starts a detached sleep that keeps descriptor 9 and a detached sleep that closed descriptor 9, both recorded in the sandbox pid list, the first SHALL be gone after the wrapper exits and the second SHALL still be running; WHEN AAI_RESIDUE_DRY_RUN=1, both SHALL still be running and the output SHALL say would terminate | done | TEST-3926 red docs/ai/tdd/test-residue-files-and-processes/red-test_3926_owned_process_terminated_foreign_kept.log; TEST-3926 green docs/ai/tdd/test-residue-files-and-processes/green-test_3926_owned_process_terminated_foreign_kept.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3926.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D5, D6, D7 |
| Spec-AC-05 | aai_residue_proc_verify SHALL refuse pid 1, the calling shell, its parent, a pid absent from the sandbox list, and a pid whose start lies before the given run start, each while that pid holds the marker on descriptor 9; aai_residue_proc_signal SHALL refuse a pid whose identity differs from the one passed and SHALL leave it running | done | TEST-3927 red docs/ai/tdd/test-residue-files-and-processes/red-test_3927_per_process_check_refusals.log; TEST-3927 green docs/ai/tdd/test-residue-files-and-processes/green-test_3927_per_process_check_refusals.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3927.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D6 |
| Spec-AC-06 | every listing call recorded by a logging lsof shim SHALL carry -a, -d 9 and the marker path; WHEN the marker path is empty or not an existing .aai-test-run file, or the marker names another run, the cleanup SHALL exit 2 without calling the shim; WHEN the shim lists 26 pids, the cleanup SHALL exit 4 and signal none of them | done | TEST-3928 red docs/ai/tdd/test-residue-files-and-processes/red-test_3928_listing_filter_refusal_and_cap.log; TEST-3928 green docs/ai/tdd/test-residue-files-and-processes/green-test_3928_listing_filter_refusal_and_cap.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3928.txt; TEST-3928 red (marker naming another run) docs/ai/tdd/test-residue-files-and-processes/red-r1-test_3928_listing_filter_refusal_and_cap.log; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D5, D7 |
| Spec-AC-07 | WHEN a copy of the library whose listing drops -d 9 runs on a sandbox holding an owned sleep on descriptor 9 and a foreign sleep holding the marker on descriptor 8, the filter check SHALL fail and the foreign sleep SHALL still be running while the owned one is gone; WHEN a copy without the root name check runs on a decoy directory without a valid marker, and a copy without the marker line check runs on a decoy whose name is another run's, each decoy SHALL still exist | done | TEST-3929 red docs/ai/tdd/test-residue-files-and-processes/red-test_3929_two_layers_under_mutation.log; TEST-3929 green docs/ai/tdd/test-residue-files-and-processes/green-test_3929_two_layers_under_mutation.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3929.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D3, D5, D6, D9 |
| Spec-AC-08 | CHANGELOG.md SHALL hold exactly one unreleased heading for this change, docs/TECHNOLOGY.md SHALL name AAI_TEST_OWNER and the aai-tr- root, and docs/product/test-residue-safe-cleanup.md SHALL say that a leftover process is terminated only while it holds the run's marker | done | TEST-3930 red docs/ai/tdd/test-residue-files-and-processes/red-test_3930_consumer_record.log; TEST-3930 green docs/ai/tdd/test-residue-files-and-processes/green-test_3930_consumer_record.log and docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3930.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D10 |
| Spec-AC-09 | WHEN aai_residue_tmp_cleanup runs on a valid root whose find -xdev walk lists fewer entries than its plain find walk (a find shim standing in for a mount point, and on macOS a real disk image attached inside the root), or whose path the mount table lists a mount under (a mount shim), the root and every file below it SHALL still exist and the output SHALL name the mount | done | TEST-3931 red docs/ai/tdd/test-residue-files-and-processes/red-r1-test_3931_mounted_filesystem_inside_root_is_kept.log; TEST-3931 red (mount table) docs/ai/tdd/test-residue-files-and-processes/red-r2-test_3931_mounted_filesystem_inside_root_is_kept.log; TEST-3931 green docs/ai/tdd/test-residue-files-and-processes/green-test_3931_mounted_filesystem_inside_root_is_kept.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3931.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D3 |
| Spec-AC-10 | WHEN the owning wrapper runs with AAI_TEST_TMPDIR=keep in sandbox mode, the command SHALL see the caller's TMPDIR, a detached process it leaves holding descriptor 9 SHALL be gone afterwards, and no root SHALL remain | done | TEST-3932 red docs/ai/tdd/test-residue-files-and-processes/red-r1-test_3932_tmpdir_opt_out_keeps_caller_tmpdir.log; TEST-3932 green docs/ai/tdd/test-residue-files-and-processes/green-test_3932_tmpdir_opt_out_keeps_caller_tmpdir.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3932.txt; validation docs/ai/validation/VALIDATION-test-residue-files-and-processes-r3.md | — | D11 |
| Spec-AC-11 | WHEN the scan for temp entries outside the root fails, the output SHALL say it did not complete; WHEN no lsof command exists, the process cleanup SHALL exit 0 and print nothing | done | TEST-3933 red docs/ai/tdd/test-residue-files-and-processes/red-restructure-test_3933_outside_scan_failure_and_no_lsof.log; TEST-3933 green docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3933.txt | — | D3, D5 |
| Spec-AC-12 | WHEN lstat of a root entry whose name is not printable ASCII fails ENOENT during a parity snapshot, the snapshot SHALL record it as a directory and print one NOTE naming it as not compared; WHEN it fails for a printable-ASCII name, the snapshot SHALL throw | done | TEST-3934 red docs/ai/tdd/test-residue-files-and-processes/red-test_3934_parity_odd_name.log; TEST-3934 green tests/skills/test-aai-install-parity.sh run, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3934.txt | — | CI parity leg |
| Spec-AC-13 | aai_residue_etime_s SHALL convert only an elapsed time of the exact form [[dd-]hh:]mm:ss with hh 0 to 23 and mm and ss 0 to 59 and SHALL fail for a blank, weekday, out-of-range or otherwise malformed field; WHEN ps returns a blank or weekday elapsed time or a shifted start time for a process holding the marker, the cleanup SHALL leave it running and name the unreadable sample | done | TEST-3935 red docs/ai/tdd/test-residue-files-and-processes/red-codex14-test_3935_malformed_ps_sample_fails_closed.log; TEST-3935 green docs/ai/tdd/test-residue-files-and-processes/green-full-suite-residue.log, mutation docs/ai/tdd/spec-test-residue-files-and-processes/mutation-TEST-3935.txt | — | D6 |

## Implementation plan

- `.aai/scripts/lib/test-residue.sh`: `aai_residue_tree_mode`,
  `aai_residue_suffix`, `aai_residue_mtime`, `aai_residue_tmp_create`,
  `aai_residue_tmp_verify`, `aai_residue_tmp_outside`,
  `aai_residue_tmp_cleanup`, `aai_residue_ancestors`,
  `aai_residue_etime_s`, `aai_residue_proc_list`, `aai_residue_proc_verify`,
  `aai_residue_proc_signal`, `aai_residue_proc_cleanup`; the header names
  the new layers. No word that TEST-3903 forbids in the library.
- `.aai/scripts/aai-run-tests.sh`: the library is sourced whenever present;
  the owner block after the container block; `TMPDIR` and descriptor 9
  around the launch; `aai_tree_finish` after `aai_reap_group` on the normal
  path and in the three traps; the header documents the new environment.
- `tests/skills/lib/cd-subshell-leak-baseline.tsv`: re-recorded for the
  three new `$(cd <dir> && pwd -P)` reads (physical base paths), each
  self-contained (post-freeze amendment after the TDD full sweep).
- `tests/skills/test-aai-test-residue.sh`: TEST-3923 to TEST-3930, a sandbox
  helper and a logging `lsof` shim; the header range.
- Seams crossed: the wrapper hands the command its environment and
  descriptor 9 (TEST-3923, TEST-3926); `lsof` reports another process's
  descriptors (TEST-3926 to TEST-3929, with real detached processes the case
  starts).
- POSIX sh (dash, bash 3.2); BSD and GNU `find`, `stat`, `ps`; `lsof`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3923 | Spec-AC-01 | integration | tests/skills/test-aai-test-residue.sh | the real wrapper in sandbox mode: a probe command prints TMPDIR and the marker; pass, fail (exit 3) and watchdog (AAI_TEST_TIMEOUT=2) runs leave no root and keep their exit codes; a nested wrapper creates no second root; a test-context wrapper without a sandbox leaves TMPDIR alone and prints no AAI-RESIDUE line; RED on the unchanged tree | target `.aai/scripts/aai-run-tests.sh`; `sed:s/TMPDIR="\$AAI_TREE_ROOT"/TMPDIR="$AAI_TREE_BASE"/` hands the command the base instead of the root and the case must fail | green |
| TEST-3924 | Spec-AC-02 | integration | tests/skills/test-aai-test-residue.sh | library cases in a sandbox: wrong name, symlink root, no marker, foreign marker, old marker (touch -t), empty, relative, slash and HOME base each keep their directory and print the reason; empty id, malformed id and bad start exit 2; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/  \[ -n "\$\{HOME:-\}" \] \x7c\x7c return 1/  return 1/` makes the HOME test (literal and physical) always answer no and the case must fail | green |
| TEST-3925 | Spec-AC-03 | integration | tests/skills/test-aai-test-residue.sh | the wrapper in sandbox mode with a command that writes outside.txt into the sandbox: one NOTE line names outside.txt, the file remains, the root is gone; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/aai_residue_tmp_outside "\$tc_base" "\$tc_root"/:/` drops the outside report and the case must fail | green |
| TEST-3926 | Spec-AC-04 | integration | tests/skills/test-aai-test-residue.sh | the wrapper in sandbox mode with a command that starts two detached sleeps (perl setsid), one keeping descriptor 9 and one with 9 closed, pids into the sandbox: the first is gone, the second runs (the case kills it itself); dry run keeps both and says would terminate; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/kill -s "\$2" "\$1"/: kill -s "$2" "$1"/` stops sending the signal and the case must fail | green |
| TEST-3927 | Spec-AC-05 | integration | tests/skills/test-aai-test-residue.sh | verify on pid 1, $$, $PPID, a sleep not in the sandbox list and a sleep with the run start one hour ahead, each holding the marker on descriptor 9 where the case can arrange it: each refused with its reason; signal with a wrong identity leaves the sleep running; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/case " \$pv_excl " in \*" \$pv_pid "\*\) echo "is this wrapper or one of its ancestors"; return 1 ;; esac//` drops the ancestor exclusion and the case must fail | green |
| TEST-3928 | Spec-AC-06 | integration | tests/skills/test-aai-test-residue.sh | a logging lsof shim: every listing line carries -a, -d 9 and the marker; empty and missing marker exit 2 with no shim call; a shim listing 26 sandbox pids gives exit 4 and every sleep still runs; a shim that fails (exit 1 with error text) or stops part-way (exit 2 after one record) gives the listing-failed NOTE and signals nothing; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/"\$AAI_RESIDUE_LSOF" -a -d 9 -F p/"$AAI_RESIDUE_LSOF" -F p/` drops the descriptor filter and the case must fail | green |
| TEST-3929 | Spec-AC-07 | integration | tests/skills/test-aai-test-residue.sh | mutated copies of the library in the scratch directory: listing without -d 9 (filter check fails, foreign sleep on descriptor 8 survives, owned sleep gone); verify without the name check (decoy without marker survives); verify without the marker line check (decoy named after another run survives); control: the unmutated library passes the filter check; RED on the unchanged tree | target `.aai/scripts/lib/test-residue.sh`; `sed:s/grep -qx 'f9'/true/` makes the per-process descriptor check always pass and the case must fail | green |
| TEST-3930 | Spec-AC-08 | unit | tests/skills/test-aai-test-residue.sh | one CHANGELOG heading; TECHNOLOGY names AAI_TEST_OWNER and aai-tr-; the product doc names the marker condition; RED on the unchanged tree | target `docs/product/test-residue-safe-cleanup.md`; `sed:s/only while it holds the run's marker/whenever it outlives the run/` reverts the statement and the case must fail | green |
| TEST-3931 | Spec-AC-09 | integration | tests/skills/test-aai-test-residue.sh | one table-driven case: find and mount shims for a shorter -xdev walk, a failing find, a failing -xdev find, an empty walk, a failing mount, an empty mount table, a mount at the root and one below it each keep the root with its reason; a control row with the real tools removes it; on macOS an hdiutil disk image attached inside the root keeps its file | target `.aai/scripts/lib/test-residue.sh`; `sed:s/\[ "\$mf_all" = "\$mf_one" \]/true/` stops comparing the two walks and the case must fail | green |
| TEST-3932 | Spec-AC-10 | integration | tests/skills/test-aai-test-residue.sh | AAI_TEST_TMPDIR=keep through the real wrapper in sandbox mode: TMP equals the sandbox, the fd-9 sleep is terminated, no aai-tr- root remains; RED on the wrapper without the opt-out | target `.aai/scripts/aai-run-tests.sh`; `sed:s/if \[ "\$\{AAI_TEST_TMPDIR:-\}" != keep \]; then/if true; then/` drops the opt-out and the case must fail | green |
| TEST-3933 | Spec-AC-11 | integration | tests/skills/test-aai-test-residue.sh | a find shim fails the outside scan: one NOTE says it did not complete; AAI_RESIDUE_LSOF naming a missing command: the process cleanup exits 0 and prints nothing | target `.aai/scripts/lib/test-residue.sh`; `sed:s/if ! to_out=\$\(find/if to_out=$(find/` inverts the scan status check and the case must fail | green |
| TEST-3934 | Spec-AC-12 | unit | tests/skills/test-aai-install-parity.sh | lstatSync patched to throw ENOENT for one non-ASCII directory name: the snapshot records it as a dir and the other entries; for an ASCII name it throws | target `tests/skills/lib/install-parity.mjs`; `sed:s/if \(err && err.code === 'ENOENT'/if (false && err.code === 'ENOENT'/` stops tolerating the unreadable odd name and the case must fail | green |
| TEST-3935 | Spec-AC-13 | integration | tests/skills/test-aai-test-residue.sh | an 18-row etime table (valid forms with their seconds; blank, weekday, out-of-range and malformed fields fail); a ps shim returning a blank or weekday elapsed time, or a shifted start time, for a marker-holding sandbox sleep: the sleep survives and the skip names the unreadable sample | target `.aai/scripts/lib/test-residue.sh`; `sed:s/if \(h > 23 \x7c\x7c m > 59 \x7c\x7c x > 59\) exit 1//` accepts out-of-range fields and the case must fail | green |

RED observations: TEST-3923 to TEST-3930 are written first and run against
the unchanged tree; failing runs go to `red-<selector>.log` under
`docs/ai/tdd/test-residue-files-and-processes/`. Mutation records go under
`docs/ai/tdd/spec-test-residue-files-and-processes/`.

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE DOCKER_HOST=unix:///nonexistent/aai-no-docker.sock CONTAINER_HOST=unix:///nonexistent/aai-no-docker.sock bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh`
- `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>` (this
  spec only, daemon unreachable in the calling shell)
- One full sweep before close (`AAI_TEST_TIMEOUT=3600`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `test-residue-files-and-processes`, Spec-AC and
TEST-xxx, command, exit code, evidence path under
`docs/ai/tdd/test-residue-files-and-processes/` and
`docs/ai/tdd/spec-test-residue-files-and-processes/`, commit SHA once
committed.

Registry items closed by this scope: fu-test-residue-temp-and-processes

## Residual risks

- A process that closed descriptor 9 is not provable and survives, for
  example a child spawned by Node or Python with closed descriptors, or a
  daemon that closes every descriptor. A process that keeps descriptor 9 but
  reopened it on another file is not provable either.
- Temp entries created outside the root (a hard-coded `/tmp` path) are
  reported, never removed; one created in the same second as the marker is
  not reported.
- The start-time check has one second of slack and rests on `ps etime`.
- A redirected `TMPDIR` is longer: 16 bytes for the root name, and on macOS
  24 in all, because the base becomes its physical `/private/var/...` path.
  That can matter for Unix socket paths near their limit (104 bytes on
  macOS); `AAI_TEST_TMPDIR=keep` avoids it.
- `lsof` runs after the watchdog has stopped and with no time limit; a hung
  network mount could hold the wrapper (follow-up `fu-tree-lsof-unbounded`).
- The Git Bash path runs none of this; Windows CI covers only that it stays
  off.
- A same-device bind mount added under the root by a privileged process
  after the last probe keeps the device number, so `find -xdev` cannot tell
  it apart at deletion time; a different-device mount added then is not
  entered. A same-uid process can still rearrange entries inside the run's
  own root while it is removed (shell has no descriptor-relative deletion).

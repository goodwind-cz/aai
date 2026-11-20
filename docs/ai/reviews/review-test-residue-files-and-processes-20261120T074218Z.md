```yaml
review:
  scope: "uncommitted diff vs origin/main daf88f69 in worktree feat/test-residue-files-and-processes, explicit paths: .aai/scripts/lib/test-residue.sh (new section, lines 270-544); .aai/scripts/aai-run-tests.sh; tests/skills/test-aai-test-residue.sh (TEST-3923..3930 + helpers); tests/skills/lib/cd-subshell-leak-baseline.tsv; docs/TECHNOLOGY.md; CHANGELOG.md; docs/product/test-residue-safe-cleanup.md; docs/ai/roadmap.yaml; docs/issues/CHANGE-0260-test-residue-files-and-processes.md; docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md"
  spec: docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:837-873,899-955,1011-1013 + traps 886-888; TEST-3923 PASS (rerun 2026-11-20)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:320-390; TEST-3924 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:351-359,382; TEST-3925 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:476-544; TEST-3926 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:392-474; TEST-3927 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/scripts/lib/test-residue.sh:415-433,487-504; TEST-3928 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "layer:name / layer:marker tags at test-residue.sh:336,344; TEST-3929 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33-35, docs/TECHNOLOGY.md:179-191, docs/product/test-residue-safe-cleanup.md:90-102; TEST-3930 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/lib/test-residue.sh, line: 387,
          issue: "the verified root is removed with plain `rm -rf -- <root>`, which descends into any filesystem mounted inside the root and deletes that filesystem's contents; neither the name nor the marker layer says anything about what is mounted below the root",
          failure_scenario: "a test mounts something under its TMPDIR (hdiutil attach, a FUSE/sshfs/bindfs mount, a Linux bind mount when CI runs as root) and is killed by the watchdog or Ctrl-C before it unmounts; the wrapper (default-on, every top-level run) verifies the root and rm -rf deletes the mounted data, then prints FAILED to delete because the busy mount point stays. Reproduced on this host: docs/ai/reviews/repro-tree-root-crosses-mount-20261120.sh exits 1 (DEFECT: the file inside the mounted filesystem was deleted); `rm -rf -x` (BSD) kept it",
          backed_by: "repro docs/ai/reviews/repro-tree-root-crosses-mount-20261120.sh" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 903-910,
          issue: "default-on TMPDIR redirect to a fresh per-run root that is deleted afterwards defeats every tmpdir-keyed cache and long-lived helper downstream, and there is no documented opt-out",
          failure_scenario: "a downstream Jest project (default cacheDirectory = os.tmpdir()/jest_<uid>) run through aai-run-tests.sh starts with a cold transform cache on every run and the cache is deleted at exit, so every run pays the full babel/ts-jest transform cost; same for any tool caching under $TMPDIR. CHANGELOG/TECHNOLOGY/product doc do not mention it or how to turn it off" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/test-residue.sh, line: 432,
          issue: "the lsof listing (every real-mode run) and the per-pid lsof (462) run with no -b/-w and no time bound, after the watchdog has already been stopped",
          failure_scenario: "a developer machine or CI host with an unresponsive NFS/SMB mount on which some process holds an open file: lsof blocks in stat() on that file, so the wrapper hangs after the command finished, never prints the exit code, and no watchdog is armed any more (previously the wrapper never called lsof)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md, line: 247,
          issue: "residual risk says the redirected TMPDIR is 16 bytes longer; on macOS it is 24 bytes longer because the base is also physicalized (/var -> /private/var); the CHANGE draft repeats 16",
          failure_scenario: "a tool building a Unix socket under TMPDIR within 24 bytes of the 104-byte macOS limit fails although the documented margin (16) says it fits; measured: old TMPDIR join base 48 chars, new 72 chars" }
  cannot_verify:
    - { claim: "Linux (dash, GNU ps/stat/find, Linux lsof) behaviour of the new section", closes_with: "Linux CI leg of tests/skills/test-aai-test-residue.sh green on the PR (dash was exercised locally on macOS only)" }
    - { claim: "lsof cost inside Linux containers with a huge RLIMIT_NOFILE (older lsof is known to take seconds there) on every top-level wrapper run", closes_with: "timing of one wrapper run in a container image with lsof < 4.95 and nofile=1048576" }
    - { claim: "pid reuse in the window between the final lsof check (462) and kill (472)", closes_with: "not closable in POSIX sh (no pidfd); mitigated by the lstart identity plus the fact that a reused pid must also hold this marker on descriptor 9" }
    - { claim: "Windows/Git Bash path stays off", closes_with: "Windows CI leg (DEGRADED_MSYS gate at aai-run-tests.sh:843 read only)" }
  overall: fail
```

security_relevant: true

# Code review — test-residue-files-and-processes (round 1)

- Reviewer: independent CODE REVIEW role (did not write the code), dispatched.
- Scope: uncommitted diff against `origin/main` (daf88f69) in
  `/Users/ales/Projects/aai-worktrees/test-residue-files-and-processes`, the
  explicit path list above. `git status --porcelain` also shows ledger
  files (EVENTS, decisions, test-runs) outside the review scope; not reviewed.
- Spec: docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md
  (frozen, 8 Spec-AC). Validation r1 PASS read, including its NB-1..NB-4.
- Coaching check: the dispatch named risk areas to probe (paths, symlinks,
  TOCTOU, pid reuse, ancestors) but did not pre-rate severity or exclude any
  area. Full scope reviewed.
- Safety of this review's probes: docker variables pointed at a nonexistent
  socket (`docker ps` failed first); every library call ran in sandbox mode
  on directories under the session scratchpad or with a sandbox the probe
  created; every process signalled was a `sleep 131/133` this review started,
  killed by exact pid after checking its command line; the disk image used
  for the repro was created and detached by the probe.

## Spec compliance — AC walk (verdict: pass)

| Spec-AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | wrapper owner block `aai-run-tests.sh:837-873`, TMPDIR and fd 9 around launch `:899-955`, `aai_tree_finish` after the reap `:1011-1013` and in the three traps `:886-888`; TEST-3923 PASS in this review's rerun |
| Spec-AC-02 | compliant | `aai_residue_tmp_verify`/`_tmp_cleanup` `test-residue.sh:320-390`; TEST-3924 PASS |
| Spec-AC-03 | compliant | `aai_residue_tmp_outside` `:351-359`, called before removal `:382`; TEST-3925 PASS |
| Spec-AC-04 | compliant | `aai_residue_proc_cleanup` `:476-544`, dry run `:512-515`; TEST-3926 PASS |
| Spec-AC-05 | compliant | `aai_residue_ancestors` `:392-402`, `aai_residue_proc_verify` `:438-464`, identity compare `:470`; TEST-3927 PASS |
| Spec-AC-06 | compliant | `aai_residue_marker_ok` + listing `:415-433`, refusal before lsof `:487-490`, cap `:501-504`; TEST-3928 PASS |
| Spec-AC-07 | compliant | layer tags `:336` and `:344`, fd filter in listing and in verify `:432,:462`; TEST-3929 PASS |
| Spec-AC-08 | compliant | CHANGELOG heading `CHANGELOG.md:33`, TECHNOLOGY `:179-191`, product doc sentence "only while it holds the run's marker"; TEST-3930 PASS |

TEST evidence: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh`
exit 0, "All tests passed!", TEST-3923..3930 each PASS (35.8 s). RED/GREEN
logs and the eight mutation records exist under
`docs/ai/tdd/test-residue-files-and-processes/` and
`docs/ai/tdd/spec-test-residue-files-and-processes/`.

Deviations from the frozen spec (none changes an AC call):
- D7 says a clean run prints nothing; in real mode on a shared macOS
  `$TMPDIR` the D4 NOTE almost always names other tools' entries, so a clean
  run usually prints one NOTE (same observation as validation NB-2).
- Residual-risk text "16 bytes longer" is 24 on macOS (NON-BLOCKING 3 below).

## Code quality (verdict: fail)

### BLOCKING-1 — root removal crosses into a filesystem mounted inside the root

`.aai/scripts/lib/test-residue.sh:387` removes the verified root with
`rm -rf -- "$tc_root"`. Both layers prove the root DIRECTORY is this run's;
nothing proves that everything below it is. Plain `rm -rf` (BSD and GNU)
descends into a mount point and deletes the mounted filesystem's contents.

Failure scenario: a test mounts something under its `TMPDIR` (a disk image
via `hdiutil attach`, a FUSE/sshfs/bindfs mount of real data, a Linux bind
mount in a root CI container) and is killed by the watchdog or Ctrl-C before
it unmounts. On every top-level run (default-on), the wrapper verifies the
root and deletes the mounted data; the busy mount point survives, so the
only trace is `AAI-RESIDUE: FAILED to delete temp root`. Before this change
nothing was deleted from `TMPDIR`. This is the "a single check is the only
thing between the code and foreign data" shape the spec set out to exclude:
the two layers both guard the directory name, none guards its contents.

backed-by: repro `docs/ai/reviews/repro-tree-root-crosses-mount-20261120.sh`
(macOS; creates a scratch sandbox and a disk image, mounts it at
`<root>/mnt`, calls `aai_residue_tmp_cleanup` in sandbox mode, detaches).
Observed: exit 1, "DEFECT: the file inside the mounted filesystem was
deleted". With `rm -rf -x` (BSD) the same layout kept the mounted file.

Suggested fix (implementer's call): keep the root with a reason when anything
below it is on another filesystem (for example compare the `find <root>` and
`find <root> -xdev` listings, or probe `rm -x` / `rm --one-file-system`), plus
a TEST-xxx with a mount (hdiutil on macOS; skip-case where no unprivileged
mount exists) and its mutation record.

### NON-BLOCKING-1 (P2) — default-on TMPDIR redirect, no opt-out

`.aai/scripts/aai-run-tests.sh:903-910`. Every top-level run now hands the
command a fresh `TMPDIR` that is deleted afterwards. Failure scenario: a
downstream Jest project (default `cacheDirectory` is `os.tmpdir()/jest_<uid>`)
gets a cold transform cache on every run and loses it at exit; any other
tool that caches or keeps a socket under `$TMPDIR` behaves the same. The
CHANGELOG, TECHNOLOGY and the product doc do not mention the effect or a way
to turn it off. Recommended disposition: remediate-in-tree (document the
effect and offer an explicit opt-out), else promote to a follow-up ref.

### NON-BLOCKING-2 (P3) — unbounded lsof after the watchdog is gone

`.aai/scripts/lib/test-residue.sh:432` (every real-mode run) and `:462`.
Failure scenario: a host with an unresponsive NFS/SMB mount where some
process holds a file open; lsof blocks in `stat()`, the wrapper never
returns the command's exit code, and the watchdog was already stopped at
`aai-run-tests.sh:996`. The wrapper never called lsof before this change.
Recommended disposition: promote to follow-up ref (suggested:
`fu-tree-lsof-unbounded`, not filed) to evaluate `-b`/`-w` or a bounded call.

### NON-BLOCKING-3 (P3) — residual says 16 bytes, macOS measures 24

Spec residual risks (spec line 247) and CHANGE draft line 63. Old command TMPDIR join base
`/var/folders/.../T` = 48 chars; new `/private/var/folders/.../T/aai-tr-xxxxxxxx`
= 72 chars. A socket path within 24 bytes of the 104-byte limit fails while
the record says 16 is the margin. Recommended disposition: remediate-in-tree
(correct the wording with the additive-amendment convention).

### Checked and found sound (no finding)

- Signals: one positive pid only (`kill -s SIG pid`); pid must match
  `[0-9]+`, not 0/1 (`00` makes `ps` fail → "is gone"); not `$$` or any
  ancestor; same uid; started at or after the run start; listed in the
  sandbox in a test; still holding this marker on descriptor 9 (lsof
  `-a -p -d 9`); identity (lstart) re-compared before TERM and before KILL;
  cap 25. Each single mutation (drop `-d 9` in the listing, drop the `f9`
  check, drop the ancestor exclusion, stub the kill) still leaves an
  independent layer; checked by reading and by TEST-3929.
- A signal arriving between `exec 9<` and `exec 9<&-` makes the wrapper a
  marker holder; `$$` exclusion covers it (also covered under dash: a probe
  `aai_residue_proc_verify $$` returned "is this wrapper or one of its ancestors").
- Root: name and marker layers are independent; symlink root, symlink marker,
  foreign uid, old marker and bad bases kept; `rm -rf` does not follow
  symlinks inside the root.
- Mutation replays run with `AAI_RESIDUE_IN_TEST=1` (mutation-run.mjs:802),
  so the owning wrapper there is `off` unless a case names a sandbox; a
  mutated library never runs in real mode under the mutation runner.
- Tests: every removal and signal acts on sandbox directories under the
  suite's scratch dir and on `sleep 127` processes the case started,
  reaped by exact pid only while their command is still `sleep 127`; the
  HOME case sets `HOME` to the sandbox; the `/` base case targets a path
  that does not exist and is refused before any check.
- `set -u` in the wrapper: every variable read in the new code is set on
  the paths that read it. Exit code: `aai_tree_finish` returns 0 and never
  touches `STATUS`; TEST-3923 holds 0/3/124. Real-mode probe in this review
  (TMPDIR = scratch): exit 7 preserved, the fd-9 holder terminated, the
  holder that closed fd 9 survived, root removed.
- dash: the new functions ran under `dash -u` in a sandbox (create, verify,
  proc cleanup, tmp cleanup) with the expected results.

### INFO (never gates)

- The wrapper replaces an inherited descriptor 9 for the command (for
  example a make jobserver fd that happens to be 9).
- Ctrl-C during `aai_tree_finish`'s TERM wait makes the trap's call a
  no-op (`AAI_TREE_OWN=0` already), so the root stays behind; safe
  direction.
- Validation NB-2 (outside NOTE names other tools' entries) and NB-3
  (`proc_cleanup` does not bind the marker to the id) are confirmed and not
  repeated here.

## cannot_verify

1. Linux behaviour (dash + GNU ps/stat/find + Linux lsof) of the new
   section — closes with the PR's Linux CI leg of the residue suite.
2. lsof cost in Linux containers with a huge `RLIMIT_NOFILE` on every
   top-level run — closes with one timed run in such an image.
3. pid reuse between the last lsof check and `kill` — not closable in POSIX
   sh; mitigated by lstart identity plus the marker-on-fd-9 requirement.
4. Git Bash path stays off — closes with the Windows CI leg.

## Warning dispositions (H6, recommended; the orchestrator records them)

- NON-BLOCKING-1: remediate-in-tree (doc + opt-out), else follow-up ref.
- NON-BLOCKING-2: promote to follow-up (suggested `fu-tree-lsof-unbounded`, not filed).
- NON-BLOCKING-3: remediate-in-tree (wording amendment).

## Next steps

1. Remediate BLOCKING-1 with a failing-first test and a mutation record.
2. Apply or record the NON-BLOCKING dispositions above.
3. Re-review (same single pass) after remediation.

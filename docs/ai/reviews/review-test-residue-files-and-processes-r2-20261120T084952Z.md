```yaml
review:
  scope: "uncommitted diff vs origin/main daf88f69 in worktree feat/test-residue-files-and-processes, same explicit path list as r1: .aai/scripts/lib/test-residue.sh; .aai/scripts/aai-run-tests.sh; tests/skills/test-aai-test-residue.sh; tests/skills/lib/cd-subshell-leak-baseline.tsv; docs/TECHNOLOGY.md; CHANGELOG.md; docs/product/test-residue-safe-cleanup.md; docs/ai/roadmap.yaml; docs/issues/CHANGE-0260-test-residue-files-and-processes.md; docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md"
  spec: docs/specs/SPEC-0305-spec-test-residue-files-and-processes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "aai-run-tests.sh owner block + launch + aai_tree_finish; TEST-3923 PASS (r2 rerun)" }
      - { ac: Spec-AC-02, call: compliant, citation: "test-residue.sh aai_residue_tmp_verify/_tmp_cleanup; TEST-3924 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "test-residue.sh aai_residue_tmp_outside; TEST-3925 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "test-residue.sh aai_residue_proc_cleanup; TEST-3926 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "test-residue.sh aai_residue_proc_verify/_proc_signal; TEST-3927 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "test-residue.sh:504-509 marker-names-this-run refusal + listing/cap; TEST-3928 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "layer:name / layer:marker; TEST-3929 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md:33, docs/TECHNOLOGY.md:179-195, product doc; TEST-3930 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "test-residue.sh:383-397 (find vs find -xdev count, mount table); TEST-3931 PASS incl. real hdiutil leg; r1 repro now exits 0" }
      - { ac: Spec-AC-10, call: compliant, citation: "aai-run-tests.sh:910-915 AAI_TEST_TMPDIR=keep; TEST-3932 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/test-residue.sh, line: 386,
          issue: "the mount check's plain `find <root>` walks the whole mounted filesystem to count it, with no bound, after the watchdog is stopped",
          failure_scenario: "a test killed by the watchdog leaves a large tree (a bindfs/sshfs mount of $HOME, or a network share) mounted inside its root: the wrapper walks all of it before deciding to keep the root, and blocks indefinitely if that mount is unresponsive; the decision (keep) is safe, only the wait is unbounded. Same class as fu-tree-lsof-unbounded" }
  cannot_verify:
    - { claim: "Linux behaviour of the new mount checks (GNU find -xdev, util-linux mount output, dash)", closes_with: "Linux CI leg of tests/skills/test-aai-test-residue.sh on the PR (TEST-3931 runs only the shim legs there)" }
    - { claim: "lsof cost in Linux containers with a very high RLIMIT_NOFILE on every top-level run", closes_with: "one timed run in such an image" }
    - { claim: "pid reuse between the last lsof check and kill", closes_with: "not closable in POSIX sh; mitigated by lstart identity plus the marker-on-fd-9 requirement" }
    - { claim: "Git Bash path stays off", closes_with: "Windows CI leg" }
  overall: pass
```

security_relevant: true

# Code review — test-residue-files-and-processes (round 2)

- Reviewer: independent CODE REVIEW role, dispatched; same scope and the same
  probe-safety rules as r1 (docker variables at a nonexistent socket,
  `docker ps` failed first; library calls only in sandbox mode on scratch
  directories; no process signalled that this review did not start; the
  r1 repro's disk image was created and detached by the repro itself).
- Previous round: docs/ai/reviews/review-test-residue-files-and-processes-20261120T074218Z.md
  (FAIL: BLOCKING-1, NON-BLOCKING-1..3).
- Coaching check: the dispatch listed what was changed since r1; it did not
  pre-rate severity or exclude any area. Full scope re-reviewed.

## r1 findings — status

| r1 finding | Status | Evidence |
|---|---|---|
| BLOCKING-1 rm -rf crosses a mount inside the root | fixed | `test-residue.sh:383-397`: root kept when `find <root>` and `find <root> -xdev` counts differ, or when `mount` lists a mount under `<root>/`. `docs/ai/reviews/repro-tree-root-crosses-mount-20261120.sh` now exits 0 ("kept temp root ... another filesystem is mounted inside it", mounted file survived). TEST-3931 (find shim, mount shim, real hdiutil image) PASS; Spec-AC-09 added by amendment |
| NON-BLOCKING-1 TMPDIR redirect, no opt-out | fixed | `aai-run-tests.sh:910-915` `AAI_TEST_TMPDIR=keep`; documented in the wrapper header, TECHNOLOGY:192, product doc:96, CHANGELOG; TEST-3932 PASS; Spec-AC-10 / D11 |
| NON-BLOCKING-2 unbounded lsof | follow-up | `fu-tree-lsof-unbounded` in docs/ai/decisions.jsonl (P3) |
| NON-BLOCKING-3 16 vs 24 bytes | fixed | spec residual lines 267-270 and CHANGE draft line 63 now state 24 on macOS |

Also verified: validation r1 NB-3 (process cleanup refuses a marker naming
another run, exit 2, before any lsof; `test-residue.sh:506-509`, TEST-3928
extended) and the reworded outside NOTE ("changed since this run started,
by this run or any other process").

## Spec compliance — AC walk (verdict: pass)

All ten Spec-AC compliant; see the YAML block for per-row citations.
TEST evidence: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-test-residue.sh`
exit 0, "All tests passed!", TEST-3923..3932 each PASS, no mount left
behind afterwards. Spec-AC-09/10 and D11 are post-freeze amendments that the
orchestrator recorded with signoff none (owner-assigned by canon; noted, not
re-judged here).

## Code quality (verdict: pass)

No BLOCKING finding.

### NON-BLOCKING-1 (P3) — the mount check walks the mounted filesystem

`.aai/scripts/lib/test-residue.sh:386`. To detect a mount, the plain `find`
walk descends into it and counts everything on it. Failure scenario: a test
killed by the watchdog leaves a large or unresponsive filesystem mounted
inside its root (bindfs/sshfs of `$HOME`, a network share); the wrapper
walks all of it, or blocks on it indefinitely, after the watchdog has been
stopped. The outcome is safe (the root is kept); only the wait is
unbounded. A walk that stays on the root's filesystem (`find <root> -xdev
-type d` and compare each directory's device with the root's) would see the
mount point without entering it. Recommended disposition: promote to
follow-up, ideally by widening `fu-tree-lsof-unbounded` (same class:
an unbounded external call after the watchdog stops) or as
`fu-tree-mount-walk-unbounded` (suggested, not filed).

### Checked and found sound

- Two independent layers for a mount on another device (walk comparison
  and mount table); a same-device bind mount rests on the mount table alone,
  and the gaps of that layer (no `mount`, Linux space escapes) are tracked
  in `fu-tree-mount-check-gaps`. A mount exactly at the root hides the
  marker, so the marker layer keeps the root.
- `AAI_TEST_TMPDIR=keep`: the root, the marker on descriptor 9, the
  process check and the root removal still run; TMPDIR restore after the
  launch is correct whether TMPDIR was set or unset.
- Marker identity in `aai_residue_proc_cleanup`: an empty first line or
  another run's id refuses with exit 2 before lsof.
- TEST-3931 acts only on its sandbox and on a disk image it creates; it
  detaches (with a `-force` fallback). TEST-3932 reaps its own sleep by exact
  pid. The r1 checks on signals, ancestors, pid identity, mutation context
  and exit codes still hold (re-read; suite PASS).

### INFO (never gates)

- If both detaches in TEST-3931 fail, the suite's `cleanup()` (test file
  line 64) runs `rm -rf "$TR_TMP"` over the still-mounted image, the same
  pattern BLOCKING-1 was about; it only reaches the test's own image.
- Files appearing or vanishing inside the root between the two walks (a
  surviving process that closed descriptor 9) make the counts differ and
  keep the root with a "mounted inside" reason that is not the real cause;
  safe direction.
- Each run now walks the root twice before removing it; cost grows with
  what the run left in its temp root.

## cannot_verify

1. Linux behaviour of the new mount checks (GNU find, util-linux `mount`,
   dash): closes with the PR's Linux CI leg (TEST-3931 runs only the shim
   legs there).
2. lsof cost in Linux containers with a very high `RLIMIT_NOFILE`: closes
   with one timed run in such an image.
3. pid reuse between the last lsof check and `kill`: not closable in POSIX
   sh; mitigated by lstart identity plus the marker-on-fd-9 requirement.
4. Git Bash path stays off: closes with the Windows CI leg.

## Warning dispositions (H6, recommended; the orchestrator records them)

- r2 NON-BLOCKING-1: promote to follow-up (widen `fu-tree-lsof-unbounded`
  or file `fu-tree-mount-walk-unbounded`; suggested, not filed).
- r1 NON-BLOCKING-2: already `fu-tree-lsof-unbounded` (filed by the orchestrator).

## Next steps

Record the disposition above; the scope is review-ready for the PR step.

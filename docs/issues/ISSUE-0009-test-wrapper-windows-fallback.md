---
id: test-wrapper-windows-fallback
type: issue
number: 9
status: draft
links:
  pr: []
  commits: []
---

# Issue — Test Wrappers Are Bash/POSIX-Only; No Deterministic Windows Fallback

## Summary
`.aai/scripts/aai-run-tests.sh` and `.aai/scripts/aai-reap-tests.sh` are
POSIX `sh`/bash scripts that assume a Unix-like process-group model
(`setsid`, `perl POSIX::setsid`, `kill -TERM -<pgid>`, bash job control).
On native Windows without WSL (no bash, no `setsid`, no POSIX signal
semantics), invoking them fails, and — because the loop runner has no
environment-detection step before shelling out to these wrappers — it fails
NONDETERMINISTICALLY depending on which shell happens to be on PATH (Git
Bash present vs absent, WSL present vs absent) rather than failing clearly
or falling back to a working path.

## Type
- bug (portability gap, not a regression)

## Impact
- Who/what is affected: any downstream AAI project's contributor or CI
  runner operating on native Windows without WSL. Git Bash alone (common
  Windows dev setup — ships with Git for Windows) does NOT guarantee
  `setsid` or POSIX signal group semantics identical to Linux/macOS, so even
  where a shell is found, the wrapper's process-group-kill contract
  (SPEC-0009 / ISSUE-0002: "no descendant of the command can outlive this
  call") is not proven to hold there.
- Severity/priority: medium — does not affect this repo's own CI/dev
  environment (macOS/Linux), but blocks/degrades the AAI loop for any
  Windows-only downstream project, and failure mode is currently silent/
  nondeterministic rather than a clear, actionable error.

## Current Behavior
- `.aai/scripts/aai-run-tests.sh` (and the sibling `aai-reap-tests.sh`) are
  invoked directly as `sh`/bash scripts by the loop/test-running machinery
  with no upstream check for interpreter availability or platform.
- On Windows: if WSL is present, `bash` resolves via WSL and the script may
  work as intended (Unix semantics available). If WSL is ABSENT but Git
  Bash is installed, the script may partially run under Git Bash's MSYS
  environment, where `setsid`/process-group signal delivery is not
  guaranteed to match the script's stated contract (SPEC-0009 comment
  block, lines 45-55, explicitly reasons about "the Linux /bin/sh" and
  macOS as the two supported cases — Windows is not analyzed). If NEITHER
  WSL nor a POSIX-ish shell is present, the invocation fails with a generic
  "command not found" / non-zero exit with no diagnostic naming the actual
  cause (missing interpreter vs. a real test failure), which the caller
  cannot reliably distinguish from a genuine test failure.
- Net effect: behavior differs across three Windows configurations (WSL
  present / Git Bash only / neither) with no explicit detection or
  documented supported matrix, so the same downstream project can see the
  loop work on one contributor's machine and fail unexplainably on
  another's.

## Expected Behavior
- The wrapper (or a thin dispatcher in front of it) deterministically
  detects the environment at invocation time:
  1. WSL present -> use it (current implicit behavior, made explicit).
  2. WSL absent, native Git Bash present -> fall back to a documented,
     supported native-Git-Bash code path (which may need its own narrower
     process-group strategy, since `setsid`/POSIX signal groups are not
     guaranteed identical under MSYS — this needs its own investigation,
     not assumed to be a no-op fallback).
  3. Neither available -> fail immediately with a CLEAR, actionable error
     naming the missing interpreter (not a silent/ambiguous non-zero exit
     that could be mistaken for a test failure).
- The supported environment matrix (which OS/shell combinations are
  supported, and what the fallback guarantees vs. does not guarantee about
  process-group cleanup) is documented alongside the wrapper (in the script
  header comment and/or `docs/TECHNOLOGY.md`).

## Steps to Reproduce (if applicable)
1. On a native Windows machine with Git for Windows installed and WSL
   NOT installed, run `.aai/scripts/aai-run-tests.sh <any test command>`
   from a plain `cmd.exe`/PowerShell prompt (not inside Git Bash).
2. Observe: the invocation either fails to find an interpreter for the `sh`
   shebang, or (if run from within Git Bash directly) proceeds without any
   confirmation that the `setsid`/process-group kill contract actually
   holds under MSYS.
3. Compare against the same command run from within WSL: behaves per the
   script's documented contract (SPEC-0009).

## Verification
- A documented, deterministic interpreter-resolution step that: selects WSL
  when present; falls back to a defined native-Git-Bash path when WSL is
  absent but Git Bash is present; and exits with a clear, named error when
  neither is available.
- Manual verification on a Windows machine (or CI Windows runner) in each of
  the three configurations (WSL present / Git-Bash-only / neither),
  confirming the observed behavior matches the "Expected Behavior" section
  for each.
- If a native-Git-Bash fallback path is implemented, a targeted check that
  its process-cleanup guarantee (or documented lack thereof) is explicit —
  not silently assumed equivalent to the Linux/macOS contract.

## Constraints / Risks
- Git Bash's MSYS environment does not provide true POSIX process groups —
  a native fallback may need a materially different reaping strategy (e.g.
  Windows `taskkill /T` on the process tree) rather than a drop-in
  `setsid`/`kill -TERM -pgid` substitution; this is real design work, not a
  detection-only fix.
- This repo's own environment (macOS/Linux, per `docs/TECHNOLOGY.md`) is
  unaffected — this issue is scoped to portability for downstream AAI
  projects running natively on Windows, and should not regress the existing
  macOS/Linux contract (SPEC-0009) in any way.
- CI coverage for the Windows fallback path may not exist in this repo's own
  pipeline; verification may need to lean on manual runs or a
  downstream-project report until/unless a Windows CI runner is added.

## Notes
- Evidence: `.aai/scripts/aai-run-tests.sh` header comment (lines 1-28) and
  the setsid/perl/bash-job-control fallback chain (lines 45-69) explicitly
  reason about Linux and macOS only ("macOS has no GNU `timeout`"; "the
  Linux /bin/sh"); Windows is absent from the documented contract entirely.
  `.aai/scripts/aai-reap-tests.sh` shares the same POSIX assumption.
- Filed as part of the same 2026-07-17 intake batch responding to EEX
  downstream operator feedback (a Windows-based downstream contributor
  scenario) and independent in-repo confirmation that the wrapper's own
  header never analyzes the Windows case.

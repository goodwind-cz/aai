---
id: ps1-wrapper-path-dup
number: 133
type: change
status: done
user_visible: true
ceremony_level: 2
capability: windows-test-wrapper
links:
  commits:
    - 83e0ff3946497b7388f93f9fa17c9f5a4316ea25
  pr:
    - 247
---

# Change — aai-run-tests.ps1: Path/PATH duplicate kills Start-Process; failure masquerades as timeout 124

## Summary
- Downstream owner report (Codex/Windows AAI project, 2026-08-12, with a
  minimal reproduction): three separate defects in the Windows test
  wrapper's Git Bash branch (aai-run-tests.ps1:239 area):
  1. The process environment can carry BOTH `Path` and `PATH`; Windows
     PowerShell builds a case-insensitive dictionary for Start-Process and
     dies with "Item has already been added. Key in dictionary: 'Path'".
  2. The wrapper does not catch that failure: Start-Process returns no
     process, the wait logic operates on $null, and the wrapper returns
     124 — a FAKE timeout for a test run that never started. Repro: direct
     `python --version` passes; the same command through the wrapper fails
     with the Path/PATH error and exits 124.
  3. Process cleanup weakness: a hanging wrapper/subagent process was
     observed once on a failure path (not proven caused by the dup, but
     the cleanup does not cover the Start-Process-failed branch).
- Cost of the defect class downstream: a validator burned ~20 minutes of
  wall time and weekly-limit tokens orchestrating around a wrapper that
  had never run anything (actual validation content: 42 seconds).
- Owner changed nothing downstream; the fix belongs in the vendored
  wrapper.

## Acceptance Criteria
- AC-001: before any process spawn, the wrapper normalizes the environment
  case-insensitively — exactly one canonical `Path` entry survives (values
  merged deterministically, duplicate keys of ANY casing collapsed), on
  both the WSL and Git Bash branches.
- AC-002: a Start-Process (or equivalent spawn) failure exits with an
  EXPLICIT infrastructure error — its own exit code distinct from 124 and
  from test exit codes, a stderr line naming the real exception — and
  never reaches the wait logic with $null; 124 remains reserved for a
  genuine timeout of a process that RAN.
- AC-003: failure paths (spawn failed, WSL E_ACCESSDENIED fallthrough)
  leave no orphan wrapper/child processes; the branch taken (WSL vs Git
  Bash) is named in the wrapper's diagnostic output.
- AC-004: RED-first tests in the ps1 test surface (Pester/test-ps1-quality
  conventions): dup Path/PATH env → pre-fix reproduces the dictionary
  error path, post-fix the command RUNS; spawn-failure injection → infra
  exit code + named stderr, not 124; both proven on the repo's pwsh.
- AC-005: parity check on aai-run-tests.sh (POSIX twin) — confirm the
  failure-masquerade class does not exist there or fix identically; docs
  (USER_GUIDE/product doc of the wrapper if present) updated truthfully.

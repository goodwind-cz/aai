---
id: pester-on-windows-ci
number: 134
type: change
status: done
user_visible: false
ceremony_level: 1
links:
  commits:
    - d5f4c403d0dd217324c42cb599137e8855a19823
  pr:
    - 248
---

# Change — Run the full Pester suite on real Windows CI under both engines

## Summary
- CHANGE-0133 cost four blind ~10-minute e2e CI iterations for defects that
  were ALL unit-testable on a real Windows engine (5.1 Handle/ExitCode-null,
  env-dictionary semantics, quoting): the 111-test Pester suite runs only
  on pwsh (macOS/Linux); the windows-latest job does parse + smoke only.
- Close that gap: the ps1-quality windows job runs the FULL Pester suite
  under Windows PowerShell 5.1 AND pwsh 7, so engine-specific runtime
  semantics fail in unit tests, not in e2e archaeology.

## Acceptance Criteria
- AC-001: .github/workflows/ps1-quality.yml windows job gains Invoke-Pester
  steps over tests/skills/*.Tests.ps1 under BOTH engines (powershell.exe
  and pwsh); a Pester failure fails the job; runtime stays reasonable
  (suite is ~2 min locally).
- AC-002: tests that are inherently host-specific (paths, POSIX-only
  fixtures) are skipped on Windows via Pester tags/skip conditions with a
  NAMED reason — never silently green; the skip count is printed.
- AC-003: the same latent Test-WslUsable existence-probe bug found in
  aai-reap-tests.ps1 (CHANGE-0133 follow-up) is fixed with the identical
  functional-probe pattern + Pester coverage, so the reaper cannot route
  into a distro-less WSL.
- AC-004: docs (product doc windows-test-wrapper.md + workflow header)
  state the fast-iteration path: workflow_dispatch runs the windows job
  standalone; recorded so the next Windows debugging session does not
  rediscover it.

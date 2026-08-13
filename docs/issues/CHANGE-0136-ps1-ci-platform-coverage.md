---
id: ps1-ci-platform-coverage
number: 136
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: windows-test-wrapper
---

# Change — ps1-quality: close the three CI platform blind spots (functional WSL, 5.1-only hosts, image drift)

## Summary
- Owner ask 2026-08-13 ("co by se mělo nebo dalo pro to vylepšit, aby bylo
  testováno na všech platformách?" → "ano 1+2+3"): after CHANGE-0135's PR,
  three blind spots remain in the Windows CI surface, and two of them have
  already produced real escapes:
  1. **Functional WSL**: GitHub windows runners have wsl.exe with NO distro,
     so the wrapper's WSL branch has NEVER run end-to-end in CI — both Codex
     P1 findings on PR #249 (untranslated marker path, System32 PATH leaking
     wsl.exe past the decoy) lived exactly there and were caught by a bot,
     not a test.
  2. **5.1-only hosts**: runners carry BOTH engines, so every
     prefer-pwsh-else-powershell fallback (Resolve-SelfTestEngine, doctor's
     engine pick) always takes the pwsh arm in CI; the powershell.exe-only
     path — a common downstream corporate configuration — is never exercised.
  3. **Image drift**: ps1-quality runs only on PR/dispatch, so a Git
     Bash/Pester/pwsh image update breaks the next unrelated PR instead of a
     scheduled canary run.

## Acceptance Criteria
- AC-001 (functional-WSL leg): the ps1-quality windows job (or a sibling
  matrix leg) installs a WSL1 distribution on windows-latest (known-good
  action, e.g. Vampire/setup-wsl; WSL2 is unavailable on hosted runners —
  the limitation is DOCUMENTED, never papered over) and, with WSL genuinely
  usable, proves end-to-end: the wrapper routes via the WSL branch
  (AAI-BRANCH: WSL), the three-arm smoke passes with WSL semantics (marker
  translated and written, timeout 124, spawnfail contract), and the
  host-adaptive doctor/CAT-14 Pester test passes with the WSL routing.
- AC-002 (5.1-only leg): a CI step or leg hides pwsh from the effective
  PATH and proves the fallbacks for real: Resolve-SelfTestEngine and the
  doctor's engine selection pick powershell.exe, and the CAT-14 self-test
  still passes all three arms under that engine; the leg fails loudly if
  the hiding itself silently stopped working (control assertion that pwsh
  is NOT resolvable in the doctored context).
- AC-003 (scheduled canary): ps1-quality gains a weekly cron trigger; a
  scheduled failure is distinguishable from PR noise (run-name or summary
  line names the canary), and the fast-iteration docs gain one sentence on
  it. No new notification plumbing — visibility via the Actions UI/scryer
  is enough for this scope.
- AC-004 (honesty + budget): each new leg prints the same result-floor
  discipline as the existing gate (counts pinned or floored, skips named);
  total added wall-clock for the windows job stays within reason
  (~+5 min budget for the WSL leg); WSL1-vs-WSL2 difference is stated in
  the workflow header and the wrapper product doc.
- AC-005: tests per repo conventions — workflow-shape assertions in the
  existing bash suite that pins ps1-quality.yml (or its sibling), RED-first
  where a contract is new; docs (windows-test-wrapper product doc,
  TECHNOLOGY if the platform matrix changes) updated truthfully.

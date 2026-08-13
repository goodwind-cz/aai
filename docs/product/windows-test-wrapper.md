---
id: windows-test-wrapper
type: product
capability: windows-test-wrapper
status: current
delivered_by:
  - CHANGE-0133
  - ps1-wrapper-path-dup
  - CHANGE-0134
  - pester-on-windows-ci
  - CHANGE-0136
  - ps1-ci-platform-coverage
  - canonical-test-invocation
spec: docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md
updated: 2026-08-13
---

# Windows test wrapper stops lying about timeouts it never caused

## What it does

On Windows, running the factory's test/build commands goes through
`.aai/scripts/aai-run-tests.ps1`, which hands off to the same
process-group-safe wrapper macOS and Linux use. A downstream report found
that on some Windows machines the process environment can carry the same
variable twice under different capitalization (both `Path` and `PATH`) —
invisible in an ordinary PowerShell prompt, but fatal to the exact
dictionary the wrapper needs to build before launching anything. Before
this fix, that collision made the wrapper crash before the wrapped command
ever ran, and it reported the run as **timed out** — the same code used
for a test suite that genuinely hangs — so a person or an AI agent
debugging the failure would look for a slow test instead of the real
cause, burning real time chasing a phantom hang. The wrapper now cleans up
any duplicate-cased environment variable before it launches anything, and
if a launch still cannot start for some other reason, it reports that
honestly with its own distinct signal instead of pretending the run timed
out.

## How to use it

Nothing to configure — this is the existing Windows test-wrapper command.
The canonical invocation (CHANGE-0139), from the repository root, is:
`powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1 <command> [args...]`.
`powershell.exe` exists on every Windows host — including 5.1-only corporate
machines where `pwsh` is not installed (`pwsh -NoProfile -File ...` runs
identically where present, but it is not the canonical shape). Keeping this
one fixed repo-root literal is what makes approval allowlists work: an
operator approves the stable command prefix once, instead of re-approving
every ad-hoc variation. The environment cleanup and the failure signal
both happen automatically on every invocation.

## Data model

None. No new files or persistent records — the fix operates purely on the
current process's in-memory environment variables for the duration of one
wrapper invocation.

## Interfaces and contracts

- Exit code **124** keeps its existing meaning: the wrapped command
  actually started running and was killed after exceeding the timeout.
- Exit code **125** is new: the wrapper itself could not start the
  wrapped command at all (an infrastructure failure, such as the
  duplicate-variable collision this fix closes). One line on stderr
  beginning `AAI-SPAWN-ERROR:` names which launch path failed (WSL or Git
  Bash) and the underlying error, so the real cause is visible instead of
  guessed at.
- Exit code **78** is unchanged: no usable Windows Subsystem for Linux or
  Git Bash was found at all, so no run was attempted.
- No command-line flags or environment variables were added; the fix is
  entirely internal to how the wrapper prepares to launch.

## Fast-iteration path (CHANGE-0134)

The `windows-5_1` job in `.github/workflows/ps1-quality.yml` runs the full
`tests/skills` Pester suite under both Windows PowerShell 5.1 and pwsh 7 on
every relevant push/PR. It can also run the whole ps1-quality workflow via
`workflow_dispatch`, on demand and without opening a PR:

```
gh workflow run ps1-quality.yml
```

This is the fast-iteration path for a Windows debugging session: a defect
that is unit-testable in the Pester suite now fails there, in the same job
that already parse-checks every script, instead of only surfacing after a
blind end-to-end iteration.

The same workflow also runs as a weekly scheduled canary (Mondays 05:00
UTC, CHANGE-0136): a failure on one of those scheduled runs means the
GitHub runner image drifted (a Git Bash / Pester / pwsh / WSL update), not
that any pull-request change broke something — the run name marks canary
runs in the Actions list so the two are never confused.

## What CI proves per platform (CHANGE-0136)

- **Functional WSL, WSL1 only**: the `windows-wsl1` job installs a real
  WSL1 Debian distribution on the runner and proves the wrapper's WSL
  branch end-to-end — routing (`AAI-BRANCH: WSL`), the marker path
  translated via `wslpath`, the timeout (124) and spawn-failure (125)
  contracts, and the full Pester suite with WSL genuinely usable.
  WSL1-coverage caveat: GitHub-hosted runners cannot run WSL2 at all (no
  nested virtualization), so WSL2-specific failures — for example the
  E_ACCESSDENIED class — remain field-only and are never claimed by CI.
- **5.1-only hosts**: the `windows-5_1` job additionally proves the
  prefer-pwsh-else-powershell fallbacks in a doctored child context where
  `pwsh` is genuinely not resolvable (the common corporate shape: Windows
  PowerShell 5.1 plus Git Bash, no pwsh). Nothing is uninstalled or renamed
  on the host — only a child process's PATH is reduced, with control
  assertions in both directions.

## Limits and non-goals

- This does not change anything about how the wrapper behaves on macOS or
  Linux, and it does not change what a genuinely hung test run looks like
  (still 124).
- The exact field scenario (a real Windows machine handing the wrapper a
  duplicate-cased environment) cannot be reproduced on this project's own
  Linux/macOS continuous integration; this fix is proven with an
  equivalent reproduction plus a real end-to-end run on Windows in CI, but
  a residual gap in full real-world coverage is documented in the spec.
- This does not add new process-cleanup guarantees beyond what the wrapper
  already provided for a run that starts successfully — it only closes the
  gap for a run that fails to start in the first place.

## Links

- Request: docs/issues/CHANGE-0133-ps1-wrapper-path-dup.md
- Spec: docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md
- Request (fast-iteration path, full Pester on Windows CI):
  docs/issues/CHANGE-0134-pester-on-windows-ci.md
- Spec (fast-iteration path, full Pester on Windows CI):
  docs/specs/SPEC-0121-spec-pester-on-windows-ci.md
- Validation evidence: docs/ai/validation/ (gitignored runtime directory —
  reports land here per ride, not committed to the repo)

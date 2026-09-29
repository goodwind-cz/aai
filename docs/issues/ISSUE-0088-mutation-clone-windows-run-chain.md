---
id: mutation-clone-windows-run-chain
type: issue
number: 88
status: done
links:
  pr:
    - 408
  commits:
    - 1912fae483177a4bcc0d591d023e8e4df355df95
---

# Issue — Windows mutation clone never reaches the mutated test

## Summary
- After the merged clone-fidelity ride, a Windows mutation run still dies before the mutation is exercised. The isolated clone is built with `git clone --local`, then the suite is launched from inside that clone.
- Three defects show up in order. Each one hides the next:
  1. The Git LFS hook is blocked by protection of the local clone, so checkout does not finish.
  2. `.aai` is gitignored, so the isolated clone lacks the test wrapper.
  3. After the wrapper is supplied, translating the project Python path between PowerShell and Git Bash still exits 127.

## Type
- bug

## Impact
- Who/what is affected: TDD mutation runs on Windows whose working tree uses Git LFS, keeps `.aai` gitignored, and resolves the project Python interpreter from local settings. The mutated test never starts, so mutation evidence cannot be recorded.
- Severity/priority: high. A correct change still cannot produce mutation evidence on the platform the previous clone-fidelity ride was meant to unblock.

## Current Behavior
- `buildIsolatedClone()` in `.aai/scripts/mutation-run.mjs` clones the source with `git clone --local --no-hardlinks`, checks out HEAD, overlays tracked working-tree bytes, and copies untracked-not-ignored paths. `runSuite()` then spawns `bash` on `.aai/scripts/aai-run-tests.sh` inside that clone.
- On a Windows tree that uses Git LFS, that local clone's protection blocks the Git LFS hook. Checkout stops before the clone is a usable working tree.
- `.aai` is gitignored in the source tree. `git clone` does not carry ignored paths, and `git ls-files --others --exclude-standard` does not list them. The closed runtime allowlist (`docs/ai/STATE.yaml`, `docs/ai/LOOP_TICKS.jsonl`) does not name `.aai`. The clone therefore has no `.aai/scripts/aai-run-tests.sh` and no Windows `.ps1` entry for the platform wrapper.
- Supplying the wrapper by hand gets past that gap. The suite still exits 127: the project Python path taken from local settings is not translated into a path both PowerShell and Git Bash can execute. 127 is command-not-found, before the mutated assertion runs.

## Expected Behavior
- A Windows mutation run whose source uses Git LFS finishes the isolated checkout. Protection of the local clone does not block the Git LFS hook.
- When the source working tree contains the test wrapper under a gitignored `.aai`, the clone that `runSuite()` uses contains that wrapper (`.aai/scripts/aai-run-tests.sh` and the Windows `.ps1` entry).
- The project Python interpreter from local settings is invoked successfully on both sides of the PowerShell and Git Bash boundary. The process exit is the suite verdict, not 127 from an untranslated path.
- The run reaches the mutated test. It does not stop on clone protection, a missing wrapper, or interpreter lookup.

## Steps to Reproduce (if applicable)
1. Windows working tree with Git LFS content, `.aai` gitignored (the vendored test wrapper is present on disk and ignored), and the project Python path recorded in central local settings.
2. Have a dirty in-scope change whose targeted tests are green.
3. Run `node .aai/scripts/mutation-run.mjs` for that TEST id, launching tests through the platform wrapper (`powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1`).
4. Observe, in order: the local clone blocks the Git LFS hook; with that bypassed, the clone has no test wrapper; with the wrapper supplied, the project Python path exits 127 between PowerShell and Git Bash.

## Verification
- On that Windows tree, the mutation clone checkout completes with Git LFS content present. The LFS hook is not refused by local-clone protection.
- The clone directory the suite runs in contains `.aai/scripts/aai-run-tests.sh` and the Windows `.ps1` entry, even though `.aai` is gitignored in the source.
- The suite's Python process is the project interpreter from local settings. The run exits with the suite verdict, not 127 from a path only one of PowerShell or Git Bash understands.
- The mutated test is what the verdict is about.
- Already-shipped clone-fidelity checks stay green: `tests/skills/test-aai-mutation-gate.sh` selectors `test_001_tracked_crlf_overlay`, `test_002_root_untracked_copied`, `test_003_eol_only_mismatch_token`, `test_004_symlink_ancestor_does_not_write_root`, `test_005_symlink_leaf_does_not_write_root`, via `bash .aai/scripts/aai-run-tests.sh` on POSIX and `powershell -NoProfile -File .aai/scripts/aai-run-tests.ps1` on Windows.
- New tests do not add or edit per-project settings templates.

## Constraints / Risks
- Known risks or constraints: SPEC-0193 (`docs/specs/SPEC-0193-spec-mutation-clone-fidelity-windows-eol.md`, merged as PR 406) already owns tracked CRLF overlay, untracked-not-ignored copy, the EOL-only diagnostic, and symlink ROOT safety. Do not redo that ride. `--include` was explicitly out of scope there and stays out of scope here. PRs 403, 404, and 405 are merged; do not reopen them. SPEC-0191 already routes Windows test launches through the platform wrapper; this issue is the mutation-clone chain after that launch. Talk about local settings generally. In the reporting environment the per-project values are already in a central `settings.ini`. This issue does not require copying those per-project files, and tests must not touch per-project settings templates. The isolated mutation must still never write the shipping tree (SPEC-0181 D7, unchanged by SPEC-0193).
- Secrets preflight results (if any secret referenced): none — no local secret is referenced.

## Notes
- Assumption: one issue for the chain. Filing the three defects separately would hide that each one is only visible after the previous one is bypassed.
- Context only, not a fix requirement: an earlier report also saw ignored local config missing from the clone, and a false RED before the mutation itself. That config is operationally already in the central `settings.ini`. Do not design test fixtures around per-project ini templates.
- Related done work that does not close this: ISSUE-0087 / SPEC-0193 (PR 406), ISSUE-0085 / SPEC-0191 (PR 404), CHANGE-0187 / SPEC-0181 D4 clone-fidelity, ISSUE-0045 (suite isolation no longer shares the shipping git).
- Implementation mode: not chosen at intake. Planning decides.

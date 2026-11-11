---
id: spec-update-ps1-git-stderr
type: spec
number: 285
status: done
mutation_gate: v1
frozen_sha256: 45231f6e09a8cc669e7c380af53a754de4cb1d84ea31976be8a37d8d253fe898
ceremony_level: 2
links:
  requirement: update-ps1-git-stderr
  rfc: null
  pr: []
  commits: []
---

# aai-update.ps1 runs its best-effort git and gh calls without dying on stderr or a nonzero exit

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0112-update-ps1-git-stderr.md
- Prior art: docs/specs/SPEC-0284-spec-install-path-parity-harness.md. It is done and frozen, and its D-ENV paragraph describes the `GIT_REDIRECT_STDERR=2>&1` workaround that this scope removes. That paragraph stays as the historical record and is not edited here.
- Technology contract: docs/TECHNOLOGY.md

Registry items closed by this scope: fu-parity-win-update-5-1-stderr. Filed during Planning and NOT CLOSED here: fu-hook-installer-not-a-repo-msg and fu-sync-ps1-merge-lib-stderr-5-1. Both are the same PowerShell class in sibling installers (`install-pre-commit-hook.ps1:119`, `aai-sync.ps1:781`), and both are outside this scope.

## Implementation strategy

- Strategy: tdd
- Rationale: The defect is deterministic, and it was observed on CI run 42972323735 (Windows PowerShell 5.1, UP-01, exit sh 0 against ps1 1). It can also be reproduced locally under pwsh 7.6.3. With `$PSNativeCommandUseErrorActionPreference = $true` inherited from a caller, the unchanged updater exits 1 and syncs nothing. Planning observed this on a scratch fixture: wrapper exit 1, no sync marker, failure at the `git -C $Target config --get` line. Because a cheap failing-first observation exists on the local engine, the fix starts RED first. The 5.1 behaviour itself can only be observed on the Windows CI legs.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: The PR is bound to the consumer-visible updater, and the main checkout is shared and holds uncommitted telemetry. The orchestrator directed the ride into a worktree.
- User decision: worktree (orchestrator-directed; recorded in STATE)
- Base ref: origin/main at b8c4973a
- Worktree branch/path: fix/update-ps1-git-stderr at /Users/ales/Projects/aai-worktrees/update-ps1-git-stderr
- Review required: true
- Review scope: .aai/scripts/aai-update.ps1; tests/skills/aai-update.Tests.ps1; tests/skills/lib/install-parity.mjs; tests/skills/lib/install-parity.test.mjs; tests/skills/install-parity.Tests.ps1 (comment line only); CHANGELOG.md (one new per-entry heading); docs/issues/ISSUE-0112-update-ps1-git-stderr.md; docs/specs/SPEC-0285-spec-update-ps1-git-stderr.md; the append-only ledger lines this ride writes (docs/ai/decisions.jsonl, docs/ai/EVENTS.jsonl, docs/ai/tests/test-runs.jsonl); diff range origin/main...HEAD.

The ceremony level is L2, not L1. The script change touches one surface, but three things argue against the lighter lane. The decisive evidence comes only from the Windows CI legs (Windows PowerShell 5.1 cannot run locally). The change also edits the shared install-parity harness that another suite owns. And the default clone path, which every Windows `/aai-update` takes, is part of the same fix. No protected L3 path is touched.

## Acceptance Criteria Mapping

- Maps to: the intake's Expected Behavior and Verification sections.
- Spec-AC-01: WHEN aai-update.ps1 runs with a local `-Repo` checkout that has no `origin` remote (so fetch and pull exit nonzero and write to stderr), from a git target with a non-canonical origin, under the engine that hosts the test, the updater SHALL exit 0 and SHALL run the source's sync (sync marker present in the target). Its stderr SHALL contain neither `NativeCommandError` nor `non-zero exit code`. On pwsh 7.3 or later, the case runs with `$PSNativeCommandUseErrorActionPreference = $true` set by the invoking wrapper.
- Verification: the Pester case TEST-3580. On the unchanged tree under pwsh 7.6, it must be observed failing with exit 1 and no marker.
- Spec-AC-02: WHEN the default clone path runs against a source URL that does not exist, every attempt in the clone cascade (gh if present, plain git, anonymous git) SHALL be tried. The updater SHALL then exit 3 with its `ERROR: could not fetch` line, never exit 1 with a terminating native-command error. WHEN the source URL is a real file:// fixture repository, the updater SHALL exit 0 and run the cloned sync. Success is decided by each attempt's exit code alone, never by stderr text.
- Verification: the Pester cases TEST-3581 (failing URL, exit 3) and TEST-3582 (fixture clone, exit 0 plus marker), both under the hosting engine and with the same wrapper preference as Spec-AC-01. Neither case is skipped on Windows: the file:// URL is built with `[System.Uri]` and no TMPDIR redirection is needed. TEST-3581 must be observed failing on the unchanged tree under pwsh 7.6.
- Spec-AC-03: WHEN the target directory is not a git repository, the updater SHALL still pass the canonical-repo guard (git config exits 1), run the sync, print `- Changed files: none (already up to date)` (git status exits 128) and exit 0, as the sh twin does.
- Verification: the Pester case TEST-3583. It must be observed failing on the unchanged tree under pwsh 7.6 with the wrapper preference.
- Spec-AC-04: Every git or gh invocation in aai-update.ps1 that discards or redirects its output SHALL go through one best-effort helper. The helper scopes `$ErrorActionPreference = 'Continue'` on its own line, tagged `# AAI-BEST-EFFORT-EAP`, and also scopes `$PSNativeCommandUseErrorActionPreference = $false`. It discards stderr, optionally returns stdout, and returns the exit code on a line tagged `# AAI-BEST-EFFORT-RC`. No line outside the helper SHALL combine a git or gh call with `*>`, `2>` or `2>&1`. The existing literal pins of TEST-006 and TEST-007 (`gh repo clone $Repo $SrcDir` once, `$CloneUrl $SrcDir` twice, three `Remove-Item -Recurse -Force $SrcDir -ErrorAction SilentlyContinue`, one for `$Tmp`) SHALL keep their counts. The file SHALL stay ASCII-only.
- Verification: the static Pester case TEST-3584, plus the unchanged TEST-006 and TEST-007 cases in the same file and `bash tests/skills/test-aai-update.sh` (0137-TEST-009, the ASCII and postamble pin).
- Spec-AC-05: The install-parity harness SHALL run the ps1 update twin with the same environment as every other step on every host. `GIT_REDIRECT_STDERR` SHALL appear nowhere in tests/skills/lib/install-parity.mjs or tests/skills/install-parity.Tests.ps1. The driver report's `notes` SHALL carry no Windows PowerShell 5.1 update NOTE. The node test that scoped the override SHALL be replaced by one that asserts no twin step (sync, update, hooks; sh and ps1) receives `GIT_REDIRECT_STDERR` with `ps5` true or false.
- Verification: `node --test tests/skills/lib/install-parity.test.mjs` (TEST-3585) and `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-install-parity.sh`. On CI, the `windows-parity` job's Windows PowerShell 5.1 step green on the PR head is the end-to-end proof of Spec-AC-01 on 5.1, with no workaround.
- Spec-AC-06: CHANGELOG.md SHALL gain exactly one new `## [unreleased] — fix(update): ...` heading entry inserted below the bare `## [unreleased]` scaffold, with the scaffold kept, and the entry SHALL name the 5.1 symptom and the fix.
- Verification: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` (TEST-3586 is its existing scaffold-count case TEST-022, exactly one bare scaffold).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN aai-update.ps1 runs with a local -Repo checkout whose fetch and pull fail and write to stderr the updater SHALL exit 0 and run the source sync with no NativeCommandError on Windows PowerShell 5.1 and on pwsh 7 with native error preference on | done | docs/ai/tdd/update-ps1-git-stderr/red.log; docs/ai/tdd/update-ps1-git-stderr/green.log; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3580.txt | — | RED locally on pwsh 7.6 via the wrapper preference; 5.1 proof is CI windows-5_1 and windows-parity |
| Spec-AC-02 | WHEN the default clone cascade runs the updater SHALL decide each attempt by exit code alone, exit 3 with its ERROR line when every attempt fails and exit 0 with the sync run when a fixture clone succeeds | done | docs/ai/tdd/update-ps1-git-stderr/red.log; docs/ai/tdd/update-ps1-git-stderr/green.log; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3581.txt; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3582.txt; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3587.txt; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3588.txt; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3589.txt | — | Same class on the path every Windows /aai-update takes; not observed failing in CI before because TEST-009 skips on Windows |
| Spec-AC-03 | WHEN the target is not a git repository the updater SHALL pass the guard, run the sync, print the no-changes evidence line and exit 0 as the sh twin does | done | docs/ai/tdd/update-ps1-git-stderr/red.log; docs/ai/tdd/update-ps1-git-stderr/green.log; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3583.txt | — | Covers the git config and git status calls |
| Spec-AC-04 | Every redirected git or gh call in aai-update.ps1 SHALL go through one tagged best-effort helper, the TEST-006 and TEST-007 literal pins SHALL keep their counts and the file SHALL stay ASCII-only | done | docs/ai/tdd/update-ps1-git-stderr/red.log; docs/ai/tdd/update-ps1-git-stderr/green.log; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3584.txt; tests/skills/test-aai-update.sh rc 0 | — | Static guard against reintroducing the raw form |
| Spec-AC-05 | The install-parity harness SHALL run the ps1 update twin without GIT_REDIRECT_STDERR or its NOTE on any host and its node test SHALL assert that no step receives the variable | done | node --test tests/skills/lib/install-parity.test.mjs 72 of 72 pass; tests/skills/test-aai-install-parity.sh rc 0; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3585.txt | — | windows-parity 5.1 leg becomes the end-to-end proof |
| Spec-AC-06 | CHANGELOG.md SHALL gain one fix(update) per-entry unreleased heading below the kept bare scaffold | done | tests/skills/test-aai-release.sh rc 0; docs/ai/tdd/spec-update-ps1-git-stderr/mutation-TEST-3586.txt | — | Consumer-visible fix |

## Implementation plan

1. RED. Add the Pester Context `best-effort native calls (update-ps1-git-stderr)` to tests/skills/aai-update.Tests.ps1 with TEST-3580, TEST-3581, TEST-3583 and TEST-3584 written against the unchanged script. Run it under pwsh 7.6 through the canonical wrapper and store the output in `docs/ai/tdd/update-ps1-git-stderr/red.log`. Expected failures: TEST-3580 (exit 1, no marker), TEST-3581 (exit 1, not 3), TEST-3583 (exit 1) and TEST-3584 (raw redirected calls found). TEST-3582 may be green on pwsh 7 when gh is absent from PATH. Record which way it went, and note that its failing-first proof is the 5.1 leg plus its mutation.
   - Engine under test: `(Get-Process -Id $PID).Path`, so the windows-5_1 job's Windows PowerShell 5.1 Pester run executes the updater under powershell.exe and the pwsh 7 run under pwsh. Invoke it through a small wrapper .ps1 in `$TestDrive`. The wrapper sets `$PSNativeCommandUseErrorActionPreference = $true` when `$PSVersionTable.PSVersion` is 7.3 or later, calls the updater with `&`, and exits with `$LASTEXITCODE`. Capture through the existing `Invoke-NativeCaptured` (tests/skills/lib/pester-native-capture.ps1), never an in-process `2>` under Stop.
   - Fixtures: a source checkout initialised with `git init -q -b main` and one commit, carrying the commit identity with `-c user.email/-c user.name` and no origin. Its `.aai/scripts/aai-sync.ps1` is a stub that writes a marker into `-TargetRoot`. The target is `git init` plus `remote add origin https://github.com/acme/foo.git` (Spec-AC-01), or a plain directory (Spec-AC-03).
2. GREEN. In .aai/scripts/aai-update.ps1, add the helper from Spec-AC-04 near `Get-NormSlug` and route every redirected git and gh call through it: the guard's `git config --get`, fetch, checkout and pull, the three clone attempts, and `git status --short`. The clone attempts keep `$cloned` decided by the returned exit code. Keep the TEST-006 and TEST-007 literal strings, for example by passing the command as a scriptblock whose text still reads `gh repo clone $Repo $SrcDir ...` and `... $CloneUrl $SrcDir`. Exit codes 2, 3 and 4, the dry-run output and the doctor postamble stay unchanged. Keep the file ASCII-only.
3. Harness. In tests/skills/lib/install-parity.mjs, drop the `ctx.ps5 ? { env: { GIT_REDIRECT_STDERR: '2>&1' } }` arm and its comment, plus the `ps5` field passed into the twin context if nothing else reads it. Drop the 5.1 NOTE from `report.notes`. Keep the `ps5` host probe and `hostMatches`, because the scenario host filter still uses them. In tests/skills/lib/install-parity.test.mjs, replace the scoping test with the TEST-3585 assertion. In tests/skills/install-parity.Tests.ps1, reword the comment at line 82 so it no longer names the removed NOTE. The behaviour of printing notes stays.
4. CHANGELOG entry (Spec-AC-06). Insert it below the scaffold; the inserted text starts by re-emitting `## [unreleased]` followed by a blank line.
5. Mutation and regression. Run mutation records for TEST-3580 to TEST-3585 (Pester rows are replayed by hand, the same way SPEC-0280 did, with the output stored under `docs/ai/tdd/spec-update-ps1-git-stderr/`). Then run the selected suites through the canonical wrapper with `env -u AAI_ROLE -u AAI_GIT_WRITE`: aai-update, aai-install-parity, aai-update-check, aai-layer-drift, aai-win-fallback, aai-win-fallback-corpus, aai-release, aai-follow-ups, aai-spec-amend, plus CORE. Also run `bash tests/skills/test-ps1-quality.sh`, which covers PSScriptAnalyzer and the Pester smoke for this file.

Edge cases: `git` missing from PATH (CommandNotFound inside the helper must not terminate; the helper returns a nonzero code). Stale `$LASTEXITCODE` from an earlier call must not leak into the helper's result. Do not set the preference variables at script scope; scope them inside the helper so the in-process `& $Sync` keeps its own Stop semantics.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3580 | Spec-AC-01 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine runs the updater with -Repo pointing at a local checkout that has no origin, from a git target with origin acme/foo; asserts exit 0, sync marker present, stderr free of NativeCommandError and non-zero exit code | target `.aai/scripts/aai-update.ps1`; `sed:s/^.*# AAI-BEST-EFFORT-EAP\n.*PSNativeCommandUseErrorActionPreference = \$false$//m` removes both scoped preference lines so the inherited Stop and native error preference apply and the case must fail | pending |
| TEST-3581 | Spec-AC-02 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine runs the updater with -Repo set to a file:// URL that does not exist; asserts exit 3 and the ERROR could not fetch line, never exit 1 | target `.aai/scripts/aai-update.ps1`; `sed:s/^.*# AAI-BEST-EFFORT-RC$/    return 0  # AAI-BEST-EFFORT-RC/` makes every attempt look successful so the exit becomes 4 and the case must fail | pending |
| TEST-3582 | Spec-AC-02 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine clones a real file:// fixture repository through the cascade, not skipped on Windows; asserts exit 0 and the cloned stub sync marker in the target | target `.aai/scripts/aai-update.ps1`; `sed:s/^.*# AAI-BEST-EFFORT-RC$/    return 1  # AAI-BEST-EFFORT-RC/` makes every attempt look failed so the exit becomes 3 and the case must fail | pending |
| TEST-3583 | Spec-AC-03 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine runs the updater from a target that is a plain directory, not a git repository; asserts exit 0, sync marker, the Changed files none line, and no REFUSED | target `.aai/scripts/aai-update.ps1`; `sed:s/^.*# AAI-BEST-EFFORT-EAP\n.*PSNativeCommandUseErrorActionPreference = \$false$//m` removes both scoped preference lines and reinstates the inherited Stop and native error preference and the case must fail | pending |
| TEST-3584 | Spec-AC-04 | unit | tests/skills/aai-update.Tests.ps1 | Static: outside the helper no line combines a git or gh call with a stderr or all-stream redirect; the helper carries both tags; the file is ASCII-only | target `.aai/scripts/aai-update.ps1`; `sed:s/^\$ErrorActionPreference = "Stop"$/$ErrorActionPreference = "Stop"; git --version *> $null/` adds one raw redirected call and the case must fail | pending |
| TEST-3585 | Spec-AC-05 | unit | tests/skills/lib/install-parity.test.mjs | No twin step (sync, update, hooks; sh and ps1) carries GIT_REDIRECT_STDERR with ps5 true or false, and the driver adds no 5.1 update NOTE to report notes | target `tests/skills/lib/install-parity.mjs`; `sed:s/cwd: ctx.target };$/cwd: ctx.target, env: { GIT_REDIRECT_STDERR: '2>\&1' } };/` reintroduces the override on twin steps and the case must fail | pending |
| TEST-3586 | Spec-AC-06 | integration | tests/skills/test-aai-release.sh | Existing TEST-022 asserts exactly one bare unreleased scaffold and the release parser accepts the new per-entry heading | target `CHANGELOG.md`; `sed:s/^## \[unreleased\]$/## [unreleased] — broken/` consumes the bare scaffold and the case must fail | pending |
| TEST-3587 | Spec-AC-02 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine runs the updater with git absent from PATH and a local -Repo checkout; asserts exit 0 and the sync marker, and that the missing executable never terminates the script | target `.aai/scripts/aai-update.ps1`; `sed:s/try { (.*) } catch .*$/\1/` removes the typed CommandNotFoundException catch and the case must fail | pending |
| TEST-3588 | Spec-AC-02 | integration | tests/skills/aai-update.Tests.ps1 | Hosting engine runs the updater with git absent from PATH and a failing file:// source; asserts exit 3 and the ERROR could not fetch line as the sh twin, never 1 | target `.aai/scripts/aai-update.ps1`; `sed:s/try { (.*) } catch .*$/\1/` removes the typed catch and the case must fail | pending |
| TEST-3589 | Spec-AC-02 | integration | tests/skills/aai-update.Tests.ps1 | Same git-less failing-clone run with the caller exit code pre-set to 0; asserts exit 3, so a stale caller code never reads as a successful attempt | target `.aai/scripts/aai-update.ps1`; `sed:s/\$global:LASTEXITCODE = \$null/\$global:LASTEXITCODE = 0/g` turns both null resets into 0 and the case must fail; removing either reset alone stays green because the two are redundant for a missing executable | pending |

Seams crossed:
- Caller engine and preference variables → updater script scope → native git/gh exit and stderr → updater exit code and the sync it runs. TEST-3580 to TEST-3583 set the caller side (hosting engine, inherited `$PSNativeCommandUseErrorActionPreference`) and assert the real exit code and the target tree. No mock of git is involved.
- Updater (ps1 twin) against its bash twin through the install-parity driver: same fixture, same environment, and the comparison of exit codes and target trees. TEST-3585 proves that the environment is now identical. The `windows-parity` 5.1 step is the only place where the real 5.1 behaviour crosses this seam. It is a CI-only observation, recorded on the PR head, and never inferred.
- update-check.mjs → aai-update.ps1 on Windows (resolveRunner prefers pwsh, else powershell). There is no automated test of this hop on 5.1 beyond the windows-5_1 Pester leg, which invokes the updater with powershell.exe directly. This is a residual risk, written down here.

## Verification

All local runs go through `.aai/scripts/aai-run-tests.sh` with `env -u AAI_ROLE -u AAI_GIT_WRITE`.

1. RED, GREEN and mutation follow Implementation plan steps 1, 2 and 5. Evidence goes under `docs/ai/tdd/update-ps1-git-stderr/` and `docs/ai/tdd/spec-update-ps1-git-stderr/`.
2. Pester: `pwsh -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-update.Tests.ps1 -PassThru"` with FailedCount 0, and `bash tests/skills/test-ps1-quality.sh` with exit 0.
3. Node: `node --test tests/skills/lib/install-parity.test.mjs` with exit 0. Run `bash tests/skills/test-aai-install-parity.sh` (default matrix on POSIX) with exit 0.
4. Selected suites (see Implementation plan step 5), each exit code recorded. One full sweep before close, per the ride's standing practice.
5. CI on the PR head, observed and never inferred: ps1-quality.yml jobs `gate` (Linux pwsh 7), `windows-5_1` (full Pester under Windows PowerShell 5.1 and pwsh 7; it runs TEST-3580 to TEST-3584 under powershell.exe) and `windows-parity` (install-parity under 5.1 and 7, with no `GIT_REDIRECT_STDERR` NOTE in the log). Also the skill-suite workflow.
6. PASS criteria: every TEST row green, every Spec-AC done with evidence, and the CI jobs above green on the PR head.

## Evidence contract

Each artifact records the ref_id update-ps1-git-stderr, its Spec-AC and TEST links, the command, the exit code and the evidence path, plus the commit SHA once one exists. RED and GREEN logs are stored under docs/ai/tdd/ (strategy tdd). Mutation records go under docs/ai/tdd/spec-update-ps1-git-stderr/.

Residual risks:
- Windows PowerShell 5.1 cannot be run locally. The 5.1 claims rest on CI only. If a 5.1 leg reveals a further 5.1-only stderr path in the in-process sync, that path belongs to fu-sync-ps1-merge-lib-stderr-5-1 and is not widened into this scope.
- SPEC-0284's D-ENV text keeps describing the removed workaround, as the historical record of a done spec.

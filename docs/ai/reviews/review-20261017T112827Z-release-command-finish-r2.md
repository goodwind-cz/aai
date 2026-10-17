```yaml
review:
  scope: "git diff b6f740783f6df8885bfc49a56fb3b4225f7538e5..2f13ad79 (33 files, +1787/-438; branch change/release-finish-one-command); round-2 delta cbf0cdcd..2f13ad79 (ab70289e, 2f13ad79)"
  spec: docs/specs/SPEC-0233-spec-release-command-finish.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/release-finish.mjs historyBoundary/audit (unchanged since r1 review, CR-1 fixed); TEST-001..003 green (validation r8 aai-release rc 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/release-finish.mjs:313-321 (gh exit 0/1/8, empty/malformed refuse), merge path with --match-head-commit, no --auto/--admin; TEST-004/005" }
      - { ac: Spec-AC-03, call: compliant, citation: "release-finish.mjs:413-415 merge-SHA run, peeled tag, trimmed body equality before cleanup; .github/workflows/release.yml no auto-generated fallback; TEST-006" }
      - { ac: Spec-AC-04, call: compliant, citation: "CR-3 fixed: release-finish.mjs:15-21 samePath/worktreeBlock, :361 realpathSync.native, :363 and :378 worktreeBlock, :418 trimEnd; TEST-702 (Windows-form inputs on any OS) + tests/skills/lib/release-finish-worktree-identity.mjs; hosted run 39022783097 step 'Release finish worktree identity on Windows (CR-3)' = success, log 'PASS: release-finish worktree identity on win32'; TEST-007..009" }
      - { ac: Spec-AC-05, call: compliant, citation: "hosted run 39022783097 at ab70289e (success): Windows 5.1 and pwsh7 Pester 152/0/4 with native SHA/URL cases, Linux leg; 2f13ad79 changes only ps1-quality.yml path triggers" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/SKILL_RELEASE.prompt.md:86 (NB-6 exit-20 annotation), product doc, PROFILES, suite-map (+probe glob), prompt-diet ledger, catalogs; product-doc staleness (r1 NB-5) deferred to ship step by recorded disposition" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 423, issue: "run-directly guard (main() only when argv[1] realpath URL equals import.meta.url) is correct by construction but no Windows case proves main() executes; a false negative is silent and fails open", failure_scenario: "If the guard evaluated false on a Windows invocation (& node (Join-Path $PSScriptRoot 'release-finish.mjs') ... in aai-release.ps1:130/287), --audit prints nothing and exits 0, so $unlogged is empty: preview says 'ready to cut' and the -NoRemote cut skips the missing-notes refusal (aai-release.ps1:329); remote -Confirm exits 0 with no output and nothing done. Hosted run only proves the guard is false on import (probe passed), not true on direct run." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-release.ps1, line: 284, issue: "NB-1 fix uses 'git remote get-url origin *> $null' under $ErrorActionPreference = 'Stop' (:93); git writes 'error: No such remote origin' to stderr exactly in the no-origin case (verified locally, rc 2), and Windows PowerShell 5.1 promotes redirected native stderr to a terminating NativeCommandError (the repo's own aai-win-dispatch.Tests.ps1:1003 records this 5.1 promotion as proven in PR #248)", failure_scenario: "Windows PowerShell 5.1, repo without origin, gh authenticated: aai-release.ps1 -DryRun terminates at :284 (try/finally has no catch) with exit 1 and a NativeCommandError instead of printing the plan; shell frontend exits 0. TEST-703 covers only pwsh 7 (Linux/macOS). Fix: 'git -C $Root config --get remote.origin.url' (silent rc 1 when absent, verified) or Invoke-NativeChecked in try/catch." }
  cannot_verify:
    - { claim: "release-finish.mjs end-to-end finish on Windows (journal, claim, worktree add/remove, base-index sync) under PowerShell 5.1/pwsh7", closes_with: "One finish fixture executed on hosted windows-latest; current hosted proof covers only worktree identity (CR-3 probe) and native capture controls" }
    - { claim: "Direct-run guard evaluates true on Windows for the ps1 invocation style", closes_with: "Hosted Windows step asserting 'node .aai/scripts/release-finish.mjs --version v1' exits 20 with 'REFUSED: confirmation' (see NB-R2-1)" }
    - { claim: "NB-R2-2 stderr promotion on Windows PowerShell 5.1 for '*> $null'", closes_with: "Run the no-origin -DryRun case (TEST-703 shape) on the hosted 5.1 engine; not reproducible on this macOS host (pwsh 7 only)" }
    - { claim: "Live GitHub semantics (required-check registration latency, gh run list --commit, squash title feeding release.yml regex)", closes_with: "Real disposable-repo release; follow-up fu-release-checks-registration-grace tracks the known latency risk" }
    - { claim: "External race between final base observation and GitHub merge", closes_with: "Not closable client-side; disclosed spec limitation" }
  overall: pass
```

# Independent Code Review r2 - release-command-finish

**Verdict: PASS (conditional on the two NON-BLOCKING dispositions below).** CR-3 is fixed and proven on a real Windows runner. NB-1, NB-4 and NB-6 are remediated, and NB-2/NB-3 are filed as follow-ups. No BLOCKING finding remains. Both new findings are non-blocking Windows-assurance items in the round-2 delta.

## Scope and independence

- Root `/Users/ales/Projects/aai-change-release-finish-one-command`, branch `change/release-finish-one-command`, HEAD `2f13ad79`.
- Full scope `b6f74078..2f13ad79`. I read the round-2 delta `cbf0cdcd..2f13ad79` (ab70289e, 2f13ad79) line by line. The rest of the scope was reviewed in r1 and is unchanged since `cbf0cdcd`. The spec is unchanged since r1 (frozen).
- STATE: `worktree.user_decision: worktree`, `inline_review_scope: null`. `git status --porcelain` shows only `docs/ai/tests/test-runs.jsonl`, which is test telemetry outside the scope, so the scope is clean.
- Dispatch note: the dispatch named round-1 findings and areas of the delta to inspect. It did not pre-rate severity or exclude any area, so I recorded it as area focus, not coaching.

## Round-1 findings: verification

| R1 finding | Status | Evidence |
|---|---|---|
| CR-3 BLOCKING (Windows worktree string compare) | **Resolved** | `samePath` normalizes `\` to `/`, strips trailing slashes, and case-folds on win32 (release-finish.mjs:15-18). `worktreeBlock` is used at both registration lookups (:363, :378). The preparation dir is created with `realpathSync.native` (:361), so 8.3 names expand to the long form, the same form Git for Windows stores. The cleanup check trims line ends (:418). The hosted run 39022783097 step "Release finish worktree identity on Windows (CR-3)" passed; its log shows `PASS: release-finish worktree identity on win32` on windows-latest, where TEMP uses `RUNNER~1`. The probe also proves the removed worktree is no longer found. A local probe run passed on darwin. |
| NB-1 PS1 preview without origin | **Resolved on pwsh 7, incomplete on Windows PowerShell 5.1** | aai-release.ps1:283-286 now checks for origin before adding `--online`. TEST-703 passes under pwsh 7. On 5.1 the new check itself can terminate the script; see NB-R2-2. |
| NB-2 checks registration grace | Follow-up | `fu-release-checks-registration-grace` (P2) is in decisions.jsonl. |
| NB-3 heading multiset | Follow-up | `fu-release-notes-heading-multiset` (P3) is in decisions.jsonl. |
| NB-4 version vs tag pattern | **Resolved** | `validTagVersion` `/^v?[0-9]\S*$/` (:23) matches release.yml:42 `v?[0-9][^[:space:]]*`. It is checked at :328 after check-ref-format and before `gh auth status`, the journal or the claim. Verified locally: `--version stable-2026 --confirm` gives rc 20 `REFUSED: version` with nothing written. TEST-702 asserts this. |
| NB-5 stale product doc | Deferred (recorded) | To be updated at the ship/product-docs step after LOOP COMPLETE. Still pending; it must not be dropped. |
| NB-6 exit-code table | **Resolved** | SKILL_RELEASE.prompt.md:86 now states that 12/13/15/16 surface as 20 on remote `--confirm`. This matches the shell, which delegates at aai-release.sh:107 after the 10/11 checks. |

## Spec-compliance AC walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | Audit logic is unchanged since r1 (CR-1 fixed). TEST-001..003 green (validation r8). |
| Spec-AC-02 | compliant | Unchanged; TEST-004/005. |
| Spec-AC-03 | compliant | Unchanged; TEST-006. |
| Spec-AC-04 | compliant | CR-3 fixed and proven on hosted win32 (above). Resume, leases and sync are unchanged; TEST-007..009 plus TEST-702. |
| Spec-AC-05 | compliant | Hosted run 39022783097 at ab70289e: Windows 5.1 and pwsh7 Pester 152/0/4 with the native SHA/URL cases. 2f13ad79 changes only path triggers. Validation r8 judged the pre-existing hosted evidence still valid, and I agree. PR CI will re-run it. |
| Spec-AC-06 | compliant | Prompt exit-code annotation, suite-map glob for the probe, and companions. The product doc is deferred to the ship step. |

Deviations from the frozen spec: none. TEST-702 and TEST-703 are suite-internal additions under AC-04 and AC-05.

## Fresh pass over the delta

### Run-directly guard (release-finish.mjs:422-423)

`main()` runs only when `import.meta.url === pathToFileURL(fs.realpathSync(process.argv[1])).href`.

**On POSIX this triggers.** I verified it empirically under Node 22.23.1 with four invocation styles; each reached `main()` and returned the expected exit 20 refusal:
- an absolute path;
- `./release-finish.mjs` from the scripts directory;
- a non-normalized `.aai//scripts/../scripts/` path;
- a symlinked parent directory whose name contains spaces, `#` and `%`.

**On Windows I reasoned from Node's loader.**
- Node path-resolves `process.argv[1]` at startup.
- `resolveMainPath` applies the same JS `fs.realpathSync` (not `.native`) to the same `path.resolve(argv[1])`.
- `finalizeResolution` re-applies that realpath, then the result goes through the same `pathToFileURL`.
- Drive-letter case, 8.3 segments and percent-encoding therefore pass through identical functions on both sides. I expect the guard to hold for the ps1 style `& node (Join-Path $PSScriptRoot 'release-finish.mjs')` and for the Git Bash style `node /c/...`, which MSYS converts to `C:/...`.

**What the hosted evidence covers.** The CR-3 probe imports the module on win32 and passed, which proves only the false-negative-on-import direction (`main()` did not run on import). Nothing proves the direct-run direction on Windows, and a miss there fails open silently. Hence NB-R2-1.

**Arguments are parsed at import time (:25-34).** An importer that has its own CLI arguments would throw `Unknown release-finish argument` at import. The only importers today (the probe and the TEST-702 heredoc) pass none. INFO.

### samePath / worktreeBlock / realpathSync.native

These are correct for the forms Git for Windows prints. Case folding is limited to win32, and POSIX stays case-sensitive (TEST-702 asserts both). The base-sync lookup (:252) uses the Git-printed path only as a cwd, so it is unaffected. Any journal path written before this fix would be non-native, but the feature is unreleased, so no such journals exist.

### validTagVersion

The pattern matches release.yml's regex. Where they differ (Unicode whitespace allowed by check-ref-format), JS `\S` refuses more than bash `[^[:space:]]`, which is the safe direction. INFO: the refusal's `Resume:` line repeats the invalid version, which can never succeed.

### ps1 origin check

See NB-R2-2. The pre-existing `rev-parse -q --verify ... *> $null` at :272 is safe because `-q` writes no stderr. The new `remote get-url` writes stderr exactly in the case the check exists for.

### CI step and probe

The step runs under `shell: pwsh` on the Windows job and creates its temp dirs with `realpathSync.native`, exactly as production does. It cleans up in `finally`, and its asserts fail the step (it passed in the hosted run). Commit 2f13ad79 drops the probe from the ps1-quality path triggers. `release-finish.mjs` remains a trigger (:73/:92), so an edit to the probe alone will not re-run the workflow. That is acceptable because the probe has no behaviour of its own.

## Code-quality findings

No BLOCKING findings.

### NB-R2-1 - NON-BLOCKING (P2) - No Windows proof that the direct-run guard triggers

- **Where:** `.aai/scripts/release-finish.mjs:423`.
- **Failure scenario:** suppose the guard evaluates false on a Windows invocation.
  - `aai-release.ps1:287` would get empty audit output with rc 0. The preview would report "ready to cut", and the `-NoRemote` cut would skip the missing-notes refusal at `:329`. That is a silent fail-open of the notes gate.
  - `-Confirm` at `:130` would exit 0 with no output and no action.
- **Assessment:** I judge the guard correct by construction (see the analysis above), so this is an assurance gap rather than an observed defect. It is cheap to close.
- **Recommended disposition: remediate-in-tree.** Add to the CR-3 hosted step an invocation in the ps1 style, `node (Join-Path $PWD '.aai/scripts/release-finish.mjs') --root $PWD --version v1`, and assert exit 20 with `REFUSED: confirmation`. Optionally make the ps1 front end treat a `--confirm` run with rc 0 and no `## aai-release — complete` line as a refusal. If deferred: follow-up `fu-release-finish-win-direct-run-proof` (P2).

### NB-R2-2 - NON-BLOCKING (P3) - NB-1 fix still breaks the no-origin preview on Windows PowerShell 5.1

- **Where:** `.aai/scripts/aai-release.ps1:284`, which runs `git -C $Root remote get-url origin *> $null` under `$ErrorActionPreference = "Stop"` (:93).
- **Cause:** I verified locally that git prints `error: No such remote 'origin'` to stderr with rc 2 in exactly the no-origin case. Windows PowerShell 5.1 promotes redirected native stderr to a terminating NativeCommandError; the repo already records this as proven on real 5.1 (`tests/skills/aai-win-dispatch.Tests.ps1:1003`, PR #248). The surrounding `try` has no `catch`.
- **Failure scenario:** on PowerShell 5.1, with no origin and gh authenticated, `-DryRun` exits 1 with a NativeCommandError, while `aai-release.sh --dry-run` exits 0. TEST-703 runs only under pwsh 7, and the hosted 5.1 Pester does not cover this case.
- **Recommended disposition: remediate-in-tree.** Replace the call with `git -C $Root config --get remote.origin.url *> $null`, which returns rc 1 with no stderr when origin is absent (verified). This mirrors identity() at release-finish.mjs:330. If the one-line fix is deferred: follow-up `fu-release-ps1-origin-check-ps51` (P3).

### INFO (no gate)

- `realOrResolve` falls back to `path.resolve` if realpath throws. Node would already have failed to load such a path, so this is harmless.
- The import-time argument parsing and the `Resume:` line on a version refusal are described above.
- Carried from r1, still open as INFO: `AAI_RELEASE_POLL_SECONDS=0`, fork-PR head-name DoS, the "dry-run first" wording, and the release.yml direct-tag behaviour change not called out in the CHANGELOG.

## Probes run (read-only, scratch only)

Scratch directory: `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/r2`.

- **Guard invocation matrix** (absolute, relative `./`, non-normalized, symlink plus special characters): `main()` ran in every style.
- **Identity probe:** `node tests/skills/lib/release-finish-worktree-identity.mjs` gave PASS on darwin.
- **Exported helpers:**
  - `samePath('C:\\A\\b','c:/a/B/','win32')` returns true; `samePath('/a','/A','linux')` returns false.
  - `worktreeBlock` selects the correct block.
  - `validTagVersion` rejects `stable-2026`.
- **Version refusal:** `--version stable-2026 --confirm` on a scratch repo returns rc 20 `REFUSED: version` before any gh call.
- **git stderr behaviour:**
  - `git remote get-url origin` without origin: stderr text, rc 2.
  - `git config --get remote.origin.url`: silent, rc 1.
- **Hosted evidence:** `gh run view 39022783097` (read-only) shows headSha ab70289e, conclusion success, and the Windows CR-3 step = success with the win32 PASS log line.

There were no source, STATE, index, commit, push or GitHub writes. I did not re-run the suite, to avoid telemetry writes; I relied on validation r8 (aai-release rc 0, including TEST-702/703).

## Warning dispositions (H6)

| Finding | Recommended disposition (orchestrator records) |
|---|---|
| NB-R2-1 Windows direct-run guard proof | remediate-in-tree (one hosted assertion); else follow-up `fu-release-finish-win-direct-run-proof` P2 |
| NB-R2-2 ps1 origin check under 5.1 | remediate-in-tree (`git config --get remote.origin.url`); else follow-up `fu-release-ps1-origin-check-ps51` P3 |
| r1 NB-2 | follow-up `fu-release-checks-registration-grace` (recorded) |
| r1 NB-3 | follow-up `fu-release-notes-heading-multiset` (recorded) |
| r1 NB-5 | remediate at ship/product-docs step (still pending) |

## Next steps

1. Fold NB-R2-1 and NB-R2-2 in-tree, or record the follow-ups above.
2. Run the ship step and update the product doc (r1 NB-5).
3. Let PR CI re-run the Windows jobs at the final head.
4. Stage this report with the next scope commit.

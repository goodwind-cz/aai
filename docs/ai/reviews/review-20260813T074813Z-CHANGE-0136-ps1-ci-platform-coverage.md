# Code Review — CHANGE-0136 ps1-ci-platform-coverage

- Date: 2026-08-13T07:48:13Z
- Reviewer: Code Review role (dual verdict, .aai/SKILL_CODE_REVIEW.prompt.md)
- Branch: feat/ps1-ci-platform-coverage (verified)
- Scope: git diff e18cd63..HEAD (commits 51f9104, 852c561, 5595aa8)
- Spec: docs/specs/SPEC-0123-spec-ps1-ci-platform-coverage.md (SPEC-FROZEN, ceremony_level 1)
- Intake: docs/issues/CHANGE-0136-ps1-ci-platform-coverage.md
- Validation round 1 read: docs/ai/validation/validation-20260813T073331Z-CHANGE-0136-ps1-ci-platform-coverage.md (CONDITIONAL-PASS) — every claim I rely on was re-verified independently below.

```yaml
review:
  scope: e18cd63..HEAD (51f9104, 852c561, 5595aa8)
  spec: docs/specs/SPEC-0123-spec-ps1-ci-platform-coverage.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "planned per D5/SPEC-0122 discipline; shape pinned by test_019 (green, RED at docs/ai/tdd/red-20260813T071157Z; flip contract names the run URL + per-arm exit codes + captured AAI-BRANCH: WSL line)" }
      - { ac: Spec-AC-02, call: compliant, citation: "planned; test_020+017 green; AAI_EXPECTED_WIN_SKIP_COUNT declared once at workflow level (grep -c = 1, decl line < jobs: line); flip contract names the PESTER OK line" }
      - { ac: Spec-AC-03, call: compliant, citation: "planned; test_021 pins step shape incl. exits 97/98 controls and the Move-Item/Rename-Item negative at step scope; flip contract names control + arm lines" }
      - { ac: Spec-AC-04, call: compliant, citation: "done with evidence: cron '0 5 * * 1' + schedule-conditioned run-name parsed from YAML; product-doc canary sentence; test_022 green in all my runs" }
      - { ac: Spec-AC-05, call: compliant, citation: "done with evidence: WSL1-vs-WSL2 statements consistent across workflow header / docs/product/windows-test-wrapper.md / docs/TECHNOLOGY.md; matrix rows byte-unchanged (diff shows one prose hunk); CHANGELOG heading present; test_023 + test-aai-release TEST-024 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "done with evidence: ALL_TESTS carries 019..023, check-test-registration exit 0, RED log names all five missing contracts, test_009/014..018 intact — but see BLOCKING-1 for suite robustness" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 462,
          issue: "test_021's `echo \"$job\" | grep -qF \"$step_name\"` (and the 41 sibling `echo big-var | grep -q` pipes in test_019..021) races SIGPIPE under the suite's `set -uo pipefail`: grep -q exits at first match, echo takes EPIPE, pipefail turns the matched (correct) pipeline into rc=141 and `|| log_fail` fires. This is NOT the 1/1300 tail event validation F-2 measured — I reproduced it 3/11 full-suite runs on this host, always at test_021's first job-block grep.",
          failure_scenario: "windows-5_1 job block is 42,975 bytes with the step-name match at byte 27,207; whenever the kernel keeps the pipe at its initial 16KB (memory pressure / CI load) instead of growing to 64KB, grep exits mid-stream and echo dies. Proven mechanism: a synthetic >64KB payload with an early match fails 95/100 iterations in bash under set -uo pipefail (scratchpad/sigpipe-probe.sh). The job block only grows — at >64KB the suite fails near-deterministically. Worse, the negative pins (`echo \"$step\" | grep -qF Move-Item && log_fail`) have the FAIL-OPEN direction: a SIGPIPE on a genuine match yields rc=141 and skips log_fail, silently passing a host-mutation regression. Fix is mechanical: `grep -qF \"$x\" <<<\"$var\"` (herestring, bash-3.2-safe, no pipe) or grep the awk output written to a temp file." }
      - { rank: NON-BLOCKING, file: .github/workflows/ps1-quality.yml, line: 893,
          issue: "WSL-leg doctor step: the last native command is `& node aai-doctor.mjs --json` and there is no explicit trailing exit, so GitHub's appended `if (Test-Path variable:\\LASTEXITCODE) { exit $LASTEXITCODE }` makes the doctor's process exit code load-bearing — contradicting the step's own 'informational' comment.",
          failure_scenario: "If any of CAT-01/02/06 (the only FAIL-capable categories, aai-doctor.mjs:121/143/250,659) ever FAILs on the runner, the step fails AFTER printing 'SELFTEST OK', with no assertion line naming why. Today benign (all three are repo-content checks that PASS on this tree) and the miss direction is fail-closed; align the comment or assert the doctor exit explicitly." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-win-fallback.sh, line: 397,
          issue: "Anchor sloppiness in shape pins: test_019's exit-code pins (`-ne 3`, `-ne 124`, `-ne 125`) and CAT-15 'functional' grep are job-block-wide, not arm-scoped; test_020's `shell: powershell` grep is job-wide rather than Pester-step-scoped.",
          failure_scenario: "A future edit that swaps arm variables (asserting 124 on the success arm and 3 on the timeout arm) keeps every pin green while the workflow asserts the wrong contract. Bounded: the live CI run still fails on real misbehavior, and the tokens currently sit on the right arms (verified by reading lines 893-948). LOW." }
  cannot_verify:
    - { claim: "The windows-wsl1 job and the 5.1-only doctored-child step actually pass on Windows (WSL1 routing, wslpath marker translation, 124/125 contracts, powershell.exe arm) — no Windows execution has ever happened for these paths",
        closes_with: "the named green ps1-quality run on this scope's PR (TEST-007/008/009); evidence copied into the Spec-AC-01/02/03 cells" }
    - { claim: "Vampire/setup-wsl@v7 supports `wsl-version: 1` + `distribution: Debian` on the current windows-latest image and produces a functional WSL1 distro",
        closes_with: "same run — the three controls (sentinel 42, VERSION 1, wslpath /mnt/c) convert any install failure into a named leg failure (verified non-vacuous at source)" }
    - { claim: "The WSL-leg Pester step's final in-suite native command exits 0 (GitHub's appended exit-$LASTEXITCODE hop) under WSL routing — empirically true on the existing no-WSL legs, and the last container's last test ends with `& node aai-doctor.mjs --json` (exit 0), but WSL routing changes in-test process behavior",
        closes_with: "the same run's PESTER OK line followed by a green step conclusion" }
    - { claim: "The scheduled cron EVENT fires and the canary run-name renders in the Actions list (RR-1)",
        closes_with: "first Monday 05:00 UTC run after merge" }
    - { claim: "GitHub's empty-run-name-falls-back-to-default behavior on non-schedule events",
        closes_with: "any PR/push event on the merged workflow keeping its default run name (documented semantics only until then)" }
  overall: fail
```

## Independent verification log (all re-executed here, not taken from reports)

| Command | Exit / result |
|---|---|
| bash tests/skills/test-aai-win-fallback.sh (11 full runs) | 8× green, **3× FAIL at test_021's first job-block grep** (BLOCKING-1) |
| isolated mechanism probe (synthetic >64KB payload, bash, set -uo pipefail) | 95/100 pipeline failures — SIGPIPE class proven |
| bash tests/skills/test-aai-release.sh | 0 (TEST-024 merge-base headings intact) |
| node .aai/scripts/spec-lint.mjs --path <spec> | 0 — LINT PASS, 0 findings |
| node .aai/scripts/check-test-registration.mjs | 0 |
| python3 yaml.safe_load(ps1-quality.yml) | OK; jobs = gate, windows-5_1, windows-wsl1; run-name + schedule parsed as spec'd |
| here-string extraction from parsed YAML | `$inner = @'` and `'@` both dedent to column 0 — 5.1-legal |
| RED log spot-check (docs/ai/tdd/red-20260813T071157Z-…) | all five pins fail naming their missing contract on the pre-change tree |
| grep -n Move-Item/Rename-Item workflow | only pre-existing swap/restore lines 428/434/563/569 (validation F-3 confirmed); new step clean |

## PowerShell run-block audit (dispatch focus 1 — the PR-#249 failure class)

Every new run block declares `shell: powershell` (5.1) — engine-consistent with what it proves. Per block:

- **Controls step**: sentinel uses the direct call operator `&` (native argv; the Start-Process pre-quoting footgun does not apply), demands `$LASTEXITCODE` EQUAL 42 (native non-zero exits never throw under 5.1's EAP Stop, so the check is reached); `wsl -l -v` read is double-guarded against UTF-16 (WSL_UTF8=1 + explicit null strip) and `(?m)Debian.*\s1\s*$` cannot match VERSION 2 or a "11" digram; wslpath control deliberately passes `C:\Windows` (trailing-backslash argv mangle avoided, documented in-step). Last native command on the success path exits 0 → the GH-appended exit hop is safe.
- **Routing step**: real child + `-RedirectStandardError` (required — `[Console]::Error` from Write-BranchDiag, aai-run-tests.ps1:430, is invisible to in-process `2>`); the array-ArgumentList join is safe both under 5.1's raw space-join AND under quote-adding semantics because powershell.exe `-Command` re-joins trailing argv with single spaces and the payload carries no double quotes; `-Wait -PassThru` makes `.ExitCode` reliable; non-vacuous against Git-Bash routing (the wrapper's only branch tokens are `WSL` / `Git Bash`; the regex rejects the latter). No native command runs in the parent → appended exit hop inert.
- **Doctor/selftest step**: JSON via pipe decode of a real node child (no BOM-sniffing file read); per-arm assertions match the real report field names (aai-win-selftest.ps1 Build-SelfTestReport: lowercase name/status/exitCode/diag/markerOk/spawnErrorCount; CAT-15 detail.wsl from Get-WslTriState with literal 'functional'). NB-1: trailing $LASTEXITCODE hop (see finding).
- **5.1-only step**: parent has no native calls (hop inert); inner script ends `exit 0` explicitly (hop handled); child spawned with pre-quoted argument string + `.Handle` touch + WaitForExit (5.1 ExitCode-null footgun handled); exits 97/98 are distinct and mapped; controls hold in both directions so the step cannot pass vacuously — if the hiding breaks, 97 fires; if `Get-Command pwsh` somehow resolves outside PATH, 97 fires; if doctor emits nothing, ConvertFrom-Json throws under EAP Stop. Dot-sourcing aai-win-selftest.ps1 is side-effect-free (guard at line 430, and its nested dot-source of aai-run-tests.ps1 hits that wrapper's own `InvocationName -ne '.'` guard).
- **Pester install/run steps**: byte-shape copies of the CI-proven windows-5_1 steps; the single workflow-level `AAI_EXPECTED_WIN_SKIP_COUNT: "4"` feeds both legs (declared once — verified; count re-derivation argument checked: all four `-Skip:$script:SkipOnWindows` predicates are host-OS-driven, none WSL-state-driven).

## Doctored-child controls vacuity check (dispatch focus 3)

Exit 97 (pwsh still resolvable) and 98 (wrong engine) cannot pass vacuously: `powershell.exe -File` propagates script `exit N` as the process exit; the parent maps 97→fail, 98→fail, any non-zero→fail, and the arm assertions read the JSON the child wrote — an unlaunched or crashed child leaves no parseable JSON and the step throws. No vacuous path found.

## Validation F-2 severity re-assessment (dispatch focus 4)

Validation ranked it LOW/advisory on a 1-in-1300 measurement. My measurement contradicts that: 3 failures in 11 full-suite runs, and the mechanism is size-cliff-shaped (43KB payload today, 64KB pipe-buffer cliff, match at 27KB, job block grows with every future step), with a fail-open direction on the negative pins. Upgraded to **BLOCKING — fix now, before the PR**: the fix is a mechanical pipe→herestring swap confined to the new test functions, needs no RED ceremony (no contract change), and removes a ~27% chance of poisoning the very CI run whose greenness is the Spec-AC-01/02/03 flip evidence. This is also the repo's documented LEARNED trap class (test-harness shell-options).

## Docs truth + companion obligations (dispatch focus 5)

- WSL1-vs-WSL2 statements consistent in all three places (workflow header, product doc "What CI proves per platform", TECHNOLOGY.md prose); the 5-row matrix rows byte-unchanged; TECHNOLOGY's claim scope ("WSL1 delegation CI-verified") becomes literally true only when the leg is green — acceptable because the claims merge in the same PR the run gates.
- CHANGELOG: one `## [unreleased] — …` per-entry heading, additive (TEST-024 green) — correct per repo discipline.
- Prompt corpus: zero `.aai/**` bytes in the diff (diff stat verified) — no ledger/TEST-012/PROFILES obligations. Correct.
- suite-map.yaml: adds docs/product/windows-test-wrapper.md to aai-win-fallback globs — correct (test_018/022/023 pin sentences there); validation verified selector behavior live, and the shape is plainly right.

## Ceremony level judgement (dispatch focus 6)

Level 1 is appropriate. The workflow file is CI-load-bearing, but the scope changes zero production-script bytes, touches no protected_paths_l3 surface, is purely additive on the existing jobs (only the env-declaration move, verified as the diff's only removal), and the genuinely dangerous part — live Windows behavior — is gated by the spec's own planned-until-green AC rows, which no amount of local ceremony could substitute for. The spec records the justification accurately.

## Warning dispositions (H6)

- BLOCKING-1 (SIGPIPE pins): remediate-in-tree NOW — pipe→herestring in test_019..021 (all `echo "$var" | grep` sites in the new functions, both positive and negative pins), then re-run the full suite several times.
- NB-1 (doctor exit-code hop): recommended disposition remediate-in-tree alongside BLOCKING-1 (either delete the misleading "informational" wording or assert the doctor exit explicitly) — one-line; alternatively promote to a decisions.jsonl entry accepting the fail-closed hop.
- NB-2 (arm-scoped anchors): recommended disposition promote-to-decision (accept: live run bounds the risk) or fold an arm-scoped grep tightening into a future test touch. Not worth its own ride.

## Merge gate

1. BLOCKING-1 fixed and the full win-fallback suite green on repeated runs (I suggest ≥5 consecutive) under `bash tests/skills/test-aai-win-fallback.sh`.
2. Re-review of that remediation commit (mechanical; same-pass re-walk).
3. The named ps1-quality run on this scope's PR green, showing verbatim: the three `CONTROL OK` lines + `WSL1 CONTROLS OK`, `WSL ROUTING OK: wrapper exit 0 with AAI-BRANCH: WSL on stderr`, `SELFTEST OK (WSL semantics): success 3 via wslpath-translated marker, timeout 124, spawnfail 125` with `CAT-15 OK: wsl functional`, `PESTER OK (Windows PowerShell 5.1, WSL1 leg): N passed, 4 skipped, 0 failed, <t>s` (N ≥ 111, t ≤ 600), and on windows-5_1 both control lines + `Resolve-SelfTestEngine -> powershell` + three `CAT-14 arm …: PASS … under powershell.exe` lines + `5.1-ONLY FALLBACK OK`.
4. That evidence copied into the Spec-AC-01/02/03 cells before those rows flip to done (docs-audit --gate goes 1→0).

# Evidence: SPEC-0257 Spec-AC-05 final-tree release corpus (2026-11-08)

This is a tracked digest of the gitignored raw evidence `docs/ai/tdd/final-corpus-release-first-20261108.{log,json}`. It was written by the independent Validation agent (claude-opus-5-5). No code was changed.

## Command and identity

- Source: an independent `git clone --no-local` of main `c88cf7087646326aa15b635de4dd46634090a263` (after #541), with its own .git.
- Command: `env -u AAI_ROLE -u AAI_GIT_WRITE -u AAI_TEST_TIMEOUT node .aai/scripts/release-dry-run.mjs --root <clone> --both --jobs 4 --timeout-seconds 1800 --budget-seconds 3600 --report <outside clone>`
- Window: 2026-11-08T21:05:56Z to 21:38:34Z. Exit code 0. `/usr/bin/time -p`: real 1953.79 s, user 2335.20 s, sys 1942.76 s.
- Machine: darwin arm64 27.0.0, 16 logical CPUs (Apple M4 Max).
- Interpreters: Node v22.23.1, Bash 3.2.57, PowerShell 7.6.3, Pester 5.7.1.
- Host load: heavily loaded by foreign work (other rides' suites, system indexers, a VM). The load average reached about 191 on 16 CPUs at 21:36Z and was 22.6 at the start. Timings are therefore an upper-bound local observation, not a performance claim.

## Executor report

- Readers: 33. Executions: 66 of 66. Every exitCode is 0 on both arms.
- complete=true, termination=absent, sourcePreserved=true, sourceHead=c88cf7087646326aa15b635de4dd46634090a263.
- jobs=4, peakActive=4, readerTimeoutSeconds=1800, budgetSeconds=3600. Schedule policy: suite-weight-desc.
- wallSeconds: ordinary 846.209, rolled 1102.995. totalSeconds: 1952.697.
- Source proof: treeSha256 `a9c668da9a3e8760dcfa033f9a534455ff642eb3224d11166a8bb8c79ec6741a`, indexSha256 `1bfca0072ad7f1f2ed2c6e6c08e5c0cf1fb868f1c5890a8fb5ee51ad985a6334`. The refs list is identical before and after.
- hostedTiming: unverified — local execution only.
- The 1800/3600 bounds are local operational limits (SPEC-0277 precedent). This run does not show that readers fit the shipped 540/1080 CI defaults: test-aai-release.sh exceeded 540 s locally under this load.

## Per-reader results

| Reader | Ordinary exit | Ordinary s | Rolled exit | Rolled s |
|---|---|---|---|---|
| tests/skills/aai-win-dispatch.Tests.ps1 | 0 | 21.9 | 0 | 23.9 |
| tests/skills/lib/current-head-ci.test.mjs | 0 | 41.7 | 0 | 52.7 |
| tests/skills/lib/recheck.test.mjs | 0 | 182.9 | 0 | 307.7 |
| tests/skills/lib/release-cut.test.mjs | 0 | 11.9 | 0 | 14.0 |
| tests/skills/lib/release-first.test.mjs | 0 | 63.9 | 0 | 79.9 |
| tests/skills/lib/release-notes-docs.test.mjs | 0 | 9.0 | 0 | 12.0 |
| tests/skills/release-cut.Tests.ps1 | 0 | 10.7 | 0 | 12.4 |
| tests/skills/test-aai-canon.sh | 0 | 13.7 | 0 | 14.2 |
| tests/skills/test-aai-deslop.sh | 0 | 28.9 | 0 | 41.4 |
| tests/skills/test-aai-doc-number-reservation.sh | 0 | 24.2 | 0 | 27.5 |
| tests/skills/test-aai-doc-numbering.sh | 0 | 59.2 | 0 | 87.6 |
| tests/skills/test-aai-docs-audit.sh | 0 | 106.1 | 0 | 170.4 |
| tests/skills/test-aai-doctor.sh | 0 | 166.0 | 0 | 223.7 |
| tests/skills/test-aai-feedback-upsert.sh | 0 | 16.1 | 0 | 17.9 |
| tests/skills/test-aai-hygiene-pack.sh | 0 | 39.5 | 0 | 69.4 |
| tests/skills/test-aai-learned-routing.sh | 0 | 17.5 | 0 | 18.4 |
| tests/skills/test-aai-legacy-migrations.sh | 0 | 248.0 | 0 | 319.5 |
| tests/skills/test-aai-merge-policy.sh | 0 | 60.5 | 0 | 82.2 |
| tests/skills/test-aai-orchestration-mode.sh | 0 | 6.7 | 0 | 6.7 |
| tests/skills/test-aai-pre-commit-checks.sh | 0 | 38.4 | 0 | 52.8 |
| tests/skills/test-aai-prompt-diet.sh | 0 | 10.0 | 0 | 11.5 |
| tests/skills/test-aai-recheck.sh | 0 | 168.7 | 0 | 322.9 |
| tests/skills/test-aai-release-cut.sh | 0 | 75.5 | 0 | 114.8 |
| tests/skills/test-aai-release-notes.sh | 0 | 33.0 | 0 | 38.4 |
| tests/skills/test-aai-release.sh | 0 | 618.1 | 0 | 727.7 |
| tests/skills/test-aai-retired-loop-runner.sh | 0 | 18.7 | 0 | 36.7 |
| tests/skills/test-aai-role-output.sh | 0 | 7.1 | 0 | 7.6 |
| tests/skills/test-aai-suite-reuse.sh | 0 | 107.0 | 0 | 191.0 |
| tests/skills/test-aai-suite-select.sh | 0 | 37.0 | 0 | 47.5 |
| tests/skills/test-aai-update.sh | 0 | 11.3 | 0 | 11.5 |
| tests/skills/test-aai-validate-skills.sh | 0 | 40.6 | 0 | 62.0 |
| tests/skills/test-aai-verify-gate.sh | 0 | 4.9 | 0 | 5.2 |
| tests/skills/test-aai-win-fallback.sh | 0 | 34.2 | 0 | 67.2 |

## TEST-007

`env -u AAI_ROLE -u AAI_GIT_WRITE -u AAI_TEST_TIMEOUT bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release-first.sh test_007` exited 0 with PASS TEST-007 (raw log `docs/ai/tdd/final-corpus-release-first-test007-20261108.log`).

## Post-open hosted observation (PR #543, head fbd8328c)

- Run 42526413485 (pull_request), job 128870915856 `release dry-run (complete tracked changelog readers)`.
- Run created 21:40:56Z. The job ran from 21:40:59Z to 21:52:13Z, about 3 s of queue time and 674 s of job time.
- The hosted executor ran the rolled arm only: 33 readers, 0 failed out of 33 executions, 649.101 s. test-aai-release.sh passed in 397.1 s.
- Added verification critical-path delay: max(0, 21:52:13Z minus 21:45:31Z, the completion of the latest preexisting verification job, `skill suite (selected)`) = 402 s.
- That is above the diagnostic 60-second target from Planning measurements. Optimizing it is out of scope for this measurement closure and is reported at the merge checkpoint. Runner-seconds were not available from the check API.
- This applies to this head only. Later heads and other platforms are not inferred.

# Checked TEST008 maker result

Requested canonical gpt-5 unavailable; inherited actual model unknown; no usage estimate. Full interval includes diagnostic CI wait. All wrappers settled. Maker PASS does not issue a native CI, Review or Validation verdict.

```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Remediation
  status: PASS
  started_utc: 2026-10-08T00:02:04Z
  ended_utc: 2026-10-08T00:42:32Z
  duration_seconds: 2428
  evidence:
    - command: Read complete bfea native Windows and WSL clone JSON and raw logs
      exit_code: 0
      output_snippet: Same604abd7merge HEAD; core.longpaths unset; deep274 exit128 five Filename-too-long; short255 exit0 shallow true
    - command: bash .aai/scripts/aai-run-tests.sh pwsh -NoProfile -File /private/tmp/aai-pr434-remediation-scratch/capture-legacy-red.ps1
      exit_code: 1
      output_snippet: Real Legacy quoting loses inline JavaScript quotes; ReferenceError full undefined; expected7 actual1
    - command: bash .aai/scripts/aai-run-tests.sh pwsh -NoProfile -File /private/tmp/aai-pr434-remediation-scratch/capture-legacy-green.ps1
      exit_code: 0
      output_snippet: UTF8 script file preserves JSON stderr exit7 and restores Stop under Legacy delivery
    - command: bash .aai/scripts/aai-run-tests.sh python3 docs/ai/tdd/test008-native-20261008T000204Z/check-recovery.py
      exit_code: 0
      output_snippet: Recovery24/24;five equal bfea blobs; CRLF identity/base64 exact; unknown and wrong current hashes refuse
    - command: Serial canonical focused TEST001 on real Git2.43 and2.54
      exit_code: 0
      output_snippet: Quoted/effective bytes retained; older blank destinations refuse0providers; newer single URL succeeds3providers; reached deterministic blanks refuse
    - command: bash .aai/scripts/aai-run-tests.sh pwsh -NoProfile -Command Invoke-Pester
      exit_code: 0
      output_snippet: Final focused Pester2/2; shared8/8 and canonical POSIX Bash companion8/8; native repaired-head proof pending
    - command: Final candidate byte-path audit and strict amendment ACgate ACflip speclint source diff checks
      exit_code: 0
      output_snippet: Max136relative258full at observed122prefix; no undeclaredNUL; historical manifests and ledger prefixes exact
  files_changed:
    - tests/skills/test-aai-pr-preflight.sh
    - tests/skills/aai-pr-preflight.Tests.ps1
    - docs/specs/SPEC-0210-spec-pr-capability-preflight.md
    - docs/ai/decisions.jsonl
    - docs/ai/reports/REMEDIATION-20261008T000204Z-test008-native.md
    - docs/ai/reports/RESULT-20261008T000204Z-test008-native.md
    - docs/ai/tdd/test008-native-20261008T000204Z/explicit-files.json
    - docs/ai/tdd/test008-native-20261008T000204Z/final-manifest.json
  blockers:
    - Native repaired-head GREEN pending root commit and CI snapshot
    - Fresh independent Review then proper root metadata close full green CI and final independent Validation pending
    - Existing frozen-spec follow-up remains open; no signoff or merge waiver
  state_update_commands:
    - node .aai/scripts/state.mjs reset-block code_review
    - node .aai/scripts/state.mjs set-phase --ref pr-capability-preflight --phase code_review --status in_progress
```

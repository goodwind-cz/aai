```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: FAIL
  started_utc: 2026-10-08T01:20:48Z
  ended_utc: 2026-10-08T01:34:29Z
  duration_seconds: 821
  evidence:
    - command: bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh
      exit_code: 0
      output_snippet: All eight current-source rows pass; TEST0041554ms child gone, SSH443 controls pass, TEST008 real shallow replay1319ms.
    - command: Serial canonical pr-platform, layer-profiles, prompt-diet and ride-select suites
      exit_code: 0
      output_snippet: All four suites pass; complete logs preserved and read, no tripwire failures.
    - command: bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr434-review-replay-scratch/dot-path.cjs /private/tmp/aai-pr-capability-preflight 007
      exit_code: 1
      output_snippet: B1 actual READ_VERIFIED0 expected identity refusal2; real Git sends raw path, raw upload-pack128 normalized positive control0.
    - command: node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0210-spec-pr-capability-preflight.md --json
      exit_code: 0
      output_snippet: Eight satisfied rows; zero degraded unstamped uncomparable; current target hashes match.
    - command: Independent current CI raw logs and source-bound job metadata inspection
      exit_code: 0
      output_snippet: Linux157/0/0 WSL153/0/4; Windows113100989118 pending; full104=97PASS6FAIL1SKIP with actual aggregate failure.
  files_changed:
    - docs/ai/reviews/review-20261008T012048Z-pr434-replay.md
    - docs/ai/reviews/pr434-replay-20261008T012048Z/audit.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/boundary-after.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/boundary-before.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/compatibility-read.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/dot-path-red.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/dot-path.cjs
    - docs/ai/reviews/pr434-replay-20261008T012048Z/dot-path.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-113101059159.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-113101059206.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-113101059211.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-113101059241.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-113103257596.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-jobs.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/full-read.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/layer-profiles.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/native-jobs-observed.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/native-linux-read.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/native-linux.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/native-wsl-read.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/native-wsl.log.b64
    - docs/ai/reviews/pr434-replay-20261008T012048Z/pr-platform.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/preflight.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/prompt-diet.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/recovery.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/ride-select.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/scope-hashes.json
    - docs/ai/reviews/pr434-replay-20261008T012048Z/result.md
    - docs/ai/reviews/pr434-replay-20261008T012048Z/role-check.log
    - docs/ai/reviews/pr434-replay-20261008T012048Z/manifest.json
  blockers:
    - B1 raw SSH path normalization violates Spec-AC-01; remediation required.
    - Current Windows native job and final green full CI plus independent Validation remain incomplete.
  report: docs/ai/reviews/review-20261008T012048Z-pr434-replay.md
  artifact_manifest: docs/ai/reviews/pr434-replay-20261008T012048Z/manifest.json
  requested_model: gpt-6-astra high
  actual_model: unknown
  usage_capture: none
  spec_compliance: fail
  code_quality: fail
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status fail --scope bdeb425c040ada918dd97e5b878b71e420bad83a...5685e3625bc94f00ade55d9cf491158dde058177 --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261008T012048Z-pr434-replay.md --notes 'Dual FAIL: B1 raw SSH dot segments normalize before identity validation, AC01 noncompliant. AC06 current Windows job pending; Linux157/0/0 WSL153/0/4; full104=97PASS6FAIL1SKIP. No H6 warnings; no closure/Validation PASS. Actual model unknown.'
```

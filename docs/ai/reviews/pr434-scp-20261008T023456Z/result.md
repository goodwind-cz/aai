```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: FAIL
  started_utc: 2026-10-08T02:34:56Z
  ended_utc: 2026-10-08T02:46:23Z
  duration_seconds: 687
  evidence:
    - command: bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh
      exit_code: 0
      output_snippet: Eight of eight current-source test rows pass in the isolated scratch clone.
    - command: bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr434-scp-review-scratch/probe.cjs /private/tmp/aai-pr434-scp-review-scratch/repo
      exit_code: 1
      output_snippet: Malformed scheme returns 0 instead of 2; case-equivalent GitHub result returns 3 instead of 0; ordinary and generic positives pass.
    - command: Independent current maker manifest and source audit
      exit_code: 0
      output_snippet: 144 manifest rows match; 24 recoveries; 8 target stamps; 4 byte-exact base ledger prefixes.
  files_changed:
    - docs/ai/reviews/pr434-scp-20261008T023456Z/audit.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/boundary-after.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120521324.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120521878.log.b64
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120584384.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120584390.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120584458.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113120584482.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-113122815599.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ci-transport.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/diff-check.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/dispatch.txt
    - docs/ai/reviews/pr434-scp-20261008T023456Z/external-review.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/full-jobs.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/full-run-final.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/layer-profiles.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/machine-dispatch.txt
    - docs/ai/reviews/pr434-scp-20261008T023456Z/manifest.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/native-jobs.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/owner-dispatch.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/pr-platform.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/preflight.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe-infra-results.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe-infra.cjs
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe-infra.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe-results.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe.cjs
    - docs/ai/reviews/pr434-scp-20261008T023456Z/probe.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/prompt-diet.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/result.md
    - docs/ai/reviews/pr434-scp-20261008T023456Z/ride-select.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/role-check.log
    - docs/ai/reviews/pr434-scp-20261008T023456Z/sources.json
    - docs/ai/reviews/pr434-scp-20261008T023456Z/timing.json
    - docs/ai/reviews/review-20261008T023456Z-pr434-scp.md
  blockers:
    - B1 malformed scheme endpoint bypasses identity refusal.
    - B2 case-equivalent GitHub identity is rejected.
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status fail --scope bdeb425c040ada918dd97e5b878b71e420bad83a...1691558c034e13258a31b8288df5642f6263a8cb --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261008T023456Z-pr434-scp.md --notes "Dual FAIL B1 malformed scheme generic fallback and B2 GitHub case-equivalent identity refusal. No H6 warnings. Current package exhausted; no closure. Windows pending; full CI 97PASS6FAIL1SKIP."
```

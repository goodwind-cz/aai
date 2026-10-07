```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: FAIL
  started_utc: 2026-10-07T16:51:59Z
  ended_utc: 2026-10-07T16:55:38Z
  duration_seconds: 219
  evidence:
    - command: "node .aai/scripts/canon.mjs build --role 'Code Review' --ref HEAD"
      exit_code: 0
      output_snippet: "Canonical contract, review role and learned sections assembled."
    - command: "git diff bdeb425c040ada918dd97e5b878b71e420bad83a...HEAD; git diff; git diff --cached"
      exit_code: 0
      output_snippet: "Full committed scope plus three tracked working changes; staged diff empty."
    - command: "Read-only in-memory extraction and execution of probe() with split UTF-8 buffers"
      exit_code: 0
      output_snippet: "Expected Repo 雪; observed Repo ���; equal=false."
    - command: "SHA-256 verification of final-evidence.json referenced files"
      exit_code: 0
      output_snippet: "Evidence hashes verified: true."
  files_changed:
    - docs/ai/reviews/review-20261007T165159Z-pr-capability-preflight.md
    - docs/ai/reviews/result-20261007T165159Z-pr-capability-preflight.md
  blockers:
    - "R1 Linux Bash scratch default; R2 split UTF-8 corruption."
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status fail --scope "bdeb425c040ada918dd97e5b878b71e420bad83a...6005f5874dd789dbacd3e61088edf38aa8b35d99 plus all tracked working diffs" --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261007T165159Z-pr-capability-preflight.md --notes "Round 1 FAIL: R1 portable Linux scratch default and R2 split UTF-8 corruption require in-tree remediation; no NON-BLOCKING warnings."
```

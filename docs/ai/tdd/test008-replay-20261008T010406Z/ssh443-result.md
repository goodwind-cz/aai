```yaml
subagent_result:
  scope: PR434-thread4213513507-ssh443
  role: Research
  status: PASS
  started_utc: 2026-10-08T01:05:33Z
  ended_utc: 2026-10-08T01:07:30Z
  duration_seconds: 117
  evidence:
    - command: env AAI_ROLE=subagent AAI_TEST_TIMEOUT=30 bash .aai/scripts/aai-run-tests.sh node /private/tmp/aai-pr434-ssh443-research/probe.mjs
      exit_code: 0
      output_snippet: documented-alias exit2 IDENTITY_INVALID identity zero provider calls; ordinary HTTPS/scp/SSH controls READ_VERIFIED with three github.com mock provider calls each.
    - command: Read exact GitHub primary SSH-over-HTTPS page and frozen requirements
      exit_code: 0
      output_snippet: Official SSH443 alias; existing classifier github for ssh.github.com; CHANGE0204 AC005 and SPEC0210 SpecAC05 preserve existing GitHub route.
  files_changed:
    - /private/tmp/aai-pr434-ssh443-research/report.md
    - /private/tmp/aai-pr434-ssh443-research/probe.mjs
    - /private/tmp/aai-pr434-ssh443-research/probe.log
    - /private/tmp/aai-pr434-ssh443-research/observations.json
    - /private/tmp/aai-pr434-ssh443-research/input.json
    - /private/tmp/aai-pr434-ssh443-research/provider-calls.jsonl
    - /private/tmp/aai-pr434-ssh443-research/bin/gh
    - /private/tmp/aai-pr434-ssh443-research/result.md
  blockers: []
```

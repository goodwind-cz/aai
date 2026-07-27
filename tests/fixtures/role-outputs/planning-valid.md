Froze the spec and emitted the work-item brief.

```yaml
subagent_result:
  scope: role-output-contracts
  role: Planning
  status: PASS
  started_utc: 2026-01-04T09:00:00Z
  ended_utc: 2026-01-04T09:07:00Z
  duration_seconds: 420
  evidence:
    - command: node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-x.md
      exit_code: 0
      output_snippet: "OK: spec structurally valid"
  files_changed:
    - docs/specs/SPEC-DRAFT-spec-role-output-contracts.md
  blockers: []
```

Froze the spec, emitted the brief, and recorded the validation verdict.

```yaml
subagent_result:
  scope: altitude-prompt-adoption
  role: Planning
  status: PASS
  started_utc: 2026-01-04T09:00:00Z
  ended_utc: 2026-01-04T09:07:00Z
  duration_seconds: 420
  last_validation: pass
  evidence:
    - command: node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-x.md
      exit_code: 0
      output_snippet: "OK: spec structurally valid"
  files_changed:
    - docs/specs/SPEC-DRAFT-x.md
  blockers: []
```

<!-- VIOLATION: E-PLANNING-VERDICT (a Planning block claims a VALIDATION
     verdict via `last_validation`). Note that `status: PASS` above is NOT the
     violation: per .aai/SUBAGENT_CONTRACT.md `status` is the ROLE RUN's own
     outcome and every role uses PASS for "my run completed". The verdict on
     the WORK is Validation's, on evidence Planning does not yet have. -->

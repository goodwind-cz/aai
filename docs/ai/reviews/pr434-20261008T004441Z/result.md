```yaml
subagent_result:
  scope: pr-capability-preflight
  role: Code Review
  status: FAIL
  started_utc: 2026-10-08T00:44:41Z
  ended_utc: 2026-10-08T01:01:41Z
  duration_seconds: 1020
  evidence:
    - command: "AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-review-test008-scratch bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh"
      exit_code: 0
      output_snippet: "TEST001..008 PASS; timeout1462ms child_alive=false later_probes=0"
    - command: "bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-platform.sh"
      exit_code: 0
      output_snippet: "Provider compatibility suite PASS"
    - command: "bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-layer-profiles.sh"
      exit_code: 0
      output_snippet: "196 core +75 extended =271; classification100%"
    - command: "bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh"
      exit_code: 0
      output_snippet: "All pass; canonical prompt36430->37717 bytes +1287"
    - command: "bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-ride-select.sh"
      exit_code: 0
      output_snippet: "Structured next and independent count companion cases PASS"
    - command: "bash .aai/scripts/aai-run-tests.sh node docs/ai/reviews/pr434-20261008T004441Z/deadline-probe.cjs"
      exit_code: 0
      output_snippet: "Synthetic counterexample: status null ETIMEDOUT SIGTERM at10062ms after PASS; outer10000ms inner75000ms; immediate control0"
    - command: "node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0210-spec-pr-capability-preflight.md"
      exit_code: 0
      output_snippet: "No findings"
    - command: "python3 docs/ai/reviews/pr434-20261008T004441Z/audit.py"
      exit_code: 0
      output_snippet: "387 paths;98 manifest records;4 exact ledger prefixes;24 exact transport aliases;8 current mutation targets"
    - command: "node .aai/scripts/docs-audit.mjs --check"
      exit_code: 0
      output_snippet: "NEEDS-TRIAGE1 probable-false-open; automatically appended audit telemetry; boundary mistake disclosed/preserved"
    - command: "git diff --check bdeb425c040ada918dd97e5b878b71e420bad83a...ebbd0eaeaebfa9015f550193df6f0b54afc338c3"
      exit_code: 2
      output_snippet: "Full diagnostics preserved: historical CRLF raw logs and Markdown EOF whitespace; source-only check0"
    - command: "Inspect completed native job113091070599 on head ebbd0eaeaebfa9015f550193df6f0b54afc338c3"
      exit_code: 0
      output_snippet: "Linux157PASS0FAIL0SKIP"
    - command: "Inspect completed native jobs113091070350 and113091070610 on head ebbd0eaeaebfa9015f550193df6f0b54afc338c3"
      exit_code: 1
      output_snippet: "Each Windows5.1 Pester152PASS1FAIL4SKIP; TEST008 status null; full Windows pwsh7 step skipped"
    - command: "Inspect completed full workflow37709272211 on head ebbd0eaeaebfa9015f550193df6f0b54afc338c3"
      exit_code: 1
      output_snippet: "104 suites:97PASS6FAIL1SKIP; lifecycle audit/companion failures disclosed"
    - command: "Review artifact seal checks"
      exit_code: 0
      output_snippet: "Six AC rows, seven raw CI transports hash-verified, all jobs terminal and source bound, head/index unchanged, telemetry delta exact"
    - command: "Initial check-role-output.mjs on result.md"
      exit_code: 1
      output_snippet: "Quoted STATE command scalar refused; corrected to canonical unquoted scalar list, final check passes."
  files_changed:
    - docs/ai/reviews/pr434-20261008T004441Z/role-output-first-failure.log
    - docs/ai/EVENTS.jsonl
    - docs/ai/reviews/pr434-20261008T004441Z/audit.json
    - docs/ai/reviews/pr434-20261008T004441Z/audit.log
    - docs/ai/reviews/pr434-20261008T004441Z/audit.py
    - docs/ai/reviews/pr434-20261008T004441Z/boundary.json
    - docs/ai/reviews/pr434-20261008T004441Z/ci-transport.json
    - docs/ai/reviews/pr434-20261008T004441Z/deadline-probe.cjs
    - docs/ai/reviews/pr434-20261008T004441Z/deadline-probe.log
    - docs/ai/reviews/pr434-20261008T004441Z/docs-audit.log
    - docs/ai/reviews/pr434-20261008T004441Z/full-diff-check.log
    - docs/ai/reviews/pr434-20261008T004441Z/full-jobs.json
    - docs/ai/reviews/pr434-20261008T004441Z/full1.log
    - docs/ai/reviews/pr434-20261008T004441Z/full2.log
    - docs/ai/reviews/pr434-20261008T004441Z/full3.log
    - docs/ai/reviews/pr434-20261008T004441Z/full4.log
    - docs/ai/reviews/pr434-20261008T004441Z/incidental-events.diff
    - docs/ai/reviews/pr434-20261008T004441Z/layer-profiles.log
    - docs/ai/reviews/pr434-20261008T004441Z/linux-excerpt.log
    - docs/ai/reviews/pr434-20261008T004441Z/linux.log
    - docs/ai/reviews/pr434-20261008T004441Z/manifest.json
    - docs/ai/reviews/pr434-20261008T004441Z/native-jobs.json
    - docs/ai/reviews/pr434-20261008T004441Z/pr-platform.log
    - docs/ai/reviews/pr434-20261008T004441Z/preflight.log
    - docs/ai/reviews/pr434-20261008T004441Z/prompt-diet.log
    - docs/ai/reviews/pr434-20261008T004441Z/result.md
    - docs/ai/reviews/pr434-20261008T004441Z/ride-select.log
    - docs/ai/reviews/pr434-20261008T004441Z/role-output-check.log
    - docs/ai/reviews/pr434-20261008T004441Z/seal-check.json
    - docs/ai/reviews/pr434-20261008T004441Z/spec-lint.log
    - docs/ai/reviews/pr434-20261008T004441Z/windows-excerpt.log
    - docs/ai/reviews/pr434-20261008T004441Z/windows.log
    - docs/ai/reviews/pr434-20261008T004441Z/wsl-excerpt.log
    - docs/ai/reviews/pr434-20261008T004441Z/wsl.log.b64
    - docs/ai/reviews/review-20261008T004441Z-pr434.md
  blockers:
    - "Required native TEST008 fails both Windows5.1 jobs; Spec-AC-06 non-compliant."
    - "B1 BLOCKING: shallow replay timeout10000ms undercuts nested75000ms; bounded successful child can be killed."
    - "Full CI remains97PASS6FAIL1SKIP; authorized metadata reconciliation and independent Validation remain gated."
  state_update_commands:
    - node .aai/scripts/state.mjs set-code-review --required true --status fail --scope "bdeb425c040ada918dd97e5b878b71e420bad83a...ebbd0eaeaebfa9015f550193df6f0b54afc338c3" --base-ref bdeb425c040ada918dd97e5b878b71e420bad83a --report docs/ai/reviews/review-20261008T004441Z-pr434.md --notes "Spec FAIL AC06: native TEST008 fails both Windows5.1 jobs; code_quality FAIL B1: 10s shallow replay parent undercuts 75s nested work. Linux157/0/0, Windows and WSL152/1/4; Windows pwsh7 full Pester skipped; full104=97PASS6FAIL1SKIP. No H6 warnings. No closure or Validation PASS. Actual model unknown. Three incidental docs_audit EVENTS rows preserved by root instruction; boundary.json records exact prefix/post hashes."
  report: docs/ai/reviews/review-20261008T004441Z-pr434.md
  artifact_manifest: docs/ai/reviews/pr434-20261008T004441Z/manifest.json
  spec_compliance: fail
  code_quality: fail
  requested_model: gpt-6-astra high
  actual_model: unknown
  boundary_disclosure: "Three incidental docs_audit EVENTS rows at2026-10-08T00:56:13Z,00:56:34Z,00:58:11Z. Root directs preservation. PrefixSHA04230c0e9928ec89be65bb8b22dddce1be5fd1569629c3ef26cdfaf954b26870; postSHA6a439790b681bcb6c07905db934aaf1c9bd508a5856a8467ef43b49e01f5c113. Exact boundary.json; no prior bytes changed."
```

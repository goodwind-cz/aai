# Code review round 3: ci-flake-root-causes (R2-1 delta only)

```yaml
review:
  scope: "25454d87..dc876afb (remediation of round-2 BLOCKING R2-1)"
  spec: docs/specs/SPEC-0322-spec-ci-flake-root-causes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched by this delta; round 2 call stands" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched by this delta; round 2 call stands" }
      - { ac: Spec-AC-03, call: compliant, citation: "only the TEST-4160 log_pass text changed (tests/skills/test-aai-close-reconcile.sh:1426); round 2 call stands" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched by this delta; round 2 call stands" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:183-184,941-943; the TEST-4161 not-armed arm (tests/skills/test-aai-run-tests.sh:1467-1477); reviewer repro: rc 125 in both the shipped and the no-tripwire-library layout, no unbound variable, command not run" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched by this delta; the TEST-4161 Test Plan description amendment is recorded in decisions.jsonl" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "the whole aai-run-tests suite exits 0 at dc876afb (it is the only runner of TEST-4161, and it has no single-test selector)",
        closes_with: "the remediation agent's whole-suite run log; the reviewer reproduced the two layouts by hand" }
    - { claim: "the full sweep is green. EVENTS records full_sweep rc=1 at 25454d87 (run test-20261127-005335), with follow-up fu-sweep-queue-child-sigkilled (aai-release-cut queue child SIGKILLed by an unknown sender)",
        closes_with: "the one full sweep before the close at the final head, required by the spec's Verification section; outside this delta" }
    - { claim: "the items carried from round 2: hosted noclobber O_EXCL, the uutils rm release race, the hosted SIGTERM ordering, gitignored mutation evidence, and the Pester-present branch",
        closes_with: "as listed in review-ci-flake-root-causes-20261127T013053Z.md" }
  overall: pass
```

security_relevant: false

## Scope

- Delta: `git diff 25454d87..dc876afb`. It touches aai-run-tests.sh (initialising two variables and a guarded cleanup loop), TEST-4161 (a new arm), the TEST-4160 pass text, the spec's TEST-4161 description and the round-2 Notes line, and decisions.jsonl and EVENTS.jsonl entries. It also commits the round-2 report.
- This is the extra round allowed for a hazard the change itself introduced. The review is limited to this delta, as the request asked.
- Clone state: clean apart from this report.

## R2-1 re-check

- Fixed. `AAI_TW_BEFORE=''` and `AAI_TW_AFTER=''` are now set beside `AAI_TW_ARMED=0` (lines 183-184), before any branch, so `set -u` cannot trip on them anywhere in the script. Their later readers (lines 1124-1174) are all inside `AAI_TW_ARMED -eq 1` or the cleanup that ends it, and the armed branch still assigns both at lines 193-194, so the initialisation changes nothing on the armed path. The refusal loop skips empty values, so it never runs `rm -f ''`.
- Reviewer repro at dc876afb: a scratch copy of `.aai/scripts` without `lib/repo-tripwire.sh`, with TMPDIR set to a regular file, gives rc 125, no `unbound variable` and no `RAN`. The shipped tree gives rc 125 in the same environment. A normal run (`sh -c 'echo NORMAL'`) gives rc 0, so the armed path is unaffected.
- TEST-4161's new arm copies the scripts directory into its own `$root`, which is removed on every path with `rm -rf "${root:?}"`. It asserts rc 125, that the command did not run, the refusal line, and the absence of `unbound variable`. The arm would have failed at 25454d87 (rc 1 with the unbound variable), so it guards the regression.

## Findings

None.

INFO (never gates):
- The spec's TEST-4160 Test Plan row still says "six untouched draft docs"; the fixture seeds seven. This was carried from round 2 and is cosmetic.

## Next steps

- The review is pass at dc876afb. The full sweep before the close at the final head is still owed (see cannot_verify).

state_update_commands:
```bash
node .aai/scripts/state.mjs set-code-review --required true --status pass \
  --scope "25454d87..dc876afb" --base-ref 25454d87 \
  --report docs/ai/reviews/review-ci-flake-root-causes-20261127T013526Z.md \
  --notes "round 3: R2-1 fixed (TW vars initialised, guarded cleanup; TEST-4161 no-tripwire arm); both verdicts pass; no open WARNINGs; round-1 #5 = fu-claim-span-granularity (P3)"
```

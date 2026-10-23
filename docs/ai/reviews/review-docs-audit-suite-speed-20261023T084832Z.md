```yaml
review:
  scope: "git diff 34f0cbca..d55bc491 (branch change/docs-audit-suite-speed, worktree /private/tmp/aai-docs-audit-speed)"
  spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-2201 PASS in reviewer full run; docs/analysis/docs-audit-suite-speed.md (unchanged since round 1)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/docs-audit-live.sh; TEST-2202/2203 PASS; TEST-2206 PASS on the real file, but its guard still misses chained launches after echo/printf/cp (BLOCKING B1-r2)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs-audit-live.sh index pair + setup_indexarm_snapshots; TEST-2204/2205 PASS; scratch tree clean after the run" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test_histmap_corpus_equivalence PASS locally (Node 22); CI Node 20 is cannot_verify" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/lib/docs-audit-closeout.test.mjs via TEST-2208 PASS; TEST-2211 PASS" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "accepted deviation: row deferred; hosted after rows and suite-weights.tsv re-measure pending push" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "reviewer wrapper run at d55bc491 rc 0 'PASS: All aai-docs-audit tests passed' (83 s, 0 FAIL); check-test-registration rc 0; mutation-gate GATE PASS 11 rows degraded=0" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8607,
          issue: "B1-r is resolved for if, !, ||, while, exec, time, eval, bash -c and env-prefixed launches. The echo/printf/cp/table skip is still decided per line, though. It spares a line that starts with echo, printf or cp unless node follows a pipe, so a launch chained after one of those commands with && or ; is never scanned. The comment above the programs says 'node, at ANY command position'. The test name and spec lines 267 and 353 claim no bypass. Line 8614 (gen_prog) has the same defect.",
          failure_scenario: "Reviewer mutations in a scratch clone at d55bc491, each added as a new function: '  echo \"== audit\" && node \"$AUDIT_SCRIPT\" --check --strict --no-event > x.log 2>&1' and '  cp a b && node .aai/scripts/generate-docs-index.mjs'. Both: TEST-2206 'PASS: No direct real-corpus launch; 15 live_audit call sites'. Direct awk probe: 'echo start; node .aai/scripts/docs-audit.mjs --check' and 'printf ... >&2; node \"$AUDIT_SCRIPT\" --check' also MISSED. Each one is an uncached real-corpus launch, or an unrestored real INDEX.md rewrite, that the test says does not exist." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8610,
          issue: "N2 (carried): TEST-2206 failure messages give NR in the joined logical text, not the file line.",
          failure_scenario: "A bypass after any backslash-continued line is reported at a lower line number than its real one. There is no false pass, and the offending text is printed in full." }
  cannot_verify:
    - { claim: "Worker sharding and the node:test file behave the same on CI Node 20",
        closes_with: "green hosted skill-suite run of test-aai-docs-audit.sh on the pushed head, with the 'shards=' info line showing >=2" }
    - { claim: "Suite passes under GNU Bash 5 / GNU awk with set -euo pipefail (only Bash 3.2 / BSD awk exercised locally)",
        closes_with: "hosted Linux run on the pushed head" }
    - { claim: "Spec-AC-06 hosted after durations and the re-measured aai-docs-audit weight row",
        closes_with: ">=3 hosted runs on the final suite blob; suite-weights.tsv row + test-aai-suite-select.sh rc 0" }
  overall: fail
```

# Code review: docs-audit-suite-speed (round 3, re-review after 0f65c981 and d55bc491)

- **Scope:** `git diff 34f0cbca..d55bc491`, in worktree mode with base main. The delta since round 2 touches only `tests/skills/test-aai-docs-audit.sh`, and `.aai/` is unchanged from base.
- **Spec:** docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md (frozen).
- **Outside the scope:** the uncommitted `docs/ai/roadmap.yaml` edit and the untracked round 1 and 2 review reports.
- **Dispatch note:** the dispatch named the accepted deviations and the prior validation result. The full diff was reviewed anyway.

## BLOCKING

**B1-r2. A chained launch after echo, printf or cp still gets past TEST-2206** (`tests/skills/test-aai-docs-audit.sh:8607` and `:8614`).

The round 2 fix is in place and it bites. The unanchored `(^|[^[:alnum:]_.\/-])node` pattern catches `if`, `!`, `||`, `while`, `exec`, `time`, `eval`, `bash -c`, `$(…)` and `VAR=x node`. There are 10 in-test positive controls, and the real file still passes with 15 sites.

The defect is in the skip line that round 2 recommended, which d55bc491 then narrowed. It decides per line, not per command. A line that starts with `echo`, `printf` or `cp` is skipped unless `node` follows a `|`. So these all pass TEST-2206:

- `echo "== audit" && node "$AUDIT_SCRIPT" --check --strict` (bite-proved with the full TEST-2206 run)
- `cp a b && node .aai/scripts/generate-docs-index.mjs` (bite-proved with the full TEST-2206 run)
- `echo start; node .aai/scripts/docs-audit.mjs --check` (awk probe)
- `printf 'x\n' >&2; node "$AUDIT_SCRIPT" --check` (awk probe)

The `cp` case has slipped through since round 1, and both earlier reviews missed it. A reviewer sweep of the corpus found no real launch in any of these shapes, so the claim is true today. The guard does not hold it, though, and the comment above the programs promises "ANY command position". Under the review contract that is BLOCKING.

**Minimal fix (verified in a scratch copy):** in both programs, widen the exception from a pipe to any command separator:

```
/^[[:space:]]*(cp|echo|printf|[|]) / && !/[|;&][[:space:]]*node[[:space:]]/ { next }
```

(this replaces `!/[|][[:space:]]*node[[:space:]]/`). With it:
- The real file still passes (15 sites). The echoed `regenerate with node …` hints at lines 2137 and 2153 and the AC table row at 5810 stay skipped.
- The echo-chain mutation fails TEST-2206 with `8509:   echo "== audit" && node "$AUDIT_SCRIPT" --check`.
- All four shapes above are caught by the awk probe.

Add `echo x && node "$AUDIT_SCRIPT" --check` and `cp a b; node .aai/scripts/generate-docs-index.mjs` as positive controls.

A known gap outside the claim is indirection through a variable, such as `"$NODE" "$AUDIT_SCRIPT"`. The corpus has no `$NODE`, and the claim is about literal `node` launches. That is INFO, not a finding.

## NON-BLOCKING

- **N2 (carried): the line numbers TEST-2206 prints are cosmetic.** Disposition (d), P3. `accepted residual: TEST-2206 failure messages report joined-logical line numbers; no false pass, the offending text is printed in full`

## Reviewer evidence

| Command | Result |
|---|---|
| `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` (scratch clone at d55bc491) | rc 0, 83 s, 0 FAIL, clone tree clean |
| `check-test-registration.mjs tests/skills` | rc 0 |
| `mutation-gate.mjs --spec <spec>` (worktree, read-only) | GATE PASS 11 rows, degraded=0 |
| `git diff --quiet 34f0cbca d55bc491 -- .aai/` | rc 0 |
| awk probe of audit_prog: exec, time, eval, `$(node --no-warnings …)`, `NODE_OPTIONS=x node`, `run node`, `x=1; node` | 7 of 7 caught |
| awk probe: echo &&, echo ;, printf ;, cp && | 4 of 4 MISSED |
| TEST-2206 at HEAD with an echo-chain mutation and a cp-chain generator mutation | 2 of 2 PASS (bite miss) |
| Proposed `[|;&]` fix: clean file, echo-chain mutation | PASS, FAIL (as intended) |

## Next steps

1. Apply the one-token B1-r2 fix in both programs, add the two controls, and re-review.
2. N2 stays an accepted residual.
3. After push, close the cannot_verify items and fill in the Spec-AC-06 hosted rows and the weights row.

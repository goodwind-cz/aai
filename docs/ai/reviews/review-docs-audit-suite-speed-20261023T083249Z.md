```yaml
review:
  scope: "git diff 34f0cbca..01f94e8b (branch change/docs-audit-suite-speed, worktree /private/tmp/aai-docs-audit-speed)"
  spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-2201 PASS in reviewer full run; docs/analysis/docs-audit-suite-speed.md (unchanged since round 1)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/docs-audit-live.sh; TEST-2202/2203 PASS; TEST-2206 PASS on the real file but its guard still misses ordinary launch shapes (BLOCKING B1-r)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs-audit-live.sh index pair + setup_indexarm_snapshots; TEST-2204/2205 PASS; tree clean after the reviewer run" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test_histmap_corpus_equivalence PASS locally (Node 22); CI Node 20 is cannot_verify" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/lib/docs-audit-closeout.test.mjs via TEST-2208 PASS; TEST-2211 PASS" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "accepted deviation: row deferred, Review-By 2026-11-06; hosted after rows and suite-weights.tsv re-measure pending push" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "reviewer wrapper run rc 0 'PASS: All aai-docs-audit tests passed' (78 s); check-test-registration rc 0; mutation-gate GATE PASS 11 rows" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8604,
          issue: "B1 not fully resolved. TEST-2206 still claims a universal negative (name; spec lines 267 and 353 say no consumer bypasses the helper). Its launch pattern only accepts node after ^ ( ; & { then do, so the ordinary bash shapes if / ! / || / while in front of node are not scanned.",
          failure_scenario: "Reviewer mutations in a scratch copy, each added as a new function: 'if node \"$AUDIT_SCRIPT\" --check --strict --no-event > x.log 2>&1; then :; fi', '! node .aai/scripts/docs-audit.mjs --check ...', 'true || node .aai/scripts/docs-audit.mjs --check ...', '(cd \"$PROJECT_ROOT\" && if node .aai/scripts/generate-docs-index.mjs; then :; fi)'. All four: TEST-2206 rc 0, 'PASS: No direct real-corpus launch; 15 live_audit call sites'. Each is an uncached real-corpus launch, or an unrestored real INDEX.md rewrite for the generator case, that the test says does not exist." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8594,
          issue: "Line numbers in a TEST-2206 failure message count joined logical lines, not file lines (cosmetic; validation NB).",
          failure_scenario: "A bypass after any backslash-continued line is reported at a line number lower than its real one. The operator greps for it and finds it. No false pass." }
  cannot_verify:
    - { claim: "Worker sharding and the node:test file behave the same on CI Node 20",
        closes_with: "green hosted skill-suite run of test-aai-docs-audit.sh on the pushed head, with the 'shards=' info line showing >=2" }
    - { claim: "Suite passes under GNU Bash 5 with set -euo pipefail (only Bash 3.2 exercised locally)",
        closes_with: "hosted Linux run on the pushed head" }
    - { claim: "Spec-AC-06 hosted after durations and the re-measured aai-docs-audit weight row",
        closes_with: ">=3 hosted runs on the final suite blob; suite-weights.tsv row + test-aai-suite-select.sh rc 0" }
  overall: fail
```

# Code review: docs-audit-suite-speed (round 2, re-review after 01f94e8b)

- **Scope:** `git diff 34f0cbca..01f94e8b`, in worktree mode with base main. This matches the STATE `code_review.scope` path list.
- **Spec:** docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md (frozen).
- **Outside the scope:** the uncommitted `docs/ai/roadmap.yaml` edit.
- **Dispatch note:** the dispatch named the accepted deviations and the validator's list of NBs. The full diff was reviewed anyway.

## BLOCKING

**B1-r. TEST-2206 still overpromises. It is narrower than before, but some common shapes still get through** (`tests/skills/test-aai-docs-audit.sh:8604` and `:8613`).

Commit 01f94e8b took option (b) from round 1:
- joins backslash-continued lines
- matches `$AUDIT_SCRIPT` and absolute-path forms
- raises the floor to an exact 15

It did not rename the test. The name, and spec lines 267 and 353, still say *no* consumer bypasses the helper. The prefix group `(^|[(;&{]|then|do)` leaves out `if`, `!`, `||` and `while`.

All four mutations listed in the YAML pass TEST-2206 with rc 0. In bash suites, `if node …; then` is the most common way to launch a command whose result is checked.

A reviewer corpus sweep of the current file found no real launch in any of these shapes. So the claim is true today, but the guard does not hold it. Under the review contract, a test whose name claims "no X" while checking only some paths is BLOCKING.

**Minimal fix (verified in a scratch copy):** in both awk programs, drop the prefix anchor and skip echo, printf and table rows. Replace

```
/(^|[(;&{]|then|do)[[:space:]]*([A-Za-z_]+=[^[:space:]]*[[:space:]]+)*node[[:space:]]
```
with
```
/(^|[^[:alnum:]_.\/-])node[[:space:]]
```
and replace the skip line with
```
/^[[:space:]]*#/ || /^[[:space:]]*(cp|echo|printf|[|]) / { next }
```

Results with this fix:
- The real file still passes (15 sites).
- `if`, `||`, `bash -c "node …"`, and the earlier B1 shapes all fail TEST-2206.
- A fixture launch such as `(cd "$TEST_DIR/fx" && if node …)` is still exempt.

A smaller alternative, also verified: widen the prefix group to `(^|[(;&{|!]|then|do|if|elif|while|until|time|exec)`. This closes `if`, `!`, `||` and `while`, but not `bash -c` or `eval`.

Add the `if node` and `|| node` mutation rows to the TDD evidence. A rename alone would also clear the finding. It would need a spec amendment, because D5, the Test Plan and lines 267 and 353 name the claim.

## NON-BLOCKING

- **N1 (round 1): resolved.** `docs-audit-live.sh:35-36` now resets `LIVE_ROOT` and `LIVE_CACHE_DIR` to empty at source time. `live_test_enter` still sets both, and TEST-2202 to 2205 pass.
- **N2. The line numbers TEST-2206 prints are cosmetic.** It reports positions in the joined logical lines, not file lines. Recommended disposition (d), P3: `accepted residual: TEST-2206 failure messages report joined-logical line numbers; no false pass, the offending text is printed in full`.
- **The heredoc false positive is fail-safe.** It can only over-flag. That is INFO, not a finding.

## Reviewer evidence

| Command | Result |
|---|---|
| `env -u AAI_ROLE AAI_TEST_TIMEOUT=900 bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh` | rc 0, 78 s, tree clean except roadmap.yaml and the untracked round-1 review |
| `mutation-gate.mjs --spec <spec>` | GATE PASS 11 rows |
| `check-test-registration.mjs tests/skills` | rc 0 |
| `git diff --quiet 34f0cbca -- .aai/` | rc 0 (production code unchanged) |
| TEST-2206 mutations at HEAD (scratch copy): `if node`, `! node`, `\|\| node`, `&& if node` generator | 4 of 4 PASS (bite miss) |
| TEST-2206 mutations at HEAD: `$(node …)`, `(cd "$PROJECT_ROOT" && node …)`, `out="$(time node …)"` | 3 of 3 FAIL (caught) |
| Proposed unanchored fix (scratch copy): clean file, `if`, `\|\|`, `bash -c`, fixture-exempt | PASS, FAIL, FAIL, FAIL, PASS (as intended) |
| `docs-audit.mjs` / `generate-docs-index.mjs` root selection | `process.cwd()` only, no `--root`, so the cd-based fixture exemption is sound |

## Next steps

1. Apply the B1-r fix: preferably the unanchored pattern, or else the widened prefix. Add the two mutation rows, then re-review.
2. Record the N2 disposition.
3. After push, close the cannot_verify items and fill in the Spec-AC-06 hosted rows and the weights row.

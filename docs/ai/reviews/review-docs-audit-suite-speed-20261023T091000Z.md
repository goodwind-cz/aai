```yaml
review:
  scope: "git diff 34f0cbca..4db58f0f (branch change/docs-audit-suite-speed, worktree /private/tmp/aai-docs-audit-speed, base main)"
  spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-2201 PASS in reviewer full run at 4db58f0f; docs/analysis/docs-audit-suite-speed.md unchanged since round 1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/docs-audit-live.sh; TEST-2202/2203 PASS; TEST-2206 PASS on the real file (15 sites, spec floor 14); B1-r3a/b/c closed: 10/10 bite mutations FAIL TEST-2206 at 4db58f0f" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs-audit-live.sh index pair; TEST-2204/2205 PASS; generator controls added in 4db58f0f are caught" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test_histmap_corpus_equivalence PASS locally; CI Node 20 is cannot_verify" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-2208/2209/2211 PASS in reviewer full run at 4db58f0f" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "accepted deviation: row deferred to 2026-11-06; hosted after rows and suite-weights.tsv re-measure pending push" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "reviewer run of the suite at 4db58f0f in a scratch clone: rc 0, 'PASS: All aai-docs-audit tests passed', 79 s, 0 FAIL lines; check-test-registration rc 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8609,
          issue: "N4 (carried, filed): deliberate indirection gets past the static scan and nothing at runtime backs it up",
          failure_scenario: "'\"$NODE\" \"$AUDIT_SCRIPT\" --check', '/usr/local/bin/node ...', 'local audit=\"$AUDIT_SCRIPT\"' then 'node \"$audit\"', '(cd \"$PROJECT_ROOT\" && .githooks/pre-commit)' all ESCAPE the committed awk programs. None occur in the corpus." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8645,
          issue: "N2 (carried): TEST-2206 failure messages report NR in the joined logical text, not the file line",
          failure_scenario: "A bypass after any backslash-continued line is reported at a lower line number than its real one. There is no false pass, and the offending text is printed in full." }
  cannot_verify:
    - { claim: "The lits() awk function and the scan behave the same under GNU awk/mawk on the CI runner (only BSD awk exercised here)",
        closes_with: "hosted Linux run of test-aai-docs-audit.sh on the pushed head" }
    - { claim: "Worker sharding and the node:test file behave the same on CI Node 20",
        closes_with: "green hosted skill-suite run showing 'shards=' >= 2" }
    - { claim: "Spec-AC-06 hosted after durations and the re-measured aai-docs-audit weight row",
        closes_with: ">=3 hosted runs on the final suite blob; suite-weights.tsv row + test-aai-suite-select.sh rc 0" }
  overall: pass
```

# Code review: docs-audit-suite-speed (round 5, confirmation of the B1-r3 fix)

- **Scope:** `git diff 34f0cbca..4db58f0f`. Since round 4 (d6434432), one commit: 4db58f0f, which changes TEST-2206 in `tests/skills/test-aai-docs-audit.sh` and appends one `follow_up` line to `docs/ai/decisions.jsonl`.
- **Spec:** docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md (frozen).
- **Outside the scope:** the uncommitted `docs/ai/roadmap.yaml` edit and the untracked review reports from rounds 1 to 4.
- **Dispatch note:** the dispatch named accepted deviations (Spec-AC-06 deferred, suite-weights pending hosted re-measure) and asked that N4-class shapes not be reopened unless the fix caused a regression. Neither is coaching on new findings. The whole round-5 delta was still reviewed.

## BLOCKING

None. B1-r3a, B1-r3b and B1-r3c are resolved.

## Evidence

1. **The committed fix is the verified fix.** `git show HEAD:tests/skills/test-aai-docs-audit.sh` is byte-identical to the round-4 verified `cr7/fixed-suite.sh`. The +/- lines of `git show 4db58f0f -- tests/skills/test-aai-docs-audit.sh` are identical to `cr7/fix.diff`. The awk programs extracted from HEAD (`:8609-8646`) are identical to `cr7/progs-fixed.sh`.
2. **The probe was re-run against the programs extracted from HEAD.** The script is `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr8/probe-head.sh`. Over the 103-shape set (`cr7/all.txt`), 84 are CAUGHT and 19 ESCAPE. That matches the round-4 projection exactly. The 19 escapes are the same set that round 4 classified: 4 non-launches, 13 N4 indirection shapes, and 2 deliberate exemption abuses (`| grep -q -- --list` and `cd "$PROJECT_ROOT/.aai/.."`). None of them is new.
3. **Bite test of the real function.** Each of 10 lines was inserted into a scratch copy of the HEAD suite, and `test_2206_no_direct_live_corpus_launch` was run on that copy. The lines were the three B1-r3a echo/printf shapes, the brace and trailing-slash PROJECT_ROOT cds (B1-r3b), the two whole-line cd exemptions (B1-r3c), the two N3 substring cases, and a printf pipe. **All 10 FAIL** with the offending line printed. The unmutated control PASSes (15 sites).
4. **Full suite at HEAD** (scratch clone `cr8/repo`, `env -u AAI_ROLE`): rc 0, `PASS: All aai-docs-audit tests passed`, 79 s. `check-test-registration.mjs tests/skills` returns rc 0.
5. **Ledger.** `decisions.jsonl` is append-only against base (0 removed lines), and the new line parses as JSON. `follow-ups.mjs list` shows `fu-docs-audit-bypass-node-shim` as open, P3, under ref docs-audit-suite-speed. N4 is therefore filed for real, not only suggested.

**Regression check on the fix itself.** Scoping the cd exemption to `cd "$X"[^)]*node` can only narrow the exemption, so any change it causes is a louder failure, never a new escape. If a future fixture line had a `$( )` between its cd and its node, TEST-2206 would fail and print that line. That is fail-closed. In `lits()`, an unterminated quote returns the open text, so the launch stays visible to the scan (also fail-closed). The real file still exempts the fixture lines at `index_generate_at`, `br_generate`, `live_test_repo` and `setup_ac24_fixture`, and the echoed STALE hints.

## NON-BLOCKING (dispositions)

- **N3 (substring flag exemption):** disposition (a), remediated in tree by 4db58f0f. Mutations 8 and 9 above prove it.
- **N4 (deliberate indirection has no runtime backstop):** P3, disposition (b), filed as `fu-docs-audit-bypass-node-shim` (decisions.jsonl, ts 2026-10-23T09:05:27Z).
- **N2 (joined-line NR in messages):** P3, disposition (d). `accepted residual: TEST-2206 failure messages report joined-logical line numbers; no false pass, the offending text is printed in full`

## Next steps

1. Push, then close cannot_verify items 1 and 2 with the hosted Linux run.
2. Spec-AC-06 stays deferred as accepted. Re-measure suite-weights after ≥3 hosted runs on the final suite blob.

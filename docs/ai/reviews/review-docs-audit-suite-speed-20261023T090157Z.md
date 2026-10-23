```yaml
review:
  scope: "git diff 34f0cbca..d6434432 (branch change/docs-audit-suite-speed, worktree /private/tmp/aai-docs-audit-speed, base main)"
  spec: docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-2201 PASS in reviewer full run at d6434432; docs/analysis/docs-audit-suite-speed.md unchanged since round 1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/lib/docs-audit-live.sh; TEST-2202/2203 PASS; TEST-2206 PASS on the real file (15 sites, spec floor 14). The guard has ordinary-shape escapes (BLOCKING B1-r3a/b/c), but no real launch in the corpus bypasses the helper today" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "docs-audit-live.sh index pair; TEST-2204/2205 PASS; index_generate_at on PROJECT_ROOT is the exemption that spec TEST-2206 row names" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test_histmap_corpus_equivalence PASS locally; CI Node 20 is cannot_verify" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-2208/2209/2211 PASS in reviewer full run" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "accepted deviation: row deferred to 2026-11-06; hosted after rows and suite-weights.tsv re-measure pending push" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "reviewer run of the suite at d6434432 in a scratch clone: rc 0, 'PASS: All aai-docs-audit tests passed', 77 s, 0 FAIL; check-test-registration rc 0" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8608,
          issue: "B1-r3a: the echo/printf literal strip gsub(/\"[^\"$][^\"]*\"/) does not track quote pairing. After a quoted word that starts with $, it pairs the closing quote with the next opening quote. That deletes the unquoted ' && node ' text between them. Same defect at :8615 (gen_prog). d6434432 introduced it.",
          failure_scenario: "Each of these, added to a scratch copy of the suite at d6434432, gives TEST-2206 'PASS: No direct real-corpus launch': '  echo \"$msg\" && node \"$AUDIT_SCRIPT\" --check --strict --no-event > \"$TEST_DIR/m.log\" 2>&1', '  echo \"audit: $(node \"$AUDIT_SCRIPT\" --check)\"', '  echo \"$v\" > \"$TEST_DIR/f\"; node \"$PROJECT_ROOT/.aai/scripts/generate-docs-index.mjs\"'. An awk probe also missed 'echo x >\"$TEST_DIR/o\"; node ...' and 'printf \"%s\\n\" \"$x\" | node ...'." }
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8610,
          issue: "B1-r3b: the fixture-cd exemption only recognises the exact text cd \"$PROJECT_ROOT\". It reads cd \"${PROJECT_ROOT}\" or cd \"$PROJECT_ROOT/\" as a cd into a fixture and skips the line. Same at :8617.",
          failure_scenario: "With '  (cd \"${PROJECT_ROOT}\" && node .aai/scripts/docs-audit.mjs --check --strict --no-event)' or the same shape with generate-docs-index.mjs added to a scratch copy, TEST-2206 PASSes. The second one is an unrestored rewrite of the real INDEX.md." }
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8610,
          issue: "B1-r3c: the fixture-cd exemption covers the whole line. Any cd \"$X\" anywhere on the line excuses a real-corpus launch that runs outside that subshell, before it or after it. Same at :8617.",
          failure_scenario: "With '  (cd \"$d\" && git add -A && git commit -qm x) && node \"$AUDIT_SCRIPT\" --check' added, TEST-2206 PASSes. The intent was the fixture, but the audit runs on the suite's cwd, which is the real corpus. An awk probe also missed 'node \"$AUDIT_SCRIPT\" --check > x.log 2>&1 || (cd \"$TEST_DIR\" && cat x.log)' and '(cd \"$PROJECT_ROOT\" ...)' generator variants." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8611,
          issue: "N3: the flag exemption /--path|--quick|--lint-body|--ac-flip-check|--list/ matches substrings anywhere on the line, including file names and longer flags.",
          failure_scenario: "awk probe: 'node \"$AUDIT_SCRIPT\" --check > \"$TEST_DIR/quick--path.log\"', 'node \"$AUDIT_SCRIPT\" --check --strict --no-event --pathless' and 'node \"$AUDIT_SCRIPT\" --check | grep -q -- --list' are all skipped. All three are full real-corpus audits." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8609,
          issue: "N4: launches that use deliberate indirection get past the text scan. None of these occur in the corpus. Contrary to the dispatch premise, there is no runtime backstop. live_log_launch (docs-audit-live.sh:66) logs only launches that go through the helper, so a bypass is invisible to TEST-2202.",
          failure_scenario: "awk probe ESCAPE: '\"$NODE\" \"$AUDIT_SCRIPT\"', '\"$(command -v node)\" ...', '/usr/local/bin/node ...', '\"node\" ...', 'nodejs ...', 'local audit=\"$AUDIT_SCRIPT\"' then 'node \"$audit\"', 'node \"$PROJECT_ROOT/.aai/scripts/$name\"', and indirect launchers such as '(cd \"$PROJECT_ROOT\" && .githooks/pre-commit)' or other .aai scripts that spawn the generator." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8645,
          issue: "N2 (carried): TEST-2206 failure messages report NR in the joined logical text, not the file line.",
          failure_scenario: "A bypass after any backslash-continued line is reported at a lower line number than its real one. There is no false pass, and the offending text is printed in full." }
  cannot_verify:
    - { claim: "The proposed lits() awk function and the existing scan behave the same under GNU awk/mawk on the CI runner (only BSD awk exercised here)",
        closes_with: "hosted Linux run of test-aai-docs-audit.sh on the pushed head with the fix" }
    - { claim: "Worker sharding and the node:test file behave the same on CI Node 20",
        closes_with: "green hosted skill-suite run showing 'shards=' >= 2" }
    - { claim: "Spec-AC-06 hosted after durations and the re-measured aai-docs-audit weight row",
        closes_with: ">=3 hosted runs on the final suite blob; suite-weights.tsv row + test-aai-suite-select.sh rc 0" }
  overall: fail
```

# Code review: docs-audit-suite-speed (round 4, exhaustive adversarial pass on TEST-2206)

- **Scope:** `git diff 34f0cbca..d6434432`. Since round 3, only TEST-2206 in `tests/skills/test-aai-docs-audit.sh` has changed.
- **Spec:** docs/specs/SPEC-0245-spec-docs-audit-suite-speed.md (frozen).
- **Outside the scope:** the uncommitted `docs/ai/roadmap.yaml` edit and the untracked review reports from rounds 1 to 3.
- **Dispatch note:** the dispatch named the accepted deviations and gave a proposed severity rubric. The rubric is "accidental means BLOCKING, deliberate obfuscation means NON-BLOCKING". It is consistent with the contract's "failure scenario" bar, so it was applied. The dispatch also said the TEST-2202 launch-count shim is a runtime backstop. That is not accurate (see N4). The full diff was still reviewed.

## Method

The scan programs were extracted verbatim from d6434432 and run against 103 candidate launch shapes. The shapes covered:
- separators, subshells and grouping
- here-strings and `bash -c`
- `command`, `env`, `exec`, `time`, `timeout`, `nice`, `xargs` and `find -exec`
- arrays, `eval`, `coproc` and backticks
- line continuations and multi-line `$( )`
- echo/printf interplay and the cd exemption
- the flag exemption and node binary or script indirection

The probe script is at `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr7/probe.sh` and the cases are in `all.txt` in the same directory. Six representative escapes were then bite-tested by inserting them into a scratch copy of the suite and running the real `test_2206_no_direct_live_corpus_launch` function. Each one PASSes at d6434432 and FAILs with the fix. Of the 103 shapes, 66 are caught at HEAD and 37 escape. The fix catches 18 of those 37 and loses none of the 66. Of the 19 still escaping:
- 4 are not launches: a lone `)"` line and a line that starts with `|` (both probe artefacts), `node .aai/scripts/docs-audit` without `.mjs`, and the bare `local audit=` assignment.
- 13 are the deliberate shapes listed under N4.
- 2 are deliberate exemption abuse: N3's `grep -- --list`, and `cd "$PROJECT_ROOT/.aai/.."`.

## BLOCKING

All three are in the same two awk programs, at `:8606-8618`. One patch fixes all three. It was verified in the scratch clone at `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/cr7/repo`, and the diff is in `fix.diff` in the cr7 directory.

**B1-r3a. The echo/printf literal strip does not pair quotes** (introduced by d6434432).

The gsub `"[^"$][^"]*"` starts a match at any quote, including a closing one. So in `echo "$msg" && node "$AUDIT_SCRIPT"`, it deletes `" && node "`. These all get past the scan:
- `echo "$msg" && node "$AUDIT_SCRIPT" --check`
- `echo x >"$f"; node …`
- `printf "%s\n" "$x" | node …`
- `echo "audit: $(node "$AUDIT_SCRIPT" --check)"`
- the generator equivalents

These are ordinary shapes.

**B1-r3b. `cd "${PROJECT_ROOT}"` and `cd "$PROJECT_ROOT/"` count as fixture cds.** Both the audit and the generator lines then get past the scan. Brace style is an ordinary thing to write.

**B1-r3c. The cd exemption covers the whole line.** `(cd "$d" && git commit -qm x) && node "$AUDIT_SCRIPT" --check` and `node … || (cd "$TEST_DIR" && cat log)` both get past the scan. The first is exactly the accidental shape the guard exists for: the author meant the fixture, but the launch runs outside the subshell, on the real corpus.

**Minimal fix (verified).** Replace the two gsubs with a quote-pairing `lits()` function. It drops literal double-quoted text and single-quoted text. It keeps words that start with `$` and keeps the code inside `$( )`. Scope the cd exemption to a `cd "$X" … node` run with no `)` between them, and accept the brace and trailing-slash spellings of PROJECT_ROOT:

```
/^[[:space:]]*(echo|printf) / { $0 = lits($0) }
...
if ($0 ~ /cd "\$[^"]*"[^)]*node[[:space:]]/ && $0 !~ /cd "\$\{?PROJECT_ROOT\}?\/?"/) next
```

Verification of the fix in the scratch clone:
- **Real file:** TEST-2206 PASS, 15 sites. The echoed STALE hints at :2137 and :2153 stay exempt, and so do `index_generate_at`, `br_generate`, `live_test_repo` and `setup_ac24_fixture`.
- **Full suite:** rc 0, `PASS: All aai-docs-audit tests passed`.
- **Mutations:** all 6 bite mutations FAIL TEST-2206 with the offending line printed.
- **New positive controls:** 4 audit shapes and 1 generator shape, the ones listed in fix.diff.

Pitfall seen while verifying: `local … lits_fn` must come before the `lits_fn=` assignment. Declaring it after the assignment silently empties it.

## NON-BLOCKING

- **N3, the flag exemption matches substrings** (`:8611`). P3, disposition (a) remediate in tree. The same fix.diff anchors it as `/[[:space:]]--(path|quick|lint-body|ac-flip-check|list)([[:space:]=]|$)/`. After that, `quick--path.log` and `--pathless` are caught. `| grep -q -- --list` still gets past and is accepted as deliberate.
- **N4, deliberate indirection has no backstop.** P3, disposition (b) promote to a follow-up, `suggested: fu-docs-audit-bypass-node-shim`. The shapes are an indirect node binary (`"$NODE"`, `$(command -v node)`, an absolute path, a quoted `"node"`, `nodejs`), a script alias variable, a built script path, and other programs that spawn the generator (the pre-commit hook, `.aai` scripts). None exist in the corpus. Note the correction to the dispatch: `live_log_launch` (docs-audit-live.sh:66) records only launches that go through the helper. TEST-2202 therefore cannot see a bypass, and today nothing at runtime backs up the text scan. The follow-up would put a PATH `node` shim in place for the ordinary run. It would log any `docs-audit.mjs` or `generate-docs-index.mjs` invocation whose cwd is PROJECT_ROOT and whose parent is not the helper, and assert the count is no more than the helper's own launch log.
- **N2 (carried), the line numbers are cosmetic.** P3, disposition (d). `accepted residual: TEST-2206 failure messages report joined-logical line numbers; no false pass, the offending text is printed in full`

## Next steps

1. Apply fix.diff, or an equivalent, to `test_2206_no_direct_live_corpus_launch`, including the N3 anchor and the new positive controls. RED evidence is the 6 mutations above, which PASS at d6434432.
2. Re-review should be one check: the probe set in the scratch directory plus the real-file run. No new shape class is outstanding beyond N4.
3. The orchestrator records N4 as a follow-up and N2 as a residual.

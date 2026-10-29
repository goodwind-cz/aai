```yaml
review:
  scope: git diff main...HEAD (base main, head dc25add4, branch chore/docs-audit-content-engine-split)
  spec: docs/specs/SPEC-DRAFT-spec-docs-audit-content-engine-split.md (frozen + Amendment 1, A1-a to A1-m)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2301 (test-aai-docs-audit.sh); note docs/analysis/docs-audit-content-engine-split.md; mutation-gate GATE PASS 12 rows" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2302 test-aai-suite-select.sh rc 0 (re-run); TEST-2303 test-aai-lightweight-lane.sh:323-326 test_017 rc 0 (re-run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-2304 (validation r3 engine suite rc 0); allowlist row nested-suite-allowlist.tsv:9; A1-c wording deviation" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2305 rc 0 (re-run); TEST-2306 rc 0 (re-run) plus reviewer mutation (drop docs-audit check-state glob in a scratch copy) RED naming test_change0012_allocation_durability; reviewer corpus sweep of every path token in 174 engine bodies: no real-tree hole; suite-map.yaml:388-389" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2307 rc 0 (re-run); content suite rc 0 (re-run); .aai/ untouched in diff" }
      - { ac: Spec-AC-06, call: compliant, citation: "docs-audit-gate.test.mjs pass 5 fail 0 (re-run); TEST-2308/2309 in validation r3 engine run" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2310 passed inside reviewer content-suite run; RFC-0017 row 2 done, row 4 links CHANGE-0228" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2311 (suite-select rc 0 re-run); TEST-2312 delta-stage3 companion suite-map.yaml:287" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/nested-suite-allowlist.tsv, line: 3,
          issue: "Carried from r1 F-N1, unchanged by design: the header still says 'The allowlist only shrinks' while the file grew 3 to 4 rows (A1-i).",
          failure_scenario: "A later ratchet author trusts the header and refuses a legitimate row, or treats growth as unprecedented; the record is false as of this branch." }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 377,
          issue: "docs/project-sessions/**, CHANGELOG.md, README.md and docs/TECHNOLOGY.md stay on the aai-docs-audit (engine) row, but no engine case reads them (no occurrence in test-aai-docs-audit.sh outside a fixture br_write). docs/project-sessions/** maps to no other suite.",
          failure_scenario: "A session-journal-only PR (only docs/project-sessions/<x>.md) used to run docs-audit as core, 144.8 s median. It now selects the engine suite and the core content suite, 131.7 s + about 40 s = about 172 s by the note's own medians, possibly on two runners. This is slower than before for a common document-only PR class, which the split was meant to make cheaper. A1-h discloses the double cost only for engine-input PRs." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8953,
          issue: "The widened TEST-2306 extractor catches the relative form only when the path follows `cd \"$PROJECT_ROOT\" &&` on the SAME line, preceded by whitespace. It misses a path on a backslash-continuation line, a quoted relative path (node \".aai/scripts/x.mjs\"), and `cd \"$PROJECT_ROOT\";` or `|| exit` forms.",
          failure_scenario: "A future engine case writes `(cd \"$PROJECT_ROOT\" && node \\` and puts `.aai/scripts/new.mjs ...)` on the next line. TEST-2306 extracts nothing, stays green, and a PR that changes only new.mjs under-selects the engine suite. None of these forms exists today: a reviewer corpus sweep over every path token in all 174 engine bodies found no real-tree hole." }
  cannot_verify:
    - { claim: "TEST-2304 and the content suite behave the same on the hosted Linux runner (clone of the PR merge checkout, framework isolation, GNU grep for the widened -oE '(^|[[:space:]])' extraction)", closes_with: "a hosted skill-suite run of this branch with aai-docs-audit selected, green" }
    - { claim: "Timing claims (Content ratio 0.28, Gate ratio 0.07, 131.7 s and 144.8 s medians) carry over to hosted CI", closes_with: "hosted durations after a weights reseed (the note reports local only)" }
    - { claim: "Non-literal real-tree reads, i.e. paths computed at run time or reached through helper functions, are covered", closes_with: "an instrumented engine run that logs real-tree opens; the spec names this as a residual risk" }
    - { claim: "Owner acceptance of Amendment 1 (A1-a to A1-m, owner_signoff false), in particular A1-i ratchet growth and the in-place edits of frozen Test Plan cells", closes_with: "owner decision at merge, which closes fu-amend-docs-audit-content-engine-split" }
  overall: pass
```

# Code review: docs-audit-content-engine-split, round 2

security_relevant: false

- Scope: `git diff main...HEAD` in /Users/ales/Projects/aai-wt-docs-audit-split, head dc25add4 (24 files). STATE `worktree.user_decision: worktree`, base `main`. I reviewed the whole diff, not only the remediation delta 622a599d and dc25add4.
- Spec: docs/specs/SPEC-DRAFT-spec-docs-audit-content-engine-split.md (frozen, Amendment 1 A1-a to A1-m). spec-lint: LINT PASS. mutation-gate: GATE PASS, 12 rows. `spec-amend list --strict`: rc 0, with five unsigned-tracked records under fu-amend-docs-audit-content-engine-split.
- Dispatch note (anti-gaming contract): the dispatch named r1's findings and the remediation commits, and it suggested defect classes to look for. It also said in advance that F-N1 is "intentionally not changed". I recorded this and reviewed the full scope with my own probes.
- Working-tree note: `docs/ai/EVENTS.jsonl` was already modified when I started. During this review, `docs/ai/overview-data.json` and `docs/ai/overview.html` were regenerated at 18:01:56Z. Their content is an overview refresh that adds this ride's in-progress row, which is not what a test writes, and every wrapper run reported `AAI-ISOLATION: isolated`. They look like a hook or orchestrator refresh, not output of my runs. I did not touch, stage or restore them. The orchestrator should decide whether they belong in the ride.

## r1 findings: resolution check

| r1 finding | Status | Evidence |
|---|---|---|
| F-B1 (BLOCKING) | **resolved** | suite-map.yaml:388-389 adds `.aai/scripts/check-state.mjs` and `.aai/scripts/select-suites.mjs` to aai-docs-audit. Both now print `SELECTED aai-docs-audit` through the real selector. TEST-2306 now extracts the quoted form (`root_re` with optional `"`) and the same-line `cd "$PROJECT_ROOT" &&` relative form. My own mutation in a scratch copy (`git archive HEAD`) removed only the aai-docs-audit `check-state.mjs` glob and left aai-check-state's copy, and TEST-2306 went RED: `FAIL: TEST-2306: .aai/scripts/check-state.mjs (read by engine case test_change0012_allocation_durability) selects neither ...`. The recorded mutation (select-suites glob) is RED too. My first attempt deleted both copies of that line; the path then became unmapped, and TEST-2306 correctly passed on FULL_RUN, so the failure is not a false red. |
| F-N2 (NB) | **resolved** | test-aai-docs-audit.sh:8973-8974 floor `(( nfn > 0 && npath > 0 )) \|\| log_fail`. This is safe under `set -e`: the arithmetic sits on the left of `\|\|`. |
| F-N1 (NB) | **open, owner decision** | The header at nested-suite-allowlist.tsv:3 still says "only shrinks", although it now pins 4. It is carried below as NB-1. |

### Independent hole scan (re-run through the real selector)

I took every `(\.aai|\.claude|\.github|tests|docs)/...` token in the bodies of all 174 engine-registered functions, from any form (not only the forms TEST-2306 parses). That gave 316 unique paths, each sent to `select-suites.mjs`. 177 select neither aai-docs-audit nor FULL_RUN. Of those, 174 are fixture names that do not exist in the real tree. Three exist: `docs/INDEX.md`, `docs/ai/EVENTS.jsonl` and `docs/ai/METRICS.jsonl`. Every engine case that names them uses them only as fixture-relative paths, because TEST-2306 would have caught any `$PROJECT_ROOT/` form, and no `cd "$PROJECT_ROOT"` line names them. Helper-read real paths (append-event.mjs, install-pre-commit-hook.sh, DOCS_AI_CANON.list, both analysis notes, lib/*.mjs) and `.gitattributes` all select aai-docs-audit or FULL_RUN. I found no remaining real-tree hole.

### Remediation side effects checked

- Widened extractor on BSD grep (macOS bash 3.2, the suite's own `set -euo pipefail`) extracts exactly state.mjs, check-state.mjs, select-suites.mjs and the two node test files. `\|\| true` covers the whole pipeline. No `printf | grep -q`.
- False-positive exposure: a same-line fixture-relative argument after `cd "$PROJECT_ROOT" &&` (for example `--spec-path docs/specs/...`) would be extracted and fail closed. That fails safe, as a red rather than a hole. Today such an argument appears only on a continuation line (line 4517), so it is not extracted. INFO only.
- dc25add4 pins: each changes exactly one tuple, `['2','in progress']` to `['2','done']`, in TEST-2623, TEST-2716 and TEST-2825. Rows 0, 1, 3 and 5, the row-4 retire logic and the byte-pair ratio are unchanged. The pin is exact (`done`), not loosened. TEST-2623 rc 0 and recheck.test.mjs (85 pass, 0 fail) were re-run by me.
- Spec text: the frozen Test Plan row TEST-2306 (Description and Mutation cell) and the "Not touched" line were edited in place and the hash was restamped. A1-k and A1-l disclose this, and spec-amend `--strict` rc is 0. The A1 preamble says "the original text above is kept", which is not literally true for those cells. A1-f, A1-g and A1-k each name the cell rewrites, so this is INFO only.

## AC table walk

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | TEST-2301 in validation r3 engine run (rc 0). Mutation record present, gate PASS. |
| Spec-AC-02 | compliant | TEST-2302: suite-select rc 0, re-run by me. TEST-2303: lightweight-lane test_017 rc 0, re-run by me. |
| Spec-AC-03 | compliant | TEST-2304 (validation r3, engine suite rc 0). A1-c deviation disclosed. |
| Spec-AC-04 | compliant | TEST-2305 rc 0 and TEST-2306 rc 0, re-run by me. Mutation RED confirmed by me. The corpus sweep above finds no hole. The A1-d exclusions are disclosed. |
| Spec-AC-05 | compliant | TEST-2307 rc 0 (195 = engine + 24 + 5, check-test-registration rc 0), re-run by me. Content suite rc 0, re-run by me. Nothing under `.aai/` is in the diff. |
| Spec-AC-06 | compliant | docs-audit-gate.test.mjs 5 pass, re-run by me. TEST-2308 and TEST-2309 ran in validation r3. |
| Spec-AC-07 | compliant | TEST-2310 PASS inside my content-suite run. |
| Spec-AC-08 | compliant | TEST-2311 PASS (suite-select). TEST-2312: delta-stage3 companion. hygiene-pack test_133 (4-row pin) rc 0, re-run by me. |

Deviations from the frozen text, all disclosed in Amendment 1 (A1-a to A1-m): 24 content names; setup in both suites; TEST-2304 wording; TEST-2306 exclusions and widened forms; extra content-row globs (INDEX, EVENTS); rewritten mutation cells; the TEST-2310 path; engine median not lower than the old suite; allowlist growth from 3 to 4; four input-closure globs beyond D3 (check-test-registration, check-state, select-suites, plus the five in A1-e); the delta-stage3 message edit; and the three earlier-ride pins (A1-m). None of them is signed by the owner.

## Findings

### NB-1 (carried r1 F-N1): the allowlist header claims "only shrinks"
- tests/skills/lib/nested-suite-allowlist.tsv:3. The scenario is in the YAML block above.
- Recommended disposition: (c) tracked by the existing owner sign-off follow-up `fu-amend-docs-audit-content-engine-split`, which covers A1-i. If the owner keeps the row, reword the header in tree to name the A1-i exception. If the owner narrows TEST-2304, the row goes away.

### NB-2 (new): content-only globs left on the engine row
- tests/skills/suite-map.yaml, aai-docs-audit row: `docs/project-sessions/**`, `CHANGELOG.md`, `README.md`, `docs/TECHNOLOGY.md`. No engine case reads them. Their old purpose was the live-corpus cases, which now live in the core content suite.
- Failure scenario: a PR that only changes a session journal now costs about 172 s (engine plus content) instead of 144.8 s. The same applies to a CHANGELOG-only or README-only PR. This is spec-compliant, because D3 keeps every engine glob, but it works against the stated goal of the split.
- Recommended disposition: remediate in tree by moving the four globs to the aai-docs-content row. CHANGELOG, README and TECHNOLOGY are also mapped by aai-release, aai-roadmap and aai-win-fallback, and the content row keeps project-sessions mapped, so nothing falls to unmapped FULL_RUN. Then add a TEST-2302-style probe. Alternatively, use (b) `suggested: fu-docs-split-content-globs-on-engine-row` (P3).

### NB-3 (new): TEST-2306 relative-form coverage is same-line only
- tests/skills/test-aai-docs-audit.sh:8953-8956. The scenario is in the YAML block above.
- Recommended disposition: (d) accepted residual: P3 assurance-strength. No instance exists today (the reviewer corpus sweep found 0 real-tree holes) and the guard leaves no false record. The spec already names non-literal reads as residual risk.

## Runs by the reviewer (worktree, `env -u AAI_ROLE`, through aai-run-tests.sh, one per call)

- `test-aai-docs-audit.sh test_2306_engine_input_closure`: rc 0
- `test-aai-docs-audit.sh test_2307_case_inventory_partition`: rc 0
- `test-aai-docs-audit.sh test_2211_migration_map_owners`: rc 0
- `test-aai-docs-audit.sh test_change0012_allocation_durability` alone: rc 1. This is a pre-existing single-dispatch limitation: `TEST_DIR` is unset without `setup_fixture`, so it fails with `mkdir: /iso-c12-alloc: Read-only file system`. The function and `main()` dispatch are unchanged from main. Through a scratch driver (`check_deps; setup_fixture; test_change0012_allocation_durability; test_2211_migration_map_owners`): rc 0, all PASS.
- `test-aai-expert-fetch.sh test_2623_rfc_phase3_done`: rc 0
- `node --test tests/skills/lib/recheck.test.mjs`: rc 0 (85 pass)
- `node --test tests/skills/lib/docs-audit-gate.test.mjs`: rc 0 (5 pass)
- `test-aai-suite-select.sh`: rc 0
- `test-aai-docs-content.sh`: rc 0
- `test-aai-hygiene-pack.sh test_133_nested_suite_lint_live_and_base`: rc 0
- `test-aai-lightweight-lane.sh test_017_docs_only_close_diff_never_full`: rc 0
- Scratch-copy mutation (docs-audit check-state glob removed): TEST-2306 rc 1 with the expected FAIL line.

## Next steps

1. The orchestrator records dispositions: NB-1 (c) under fu-amend-docs-audit-content-engine-split, NB-2 remediate or (b), NB-3 (d) via the accepted residual line below.
2. Owner decision at merge on Amendment 1 (A1-i in particular).
3. One full sweep before close, which validation already schedules.

accepted residual: NB-3, TEST-2306 parses the relative read form only on the same line as `cd "$PROJECT_ROOT" &&` and only when the path is unquoted; P3 assurance strength, no instance in the current corpus (reviewer sweep, 0 real-tree holes), no false record.

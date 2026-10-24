# Code Review r4 (delta): node-first-third-slice

- Started: 2026-10-24T08:59:44Z
- Ended: 2026-10-24T09:15:33Z
- Report UTC stamp: 20261024T091533Z (copy as docs/ai/reviews/review-node-first-third-slice-20261024T091533Z.md)
- Reviewer: Code Review role, round 4, dispatched (state write returned, not run)

```yaml
review:
  scope: "296fed35..9659f076 (delta); full range 4d4566bc..9659f076, rounds 1-3 reviewed the rest"
  spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "no production change in the delta; r3 walk stands" }
      - { ac: Spec-AC-02, call: compliant, citation: "no production change in the delta; r3 walk stands" }
      - { ac: Spec-AC-03, call: compliant, citation: "no production change in the delta; r3 walk stands" }
      - { ac: Spec-AC-04, call: compliant, citation: "D-1 decision text spec:140; code unchanged; TEST-2627/2628/2630/2633 green in probe copy. The parenthetical about ps1 is still incomplete, see NB-1" }
      - { ac: Spec-AC-05, call: compliant, citation: "no production change in the delta; r3 walk stands" }
      - { ac: Spec-AC-06, call: compliant, citation: "expert-fetch.mjs:189 guard; TEST-2634 (expert-fetch.test.mjs:369-382) and test_2630 launcher case (test-aai-expert-fetch.sh:254-260) go red under the recorded /.*/ mutation. The case and dot parts of the guard are not pinned, see NB-2. The AC row's TEST column (spec:487) does not list TEST-2634, see NB-3" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2612 whole-source pin, test-aai-expert-fetch.sh:184-212; reverting the regex makes the shape loop go red. Residual evasion shape, see NB-4" }
      - { ac: Spec-AC-08, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-09, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-10, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-11, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-12, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-13, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-14, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-15, call: compliant, citation: "no change in the delta" }
      - { ac: Spec-AC-16, call: compliant, citation: "spec-amend list --strict on the probe copy: the 08:50:35Z record is unsigned-tracked (fu-amend-spec-node-first-third-slice, open) and the 08:55:03Z record is measurement; no unsigned-untracked or unclassified record" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0249-spec-node-first-third-slice.md, line: 140,
          issue: "The corrected D-1 wording and the 08:50:35Z contract record still list the ps1-over-blocking cases as exactly 'two non-canonical shapes'. There are at least three more.",
          failure_scenario: "Each case run through the ps1 regex (pwsh) and through parseRegistry. (1) A prefix: '- zblocked-extra' blocks category zblocked in ps1, the node parser does not. (2) A case variant: '- ZBlocked' blocks in ps1 (-match ignores case), the node parser does not. (3) A commented-out item: '  # - zblocked' blocks in ps1, the node parser does not. (2) is a canonical list item, not a non-canonical shape." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/expert-fetch.test.mjs, line: 369,
          issue: "Of the three TEST-2634 cases, only '../x' bites. Nothing is planted for 'Typescript' or 'type.script', so both refuse through !existsSync even when the guard is gone. The case-sensitivity part of the guard can be loosened and every test stays green.",
          failure_scenario: "Mutant: guard changed to /^[a-zA-Z][a-zA-Z0-9_-]*$/. TEST-2634, TEST-2630 and TEST-2629 all stay green. In a fixture with .aai/cache/experts/zblocked.md, '--body zblocked' is refused (blocked category) but '--body Zblocked' prints the blocked body with exit 0 on macOS (case-insensitive APFS), because reg.experts.get('Zblocked') is undefined, so the blocked check sees category ''. Measured on the probe copy. The production guard at expert-fetch.mjs:189 is correct; only the test misses it." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0249-spec-node-first-third-slice.md, line: 606,
          issue: "Stale or undisclosed spec text and ledger records for this delta. (a) The TEST-2629 row still says it runs '--body ../x exits 1 with empty stdout', but the commit moved that case out of TEST-2629 (expert-fetch.test.mjs:352-367 no longer has it). (b) The TEST-2630 row (spec:607) does not mention the new planted ../x launcher case and still says 'in all four'. (c) The Spec-AC-06 TEST column (spec:487) lists TEST-2610 and TEST-2629, not TEST-2634. (d) No ledger record discloses the new TEST-2634 row, the TEST-2629 and TEST-2630 changes, or the mapping change at spec:462. The 08:55:03Z measurement record names only a 'correction' to the mutation cell of a row whose first draft was never committed (296fed35 has no TEST-2634).",
          failure_scenario: "A validator walks the TEST-2629 row and looks for the ../x assertion it describes, but the assertion is gone. A reader of decisions.jsonl cannot learn from any record that a TEST row was added in 9659f076." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-expert-fetch.sh, line: 192,
          issue: "The whole-source import pin misses a dynamic import with whitespace before the parenthesis.",
          failure_scenario: "With 'const n = await import (\\'node:net\\');' prepended to the module, import_pin_bad prints nothing: the 'import(' substring check misses the space, and \\bimport\\s*['\"] needs a quote, not '('. The line is valid ESM; node runs 'await import (\\'node:fs\\')' fine. Measured." }
  cannot_verify:
    - { claim: "RED/GREEN/mutation evidence for TEST-2634 exists under docs/ai/tdd/node-first-third-slice/",
        closes_with: "red/, green/ and mut/ hold no TEST-2634 log (mut/ ends at TEST-2626). The validator's mutation-gate run, or the logs it writes, would close this. My manual application of the row's sed went red, but that is not the recorded evidence." }
    - { claim: "the full bash suite and the CI legs (Linux, Windows Pester) are green at 9659f076",
        closes_with: "the running validator's full sweep and CI. I ran only test_2612, test_2629, test_2630, test_2634 and the 27-case node file (all green)" }
    - { claim: "the 'first draft' mutation cell described by the 08:55:03Z measurement record existed and stayed green",
        closes_with: "no commit holds it. Only the author's working-tree log could show it; git history cannot." }
  overall: pass
```

## Scope and spec

- Range: 296fed35..9659f076 (one commit, 9659f076). Spec: docs/specs/SPEC-0249-spec-node-first-third-slice.md. Probes ran in copies under cr16-work/ made with git archive. The shipping worktree was only read.
- Coaching check: the dispatch listed what to check and restated the commit's claims. It did not pre-rate any finding. Limiting the scope to the delta is the standard re-review shape after r3 passed. I checked every claim myself and did not take any on trust.

## The checks the dispatch asked for

1. **No production code.** Confirmed. `git diff --stat` shows four paths only: decisions.jsonl, the spec, expert-fetch.test.mjs and test-aai-expert-fetch.sh.
2. **New tests go red when the guard is removed.**
   - The row's exact sed (`/.*/.test(key)`) makes TEST-2634 go red ("node --test exited 1"). It also makes test_2630 go red: "--body ../x must exit 1 with empty stdout, got 0: PLANTED-SECRET".
   - TEST-2612 with the old line-anchored regex restored goes red: "the import pin missed this shape: import 'node:net';".
   - Weaker spots: NB-2 (the case and dot parts of the guard) and NB-4 (one evasion shape).
3. **The two ledger records.**
   - Both are append-only: two `+` lines at the end, and no earlier line is touched.
   - The contract record's text matches the D-1 diff, apart from the incomplete list in NB-1.
   - The measurement record is honest about the mutation cell, but it is the only ledger mention of a new TEST row (NB-3d).
4. **D-1 accuracy against the old ps1.** Better than r3, because it no longer claims parity. It is still not accurate: it lists two shapes where the true set is at least five (NB-1). The old ps1 line is `$RegistryContent -match "blocked_categories:[\s\S]*?- $Category"`, at 4d4566bc:.aai/scripts/expert-fetch.ps1:166. It matches case-insensitively, by prefix, and inside comments.
5. **Is the measurement record legitimate?**
   - Partly. Fixing a mutation cell that did not go red is the definition of measurement in spec-amend.mjs:189-193.
   - Adding a TEST row as evidence for an existing D-22 clause also arguably counts as measurement. The AC predicate is unchanged.
   - It does not hide a contract change. But it under-discloses: it names only the mutation cell, not the row addition, the TEST-2629/2630 text changes or the mapping line.

## Warning dispositions (H6). The orchestrator records these.

- **NB-1 (P3, leaves a false record).** Remediate in tree. Reword the D-1 parenthetical so it is not an exhaustive count. For example: "the old ps1 regex matched case-insensitively, by prefix, inside comments and anywhere after the heading, so it blocked more in several shapes (examples: …); this parser does not, accepted". Append a contract-class corrective record. Disposition (d) is not allowed here because a false record remains.
- **NB-2 (P2, a surviving mutant behind a measured bypass on macOS).** Remediate in tree. In TEST-2634, plant `.aai/cache/experts/type.script.md`, which bites on every filesystem. Also plant a cached `zblocked.md` and assert `--body Zblocked` exits 1 with empty stdout; this bites on case-insensitive filesystems. Record the mutant /^[a-zA-Z][a-zA-Z0-9_-]*$/ as a second mutation cell.
- **NB-3 (P3, leaves a false record).** Remediate in tree.
  - Fix the TEST-2629 row text, the TEST-2630 row text and the Spec-AC-06 TEST column.
  - Append one measurement-class record that names the new TEST-2634 row and these text changes.
- **NB-4 (P3, assurance strength, no observed bite).** Either an accepted residual (the module has no dynamic import and the "import(" check covers the usual spelling), or extend the check with `/\bimport\s*\(/`. Recommended: remediate in tree, since it is one line.

## Next steps

- Fold NB-1..NB-4 into one remediation commit (no module change needed), then a delta re-review.
- The pending validator run should produce the TEST-2634 red/green/mut evidence. That evidence closes the first cannot_verify item.

```yaml
review:
  scope: git diff main...HEAD (base main, head ff8a6311, branch chore/docs-audit-content-engine-split)
  spec: docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md (frozen + Amendment 1)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-2301 test_2301_split_note_inventory (tests/skills/test-aai-docs-audit.sh); note docs/analysis/docs-audit-content-engine-split.md; Content ratio 0.28" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-2302 test-aai-suite-select.sh; TEST-2303 test-aai-lightweight-lane.sh:323-326; suite-map.yaml aai-docs-content row" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-2304 rc=0 re-run by reviewer (clone exits 1 with Orphans >= 1); A1-c wording deviation" }
      - { ac: Spec-AC-04, call: non-compliant, citation: "named gap: .aai/scripts/check-state.mjs (read by engine case test_change0012_allocation_durability) and .aai/scripts/select-suites.mjs (read by engine case test_2211_migration_map_owners) select neither aai-docs-audit nor FULL_RUN; TEST-2306 misses the cd \"$PROJECT_ROOT\" && node .aai/... relative form" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-2307 rc=0 re-run; content suite rc=0 re-run; .aai/ untouched in diff" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-2308 rc=0 re-run; TEST-2309; tests/skills/lib/docs-audit-gate.test.mjs G1-G5 keep each removed clause" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-2310 passed inside the reviewer's content suite run; RFC-0017 rows 2 and 4" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-2311 (suite-select rc=0 re-run); TEST-2312 test-aai-delta-stage3.sh test_007 + companion in suite-map.yaml" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8948,
          issue: "TEST-2306 extracts only $PROJECT_ROOT/<path> tokens, so real-tree reads written as (cd \"$PROJECT_ROOT\" && node .aai/scripts/X) are invisible to it, yet its PASS line says every literal real-tree path read by an engine case selects the engine suite. Two such reads are under-selected today.",
          failure_scenario: "A PR that changes only .aai/scripts/check-state.mjs (for example, check-state starts rejecting a spec_path that no longer exists) selects aai-check-state and the other core suites, but not aai-docs-audit. test_change0012_allocation_durability (the CHANGE-0012 seam test: slug-keyed STATE survives the allocator rename) would go red, but it is not run, so the PR shows green; main or nightly is the first run that sees it. The same applies to a select-suites.mjs change and TEST-2211." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/nested-suite-allowlist.tsv, line: 3,
          issue: "The header still says 'The allowlist only shrinks', while this change grows it from 3 rows to 4 (A1-i). The file now makes a claim its own history disproves.",
          failure_scenario: "A later reviewer or ratchet author trusts the header and refuses a legitimate fifth row, or treats a growth as unprecedented. The record is false as of this commit." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-docs-audit.sh, line: 8936,
          issue: "TEST-2306 never asserts that it scanned at least one function or path. If docs_audit_main_names returns nothing (main() format drift, or SUITE_FILE resolving to a different file), the loop body never runs and the test passes vacuously.",
          failure_scenario: "Someone reformats main() as a for-loop over an array. docs_audit_main_names yields an empty list, TEST-2306 passes with zero paths checked, and the input closure stops being guarded without any red." }
  cannot_verify:
    - { claim: "TEST-2304 and the content suite behave the same on the hosted Linux runner (git clone of the PR merge checkout, framework isolation, GNU tools) as they did locally on macOS", closes_with: "a hosted skill-suite run of this branch with aai-docs-audit selected (green), plus the content suite leg green" }
    - { claim: "Timing claims (Content ratio 0.28, Gate ratio 0.07, the 40.7 s and 144.8 s medians) reflect hosted CI savings", closes_with: "hosted durations of aai-docs-content after a weights reseed; the note itself reports these as local only" }
    - { claim: "Non-literal or helper-function real-tree reads by engine cases are covered (the spec names these as a residual risk)", closes_with: "a widened TEST-2306 that also scans helper functions engine cases call, or a corpus sweep with real reads instrumented" }
    - { claim: "Owner acceptance of Amendment 1 (additive-with-disclosure, no sign-off obtained), in particular the A1-i ratchet growth", closes_with: "owner decision recorded at merge" }
  overall: fail
```

# Code review: docs-audit-content-engine-split, round 1

security_relevant: false

- Scope: `git diff main...HEAD` in the worktree /Users/ales/Projects/aai-wt-docs-audit-split (21 files). STATE `worktree.user_decision: worktree`, base `main`. The only working-tree change is a pre-existing `M docs/ai/EVENTS.jsonl` that is not part of the review; my runs left its bytes unchanged.
- Spec: docs/specs/SPEC-0260-spec-docs-audit-content-engine-split.md (frozen, plus Amendment 1 A1-a to A1-j).
- Dispatch note (anti-gaming contract): the dispatch named focus areas and passed on the validator's findings F1 to F5. I recorded this, reviewed the full scope anyway, and reached my own findings independently. My finding F1 below overlaps with the validator's F1. The rest come from this review.

## AC table walk

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | TEST-2301 parses the note against the baseline main list from `git show c3e706e7`; the CI checkout uses `fetch-depth: 0`, so the commit is present. |
| Spec-AC-02 | compliant | TEST-2302 (selector over the real map, doc paths plus INDEX) and TEST-2303 (close diff: CORE aai-docs-content, no aai-docs-audit line). Suite-select rc=0, re-run by me. |
| Spec-AC-03 | compliant | I re-ran TEST-2304: rc=0, meaning the clone's content suite exits 1 with `FAIL:` and `Orphans: [1-9]`. The clone sets its own user identity, `rc` is captured with `|| rc=$?`, and every `cd` is inside a subshell. A1-c deviation (FAIL line plus Orphans on continuation lines) is disclosed. |
| Spec-AC-04 | **non-compliant** | The AC requires that "every literal real-tree path an engine case reads SHALL print SELECTED aai-docs-audit or FULL_RUN". Two literal paths fail this (see F-B1). |
| Spec-AC-05 | compliant | I re-ran TEST-2307: rc=0 (195 = engine + 24 content + 5 Node, `check-test-registration.mjs` exits 0). I re-ran the content suite: rc=0. The diff touches nothing under `.aai/`. |
| Spec-AC-06 | compliant | I re-ran TEST-2308: rc=0. The Node cases G1 to G5 keep every clause of the removed Bash functions; the exit codes stay with the retained CLI owners. TEST-2309 checks the Gate ratio. |
| Spec-AC-07 | compliant | TEST-2310 passed inside the content suite run. The RFC diff marks row 2 done with the intake and note links, and row 4 links CHANGE-0228. |
| Spec-AC-08 | compliant | TEST-2311: core list, one weights row, product doc line. TEST-2312: delta-stage3 companion `aai-docs-audit`. |

Deviations from the frozen text, all disclosed in Amendment 1: 24 content names instead of 23 (A1-a), setup registered in both suites (A1-b), TEST-2304 wording (A1-c), TEST-2306 exclusions (A1-d), extra globs including INDEX/EVENTS on the content row (A1-e), rewritten mutation cells (A1-f), TEST-2310 selector location (A1-g), engine median not lower than the old suite (A1-h), allowlist growth 3 to 4 (A1-i), and the check-test-registration glob (A1-j). Also, `test-aai-delta-stage3.sh` is listed as "Not touched" in the spec but its TEST-007 failure message changed (validator F5). That change only edits a message and does not affect selection.

## Findings

### F-B1 (BLOCKING): the input-closure guard misses relative-form reads, and two engine inputs are under-selected

- File: tests/skills/test-aai-docs-audit.sh, `test_2306_engine_input_closure` (the line `paths="$(grep -oE "${root_re}/..."`). The regex only matches `$PROJECT_ROOT/<path>`.
- Engine cases read other real-tree files in the form `(cd "$PROJECT_ROOT" && node .aai/scripts/<x>)`. I scanned every engine-registered function body for that form and ran each path through the real selector:
  - `HOLE test_change0012_allocation_durability .aai/scripts/check-state.mjs` (lines 4522 and 4539). The selector prints only CORE lines plus `SELECTED aai-prompt-diet`, with no aai-docs-audit.
  - `HOLE test_2211_migration_map_owners .aai/scripts/select-suites.mjs` (line 8635). It selects suite-select, harness-shims, lightweight-lane and ci-carry-forward, but not aai-docs-audit.
  - The other relative reads are fine: state.mjs goes to FULL_RUN (protected-l3), and docs-audit-body/closeout test.mjs select aai-docs-audit.
- TEST-2306 passes today (rc=0, re-run by me) even though both holes exist, so the green result does not show what the AC says. A1-j already demonstrates the blind spot: `check-test-registration.mjs` only became visible after TEST-2307 switched to the absolute path.
- Failure scenario: a PR that changes only check-state.mjs runs no docs-audit engine case. The CHANGE-0012 seam test (slug-keyed STATE must validate unchanged after the allocator rename) can break without the PR going red.
- Fix (remediate in tree):
  1. Add `.aai/scripts/check-state.mjs` and `.aai/scripts/select-suites.mjs` to the `aai-docs-audit` globs. Over-selection is the map's stated preference.
  2. Widen TEST-2306 to also extract `(\.aai|tests|docs|\.claude)/...` tokens from body lines that `cd` into `$PROJECT_ROOT`, and the quoted `"$PROJECT_ROOT"/...` form.
  3. Add a mutation record showing the widened row bites when one of the new globs is removed.

### F-N1 (NON-BLOCKING): the allowlist header contradicts the change

- File: tests/skills/lib/nested-suite-allowlist.tsv:3. The header still says "The allowlist only shrinks", but the file grows 3 to 4 rows.
- Recommended disposition: (b) promote to a follow-up `fu-nested-allowlist-shrink-claim` (P3), or remediate in tree by rewording the header to name the A1-i exception. Either way, the owner decides between narrowing TEST-2304 and keeping the row (A1-i).

### F-N2 (NON-BLOCKING): TEST-2306 can pass vacuously

- File: tests/skills/test-aai-docs-audit.sh, `test_2306_engine_input_closure`. Nothing asserts that the number of scanned functions or paths is greater than 0.
- Recommended disposition: remediate in tree together with F-B1 (one line, for example a floor such as "scanned >= 150 functions and >= 10 paths"). Otherwise (d) accepted residual (P3 assurance strength; the mutation record shows it bites today).

### Checked and clean

- `set -euo pipefail` hazards in the new code: no bare `rc=$?`, and every `rc` is captured with `|| rc=$?`. There is no `printf | grep -q`; matching uses here-strings or `case`. `grep -c` and `uniq -d` are guarded with `|| true`. The only `grep | qhead | cut` sits inside a failure message, after a FAIL line was already proven present.
- Unanchored greps: TEST-2310 frontmatter uses `-qxF`; TEST-2308 counts use `^fn() {` and `-cx`.
- Fixture git identity is set in the TEST-2304 clone, `setup_iso_repo` and `setup_fixture`.
- No new leaked `cd`. The content suite's `setup_fixture` cd is the pre-existing design, and the `cleanup` EXIT trap at top level of the definition file is armed when the file is sourced, so the INDEX restore floor applies to the content suite.
- Document-only PR in CI: `aai-docs-content` is core and resolves via `test-framework.sh` as `test-aai-docs-content.sh`. CI checkouts use `fetch-depth: 0`. TEST-2304 proves that the suite's own list fails on a planted orphan, and the `Orphans: [1-9]` grep ties the failure to the plant, because the clean tree reports 0.

## Runs by the reviewer (worktree, `env -u AAI_ROLE`, through aai-run-tests.sh)

- `bash tests/skills/test-aai-docs-content.sh`: rc 0, `PASS: All aai-docs-content tests passed`
- `test-aai-docs-audit.sh test_2306_engine_input_closure`: rc 0. It passes despite F-B1, which is the point of the finding.
- `test_2307_case_inventory_partition`, `test_2308_gate_node`, `test_2304_content_suite_fails_on_planted_orphan`: each rc 0
- `bash tests/skills/test-aai-suite-select.sh`: rc 0
- Selector probes for the two holes: the outputs quoted under F-B1.

## Next steps

1. Remediation round for F-B1: two globs, widened TEST-2306, plus a mutation record. Fold F-N2 into the same round.
2. Record dispositions for F-N1 and F-N2 (orchestrator).
3. Re-review (the delta touches only tests and the map).

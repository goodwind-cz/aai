# Code Review r2: release-one-shot-finish

Target path: docs/ai/reviews/review-20261017T234610Z-r2-release-one-shot-finish.md

```yaml
review:
  scope: git diff 056ffd52..513a9369 (branch fix/release-one-shot-finish, PR #477, HEAD 513a9369 verified); paths .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/specs/SPEC-0236-spec-release-one-shot-finish.md docs/ai/decisions.jsonl
  spec: docs/specs/SPEC-0236-spec-release-one-shot-finish.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched in r2; r1 PASS (review-20261017T225414Z) stands; TEST-074 unchanged" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:375,379,409 (rulesets read paginated + flattened); TEST-086 (test-aai-release.sh:1838-1845) + TEST-075; mutation-TEST-086 RED, target_sha256 707e3eae matches HEAD blob" }
      - { ac: Spec-AC-03, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "release-finish.mjs:376 unchanged unreadable branch now also catches old-gh --slurp rejection; TEST-086 rules-no-slurp arm asserts the UNREADABLE rulesets line" }
      - { ac: Spec-AC-06, call: compliant, citation: "release-finish.mjs:379 non-array page keeps the Unexpected shape refusal; TEST-079 rules-bad-shape now answered slurp-wrapped (test-aai-release.sh:1449)" }
      - { ac: Spec-AC-07, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "untouched in r2; r1 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "untouched in r2 (see NB-2 on product doc not naming gh 2.48)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-086 matches ownSelector /^TEST-0[6-8][0-9]$/; wrapper test_730_ruleset_pages_read defined (:2194) and called from main (:2376)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1450,
          issue: "TEST-086 never crosses a page boundary at the engine's real page size. The fixture has 35 filler rules + 1 required_status_checks rule = 36 items; with per_page=100 the stub returns one page [[36 items]]. The 'page 2' comment (:1839) and the spec TEST-086 row ('puts the required_status_checks rule on page 2') are true only at the default 30. The multi-page flatten (data.flat() over >1 page) is never exercised.",
          failure_scenario: "A mutant that reads only the first page of the slurped answer (e.g. data=data[0]) keeps TEST-086 green, yet drops a required_status_checks rule past rule 100 in a real repo, merging early (outcome still the safe PENDING merge-policy). Fix: filler length >= 100 (e.g. 105) so the rule lands on page 2 at per_page=100. Disposition: remediate-in-tree (one number + spec row wording already matches)." }
      - { rank: NON-BLOCKING, file: docs/product/release-command-finish.md, line: 50,
          issue: "The product doc (and SKILL_RELEASE) do not say the rulesets read is paginated or that gh >= 2.48 is needed for it. On older gh the rulesets source is now ALWAYS unreadable, where before it read page 1.",
          failure_scenario: "A downstream operator on gh 2.4x (<2.48) sees '- Required contexts: UNREADABLE rulesets (unknown flag: --slurp)' on every release with no documented remedy; repos whose only required contexts come from rulesets lose the pre-merge wait they had on page 1 (outcome still safe via PENDING merge-policy). Disposition: remediate-in-tree (one clause in the product doc's Required contexts bullet) or promote-to-follow-up." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1443,
          issue: "Stub strictness 'unslurped pagination is not parsed by the engine' is a fixture guard, not real gh behavior: real gh --paginate without --slurp on an array endpoint exits 0 and prints merged/concatenated pages. The stub's 'slurp without paginate' die (:1441) DOES match real gh ('`--paginate` required when passing `--slurp`', probed on gh 2.93.0).",
          failure_scenario: "None for correctness today (the guard only makes a regression louder). Info: the mutation sed:s/'--paginate',// is killed via the stub's real-gh-faithful slurp-without-paginate rejection, so the kill is legitimate." }
  cannot_verify:
    - { claim: "gh 2.48 is the first version with --slurp, and older gh rejects it with a non-zero exit (cobra 'unknown flag'), never ignoring it",
        closes_with: "gh release notes for v2.48.0, or a run of an older gh binary; the precedent .aai/scripts/lib/platform-adapter.mjs:180 already uses --paginate --slurp" }
    - { claim: "Live multi-page rules/branches answer with a required_status_checks rule past page 1 (only empty and one-rule answers were probed: goodwind-cz/aai main -> [[]], cli/cli trunk -> [[{copilot_code_review}]], octocat/Hello-World -> [[]])",
        closes_with: "A live probe on a repo with > per_page rules, or with per_page=1 on a repo with >= 2 rules" }
    - { claim: "r1 cannot_verify items (evaluate-mode rulesets, gh blockedReason text, admin bypass, app-pinned name collision) remain open and are unaffected by r2",
        closes_with: "as listed in review-20261017T225414Z-release-one-shot-finish.md" }
  overall: pass
```

## Scope and preflight

- Verified HEAD 513a9369 on fix/release-one-shot-finish; `git status --porcelain` empty before and after. Commits in range: 10aafc79 (fix), 513a9369 (follow-up close).
- Read-only: no suites run (validator runs them concurrently). Only read-only commands: `git diff/log/cat-file`, `shasum`, `spec-amend.mjs list --strict` (rc 0, output to scratch), and live `gh api` GET probes from /private/tmp.
- Dispatch check: the dispatch listed areas to check (flatten, empty pages, query joining, --slurp shape, degrade, stub fidelity, amendment accuracy, test quality). It did not pre-rate severity or exclude any area; no coaching recorded. Full r2 scope reviewed.

## Correctness checks (release-finish.mjs:374-382, 409)

- --slurp shape: real gh answers one array of page arrays (probed: `[[]]` for an empty list, `[[{...}]]` for one rule). Line 379 requires an array of arrays and flattens with `.flat()` (depth 1, so rule objects are kept intact). Correct.
- Empty pages: `[[]]` flattens to `[]`; rulesetContexts then yields no contexts. Correct; the stub reproduces `[[]]` via the `!pages.length` loop guard (:1442).
- Query joining: the endpoint is built at :409 from `repos/${record.repo}/rules/branches/${encodeURIComponent(record.base)}` and carries no query string, so `?per_page=100` is the only query. `encodeURIComponent` escapes any `?`/`&` in the branch name. Correct. The Invalid JSON/shape refusals name the endpoint without the query; harmless.
- Error mid-pagination (e.g. rate limit on page 2): gh exits non-zero -> unreadable line, not a partial read. Correct.
- Classic protection stays a single unpaginated `['api',endpoint]` call; stub enforces exactly 2 args for it (:1441).

## Degrade semantics (old gh)

- With gh < 2.48 the flag is rejected, the call exits non-zero, and line 376 prints `UNREADABLE rulesets (<first stderr line>)`. There is no fallback/retry to an unpaginated call, so a silent first-page read is now impossible: either gh follows every Link page, or the source is named unreadable. TEST-086's rules-no-slurp arm pins the named line (a reintroduced silent fallback would print no line and fail the assert).
- Trade-off (NB-2): old gh loses page-1 coverage it had before; the outcome remains safe (PENDING merge-policy) per D2.

## Amendment accuracy (spec D9 + TEST-086 row, decisions.jsonl)

- Diff to the spec is additive: frozen_sha256 restamp, D9 line, TEST-086 row. No AC, decision or test row altered; matches the 23:35:20Z spec_amendment `what`.
- `spec-amend list --strict` rc 0; both unsigned contract amendments are tracked by the open fu-amend-spec-release-one-shot-finish (owner sign-off owed, expected).
- D9 matches the code (paginate, slurp, per_page=100, flatten, shape refusal, old-gh UNREADABLE, classic unpaginated). D9's "never a silent first-page read" is accurate.
- Inaccuracy (NB-1): the TEST-086 row's "page 2" holds only at the default 30, not at the engine's per_page=100.
- Minor: the "Mutation targets" sentence (spec :149) still says "TEST-074 to TEST-083" and does not mention TEST-086; the mutation record targets release-finish.mjs, so the gate works, but the sentence is stale. Fold into NB-1 remediation if the spec is touched again.
- follow_up_status fu-release-rulesets-unpaginated done, source 10aafc79 (exists, ancestor of HEAD). Correct.

## Test evidence

- mutation-TEST-086.txt: mutation `sed:s/'--paginate',//` (one occurrence in the target), verdict RED, target_sha256 707e3eae... equals the HEAD blob of release-finish.mjs. The mutant answer was `UNREADABLE rulesets (... bad api flags ["api","--slurp",...])` then early merge -> exit 8 vs expected 0.
- TEST-086 asserts every rules read carries --paginate, --slurp and ends with per_page=100, plus merge after the late-suite pass read.

## Warning dispositions (H6)

- NB-1 (TEST-086 doesn't cross a page at per_page=100): remediate-in-tree recommended (cheap; also fixes the "page 2" wording drift).
- NB-2 (product doc lacks paginated read / gh 2.48 note): remediate-in-tree or promote-to-follow-up; orchestrator's call.
- NB-3 (stub guard not real gh): INFO, no action.

## Next steps

Overall PASS. Orchestrator records NB dispositions; owner sign-off on fu-amend-spec-release-one-shot-finish still owed.

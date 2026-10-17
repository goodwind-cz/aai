# Code Review r2 — release-changelog-eol

```yaml
review:
  scope: "git diff 068c77c1..2306a2e5 (branch fix/release-changelog-eol, commit 2306a2e5): .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/specs/SPEC-0235-spec-release-changelog-eol.md docs/ai/decisions.jsonl docs/ai/tests/test-runs.jsonl docs/ai/reviews/review-20261017T194555Z-release-changelog-eol.md"
  spec: docs/specs/SPEC-0235-spec-release-changelog-eol.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unchanged since r1 (pass); release-finish.mjs:110 adds a no-op for BOM-less input; TEST-067 unchanged" }
      - { ac: Spec-AC-02, call: compliant, citation: "release-finish.mjs:110,126 strip one leading U+FEFF and put it back; TEST-068 original arm unchanged plus a new BOM-before-first-heading arm (test-aai-release.sh:1751-1754)" }
      - { ac: Spec-AC-03, call: compliant, citation: "cr comes from lines[first] after the BOM strip; scratch harness: BOM+CRLF with and without a final CRLF round-trip; TEST-069 unchanged" }
      - { ac: Spec-AC-04, call: compliant, citation: "unchanged; TEST-070" }
      - { ac: Spec-AC-05, call: compliant, citation: "the identity check (release-finish.mjs:397) calls the same rollup(), so the journal and the re-derivation stay symmetric; TEST-071" }
      - { ac: Spec-AC-06, call: compliant, citation: "test_716 (test-aai-release.sh:2003) now shows fixture failures; TEST-072" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 2003,
          issue: "`return 0` after log_fail can never run, because log_fail (line 84) does `exit 1`; with 2>&1, stderr lines also go into the T072REPO parse loop",
          failure_scenario: "None today: log_fail exits first, and no stderr line starts with 'T072REPO '. A later change to a non-exiting log_fail would make `return 0` hide the failure only together with a matching log_fail call, which it already has. INFO-grade." }
  cannot_verify:
    - { claim: "Live GitHub release workflow publishes correctly from a BOM-prefixed rolled CHANGELOG", closes_with: "first live /aai-release --confirm after merge (spec's named residual)" }
    - { claim: "The r2 suite runs (test-runs.jsonl 2026-10-17T20:01:00Z shows 14/15 pass, 1 fail, which comes before the spec reorder that fixes TEST-029)", closes_with: "the concurrent validator's re-run of aai-release + aai-follow-ups selectors on 2306a2e5" }
  overall: pass
```

## Scope and method
Reviewed `git diff 068c77c1..2306a2e5` (one commit, 2306a2e5) in /Users/ales/Projects/aai-fix-release-changelog-eol, which addresses r1's NB-1 (BOM before the first entry heading) and the test_716 visibility note, and fixes a Validation FAIL (aai-follow-ups TEST-029). Suites were not run, because a validator is running concurrently. Everything was checked in scratch copies.

## Evidence
- **rollup() BOM handling** (release-finish.mjs:110,126): I pulled the function into a scratch harness and ran these cases:
  - BOM + title line: BOM kept once. The bytes match the pre-fix engine, which kept the BOM inside lines[0].
  - BOM + `## [unreleased] — …` as the first line (LF, CRLF, no final newline, BOM+CRLF+no final CRLF): each rolls the entry, emits exactly one BOM at offset 0, keeps the BOM out of the notes, and preserves the EOL and EOF state.
  - Empty file, BOM only, BOM+`\n`: `empty-notes` refusal, fail-closed.
  - Double BOM and a BOM in the middle of the file: only a BOM at index 0 is stripped. The second or middle BOM stays in its line, and the heading regex then misses it, so the result is an `empty-notes` refusal (fail-closed, never mis-rolled).
  - BOM-less input: output unchanged.
- **Resume symmetry:** the journal content (line 403) and the re-derivation (line 397) both go through rollup(), so the BOM handling cannot cause a false `identity` refusal.
- **TEST-068 new arm:** if the BOM strip is removed, rollup refuses `empty-notes`. stopAt then fails on its `/interrupted/` match, so the arm is RED without the fix and acts as a real guard. The `'﻿'` escape removes an invisible literal and does not change behaviour.
- **test_716** (line 2003): test_700 is a single node process, so its exit status is node's and errexit does not matter inside it. On failure, the captured stdout+stderr (including `FAIL: TEST-072 …`) is now printed before log_fail. This addresses r1's note.
- **Spec amendment matches the text:** the spec diff swaps two paragraphs and changes nothing else. I recomputed `contractHash` with .aai/scripts/lib/spec-contract-hash.mjs:
  - base: 8c1f0afc… (old stamp)
  - head: 059b0293… (new stamp)

  Both match their stamps. I ran `follow-ups verify-closures --path` (read-only) on scratch copies: base gives claims=3 miss=3 (the three left-open fu- ids), head gives claims=0. This confirms what the amendment's what/why says. It is filed with `owner_signoff:false` and tracked by `fu-amend-spec-release-changelog-eol`, under the additive-with-disclosure convention. `amendment_class: contract` fits, because the projected contract hash changed even though the edit is editorial.
- **Follow-up `fu-verify-closures-none-blank-line`:** the id is 34 chars, P3, and has a source. The root cause matches follow-ups.mjs:991-1019: when there is no id before the blank line, the segment jumps to the following bulleted block, and the `none` sentinel check then sees the later paragraph.
- **Gitignored artifacts:** `git ls-files -ci --exclude-standard` returns nothing.

## Warning dispositions (H6)
- NB-1 (test_716 line 2003, `return 0` can never run): recommended disposition (d). Accepted residual: INFO-grade maintenance nit with no failure path and no false record.

## Next steps
Return to the validator. TEST-029 (aai-follow-ups) and the aai-release selectors 711-716 must pass on 2306a2e5. The owner sign-off on the amendment is still owed (fu-amend-spec-release-changelog-eol).

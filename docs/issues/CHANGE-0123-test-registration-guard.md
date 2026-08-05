---
id: test-registration-guard
number: 123
type: change
status: done
user_visible: true
ceremony_level: 1
links:
  pr:
    - 230
  commits:
    - 8f1b22c2ba729e4928b1adfb7f395d57def458cb
---

# Change — tests that lie get caught: registration guard, corpus-sweep rule, honest test names

## Summary
- Owner retrospective on the CHANGE-0120 saga ("you write tests that are
  wrong?"): yes — three concrete shapes shipped green suites around real
  defects, all rooted in the same cause (the model that writes the code
  writes the tests, with correlated blind spots):
  (1) a regression pin DEFINED but never wired into main() — green suite,
  zero coverage; (2) fixtures idealized vs the real corpus (30 nested + 24
  backticked + 3 no-H1 specs no fixture had); (3) a test NAMED for a
  universal negative while asserting only refusal paths.
- Three measures, one per shape:
  1. check-test-registration.mjs + hygiene test_093: every defined test_*
     function in every suite must be invoked (bare-name occurrence beyond
     definition, or the dynamic `"test_${t}"`/ALL_TESTS idiom). GREEN on
     the real tree (0 violations across 60+ suites after verifying the 3
     dynamic-idiom suites parse correctly); RED-proven on an orphan
     fixture.
  2. VALIDATION corpus-sweep rule: parsers of repo-corpus files must be
     validated across ALL real instances, not fixtures only (the practice
     that actually caught the 0120 defects, now contract).
  3. Review pin: universal-negative test names are BLOCKING unless proven
     (corpus sweep/mutation) — rename or prove.
- LEARNED.md records the class (vendored downstream). +492 B prompt bytes
  ledger-credited.
- Honest boundary: measure 4 for the root cause (correlated blind spots) is
  ARCHITECTURE, not a rule — the L2 independent-validation pipeline and the
  bot sweep remain the only reliable defense; these measures make it
  cheaper, not replaceable.

## Acceptance Criteria
- AC-001: test_093 fails on a fixture suite with an orphan test function
  (RED-proven) and passes the real tree.
- AC-002: dynamic-idiom suites (ALL_TESTS) are not false-flagged.
- AC-003: VALIDATION + CODE_REVIEW pins present; ledger credited; headroom
  in budget.

## Verification
- check-test-registration GREEN/RED runs recorded; hygiene-pack, layer-
  profiles, prompt-diet, release TEST-022 green; docs-audit strict CLEAN.

## Constraints / Risks
- Ceremony L1, strategy direct. The guard reads test invocation statically;
  a suite invoking tests via an idiom it doesn't know would false-flag —
  loudly (named orphans), fixed by teaching the guard the idiom.

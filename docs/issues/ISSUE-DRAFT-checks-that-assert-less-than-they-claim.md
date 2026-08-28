---
id: checks-that-assert-less-than-they-claim
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Arms that read a weaker signal than the claim they print, and a close ceremony whose order is only a habit

## Summary
- Five registry items from the `deslop-corpus-honesty` ride. Three are one mechanism: an
  assertion reads something weaker than the sentence it prints, so it is green while the
  claim is false. The other two are a second mechanism: the PR close ceremony has a
  required ORDER that nothing enforces and a tool whose required argument does not exist
  yet at the moment that order demands it be run.

## Type
- bug

## Impact
- Affected: `tests/skills/test-aai-deslop.sh`, `tests/skills/test-aai-doc-numbering.sh`,
  every new test or script that pins a git ref, and every PR ceremony.
- The registry entry for one of these says the weak-signal defect is "the recurring defect
  class this repo has now hit eight times".

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-test028-exitcode-not-clean` (P2). Measured: `tests/skills/test-aai-deslop.sh:2186`
  asserts docs-audit cleanliness with
  `if ! node "$PROJECT_ROOT/.aai/scripts/docs-audit.mjs" --check --strict --no-event >/dev/null 2>&1;`
  — the EXIT CODE. But `docs-audit.mjs:610` prints
  `### Verdict: CLEAN` or `NEEDS-TRIAGE (n items)` and
  `.aai/scripts/lib/docs-audit-core.mjs:1431` records that the NEEDS-TRIAGE tally is
  "report-only, preserving the RFC-0002 report-not-block" behaviour, so the audit exits 0
  at NEEDS-TRIAGE. The pass line at `:2195` nevertheless states "docs-audit and spec-lint
  are clean". The sibling arm gets it right:
  `tests/skills/test-aai-doc-numbering.sh:667` does
  `assert_contains "$TEST_DIR/repo-audit.log" "CLEAN"`. Measured live at filing time: the
  deslop arm was green while doc-numbering TEST-013 was red on the same tree.
- `fu-docnumbering-logfail-aborts-suite` (P2). `tests/skills/test-aai-doc-numbering.sh:41`
  defines `log_fail() { echo "FAIL: $*" >&2; exit 1; }`, so the FIRST failed assertion
  aborts the whole suite and every later arm silently never runs. Measured 2026-08-19:
  while docs-audit is NEEDS-TRIAGE the suite aborts at TEST-013 and TEST-014 onward never
  execute, so a suite that appears to cover doc numbering reports on almost nothing — and
  its own coverage loss is invisible in the output.
- `fu-bare-main-baseref-sweep` (P2). No guard stops a NEW test or script from pinning a
  bare `main` ref that silently never resolves on a `pull_request` checkout. Fourth
  occurrence of this exact class in the repository at filing time (TEST-024, the follow-ups
  suite, `test-aai-spec-lint.sh`, then `test-aai-deslop.sh` TEST-027/028); each time it was
  found by review or validation, not by a check, and each time the affected guard degraded
  to PASS or to a false reason on CI. Measured today: `merge-base` appears in four suites
  (`test-aai-close-work-item.sh`, `test-aai-hooks-overlay.sh`, `test-aai-release.sh`,
  `test-aai-routine.sh`), and a `/usr/bin/grep` for git commands against a literal `main`
  across `tests/skills/*.sh` returns 18 lines. The repo-wide sweep was explicitly out of
  the filing scope.
- `fu-close-before-push-ordering` (P2). Running `close-work-item.mjs` BEFORE the push is
  currently only a habit; nothing enforces it, so a ride can push first and then spend a
  round chasing framework reds that the close would have cleared. Validation round 4 of
  that scope proved empirically that the five `tests/skills/test-framework.sh` reds are
  ride-caused and clear only once the close has run.
- `fu-close-requires-pr-before-it-exists` (P2). Measured at
  `.aai/scripts/close-work-item.mjs:172`:
  `if (!args.pr || !/^\d+$/.test(String(args.pr))) usageError('missing or invalid --pr (integer required)')`.
  The correct ceremony order runs the tool BEFORE the push that creates the PR, so the
  number must be GUESSED. On 2026-08-19 the guess 265 happened to be right, which is luck,
  not procedure. The ordering is not optional: `fu-close-before-push-ordering` proves the
  framework reds only clear post-close, and `fu-close-after-merge-bypasses-ci` proves
  running it after merge bypasses required checks. The tool therefore forces either a guess
  or a wrong order.

Where the members disagree: the first three are assertion strength; the last two are
ceremony sequencing and a CLI contract. They share a ride, not a fix.

## Expected Behavior
- An arm that prints "clean" asserts the token that means clean, not an exit code that is
  0 either way.
- A failed assertion fails its arm; the suite continues and reports every arm's verdict.
- A new git-ref pin either resolves on a `pull_request` checkout or fails loudly.
- The close-before-push order is a precondition the ceremony checks, not prose.
- `close-work-item.mjs` can run at the moment the order requires, without a guessed PR
  number.

## Steps to Reproduce (if applicable)
1) Put the repository into a NEEDS-TRIAGE docs-audit state (an untracked draft doc is
   enough) and run `tests/skills/test-aai-deslop.sh`: TEST-028 is green while
   `tests/skills/test-aai-doc-numbering.sh` TEST-013 is red.
2) Make any early arm in `test-aai-doc-numbering.sh` fail and observe the suite exit before
   the later arms run.
3) Run the close ceremony after a push and count the framework reds that clear once the
   close runs.

## Verification
- The deslop arm greps for the `CLEAN` token and reddens on NEEDS-TRIAGE.
- `test-aai-doc-numbering.sh` reports every arm's verdict after an early failure.
- A planted bare-`main` ref in a new suite is caught by a check rather than by a reviewer.
- The close ceremony refuses to run out of order, and does not require a number that does
  not exist yet.

## Constraints / Risks
- `.aai/scripts/close-work-item.mjs` is content-hash pinned; any edit moves the hash and
  forces an allowlist re-pin plus re-proof of `test-aai-follow-ups` TEST-008 and
  `test-aai-doc-numbering` TEST-029. Batch it with the other deferred edits to that file.
- Converting `log_fail` from `exit 1` to a per-arm failure changes the suite's exit
  semantics and every caller that reads them.

## Notes
- OUT OF SCOPE: the vacuous-guard class (a guard green because its comparison is degenerate
  on the taken path), filed separately. That is about a guard that CANNOT fail; this is
  about a guard that reads the wrong thing.
- Registry ids covered: `fu-test028-exitcode-not-clean`,
  `fu-docnumbering-logfail-aborts-suite`, `fu-bare-main-baseref-sweep`,
  `fu-close-before-push-ordering`, `fu-close-requires-pr-before-it-exists`.

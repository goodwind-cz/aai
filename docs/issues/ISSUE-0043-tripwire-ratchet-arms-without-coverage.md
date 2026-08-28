---
id: tripwire-ratchet-arms-without-coverage
type: issue
number: 43
status: draft
links:
  pr: []
  commits: []
---

# The drained offender table left an arm with no legal repair, a spec that contradicts its own code, and a green that proves nothing

## Summary
- The tripwire's known-offender ratchet was drained to zero entries. Four registry items
  record what the drain left: an arm coupled to a shipped count of exactly zero so a
  legitimate raise leaves it red with no legal one-line repair, a spec section still saying
  the opposite of the branch that shipped it, a "zero ALLOWED lines" claim that proves the
  branch was unreachable rather than that nothing was forgiven, and one coverage gap that
  measurement shows has since been closed.

## Type
- bug

## Impact
- Affected: `tests/skills/test-aai-repo-tripwire.sh`, `tests/skills/test-framework.sh`,
  `docs/specs/SPEC-0146-spec-drain-the-tripwire-known-offender-list.md`.
- The failure mode is the delete-the-arm temptation: an arm that goes UNCOVERED with no
  legal repair invites someone to remove it instead.

## Current Behavior
Verified in a disposable clone of `origin/main` (`c6b32d0`):

- `fu-test013-uncovered-on-legal-max-raise` (P2). Measured at
  `tests/skills/test-aai-repo-tripwire.sh:67` (`TRIPWIRE_RATCHET_MAX_ENTRIES=0`) and
  `:826-835`: TEST-013 fails with "the shipped table holds $shipped_count entr(ies), so
  this arm is not testing a drained table" whenever the count is non-zero. Mutation M3 at
  `7c5a09c` added one entry and set the maximum to 1: TEST-014 PASSED at 1 entry under
  maximum 1 while TEST-013 FAILED UNCOVERED, suite exit 1. TEST-014 survives a legitimate
  maximum raise; TEST-013 does not, and there is no legal one-line repair. What TEST-013
  actually needs is that the two fixture suite names are ABSENT from the table, not that
  the count is zero.
- `fu-drain-spec-says-d7-filed-not-fixed` (P3) is LIVE. Measured at
  `docs/specs/SPEC-0146-spec-drain-the-tripwire-known-offender-list.md:202-206`: the Edge
  cases section still says the D7 reopening is "in scope to NAME and out of scope to fix"
  and "This is filed, not fixed", while the same branch ships the `TRIPWIRE_ALWAYS_WATCH`
  floor that fixes it. The spec is the artifact a reader consults to learn whether the
  hashed path set derives from the table; leaving it stating the opposite of the code is
  exactly the drift docs-audit exists to catch, and Spec-AC-05's "nothing else about the
  tripwire changes" is no longer literally true either.
- `fu-drained-suites-still-write-unisolated` (P2). Measured 2026-08-23 in a disposable
  worktree at `7c5a09c` with `AAI_TEST_ISOLATION=0`:
  `bash tests/skills/test-framework.sh --skill aai-state` gave `FAIL [TRIPWIRE]` with
  ` M docs/INDEX.md` and a ratchet-path hash hit; `--skill aai-token-capture` gave
  `FAIL [TRIPWIRE]` with ` M docs/ai/overview-data.json` and ` M docs/ai/overview.html`;
  both at 0/1 attested clean. The four formerly exempt suites still write the shipping
  repository when isolation is off, so the drain's supporting claim — zero tripwire
  ALLOWED lines before the drain — proves the branch was UNREACHABLE, not that nothing was
  forgiven. Under disposable-checkout isolation no suite can dirty the shipping tree, so
  zero ALLOWED is structurally guaranteed for all 81 suites and has no discriminating
  power. The framework comment's "none of them writes to the shipping repository any more"
  and the commit message's "they were just there" overstate what was measured.
- `fu-tripwire-always-watch-floor-uncovered` (P2) measures as ALREADY FIXED on
  `origin/main`. It recorded that the `TRIPWIRE_ALWAYS_WATCH` floor had no gating arm and
  was silently revertible. Today `tests/skills/test-aai-repo-tripwire.sh:895-945` carries
  TEST-015, which asserts the floor is declared, names all three paths BY NAME
  (`docs/INDEX.md`, `docs/ai/overview.html`, `docs/ai/overview-data.json`), seeds the watch
  set, seeds the dedup set, and carries a vacuity guard. The registry entry is stale-open;
  it should be closed rather than planned.
- One adjacent gap the same file declares about itself, at
  `tests/skills/test-aai-repo-tripwire.sh:890-893`: "this pins 7 of the 68 grep sites in
  this file. The other 61 predate it and are unpinned. A half-pinned file advertises a
  guarantee it does not keep, which code review judged WORSE than a consistently unpinned
  one — filed rather than swept."

## Expected Behavior
- TEST-013 asserts the property it means (the two fixture suite names are absent from the
  table), so a legitimate maximum raise has a legal repair.
- The spec states what the branch shipped: the D7 reopening is fixed by the floor, not
  filed.
- Claims about what the drain proved are stated at the strength the measurement supports.

## Steps to Reproduce (if applicable)
1) Add one entry to `TRIPWIRE_KNOWN_OFFENDERS` and set
   `TRIPWIRE_RATCHET_MAX_ENTRIES=1` in a disposable copy; run
   `tests/skills/test-aai-repo-tripwire.sh`: TEST-014 passes, TEST-013 fails UNCOVERED,
   suite exit 1.
2) Read `SPEC-0146:202-206` against `tests/skills/test-framework.sh:135-191` and observe
   the contradiction.
3) With `AAI_TEST_ISOLATION=0`, run `tests/skills/test-framework.sh --skill aai-state` and
   observe `FAIL [TRIPWIRE]` with ` M docs/INDEX.md`.

## Verification
- A one-entry table with a matching maximum leaves both TEST-013 and TEST-014 green.
- `SPEC-0146` no longer says the D7 reopening is out of scope to fix.
- The framework comment and the CHANGELOG entry about the four formerly exempt suites say
  what was measured.
- `fu-tripwire-always-watch-floor-uncovered` is closed against TEST-015 rather than
  re-planned.

## Constraints / Risks
- The tripwire is permanent by `hitl_decision 2026-08-23T20:05:00Z`; these are repairs, not
  steps toward removal.
- Rewriting TEST-013's premise changes what a drained table means to the ratchet and must
  be proved in both directions (drained and one-entry).

## Notes
- OUT OF SCOPE: the tripwire's REPORTING defects (log tail, pre-dirty ALLOWED, per-suite
  degrade line) and the run-directory collision, filed with the
  `suites-must-not-touch-the-shipping-repo` residuals.
- Registry ids covered: `fu-test013-uncovered-on-legal-max-raise`,
  `fu-drain-spec-says-d7-filed-not-fixed`, `fu-drained-suites-still-write-unisolated`,
  `fu-tripwire-always-watch-floor-uncovered` (measured already fixed; close, do not plan).

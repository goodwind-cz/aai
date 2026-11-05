---
id: admit-tests-other-suites
type: issue
number: 109
status: done
links:
  pr: []
  commits: []
---

# TEST-3307 and TEST-3337 go red when only other manifest suites changed, and TEST-3341 lacks the escaping-path case

## Summary
- `tests/skills/test-aai-suite-reuse.sh` `test_3307_live_appended_probes` (TEST-3307) and `test_3337_split_admission` (TEST-3337) judge the live admission (`suite-reuse.mjs lint --admit --changed-since main`) and require at least one of THEIR OWN suites to be admitted whenever the admission is not ADMIT-NONE or ADMIT-OFF. On a branch that changes only another manifest suite (for example `tests/skills/test-aai-pricing.sh`) the admission lists only that suite, and both tests fail with "none of ... was admitted". Follow-up `fu-admit-tests-red-on-other-suites` (P3).
- SPEC-0271 Spec-AC-09 says `lint` rejects a `sources` path that escapes the repo root. `suite-reuse.mjs` does reject it (a path with a `..` segment, or an absolute path, yields `no-source-file <path>`), but no test covers it, and the comment on TEST-3341 claims one does. Follow-up `fu-sources-lint-escape-untested` (P3).

## Type
- bug

## Impact
- Internal test-only (tests/skills is not shipped downstream). Spurious red on any branch that touches a manifest suite other than the ones these two tests own; an untested lint rule. Severity P3.

## Current Behavior
- TEST-3307 and TEST-3337 exit 1 with "none of the ... suites was admitted" when the admission output holds only other suites.
- TEST-3341 exercises a missing path and a non-list value only; its comment says the escape is covered.

## Expected Behavior
- Each of the two tests judges only its own suites. When none of its suites appears in the admission output it passes with a "not admitted on this branch" line. For a suite that was admitted it keeps the ADMIT-FAIL rejection and the per-suite probe checks; standalone mode is kept.
- TEST-3341 covers a `../`-escaping sources path and a path that normalizes outside the root (`tests/../../x`); both must fail lint with exit 1.

## Steps to Reproduce (if applicable)
1) Branch from main, change only `tests/skills/test-aai-pricing.sh`, commit.
2) `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh test_3307_live_appended_probes` exits 1 (same for `test_3337_split_admission`).

## Verification
- `env -u AAI_ROLE bash tests/skills/test-aai-suite-reuse.sh` exit 0; the two tests pass on the reproduction branch; the new escape case fails against a copy of `suite-reuse.mjs` with the `..` check removed.

## Constraints / Risks
- Test-only; product code (`.aai/scripts/suite-reuse.mjs`) is not changed.

## Notes
- Assumption (autopilot): human_time_minutes null.

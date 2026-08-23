---
id: a-run-must-say-whether-isolation-armed
number: 156
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-suite-isolation
links:
  pr:
    - 273
  commits:
    - cf6120946f4c07c27fa7d1db25a9fd49e0dfe4d4
---

# Change — nothing counts a run in which isolation never armed

## Summary
- Suites run in a disposable git worktree (SPEC-0138) so a suite cannot write to
  the shipping repository. When that fails, the run continues **against the
  shipping repository** and says so in a single mid-scroll `log_warn`.
- Nothing counts it. No counter, no summary line, no run-ledger field. A
  1500-line CI log scrolls past three warnings and ends `Passed: 81 (100%)`.

## Evidence
Measured on `main` at `2d1d57c`:

- `ISOLATION_WHY` is set at `tests/skills/test-framework.sh:240,243,246`
  (`AAI_TEST_ISOLATION=0`, `git not found`, `PROJECT_ROOT is not a git
  checkout`) and surfaced exactly once, at `:886`, as a `log_warn`. It reaches
  no counter.
- Per-suite degrades are `log_warn` only: `:551`
  (`'<suite>' is not in the disposable checkout`) and `:557`
  (`no disposable checkout for '<suite>'`).
- The summary block (`:802-825`) has **no** isolation line. It does have the
  model to copy: `:825` prints
  `Tripwire: N/M suite(s) attested clean; K not attested`, driven by the
  `TRIPWIRE_UNATTESTED` counter.
- The run ledger append (`:867`) writes
  `{timestamp,type,run_id,total,passed,failed,skipped}` — no isolation field.
- `.aai/scripts/aai-run-tests.sh` has the matching `AAI-ISOLATION` NOTE on
  stderr, with the same problem.

## Impact
This is the **hard precondition for deleting the tripwire** (SPEC-0138 D8,
recorded as an `hitl_decision`). The tripwire is explicitly transitional: about
1140 lines and roughly thirteen registry items exist only to police writes that
isolation is supposed to make impossible.

While the tripwire is armed, a run where isolation silently never armed still
turns red on the first write. **Once the tripwire is deleted, that same run
stays GREEN and nothing in the output or the ledger says isolation was off.**
So the tripwire cannot be removed until a run is able to state its own
isolation status.

**CORRECTION (2026-08-23).** "The tripwire is explicitly transitional" and the
framing of this scope as a precondition for deleting it are both withdrawn. The
successor those rested on landed (SPEC-0138) and does not remove the cause:
inside a disposable worktree, `git rev-parse --git-common-dir` returns the
shipping repository's `.git` and its `dirname` is the shipping working tree, so
isolation relocates a suite without removing its reach
(`fu-isolated-suite-reaches-shipping-repo`, P1, open). The tripwire is
permanent; its deletion is not scheduled. What this scope delivered — a run
stating its own isolation status — stands on its own merit and is not affected.
The count in the paragraph above ("roughly thirteen registry items") is also
stale: sixteen open registry items carry `tripwire` in their id today, of which
exactly one (`fu-tripwire-removal-needs-a-gate`) closes on the permanence
decision and fifteen stay open as defects in a layer that now stays. Superseding
record: the `hitl_decision` at 2026-08-23T20:05:00Z in `docs/ai/decisions.jsonl`.

## Desired Behavior
A run says, in a place a reader and a machine can both find, how many suites ran
isolated and how many did not — whether or not anything went wrong.

## Acceptance Criteria
- AC-001: a per-run counter tracks suites that ran isolated and suites that
  degraded, incremented at **every** degrade path — the global probe failure and
  both per-suite paths. Prove each path increments it, by mutation, one at a
  time.
- AC-002: the summary block prints an isolation line **on every run**, including
  the all-clear. A line that appears only on failure is one a reader learns to
  expect the absence of. Model it on the existing tripwire line at `:825`.
- AC-003: the run-ledger record at `:867` carries the same two numbers. Prove a
  ledger line can be read back and the numbers matched to the summary line of
  the same `run_id`.
- AC-004: a fully degraded run is **visibly** different from a fully isolated
  one in all three places, with an exit code that is unchanged — this is
  reporting, not a new gate. State explicitly that it does not fail the run,
  and why that is the right call for now.
- AC-005: `aai-run-tests.sh` reports its own single-suite isolation status in
  the same vocabulary, so the two funnels cannot be read as disagreeing.

## Verification
- prove each of the three degrade paths increments the counter by mutation,
  with an unmutated control that shows the all-clear line
- force a global degrade with `AAI_TEST_ISOLATION=0` and read all three
  surfaces on the same run
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- `tests/skills/test-framework.sh` is the funnel for all 83 suites. A mistake
  here does not fail one suite, it fails or silently weakens every run.
- **The ledger append at `:867` is itself a known hole**: it writes to the
  TRACKED `docs/ai/tests/test-runs.jsonl` after the last suite's tripwire
  snapshot, so the tripwire is structurally blind to it
  (`fu-framework-appends-tracked-testruns`, P3, validation argued P2). Do NOT
  fix that here — but do not make it worse, and say in the spec that the field
  this scope adds rides on a write the tripwire cannot see.
- `docs/ai/tests/test-runs.jsonl` is append-only live data. Never rewrite it.
- Report-only. No exit code changes, no new gate. Nothing may start blocking
  because of this change.
- Do not delete the tripwire in this scope. This change makes deleting it
  *possible*; deleting it is a separate decision with its own evidence.
  *(2026-08-23: withdrawn — the tripwire is permanent; see the CORRECTION block in this document.)*
- The full framework run costs 20-28 minutes. Budget one, not several.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: `fu-isolation-arm-failure-uncounted` (P1).
- Unlocked but NOT in scope: deleting the tripwire (~1140 lines, ~13 registry
  items). That is the payoff and it needs its own ride.
  *(2026-08-23: withdrawn — the tripwire is permanent; see the CORRECTION block in this document.)* The ride ran, measured the reach, and stopped; exactly ONE registry item closed, not thirteen.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, reading an exit code after a pipe reports the
  pipe's last command, and in JavaScript `String.replace` a `$'` in the
  REPLACEMENT means "everything after the match" — all five have produced
  fabricated measurements or corrupted files in this repository this week.

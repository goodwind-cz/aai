---
id: a-half-seeded-checkout-says-it-is-isolated
number: 157
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-suite-isolation
links:
  pr:
    - 274
  commits:
    - 0645434f207509aa20e4d3c848ff145ffdc9dd24
---

# Change — a half-seeded disposable checkout still reports `isolated`

## Summary
- CHANGE-0156 made a run say whether isolation **armed**. It did not make a run
  say whether the disposable checkout was **completely built**.
- `iso_create` seeds a checkout in three steps. Two of them fail in total
  silence, and the run reports `isolated` on all three surfaces regardless.

## Evidence
Measured on `main` at `4988771`:

| step | site | on failure |
|---|---|---|
| replay the working-tree diff | `test-framework.sh:297-299` | one mid-scroll `log_warn` |
| copy untracked files | `test-framework.sh:301-305` | `cp -p … 2>/dev/null \|\| true` — silent |
| copy the seed paths | `test-framework.sh:306-311` | `cp -p … 2>/dev/null \|\| true` — silent |

The wrapper has the same shape at `.aai/scripts/aai-run-tests.sh:377` and `:384`.

`ISOLATION_SEED_PATHS` defaults to `docs/ai/STATE.yaml`,
`docs/ai/LOOP_TICKS.jsonl`, `docs/ai/hitl-channel.json` — the state a suite
reads to decide what it is looking at.

This is `fu-isolation-arm-failure-uncounted` (P1, closed by CHANGE-0156) **one
axis over**: the same "nothing counts it" defect, moved from *did isolation
arm* to *was the isolated tree completely built*.

## Impact
- A suite runs against an incomplete tree and either reds for a reason that has
  nothing to do with it, or — worse — passes because the file whose absence it
  should have caught was never copied in.
- It is a **second input to deleting the tripwire**, alongside
  `fu-tripwire-removal-needs-a-gate` (P2). Once the tripwire is gone, a silently
  half-seeded run is green and says `isolated`.
- Today the working tree has **zero** untracked files that step 2 would copy, so
  the step is currently a no-op here. That is exactly why it is worth fixing now
  rather than after it starts mattering: nothing would notice it breaking.

## Suspected Cause
Not carelessness — `|| true` was almost certainly right when written, because a
failed copy must not abort a run. The gap is that "must not abort" was
implemented as "must not be mentioned".

## Desired Behavior
A run states whether each disposable checkout was fully seeded, in the same
places and the same vocabulary it already states whether isolation armed.

## Acceptance Criteria
- AC-001: every seeding step reports its own failure. A failed copy still does
  not abort the run — the requirement is that it stops being silent. Prove each
  of the three steps separately by mutation.
- AC-002: `isolated` does NOT become false for a partly seeded checkout. The
  word means the suite ran in a disposable tree and that stays true. A new,
  separately named axis carries seeding completeness. Say in the spec why the
  two are not merged.
- AC-003: the new axis appears on all three surfaces — stdout, the summary
  block, and the run-ledger record — exactly as `isolated`/`degraded` does.
- AC-004: the exit code is unchanged. Report-only, no new gate. State why, and
  state whether it should become a gate when the tripwire is deleted.
- AC-005: `aai-run-tests.sh` reports the same axis in the same words, so the two
  funnels cannot be read as disagreeing.

## Verification
- prove each of the three seeding steps separately by mutation, each with an
  unmutated green control
- force a real partial seed (an unreadable seed path, a full destination) and
  read all three surfaces on the same run
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed>` returns

## Constraints / Risks
- `tests/skills/test-framework.sh` is the funnel for all 83 suites and
  `aai-run-tests.sh` is the canonical per-suite entrypoint (CHANGE-0139). A
  defect here weakens every run on every machine.
- **Do not make a failed copy abort the run.** The `|| true` is there for a
  reason; only its silence is the defect.
- Follow the accounting shape CHANGE-0156 already established: one status per
  suite, ONE increment site, and an invariant the summary CHECKS rather than
  assumes (`generate_summary` already does this for `isolated`/`degraded`).
- The wrapper must stay POSIX sh — verify with `sh -n` and `dash -n`, and do not
  disturb its exit codes (124 watchdog, 125/127 unlaunchable, wrapped command's own).
- `docs/ai/tests/test-runs.jsonl` is append-only live data. Never rewrite it.
- The full framework run costs 18-28 minutes. Budget one, not several.
- No secret is referenced by this scope.

## Notes
- Registry item this scope closes: `fu-seeding-completeness-uncounted` (P2).
- Related, NOT in scope: `fu-tripwire-removal-needs-a-gate` (P2) and deleting
  the tripwire itself. This change is the second of that ride's two inputs.
- Ride discipline: ship on these acceptance criteria and nothing else. A finding
  outside them is filed, not fixed here. Two validation rounds maximum.
- Worth knowing while working: `grep` resolves to a shell function even
  non-interactively here, zsh does not word-split unquoted variables,
  `find -newermt` is a hard error, reading an exit code after a pipe reports the
  pipe's last command, and in JavaScript `String.replace` a `$'` in the
  REPLACEMENT means "everything after the match" — all five have produced
  fabricated measurements or corrupted files in this repository this week.

---
id: reaper-etime-impossible-age-clamp
number: 53
type: change
status: done
links:
  spec: null
  pr:
    - 152
  commits:
    - c721f0b4c34205698030edc7a7dcd48e6dd37f2c
---

# Reaper CI-load flake — root-cause fix: pre-epoch impossible-age clamp

## Summary
- Root-cause fix for the recurring **CI-load-only** flake of
  `tests/skills/test-aai-run-tests.sh` in BOTH reaper directions — TEST-018
  (legacy "must spare the fresh match") and TEST-006/015/016 (epoch "over-reached:
  killed a fresh sibling"). The `reaped ages:` diagnostic added in SPEC-0083 / #149
  captured the smoking gun on PR #150 CI: `reaped ages: 208482=38109073018720` — the
  age guard saw a JUST-FORKED process as **~38.1 trillion seconds** old
  (`441077234-00:18:40`, a ~441-million-DAY etime).
- Mechanism: under heavy CI load, reading `/proc/<pid>/stat` for a process still
  mid-fork can sample a near-zero `start_time`, so `ps` computes `etime = now -
  start_time` as a huge, **grammar-valid day form**. The SPEC-0083 charset guard
  (`*[!0-9:-]*`) cannot catch it — every character is a digit/colon/dash. That huge
  age crosses the legacy `MIN_AGE` (reap a fresh match) and, symmetrically, makes
  `start_epoch = SNAP_NOW - age` hugely negative in epoch mode (reap a
  post-boundary sibling). ONE bad age → BOTH failure directions.
- Fix: a **pre-epoch plausibility clamp** in `etime_to_secs` — a process cannot
  have started before the Unix epoch, so any computed age `>= SNAP_NOW` is
  physically impossible and is treated as age 0 (just started = spare). Plus a
  strict ps-grammar **range guard** (seconds/minutes 00-59, hours 00-23) that
  rejects a bare multi-digit number sliding into the etime column. Both only ever
  make the reaper MORE conservative (spare on uncertainty) — never reap more.

## Type
- change (test-infra / reaper de-flake; safety-critical fail-safe direction; the
  confirmed root-cause fix that SPEC-0083's guard only defended against)

## Motivation / Business Value
- This flake has blocked multiple unrelated green-code PRs (its diff never touches
  the reaper) and survived three prior attempts (margin widening #123, workspace
  isolation #128, the etime charset guard #149). #149's diagnostic was explicitly
  built to root-cause the next recurrence — it did. This closes it at the parse
  boundary with a principled, physically-grounded bound rather than another margin.

## Scope
- In scope:
  - `.aai/scripts/aai-reap-tests.sh`: `etime_to_secs` gains (1) a strict range
    guard (ss/mm 00-59, hh 00-23 → out-of-range = age 0) and (2) an optional
    `now` (SNAP_NOW) 2nd arg enabling the pre-epoch clamp (`total >= now` → 0).
    The Guard-3 call site passes `SNAP_NOW`.
  - `tests/skills/test-aai-run-tests.sh`: TEST-022 extended — a bare 14-digit
    number and out-of-range components reject to 0; the exact huge-day form
    (`441077234-00:18:40`) returns raw seconds with 1 arg (RED baseline) and
    clamps to 0 with `now`; a real 10-day age (864000 s) survives the clamp.
- Out of scope:
  - The reap/spare thresholds, GRACE, and epoch arithmetic (unchanged). No margin
    widening. The charset guard from #149 is retained.

## Desired Behavior (To-Be)
- A garbled etime whose implied age predates the Unix epoch (the mid-fork
  `/proc` race) is treated as age 0, so a fresh match is SPARED in legacy mode and
  a post-boundary sibling is SPARED in epoch mode, under any CI load.
- A bare multi-digit number or out-of-range component (a column-shift word) is
  treated as age 0.
- Every genuinely-valid etime (`SS`, `MM:SS`, `HH:MM:SS`, `D-HH:MM:SS`) up to a
  physically-plausible age parses exactly as before — no regression to the
  legitimate reap-old direction (TEST-017 still reaps a real pre-step survivor).

## Acceptance Criteria
- AC-001: `etime_to_secs` clamps any age `>= now` (2nd arg) to 0; the exact CI
  form `441077234-00:18:40` returns `38109073018720` with 1 arg (RED baseline) and
  `0` with `now`. Deterministic unit test (TEST-022), RED against the pre-change
  parser.
- AC-002: `etime_to_secs` rejects a bare multi-digit number and out-of-range
  ss/mm (`>59`) / hh (`>23`) components to age 0; valid etimes (`00:03`→3,
  `01:00`→60, `1-00:00:00`→86400) parse exactly; a real 10-day age (`10-00:00:00`
  →864000) is NOT clamped.
- AC-003: the full `test-aai-run-tests.sh` reaper suite passes locally and runs
  clean under POSIX sh (dash); no parser regression on `reaped:`/`reaped pids:`.

## Verification
- `bash tests/skills/test-aai-run-tests.sh` (all green, incl. the extended TEST-022).
- `dash -n .aai/scripts/aai-reap-tests.sh` (bashless — W1).
- Extracted the pre-change `etime_to_secs` and confirmed it returns the raw
  `38109073018720` / `6039` for the new assertions (RED), the new one returns 0.
- CI-authoritative for the CI-load recurrence: TEST-018 + TEST-006 must stop
  flaking across subsequent unrelated PRs (Review-By below; closes SPEC-0083 AC-04).

## Constraints / Risks
- The clamp bound (`>= SNAP_NOW ≈ 1.75e9 s`) is ~55 years — no real process
  approaches it, so no legitimate age is ever rejected; the observed garbage
  (`3.8e13 s`) is four orders of magnitude past it. The clamp only ever spares
  (fail-safe direction: a mis-aged process lingers rather than a fresh one dying).
- Residual: a column-shifted argv word that is COINCIDENTALLY a valid in-range
  `MM:SS`/`HH:MM:SS` string (age 60-86399 s) would still parse; not observed, and
  the fixture markers are not time-shaped. Recorded for the same diagnostic.
- `.aai/scripts/aai-reap-tests.sh` is NOT a protected_paths_l3 path (L2).

## Notes
- Related: reaper-test-018-etime-shape-guard (CHANGE-0050/SPEC-0083, the diagnostic
  that captured this), reaper-deterministic-age-guard (SPEC-0064). This is the
  root-cause fix SPEC-0083 AC-04 anticipated — "use the data, not another margin."

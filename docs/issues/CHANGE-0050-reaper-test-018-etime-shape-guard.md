---
id: reaper-test-018-etime-shape-guard
number: 50
type: change
status: done
links:
  spec: null
  pr:
    - 149
  commits:
    - a2f5a473273e2b53be0933df79c074bff7a70376
---

# Reaper test-018 legacy spare-fresh flake — etime shape fail-safe guard

## Summary
- De-flake the recurring CI-load-only failure of `tests/skills/test-aai-run-tests.sh`
  TEST-018 "fail-safe broken … legacy MIN_AGE=60 must still spare the fresh match".
  Root cause (traced from the test's own Spec-AC-04 DIAG): the reaper's
  `etime_to_secs` parses whatever lands in the `etime` column of
  `ps axo pid=,etime=,args=`. A just-forked process can momentarily present an
  EMPTY etime to `ps`, shifting the whitespace column read so an argv WORD lands
  in the etime field; parsing that word yields a nondeterministic age that can
  cross MIN_AGE and REAP a fresh sibling under load.
- Fix: `etime_to_secs` now FAILS SAFE — a field that is not etime-shaped (only
  `[0-9:-]`) is treated as age 0 (spare). This only ever makes the reaper more
  conservative, never reaps more. Plus an authoritative diagnostic so any future
  recurrence is root-caused at decision time.

## Type
- change (test-infra / reaper de-flake; safety-critical fail-safe direction)

## Motivation / Business Value
- This flake has blocked multiple unrelated PRs (its diff never touches the
  reaper) and resisted two prior attempts (margin widening, workspace isolation).
  It is not a margin problem — it is a column-parse race. A principled fail-safe
  guard closes it without touching the reap/spare thresholds.

## Scope
- In scope:
  - `.aai/scripts/aai-reap-tests.sh`: `etime_to_secs` fail-safe shape guard
    (non-`[0-9:-]` -> 0); a `reaped ages:<pid>=<age>` diagnostic line reporting the
    snapshot-time age the age guard decided on (existing parsers key on
    `reaped pids:` only and ignore it).
  - `tests/skills/test-aai-run-tests.sh`: new deterministic TEST-022 unit-testing
    the guard (empty / argv-word / non-etime input -> 0; valid etimes still parse),
    added to ALL_TESTS; TEST-018 DIAG dumps the reaper's authoritative ages line.
- Out of scope:
  - The epoch-mode reap thresholds and GRACE (unchanged). No margin widening.

## Desired Behavior (To-Be)
- A non-etime-shaped elapsed field (the column-shift race) is treated as age 0, so
  a fresh sibling is spared by the legacy MIN_AGE fail-safe under any CI load.
- Valid etimes (`SS`, `MM:SS`, `HH:MM:SS`, `D-HH:MM:SS`) parse exactly as before —
  no regression to the reap-old direction.
- The reaper reports the per-matched-pid snapshot-time age for diagnosis.

## Acceptance Criteria
- AC-001: `etime_to_secs` returns 0 for an empty field and for any field
  containing a non-`[0-9:-]` character (argv words, paths, dotted versions);
  valid etimes parse exactly (`00:00`->0, `00:03`->3, `01:00`->60,
  `1-00:00:00`->86400). Deterministic unit test (TEST-022), RED without the guard.
- AC-002: the full reaper suite passes locally with the added output line (no
  parser regression on `reaped:`/`reaped pids:`).
- AC-003: the reaper emits a `reaped ages:` line with `<pid>=<age>` for each
  matched pid.

## Verification
- `bash tests/skills/test-aai-run-tests.sh` (all green, incl. TEST-022).
- `bash tests/skills/test-aai-run-tests.sh TEST-022` RED against the guard-less
  reaper (proven), GREEN with the guard.
- CI-authoritative for the CI-load recurrence: TEST-018 must stop flaking across
  subsequent unrelated PRs (Review-By below).

## Constraints / Risks
- Residual: if a just-forked process's argv[0] were itself purely numeric and
  large, the shape guard would admit it; in practice argv[0] is a command name /
  path (non-numeric) for every real runner and test marker, so the observed flake
  is closed. The authoritative `reaped ages:` diagnostic captures any residual
  recurrence for follow-up. Recorded.
- CI-only reproduction (not reproducible locally); confirmation is CI-authoritative.
- `.aai/scripts/aai-reap-tests.sh` is NOT a protected_paths_l3 path (L2).

## Notes
- Related: reaper-deterministic-age-guard (SPEC-0064), test-018-legacy-spare-attribution
  (SPEC-0076). This is the boundary/mechanism fix those anticipated, not another margin.

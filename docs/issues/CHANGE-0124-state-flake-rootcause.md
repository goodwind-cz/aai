---
id: state-flake-rootcause
number: 124
type: change
status: done
user_visible: false
ceremony_level: 1
links:
  pr:
    - 231
  commits:
    - fec69d5f7011daf22cd161e9927e2fb6b8d2b5ad
---

# Change — the state-suite "byte-identical write" flake was a second-boundary race, not CI load

## Context (source + why now)

`tests/skills/test-aai-state.sh` arm
`test_063_rguard_marker_absent_bytewise` (r-guard TEST-RG-STATE-02 /
Spec-AC-02) failed on CI twice recently and passed on both re-runs and
locally. The most recent failure, run `31075894154`, landed on a diff that
does not touch `.aai/scripts/state.mjs` at all — a strong signal the arm,
not the code under test, was at fault. Project memory already carries a
"CI-load-only flake, re-run it" class for the reaper arms in
`tests/skills/test-aai-run-tests.sh`; this change stops the state arm from
being filed under that heading, because it is not the same defect and it is
not actually load-only.

## Root cause (measured, not inferred)

The arm performs TWO separate `state.mjs set-strategy` invocations — one
with no `AAI_ROLE`, one with `AAI_ROLE=orchestrator` — against two copies of
the same fixture, then `cmp -s` the two resulting files with ZERO
normalization.

Every mutator self-stamps the top-level `updated_at_utc` field from the wall
clock at one-second resolution: `bumpUpdatedAt()` defaults to `nowIso()`
(`.aai/scripts/lib/state-engine.mjs:39`, `:103`), which is
`new Date().toISOString().replace(/\.\d+Z$/, 'Z')`. Two invocations
separated by a cold `node` start therefore stamp DIFFERENT values whenever
the pair straddles a second boundary.

Captured failing diff (local repro, `KEEP_TEST_DIR=1`):

```
104c104
< updated_at_utc: 2026-08-06T09:18:47Z
---
> updated_at_utc: 2026-08-06T09:18:48Z
```

`cmp -l` reports exactly ONE differing byte — offset 2671, `7` vs `8`, the
seconds digit. Nothing else in the file varies: `set-strategy` writes fixed
scalars, the atomic-write tmp name (`${statePath}.tmp-${process.pid}`) never
reaches file content, and there is no map-ordering or mtime-derived field in
the written bytes.

This is the mutator behaving CORRECTLY. Two writes at two different wall-clock
instants are supposed to carry two different stamps. There is no
nondeterminism in `state.mjs` to fix; the defect is that the assertion
compared a deliberately time-varying field.

## Correction to the "CI-load-only" framing

The arm fails locally at roughly 1/30 with no load at all (measured). Load
does not create the race; it widens the window between the two `node` starts
and so raises the hit rate. Re-running was masking a permanently-present
~3%+ failure probability on every CI run of this suite.

## Scope

- In scope: `tests/skills/test-aai-state.sh`, arm
  `test_063_rguard_marker_absent_bytewise` only.
- Out of scope: `.aai/scripts/state.mjs` and
  `.aai/scripts/lib/state-engine.mjs` (L3, and not defective here); the
  reaper arms in `tests/skills/test-aai-run-tests.sh` (different mechanism,
  see Notes).

## Desired Behavior (To-Be)

The arm proves what Spec-AC-02 actually claims — a non-`subagent` `AAI_ROLE`
value produces the same write as no marker — without asserting that two
wall-clock stamps taken a few hundred milliseconds apart are equal.

## Acceptance Criteria

- AC-001: the arm normalizes exactly one field, the self-stamped
  `updated_at_utc` line, and compares every other byte of the two files
  verbatim.
- AC-002: a real, marker-induced content divergence still fails the arm.
- AC-003: a suppressed `updated_at_utc` bump (marker preventing the stamp
  refresh) still fails the arm, so the normalization cannot mask that
  regression.
- AC-004: a malformed or missing stamp still fails the arm.
- AC-005: 30 consecutive runs green under saturating CPU load; 30
  consecutive runs green without load; full `test-aai-state.sh` green.

## Verification

- `bash tests/skills/test-aai-state.sh test_063_rguard_marker_absent_bytewise`
  x30 with 24-32 self-terminating CPU load workers -> 0 failures
  (pre-fix under the same load: 2/30).
- Same arm x30 with no load -> 0 failures (pre-fix: 1/30).
- `bash tests/skills/test-aai-state.sh` -> exit 0.
- `bash tests/skills/test-aai-run-tests.sh` -> exit 0 (unchanged, regression
  check only).
- Negative controls, each RED-proven against the FIXED arm before landing:
  divergent `--selected` value -> FAIL; `updated_at_utc` forced back to the
  frozen fixture value -> FAIL; `updated_at_utc` replaced with a
  non-ISO string -> FAIL.

## Constraints / Risks

- Strategy `direct`: the change is a single test-assertion correction whose
  own RED/GREEN evidence is the load loop plus three negative controls
  recorded above; a separate TDD cycle would only restate them.
- Residual: the normalization is scoped to a well-formed ISO-8601 UTC stamp
  by regex, so a stamp-format change in `state-engine.mjs` surfaces as an
  arm failure rather than being silently absorbed. That is intentional.
- No secrets referenced.

## Notes

- The reaper arms in `tests/skills/test-aai-run-tests.sh` share the
  "wall-clock timing under load" family but NOT this mechanism: they compare
  process liveness across an `etime`-derived epoch guard, not bytes. That
  suite contains no `cmp`/`diff` assertion at all, and TEST-006 has already
  been migrated onto a deterministic step-start-epoch contract with
  documented slack (see the comment above `test_006`). The normalize-the-
  volatile-field fix has nothing to attach to there, so they are left
  untouched.

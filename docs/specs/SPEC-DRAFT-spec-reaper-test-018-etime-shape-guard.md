---
id: spec-reaper-test-018-etime-shape-guard
type: spec
number: null
status: draft
ceremony_level: 2
links:
  requirement: CHANGE-DRAFT-reaper-test-018-etime-shape-guard
  pr: []
  commits: []
---

# SPEC — Reaper test-018 legacy spare-fresh flake: etime shape fail-safe guard

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-reaper-test-018-etime-shape-guard.md
- Related: SPEC-0064 (reaper deterministic age guard), SPEC-0076 (test-018 attribution)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: The fix is a deterministic parse guard with a clean RED/GREEN — a
  unit test drives `etime_to_secs` with the exact garbage shapes the column-shift
  race produces (RED without the guard, GREEN with it). Safety-critical fail-safe
  direction of the reaper.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: One guarded function + one diagnostic line + one unit test;
  reversible; dedicated branch; no protected_paths_l3 (aai-reap-tests.sh is not listed).
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/aai-reap-tests.sh, tests/skills/test-aai-run-tests.sh

## Acceptance Criteria Mapping
- Spec-AC-01 (AC-001): `etime_to_secs` returns 0 for empty / non-`[0-9:-]` input
  (argv words, paths, dotted versions) and parses valid etimes exactly. Verification:
  deterministic TEST-022 (RED without the guard).
- Spec-AC-02 (AC-002): the full reaper suite passes with the added output line (no
  `reaped:`/`reaped pids:` parser regression). Verification: `bash tests/skills/test-aai-run-tests.sh`.
- Spec-AC-03 (AC-003): the reaper emits `reaped ages:<pid>=<age>` for matched pids.
  Verification: TEST-022 + a live reaper run showing the line.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By   | Notes |
|------------|--------------------------------------------------------|---------|----------|-------------|-------|
| Spec-AC-01 | etime_to_secs fail-safe on non-etime input             | done    | TEST-022 RED/GREEN | —   | GREEN |
| Spec-AC-02 | full reaper suite green with new output line           | done    | local suite pass   | —   | GREEN |
| Spec-AC-03 | reaper emits reaped ages: diagnostic                   | done    | live run           | —   | GREEN |
| Spec-AC-04 | TEST-018 stops flaking on unrelated PRs (CI-load)      | deferred | —       | 2026-08-15  | CI-authoritative; the flake is CI-load-only and not locally reproducible |

## Implementation plan
- `.aai/scripts/aai-reap-tests.sh`: shape guard at the top of `etime_to_secs`
  (`case "$et" in '' | *[!0-9:-]*) echo 0; return ;; esac`); `MATCH_AGES`
  accumulator + `echo "reaped ages:$MATCH_AGES"` after `reaped pids:`.
- `tests/skills/test-aai-run-tests.sh`: TEST-022 (extract + drive `etime_to_secs`);
  ALL_TESTS += 022; TEST-018 DIAG dumps the reaper ages line.

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                    | Description                                                  | Status |
|----------|------------|------|-----------------------------------------|--------------------------------------------------------------|--------|
| TEST-022 | Spec-AC-01 | unit | tests/skills/test-aai-run-tests.sh      | etime_to_secs: garbage/empty/argv-word -> 0; valid etimes exact | green |

RED-proof: TEST-022 observed FAILING against the guard-less reaper (stash the fix,
run TEST-022 -> a non-etime field yields a non-zero/empty age, not 0) before GREEN.

## Verification
- `bash tests/skills/test-aai-run-tests.sh` (all green, incl. TEST-022)
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS: TEST-022 green + full reaper suite green + AC-04 deferred (CI-authoritative)

## Evidence contract
Per artifact: ref_id reaper-test-018-etime-shape-guard; Spec-AC + TEST links;
command/scope; exit code; evidence path; commit SHA.

Notes: This document defines HOW, not WHAT/WHY. It does not define workflow.

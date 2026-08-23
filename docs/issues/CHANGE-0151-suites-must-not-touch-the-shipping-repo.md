---
id: suites-must-not-touch-the-shipping-repo
number: 151
type: change
status: done
user_visible: false
ceremony_level: 1
capability: aai-test-harness
links:
  pr:
    - 266
  commits:
    - 0067ffb3e1a30f369bf517ff8e1f78b41fc070a3
---

# Change — a suite must not be able to write to the shipping repository

## Summary
- Three registry items share one cause: a test or a probe runs a generator or a
  git command against `PROJECT_ROOT` instead of a fixture, and nothing notices.
- The worst instance is P1: on 2026-08-14 a validator probe helper `cd`-ed into a
  fixture **inside a command substitution**, which runs in a subshell, so the
  parent shell stayed in the real repository and two commits landed on `main`.
  It was repaired and verified, but it was caught by luck, not by a check.

## Motivation / Business Value
- A read-only role mutated the shipping repository. Nothing structural prevented
  it and nothing would have reported it.
- Two suites are today unrunnable during validation and remediation because they
  rewrite tracked files, so every role that needs them has to skip them — which
  means the surface they cover goes unverified exactly when it matters.

## Scope
- In scope: a tripwire at the single point where every suite is invoked, plus the
  two suites known to write to `PROJECT_ROOT`.
- Out of scope: making the suites themselves hermetic in general; any change to
  the roles' prompts; anything under `protected_paths_l3`.

## Affected Area
- `tests/skills/test-framework.sh` — the real funnel. It invokes each suite with a
  bare `bash "$test_file"` at lines ~179 and ~181, and CI runs the framework, so a
  tripwire placed only in `.aai/scripts/aai-run-tests.sh` would miss CI entirely.
- `.aai/scripts/aai-run-tests.sh` — the funnel roles use ad hoc.
- `tests/skills/test-aai-doc-numbering.sh` (TEST-013 runs `generate-docs-index.mjs`
  against `PROJECT_ROOT`).
- `tests/skills/test-aai-deslop.sh` (TEST-014 restores two real files from a temp copy).

## Desired Behavior (To-Be)
- D1 — a suite that changes the shipping repository's tracked state **fails and
  names itself**, rather than passing quietly. The comparison is `git rev-parse HEAD`
  plus `git status --porcelain=v1` before and after each suite.
- D2 — the tripwire reports **what** changed, not just that something did, so the
  next reader does not have to reproduce it to find out.
- D3 — the two known offenders stop writing to `PROJECT_ROOT` and become runnable
  during validation.
- D4 — the tripwire cannot be satisfied by a suite that fails to run at all: a
  skipped or crashed suite must not read as clean, and neither may a suite whose
  after-snapshot could not be taken.
- D5 — the guard lands as a **ratchet**, because validation's clean-tree census
  found four live writers, not two. The four are listed in the framework, each
  entry bound to the registry item that owes its fix and scoped to the exact
  paths that suite already dirties: an allowlisted suite inside its paths warns
  loudly and is counted separately, anything else — another suite, another path,
  a commit — still fails. Without it, the day this lands CI is red on a clean
  tree until four out-of-scope suites are fixed, which is not landable. The list
  only shrinks, and it is drained BY HAND: an automatic stale-entry report was
  shipped and then deleted, because "changed nothing in this run" is also true
  of a suite that skipped or crashed, so it told the operator to delete live
  entries and close real defects as fixed. Two stated limits, not enforced: an
  entry's path list cannot bind a path that was already dirty when the suite
  started and is not a ratchet path (`fu-tripwire-allowed-ignores-pre-dirty`),
  and the ratchet as a whole is transitional — the recorded successor is one
  disposable worktree per suite. This serves AC-001; it adds no acceptance
  criterion of its own.
  **CORRECTION (2026-08-23):** "the ratchet as a whole is transitional" is
  withdrawn. The recorded successor landed (SPEC-0138) and does not remove the
  cause — a disposable worktree shares the shipping repository's git common dir,
  so a suite inside it still reaches the shipping tree
  (`fu-isolated-suite-reaches-shipping-repo`, P1). The tripwire, the ratchet and
  the hashing are permanent; see the superseding `hitl_decision` at
  2026-08-23T20:05:00Z in `docs/ai/decisions.jsonl`.

## Acceptance Criteria
- AC-001: a deliberately dirty test suite, added as a fixture, turns the framework
  run red and the failure names that suite and the paths it touched.
- AC-002: the same fixture run through `.aai/scripts/aai-run-tests.sh` is also caught.
- AC-003: `tests/skills/test-aai-doc-numbering.sh` and `tests/skills/test-aai-deslop.sh`
  both run to completion against the real tree leaving `git status --porcelain=v1`
  byte-identical, demonstrated by running them.
- AC-004: the exit-42-is-SKIP contract still works and a skipped suite is not
  reported as clean by the tripwire.
- AC-005: the tripwire adds no more than one `git status` pair per suite and does
  not change any suite's exit code when the tree is unchanged.

## Verification
- run `bash tests/skills/test-framework.sh` and confirm the aggregate is unchanged
  apart from the new fixture arm
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>`
  returns, plus `tests/skills/test-aai-layer-profiles.sh` and
  `tests/skills/test-aai-feedback-upsert.sh` — the selector has repeatedly proven
  not to be a superset of what CI runs
- prove each new assertion **bites** by mutation, at full-suite level, with an
  unmutated green control; an assertion verified only by reading is not accepted
  on this repository

## Constraints / Risks
- `tests/skills/test-aai-doc-numbering.sh` aborts its whole suite on the first
  failed assertion (`log_fail` calls `exit 1`), so its later arms currently report
  nothing. Do not mistake its silence for coverage. That defect is filed separately
  as `fu-docnumbering-logfail-aborts-suite` and is **out of scope here**.
- The tripwire must not itself become a check that cannot fail. It is verified by a
  fixture suite that deliberately dirties the tree.
- Bash only, no dependencies. No change to `protected_paths_l3`.
- No secret is referenced by this scope.

## Notes
- Registry items closed by this scope: `fu-subagent-probe-hits-real-repo` (P1),
  `fu-docnumbering-t013-writes-real-tree` (P2), `fu-deslop-test014-no-restore-trap` (P3).
- Ride discipline adopted 2026-08-19 after the previous ride took nine validation
  rounds: ship on these acceptance criteria and nothing else. A finding outside them
  is filed, not fixed in this ride. Two validation rounds maximum.

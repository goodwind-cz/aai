---
id: ci-test-impact-selection
number: 71
type: change
status: done
user_visible: true
links:
  pr:
    - 171
  commits:
    - 7df1d74d75eba3aededa71336accca78714a4996
---

# Change — CI test impact selection: PR pushes run affected suites, full framework moves to merge + nightly

## Summary
- CI currently runs the full 49-suite framework (~25 min) on every PR push,
  including review-fix pushes (~30 full runs this weekend, 12+ CI-hours).
  Introduce deterministic impact selection: a declarative suite map
  (suite -> watched path globs), a selection script driven by
  git diff --name-only, an always-run cheap core, and FAIL-OPEN to the full
  run whenever any changed path is unmapped or touches shared libs or L3
  protected surfaces. The full framework becomes a post-merge gate on main
  plus a nightly cron plus an on-demand ci-full label.

## Motivation / Business Value
- Typical PR touches 2-5 mappable surfaces; selected runs land in 3-8 min.
  The safety net moves, it does not disappear: a regression slipping the
  selection is caught at merge or nightly, never silently dropped.
- Mirrors the local policy already adopted (targeted suites locally, CI
  binding) one level up, per operator direction 2026-07-27.

## Scope
- In scope:
  - tests/skills/suite-map.yaml: one row per test-aai-*.sh suite -> watched
    globs; shared-lib and protected-path triggers listed as FULL-RUN keys.
  - .aai/scripts/select-suites.mjs: reads the diff (base ref arg), applies
    the map, prints the selected suite list + per-suite reason + the core
    set (check-state, docs-audit strict, spec-lint corpus); prints
    FULL_RUN with the triggering path when fail-open fires; zero deps.
  - .github/workflows: PR job invokes the selector and runs only selected
    suites via test-framework.sh --skill; new post-merge (push to main)
    full-framework job; nightly cron full job; ci-full label override.
  - Hygiene pin: every existing test-aai-*.sh suite has a suite-map row
    (new stanza in test-aai-hygiene-pack.sh); selector self-test suite
    tests/skills/test-aai-suite-select.sh (fixtures: mapped diff, unmapped
    file fail-open, shared-lib fail-open, L3 fail-open, core always
    present).
  - PROFILES classification for the new script.
- Out of scope: changing test-framework.sh itself beyond consuming a suite
  list; local wrapper policy (already targeted); flake management.

## Affected Area
- tests/skills/suite-map.yaml (new), .aai/scripts/select-suites.mjs (new),
  .github/workflows/*.yml, tests/skills/test-aai-suite-select.sh (new),
  tests/skills/test-aai-hygiene-pack.sh (pin), .aai/system/PROFILES.yaml.

## Desired Behavior (To-Be)
- PR push: selector output visible in CI summary (suites + reasons); only
  selected + core suites run; unmapped/shared/L3 diffs escalate to full.
- Merge to main: full framework always. Nightly: full framework. Label
  ci-full on a PR: full framework.

## Acceptance Criteria
- AC-001: selector picks exactly the mapped suites for a fixture diff and
  always includes the core set (suite-verified).
- AC-002: fail-open triad — unmapped path, shared-lib path, protected L3
  path each force FULL_RUN with the triggering path named (suite-verified).
- AC-003: every existing test-aai-*.sh has a suite-map row; a new unmapped
  suite fails the hygiene pin (suite-verified RED/GREEN).
- AC-004: workflow YAML wires selector -> selected runs on pull_request,
  full on push-to-main + schedule + ci-full label (grep contracts on the
  workflow files; live CI proof on this very PR).
- AC-005: selection output is auditable — one line per selected suite with
  reason, one line naming dropped count (no silent truncation).
- AC-006: no regression — new suite + hygiene green locally; this PR's own
  CI demonstrates the selected path end-to-end.

## Verification
- bash tests/skills/test-aai-suite-select.sh (new)
- bash tests/skills/test-aai-hygiene-pack.sh
- Live: this PR's CI run shows selection; post-merge run shows full.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 (workflows/tests not protected — verify at planning).
- Risk: map rot — mitigated by the hygiene pin + fail-open default.
- Risk: selection misses a cross-suite coupling — mitigated by post-merge
  full gate + nightly (documented honestly in the workflow comment).

## Notes
- Operator direction 2026-07-27 ("efektivneji v CI vybrano aby nebezelo
  vzdy vse"). Autopilot intake: metrics question skipped,
  human_time_minutes null.

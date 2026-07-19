---
id: test-infra-reds-and-ci-gate
number: 42
type: change
status: done
links:
  pr:
    - 116
  commits:
    - afc688df6d9d8f0ebb217f7b7ce9b26ab4a9db09
---

# Fix three hidden test-infra reds and gate the skill suite in CI

## Summary
- A serialized full-suite run (honoring each suite's shebang) surfaced three real
  reds on `main` that had accumulated invisibly because the skill test suites are
  not run in CI. Fix all three, and close the gap by adding a CI job that runs the
  skill suite so such reds cannot accumulate unseen again.

## Motivation / Business Value
- `main` is red in three suites; a clean `bash tests/skills/test-framework.sh`
  currently reports failures. CI only runs `docs-numbering` + `ps1-quality`
  workflows, so skill-suite regressions ship silently (this is exactly how the
  verify-gate red — already fixed in ISSUE-0017/SPEC-0060 — and these three
  survived). Gating the suite in CI is the structural prevention.

## Scope
- In scope:
  - `.aai/system/PROFILES.yaml` — classify the 6 currently-unclassified vendored
    files so `test-aai-layer-profiles` passes.
  - `tests/skills/test-aai-worktree.sh` — fix the `pipefail` + `git log | grep -q`
    SIGPIPE false-failure (lines ~232 and ~245).
  - `.aai/scripts/aai-sync.sh` — restore the executable bit (git mode 100755) so
    `test-self-hosting-smoke` can invoke it.
  - `.github/workflows/` — add a workflow that runs the skill test suite on push/PR.
- Out of scope:
  - Refactoring the test framework itself.
  - The verify-gate red (already fixed, ISSUE-0017/SPEC-0060).

## Affected Area
- Test infrastructure (`tests/skills/`), the vendored-layer profile manifest,
  the distribution script's file mode, and CI configuration.

## Desired Behavior (To-Be)
- `test-aai-layer-profiles`, `test-aai-worktree`, and `test-self-hosting-smoke`
  all exit 0.
- A CI workflow runs the skill suite on every push/PR and fails on any red suite.

## Acceptance Criteria
- AC-001: `PROFILES.yaml` classifies 100% of the live `.aai` tree; the 6 files
  (`close-work-item.mjs`, `reconcile-telemetry.mjs`, `secrets-preflight.mjs`,
  `tdd-evidence-check.mjs`, `aai-reap-tests.ps1`, `aai-run-tests.ps1`) are placed
  in `core`/`extended` per the classification rule, disjoint, no stale entries.
  `./tests/skills/test-aai-layer-profiles.sh` exits 0.
- AC-002: `test-aai-worktree.sh` no longer false-fails under `set -o pipefail`;
  the isolation grep no longer depends on a SIGPIPE-terminated `git log`.
  `./tests/skills/test-aai-worktree.sh` exits 0, and the fixed grep still
  correctly detects both the present-in-feature and absent-in-main conditions.
- AC-003: `.aai/scripts/aai-sync.sh` is tracked with mode 100755
  (`git ls-files -s` shows 100755). `./tests/self-hosting/test-self-hosting-smoke.sh`
  no longer fails with "Permission denied" on aai-sync.sh.
- AC-004: A CI workflow file exists under `.github/workflows/` that runs the skill
  test suite (`tests/skills/`) on push and pull_request and fails the job if any
  suite is red. The workflow runs each suite honoring its shebang (not forced `sh`).

## Verification
- `./tests/skills/test-aai-layer-profiles.sh` → exit 0
- `./tests/skills/test-aai-worktree.sh` → exit 0
- `./tests/self-hosting/test-self-hosting-smoke.sh` → exit 0
- `git ls-files -s .aai/scripts/aai-sync.sh` → mode 100755
- New workflow YAML validates (parseable) and its run-step invokes the skill suite.
- Regression: `./tests/skills/test-aai-prompt-diet.sh` and
  `./tests/skills/test-aai-verify-gate.sh` remain exit 0 (unaffected).

## Constraints / Risks
- `PROFILES.yaml` has a strict two-space-dash indentation contract parsed by both
  bash awk and PowerShell regex — preserve it exactly; classification must be
  disjoint and cover 100% (test-aai-layer-profiles TEST-001 enforces against the
  live tree).
- The worktree fix must keep both assertions meaningful: commit PRESENT in the
  feature branch AND commit ABSENT in main. A naive `|| true` would mask real
  regressions — capture output to a variable instead so the grep exit reflects
  only the match, not a SIGPIPE.
- Changing `aai-sync.sh` to 100755 is a git mode change (use
  `git update-index --chmod=+x`); verify no CRLF/line-ending churn.
- CI runtime: the self-hosting smoke re-runs the whole suite in a bootstrapped
  copy (~2-3 min; docs-audit ~119s internally) — set a sane timeout; consider
  whether smoke runs in the same job or a separate one.
- No secret referenced — SECRETS PREFLIGHT skipped.

## Notes
- Root causes (from investigation 2026-07-19):
  - worktree: `set -o pipefail` + `git log --oneline | grep -q "<newest-commit-msg>"`
    → grep -q closes the pipe on first match, `git log` gets SIGPIPE (141),
    pipefail propagates it, `if ! <pipeline>` inverts to trigger `log_fail`.
    Commit itself succeeds. Timing/order-sensitive (fails when the match is the
    newest commit, i.e. line 1).
  - self-hosting-smoke: `aai-sync.sh` is committed 100644; the smoke calls it
    directly (`"$ROOT/.aai/scripts/aai-sync.sh" "$TARGET"`) → Permission denied.
  - layer-profiles: 4 engine `.mjs` (close-work-item, reconcile-telemetry,
    secrets-preflight, tdd-evidence-check) + 2 `.ps1` added over recent sessions
    were never added to PROFILES.yaml.
- `test-framework.sh` is the aggregate meta-runner; it is red only because of the
  above and needs no change of its own.

---
id: post-validation-pushes-reuse-test-results
type: change
number: 205
status: draft
links:
  pr: []
  commits: []
---

# Change Request: Post-validation pushes reuse the already-proven test result

Frontmatter status values: draft | implementing | done | deferred | rejected | superseded

## Summary
- A push that changes no code after a head already passed the full test sweep must not re-run the full sweep. CI should run only what the new delta can affect (ledger, index and core checks) and carry the earlier proof forward.
- Gitignored runtime artifacts (validation reports, evidence, TDD logs) must not be committable, because committing them is what currently forces full re-runs.

## Motivation / Business Value
- PR #434 (`pr-capability-preflight`): after the PR was CLEAN at `9d90d1e4`, commit `73359491` ("docs(pr): preserve final PR 434 validation and original RED proof") added 102 files / +12,962 lines — almost entirely force-added `docs/ai/reports/**` evidence and `docs/ai/tdd/` logs, which `.gitignore` excludes and the canon keeps local. No code changed, yet CI re-ran the full 4-shard sweep plus the Pester legs. The branch accumulated 13 `skill-suite` runs.
- Root causes, measured on that commit:
  1. `select-suites.mjs` returns `FULL_RUN reason=unmapped path=docs/ai/reports/...` for paths no suite maps (also `docs/decisions/**`), so a fail-safe meant for unknown code fires on inert artifacts.
  2. `.github/workflows/skill-suite.yml:148` selects over the whole PR diff (`--base-ref origin/<base>`), never the push delta, so once a PR contains any FULL_RUN path, every later push — including ledger-only ones — re-runs the full sweep.
  3. The PR ceremony itself produces several post-validation pushes (close commit, PR-number stamp, owner sign-offs, bot-sweep record); each must have green required checks on its exact head.
- Why the reports were committed at all: `git add -f` bypasses `.gitignore` silently, and no AAI check (pre-commit checks, `check-committed-scope.mjs`, CI, review) asks whether a committed path is ignored. The motive is a canon contradiction: Acceptance Criteria Status Evidence cells cite `docs/ai/reports/...` paths, and `close-work-item.mjs`'s evidence-path gate (CHANGE-0131, `evidence_path_gate: report-only` here) warns when a cited path does not resolve from the main checkout — which a gitignored report never does (PR #430 and #431 closes each printed 60+ such warnings). PR #434's commit messages ("preserve … RED proof", "historical evidence paths") show the agent resolved the warning by committing the evidence.
- It is systemic, not one agent: `main` already tracks 86 gitignored files (mostly `docs/ai/tdd/**`), added by PRs #292, #302, #415, #417, #420 and #433 — Claude rides included. A tracked file is no longer ignored, so every local regeneration of such a report or TDD log dirties every checkout, and report-writing tools overwrite tracked files.
- The repository is public. PR #434's 857 ignored files publish local environment details (owner e-mail 20×, `~/.codex/sessions/…` rollout paths, `~/.hermes/node/bin/node`, `~/.cache/codex-runtimes/…`, worktree layout); the `ghp_`/`AKIA`/`password` hits are synthetic test fixtures, not real secrets. Four files with similar local paths are already on `main`.
- Evidence that the narrow answer exists: selecting over the last push delta without the reports yields CORE plus 4 selected suites instead of the full run.
- Owner direction 2026-10-08: "it was already tested" — re-running the full sweep for a ledger/report-only push wastes CI time and delays merges; solve this before `/aai-merge`.

## Scope
- In scope:
  - A guard that refuses to commit a path matched by `.gitignore` (force-added runtime artifacts), in the canonical pre-commit checks and in `check-committed-scope.mjs`, with a clear message naming the path and the rule.
  - An inert path class in `select-suites.mjs` (closes or supersedes `fu-inert-path-class`): a reviewed glob list (e.g. `docs/ai/reports/**`, `docs/ai/tdd/**`, generated pages) that maps to no suite and never triggers `unmapped`.
  - Delta-based selection on PR `synchronize` events: when the previous head of the same PR passed the full sweep (or a selected run that covered the same suites) and the delta since that head contains only inert, ledger and generated-page paths, select over the delta only (CORE plus the suites those paths map to). Any code, test, prompt, workflow or unknown path in the delta falls back to today's whole-PR selection.
  - The required gate check stays the same name and stays required; the carried-forward run is visible in its log (previous head SHA and run id it relies on).
  - Clean `main`: untrack (`git rm --cached`, files stay on disk) every tracked path that `.gitignore` matches, and add a CI check that fails when `git ls-files -ci --exclude-standard` is non-empty.
  - Resolve the evidence-path contradiction: either the evidence-path gate accepts a cited path that exists as a local (ignored) runtime report, or the canon names one committed, project-owned place for durable evidence and the gate and the validation/report prompts point there. Planning picks one; the other route is documented as rejected.
- Out of scope:
  - Changing push-to-main or nightly behaviour (both stay full).
  - Skipping CI entirely (`[skip ci]`) — required checks must still report on the final head.
  - `/aai-merge` itself (follows this change on the roadmap).

## Affected Area
- `.github/workflows/skill-suite.yml` (select job), `.aai/scripts/select-suites.mjs`, `tests/skills/suite-map.yaml`, `.aai/scripts/check-committed-scope.mjs`, `.aai/scripts/pre-commit-checks.{sh,ps1}`, related suites (`test-aai-suite-select.sh`, hygiene/pre-commit suites).

## Desired Behavior (To-Be)
- Committing a gitignored path is refused with a named reason; the documented way to keep evidence is the local reports folder (and, where a project wants it shared, a project-owned path outside `docs/ai/reports/`).
- A PR push whose delta since the last fully tested head is inert/ledger-only runs CORE plus the affected suites in minutes and reports which earlier run it relies on; a push that touches anything else behaves exactly as today.
- The merge checkpoint commits (PR stamp, sign-offs, sweep record) no longer cost a full sweep each.

## Acceptance Criteria
- AC-001: A commit (staged or `git add -f`) containing a path that `git check-ignore` matches is refused by the pre-commit checks and by `check-committed-scope.mjs --strict`, naming the path; non-ignored commits are unaffected.
- AC-002: `select-suites.mjs` classifies paths matching the reviewed inert globs as inert: they never yield `FULL_RUN reason=unmapped` and select no suite beyond CORE.
- AC-003: On a PR `synchronize` event whose previous head has a successful full (or covering) skill-suite run and whose delta contains only inert, ledger and generated-page paths, the select job uses the delta and prints the previous head SHA and run id it relies on.
- AC-004: Any delta containing a code, test, prompt, workflow, protected or unmapped path falls back to whole-PR selection byte-for-byte as today; push-to-main, nightly, workflow_dispatch and the `ci-full` label stay full.
- AC-005: The required gate check name and semantics are unchanged; a missing or failed previous run never enables delta selection (fail-safe to whole-PR).
- AC-007: Closing a work item whose AC Evidence cells cite this ride's own validation reports produces no evidence-path warning and requires no commit of gitignored files; the chosen route is stated in the canon prompts that tell roles where to write evidence.
- AC-008: After this change `git ls-files -ci --exclude-standard` on `main` is empty (the 86 files are untracked, not deleted from disk), and a CI check fails any PR whose tree tracks a gitignored path, naming it.
- AC-006: Replaying PR #434's last push (`9d90d1e4..73359491`) through the new selector without the force-added reports yields CORE plus selected suites, not FULL_RUN; with the reports it is refused at commit time (AC-001).

## Verification
- Fixture tests for the guard (staged and force-added ignored paths, negated `!` re-includes, nested `.gitignore`).
- Selector tests for inert classification and the delta/whole-PR decision table, including the fail-safe cases.
- A workflow-level dry run on a scratch PR or an event-payload fixture proving the carried-forward run id is printed.

## Constraints / Risks
- Delta selection must never hide a code change: the delta is computed against the previous head that actually passed, not merely the previous push.
- Inert globs are a reviewed allow-list; a new runtime folder is `unmapped` (full) until added deliberately.
- Projects that intentionally commit evidence must use a project-owned path; the guard must say so.

## Notes
- Related: `fu-inert-path-class` (P3, ci-test-selection-narrowing-and-sharding), PR #434 run history, roadmap item `directed-merge-and-post-merge-cleanup` (follows this change).

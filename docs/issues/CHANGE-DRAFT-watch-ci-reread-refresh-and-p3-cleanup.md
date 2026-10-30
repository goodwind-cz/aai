---
id: watch-ci-reread-refresh-and-p3-cleanup
type: change
number: null
status: implementing
user_visible: false
links:
  pr: []
  commits: []
---

# watch-ci re-read refresh, SKILL_PR release-notes wording, and two ledger corrections

## Summary
- Close the four P3 follow-ups left open by the 2026-10-29 rides
  (`watch-ci-cancelled-runs-and-release-gate-docs`, PR #517, and
  `docs-audit-content-engine-split`, PR #516) in one small scope.

## Motivation / Business Value
- `fu-current-head-ci-reread-stale-cache`: `.aai/scripts/lib/github-checks.mjs`
  caches each workflow run's state in `workflows` on the first check-run read.
  The snapshot-skew re-read (`readCheckRuns()` after the run list) reuses that
  cache, so a workflow cancelled between the two reads keeps its first-read
  status and conclusion. The new-cancellation guard
  (`workflow state moved during observation`) and the supersession decision
  then work from stale state: one spurious red (exit 5) or refusal that forces a
  manual `watch-ci` re-run. Never a false green.
- `fu-skill-pr-3b-shipped-docs-wording`: `.aai/SKILL_PR.prompt.md` step 3b
  still says "Docs/test/evidence-only changes are exempt". Since PR #517 the
  release-notes gate counts README.md, AGENTS.md, CLAUDE.md, CODEX.md,
  GEMINI.md, SKILLS.md, docs/USER_GUIDE.md and docs/product/** as shipped. The
  prompt contradicts the gate, and downstream installs inherit both.
- `fu-amend-wcr-file-list-correction` and `fu-docs-split-a1n-attribution`: two
  spec_amendment records on the append-only ledger `docs/ai/decisions.jsonl`
  state false facts (which files were outside the frozen file list, and which
  review raised NB-2). A false record must be corrected by an appended
  correction record, never edited or left standing.

## Scope
- In scope:
  - `.aai/scripts/lib/github-checks.mjs`: the re-read refreshes workflow-run
    state (status, conclusion) instead of reusing the first-read cache; a
    regression test in the existing current-head-ci suite.
  - `.aai/SKILL_PR.prompt.md` step 3b: exempt wording matches the gate and
    points to `docs/product/release-notes-gate.md` for the exact list (stay
    within prompt-corpus governance: line budgets, diet ledger, TEST-012).
  - `docs/ai/decisions.jsonl`: one appended correction record per false
    amendment statement (SPEC-0261 amendment 2026-10-29T21:38:47Z; SPEC-0260
    amendment A1-n and its 2026-10-29T18:07:55Z spec_amendment record), then
    close all four follow-ups via `follow-ups.mjs close`.
- Out of scope:
  - Any other change to supersession semantics, the release-notes classifier,
    or the 257-item follow-up backlog.
  - Hermes trust hint in `aai-update` (separate capability).

## Affected Area
- CI/release check reader shared by `watch-ci.mjs` and `release-finish.mjs`;
  the PR ceremony prompt; the decisions ledger.

## Desired Behavior (To-Be)
- A workflow run cancelled between the first and second check-run read is
  judged on its refreshed state: superseded by a newer same-workflow/event run
  it stays pending or is dropped exactly as a first-read cancellation would; not
  superseded it does not pass. No false green under any interleaving.
- SKILL_PR step 3b names the shipped user-facing docs consistently with
  `release-notes-gate.mjs` `isShipped`.
- `spec-amend` / `follow-ups` readers report the corrected facts; the four
  follow-ups are closed.

## Acceptance Criteria
- AC-001: Given a fixture where a workflow run is in progress on the first
  check-run read and cancelled on the re-read, with a newer same-workflow and
  same-event run in progress, the reader reports the affected check as pending
  (not failed, not refused).
- AC-002: Given the same mid-observation cancellation with no newer sibling run,
  the reader does not report the check as passed.
- AC-003: Existing current-head-ci, watch-ci and release-finish tests stay green
  (no regression to TEST-2711 or earlier cases).
- AC-004: `.aai/SKILL_PR.prompt.md` step 3b no longer calls docs-only changes
  exempt without qualification; it states that user-facing docs (the list in
  `docs/product/release-notes-gate.md`) are shipped and internal docs, tests and
  evidence are exempt; prompt-corpus governance suites pass.
- AC-005: `docs/ai/decisions.jsonl` gains appended correction records for both
  false amendment statements; no existing line is modified (git diff shows only
  added lines).
- AC-006: `node .aai/scripts/follow-ups.mjs list --status open` no longer lists
  the four follow-up ids.

## Verification
- Command(s) and expected results:
  - `bash tests/skills/test-aai-current-head-ci.sh` passes, including the new case.
  - `git diff origin/main -- docs/ai/decisions.jsonl | grep '^-[^-]'` prints nothing.
  - Prompt-corpus suites (selected by `select-suites.mjs`) pass.

## Constraints / Risks
- `github-checks.mjs` is the shared reader for release finish: the change must
  not widen any path to PASS. Refreshing state costs one extra `actions/runs/<id>`
  call per cached run only on the re-read path (which already runs only when a
  cancelled run was seen).
- Ledger is append-only (HAZ-LEDGER); correction records must use an existing
  record shape the readers fold (check `spec-amend.mjs` / `follow-ups.mjs`
  support before inventing one).
- Secrets preflight: no secret referenced.

## Notes
- Sources: review r1/r2 of `watch-ci-cancelled-runs-and-release-gate-docs`
  (`docs/ai/reviews/review-watch-ci-cancelled-runs-and-release-gate-docs-r2-20261029T221500Z.md`),
  review r3 of `docs-audit-content-engine-split`
  (`docs/ai/reviews/review-docs-audit-content-engine-split-r3-20261029T185418Z.md`).
- Owner directed this bundle on 2026-10-30 (menu choice "drobnosti P3" before
  release v2026.10.30).

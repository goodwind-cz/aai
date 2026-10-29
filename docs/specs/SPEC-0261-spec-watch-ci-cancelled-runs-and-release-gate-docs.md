---
id: spec-watch-ci-cancelled-runs-and-release-gate-docs
type: spec
number: 261
status: done
mutation_gate: v1
frozen_sha256: 8df485461c52035fc46c70c2f26db2b5bd521df292369c2c42a85001fb074231
ceremony_level: 2
links:
  requirement: watch-ci-cancelled-runs-and-release-gate-docs
  rfc: null
  pr: []
  commits: []
---

# Superseded cancelled CI runs and user-facing docs in the release-notes gate

SPEC-FROZEN: true

## Links

- Intake: docs/issues/ISSUE-0107-watch-ci-cancelled-runs-and-release-gate-docs.md
- Prior art: docs/specs/SPEC-0256-spec-current-head-ci-reader.md (shared current-head reader),
  docs/specs/SPEC-0229-spec-release-notes-gate.md (release-notes gate)
- Product: docs/product/release-command-finish.md, docs/product/release-notes-gate.md
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only; Bash 3.2 and GNU Bash)
- Baseline commit: `8c2669c4` (main at planning time)

## Implementation strategy

- Strategy: hybrid
- Rationale: the reader rule (Spec-AC-01 to 04) and the gate classifier
  (Spec-AC-05 to 08) change what CI and the release accept, so every one of
  those rows goes RED first with a stored artifact and a mutation record (TDD).
  The product and CHANGELOG text (Spec-AC-09) is written in loop mode but its
  inspection row is still mutation-gated.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions, the
  release suites build git fixtures and the mutation runs need a quiet tree;
  the scope is PR-bound. Neither file is a protected L3 surface
  (docs/ai/docs-audit.yaml protected_paths_l3), so not required.
- User decision: undecided
- Base ref: main
- Worktree branch/path: chosen by Implementation Preparation
- Inline review scope: the list in "Files Implementation touches" below.
- Code review required: true.

## What Planning measured

Planning inputs, read from the code and the live GitHub API on 2026-10-29;
not attestations of the implementation.

### Defect 1: watch-ci on PR #515

- `.aai/scripts/watch-ci.mjs` already reads checks only through
  `readCurrentChecks` in `.aai/scripts/lib/github-checks.mjs` (SPEC-0256, the
  "current-head-ci-reader" of v2026.10.29). `release-finish.mjs`
  `readReleaseRequiredChecks` calls the same function. There is no second
  reader to merge: AC-003 is met by changing the shared reader once.
- The reader keeps the newest observation per check name. For an Actions job
  it orders by the workflow run's `created_at`, then run id, then check id.
  It only sees check runs that exist. It never asks whether a newer run of
  the same workflow exists on the head.
- PR #515 head `1edc4a54`: `skill-suite` run 40878601419 (created 13:04:18,
  run conclusion `cancelled`) and run 40878615745 (created 13:04:24, later
  `success`), same `workflow_id` 316140990, same event `pull_request`. The
  workflow uses `concurrency` with `cancel-in-progress` for pull_request and
  triggers on `edited`, so a body edit on the same head cancels the earlier run.
- In the cancelled run, the required aggregate `skill test suite (tests/skills/,
  via test-framework.sh)` concluded `failure` (not `cancelled`): its needs were
  cancelled. `self-hosting smoke` concluded `cancelled`. In the newer run the
  aggregate job was created only at 13:12:53, after its needs finished; smoke
  at 13:04:55. For about eight minutes the only check runs with those two
  required names on the head came from the cancelled run, so the reader
  returned fail and cancel, and watch-ci exited 5 on its first settled poll.
- Required contexts on main: the aggregate, self-hosting smoke, and
  `doc-numbering guards (report-only unless enforced)`.
- Run-level identity is available: the reader already fetches
  `repos/{repo}/actions/runs/{id}` per run; that object carries
  `workflow_id`, `event`, `status`, `conclusion`, `created_at`.
  `repos/{repo}/actions/runs?head_sha=<sha>` lists every run on the head.

### Defect 2: release-notes gate

- `isShipped` (release-notes-gate.mjs line 8) matches `.aai/`, `.github/`,
  `.claude/`, `.codex/`, `.agents/`, `.gemini/` and root executables
  (mode 100755 or a script extension). Root Markdown and every `docs/` path
  are exempt.
- Callers: the gate CLI (`--staged` from `/aai-pr` step 3b in
  .aai/SKILL_PR.prompt.md; `--base/--head` from the `release notes` job in
  .github/workflows/skill-suite.yml) and `release-finish.mjs` `audit`, which
  classifies every commit since the previous tag with the same function
  (`aai-release --dry-run` and the confirmed cut). No PowerShell or pre-commit
  copy of the classifier exists.
- What downstream installs receive (`aai-sync.sh` and `aai-sync.ps1`, root
  shim loop): `AGENTS.md`, `CLAUDE.md`, `CODEX.md`, `GEMINI.md`, `SKILLS.md`
  copied as-is, and `README.md` copied as `README_AAI.md`. Neither sync script
  copies `docs/USER_GUIDE.md` or `docs/product/**`; those are AAI-repo pages
  that AAI users read on GitHub (README and the release notes link into them).
- History impact: `git log v2026.10.29..HEAD` holds exactly #515 (touches
  `docs/USER_GUIDE.md`, adds `## [unreleased] — docs(hermes): ...`) and #516
  (touches `docs/product/ci-test-impact-selection.md`, adds
  `## [unreleased] — test(ci): ...`). Both added an entry that the next cut
  rolls, so the audit's `addedRolledNotes` accept holds for both under a
  widened classifier. `bash .aai/scripts/aai-release.sh --dry-run --version
  v2026.10.30` on the baseline prints `## Preconditions` `- none`.
- Existing fixtures use `README.md` as the "docs only, exempt" example:
  tests/skills/test-aai-release-notes.sh (the `docs only` arm, the TEST-004
  export check `isShipped("README.md")` false, and the TEST-005 diverge arm).
  These flip under this scope and move to an internal-doc path.

## Decisions

D1. Superseded-run rule (one rule, in the shared reader). A workflow run R
on the current head is superseded when its run-level `conclusion` is
`cancelled` and another run R2 on the same head has the same `workflow_id`
and the same `event` and is newer by (`created_at`, then run id). Only the
newest such R2 (the sibling) matters. For each check observation that
belongs to a superseded run:
- if the sibling already has a check run of the same name and provider, the
  existing newest-observation ordering already prefers it (no change);
- else, if the sibling is not `completed`, the observation is replaced by a
  pending observation for that name (link: the sibling run's URL);
- else (the sibling completed without that name), the observation is dropped;
  a required name that is then missing refuses through the existing
  `required context missing from current head` path.
A run whose run-level conclusion is anything other than `cancelled`
(including a `failure` run) is never superseded by this rule; only the
existing per-name ordering applies to it.

D2. Why run-level `cancelled` and same `event`: a concurrency cancellation
implies the newer run already exists, so the rule never predicts an
unregistered run. A failed run that a body edit re-triggers is not
cancelled, so its failure keeps counting until the newer run's own check
replaces it. A `push` run and a `pull_request` run of one workflow on one head
are two independent verdicts, never siblings.

D3. The workflow-run list (`api --paginate --slurp
repos/{repo}/actions/runs?head_sha=<head>&per_page=100`) is read only when at
least one observed Actions run has run-level conclusion `cancelled`. Every
other observation issues no extra call, so the existing transports, fixtures
and release-suite stubs are unchanged. The list is validated like the
check-run pages: consistent `total_count`, complete pagination, unique run
ids, every run's `head_sha` equal to the head, `created_at` parseable,
`workflow_id` a positive integer; anything else refuses closed.

D4. watch-ci needs no new logic: it consumes the shared reader's buckets.
Its header comment gains one sentence naming the superseded-run rule.
`release-finish.mjs` is not edited.

D5. Shipped documentation (gate). `isShipped` additionally returns true for
exactly these paths: root `README.md`, `AGENTS.md`, `CLAUDE.md`, `CODEX.md`,
`GEMINI.md`, `SKILLS.md` (the root files aai-sync installs into a target),
`docs/USER_GUIDE.md`, and any path under `docs/product/`. Matching is exact
(case-sensitive, full path; `docs/product-notes.md`, `sub/README.md`,
`docs/README.md` stay exempt). Every other `docs/` path, `CHANGELOG.md`,
`tests/` and `docs/ai/` stay exempt.

D6. History stays green. No date or tag boundary is added to the audit: the
two commits since v2026.10.29 that touch the newly shipped paths both added
an `[unreleased]` entry, so the widened audit accepts them (measured above,
re-measured by Validation). A later commit that touches these paths without
notes is now named by the audit; that is the intended behavior change.

D7. Documentation of the path list lives in the CHANGELOG preamble and in
docs/product/release-notes-gate.md. .aai/SKILL_RELEASE.prompt.md is not
edited (no prompt-corpus growth; companion obligations do not apply).

## Acceptance Criteria Mapping

- Intake AC-001 maps to Spec-AC-01.
- Intake AC-002 maps to Spec-AC-02 and Spec-AC-03.
- Intake AC-003 maps to Spec-AC-01 (both consumers on one fixture) and Spec-AC-04.
- Intake AC-004 maps to Spec-AC-05, Spec-AC-07 and Spec-AC-08.
- Intake AC-005 maps to Spec-AC-06.
- Intake AC-006 maps to Spec-AC-09.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN the current head has a workflow run with run-level conclusion cancelled whose required check exists only in that run, and a newer run of the same workflow_id and event on the same head is not completed, watch-ci --required SHALL report the check pending and keep polling (exit 3 at the deadline with a degraded line naming pending, never exit 5) and readReleaseRequiredChecks SHALL return bucket pending; WHEN a later poll shows the newer run's check as success, watch-ci SHALL exit 0. The PR #515 replay fixture (cancelled run 40878601419, newer run 40878615745) behaves the same. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2701/2702/2711 PASS) | — | TEST-2701, TEST-2702 |
| Spec-AC-02 | WHEN a cancelled run has no newer run of the same workflow_id and event on the head (no sibling at all, or only a newer run of another event or another workflow), its checks SHALL keep their own bucket and watch-ci --required SHALL exit 5 naming the check; WHEN the older run's run-level conclusion is failure, a newer in-progress sibling without that check SHALL NOT mask it and watch-ci SHALL exit 5. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2703 PASS) | — | TEST-2703 |
| Spec-AC-03 | WHEN the workflow-run list is malformed, incompletely paginated, repeats a run id, or lists a run for another head, or the newest sibling has completed without a required check that only the superseded run carries, the shared reader SHALL refuse closed: watch-ci exits 3 with a degraded line and readReleaseRequiredChecks throws; neither ever reports pass. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2704 PASS) | — | TEST-2704 |
| Spec-AC-04 | The workflow-runs-by-head request appears in exactly one script file, .aai/scripts/lib/github-checks.mjs; watch-ci.mjs and release-finish.mjs each import readCurrentChecks and contain no actions/runs request; WHEN no observed run has run-level conclusion cancelled, the reader SHALL issue zero workflow-run list calls (fixture call log). | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2705 PASS) | — | TEST-2705 |
| Spec-AC-05 | WHEN a diff changes only one of README.md, AGENTS.md, CLAUDE.md, CODEX.md, GEMINI.md, SKILLS.md, docs/USER_GUIDE.md or docs/product/x.md, with no newly added unreleased entry and no no-notes line, release-notes-gate.mjs SHALL exit 1 with a REFUSED line naming that path, in both --staged and --base/--head modes; the same diff with a new unreleased entry, or with a no-notes reason, SHALL exit 0. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2706 PASS) | — | TEST-2706 |
| Spec-AC-06 | WHEN a diff changes only internal docs (docs/specs, docs/issues, docs/rfc, docs/analysis, docs/ai, docs/knowledge, docs/decisions, docs/INDEX.md, docs/README.md) the gate SHALL print PASS release-notes exempt and exit 0; isShipped SHALL return false for docs/product-notes.md, sub/README.md and tests/README.md. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2707 PASS) | — | TEST-2707 |
| Spec-AC-07 | Every root file that aai-sync.sh and aai-sync.ps1 install into a target from the source root (the root shim loop list and README.md) SHALL be classified shipped by isShipped; the test reads both lists from the two sync scripts, so a name added to either list without the classifier fails. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2708 PASS) | — | TEST-2708 |
| Spec-AC-08 | WHEN release-finish.mjs --audit runs offline on a fixture repository with a release tag, then a numbered commit changing docs/USER_GUIDE.md that adds an unreleased entry present in the audit notes, then a numbered commit changing docs/product/x.md with no notes, the audit SHALL print the second pull request number and SHALL NOT print the first. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2709 PASS) | — | TEST-2709 |
| Spec-AC-09 | The CHANGELOG preamble (text before the first level-2 heading) and docs/product/release-notes-gate.md each name all eight shipped documentation paths of D5 and state that other docs paths stay exempt; the product page no longer says documentation is exempt; docs/product/release-command-finish.md states the superseded cancelled run rule; CHANGELOG.md carries a new unreleased entry for this scope. | done | docs/ai/reports/VALIDATION-watch-ci-cancelled-runs-and-release-gate-docs-r2.md (TEST-2710 PASS) | — | TEST-2710 |

## Implementation plan

1. Reader (`.aai/scripts/lib/github-checks.mjs`): keep each fetched workflow
   object's `workflow_id`, `event`, `status`, `conclusion` with its run id.
   After the check-run loop, if any fetched workflow has conclusion
   `cancelled`, read and validate the head's workflow-run list (D3), find the
   newest sibling per cancelled run (D1), and rewrite or drop the superseded
   observations before the per-name `latest` selection. A synthetic pending
   observation keeps the superseded observation's name, provider, kind and
   orderKind, takes the sibling's identity for ordering
   (`[sibling created_at, sibling id, 0]`), and links the sibling run URL.
   Keep the head re-read after the observation.
2. watch-ci.mjs: one header sentence (D4). No logic change.
3. Gate (`.aai/scripts/release-notes-gate.mjs`): extend `isShipped` per D5
   with an explicit list and a `docs/product/` prefix test.
4. Tests and fixtures (Test Plan). Extend the gh stub in
   current-head-ci.test.mjs to answer `actions/runs?head_sha=` and to switch
   its check-run payload by poll count (two-phase fixture). Capture
   `tests/fixtures/watch-ci-pr515.json` from the live API with a provenance
   block (PR URL, head, both run ids, capture date): phase 1 is the cancelled
   run's check runs plus the newer run listed `in_progress` with none of its
   later jobs; phase 2 adds the newer run's check runs as recorded.
5. Update the README-based exempt fixtures in test-aai-release-notes.sh to an
   internal doc path (`docs/specs/x.md`), and add the selector functions
   (Test Plan) with a first-argument dispatch; a run with no argument keeps
   running the whole suite.
6. Docs last (after the code rows are green): CHANGELOG preamble paragraph and
   one `## [unreleased] — fix: ...` entry, product pages (Spec-AC-09).
7. suite-map: add `tests/fixtures/watch-ci-pr515.json` to
   `aai-current-head-ci`; add `tests/skills/lib/release-notes-docs.test.mjs`,
   `.aai/scripts/aai-sync.sh`, `.aai/scripts/aai-sync.ps1`,
   `.aai/scripts/release-finish.mjs` and `docs/product/release-notes-gate.md`
   to `aai-release-notes` globs.

Edge cases: chains of cancelled runs (only the newest sibling counts; an
intermediate cancelled run is itself superseded); a sibling that is itself
cancelled and completed (its own checks stand); a cancelled run of a workflow
with only legacy statuses (statuses are never superseded: they have no run).

## Seams crossed

- S1 shared reader to two consumers: TEST-2701 runs watch-ci (CLI, real
  process, fixture gh) and readReleaseRequiredChecks (real module) on the
  same transport and asserts both outcomes.
- S2 GitHub run model to reader: TEST-2702 replays identities captured from
  the real PR #515 runs, not hand-made ones.
- S3 gate classifier to release history audit: TEST-2709 runs the real
  release-finish.mjs audit on a real git history; the classifier is not mocked.
- S4 aai-sync install list to gate classifier: TEST-2708 reads the list from
  both sync scripts, the producer of what ships.
- Residual (no automated test): the real GitHub timing (when the newer run's
  jobs register) is only replayed, not exercised live; Validation may watch
  one live PR with an edited body as optional evidence.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-2701 | Spec-AC-01 | integration | tests/skills/test-aai-current-head-ci.sh | test_2701 runs node:test case TEST-2701: two-phase fixture, cancelled run 10 with required check failure, sibling run 20 in_progress with no checks; phase 1 watch-ci --required exits 3 naming pending and the release reader returns pending; phase 2 adds the sibling's success, watch-ci exits 0 | `sed:s/conclusion==='cancelled'/conclusion==='cancelled-disabled'/` on .aai/scripts/lib/github-checks.mjs | pending |
| TEST-2702 | Spec-AC-01 | integration | tests/skills/test-aai-current-head-ci.sh | test_2702 replays tests/fixtures/watch-ci-pr515.json: phase 1 watch-ci --required never exits 5 and the release reader returns pending for both required names; phase 2 exits 0 | `sed:s/conclusion==='cancelled'/conclusion==='cancelled-disabled'/` on .aai/scripts/lib/github-checks.mjs | pending |
| TEST-2703 | Spec-AC-02 | integration | tests/skills/test-aai-current-head-ci.sh | test_2703 three arms each exit 5 naming the check and the release reader keeps fail or cancel: no sibling; only a newer run of another event; older run conclusion failure with an in_progress sibling | `sed:s/w\.event===sibling\.event/true/` on .aai/scripts/lib/github-checks.mjs (implementation names its event comparison) | pending |
| TEST-2704 | Spec-AC-03 | integration | tests/skills/test-aai-current-head-ci.sh | test_2704 arms: malformed run list, short pagination, repeated run id, run for another head, completed sibling without the required check; each watch-ci exit 3 with degraded and release reader throws | `sed:s/fail\('incomplete or moving workflow-run pagination'\)/void 0/` on .aai/scripts/lib/github-checks.mjs (implementation names the refusal text) | pending |
| TEST-2705 | Spec-AC-04 | inspection | tests/skills/test-aai-current-head-ci.sh | test_2705 counts script files under .aai/scripts containing actions/runs?head_sha (exactly one, github-checks.mjs), checks both consumers import readCurrentChecks, and asserts zero run-list calls in the call log of an all-success fixture | `sed:s/if\(cancelledRuns\.length\)/if(true)/` on .aai/scripts/lib/github-checks.mjs (implementation names the lazy guard) | pending |
| TEST-2706 | Spec-AC-05 | integration | tests/skills/test-aai-release-notes.sh | test_2706 runs node:test case TEST-2706 in tests/skills/lib/release-notes-docs.test.mjs: real git fixture, each of the eight paths alone refuses naming it (staged and range), passes with a new entry and with a no-notes reason | `sed:s/docs\/USER_GUIDE/docs\/USER_GUIDE_DISABLED/` on .aai/scripts/release-notes-gate.mjs | pending |
| TEST-2707 | Spec-AC-06 | integration | tests/skills/test-aai-release-notes.sh | test_2707 runs node:test case TEST-2707: internal-docs-only diffs print PASS exempt; isShipped false for docs/product-notes.md, sub/README.md, tests/README.md | `sed:s/\^docs\/product\//^docs\/product/` on .aai/scripts/release-notes-gate.mjs | pending |
| TEST-2708 | Spec-AC-07 | inspection | tests/skills/test-aai-release-notes.sh | test_2708 runs node:test case TEST-2708: parses the root shim loop of aai-sync.sh and aai-sync.ps1 plus README.md and asserts isShipped true for each | `sed:s/GEMINI/GEMINI_DISABLED/` on .aai/scripts/release-notes-gate.mjs | pending |
| TEST-2709 | Spec-AC-08 | integration | tests/skills/test-aai-release-notes.sh | test_2709 runs node:test case TEST-2709: fixture repo with tag v1, numbered docs/USER_GUIDE.md commit with entry, numbered docs/product/x.md commit without; release-finish.mjs --audit offline prints the second number only | `sed:s/docs\/product\//docs\/productX\//` on .aai/scripts/release-notes-gate.mjs | pending |
| TEST-2710 | Spec-AC-09 | inspection | tests/skills/test-aai-release-notes.sh | test_2710 runs node:test case TEST-2710: each of the eight paths appears in the CHANGELOG preamble and in docs/product/release-notes-gate.md; the old wholesale documentation exemption sentence is absent; release-command-finish.md names the superseded cancelled run rule; CHANGELOG has an unreleased entry naming watch-ci and the release-notes gate | `sed:s/docs\/USER_GUIDE\.md/docs\/GUIDE.md/` on docs/product/release-notes-gate.md | pending |

RED plan: TEST-2701 to TEST-2704 and TEST-2706 to TEST-2709 are written and
observed failing on the baseline code before the change (TEST-2702 phase 1
reproduces the PR #515 exit 5; TEST-2706 reproduces `PASS: release-notes
exempt` for docs/USER_GUIDE.md). TEST-2705's zero-call arm and the
single-file count pass on the baseline only vacuously, so its RED is the
mutation record. RED artifacts go to
docs/ai/tdd/watch-ci-cancelled-runs-and-release-gate-docs/; mutation records
to docs/ai/tdd/spec-watch-ci-cancelled-runs-and-release-gate-docs/. Mutation
anchors on code that does not exist yet are named by intent; Implementation
records the exact regex it ran in each mutation record.

## Verification

- `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh` for the selected suites
  `aai-current-head-ci`, `aai-release-notes`, `aai-release`,
  `aai-release-first`, `aai-orchestration-dispatch` (TEST-062 watch-ci) and
  `aai-ci-body-recheck` if mapped; one full sweep before close
  (`AAI_TEST_TIMEOUT=3600`).
- `node .aai/scripts/spec-lint.mjs --path <this spec>` exits 0.
- History evidence (Validation, clean worktree at the branch head):
  `bash .aai/scripts/aai-release.sh --dry-run --version v2026.10.30` prints
  `## Preconditions` followed by `- none` (no #515 or #516 named).
- PR #513 shape: in a scratch clone, the gate over the #513 merge's
  first-parent range with an empty body prints REFUSED naming
  docs/USER_GUIDE.md (or SKILLS.md, docs/product/...).
- PASS criteria: every TEST row green, every Spec-AC terminal, mutation gate
  passes.

## Evidence contract

For each artifact record ref_id, Spec-AC and TEST links, command, exit code,
evidence path, and the commit SHA or diff range.

### Evidence by strategy

hybrid: stored RED artifact per AC-gating test under docs/ai/tdd/ plus a
mutation record per Test Plan row; green suite outputs.

## Files Implementation touches

- .aai/scripts/lib/github-checks.mjs
- .aai/scripts/watch-ci.mjs (header comment only)
- .aai/scripts/release-notes-gate.mjs
- tests/skills/lib/current-head-ci.test.mjs
- tests/skills/test-aai-current-head-ci.sh
- tests/fixtures/watch-ci-pr515.json (new)
- tests/skills/lib/release-notes-docs.test.mjs (new)
- tests/skills/test-aai-release-notes.sh
- tests/skills/suite-map.yaml
- docs/product/release-notes-gate.md
- docs/product/release-command-finish.md
- CHANGELOG.md
- docs/issues/ISSUE-0107-watch-ci-cancelled-runs-and-release-gate-docs.md
- docs/specs/SPEC-0261-spec-watch-ci-cancelled-runs-and-release-gate-docs.md
- docs/INDEX.md (regenerated)
- docs/ai/tdd/** (append-only evidence)

No new `.aai/**` file and no prompt-corpus bytes: neither companion
obligation applies.

## Assumptions (autopilot, no owner question)

- A1. The shipped documentation list is the eight paths of D5. The intake
  named three; the five root files are added because aai-sync installs them
  into every target, which is the gate's own meaning of shipped.
  `docs/README.md`, `docs/TECHNOLOGY.md` and other docs stay exempt.
- A2. A completed sibling run that never registers a required name refuses
  closed (exit 3) rather than falling back to the superseded result.
- A3. Supersession needs run-level `cancelled`; a superseded `failure` run is
  left to the existing ordering (D2). This is narrower than "any older run"
  on purpose.
- A4. The release-finish history audit gets no tag-date boundary (D6);
  measured history is green.

## Risks and rollback

- More doc PRs now need a note or a `no-notes:` line (intended; stated in
  CHANGELOG). Rollback: revert the `isShipped` hunk.
- An extra API call per poll only when a cancelled run is present; bounded by
  pagination like the check-run read.
- Rollback for the reader: revert the supersession block; behavior returns to
  SPEC-0256.

## Registry disposition

Registry items closed by this scope: none. Scanned `follow-ups.mjs list`:
`fu-platform-adapter-watch-ci` (move watch-ci onto lib/platform-adapter.mjs)
is a different subject and stays open; `fu-release-notes-heading-multiset`
(audit accept multiplicity) is untouched by the classifier change and stays
open.

## Amendment (post-freeze, 2026-10-29 - remediation of review r1 NB-1 and NB-3)

This is additive-with-disclosure; no delivered criterion changed and no owner sign-off was obtained.

- NB-1: the check-run snapshot was read before the workflow-run list, so a newer sibling that registered, failed and completed in between caused the cancelled run's copy of a check to be dropped while the sibling's failing check was absent from the snapshot. In non-required watch-ci mode watch-ci then exited 0 on a failure. Remediation: github-checks.mjs re-reads the check runs after the run list whenever a cancelled run is present, and refuses closed if a new cancelled workflow appears between the reads. The lazy run-list fetch is unchanged. New test TEST-2711 (tests/skills/lib/current-head-ci.test.mjs, test_2711 in tests/skills/test-aai-current-head-ci.sh) reproduces the race with a check-run sequence stub.
- NB-3: docs/USER_GUIDE.md still described documentation as exempt from the release-notes gate in two places; both now state the widened shipped list.
- Files touched beyond the list above: docs/USER_GUIDE.md and the TEST-2711 test.

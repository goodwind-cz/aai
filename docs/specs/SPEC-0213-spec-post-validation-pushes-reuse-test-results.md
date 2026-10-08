---
id: spec-post-validation-pushes-reuse-test-results
type: spec
number: 213
status: done
mutation_gate: v1
frozen_sha256: f9583a4adabe38492ffebe96462aa88179dcca80d90f1fb31f6e85f1a50dd8aa
ceremony_level: 3
links:
  requirement: post-validation-pushes-reuse-test-results
  rfc: null
  pr:
    - 435
  commits:
    - b11f56dab2dd3c7605367b9ce5c5fb4863482907
---

# Spec — Post-validation pushes reuse the already-proven test result

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-0205-post-validation-pushes-reuse-test-results.md
  (intake AC-001..AC-008 are the owner's direction).
- Prior work: docs/specs/SPEC-0206-spec-ci-test-selection-narrowing-and-sharding.md
  (sharding, deferred narrowing), docs/specs/SPEC-0118-spec-evidence-path-gate.md
  (CHANGE-0131 evidence-path gate), SPEC-0209 TEST-006 (branch-local tracked
  layer files in a downstream that ignores `.aai/`).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2, PowerShell
  5.1 parity).

## Registry items closed by this scope

Closed at delivery (PR #435; follow-ups closed with resolved-by post-validation-pushes-reuse-test-results):
- `fu-inert-path-class` (P3) — closed by Spec-AC-05: a reviewed `inert_globs`
  class in tests/skills/suite-map.yaml; inert paths select CORE only.
- `fu-mutation-evidence-is-gitignored` (P3) — closed by decision D6: local,
  gitignored evidence is the contract (never committed); close-work-item rescues
  worktree-only cited evidence into the main checkout instead.

NOT CLOSED, with reason (registry scan `node .aai/scripts/follow-ups.mjs list`,
2026-10-08):
- `fu-lib-graph-narrowing-after-sharding` — a different subject (shared-lib
  FULL_RUN fan-out); this scope does not narrow `.aai/scripts/lib/**`.
- `fu-mutation-gate-absent-tree-passes` — mutation-gate in CI is a separate
  gate; this scope makes the evidence tree absent in CI for two more specs
  (SPEC-0201, SPEC-0203, the untracked records), which that item already
  covers as a degrade class. Named here as an interaction, not closed.
- `fu-sweep-check-not-a-required-check` — unrelated job.

## Implementation strategy

- Strategy: tdd
- Rationale: owner choice recorded at intake ("spusť to hned plným TDD; CI check
  first"); STATE carries `implementation_strategy.selected: tdd`,
  `source: intake`, `ref_id: post-validation-pushes-reuse-test-results`. Kept.
  Every TEST row owes an observed RED (stored under
  docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/), a GREEN, and the
  named mutation reddening it via `mutation-run.mjs`. A MODULE_NOT_FOUND RED for a
  new script counts only as the first RED; the behavioral RED must follow.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: ceremony L3 (protected `pre-commit-checks.sh/.ps1`), a
  workflow edit to a required check, a `git rm --cached` of 86 tracked files and
  a close-work-item re-pin. The main checkout is shared by several live sessions
  (STATE's current worktree block still names the merged
  `change/pr-capability-preflight` and is stale for this scope); an index-wide
  untrack in the shared checkout would disturb other sessions' staging. Planning
  does not create the worktree.
- User decision: undecided (L3: an explicit decision must be recorded for any
  recommendation).
- Base ref: main (045e632e at planning time).
- Worktree branch/path: chosen by Implementation Preparation (suggested
  `change/post-validation-pushes-reuse-test-results`).
- Inline review scope: .github/workflows/skill-suite.yml,
  .aai/scripts/tracked-ignored.mjs, .aai/scripts/ci-select.mjs,
  .aai/scripts/select-suites.mjs, .aai/scripts/check-committed-scope.mjs,
  .aai/scripts/pre-commit-checks.sh, .aai/scripts/pre-commit-checks.ps1,
  .aai/scripts/close-work-item.mjs, .aai/scripts/lib/evidence-paths.mjs,
  .aai/VALIDATION.prompt.md, .aai/SKILL_TDD.prompt.md, .aai/SKILL_PR.prompt.md,
  .aai/system/PROFILES.yaml, tests/skills/suite-map.yaml,
  tests/skills/test-aai-tracked-ignored.sh, tests/skills/test-aai-ci-carry-forward.sh,
  tests/skills/test-aai-suite-select.sh, tests/skills/test-aai-close-work-item.sh,
  tests/skills/lib/close-work-item-pin.sh, tests/skills/lib/prompt-diet-ledger.sh,
  tests/skills/test-aai-prompt-diet.sh, tests/fixtures/ci-carry-forward/,
  CHANGELOG.md, docs/issues/CHANGE-0205-post-validation-pushes-reuse-test-results.md,
  docs/specs/SPEC-0213-spec-post-validation-pushes-reuse-test-results.md,
  plus the deletion-only cleanup diff of the paths listed by
  `git ls-files -ci --exclude-per-directory=.gitignore` at base (reviewed as a
  list, not file by file).
- Code review required: true; L3 means MANDATORY on the most capable tier and an
  operator final-diff checkpoint before merge.

## Ceremony

`ceremony_level: 3`. The scope edits `.aai/scripts/pre-commit-checks.sh` and
`.aai/scripts/pre-commit-checks.ps1`, both in `protected_paths_l3`
(docs/ai/docs-audit.yaml); WORKFLOW.md "Ceremony levels" makes L3 mandatory.
Independently of that rule the scope changes a required CI check's inputs, a
close gate, and the commit guard every downstream installs — L3 on its merits.

## Acceptance Criteria Mapping

| Intake AC | Spec-AC | Verification | Observable and evidence |
|---|---|---|---|
| AC-008 (CI check half) | Spec-AC-01 | V1, TEST-1700..1704 | `tracked-ignored.mjs --all` exit 1 naming each tracked ignored path, exit 0 on a clean tree; workflow job wired into the required gate |
| AC-008 (clean main half) | Spec-AC-02 | V1, V6, TEST-1705 | delivered tree: zero tracked ignored paths; cleaned files still on disk in the committing tree; full sweep green |
| AC-001 (pre-commit) | Spec-AC-03 | V2, TEST-1706..1709 | pre-commit checks (sh and ps1) refuse a commit adding an ignored path, naming path and rule; real hook refuses the commit |
| AC-001 (check-committed-scope) | Spec-AC-04 | V2, TEST-1710 | in-scope tracked ignored path fails with a named `tracked-ignored` label |
| AC-002 | Spec-AC-05 | V3, TEST-1711..1713 | inert paths never FULL_RUN, select CORE only; inert list pinned to gitignored dirs |
| AC-003 (delta mechanics) | Spec-AC-06 | V3, TEST-1714..1716 | `select-suites.mjs --delta-base` selects over the delta or refuses with a named reason |
| AC-003 (anchor and log) | Spec-AC-07 | V4, TEST-1720..1722 | carry-forward prints previous head SHA and run id; exact API calls; no new secrets |
| AC-004, AC-005 | Spec-AC-08 | V4, TEST-1723..1726 | every fail-safe cell yields whole-PR output identical to today; gate name and mode logic unchanged |
| AC-006 | Spec-AC-09 | V3, TEST-1727, TEST-1728 | PR #434 last-push replay yields CORE plus selected suites; the report paths are refused at commit time |
| AC-007 (gate) | Spec-AC-10 | V5, TEST-1730..1732 | close from a linked worktree: no evidence-path warning, evidence rescued into main checkout, nothing ignored committed |
| AC-007 (canon text) | Spec-AC-11 | V5, TEST-1733, TEST-1734 | VALIDATION, SKILL_TDD, SKILL_PR carry the LOCAL EVIDENCE rule; diet ledger, TEST-012 pin and PROFILES pass |

## Constitution deviations

None.

Article 5 (additive first) note: the new pre-commit refusal is new blocking
behaviour for every downstream that installs the hook. It is explicit (named
refusal with remedy), documented (CHANGELOG entry), and scoped to NEWLY added
ignored paths (D3), so it is a documented change, not a deviation.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN `node .aai/scripts/tracked-ignored.mjs --all` runs in a repository whose index tracks a path matched by the repository's own .gitignore files (any depth, honouring negations) the system SHALL print one `TRACKED_IGNORED <path> rule=<source>:<line>:<pattern>` line per such path and exit 1, and SHALL print `TRACKED_IGNORED none checked=<n>` with n greater than 0 and exit 0 when none; skill-suite.yml SHALL run it in an unconditional job on every event and the required gate job SHALL fail when that job did not succeed. | done | TEST-1700..1704 PASS (tests/skills/test-aai-tracked-ignored.sh); mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1700.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch A, lands first |
| Spec-AC-02 | WHEN the change is delivered `git -c core.excludesFile=/dev/null ls-files -ci --exclude-standard` and `tracked-ignored.mjs --all` on the delivered tree SHALL report zero paths, every path untracked by the cleanup SHALL still exist on disk in the tree where the cleanup commit was made, and the full skill sweep SHALL pass on that tree. | done | TEST-1705 PASS; tracked-ignored.mjs --all none checked=1598; cleanup commit d9744b8e (86 paths still on disk); full sweep 105/106 (win-fallback host-only); validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch A, same push as Spec-AC-01 |
| Spec-AC-03 | WHEN a commit stages an ADDED (including copy or rename destination) path that the repository .gitignore rules match, `pre-commit-checks.sh` and `pre-commit-checks.ps1` SHALL exit 1 naming the path, the rule and the `!` re-include remedy; a MODIFIED already-tracked ignored path SHALL produce a named warning (blocking only under --strict or -Strict); a deletion SHALL pass; a path ignored only by core.excludesFile or .git/info/exclude SHALL pass; a commit with no ignored path SHALL be unaffected. | done | TEST-1706..1709 PASS (sh and ps1 under pwsh), TEST-1736 could-not-run cell; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1706.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch B, D3 |
| Spec-AC-04 | WHEN `check-committed-scope.mjs` checks an in-scope path (file or directory) that is tracked in the compared tree and matched by repository .gitignore rules the system SHALL exit 1 and list it with the label `(tracked-ignored)`, in plain and --strict mode, with --rev evaluating that revision's tree. | done | TEST-1710 PASS; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1710.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch B |
| Spec-AC-05 | WHEN a changed path matches a suite-map `inert_globs` entry `select-suites.mjs` SHALL treat it as inert (never `FULL_RUN reason=unmapped`, never SELECTED even if a suite glob also matches), protected-l3 and shared-lib SHALL still take precedence, and every inert glob SHALL be a `<dir>/**` entry whose directory the repository .gitignore ignores. | done | TEST-1711..1713 PASS (tests/skills/test-aai-suite-select.sh), TEST-1737 .gitignore stays unmapped; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1711.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch C, closes fu-inert-path-class |
| Spec-AC-06 | WHEN `select-suites.mjs --delta-base <S> --head <H>` runs, the system SHALL print `DELTA base=<S>` followed by the normal CORE, SELECTED and DROPPED lines for the S..H diff only if S is an ancestor of H and every delta path matches `inert_globs` or `carry_forward_globs` and the delta selection is not FULL_RUN; otherwise it SHALL print exactly one `DELTA_REFUSED reason=<not-ancestor or ineligible or full-run or internal-error> path=<p>` line and no selection lines, always exiting 0. | done | TEST-1714..1716 PASS; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1714.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch C |
| Spec-AC-07 | WHEN a pull_request synchronize run's whole-PR selection is FULL_RUN and an older commit of the same PR has a completed successful skill-suite run in full mode, `ci-select.mjs` SHALL output the delta selection plus `CARRY_FORWARD sha=<S> run=<id> url=<html_url>`, using only GITHUB_TOKEN with job permission `actions: read` and the two documented API endpoints. | done | TEST-1720..1722 PASS (tests/skills/test-aai-ci-carry-forward.sh); mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1720.txt; live CARRY_FORWARD line not yet observed on CI; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch D, D4/D5 |
| Spec-AC-08 | WHEN any fail-safe cell holds (non-synchronize action, API or token or JSON or pagination error, no full-mode successful run, head repo or branch mismatch, pull-request number or base mismatch, candidate cap, not-ancestor, ineligible or FULL_RUN delta, or a whole-PR selection that is already selected) `ci-select.mjs` SHALL emit the whole-PR selector lines byte-identical to `select-suites.mjs --base-ref` plus one `CARRY_FORWARD none reason=<cell>` line; push-to-main, schedule, workflow_dispatch and the `ci-full` label SHALL stay full without invoking it, and the gate job's name and mode logic SHALL be unchanged apart from the Spec-AC-01 line. | done | TEST-1723..1726 PASS incl. exactly-20 cell; 400-commit differential selector sweep; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1723.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch D |
| Spec-AC-09 | WHEN the recorded path list of PR #434's last push (9d90d1e4..73359491) is replayed through the delivered selector the result SHALL be CORE plus SELECTED with no FULL_RUN line both without and with the gitignored report paths, and staging any of those report paths with `git add -f` in a fixture SHALL be refused by Spec-AC-03. | done | TEST-1727, TEST-1728 PASS (fixture tests/fixtures/ci-carry-forward/pr434-last-push-paths.txt); mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1727.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batches B and C |
| Spec-AC-10 | WHEN `close-work-item.mjs` runs from a linked worktree and an Evidence cell cites a path that exists only in that worktree and is ignored by repository rules in both trees the system SHALL copy it (no clobber, no symlinks) into the main checkout before any doc write, print one `evidence rescued` line per path, emit no evidence-path warning for it, and leave both indexes free of ignored paths; a cited non-ignored worktree-only path SHALL still warn exactly as today, and --dry-run SHALL list the rescue without copying. | done | TEST-1730..1732 PASS incl. info/exclude and main-only re-include cells; close-work-item.mjs re-pinned c6787afb; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1731.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch E, D6, re-pin LAST |
| Spec-AC-11 | WHEN the canon prompts are read, `.aai/VALIDATION.prompt.md`, `.aai/SKILL_TDD.prompt.md` and `.aai/SKILL_PR.prompt.md` SHALL each carry one `LOCAL EVIDENCE:` line stating that runtime evidence under docs/ai/reports, docs/ai/tdd and docs/ai/validation is cited by path and never force-added, and the prompt-diet, TEST-012 and layer-profiles checks SHALL pass with an itemized ledger entry and PROFILES rows for the two new scripts. | done | TEST-1733, TEST-1734 PASS; prompt-diet ledger and TEST-012 pin; mutation docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/mutation-TEST-1734.txt; validation docs/ai/reports/validation-post-validation-pushes-reuse-test-results.md | — | Batch E |

## Implementation plan

### D1 — One predicate, repository rules only

New `.aai/scripts/tracked-ignored.mjs` (core profile) is the single
implementation of "is this path ignored by the repository". Every caller
(CI job, both pre-commit checks, check-committed-scope, close-work-item rescue)
uses it; nobody re-implements ignore matching.

- Rules counted: per-directory `.gitignore` files only, via
  `git ls-files --exclude-per-directory=.gitignore`. Global `core.excludesFile`
  and `.git/info/exclude` are deliberately NOT counted: they are per-machine, CI
  has neither, and a developer's private excludes must not refuse a commit CI
  accepts. Measured on git 2.54 in a scratch repository: `-ci
  --exclude-per-directory=.gitignore` reports force-added and nested-.gitignore
  matches, honours `!docs/ai/reports/.gitkeep`, and omits info/exclude and
  global-excludes matches, which `--exclude-standard` includes.
- Modes:
  - `--all [--rev <rev>]`: every tracked path of the index (or of `<rev>` via a
    temporary index: `GIT_INDEX_FILE=<tmp> git read-tree <rev>`, removed after).
    Output per Spec-AC-01. The rule is named best-effort with
    `git -c core.excludesFile= check-ignore -v --no-index` (exact on CI).
  - `--staged`: index versus HEAD, `git diff --cached --name-only --no-renames -z`
    with `--diff-filter=AC` (errors) and `--diff-filter=MT` (warnings), each list
    intersected with the ignored-tracked set. Output lines
    `IGNORED_ADDED <path> rule=...` and `IGNORED_MODIFIED <path> rule=...`, plus
    `IGNORED_PREEXISTING count=<n>` for tracked ignored paths the commit does not
    touch. Exit 1 when any IGNORED_ADDED, else 0.
  - Exported functions `trackedIgnored({cwd, rev, paths})` and
    `ignoredUntracked({cwd, paths})` for in-process callers.
- `--no-renames` turns a rename into delete plus add, so a rename INTO an
  ignored path is caught as an add (the same lesson select-suites already
  encodes).
- Exit 2 on usage or git failure, with the git message; never a silent 0.

### D2 — CI backstop lands first (Batch A)

- New job `tracked-ignored` in `.github/workflows/skill-suite.yml`, name
  `tracked-ignored guard (no gitignored path may be tracked)`, no `if:`, runs on
  every event, `actions/checkout@v4` (default depth), setup-node 20, step
  `node .aai/scripts/tracked-ignored.mjs --all`.
- `gate.needs` gains `tracked-ignored`; the gate script gains exactly one line
  failing when `needs.tracked-ignored.result` is not `success`. This makes the
  check required through the existing required context
  `skill test suite (tests/skills/, via test-framework.sh)` without a branch
  protection change. Making the new job its own required context is optional
  and owner-only (HITL-2).
- The same push carries the cleanup: `git rm --cached` of every path that
  `tracked-ignored.mjs --all` lists at base (86 at planning time, all under
  docs/ai/tdd/). Commit order inside Batch A: cleanup commit FIRST, then the
  script, job and tests, so no pushed head ever has the job without the cleanup.
- The cleanup paths are NOT added to `code_review.scope` as paths:
  `check-committed-scope --strict` would report each untracked-but-on-disk path
  as a degrade. They are verified by Spec-AC-02's own command instead.
- Interaction (residual risk R1): any other clone that pulls the cleanup commit
  has those 86 files DELETED from its working tree by git (a tracked file absent
  in the incoming commit is removed). They stay recoverable from history:
  `git archive <base-sha> docs/ai/tdd | tar -x` restores them as untracked
  ignored files. The owner's main checkout is such a clone (HITL-3).

### D3 — Commit guard: block newly tracked ignored paths, warn on modified

Decision: the commit-level guard blocks ADDED ignored paths (incl. `git add -f`,
copy and rename destinations); MODIFIED already-tracked ignored paths warn (and
block under `--strict`/`-Strict`, whose existing semantics turn warnings into
errors); deletions always pass (that is the remedy); untouched pre-existing
tracked ignored paths produce one count warning. The CI check (D2) blocks ANY
tracked ignored path in this repository.

Rationale: SPEC-0209 TEST-006 pins a legitimate downstream shape — a project
that ignores `.aai/` but deliberately tracks a branch-local `.aai/AGENTS.md`.
Blocking modifications would refuse every commit after `/aai-update` in such a
project. Blocking only new adds stops the PR #434 shape (857 newly force-added
files) everywhere without breaking deliberate existing exceptions; the
documented way to track an ignored path deliberately is a `!<path>` re-include
in .gitignore, which the refusal message names. This narrows intake AC-001's
"staged" wording for the modified case (HITL-1 records it for the owner).

Rejected: blocking any staged ignored path (breaks downstream deliberate
tracking; also blocks every commit in a downstream with legacy tracked ignored
files until it cleans up). Rejected: an `AAI_ALLOW_IGNORED=1` bypass (an env
bypass is invisible in review; the `!` re-include is reviewable).

Wiring:
- `pre-commit-checks.sh`: new `# --- CHECK 9: Gitignored paths staged ---` block
  after CHECK 8 and before `# --- SUMMARY`, calling
  `node "$PROJECT_ROOT/.aai/scripts/tracked-ignored.mjs" --staged`; IGNORED_ADDED
  maps to `error`, IGNORED_MODIFIED and IGNORED_PREEXISTING to `warn`; node or
  script absent maps to one `warn` naming the skip (Article 4). Must not add a
  `| grep -q` (pipe-grep-q ratchet). TEST-809 in test-aai-doc-numbering.sh
  isolates CHECK 8 by awk up to `# --- SUMMARY`; CHECK 9 text then falls inside
  that window, so TEST-809 must be re-run (seam S5).
- `pre-commit-checks.ps1`: the same block, same mapping (`Write-Error-Check`,
  `Write-Warn-Check`).
- `check-committed-scope.mjs`: after the existing loop, call `trackedIgnored`
  for the in-scope paths (directories expanded by git pathspec) against the
  index, or against `--rev` via the temporary-index mode; each hit is a mismatch
  labelled `(tracked-ignored)` and fails in plain and --strict mode. The
  existing ledger-append and degrade logic is untouched.
- No change to `install-pre-commit-hook.sh/.ps1` (the hook already runs
  pre-commit-checks on every commit).

### D4 — Inert class and delta mode in select-suites (Batch C)

tests/skills/suite-map.yaml gains two top-level lists (the hand-rolled parser
learns them; an absent list is an empty list, so an old map selects
byte-identically):

```
inert_globs:
  - docs/ai/reports/**
  - docs/ai/tdd/**
  - docs/ai/validation/**
  - docs/ai/briefs/**
  - docs/ai/archive/**
  - docs/ai/friction/**
  - docs/ai/live/**
carry_forward_globs:
  - docs/ai/EVENTS.jsonl
  - docs/ai/decisions.jsonl
  - docs/ai/METRICS.jsonl
  - docs/ai/tests/test-runs.jsonl
  - docs/INDEX.md
  - docs/ai/overview.html
  - docs/ai/overview-data.json
  - docs/ai/factory-report.html
  - docs/ai/factory-report-data.json
  - docs/ai/dashboard.html
  - docs/ai/dashboard-data.json
  - docs/SKILL_CATALOG.html
  - docs/skill-catalog-data.json
  - docs/USER_GUIDE.md
  - docs/specs/**
  - docs/issues/**
  - docs/ai/reviews/**
  - docs/decisions/**
  - CHANGELOG.md
```

- Inert = gitignored runtime directories only. Every inert glob must be
  `<dir>/**` and `<dir>/probe` must be ignored by the repository .gitignore
  (pinned by TEST-1713), so the class can never swallow a committed surface.
  A new runtime folder stays `unmapped` (full) until added deliberately.
- `docs/decisions/**` is NOT inert: docs-audit-core reads it. It is added to the
  `aai-docs-audit` row (core, always runs), which removes its `unmapped` trigger.
- `docs/ai/tdd/**` is removed from the `aai-tdd-evidence` row: under inert
  precedence the entry is dead, and that suite self-seeds its fixtures
  (test-aai-tdd-evidence.sh:42).
- Classification precedence: protected-l3, shared-lib, inert, suite match,
  unmapped. An inert path selects nothing and is never unmapped.
- `carry_forward_globs` (ledgers, generated pages, governed docs, review
  reports, changelog — the closed set of what close ceremony, PR stamp,
  sign-offs and sweep records write) only decides delta ELIGIBILITY; those paths
  still select their mapped suites in delta mode. A path in neither list is
  ineligible. Code, tests, prompts, workflows, `.aai/**`, protected and unmapped
  paths are therefore never eligible by construction. Every carry-forward glob
  must classify as mapped or inert in whole-PR mode (TEST-1713 probes one
  representative path per glob).
- New CLI: `select-suites.mjs --delta-base <S> [--head <H>]` (H defaults to
  HEAD). Steps: verify both resolve to commits; `git merge-base --is-ancestor S H`
  else `DELTA_REFUSED reason=not-ancestor`; delta =
  `git diff --name-only --no-renames S H`; first path in neither list gives
  `DELTA_REFUSED reason=ineligible path=<p>`; run the normal classification over
  the delta; a FULL_RUN gives `DELTA_REFUSED reason=full-run:<reason> path=<p>`;
  success prints `DELTA base=<S>` then CORE, SELECTED, DROPPED. Empty delta
  prints `DELTA base=<S>` plus CORE only. Exit always 0; any thrown error gives
  `DELTA_REFUSED reason=internal-error`.
- Without `--delta-base` every existing mode is byte-for-byte unchanged except
  that inert paths no longer FULL_RUN (Spec-AC-05).

### D5 — Anchor discovery and workflow wiring (Batch D)

New `.aai/scripts/ci-select.mjs` (core profile, Node 20 global `fetch`, no
dependency, no new secret). It owns the PR-path decision so the decision is
testable outside GitHub; the YAML keeps its existing mode/suites derivation
lines byte-identical.

Inputs: `--base-ref origin/<base>`, `--event <path>` (GITHUB_EVENT_PATH),
`--repo <owner/name>` (GITHUB_REPOSITORY), `--workflow-file skill-suite.yml`,
`--api-url` (default GITHUB_API_URL, else https://api.github.com), env
GITHUB_TOKEN. Test-only `--api-fixture <json>` (a map from request path and
query to `{status, body}`) plus `--request-log <file>`; the workflow never
passes them (TEST-1722 pins it).

Algorithm (first failing condition ends in `CARRY_FORWARD none reason=<cell>`
after the whole-PR lines):
1. Run `select-suites.mjs --base-ref <base-ref>` (child process, current
   behaviour). Not FULL_RUN: print its lines, `CARRY_FORWARD none
   reason=whole-pr-selected`, stop. Zero API requests in this cell.
2. Event `action` must be `synchronize` (else `reason=action-<action>`).
3. H = `pull_request.head.sha`; head repo = `pull_request.head.repo.full_name`;
   head ref = `pull_request.head.ref`. Missing field: `reason=event-malformed`.
   Missing token: `reason=no-token`.
4. Candidates = `git rev-list --max-count=20 H ^<base-ref>` minus H, newest
   first. Exhausted: `reason=no-covering-run`.
5. Per candidate C: `GET /repos/{repo}/actions/workflows/skill-suite.yml/runs?event=pull_request&status=completed&head_sha=<full C>&per_page=20`
   (verified live 2026-10-08: the filter needs the full 40-hex sha). Keep runs
   with `head_sha == C`, `event == pull_request`, `conclusion == success`,
   `head_branch == head ref`, `head_repository.full_name == head repo`.
   The run's `pull_requests[]` must also contain an entry whose `number`,
   `base.ref` and `base.sha` equal the event's `pull_request.number`,
   `pull_request.base.ref` and `pull_request.base.sha` (strict base-sha equality
   is deliberate: a moved base re-runs everything). Otherwise the run is not an
   anchor: `reason=anchor-pr-mismatch` (other PR number, or an empty array as on
   fork PRs) or `reason=anchor-base-moved` (same PR, different base ref or sha).
   An event without `number` or `base` is `reason=event-malformed` (PR #435 review).
   For each kept run, newest first:
   `GET /repos/{repo}/actions/runs/{id}/jobs?filter=latest&per_page=100`.
   Full-mode proof: the gate job (name equals the gate constant) is `success`;
   at least one job whose name starts with the full-leg constant followed by
   ` (` exists and every such leg is `success`; the selected job is `skipped`.
   A selected-mode success is not an anchor (D7).
6. Any non-200, network error, JSON parse error, or `total_count` larger than
   the entries returned ends the search with `reason=api-<status or error>` or
   `reason=pagination` — never a skip to the next candidate.
7. Anchor S found: run `select-suites.mjs --delta-base S --head H`. A
   DELTA_REFUSED line gives `reason=delta-refused:<reason>` (whole-PR lines
   printed). Otherwise print `WHOLE_PR <first whole-PR line>` (prefixed so it
   never matches `^FULL_RUN`), the delta lines, and
   `CARRY_FORWARD sha=<S> run=<id> url=<html_url>`.

The three job-name constants are exported and TEST-1721 pins them equal to the
`name:` values in skill-suite.yml.

Workflow edits (select job only, plus D2):
- job-level `permissions: { contents: read, actions: read }`;
- step env `GITHUB_TOKEN: ${{ github.token }}`, `BASE_REF`, `EVENT_PATH`;
- the line `OUT="$(node .aai/scripts/select-suites.mjs --base-ref ...)"` becomes
  `OUT="$(node .aai/scripts/ci-select.mjs --base-ref "origin/$BASE_REF" --event "$GITHUB_EVENT_PATH" --repo "$GITHUB_REPOSITORY" --workflow-file skill-suite.yml)"`;
- after `echo "$OUT"`, a carry-forward line is appended to
  `$GITHUB_STEP_SUMMARY` when present. The `grep -q '^FULL_RUN'`, mode and
  SUITES lines stay byte-identical; non-PR and `ci-full` branches are untouched.

### D6 — Evidence route: local evidence, rescued at close (Batch E)

Chosen route: runtime evidence stays local and gitignored. Evidence cells cite
`docs/ai/reports/...`, `docs/ai/tdd/...` or `docs/ai/validation/...` paths; when
close-work-item runs from a linked worktree, cited evidence that exists only in
that worktree is copied into the main checkout (still gitignored, never staged),
so the CHANGE-0131 question "do the cited bytes exist somewhere that outlives
the worktree" is answered yes without a commit.

Mechanics (close-work-item.mjs, helper in lib/evidence-paths.mjs):
- After `evaluateEvidencePathGate`, when realpath(ROOT) differs from
  evidenceRoot: rescue candidates = unresolved tokens that exist under ROOT
  (lstat: regular file or directory containing no symlink), are reported by
  `ignoredUntracked` or `trackedIgnored` in ROOT, and are ignored by repository
  rules in evidenceRoot too. Candidates count as resolved for the gate verdict.
- Refuse (enforce dial, exit 5) still happens before any write and copies
  nothing. Otherwise, before the first doc write: `fs.cpSync` with
  `errorOnExist: true, force: false`, recursive for directories, parents
  created. A copy failure returns that token to unresolved and re-evaluates the
  gate (warn, or exit 5 under enforce with no doc written).
- One stdout line per copy:
  `close-work-item: evidence rescued — <token> (worktree-only, gitignored) copied to the main checkout`.
- `--dry-run` JSON gains `evidencePathGate.rescue: [{token, from, to}]` and
  copies nothing.
- A cited NON-ignored worktree-only path still warns exactly as today (that
  evidence belongs in the branch, not in a local folder).
- close-work-item.mjs is hash-pinned (tests/skills/lib/close-work-item-pin.sh,
  four suites). All edits to it land in ONE commit; the new allowlist entry is
  written LAST and states that exit codes 0-8 are unchanged, the rescue precedes
  the D6 snapshot/rollback transaction (rescued copies are outside it and are
  not rolled back: they are gitignored local evidence), and the gate still
  evaluates before any doc write.

Canon text (Spec-AC-11): one line each, literal prefix `LOCAL EVIDENCE:`, in
VALIDATION step 6, SKILL_TDD (where it says to save logs to docs/ai/tdd), and
SKILL_PR step 4c: "cite runtime evidence (docs/ai/reports, docs/ai/tdd,
docs/ai/validation) by path; never `git add -f` it — close-work-item.mjs copies
worktree-only cited evidence into the main checkout; a project that wants shared
evidence uses a project-owned path outside those folders."

Rejected route: a committed, project-owned durable evidence folder that the gate
and prompts point to. Rejected because (1) it is exactly what PR #434 did and
cost 102 files and +12,962 lines in one post-validation commit and a full
re-run; (2) the repository is public and those reports carry local environment
details (owner e-mail 20 times, ~/.codex session paths, runtime paths); (3) it
reverses the standing .gitignore contract ("Durable evidence lives in AC Status
tables and EVENTS.jsonl, not in these logs"); (4) every ride's evidence would
then be a PR diff that the selector must classify. Also rejected: treating any
gitignored citation as resolved without existence (re-opens the CHANGE-0127
hole: evidence silently lost with the worktree).

### D7 — What counts as a covering run (v1)

Only a successful FULL-mode run anchors. A successful selected-mode run is not
an anchor in v1: its suite list is not recoverable from the jobs API without a
new artifact, and delta mode only matters when whole-PR selection is FULL_RUN
(step 1), which means some earlier head of this PR, or this head, needed a full
run. Because the anchor search walks back past failed and selected-mode runs to
the newest full-mode success, a chain of carry-forward runs keeps anchoring on
the same full run and the delta grows to include every eligible commit since —
all of which are re-selected. No transitivity is needed.

### D8 — Batch order (owner priority: CI check first)

- Batch A (first push, standalone): D1 `--all` mode, D2 job plus gate line,
  cleanup of the tracked ignored paths, PROFILES row, suite-map row for the new
  suite and script; TEST-1700..1705. Testable alone: RED is
  `tracked-ignored.mjs --all` exit 1 listing the 86 on base; GREEN after the
  cleanup. Full local sweep plus a full CI run on this push.
- Batch B: D1 `--staged` mode, D3 pre-commit sh/ps1 and check-committed-scope;
  TEST-1706..1710.
- Batch C: D4; TEST-1711..1716, TEST-1727, TEST-1728.
- Batch D: D5; TEST-1720..1726.
- Batch E: D6 and canon text, diet ledger, TEST-012 bump, close-work-item re-pin
  last; TEST-1730..1734.
- Default delivery: one work item, one PR, Batch A as the first push so the
  server-side check runs from the first CI run. Merging Batch A as its own PR
  first would need this spec split (HITL-4).

### Crossings (seams) and residual risks

- S1 workflow YAML to script: TEST-1704 extracts the `run:` text of the
  `tracked-ignored` job from skill-suite.yml and executes it against a fixture
  repo (red with a force-added file, green clean).
- S2 hook to pre-commit-checks to tracked-ignored.mjs: TEST-1709 installs the
  real hook in a fixture and attempts a real `git commit`.
- S3 selector output to YAML mode derivation: TEST-1725 feeds ci-select output
  through the YAML's own mode/SUITES lines (extracted from the file) and asserts
  mode and suites for a delta cell and a fallback cell.
- S4 close-work-item to main checkout: TEST-1730 uses a real main checkout plus
  `git worktree add` fixture; asserts on the main side.
- S5 CHECK 9 placement versus TEST-809's awk window: re-run
  test-aai-doc-numbering.sh.
- S6 cleanup versus suites that read docs/ai/tdd in the real repo
  (test-aai-tdd-evidence self-seeds; others unknown): full sweep on Batch A.
- R1 pulling clones lose the untracked files from disk (D2 recovery command).
- R2 rules read from worktree .gitignore files: a commit whose staged .gitignore
  differs from its worktree copy is judged by the worktree copy (TOCTOU). The CI
  check reads the committed tree and is the backstop.
- R3 the anchor run tested a merge with an older base. Branch protection has
  `strict: false`, so merging a PR tested against an older base is already
  allowed; push-to-main always runs full. Not narrowed further in v1.
- R4 a PR can edit ci-select.mjs or the workflow to skip its own tests — equally
  true of select-suites.mjs and the workflow today; the security boundary
  remains review. Any such edit is ineligible in a delta, so it cannot ride a
  carry-forward.
- R5 native-worktree-seed (Windows) and self-hosting smoke still run on every
  push; carry-forward saves only the 4-shard sweep. Suggested follow-up
  (suggested: fu-delta-skip-native-seed).
- R6 job display names are matched by string; a rename without updating the
  constants makes every anchor search fail safe (no carry-forward), and
  TEST-1721 catches the drift.

## Test Plan

All suites are bash 3.2 compatible, run with `env -u AAI_ROLE`, build fixture
repos with `git init -b main` and their own `user.email`/`user.name`, guard every
`cd`/`git -C` target as non-empty and absolute, and never touch the real repo
except the read-only TEST-1705.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-1700 | Spec-AC-01 | integration | tests/skills/test-aai-tracked-ignored.sh | Fixture repo: force-added ignored file gives exit 1 and one TRACKED_IGNORED line naming path and .gitignore rule; negation: clean repo gives exit 0 and `none checked=<n>` with n above 0 | `sed:s/process\.exit\(1\);/process.exit(0);/` in .aai/scripts/tracked-ignored.mjs (`--all` exits 0 after printing TRACKED_IGNORED lines) | green |
| TEST-1701 | Spec-AC-01 | integration | tests/skills/test-aai-tracked-ignored.sh | Nested sub/.gitignore match is reported; `!docs/ai/reports/.gitkeep` re-include is not reported | `sed:s/--exclude-per-directory=.gitignore/--exclude-from=.gitignore/` in .aai/scripts/tracked-ignored.mjs | green |
| TEST-1702 | Spec-AC-01 | integration | tests/skills/test-aai-tracked-ignored.sh | Paths ignored only by fixture core.excludesFile or .git/info/exclude are not reported (repo rules only); `--rev` reads that revision via a temporary index and leaves the real index byte-identical | `sed:s/--exclude-per-directory=.gitignore/--exclude-standard/` in .aai/scripts/tracked-ignored.mjs | green |
| TEST-1703 | Spec-AC-01 | static | tests/skills/test-aai-tracked-ignored.sh | skill-suite.yml: job tracked-ignored exists with no `if:`, runs `tracked-ignored.mjs --all`; gate needs it and fails on its non-success; required gate name unchanged | `sed:s/needs\.tracked-ignored\.result/needs.select.result/` in .github/workflows/skill-suite.yml (the gate no longer checks the tracked-ignored job) | green |
| TEST-1704 | Spec-AC-01 | integration | tests/skills/test-aai-tracked-ignored.sh | SEAM S1: extract the job's run text from the YAML and execute it in fixture repos; red with a force-added file, green clean | `sed:s/(node \.aai\/scripts\/tracked-ignored\.mjs --all)/if $1; then :; fi/` in .github/workflows/skill-suite.yml (job exit forced to 0) | green |
| TEST-1705 | Spec-AC-02 | integration | tests/skills/test-aai-tracked-ignored.sh | Live tree: `tracked-ignored.mjs --all` exits 0 and `git -c core.excludesFile=/dev/null ls-files -ci --exclude-standard` prints nothing; RED on base lists the 86 docs/ai/tdd paths | `sed:s/docs\/ai\/tdd\/\*\*/README.md/` on .gitignore (a tracked file becomes ignored) | green |
| TEST-1706 | Spec-AC-03 | integration | tests/skills/test-aai-tracked-ignored.sh | pre-commit-checks.sh in fixture: `git add -f` of ignored path gives exit 1 naming path, rule and `!` remedy; negation: same commit without it exits 0 | `sed:s/error "Gitignored path staged/warn "Gitignored path staged/` in .aai/scripts/pre-commit-checks.sh (the CHECK 9 IGNORED_ADDED mapping becomes a warning) | green |
| TEST-1707 | Spec-AC-03 | integration | tests/skills/test-aai-tracked-ignored.sh | Cells: rename into ignored dir exits 1; modified tracked ignored path warns and exits 0, exits 1 with --strict; `git rm --cached` deletion exits 0; untouched pre-existing tracked ignored path gives count warning; global-excludes-only path exits 0 | `sed:s/'--no-renames',//` in .aai/scripts/tracked-ignored.mjs (the staged diff detects renames again) | green |
| TEST-1708 | Spec-AC-03 | integration | tests/skills/test-aai-tracked-ignored.sh | pre-commit-checks.ps1 under pwsh on the TEST-1706 and TEST-1707 cells gives identical exit codes; named SKIP only when pwsh is absent (ubuntu CI has pwsh) | `sed:s/Write-Error-Check "Gitignored path staged/Write-Warn-Check "Gitignored path staged/` in .aai/scripts/pre-commit-checks.ps1 (the CHECK 9 IGNORED_ADDED mapping becomes a warning) | green |
| TEST-1709 | Spec-AC-03 | integration | tests/skills/test-aai-tracked-ignored.sh | SEAM S2: real install-pre-commit-hook.sh in fixture, `git add -f` ignored file then `git commit` fails and `git rev-list --count HEAD` is unchanged; positive control: a normal commit succeeds | `sed:s/node "\$TRACKED_IGNORED_SCRIPT" --staged/true/` in .aai/scripts/pre-commit-checks.sh (the CHECK 9 block no longer invokes tracked-ignored.mjs) | green |
| TEST-1710 | Spec-AC-04 | integration | tests/skills/test-aai-tracked-ignored.sh | check-committed-scope on a scope dir holding a tracked ignored file exits 1 with `(tracked-ignored)` in plain and --strict and with `--rev HEAD`; negation: same scope without it exits 0 | `sed:s/if \(tiPaths\.length\) \{/if (a.strict) {/` in .aai/scripts/check-committed-scope.mjs (the trackedIgnored call is skipped when `--strict` is absent) | green |
| TEST-1711 | Spec-AC-05 | unit | tests/skills/test-aai-suite-select.sh | `--files-from` with only docs/ai/reports paths gives CORE only, DROPPED all non-core, no FULL_RUN; negation: same list plus an unmapped path gives FULL_RUN reason=unmapped naming it | `sed:s/if \(inertGlobs\.some\(\(g\) => matchesGlob\(path, g\)\)\) continue;//` in .aai/scripts/select-suites.mjs (the inert check leaves the per-path loop) | green |
| TEST-1712 | Spec-AC-05 | unit | tests/skills/test-aai-suite-select.sh | Precedence: inert path also matched by a fixture suite glob selects nothing; protected-l3 and shared-lib still FULL_RUN; a map without inert_globs selects byte-identically to the base map on the TEST-001 fixtures | `sed:s/if \(protectedL3\.includes\(path\)\) return/if (false) return/` in .aai/scripts/select-suites.mjs (protected-l3 no longer outranks inert) | green |
| TEST-1713 | Spec-AC-05 | static | tests/skills/test-aai-suite-select.sh | Real suite-map: every inert glob is `<dir>/**` and `<dir>/probe` is ignored by the repo .gitignore; one representative path per carry_forward glob classifies without FULL_RUN in whole-PR mode | `sed:s/  - docs\/ai\/reports\/\*\*/  - docs\/**/` in tests/skills/suite-map.yaml inert_globs | green |
| TEST-1714 | Spec-AC-06 | integration | tests/skills/test-aai-suite-select.sh | Real git fixture S then H touching only EVENTS.jsonl and docs/INDEX.md: `--delta-base S --head H` prints DELTA base=S, CORE, SELECTED for those paths only, DROPPED | `sed:s/'--no-renames', baseSha, headSha/'--no-renames', baseSha + '...HEAD'/` in .aai/scripts/select-suites.mjs (the delta diffs S...HEAD instead of S H) | green |
| TEST-1715 | Spec-AC-06 | integration | tests/skills/test-aai-suite-select.sh | Table of ineligible delta cells (.aai/scripts/x.mjs, tests/skills/test-aai-x.sh, .aai/X.prompt.md, .github/workflows/y.yml, protected .aai/scripts/state.mjs, unmapped zz/u.txt): each prints one DELTA_REFUSED reason=ineligible naming the path and no CORE line | `sed:s/ctx\.carryGlobs\.some\(\(g\) => matchesGlob\(p, g\)\)/true/` in .aai/scripts/select-suites.mjs (carry_forward_globs match every path) | green |
| TEST-1716 | Spec-AC-06 | integration | tests/skills/test-aai-suite-select.sh | Force-push fixture where S is not an ancestor of H gives DELTA_REFUSED reason=not-ancestor; unknown sha gives reason=internal-error; exit 0 in every cell | `sed:s/if \(!ancestor\) return deltaRefuse\('not-ancestor'\);//` in .aai/scripts/select-suites.mjs (the is-ancestor refusal is removed) | green |
| TEST-1720 | Spec-AC-07 | integration | tests/skills/test-aai-ci-carry-forward.sh | Event fixture (synchronize) plus API fixture: newest candidate has a failed run, older one a full-mode success; output has delta lines, `CARRY_FORWARD sha=<S> run=<id> url=` and no line starting FULL_RUN; request log lists exactly the runs query with event, status, full head_sha and the jobs query with filter=latest | `sed:s/r\.conclusion === 'success'/r.conclusion === 'failure'/` in .aai/scripts/ci-select.mjs (a failed run is accepted instead of a successful one) | green |
| TEST-1721 | Spec-AC-07 | static | tests/skills/test-aai-ci-carry-forward.sh | ci-select.mjs gate, full-leg and selected job-name constants equal the `name:` values in skill-suite.yml | `sed:s/full framework, via/full framework via/` in .aai/scripts/ci-select.mjs (the full-leg constant drifts from the workflow name) | green |
| TEST-1722 | Spec-AC-07 | static | tests/skills/test-aai-ci-carry-forward.sh | select job declares `actions: read` and `contents: read`, passes `github.token` as GITHUB_TOKEN, invokes ci-select.mjs without --api-fixture or --request-log, and references no `secrets.` value | `sed:s/actions: read/actions: none/` in .github/workflows/skill-suite.yml (the select job loses the actions read scope) | green |
| TEST-1723 | Spec-AC-08 | integration | tests/skills/test-aai-ci-carry-forward.sh | Fail-safe table, one fixture each: action opened, action reopened, no token, HTTP 403, HTTP 500, malformed JSON, total_count above entries, candidate cap 20 exceeded: selector lines equal `select-suites.mjs --base-ref` output byte for byte, plus `CARRY_FORWARD none reason=<cell>` | `sed:s/if \(r\.status !== 200\) throw/if (r.status !== 200) return []; throw/` in .aai/scripts/ci-select.mjs (an API error moves on to the next candidate instead of stopping) | green |
| TEST-1724 | Spec-AC-08 | integration | tests/skills/test-aai-ci-carry-forward.sh | Fail-safe table, anchor cells: success but selected-mode jobs, success with a failed full leg, head repo mismatch (fork), head branch mismatch, anchor not ancestor (force push), ineligible delta path: whole-PR lines identical plus named reason | `sed:s/return !!sel && sel\.conclusion === 'skipped';/return true;/` in .aai/scripts/ci-select.mjs (the selected-job skipped requirement leaves the full-mode proof) | green |
| TEST-1725 | Spec-AC-08 | integration | tests/skills/test-aai-ci-carry-forward.sh | SEAM S3: run the YAML's own mode and SUITES derivation lines (extracted from skill-suite.yml) over ci-select output: delta cell gives mode=selected with CORE plus delta suites; fallback cell gives mode=full | `sed:s/`WHOLE_PR \$\{first\}/`${first}/` in .aai/scripts/ci-select.mjs (the whole-PR FULL_RUN line is printed unprefixed in carry-forward mode) | green |
| TEST-1726 | Spec-AC-08 | static | tests/skills/test-aai-ci-carry-forward.sh | Whole-PR selected cell makes zero API requests (request log empty) while TEST-1720 made more than zero (positive control); non-PR and ci-full branches of the select step and the gate's mode logic equal the lines of the immutable base 045e632e (pinned SHA, never origin/main) | `sed:s/\{ none\('whole-pr-selected'\); return 0; \}/{ }/` in .aai/scripts/ci-select.mjs (the whole-PR selected early exit is removed, so the anchor search runs) | green |
| TEST-1727 | Spec-AC-09 | integration | tests/skills/test-aai-suite-select.sh | Replay tests/fixtures/ci-carry-forward/pr434-last-push-paths.txt (recorded 9d90d1e4..73359491 list, 102 paths) through `--files-from`, without and with docs/ai/reports and docs/ai/tdd paths: both give CORE plus SELECTED and no FULL_RUN | `sed:s/  - docs\/ai\/reports\/\*\*/  - docs\/ai\/reportz\/**/` in tests/skills/suite-map.yaml inert_globs (reports leave the inert set) | green |
| TEST-1728 | Spec-AC-09 | integration | tests/skills/test-aai-tracked-ignored.sh | Fixture with the repo .gitignore: `git add -f` of the first report path from the replay list then pre-commit-checks.sh exits 1 naming it | `sed:s/docs\/ai\/reports\/\*\*/docs\/ai\/reportz\/**/` on .gitignore (the real report rule is lost from the fixture copy) | green |
| TEST-1730 | Spec-AC-10 | integration | tests/skills/test-aai-close-work-item.sh | SEAM S4: fixture main checkout plus linked worktree; spec cites docs/ai/reports/VALIDATION-x.md present only in the worktree; close from the worktree: no evidence-path WARNING, one `evidence rescued` line, file present in main, `git ls-files -ci --exclude-per-directory=.gitignore` empty in both trees | `sed:s/const \{ copied, failed \} = copyEvidenceRescue\(evidenceRescue\);/const copied = [], failed = [];/` in .aai/scripts/close-work-item.mjs (the copy step is skipped while candidates still count as resolved) | green |
| TEST-1731 | Spec-AC-10 | integration | tests/skills/test-aai-close-work-item.sh | Negations: worktree-only cited NON-ignored path still warns as today; cited ignored path missing in both trees still warns; symlink token is not rescued and warns; existing destination is never overwritten | `sed:s/if \(!ignoredByRepoRules\([a-zA-Z]+, token, isDir, members\)\) continue;/;/g` in .aai/scripts/lib/evidence-paths.mjs (both ignored-by-repository-rules conditions are dropped from rescue candidates) | green |
| TEST-1732 | Spec-AC-10 | integration | tests/skills/test-aai-close-work-item.sh | --dry-run lists evidencePathGate.rescue and copies nothing; enforce dial with one unrescuable token exits 5 and copies nothing; exit-code contract and pin suites (doc-numbering TEST-029, follow-ups TEST-008) pass with the new allowlist entry | `sed:s/evidenceGate\.severity !== 'refuse' && evidenceRescue\.length > 0/evidenceRescue.length > 0/` in .aai/scripts/close-work-item.mjs (the copy runs even when the gate would refuse) | green |
| TEST-1733 | Spec-AC-11 | static | tests/skills/test-aai-tracked-ignored.sh | VALIDATION, SKILL_TDD and SKILL_PR each contain exactly one line starting `LOCAL EVIDENCE:` that names docs/ai/reports, docs/ai/tdd, docs/ai/validation and `git add -f` | `sed:s/\n   LOCAL EVIDENCE:[^\n]*//` in .aai/SKILL_PR.prompt.md (the LOCAL EVIDENCE line is deleted) | green |
| TEST-1734 | Spec-AC-11 | integration | tests/skills/test-aai-prompt-diet.sh | Prompt-diet TEST-010 and TEST-012 pass with the new itemized JUSTIFIED_ADDITIONS entry and bumped pin; layer-profiles TEST-001 passes with tracked-ignored.mjs and ci-select.mjs classified core | `sed:s/JUSTIFIED_ADDITIONS\+=\( "879 post-validation-pushes-reuse-test-results/JUSTIFIED_ADDITIONS+=( "0 other-ref/` in tests/skills/lib/prompt-diet-ledger.sh (the itemized LOCAL EVIDENCE ledger entry no longer carries its ref) | green |
| TEST-1738 | Spec-AC-08 | integration | tests/skills/test-aai-ci-carry-forward.sh | Anchor run bound to the current PR (PR #435 review): other PR number, retargeted base ref, moved base sha and empty `pull_requests` each give whole-PR lines plus `anchor-pr-mismatch` or `anchor-base-moved`; event without number or base gives `event-malformed`; positive control and a matching entry among several anchor | `sed:s/p\.base\.sha === pr\.base\.sha/true/` in .aai/scripts/ci-select.mjs (a moved base sha no longer disqualifies the anchor) | green |
| TEST-1739 | Spec-AC-01 | integration | tests/skills/test-aai-tracked-ignored.sh | `--rev` evaluates the requested revision's own .gitignore files (PR #435 review): a force-added `*.log` whose rule a later commit removed is reported for the first revision with the revision's rule text, a rule added only later does not flag the old revision, a dirty worktree .gitignore never leaks in, global and info excludes still do not count, and `check-committed-scope.mjs --rev` inherits it | `sed:s/materializeIgnoreFiles\(top, env, work\);//` in .aai/scripts/tracked-ignored.mjs (the revision's .gitignore files are never materialized) | green |

Notes:
- TEST-1728 mutates the fixture's copy of
  .gitignore (the real line is copied in by the test), so the real .gitignore is
  never edited (HAZ-RESTORE).
- New suites need suite-map rows (`aai-tracked-ignored`, `aai-ci-carry-forward`)
  whose globs include their scripts, the workflow, pre-commit-checks.sh/.ps1 and
  check-committed-scope.mjs; the hygiene pin requires a row per suite file.
- New test functions must be registered in each suite's main
  (check-test-registration hygiene).

## Verification

- V1 (Batch A): `env -u AAI_ROLE bash tests/skills/test-aai-tracked-ignored.sh`
  (TEST-1700..1705) exit 0; `node .aai/scripts/tracked-ignored.mjs --all` exit 0
  on the delivered tree (RED log on base listing 86 paths stored); full local
  sweep `AAI_TEST_TIMEOUT=3000 bash tests/skills/test-framework.sh` exit 0; CI run
  on the Batch A push: tracked-ignored job success, gate success.
- V2 (Batch B): same suite, TEST-1706..1710; `env -u AAI_ROLE bash
  tests/skills/test-aai-doc-numbering.sh` exit 0 (S5).
- V3 (Batch C): `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh`
  exit 0 including TEST-1711..1716, 1727; hygiene-pack exit 0.
- V4 (Batch D): `env -u AAI_ROLE bash tests/skills/test-aai-ci-carry-forward.sh`
  exit 0; on the PR, a ledger-only push after a full green head shows
  `CARRY_FORWARD sha=... run=...` in the select log and mode=selected (live
  observation recorded in the validation report, not a substitute for the
  fixtures).
- V5 (Batch E): test-aai-close-work-item.sh, test-aai-doc-numbering.sh,
  test-aai-follow-ups.sh, test-aai-doc-number-reservation.sh,
  test-aai-repo-tripwire.sh, test-aai-prompt-diet.sh, test-aai-layer-profiles.sh
  exit 0.
- V6: `node .aai/scripts/spec-lint.mjs --path <this spec>` clean;
  `node .aai/scripts/docs-audit.mjs --check --strict --no-event` clean; one full
  sweep before close (sweep cost discipline: selected suites plus CORE between
  rounds).
- PASS: every TEST green with stored RED and mutation records, every Spec-AC
  terminal, CI green on the final head.

## Evidence contract

- Per TEST: RED and GREEN logs under
  docs/ai/tdd/spec-post-validation-pushes-reuse-test-results/ with RED_CLASS
  lines; mutation records via `mutation-run.mjs` (`mutation-TEST-17xx.txt`).
  These stay local and gitignored (D6) and are never force-added.
- Validation: one docs/ai/reports/VALIDATION-<run_id>-post-validation-pushes-reuse-test-results.md
  with an admissible `aai-outcome-v1` block; CI run ids for the Batch A push and
  the final head recorded in it.
- Code review: report under docs/ai/reviews/ (committed by SKILL_CODE_REVIEW H4),
  L3 most-capable tier, plus the operator final-diff checkpoint.
- Commit SHAs or diff ranges are written by the close flip, not at hand-off.

### Evidence by strategy

| Strategy | Evidence this spec may demand |
|---|---|
| tdd / hybrid | stored RED artifact per AC-gating test (docs/ai/tdd/) plus the full verification matrix — unchanged |
| loop | per-TEST-xxx green runs; RED-proof observed, storage optional |
| direct | targeted regression tests green (exit codes) plus the scoped diff — NO stored RED artifact, NO matrix beyond the declared versions |
| untested | the recorded strategy rationale plus the scoped diff — no test suites demanded for the scope itself |

## HITL items (owner decisions, each with a recommended default)

- HITL-1 — D3 narrows intake AC-001 for MODIFIED tracked ignored paths (warn,
  blocking only under --strict) to keep SPEC-0209's deliberate downstream
  tracking working. Recommended: accept. Alternative: block modifications too.
- HITL-2 — Make `tracked-ignored guard` its own required context in branch
  protection. Recommended: not needed (the required gate already requires it).
- HITL-3 — The cleanup deletes the 86 files from any pulling clone's disk,
  including the shared main checkout. Recommended: accept; restore on demand
  with `git archive 045e632e docs/ai/tdd | tar -x`.
- HITL-4 — Delivery shape. Recommended: one PR, Batch A pushed first.
  Alternative: merge Batch A as its own PR first (requires splitting this spec).

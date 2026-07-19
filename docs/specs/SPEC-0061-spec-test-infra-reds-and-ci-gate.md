---
id: spec-test-infra-reds-and-ci-gate
type: spec
number: 61
status: done
ceremony_level: 2
links:
  requirement: test-infra-reds-and-ci-gate
  rfc: null
  pr:
    - 116
  commits:
    - afc688df6d9d8f0ebb217f7b7ce9b26ab4a9db09
---

# Implementation Spec — Fix three hidden test-infra reds and gate the skill suite in CI

SPEC-FROZEN: true

## Links
- Requirement / intake: docs/issues/CHANGE-0042-test-infra-reds-and-ci-gate.md
- Decision records: RFC-0009 (ceremony levels); spec spec-layer-profiles (PROFILES.yaml classification rule)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template

## Implementation strategy
- Strategy: hybrid
- Rationale: AC-002 (the worktree `pipefail`/SIGPIPE false-failure) is a bug fix
  that needs durable regression proof and where both post-fix assertions must
  stay meaningful — treat it TDD-style (observe the RED, fix at cause, prove
  GREEN, prove neither assertion was neutralised). AC-001 (manifest
  classification), AC-003 (git mode bit) and AC-004 (new CI workflow) are
  mechanical / configuration wiring whose enforcing gates already exist and
  already fail RED on `main` today (AC-001/003) or are additive config (AC-004)
  — loop-style implement-then-verify is the right signal there. Mixed ⇒ hybrid.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: Four independent, surgical single-purpose edits (a YAML
  manifest, one test file, one script's git mode, one new CI file) — no shared
  runtime state, no migration, no protected surface. Work already proceeds on a
  dedicated feature branch (`feat/test-infra-reds-and-ci-gate`), which supplies
  the practical isolation; a separate worktree is useful for parallelism but not
  required for safety. `optional` does not block implementation when the user
  decision is left at `undecided`.
- User decision: undecided (inline on the current feature branch is an
  acceptable override; user confirms at Implementation Preparation)
- Base ref: main
- Worktree branch/path: n/a unless user elects a worktree
- Inline review scope: `.aai/system/PROFILES.yaml`
  `tests/skills/test-aai-worktree.sh` `.aai/scripts/aai-sync.sh`
  `.github/workflows/skill-suite.yml` (new)

## Acceptance Criteria Mapping

- Maps to: AC-001 (intake)
  - Spec-AC-01: The six currently-unclassified vendored files
    (`.aai/scripts/close-work-item.mjs`, `reconcile-telemetry.mjs`,
    `secrets-preflight.mjs`, `tdd-evidence-check.mjs`, `aai-reap-tests.ps1`,
    `aai-run-tests.ps1`) are added to the `core:` list of
    `.aai/system/PROFILES.yaml`, preserving the exact two-space-dash indentation
    contract, so the manifest classifies 100% of the live `.aai` tree, the two
    lists stay disjoint, and no stale entries exist.
  - Verification: `./tests/skills/test-aai-layer-profiles.sh` → exit 0
    (TEST-001 conformance + TEST-003 core-exact-set both pass).

- Maps to: AC-002 (intake)
  - Spec-AC-02: In `tests/skills/test-aai-worktree.sh` the two `git log --oneline
    | grep -q "Add login feature"` pipelines (present-in-feature at ~line 232,
    absent-in-main at ~line 245) are rewritten to first capture `git log`
    output into a variable, then `grep` that variable — so the `grep` exit
    status reflects only the match/no-match, never a SIGPIPE-terminated `git
    log` (141) propagated by `set -o pipefail`. BOTH assertions remain
    meaningful: the commit is asserted PRESENT in the feature branch AND ABSENT
    in main (no `|| true`, no assertion neutralised).
  - Verification: `./tests/skills/test-aai-worktree.sh` → exit 0, run reliably
    (TEST-002); and a structural check that neither isolation assertion pipes
    `git log` straight into `grep -q` and that both branch conditions still
    exist (TEST-003).

- Maps to: AC-003 (intake)
  - Spec-AC-03: `.aai/scripts/aai-sync.sh` is tracked with git mode 100755
    (set via `git update-index --chmod=+x`), with no CRLF / line-ending or
    content churn, so a direct `"$ROOT/.aai/scripts/aai-sync.sh" "$TARGET"`
    invocation is executable.
  - Verification: `git ls-files -s .aai/scripts/aai-sync.sh` → mode `100755`
    (TEST-004); `./tests/self-hosting/test-self-hosting-smoke.sh` → exit 0, no
    "Permission denied" (TEST-005).

- Maps to: AC-004 (intake)
  - Spec-AC-04: A new workflow `.github/workflows/skill-suite.yml` exists,
    is valid parseable YAML, triggers on `push` and `pull_request`, checks out
    full history (`fetch-depth: 0`, required by the layer-profiles suite's
    `git log -S` / `git show <sha>^` history probe) with Node available, runs
    the `tests/skills/` suite honouring each suite's own shebang (executed via
    `bash <file>` / the `test-framework.sh` aggregate runner — NOT forced `sh`),
    and fails the job on any red suite (exit code propagated; 42 = skip). The
    slow self-hosting smoke runs as a SEPARATE job with an explicit
    `timeout-minutes`.
  - Verification: the workflow file parses (TEST-006) and its run step invokes
    the `tests/skills/` suite without forcing `sh`; on push/PR the job is
    present in GitHub Actions and goes green once AC-001..003 land.

## Constitution deviations

None.

<!-- Article-by-article at freeze: (1) Evidence — every AC has an executable
verification command producing a real exit code, no PASS claimed here. (2)
Simplicity — smallest edits that clear each red; no speculative refactor of the
test framework (explicitly out of scope). (3) Portability — all four artifacts
are plain git-diffable files; the workflow is standard GitHub Actions YAML; the
mode change is a git index attribute. (4) Degrade & report — the CI honours the
42 skip convention (warn, not fail) mirroring ps1-quality.yml. (5) Additive —
manifest edit is additive (six files ADDED to core; nothing reclassified),
worktree edit is behaviour-preserving, the workflow is net-new, the mode bit is
a restore. (6) Single-writer state — no STATE.yaml hand-edit; state transitions
go through state.mjs. (7) Operator-only merge — spec plans a PR, never a merge.
No deviations. -->

## Acceptance Criteria Status

| Spec-AC    | Description                                             | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | 6 files classified `core` in PROFILES.yaml; layer-profiles green | done | docs/ai/tdd/red-20260719T105546Z-test-infra-reds-ac001-layer-profiles.log; docs/ai/tdd/green-20260719T105747Z-test-infra-reds-ac001-layer-profiles.log | — | RED confirmed on main (6 unclassified); GREEN: `bash tests/skills/test-aai-layer-profiles.sh` exit 0 |
| Spec-AC-02 | Worktree SIGPIPE false-failure fixed; both assertions meaningful | done | docs/ai/tdd/red-20260719T105553Z-test-infra-reds-ac002-worktree-sigpipe.log; docs/ai/tdd/green-20260719T105814Z-test-infra-reds-ac002-worktree-sigpipe.log | — | RED observed live ("Commit not found in feature branch"); GREEN: 3x reruns exit 0; TEST-003 static check confirms no live git-log-into-grep-q pipe remains, both branch senses preserved |
| Spec-AC-03 | aai-sync.sh git mode 100755; self-hosting-smoke green   | done | docs/ai/tdd/red-20260719T105548Z-test-infra-reds-ac003-selfhosting-mode.log; docs/ai/tdd/green-20260719T105815Z-test-infra-reds-ac003-selfhosting-mode.log | — | RED confirmed on main (100644 → Permission denied); GREEN: `git ls-files -s` = 100755, smoke exit 0. Also restored `.aai/scripts/validate-skills.sh` to 100755 — same masked root cause, invoked directly by the same smoke test one line later; was hidden behind the aai-sync.sh Permission denied until that was fixed |
| Spec-AC-04 | CI workflow runs tests/skills/ on push+PR, fails on red | done | .github/workflows/skill-suite.yml; docs/ai/tdd/green-20260719T105919Z-test-infra-reds-ac004-ci-workflow.log | — | RED = workflow absent (confirmed: no such file pre-change); GREEN: YAML parses, on.push+on.pull_request+on.workflow_dispatch present, `skills` job runs tests/skills via bash test-framework.sh (never forced sh), separate `self-hosting-smoke` job with its own timeout |

Status values: planned | implementing | done | deferred | blocked | rejected

## Classification decision (Spec-AC-01 — CLASSIFICATION RULE application)

Per the PROFILES.yaml CLASSIFICATION RULE (spec spec-layer-profiles D2), `core`
= the workflow engine (orchestration/role/intake prompts, state+docs+index+
events scripts and their closure, gates, loop/HITL/flush, distribution & health,
templates, canon); `extended` = reporting/publishing, integrations, one-off
maintenance, session conveniences, brownfield, deprecated, self-hosting QA. All
six unclassified files are engine, therefore **core**:

| File | Role (evidence) | Referenced by (all core prompts) | Verdict |
|------|-----------------|----------------------------------|---------|
| `close-work-item.mjs` | deterministic close-ceremony engine (SPEC-0053) | SKILL_PR, VALIDATION, METRICS_FLUSH | core |
| `reconcile-telemetry.mjs` | PR-time reconciler of COMMITTED EVENTS/METRICS ledgers (SPEC-0055) — an events/flush engine script | SKILL_PR | core |
| `secrets-preflight.mjs` | intake-time secrets existence gate (SPEC-0045) | INTAKE_COMMON | core |
| `tdd-evidence-check.mjs` | TDD RED-evidence gate (SPEC-0044); rule names "gates (TDD/…)" as core | SKILL_TDD, VALIDATION | core |
| `aai-reap-tests.ps1` | PowerShell mirror of the test-runner reaper; its `.sh` sibling `aai-reap-tests.sh` is already `core` | SKILL_LOOP, VALIDATION, SKILL_BOOTSTRAP | core |
| `aai-run-tests.ps1` | PowerShell mirror of the test-runner; its `.sh` sibling `aai-run-tests.sh` is already `core` | SKILL_VERIFY, SKILL_LOOP, VALIDATION, DESLOP, BOOTSTRAP | core |

No file is consumed by an extended-only prompt; no `extended` reclassification.

## Implementation plan

Components / modules affected (four independent surfaces):

1. `.aai/system/PROFILES.yaml` — insert the six paths into the `core:` list in
   sorted position, each as `  - <path>` (two-space dash). Do not touch
   `extended:`. The added `.mjs`/`.ps1` scripts already exist on disk; the
   manifest just did not list them.
2. `tests/skills/test-aai-worktree.sh` — at the two isolation assertions, replace
   `if ! git log --oneline | grep -q "Add login feature"` (present-in-feature)
   and `if git log --oneline | grep -q "Add login feature"` (absent-in-main)
   with a captured-output form, e.g. `log_out="$(git log --oneline)"` then
   `grep -q "Add login feature" <<<"$log_out"` — the `grep` now consumes a
   here-string/variable, so no producer can receive SIGPIPE. Keep the sense of
   both conditions (present ⇒ pass; absent ⇒ pass). No `|| true`.
3. `.aai/scripts/aai-sync.sh` — `git update-index --chmod=+x
   .aai/scripts/aai-sync.sh`; verify `git ls-files -s` shows `100755` and `git
   diff` shows no content/line-ending change.
4. `.github/workflows/skill-suite.yml` (new) — mirror the house style of
   `ps1-quality.yml` / `docs-numbering.yml`: `on: push` (branches: [main]) +
   `pull_request` + `workflow_dispatch`; `permissions: contents: read`;
   `actions/checkout@v4` with `fetch-depth: 0`; `actions/setup-node@v4`
   (node 20). Two jobs:
   - `skills` (ubuntu-latest): run the `tests/skills/` suite honouring each
     suite's shebang — either the aggregate `bash tests/skills/test-framework.sh`
     (it already runs each suite via `bash "$test_file"`) or an explicit
     `for f in tests/skills/*.sh; do bash "$f"; …` loop that treats exit 42 as
     a warn-skip and any other non-zero as a job failure. Never `sh <file>`.
     `timeout-minutes:` generous (heavy suites, docs-audit ~119s internally).
   - `self-hosting-smoke` (ubuntu-latest, separate job): `bash
     tests/self-hosting/test-self-hosting-smoke.sh` with its own
     `timeout-minutes` (~10; the bootstrapped copy re-runs the suite, ~2-3 min).
     Separate job isolates the slow signal and gives it an independent timeout.

Data flows / seams:
- SEAM A — PROFILES.yaml `core` list → `aai-sync.sh` / `aai-sync.ps1` `--profile
  core` copy-set (adding 6 files to `core` grows what a core sync installs) and →
  `test-aai-layer-profiles.sh` (the manifest consumer/enforcer). Crossed
  end-to-end by TEST-001 (conformance) whose suite also runs TEST-003
  `--profile core` = exact-manifest-set: producing the list on one side and
  asserting the installed file set on the other.
- SEAM B — `aai-sync.sh` git mode 100755 → `test-self-hosting-smoke.sh`, which
  EXECUTES the script directly (`"$ROOT/.aai/scripts/aai-sync.sh" "$TARGET"`).
  Crossed end-to-end by TEST-005 (mode wrong ⇒ Permission denied ⇒ red).
- SEAM C — the new workflow → the three fixed suites it runs. The workflow going
  green in Actions is the integration; locally validated by TEST-006 (parse +
  invocation-shape assertions).

Edge cases:
- The layer-profiles suite needs FULL git history (`git log -S 'PROFILES.yaml'`
  + `git show <sha>^:…`); a shallow checkout fails it ⇒ `fetch-depth: 0` is
  mandatory in the workflow (also documented as a constraint).
- Adding six files to `core` MUST NOT perturb TEST-002 (default==extended byte
  identity is about the whole tree, unchanged) — only the `core` copy-set (TEST-003)
  grows. The git mode change touches neither (tree_manifest digests content, not mode).
- `grep -q` here-string is bash-3.2 compatible (`<<<` is fine in bash 3.2); do
  not introduce bash-4 features (TECHNOLOGY constraint).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                   | Status  |
|----------|------------|-------------|-----------------------------------------------|-----------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-layer-profiles.sh       | Manifest classifies 100% of live `.aai` (TEST-001) & `--profile core` = exact set (TEST-003)  | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-worktree.sh             | Full worktree suite exits 0 reliably (no SIGPIPE false-failure under `set -o pipefail`)        | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-worktree.sh (static)    | Neither isolation assertion pipes `git log` straight into `grep -q`; both branch senses remain | green |
| TEST-004 | Spec-AC-03 | unit        | (git index)                                   | `git ls-files -s .aai/scripts/aai-sync.sh` reports mode `100755`                               | green |
| TEST-005 | Spec-AC-03 | integration | tests/self-hosting/test-self-hosting-smoke.sh | Self-hosting smoke exits 0; no "Permission denied" on aai-sync.sh                              | green |
| TEST-006 | Spec-AC-04 | e2e         | .github/workflows/skill-suite.yml (new)       | Workflow parses; has on.push+on.pull_request; runs tests/skills honouring shebang (not `sh`)   | green |
| TEST-007 | Spec-AC-01 | integration | tests/skills/test-aai-prompt-diet.sh + test-aai-verify-gate.sh | Regression guard: unaffected suites remain green (the core-set change has no collateral breakage) | green |

RED-proof obligation (per AC):
- Spec-AC-01: `test-aai-layer-profiles.sh` FAILS on `main` today (TEST-001 lists
  the six unclassified files) — RED already observed; confirm before GREEN.
- Spec-AC-02: the SIGPIPE false-failure is the observed RED (intake root cause,
  timing/order-sensitive because the match is the newest commit at line 1). The
  implementer MUST capture a real RED (rerun the suite / force the pipe-close
  condition) before crediting GREEN, per the RED-proof rule — a never-failed test
  proves nothing. TEST-003 additionally guards against a `|| true`-style GREEN
  that neutralises an assertion.
- Spec-AC-03: `git ls-files -s` shows `100644` today and `test-self-hosting-smoke.sh`
  fails with "Permission denied" — RED already observed.
- Spec-AC-04: the workflow is absent today (RED = no skill-suite gate); GREEN =
  file present, parseable, correctly wired.

## Verification
- `./tests/skills/test-aai-layer-profiles.sh` → exit 0
- `./tests/skills/test-aai-worktree.sh` → exit 0 (reliably)
- `git ls-files -s .aai/scripts/aai-sync.sh` → mode `100755`
- `./tests/self-hosting/test-self-hosting-smoke.sh` → exit 0
- Workflow parse, e.g. `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/skill-suite.yml'))"`
  (or `node`/`actionlint`) → exit 0; and `grep -Eq 'tests/skills' .github/workflows/skill-suite.yml`
  with NO forced `sh <file>` on the suite invocation.
- Regression: `./tests/skills/test-aai-prompt-diet.sh` and
  `./tests/skills/test-aai-verify-gate.sh` → exit 0.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal (`done`) status
  with commit-SHA evidence.

## Ceremony level

`ceremony_level: 2` (full pipeline — the template/RFC-0009 default). None of the
four touched paths (`.aai/system/PROFILES.yaml`,
`tests/skills/test-aai-worktree.sh`, `.aai/scripts/aai-sync.sh`,
`.github/workflows/skill-suite.yml`) appears in `protected_paths_l3`
(docs/ai/docs-audit.yaml lists only state.mjs, lib/state-engine.mjs,
lib/state-core.mjs, allocate-doc-number.mjs, pre-commit-checks.sh/.ps1,
WORKFLOW.md, CONSTITUTION.md) — so L3 is NOT forced. The scope is broader than a
single-surface L0/L1 fix (four independent files spanning CI config + the
distribution manifest + a distribution script's mode + a test), so it does not
qualify for a lightweight lane. ⇒ L2, no `Ceremony justification:` line required
(that line is only mandatory at L0/L1).

## Evidence contract
Per implementation / validation / TDD / review artifact record: ref_id
(`test-infra-reds-and-ci-gate`), the Spec-AC + TEST-xxx it satisfies, the exact
command run, its exit code / review verdict, the evidence path (log under
docs/ai/tdd/ or docs/ai/reports/), and the commit SHA / diff range.

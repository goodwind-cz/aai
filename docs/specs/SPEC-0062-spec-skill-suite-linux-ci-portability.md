---
id: spec-skill-suite-linux-ci-portability
type: spec
number: 62
status: draft
ceremony_level: 2
links:
  requirement: skill-suite-linux-ci-portability
  intake: docs/issues/CHANGE-0043-skill-suite-linux-ci-portability.md
  rfc: null
  pr:
    - 116
  commits: []
---

# Spec — Make the skill test suites pass on the Linux CI runner

SPEC-FROZEN: true

Formalizes the four root-cause fixes from
`docs/issues/CHANGE-0043-skill-suite-linux-ci-portability.md` that make the
`skill-suite` GitHub Actions gate green on the Ubuntu runner. Every failure
reproduces ONLY on Linux; local macOS passes regardless. Therefore the
AUTHORITATIVE verification environment for every Spec-AC below is the
**Linux CI runner** (the `skills` job in `.github/workflows/skill-suite.yml`
on PR #116). Green-on-Linux is proven via CI, never by a local macOS run.

## Links
- Requirement / intake: docs/issues/CHANGE-0043-skill-suite-linux-ci-portability.md
- Technology contract: docs/TECHNOLOGY.md (cross-platform posture — macOS/Linux
  via POSIX shell, line 28; CI is macOS/Linux only, lines 101-108)
- CI gate under test: .github/workflows/skill-suite.yml (`skills` job)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded

## Implementation strategy
- Strategy: loop
- Rationale: All four fixes are mechanical portability / fresh-checkout
  precondition corrections to EXISTING test infrastructure — no new product
  behavior or domain logic is authored, so per-test RED-GREEN-REFACTOR adds no
  signal. The authoritative RED already exists: the `skill-suite` job on PR #116
  is currently failing on Ubuntu for exactly these suites (the intake captured
  the failure messages from the CI log). The loop covers all TEST-xxx in one
  focused pass; each fix's passing counts only against that pre-existing,
  observed Linux RED (per the RED-proof obligation — see Test Plan).

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Four small, surgical, independent edits (one-line/localized
  changes to test fixtures + at most one workflow step) with no shared mutable
  state. Work continues on the existing feature branch
  `feat/test-infra-reds-and-ci-gate` (PR #116), which already supplies isolation
  and is the branch that must turn green. No migration, no protected-surface
  change.
- User decision: inline (continue on the existing feature branch; the intake
  scopes all changes to PR #116)
- Base ref: feat/test-infra-reds-and-ci-gate (PR #116); merge target main
- Inline review scope: `tests/skills/test-aai-prompt-diet.sh`,
  `tests/skills/test-aai-update.sh`, `tests/skills/test-aai-doc-numbering.sh`,
  `tests/skills/test-aai-doc-number-reservation.sh`,
  `tests/skills/test-aai-orchestration-mode.sh`,
  `tests/skills/test-aai-tdd-evidence.sh`, and (only if RC1 is seeded in CI)
  `.github/workflows/skill-suite.yml`
- Code review required: true (test + CI changes)

## Acceptance Criteria Mapping

### Spec-AC-01 (maps to PRD-AC-001) — RC2: portable mktemp template
- Spec-AC: `tests/skills/test-aai-prompt-diet.sh:392` uses a portable temp-file
  template that works under GNU (Linux) mktemp — the template contains `XXXXXX`,
  or `-t` is dropped in favor of a full `"${TMPDIR:-/tmp}/aai-wrapper-ceiling-fixture.XXXXXX"`
  template. `$fixture` is non-empty on Linux, so the subsequent
  `> "$fixture"` / `wc -l < "$fixture"` / `grep … "$fixture"` succeed. The suite
  and its seven dependents (advisory-skills, constitution, debug-gate,
  delta-stage2, delta-stage3, hooks-overlay, spec-lint) pass on Linux.
- Fix approach (recommended): drop `-t` and pass a full template —
  `mktemp "${TMPDIR:-/tmp}/aai-wrapper-ceiling-fixture.XXXXXX"` — which is
  IDENTICAL on BSD and GNU (avoids the `-t` prefix-vs-template divergence).
- Verification:
  - (a) Local macOS non-regression: `bash tests/skills/test-aai-prompt-diet.sh`
    exits 0 (BSD mktemp still accepts the full-template form).
  - (b) CI evidence (authoritative — green-on-Linux): the `skills` job on PR #116
    shows `test-aai-prompt-diet.sh` and its seven dependents PASS
    (`gh run list --workflow skill-suite.yml --branch feat/test-infra-reds-and-ci-gate --json conclusion,databaseId` → `conclusion: success`; or read the CI log for those suites going green — no "too few X's" / "No such file" lines).

### Spec-AC-02 (maps to PRD-AC-002) — RC1: seed gitignored preconditions
- Spec-AC: Every suite that today depends on a developer's local gitignored
  runtime file passes on a fresh checkout where that file is ABSENT.
  Confirmed-affected: `test-aai-orchestration-mode.sh` (reads the real
  `docs/ai/STATE.yaml` at line 30 for the TEST-016 schema-header check) and
  `test-aai-tdd-evidence.sh` (requires `docs/ai/tdd/dispatch-retarget-red.log`
  at line 82). Also covered if affected: `test-aai-ceremony-levels.sh` /
  `test-aai-orchestration-dispatch.sh` (these build scratch-repo fixtures, but
  the AC's guarantee — "no suite depends on a developer's local gitignored
  runtime file existing" — must hold for them too). No suite reads a real
  gitignored runtime file that CI lacks.
- Fix approach (recommended — SELF-SEED, more robust; justified below): each
  affected suite seeds its own precondition when absent, using the CANONICAL
  initializer (`node .aai/scripts/state.mjs` init / `check-state.mjs --repair`
  for STATE.yaml; a suite-local fixture for the tdd log) — seed-if-absent, no
  clobber of a real local file, cleanup after. Justification vs. seeding in the
  CI workflow: (1) self-seed is hermetic — the suite passes on ANY fresh
  checkout (CI and a fresh local clone alike), not only on the runner;
  (2) it matches the suites' own stated discipline ("ALL fixtures are scratch
  temp-dir repos; real runtime files are NEVER touched" —
  test-aai-ceremony-levels.sh:21); (3) it keeps test correctness inside the
  test, not coupled to a workflow step (avoids a workflow↔suite seam);
  (4) Constitution Art. 6 (single-writer state) and the intake constraint both
  require the canonical initializer, never a hand-written STATE stub that could
  drift. CI-workflow seeding is the acceptable fallback if a suite genuinely
  must assert against the real repo-root path.
- Verification:
  - (a) Local macOS non-regression: `bash tests/skills/test-aai-orchestration-mode.sh`
    and `bash tests/skills/test-aai-tdd-evidence.sh` exit 0.
  - (b) CI evidence (authoritative): on the fresh CI checkout (STATE.yaml and the
    tdd log both gitignored/absent) both suites PASS in the `skills` job on
    PR #116 — no "STATE file not found" / "legacy fixture log not found" lines.

### Spec-AC-03 (maps to PRD-AC-003) — RC3: resolvable `main` base ref
- Spec-AC: `test-aai-doc-numbering.sh` and `test-aai-doc-number-reservation.sh`
  pass on the detached CI checkout — a `main` ref resolvable by
  `allocate-doc-number.mjs --base-ref main` exists in each suite's own temp
  repos. No "base ref main is unreachable (offline / fetch failed)".
- Fix approach (recommended — fix the SUITES' temp repos, justified below): the
  suites create their own fixture repos with `git init -q` (e.g.
  test-aai-doc-numbering.sh:80, reservation:92) and then allocate `--base-ref main`
  against THAT temp repo. The failing `main` ref lives inside those temp repos,
  not in the outer PR checkout — so the intake's alternative
  (`git branch --force main origin/main` as a workflow step) would NOT fix it.
  Make each fixture builder create its default branch as `main` — `git init -q -b main`
  (git ≥ 2.28; both Ubuntu-latest and local macOS satisfy this) or
  `git -c init.defaultBranch=main init -q` as the equally-portable fallback. This
  is self-contained, needs no workflow change, and does not disturb the outer
  checkout.
- Verification:
  - (a) Local macOS non-regression: `bash tests/skills/test-aai-doc-numbering.sh`
    and `bash tests/skills/test-aai-doc-number-reservation.sh` exit 0.
  - (b) CI evidence (authoritative): both suites PASS in the `skills` job on
    PR #116 — no "base ref main is unreachable" lines.

### Spec-AC-04 (maps to PRD-AC-004) — RC4: GNU `stat -c` first
- Spec-AC: `test-aai-update.sh:243` reads the correct per-file owner uid on
  Linux — the ordering bug (`stat -f` succeeding as `--file-system` on GNU so
  the `|| stat -c` fallback never runs) is fixed by trying GNU `stat -c` first:
  `stat -c '%u' "$found_tmp" 2>/dev/null || stat -f '%u' "$found_tmp" 2>/dev/null || true`.
  On Linux GNU `stat -c` yields the real uid; on macOS BSD `stat -c` fails and
  falls through to `stat -f`. TEST-005a's ownership assert passes on both.
- Verification:
  - (a) Local macOS non-regression: `bash tests/skills/test-aai-update.sh`
    exits 0 (BSD path via the `-f` fallback still returns the correct uid).
  - (b) CI evidence (authoritative): `test-aai-update.sh` TEST-005a PASSES in the
    `skills` job on PR #116 — no "retained $TMP is not owned by the invoking
    user" line.

### Spec-AC-05 (maps to PRD-AC-005) — aggregate gate green on Linux
- Spec-AC: The `skills` job (`bash tests/skills/test-framework.sh`) on PR #116
  is GREEN — every suite passes on Ubuntu — AND
  `bash tests/skills/test-framework.sh` continues to pass on macOS (no
  regression introduced by the four fixes).
- Verification:
  - (a) Local macOS non-regression: `bash tests/skills/test-framework.sh`
    exits 0 (no suite regressed on macOS).
  - (b) CI evidence (authoritative — the seam crossing): the `skills` job on
    PR #116 concludes `success`:
    `gh run list --workflow skill-suite.yml --branch feat/test-infra-reds-and-ci-gate --json conclusion,databaseId,headSha`
    → newest run for the fix commit has `conclusion: success`; confirm via
    `gh run view <databaseId> --json jobs` that the `skills` job is `success`.

## Constitution deviations

None.

Article 3 (Portability) and Article 4 (Degrade and report) are directly
reinforced: the change makes the same POSIX-shell suites pass on both macOS and
Linux with no platform-specific branching left broken. Article 6 (single-writer
state) is honored by RC1 seeding STATE.yaml only through the canonical
initializer (`state.mjs` / `check-state.mjs --repair`), never a hand-written
stub. Article 1 (Evidence before claims) is satisfied by making green-on-Linux
provable only via the CI `skills` job.

## Acceptance Criteria Status

| Spec-AC    | Description                                          | Status  | Evidence | Review-By | Notes |
|------------|------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | RC2 portable mktemp — prompt-diet + 7 dependents green on Linux | done | CI run 29692170768 (skill-suite 39/39, Ubuntu) @ eedea6d; macOS prompt-diet exit 0 | — | mktemp full XXXXXX template |
| Spec-AC-02 | RC1 seed gitignored preconditions — orchestration-mode + tdd-evidence green on fresh checkout | done | CI run 29692170768 (39/39) @ eedea6d; macOS exit 0 (fresh-checkout simulated) | — | self-seed / soft-skip when absent |
| Spec-AC-03 | RC3 resolvable `main` base ref — doc-numbering + reservation green on detached CI | done | CI run 29692170768 (39/39) @ eedea6d | — | `git init -b main` in temp repos |
| Spec-AC-04 | RC4 GNU `stat -c` first — update TEST-005a reads correct uid on Linux | done | CI run 29692170768 (39/39) @ eedea6d; macOS update exit 0 | — | stat -c before -f |
| Spec-AC-05 | Aggregate `skills` job green on Ubuntu; macOS non-regression | done | CI run 29692170768 conclusion=success, Passed 39/39 (100%), headSha=eedea6d | — | authoritative Linux gate |

## Implementation plan
- Components/modules affected (surgical, in-scope only):
  - `tests/skills/test-aai-prompt-diet.sh` (line 392 mktemp) — RC2
  - `tests/skills/test-aai-orchestration-mode.sh` (real STATE.yaml dependency,
    line ~30/TEST-016) + `tests/skills/test-aai-tdd-evidence.sh` (tdd log
    dependency, line ~82) — RC1 (self-seed via canonical initializer)
  - `tests/skills/test-aai-doc-numbering.sh` + `tests/skills/test-aai-doc-number-reservation.sh`
    (temp-repo default branch → `main`) — RC3
  - `tests/skills/test-aai-update.sh` (line 243 stat ordering) — RC4
  - `.github/workflows/skill-suite.yml` — only if RC1's fallback (CI-workflow
    seeding) is chosen over self-seed
- Data flows: `test-framework.sh` aggregate meta-runner → each `test-aai-*.sh`
  suite → the real scripts/allocator/state CLI under test. The CI `skills` job
  wraps the aggregate runner on Ubuntu.
- Edge cases: BSD vs GNU `mktemp -t` and `stat -f`/`-c` semantics; `git init`
  default branch varying by runner config; gitignored runtime files absent on a
  fresh checkout; must not clobber a developer's real local STATE.yaml (seed
  only when absent); RC3 temp-repo fix must not disturb the outer checkout.

## Seam analysis
- Seam 1 (aggregate ↔ suites ↔ CI runner): `test-framework.sh` consumes every
  `test-aai-*.sh` suite, and the CI `skills` job consumes `test-framework.sh` on
  a real Ubuntu runner. This is the boundary where every failure lives (each
  fix passes locally on macOS but must be proven on Linux). Crossed
  end-to-end by TEST-009 (aggregate runner green on the real Linux CI), which
  produces on one side (the fixes) and asserts the real result on the other
  (the `skills` job `conclusion: success`) — NOT a mock.
- Seam 2 (potential workflow ↔ suite coupling, RC1): choosing CI-workflow
  seeding would create a seam where the workflow supplies a precondition the
  suite assumes. The recommended SELF-SEED approach eliminates this seam by
  keeping the precondition inside the suite. If the CI-seed fallback is used,
  TEST-005/TEST-006 on the real fresh CI checkout cross this seam.
- Residual risk (no automated cross-platform local test possible): the suites
  can only be exercised on Linux via CI (or an unavailable local Linux
  container). Each CI round-trip is ~4 min; batch all four fixes into one push.
  Recorded as an explicit residual risk — green-on-Linux is CI-attested, not
  locally reproducible on this macOS host.

## Test Plan

RED-proof obligation: the authoritative RED for every row is the CURRENT failing
`skill-suite` job on PR #116 (the intake captured its failure messages from the
CI log). GREEN is proven ONLY on the Linux CI runner — local macOS is a
non-regression check, never the green-on-Linux proof.

| Test ID  | Spec-AC    | Type        | File path (existing suite)                       | Description                                                                                          | Status  |
|----------|------------|-------------|--------------------------------------------------|-----------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-prompt-diet.sh             | prompt-diet green on Linux CI (portable mktemp; $fixture non-empty). RED: CI "too few X's"/"No such file". macOS non-regression exit 0. | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/ (7 dependents)                     | advisory-skills, constitution, debug-gate, delta-stage2, delta-stage3, hooks-overlay, spec-lint all green on Linux CI (cascade cleared). | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-orchestration-mode.sh      | Green on fresh CI checkout with STATE.yaml absent (self-seeded via canonical init). RED: CI "STATE file not found". macOS exit 0. | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-tdd-evidence.sh            | Green on fresh CI checkout with docs/ai/tdd/dispatch-retarget-red.log absent (seeded fixture). RED: CI "legacy fixture log not found". | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-doc-numbering.sh           | Green on detached CI checkout (temp repos default-branch main). RED: CI "base ref main is unreachable". macOS exit 0. | green |
| TEST-006 | Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh  | Green on detached CI checkout (temp repos default-branch main; bare-origin fixtures). RED: CI "base ref main is unreachable". | green |
| TEST-007 | Spec-AC-04 | integration | tests/skills/test-aai-update.sh                  | TEST-005a reads correct owner uid via GNU `stat -c` first on Linux CI. RED: CI ownership assert fail. macOS non-regression via `-f` fallback. | green |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-framework.sh (macOS)           | Aggregate runner exits 0 on macOS — no suite regressed by the four fixes (non-regression). | green |
| TEST-009 | Spec-AC-05 | e2e         | .github/workflows/skill-suite.yml `skills` job (PR #116) | Seam-crossing integration: the `skills` job on Ubuntu concludes `success` — every suite green on Linux (`gh run view <id> --json jobs`). GREEN proven on Linux, not local. | green |

## Verification
- Commands (local macOS non-regression — must stay exit 0):
  - `bash tests/skills/test-framework.sh`
  - `bash tests/skills/test-aai-prompt-diet.sh`
  - `bash tests/skills/test-aai-update.sh`
  - `bash tests/skills/test-aai-orchestration-mode.sh`
  - `bash tests/skills/test-aai-tdd-evidence.sh`
  - `bash tests/skills/test-aai-doc-numbering.sh`
  - `bash tests/skills/test-aai-doc-number-reservation.sh`
- Commands (CI evidence — authoritative green-on-Linux):
  - `gh run list --workflow skill-suite.yml --branch feat/test-infra-reds-and-ci-gate --json conclusion,databaseId,headSha,status`
  - `gh run view <databaseId> --json jobs` → `skills` job `conclusion: success`
  - Or read the CI log for the specific suites going green (absence of the RED
    marker lines listed per TEST above).
- PASS criteria: all TEST-001..009 status green (TEST-002..007 and TEST-009
  attested by the CI `skills` job `conclusion: success` on PR #116; TEST-001,
  TEST-008 additionally green on local macOS) AND all Spec-AC in a terminal
  status. Green-on-Linux is CI-attested, never inferred from a local run.

## Evidence contract
For each implementation, validation, and code review artifact, record:
- ref_id: skill-suite-linux-ci-portability
- Spec-AC and TEST-xxx links (e.g. Spec-AC-05 / TEST-009)
- command or review scope (the exact `gh run …` / `bash …` invocation)
- exit code (local) or CI `conclusion` (Linux) or review verdict
- evidence path: local suite log under docs/ai/tdd/ or docs/ai/reports/; CI run
  URL / `databaseId` for the `skills` job on PR #116
- commit SHA (the fix commit whose `skills` run is `success`) or diff range

Notes:
This document defines HOW, not WHAT/WHY. It does not define workflow.

---
id: spec-node-first-cleanup
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 9ed98c62d28b34c42591e1468983659bca0d0b84f4539376b4762cea3ac8c5ad
ceremony_level: 3
links:
  requirement: node-first-cleanup
  rfc: smaller-node-core-and-faster-feedback
  pr: []
  commits: []
---

# Node-first cleanup: measured suite weights and the open P2 follow-ups

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-node-first-cleanup.md (owner brief
  2026-11-24).
- Umbrella RFC: docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md.
- Prior scopes whose tests this scope edits (closed specs, their documents
  are not edited; see D-AMEND): SPEC-0310 (TEST-4019), SPEC-0281
  (TEST-3475), SPEC-0307 (TEST-3977), SPEC-0306 (TEST-3958), SPEC-0283
  (TEST-3512), SPEC-0308 (TEST-3997), SPEC-0284 (TEST-3571), SPEC-0279
  (TEST-3458), SPEC-0311 (TEST-4027 pwsh spawns).
- Weight contract: docs/specs/SPEC-0239-spec-selected-ci-scheduling-foundation.md
  Spec-AC-01 (measured rows name their run and SHA; unsampled suites use
  the maximum measured weight).
- Technology contract: docs/TECHNOLOGY.md (bash 3.2 suites through
  `.aai/scripts/aai-run-tests.sh`, Node 22 floor, Node stdlib only).

## Implementation strategy

- Strategy: tdd
- Rationale: the owner's brief asks for TDD, and every item has a test that
  can be observed failing on the unchanged tree: 40 fallback rows today, the
  literal-196 pins, timeout 25, pwsh crash text recorded as a version,
  TEST-4027 failing under a broken PowerShell cache, the preflight running
  in a linked worktree with the operator environment, the renamed doc
  passing the hook, and sync-base writing through a symlinked parent.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 ride (a workflow file and a git hook body
  template); the main checkout carries another session's uncommitted files.
- User decision: worktree (owner brief 2026-11-24 named the path)
- Base ref: origin/main at 492f8b26
- Worktree branch/path: chore/node-first-cleanup at
  /Users/ales/Projects/aai-worktrees/node-first-cleanup
- Review required: true
- Review scope (explicit paths): tests/skills/suite-weights.tsv;
  .github/workflows/skill-suite.yml; tests/skills/test-aai-sync-node.sh;
  tests/skills/test-aai-release-cut.sh; tests/skills/test-aai-update-node.sh;
  tests/skills/test-aai-bootstrap-node.sh; tests/skills/test-aai-hook-gate.sh;
  tests/skills/test-aai-hook-installer-node.sh;
  tests/skills/test-aai-install-parity.sh;
  tests/skills/test-aai-pre-commit-checks.sh;
  tests/skills/test-aai-suite-select.sh;
  .aai/scripts/release-dry-run.mjs; .aai/scripts/release-finish.mjs;
  tests/skills/lib/release-first.test.mjs;
  tests/skills/lib/aai-release.test.mjs; tests/skills/test-aai-release.sh;
  tests/skills/lib/seterr-lint.mjs;
  .aai/templates/git-hooks/pre-commit-index.sh;
  tests/skills/test-aai-git-hook-templates.sh;
  .aai/scripts/merge-cleanup.mjs; tests/skills/test-aai-merge-cleanup.sh;
  CHANGELOG.md; docs/issues/CHANGE-DRAFT-node-first-cleanup.md; this spec.

## Decisions

### D-WEIGHTS: one measurement, every suite

`tests/skills/suite-weights.tsv` is regenerated from the five most recent
successful main-push skill-suite runs at the time of planning: 45459216102,
45093987222, 45025432502, 45013455954 and 44915915697. Their head SHAs are
recorded as `# source run` lines. For each suite, the sample is the set of
`PASS (<n>s)` lines of the full-framework legs. The weight is the rounded
median, with a floor of 1. A suite that only SKIPs on the hosted runner
(today `aai-state` and `aai-hermes-skills`) keeps a `fallback unsampled`
line and takes the maximum measured weight, per SPEC-0239 Spec-AC-01. Row
order and the one-sample-line-before-each-row shape stay. The 2026-10-20 and
2026-11-07 source lines are replaced by one history comment line naming
those runs. The raw per-run samples are kept as evidence under
`docs/ai/tdd/node-first-cleanup/` (gitignored).

### D-PINS: the eight placeholder pins

TEST-4019, TEST-3475, TEST-3977, TEST-3958, TEST-3512, TEST-3997, TEST-3571
and TEST-3458 keep their checks for exactly one row of their suite. The
literal 196 becomes the positive-integer form `[1-9][0-9]*`: in an awk
check, `$2 ~ /^[1-9][0-9]*$/`; in a grep check, the extended pattern
`^<suite>\t[1-9][0-9]*$`. Whether the number is the right one stays the job
of `auditWeights` (TEST-3338).

### D-BOUND: the selected-sharded bound

The `skills-selected-sharded` job returns to `timeout-minutes: 15`. Fit is
shown in two ways:

- A model check: the selected plan of PR #582's 45 selected suites
  (fixture `tests/skills/fixtures/selected-plan-pr582.txt`, one name per
  line) under the shipped weights has `w2` of at most 600 s, against 776 s
  under the placeholder weights.
- The hosted run: the pull request head's selected-sharded legs, when
  that mode runs, finish inside the bound.

### D-PWSH-ID: interpreter identity

In `release-dry-run.mjs`, one function, `interpreterVersion(cmd, args)`,
spawns the probe. It returns the trimmed stdout only when the probe exits 0
and the first line matches `^[0-9]+\.[0-9]+`; otherwise it returns `null`.
The report keeps `interpreters.powershell`, which holds `null` for a failed
probe. A new `interpreterErrors.powershell` holds `exit <status>` or
`signal <name>` (absent when the probe succeeded). bash keeps its current
probe.

### D-PWSH-CACHE: the release tests own their PowerShell cache

Every pwsh spawn in `tests/skills/lib/aai-release.test.mjs` gets an
environment from one helper, `pwshEnv(t)`. The helper copies the
environment and sets `XDG_CACHE_HOME` to a fresh `mkdtemp` directory that
the test removes. A broken operator cache can then no longer fail
TEST-4027.

### D-PREFLIGHT: a throwaway clone with a scrubbed environment

`preflightRun(commit, file)` in `release-finish.mjs` no longer adds a linked
worktree of the real repository. It works in a fresh temp root:

1. It runs `git clone --quiet --shared --no-checkout <root> <tmp>/repo`,
   then `git -C <tmp>/repo checkout --quiet --detach <commit>`, then
   `git -C <tmp>/repo remote remove origin`.
2. It runs the test with an allowlisted environment:
   - kept from the operator: `PATH`, `LANG`, `LC_ALL`, `LC_CTYPE`, `TZ`,
     `TERM`, `TMPDIR`, `TEMP`, `TMP`, `SYSTEMROOT`, `WINDIR`, `COMSPEC`,
     `PATHEXT`;
   - set to new directories under the temp root: `HOME` (also
     `USERPROFILE`), `XDG_CACHE_HOME`, `XDG_CONFIG_HOME`;
   - nothing else. No `GH_*`, `GITHUB_*` or `GIT_*` variable, no SSH agent
     socket, no `AAI_*` variable.
3. It removes the whole temp root afterwards.

Process-group handling and the timeout are unchanged. The
`FAILS ON BASE TOO` line is unchanged.

### D-RENAME: renamed docs are gated

`.aai/templates/git-hooks/pre-commit-index.sh` lists the close-gate and
body-lint candidates with
`git diff --cached --name-only -z --no-renames --diff-filter=ACM`. Its
per-file staged hunk is read with `git diff --cached --no-renames -U0 --`.
A doc renamed in the commit is then an added path under its new name, and
its `status: done` line is an added line.

### D-INSIDE: merge-cleanup writes stay inside the checkout

`merge-cleanup.mjs` gains `escapesCheckout(origin, abs)`. It is true when the
realpath of the nearest existing ancestor of `abs` is neither the realpath of
`origin` nor inside it. `planSync` refuses
`['write_outside_checkout', rel]` for a dirty, ledger, replace or
incoming-add path that escapes. `syncBase` re-checks every planned path
before its first write. `resumeSync` stops with `write_outside_checkout`
before any write when a journal entry's path or its archive escapes.
`archiveFile` refuses a destination that escapes.

### D-SETERR: the errexit idiom lint

`tests/skills/lib/seterr-lint.mjs` (test-only, Node stdlib) exports
`lintText(text)` and `lintFiles(paths)`.

- It applies to a script that turns errexit on at top level: `set -e`,
  `set -eu...`, or `set -o errexit`.
- It reports each call of a function defined in the same file that sits in
  a condition context. A condition context is: left of `||` or `&&`, right
  after `if`, `elif`, `while`, `until` or `!`.
- Comments are skipped. A function on the right of `||` or `&&` is not a
  finding.

The check runs over every tracked `.aai/**/*.sh`. The tests corpus is out
of scope: today it holds 1405 such sites in 60 errexit suites. That corpus
gets its own follow-up, `fu-seterr-test-corpus-sweep`, with that count.

### D-AMEND: closed specs whose tests change

After the edit is verified by grep or diff, this scope records one
`spec-amend.mjs add --class contract --signoff none --ref node-first-cleanup`
record for each of SPEC-0310, SPEC-0281, SPEC-0307, SPEC-0306, SPEC-0283,
SPEC-0308, SPEC-0284, SPEC-0279 (the D-PINS edits) and SPEC-0311 (the
D-PWSH-CACHE edit of the TEST-4027 spawns). The owner's merge signs them
(L3: the owner merges).

### D-WIRE

- New tests live in existing suites; there is no new suite.
- `tests/skills/fixtures/selected-plan-pr582.txt` is a test fixture. The
  aai-suite-select suite-map row gets a glob for it.
- CHANGELOG.md gets one heading,
  `## [unreleased] — Node-first cleanup: measured suite weights, release preflight isolation and guard fixes`,
  that names each consumer-visible change: the preflight clone and
  environment, the dry-run identity, the renamed-doc gate, and the
  merge-cleanup refusal.
- No new `.aai/**` file, so no PROFILES.yaml change.

## Acceptance Criteria Mapping

- AC-001 maps to Spec-AC-01; AC-002 to Spec-AC-02; AC-003 to Spec-AC-03;
  AC-004 to Spec-AC-04; AC-005 to Spec-AC-05; AC-006 to Spec-AC-06;
  AC-007 to Spec-AC-07 and Spec-AC-08; AC-008 to Spec-AC-09 and Spec-AC-10;
  AC-009 to Spec-AC-11. Spec-AC-12 covers the wiring and amendments.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN auditWeights reads tests/skills/suite-weights.tsv over every test-aai-*.sh name it SHALL pass; the source run lines SHALL be exactly the five D-WEIGHTS runs; every measured sample SHALL name only those runs; the fallback unsampled rows SHALL be exactly aai-state and aai-hermes-skills. | planned | — | — | D-WEIGHTS |
| Spec-AC-02 | The eight D-PINS tests SHALL hold no literal 196 weight assertion and SHALL each still require exactly one positive integer weight row for their suite; each of their suites SHALL exit 0 on the re-measured weights. | planned | — | — | D-PINS, D-AMEND |
| Spec-AC-03 | The skills-selected-sharded job SHALL have timeout-minutes 15; WHEN select-suites.mjs plans the D-BOUND fixture under the shipped weights the SELECTED_DECISION line SHALL report runners=2 and w2 of at most 600. | planned | — | — | D-BOUND; hosted fit read at validation |
| Spec-AC-04 | WHEN the PowerShell probe of release-dry-run.mjs exits non-zero or prints no version-shaped first line the report SHALL record interpreters.powershell as null and interpreterErrors.powershell as the exit status, never the probe output. | planned | — | — | D-PWSH-ID |
| Spec-AC-05 | WHEN XDG_CACHE_HOME names a directory whose powershell entry is a regular file the TEST-4027 cases of tests/skills/lib/aai-release.test.mjs SHALL pass. | planned | — | — | D-PWSH-CACHE |
| Spec-AC-06 | WHEN the release preflight runs a CHANGELOG-reading test the test SHALL run in a clone that is not a linked worktree and has no remote, with HOME and XDG_CACHE_HOME under the preflight temp root and no GH_TOKEN, GITHUB_TOKEN or GIT_DIR from the operator environment; the temp root SHALL be gone afterwards. | planned | — | — | D-PREFLIGHT |
| Spec-AC-07 | WHEN a governed doc is renamed in the commit and its staged content adds status done and fails the close gate the pre-commit index hook SHALL exit non-zero under close_gate enforce. | planned | — | — | D-RENAME |
| Spec-AC-08 | WHEN a governed doc is renamed in the commit and fails the body lint the pre-commit index hook SHALL exit non-zero under body_lint enforce. | planned | — | — | D-RENAME |
| Spec-AC-09 | WHEN sync-base would write a ledger whose parent docs/ai is a symlink to a directory outside the checkout it SHALL halt with reason write_outside_checkout and the outside directory SHALL stay byte-identical. | planned | — | — | D-INSIDE |
| Spec-AC-10 | WHEN a pending sync journal names an entry whose resolved parent lies outside the checkout the resume SHALL stop with write_outside_checkout before any write and the outside directory SHALL stay byte-identical. | planned | — | — | D-INSIDE |
| Spec-AC-11 | The D-SETERR lint SHALL report zero findings over every tracked .aai shell script and SHALL report exactly one finding for a fixture with set -e and a local function left of the or operator, and zero for the same fixture without set -e. | planned | — | — | D-SETERR |
| Spec-AC-12 | CHANGELOG.md SHALL hold the D-WIRE heading naming the four consumer-visible changes; spec-amend list --strict SHALL exit 0 holding the nine D-AMEND records. | planned | — | — | D-WIRE, D-AMEND |

## Implementation plan

Order (each step RED first, evidence under
`docs/ai/tdd/node-first-cleanup/red/` and `.../green/`):

1. TEST-4037, TEST-4038, TEST-4039: weights, pins, bound (D-WEIGHTS,
   D-PINS, D-BOUND), then the D-AMEND records for the eight pin specs.
2. TEST-4040, TEST-4041: dry-run identity and the release tests' cache
   (D-PWSH-ID, D-PWSH-CACHE), then the SPEC-0311 record.
3. TEST-4042: preflight clone (D-PREFLIGHT).
4. TEST-4043, TEST-4044: renamed doc gate (D-RENAME).
5. TEST-4045, TEST-4046: merge-cleanup (D-INSIDE).
6. TEST-4047: seterr lint (D-SETERR) and its test-corpus follow-up.
7. TEST-4048: CHANGELOG and amendments (D-WIRE).

Edge cases: a suite with fewer than five samples (count below 5); a Windows
preflight (no process group, `USERPROFILE`); a hook run where rename
detection is configured on (`diff.renames=true`, which `--no-renames`
overrides); a symlinked `docs/ai` that is dangling (nearest existing
ancestor is `docs`, inside: allowed until a write needs the missing
directory, which `mkdirSync` would then create inside the checkout).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4037 | Spec-AC-01 | inspection | tests/skills/test-aai-suite-select.sh | test_4037_weights_measured runs auditWeights over every suite name, requires the five D-WEIGHTS source runs, measured samples naming only them, and fallback rows exactly aai-state and aai-hermes-skills | `sed:s/\naai-sync-node\t[0-9]+\n/\naai-sync-node\t196\n/` on tests/skills/suite-weights.tsv | pending |
| TEST-4038 | Spec-AC-02 | inspection | tests/skills/test-aai-suite-select.sh | test_4038_no_placeholder_pins scans the eight D-PINS assertions and refuses any literal 196 weight assertion, and requires each to keep a one-row check | `sed:s/\$2 ~ \/\^\[1-9\]\[0-9\]\*\$\//$2==196/` on tests/skills/test-aai-hook-gate.sh | pending |
| TEST-4039 | Spec-AC-03 | integration | tests/skills/test-aai-suite-select.sh | test_4039_selected_sharded_bound requires timeout-minutes 15 on skills-selected-sharded and plans the D-BOUND fixture, requiring runners=2 and w2 of at most 600 | `sed:s/\naai-release\t[0-9]+\n/\naai-release\t2000\n/` on tests/skills/suite-weights.tsv | pending |
| TEST-4040 | Spec-AC-04 | integration | tests/skills/lib/release-first.test.mjs | TEST-4040 runs release-dry-run with AAI_RELEASE_DRY_PWSH set to a stub that prints FileLoadException text and exits 134, and requires interpreters.powershell null and interpreterErrors.powershell exit 134 | `sed:s/r\.status!==0/false/` on .aai/scripts/release-dry-run.mjs | pending |
| TEST-4041 | Spec-AC-05 | integration | tests/skills/test-aai-release-cut.sh | test_4041_release_tests_own_pwsh_cache runs node --test --test-name-pattern TEST-4027 on aai-release.test.mjs with XDG_CACHE_HOME naming a directory whose powershell entry is a file, requiring exit 0 (SKIP with a named reason when pwsh is absent) | `sed:s/XDG_CACHE_HOME:/XDG_CACHE_HOME_OFF:/` on tests/skills/lib/aai-release.test.mjs | pending |
| TEST-4042 | Spec-AC-06 | integration | tests/skills/test-aai-release.sh | test_4042_preflight_clone_scrubbed runs a fixture cut whose CHANGELOG-reading test fails when its checkout is a linked worktree, has a remote, sees GH_TOKEN, GITHUB_TOKEN or GIT_DIR, or has HOME outside its temp root; requires the cut to pass the preflight and the temp root to be gone | `sed:s/'remote','remove','origin'/'remote','-v'/` on .aai/scripts/release-finish.mjs | pending |
| TEST-4043 | Spec-AC-07 | integration | tests/skills/test-aai-git-hook-templates.sh | test_4043_renamed_doc_close_gated stages a rename of a draft spec to a numbered name that adds status done and fails the gate, with close_gate enforce, and requires the template hook to exit non-zero | `sed:s/ --no-renames --diff-filter=ACM > "\$_aai_lists\/gated"/ --diff-filter=ACM > "$_aai_lists\/gated"/` on .aai/templates/git-hooks/pre-commit-index.sh | pending |
| TEST-4044 | Spec-AC-08 | integration | tests/skills/test-aai-git-hook-templates.sh | test_4044_renamed_doc_body_linted stages a rename of a governed doc carrying stray tool markup, with body_lint enforce, and requires the template hook to exit non-zero | `sed:s/ --no-renames --diff-filter=ACM > "\$_aai_lists\/linted"/ --diff-filter=ACM > "$_aai_lists\/linted"/` on .aai/templates/git-hooks/pre-commit-index.sh | pending |
| TEST-4045 | Spec-AC-09 | integration | tests/skills/test-aai-merge-cleanup.sh | test_4045_sync_refuses_parent_link symlinks docs/ai of a scratch origin to an outside directory holding a dirty ledger, runs sync-base, and requires write_outside_checkout and an unchanged outside tree | `sed:s/function escapesCheckout\(origin, abs\) \{/function escapesCheckout(origin, abs) { return false;/` on .aai/scripts/merge-cleanup.mjs | pending |
| TEST-4046 | Spec-AC-10 | integration | tests/skills/test-aai-merge-cleanup.sh | test_4046_resume_refuses_parent_link plants a pending journal whose entry path resolves outside the checkout and requires write_outside_checkout before any write, outside tree unchanged | `sed:s/function escapesCheckout\(origin, abs\) \{/function escapesCheckout(origin, abs) { return false;/` on .aai/scripts/merge-cleanup.mjs | pending |
| TEST-4047 | Spec-AC-11 | unit | tests/skills/test-aai-pre-commit-checks.sh | test_4047_seterr_lint runs seterr-lint over every tracked .aai shell script (zero findings) and over two fixtures (one finding with set -e, zero without) | `sed:s/return findings;/return [];/` on tests/skills/lib/seterr-lint.mjs | pending |
| TEST-4048 | Spec-AC-12 | inspection | tests/skills/test-aai-suite-select.sh | test_4048_cleanup_wiring requires the D-WIRE CHANGELOG heading with the four named changes and spec-amend list --strict exit 0 with the nine D-AMEND records | `sed:s/## \[unreleased\] — Node-first cleanup/## [unreleased] — Node first cleanup/` on CHANGELOG.md | pending |

## Verification

- Each touched suite through the canonical runner, with `env -u AAI_ROLE`:
  aai-suite-select, aai-sync-node, aai-release-cut, aai-update-node,
  aai-bootstrap-node, aai-hook-gate, aai-hook-installer-node,
  aai-install-parity, aai-pre-commit-checks, aai-release-first,
  aai-release, aai-git-hook-templates and aai-merge-cleanup. Each exits 0.
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row, and `mutation-gate.mjs` reads PASS.
- Hosted: the skill-suite run on the pull request head, including the
  selected-sharded legs when they run, and the ps1-quality Windows legs.
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `node-first-cleanup`. RED and GREEN logs go under
  `docs/ai/tdd/node-first-cleanup/{red,green}/TEST-xxxx.log`, mutation
  records go under `docs/ai/tdd/spec-node-first-cleanup/`, and the raw
  weight samples go in `docs/ai/tdd/node-first-cleanup/weights-samples.json`.
- The validation report is `docs/ai/reports/VALIDATION-<ts>-node-first-cleanup.md`.
  The review report is `docs/ai/reviews/review-node-first-cleanup-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

fu-suite-weights-placeholder-196, fu-release-pwsh-identity-crash,
fu-release-preflight-scrubbed-env, fu-seterr-suspended-left-of-or,
fu-hook-gate-skips-renamed-doc, fu-merge-sync-writes-via-parent-link.

## Residual risks

- Hosted timings vary by about ±30 % between runs. The 15-minute bound
  rests on the median model (w2 533 s for the PR #582 selection) and on one
  hosted run. A slower runner pool can still hit the bound, and the
  existing rerun path applies.
- The two SKIP-only suites take the maximum weight (450 s today). They
  occupy a modelled slot they do not use, so the model is conservative.
- The preflight clone uses `--shared`. A `git gc` in the origin repository
  during the preflight could prune objects the clone borrows. The window is
  one test run, and a failure there reads as a preflight failure on both
  the rolled and the base tree (`FAILS ON BASE TOO`), never as a pass.

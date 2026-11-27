---
id: spec-ci-flake-root-causes
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: c55ad9b599ec9913a6f003335d24483b951f7acbf2f904fac08c6d44791a1634
ceremony_level: 2
links:
  requirement: ci-flake-root-causes
  rfc: null
  pr: []
  commits: []
---

# Recurring CI flakes and the open test-infrastructure P2s, fixed at their cause

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-ci-flake-root-causes.md (owner brief
  2026-11-27).
- Prior scopes whose frozen text this scope changes (each carries an
  additive `## Amendment 2026-11-27 (ci-flake-root-causes)` section and a
  `spec-amend.mjs` record): docs/specs/SPEC-0182-spec-close-ceremony-sweep.md
  (Spec-AC-04(b), TEST-526) and docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md
  (D1 and D2, the fixed fallback cache path).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, POSIX sh
  libraries, bash suites run through `.aai/scripts/aai-run-tests.sh`).
- Debug protocol: .aai/SKILL_DEBUG.prompt.md (READ, REPRODUCE, ISOLATE,
  FIX-AT-CAUSE). No retry is added and no timeout is widened.

## Implementation strategy

- Strategy: tdd
- Rationale: every defect was reproduced before any edit (see
  Measurements), and every fix has a test that was observed failing on the
  unchanged code first. Items 1 and 2 are host-timing defects, so each RED
  reproduces the losing side of the race deterministically instead of
  racing it.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride over the shared test framework, the
  runner, the close gate and the release module; the main checkout is shared.
- User decision: worktree (owner brief 2026-11-27 named the path)
- Base ref: origin/main at ec9bb00b
- Worktree branch/path: fix/ci-flake-root-causes at
  /Users/ales/Projects/aai-worktrees/ci-flake-fixes
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/append-lock.sh;
  tests/skills/test-framework.sh; .aai/scripts/aai-release.mjs;
  .aai/scripts/close-reconcile.mjs; .aai/scripts/aai-run-tests.sh;
  tests/skills/test-aai-sweep-parallel.sh; tests/skills/lib/aai-release.test.mjs;
  tests/skills/test-aai-release-cut.sh; tests/skills/test-aai-close-reconcile.sh;
  tests/skills/lib/release-first.test.mjs; tests/skills/test-aai-release-first.sh;
  tests/skills/test-aai-run-tests.sh; tests/skills/test-aai-suite-isolation.sh;
  docs/specs/SPEC-0182-spec-close-ceremony-sweep.md;
  docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md

## Measurements (origin/main ec9bb00b, 2026-11-26/27)

No run used the owner's home cache, the main checkout, docker or a real
remote, except the throwaway diagnostic branch `diag/ci-flake-t006`, pushed
only to run the hosted skill suite by `workflow_dispatch` and deleted after.

| Item | Measured |
|---|---|
| 1 | TEST-006 failed on hosted shard 3 in runs 44516413473, 44616413846, 44729054551, 45722963303 and 45820225151, always "3 lines, 2 distinct run_id(s)"; TEST-005 failed once (45516525420, 12 records in 14 blocks). Every one of those runners reports `Image: ubuntu-26.04`. The suspected cause is REFUTED as stated: `setup_results_dir` has taken RUN_DIR with a `mkdir` test-and-set plus a `$$` suffix since PR #307, and 40 local loops, 200 loaded loops and 8 concurrent full-suite runs on macOS never failed. Diagnostic run 45912859507 (40 x TEST-006 on hosted shards) reproduced it: both framework processes printed the unsuffixed `Setting up results directory: .../test-20261126-235003`, one RUN_DIR held one suite's artifacts, and the ledger held that run_id twice. `mkdir "$RUN_DIR"` had exited 0 in BOTH processes, which an atomic mkdir(2) cannot do: the `mkdir` command on that image is not a test-and-set. append-lock.sh uses the same command as its mutex, which explains TEST-005. Run 45913897767 races two `mkdir` and two noclobber creates 400 times each on the hosted image (result in Notes). |
| 2 | TEST-3537 SIGTERM arm failed on PR #597's first run (45851092185): exit 20 with `REFUSED: git-command — git commit ...: exit 1` instead of 143. The cut reads the interrupt only from node's own handler, after one `setImmediate`. The cause is INFERRED, not reproduced: the exit-20 line can only be printed when `interrupted()` is still empty after that tick, i.e. node's handler had not run when the killed git step was read. A hosted probe of 200 group signals saw the handler run within one tick every time (late=0/200), and 25 loaded local loops never failed, so the ordering race was not observed directly. What was measured is the fix's premise: the git child's own death is reported deterministically (200 of 200 hosted probes saw `child.signal=SIGTERM, status=null`). |
| 3 | `close-reconcile.mjs --check` per merge over the last 150 first-parent merges of main reported five `id-mention-unpaired` findings over four docs (ISSUE-0091 twice); all five are mentions (`docs/issues/DEBT-0007-...` in SPEC-0181 "is NOT resolved by this scope"; "Related, not absorbed:"; "Related intake (overlap assessed, not closed):"; "a different ride"). The arm matched any substring of a touched doc, including a path and a follow-up id that contains a doc id (`fu-agents-tree-not-synced`). The two claims Spec-AC-04(b) was written for (ISSUE-0040 in PR 382, CHANGE-0181 in PR 384) both sit under a `Paired maintenance half:` label. |
| 4 | `release-first.test.mjs` passes 24 of 24 in the developer's environment and fails TEST-004 and TEST-006 (2 of 24) under the release preflight's environment (empty HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME, GIT_CONFIG_NOSYSTEM): `Import-Module: The specified module 'Pester' with version '5.0' was not loaded`. Pester is a user-scope install under HOME; CI passes because the hosted image ships Pester system-wide. Git identity and config are not involved (the other 22 cases pass). |
| 5 | With TMPDIR a regular file, `aai-run-tests.sh sh -c ...` and a framework suite with `AAI_TEST_ISOLATION=0` both run with `XDG_CACHE_HOME=/nonexistent/aai-test-no-xdg-cache`. |

## Decisions

### D1 (item 1): the claim is an O_EXCL create, not the mkdir command

- `append-lock.sh` gains `aai_claim_dir <dir> <claim-file>`: `mkdir <dir>`,
  then `( set -C; date +%s > <dir>/<claim-file> )`. noclobber makes the
  shell open the file with O_EXCL, so exactly one process can create it
  whatever `mkdir` reported. The subshell keeps noclobber out of the caller.
- The append lock acquires with `aai_claim_dir <lock> stamp`; the stamp is
  the claim, so the separate stamp write after the loop is gone. Stale-lock
  handling and the timeout are unchanged.
- `setup_results_dir` claims RUN_DIR with `aai_claim_dir "$RUN_DIR" .run-owner`;
  a failed claim takes the existing `-$$` suffix path.
- `append-lock.mjs` uses `fs.mkdirSync` (the mkdir(2) syscall), which is
  atomic, and is unchanged.

### D2 (item 2): the git child's death by the signal decides

- The real git spawn returns `signal` from spawnSync. A failed git step
  carries that signal on its Refusal when it is SIGINT or SIGTERM, and
  `stop(killed)` reports `interrupted()` or else that signal. Any other
  signal (SIGKILL) stays a git-command refusal. DB-14 of SPEC-0282 is kept
  as written: the interrupt wins over the git-command refusal.

### D3 (item 3): a claim, not a mention

- A touched doc claims an open doc when the doc's repository path, or its
  whole frontmatter id (not inside a longer `[A-Za-z0-9_-]` token), appears
  in a claim span. A doc body is cut into list items and paragraphs (an item
  runs to a blank line, a heading or the next list item, so a label's value
  may sit on the next line). A claim span is the text after a
  `Paired <words> half:` or `Paired <words> ride:` label anywhere in an item,
  or after a `Carried ...:` or `Also carried ...:` label at an item's head; a
  label with `not` inside it, or in the same clause before it (up to 40 characters, not across `.`, `;` or `:`), claims nothing; the label's word group is bounded to six words. The reason code
  `id-mention-unpaired` and every other arm are unchanged.
- Residual: a claim under any other label (for example SPEC-0185's
  "Second intake this scope settles:") is no longer itemed. Every such doc
  in the corpus is terminal today.

### D4 (item 4): the real-Pester arms probe their own environment

- `release-first.test.mjs` probes once, in the environment the reader runs
  in, whether `Import-Module Pester -MinimumVersion 5.0` succeeds. When it
  does, TEST-004 and TEST-006 run real Pester as before. When it does not,
  the Pester part is a named skip (`SKIP-CASE: Pester 5 is not importable
  ... (HOME=...)`) and fails on CI (`real Pester is required on CI`), the
  precedent of install-parity.test.mjs. TEST-006's workflow-gate half runs
  before the probe in both cases.
- The preflight's environment allowlist is not changed:
  `fu-release-preflight-env-host-gaps` stays open.

### D5 (item 5): no fixed fallback cache path

- `aai-run-tests.sh`: when neither the owned temp root nor `mktemp -d` can
  hold the cache, it prints `AAI-XDG: REFUSED - ...` and exits 125 (the
  GNU-timeout code for a failure of the wrapper itself) before the command
  starts, after running its tree and residue finishers.
- `test-framework.sh`: after the disposable checkout and `mktemp -d`, the
  suite's cache is `$RUN_DIR/aai-xdg-cache.<suite>`, unique to the suite,
  created by this run and removed after the suite. Only when that cannot be
  made either is the suite not started, with `AAI-XDG: REFUSED` in its log.
  This keeps SPEC-0179's "degraded is visible but never fatal" (TEST-103
  runs with an unusable TMPDIR and must pass).

### D6: other follow-ups taken

- `fu-azure-docnum-live-namespace` (P2) is closed as done on the
  coordinator's instruction with the live-probe evidence in its `--source`.
- No other open follow-up is a CI flake in these suites. Considered and not
  taken: `fu-pcc-3454-baseline-sigpipe-flake` (pre-commit-checks suite),
  `fu-unattended-t007-day-boundary-flake` and `fu-unattended-007-age-days-race`
  (unattended suite), `fu-follow-ups-test021-fifo-eintr` (follow-ups suite).

### D-WIRE

- New tests live in existing suites; `test-aai-sweep-parallel.sh` gains a
  one-argument selector (the mutation gate's). No new `.aai/**` file, no
  prompt-corpus bytes. CHANGELOG gets one entry: the wrapper's new exit 125
  and the close gate's claim rule are consumer-visible.

## Constraints

- Tests never push to a real remote, never install hooks into a real
  repository, never touch the docker daemon and never use the developer's
  real `~/.cache`. Every `rm -rf` names a literal path or `"${VAR:?}"`.

## Acceptance Criteria Mapping

- Intake item 1 maps to Spec-AC-01; item 2 to Spec-AC-02; item 3 to
  Spec-AC-03; item 4 to Spec-AC-04; item 5 to Spec-AC-05; the registry and
  wiring to Spec-AC-06.

## Constitution deviations

None. D3 and D5 change behaviour at a public boundary (what the close gate
items, and a new wrapper exit code); both are explicit, recorded in the
CHANGELOG and in the two amendment sections.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN two framework runs share one run id and the mkdir command exits 0 for an existing directory THEN the ledger SHALL hold two distinct run_ids and the results directory two run directories; WHEN an append lock is held and a second process with a 1 s budget tries it through the same mkdir THEN it SHALL return 1, and twelve concurrent 40-line appends SHALL come out as 480 lines in 12 contiguous blocks. | done | docs/ai/tdd/ci-flake-root-causes/test_4165_run_dir_claim_survives_a_racy_mkdir.green.log, docs/ai/tdd/ci-flake-root-causes/test_4166_append_lock_survives_a_racy_mkdir.green.log; red logs beside them; mutation records RED | — | D1, item 1 |
| Spec-AC-02 | WHEN the commit git step of a local cut is killed by SIGINT or SIGTERM and node's own handler has not run THEN aai-release.mjs SHALL print the interrupted line and exit 130 or 143; WHEN it is killed by SIGKILL THEN it SHALL stay the git-command refusal with exit 20. | done | docs/ai/tdd/ci-flake-root-causes/TEST-3537.red.log, docs/ai/tdd/ci-flake-root-causes/TEST-4168.red.log, docs/ai/tdd/ci-flake-root-causes/TEST-4168.green.log; mutation records RED | — | D2, item 2 |
| Spec-AC-03 | WHEN a delivered doc names open docs under a Paired label by id, under an Also carried label by path, and under a Paired label whose value is on the next line THEN close-reconcile --check SHALL item those three as id-mention-unpaired; WHEN it names open docs only in prose, as a disclosure, under a non-claim label or inside a longer token THEN it SHALL item none of them. | done | docs/ai/tdd/ci-flake-root-causes/test_4160_claim_not_mention.green.log, docs/ai/tdd/ci-flake-root-causes/test_4160_negated_paired.red.log, docs/ai/tdd/ci-flake-root-causes/idm-after.txt; mutation record RED | — | D3, item 3 |
| Spec-AC-04 | WHEN release-first.test.mjs TEST-004 and TEST-006 run with an empty HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME THEN they SHALL exit 0 with fail 0, as two passes where Pester is importable there and as two named Pester skips where it is not; WHEN CI is set and Pester is not importable THEN they SHALL fail naming real Pester is required on CI. | done | docs/ai/tdd/ci-flake-root-causes/release-first.preflight-env.red.log, docs/ai/tdd/ci-flake-root-causes/TEST-4163.green.log; mutation record RED | — | D4, item 4 |
| Spec-AC-05 | WHEN aai-run-tests.sh can make neither a temp root nor a mktemp cache THEN it SHALL exit 125 with AAI-XDG REFUSED and SHALL not start the command, in the inherited and the owned mode; WHEN test-framework.sh has no disposable checkout and mktemp fails THEN each suite SHALL see its own cache inside the run directory, removed after the suite, never the fixed path. | done | docs/ai/tdd/ci-flake-root-causes/TEST-4161.green.log, docs/ai/tdd/ci-flake-root-causes/TEST-4162.green.log; red logs beside them; mutation records RED | — | D5, item 5 |
| Spec-AC-06 | follow-ups.mjs list --status open --json SHALL list none of fu-sweep-parallel-t006-runid-collision, fu-reconcile-mention-vs-disclosure, fu-xdg-fallback-path-is-shared and fu-azure-docnum-live-namespace, each closed with resolved_by ci-flake-root-causes; SPEC-0182 and SPEC-0319 SHALL each hold the amendment heading and spec-amend.mjs list --strict SHALL exit 0. | done | docs/ai/tdd/ci-flake-root-causes/TEST-4167.red.log, docs/ai/tdd/ci-flake-root-causes/TEST-4167.green.log; mutation record RED | — | D6, D-WIRE |

## Implementation plan

Order: item 1, 2, 3, 4, 5, then the registry. Each TEST is run RED on the
unchanged code first; RED and GREEN logs go under
`docs/ai/tdd/ci-flake-root-causes/`.

- Item 1: `aai_claim_dir` in `.aai/scripts/lib/append-lock.sh`; its two
  callers. The RED uses a PATH shim `mkdir` that exits 0 for an existing
  directory (the losing side of the hosted race) and, for the run directory,
  a pinned `date` so both runs compute one id.
- Item 2: `aai-release.mjs` `realDeps().git` returns `signal`; `gitStep`
  sets `Refusal.signal`; `stop(killed)`.
- Item 3: `claimSpans`, `claimedByRange` in `close-reconcile.mjs`; the two
  message texts name the claim. TEST-526 in the close-reconcile suite is
  re-pointed (SPEC-0182 amendment).
- Item 4: `pesterOr(t)` in `release-first.test.mjs`.
- Item 5: the two fallback branches.

Seams:
- framework RUN_DIR claim to the run ledger reader (TEST-4165 reads the
  ledger the framework wrote);
- append-lock to the framework ledger append (TEST-006, TEST-005, TEST-4166);
- the git child (a real spawn in TEST-3537) to the cut's exit code;
- delivered doc bodies to the gate's item list (TEST-4160 runs the real CLI
  on a fixture repository; the 150-merge replay runs it on the real corpus);
- the wrapper's environment to the wrapped command (TEST-4161), the
  framework's to the suite (TEST-4162).

## Test Plan

TEST ids 4160 to 4166; the highest id on origin/main is TEST-4152.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4165 | Spec-AC-01 | integration | tests/skills/test-aai-sweep-parallel.sh | test_4165_run_dir_claim_survives_a_racy_mkdir: fixture framework repo; a mkdir shim that exits 0 for an existing directory and a date shim pinning the run id; two runs; two run_ids in the ledger and two run directories | `sed:s/if ! aai_claim_dir "\$RUN_DIR" .run-owner; then/if ! mkdir "$RUN_DIR" 2>\/dev\/null; then/` on tests/skills/test-framework.sh | green |
| TEST-4166 | Spec-AC-01 | integration | tests/skills/test-aai-sweep-parallel.sh | test_4166_append_lock_survives_a_racy_mkdir: the same mkdir shim; a held lock with a future stamp is not taken within 1 s; twelve concurrent 40-line appends give 480 lines in 12 blocks | `sed:s/\( set -C; date \+%s/( date +%s/` on .aai/scripts/lib/append-lock.sh | green |
| TEST-4164 | Spec-AC-02 | unit | tests/skills/test-aai-release-cut.sh | test_4164_child_signal_decides runs the TEST-4164 cases of tests/skills/lib/aai-release.test.mjs: commit returns signal SIGINT or SIGTERM with interrupted() empty, exit 130 or 143 and the interrupted line only; SIGKILL stays exit 20 (mocked deps; TEST-4168 covers the real spawn) | `sed:s/const sig = deps.interrupted\(\) \|\| killed;/const sig = deps.interrupted();/` on .aai/scripts/aai-release.mjs | green |
| TEST-4168 | Spec-AC-02 | integration | tests/skills/test-aai-release-cut.sh | test_4168_real_child_signal runs the TEST-4168 cases: a real spawn of the module with a git shim that kills only itself on commit (node is never signalled) by SIGINT, SIGTERM or SIGKILL; exit 130 or 143 with the interrupted line, or 20 with the git-command line; one worktree left | `sed:s/signal: r.signal \?\? '', //` on .aai/scripts/aai-release.mjs | green |
| TEST-4160 | Spec-AC-03 | integration | tests/skills/test-aai-close-reconcile.sh | test_4160_claim_not_mention: fixture repo with six untouched draft docs and one delivered carrier naming three as claims and four as mentions (one of them under two negated Paired labels); the real CLI items exactly the three claims | `sed:s/return rangeClaims.some\(\(span\) => span.includes\(doc.rel\) \|\| id.test\(span\)\);/return touched.some((t) => t.content.includes(doc.fmId));/` on .aai/scripts/close-reconcile.mjs | green |
| TEST-4163 | Spec-AC-04 | integration | tests/skills/test-aai-release-first.sh | test_4163 runs the TEST-4163 case: the TEST-004 and TEST-006 cases of the same file under an empty HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME exit 0 as passes or named skips by the probe's result, and fail with the CI message when CI is set and Pester is absent | `sed:s/  if\(!pesterOr\(t\)\)return;\n//g` on tests/skills/lib/release-first.test.mjs | green |
| TEST-4161 | Spec-AC-05 | integration | tests/skills/test-aai-run-tests.sh | test_4161_no_private_cache_refuses: TMPDIR a regular file, inherited and owned mode; exit 125, AAI-XDG REFUSED on stderr, the command never ran, nothing under the fake HOME | `sed:s/^  exit 125$/  :/m` on .aai/scripts/aai-run-tests.sh | green |
| TEST-4162 | Spec-AC-05 | integration | tests/skills/test-aai-suite-isolation.sh | test_4162_no_tmpdir_cache_is_per_run: fixture framework, AAI_TEST_ISOLATION=0, TMPDIR a regular file, two suites; each saw its own cache under the run directory, gone afterwards, never the fixed path | `sed:s/elif \[\[ -n "\$\{RUN_DIR:-\}"/elif false && [[ -n "${RUN_DIR:-}"/` on tests/skills/test-framework.sh | green |
| TEST-4167 | Spec-AC-06 | inspection | tests/skills/test-aai-close-reconcile.sh | test_4167_registry_and_amendments: the four ids closed with resolved_by ci-flake-root-causes, both amendment headings present, spec-amend.mjs list --strict exits 0 | `sed:s/## Amendment 2026-11-27 \(ci-flake-root-causes\)/## Amendment/` on docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md | green |

## Verification

- Each touched suite runs whole through the canonical runner with
  `env -u AAI_ROLE` and exits 0: aai-sweep-parallel, aai-release-cut,
  aai-close-reconcile, aai-release-first, aai-run-tests, aai-suite-isolation,
  plus aai-repo-tripwire, aai-suite-select and aai-test-residue (the other
  copiers of append-lock.sh and the runner seam).
- The 150-merge replay of `close-reconcile.mjs --check` names no doc
  (before: five, all mentions), and on the historical trees of e6aae10b and
  7270a29c it still items ISSUE-0040 and CHANGE-0181. Saved as
  `docs/ai/tdd/ci-flake-root-causes/idm-before.txt` and `idm-after.txt`.
- Release-first in the preflight environment: `release-first.preflight-env.red.log`
  (2 failed) and `release-first.preflight-env.green.log` (22 pass, 2 skip).
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row and `node .aai/scripts/mutation-gate.mjs --spec <this spec>
  --require-evidence` prints GATE PASS.
- One full sweep before the close with `AAI_TEST_TIMEOUT=3600`.
- Hosted: the pull request's skill-suite run.
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `ci-flake-root-causes`. RED and GREEN logs:
  `docs/ai/tdd/ci-flake-root-causes/`; mutation records:
  `docs/ai/tdd/spec-ci-flake-root-causes/`.
- Validation report: `docs/ai/reports/VALIDATION-<ts>-ci-flake-root-causes.md`;
  review report: `docs/ai/reviews/review-ci-flake-root-causes-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

| Follow-up | Decision | Spec-AC |
|---|---|---|
| fu-sweep-parallel-t006-runid-collision | fix (D1) | Spec-AC-01 |
| fu-reconcile-mention-vs-disclosure | fix (D3) | Spec-AC-03 |
| fu-xdg-fallback-path-is-shared | fix (D5) | Spec-AC-05 |
| fu-azure-docnum-live-namespace | closed on the coordinator's instruction with live-probe evidence (D6) | Spec-AC-06 |

Open items on the same subjects that this scope touches but does not close:

- NOT CLOSED: `fu-release-preflight-env-host-gaps` (P3): D4 makes the test
  hermetic; the preflight's allowlist is unchanged.
- NOT CLOSED: `fu-id-mention-map-swallows-read-errors` (P3): docs-audit-core,
  not close-reconcile.
- NOT CLOSED: `fu-runner-xdg-hides-other-tool-caches` (P3): which tool caches
  pass through is unchanged.
- NOT CLOSED: `fu-t4130-probe-scope-vs-pwsh-arm` (P3): TEST-4130 unchanged.

## Residual risks

- D1 trusts the shell's noclobber open to be O_EXCL. bash, dash and the
  POSIX sh of macOS do this for a regular file; run 45913897767 measures it
  on the hosted image.
- D3: a claim under a label other than Paired or Carried is not itemed.
- D2: a git child killed by SIGINT or SIGTERM from outside the process group
  (only git, not node) now reports an interrupt with 130 or 143; before, it
  was a git-command refusal with 20. Both remove the temporary worktree.
- D5: a wrapped command in an environment where no temp directory can be
  made now fails with 125 instead of running with a shared cache path.

## Notes

- Diagnostic branch `diag/ci-flake-t006` (throwaway; deleted after run
  45913897767).
- Validation round 1 (docs/ai/reports/VALIDATION-20261127T004400Z-ci-flake-root-causes.md)
  and review round 1 (docs/ai/reviews/review-ci-flake-root-causes-20261127T002444Z.md)
  remediation: TEST-4168 (the real spawn's signal), the Paired negation rule
  and a bounded label word group, an unclaimed empty lock dir is removed,
  the 125 refusal also removes the wrapper's isolation clone and tripwire
  files, TEST-006 runs its node and shell halves without Pester.
- Run 45913897767 on the hosted image: `mkdir (uutils coreutils) 0.10.0` at
  `/usr/bin/mkdir -> /usr/lib/cargo/bin/coreutils/mkdir`; two concurrent
  `mkdir` of one path both exited 0 in 20 of 400 races; two concurrent
  noclobber creates of one file both succeeded in 0 of 400.

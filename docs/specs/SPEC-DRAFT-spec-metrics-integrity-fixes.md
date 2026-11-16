---
id: spec-metrics-integrity-fixes
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 42483160fc75caef23cc6c3e4bdde0707933a12d82e556f57a652fb6cb9dfca0
ceremony_level: 2
links:
  requirement: metrics-integrity-fixes
  rfc: null
  pr: []
  commits: []
---

# Four integrity fixes: a hermetic TEST-026, a held ledger that fails loudly, and an outcome check that reads docs/ai/STATE.yaml

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-metrics-integrity-fixes.md (four open
  follow-ups: `fu-merge-cleanup-026-live-decisions-pin` P2,
  `fu-held-ledger-git-show-silent` P3, `fu-held-ledger-tmp-write-throws` P3,
  `fu-outcome-check-state-path` P2).
- Prior scopes this one builds on (closed, not edited):
  docs/specs/SPEC-0293-spec-archive-ledger-check.md (`recoverStateCopy`, the
  `--held-in` base ledger, the `ledger_runs_unchecked` keep and its fallback
  command); docs/specs/SPEC-0220-spec-merge-direction-signs-amendments.md
  (TEST-026, Spec-AC-08: a one-time claim about the live ledger after V3);
  the factory-round-cap scope that filed `fu-outcome-check-state-path`.
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: three data-integrity fixes in vendored scripts and one test
  hermeticity fix. Each behaviour can be seen failing on the unchanged tree:
  the outcome check refuses a docs/ai/STATE.yaml focus as unbound, an
  unreadable base ledger lets the recovery write the run, an unwritable temp
  directory throws out of `recoverStateCopy`, and TEST-026 fails in a tree
  without `.git` and without the live ledger. The intake's tdd note is an
  autopilot recommendation, not a recorded user choice.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: the main checkout is shared with other sessions and a
  parallel ride (effort-direct-append) is in flight; the operator already
  placed this ride in its own worktree.
- User decision: undecided in STATE (Implementation Preparation records it;
  the worktree below already exists)
- Base ref: origin/main at 16773cdf
- Worktree branch/path: fix/metrics-integrity-fixes at
  /Users/ales/Projects/aai-worktrees/metrics-integrity-fixes
- Review required: true
- Review scope (explicit paths): .aai/scripts/lib/metrics-flush-record.mjs;
  .aai/scripts/validation-outcome-check.mjs;
  tests/skills/test-aai-merge-cleanup.sh;
  tests/skills/test-aai-outcome-backcheck.sh;
  tests/skills/test-aai-role-output.sh; docs/product/telemetry.md;
  CHANGELOG.md; docs/issues/ISSUE-DRAFT-metrics-integrity-fixes.md;
  docs/specs/SPEC-DRAFT-spec-metrics-integrity-fixes.md.

## Ceremony

Ceremony level 2. No file in `protected_paths_l3` of docs/ai/docs-audit.yaml
is touched (state engine, allocator, guards, WORKFLOW.md, CONSTITUTION.md).
It is not L1: it changes two vendored scripts on two surfaces (merge-cleanup
recovery, the Validation outcome gate) and rewrites a test that pins a
corpus contract.

Companion obligations: no `.aai/*.prompt.md` or `.aai/AGENTS.md` byte
changes, no new `.aai/**` file. Neither applies.

## Decisions

### D1. TEST-026 proves the fold over its own world, never the live one

TEST-026 keeps its name, its selector and its two halves.

- First half (unchanged contract): the verdict oracle over synthetic rows in
  a fixture git repository (the 16 frontmatter cases, the absent doc, the
  missing base ref, the deleted blob). It keeps passing with zero failures.
- Second half (rewritten): instead of `$ROOT/docs/ai/decisions.jsonl` and the
  checkout's `origin/main`, it builds a fixture git repository F with
  `refs/remotes/origin/main` and a fixture ledger written by the real
  `spec-amend.mjs add` (and `classify` for the owner sign-off), then reads it
  back through the real `spec-amend.mjs list --json` and `list --strict`
  with cwd F. Rides in F:
  - `ride-merged`: doc `status: done`, `links.pr: [465]`, committed with
    `GIT_COMMITTER_DATE=2099-01-01T00:00:00Z`, so every record written now
    precedes its merge time and the read-time fold signs it. Two contract
    records.
  - `ride-open`: doc `status: implementing`, `links.pr: []`. One contract
    record left unsigned, one carrying an owner sign-off written by
    `spec-amend.mjs classify --signoff owner`.
  - `ride-late`: doc `status: done`, `links.pr: [466]`, committed with
    `GIT_COMMITTER_DATE=2000-01-01T00:00:00Z`, so its record postdates its
    merge and the fold leaves it unsigned although the ride is merged. One
    contract record, written to a second ledger only (L2 = L1 plus it).
- The oracle is parameterised (the unmerged ref, the minimum count) and
  carries no live record key: the exemptions `a90cdce977d5` and
  `91c688d47ba3`, the pinned ref `routing-tables-have-an-owner-and-a-seam`
  and the `exampleMerged` arm (PR #555) go, because they existed only to
  describe the live ledger.
- Not kept: the live-corpus invariant "every merged ride's contract record
  in this repository's ledger is signed". `spec-amend list --strict` (the
  PR gate) does NOT cover it: `--strict` fails only on
  `unsigned-untracked`, `unclassified` and undisclosed frozen-spec drift, and
  a merged ride's late record is `unsigned-tracked`, which `--strict`
  accepts. SPEC-0220 Spec-AC-08 was a one-time claim verified at that
  scope's close; re-asserting it on every suite run is what made the suite
  red when the ledger moved on (PR #553). The gap is written down as R1, not
  silently dropped.

### D2. The held base ledger: absent is fine, unreadable keeps the step

`recoverStateCopy` (`.aai/scripts/lib/metrics-flush-record.mjs`) classifies
the base ledger at `refs/remotes/origin/<base>:docs/ai/METRICS.jsonl` in the
main checkout before it runs the recovery:

1. No such ref (`git rev-parse --verify -q <ref>^{commit}` exit 1, no
   stderr): nothing held from the base; the recovery runs as today.
2. Ref present, no such path in its tree (`git ls-tree <ref> --
   docs/ai/METRICS.jsonl` exit 0, empty output): nothing held from the base;
   the recovery runs as today.
3. Path present and its blob read (`git cat-file blob` or `git show`) exits
   0: its bytes are held exactly as today (an empty blob holds nothing).
4. Anything else (a git call that exits otherwise, a spawn error such as
   ENOBUFS, a blob that cannot be read): the function returns
   `{ would: 0, refs: [], recovered: 0, keep }` with keep
   `base ledger unreadable (<reason>); run from the main checkout: <fallback>`
   where `<fallback>` is the existing
   `node .aai/scripts/metrics-flush.mjs --recover-archives --include-focus --state <rel> --archive <rel>`.
   No metrics-flush child is started and nothing is written.

`archiveRuntime` and the `archive-runtime` planner already map a non-null
keep to `ledger_runs_unchecked` (merge-cleanup.mjs line 869 and line 1285);
they do not change. merge-cleanup.mjs stays at 1490 lines (TEST-058).

### D3. The temp copy cannot throw

The temp file write and the removal run inside one try. A write that throws
returns the same shape with keep
`held ledger temp write failed (<code>); run from the main checkout: <fallback>`;
the `finally` removal swallows its own error. No exception leaves
`recoverStateCopy` for a temp-file failure.

Out of scope here and disclosed as R2: merge-cleanup.mjs itself creates two
temp directories without a guard (`archiveSubmoduleTags`, always, and
`moveLedgerTails`, when tails exist) in step `remove-worktree`. With an
unwritable temp directory `apply` therefore still throws, one step later.
Fixing it touches merge-cleanup.mjs, which has no line to spare.

### D4. The outcome check reads docs/ai/STATE.yaml, canonical path only

`readStateFocus` in `.aai/scripts/validation-outcome-check.mjs` reads
`<root>/docs/ai/STATE.yaml`, the path every other script joins as
`docs/ai/STATE.yaml`. No legacy fallback to `.aai/STATE.yaml`: nothing in the
layer writes it (the only reader in `.aai/` is this function, and the only
writer is the TEST-013 fixture), and a second path would let a stale file
bind a ref the live STATE no longer focuses. The binding origin string and
the unbound error text name `docs/ai/STATE.yaml`. The TEST-013 fixture in
tests/skills/test-aai-outcome-backcheck.sh moves its STATE to
`docs/ai/STATE.yaml` in the same change.

## Acceptance Criteria Mapping

- Intake Expected (1) maps to Spec-AC-01, Spec-AC-02.
- Intake Expected (2) maps to Spec-AC-03.
- Intake Expected (3) maps to Spec-AC-04, Spec-AC-05.
- Intake Expected (4) maps to Spec-AC-06, Spec-AC-07.
- Intake Constraints (CHANGELOG for vendored scripts) maps to Spec-AC-08.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN TEST-026 runs it SHALL keep its fixture half passing with zero failures, and over its own fixture repository F (D1) with cwd F it SHALL observe through the real spec-amend.mjs list --json over ledger L1: both ride-merged contract rows in bucket signed, the unsigned ride-open row in bucket unsigned-tracked, the owner-classified ride-open row in bucket signed; the oracle over L1 rows SHALL exit 0 printing OK 2 merged contract records; the oracle over L2 rows SHALL exit 1 printing merged contract amendments not signed and the ride-late record key; spec-amend.mjs list --strict over L1 with cwd F SHALL exit 0 | done | TEST-026 green docs/ai/tdd/metrics-integrity-fixes/green-test-026.log, RED observed as TEST-3771 RED docs/ai/tdd/metrics-integrity-fixes/red-test-3771.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-026.txt | — | D1; closes fu-merge-cleanup-026-live-decisions-pin and fu-test026-unmerged-example-arm-vacant |
| Spec-AC-02 | WHEN tests/skills/test-aai-merge-cleanup.sh TEST-026 runs from a scratch copy of the worktree's .aai/ and tests/ directories that holds no .git and no docs/ai/decisions.jsonl it SHALL exit 0 and print PASS: TEST-026; the suite text SHALL contain none of the strings ROOT/docs/ai/ preceded by a dollar sign, cd followed by the quoted ROOT variable, a90cdce977d5, 91c688d47ba3 and routing-tables-have-an-owner-and-a-seam | done | TEST-3771 green docs/ai/tdd/metrics-integrity-fixes/green-test-3771.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3771.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3771.txt | — | D1; hermeticity, RED on the unchanged suite |
| Spec-AC-03 | WHEN recoverStateCopy runs with origin and base over a main checkout whose refs/remotes/origin/main tree lists docs/ai/METRICS.jsonl but whose blob object was removed, and a ride STATE holding a run the ride METRICS lacks, it SHALL return recovered 0 and a keep starting base ledger unreadable ( and containing the fallback command naming rel, and the ride METRICS SHALL be byte-identical; WHEN the ref does not exist, and WHEN the ref's tree has no docs/ai/METRICS.jsonl, the same call SHALL return keep null and recovered 1 with the run appended to the ride METRICS | done | TEST-3772 green docs/ai/tdd/metrics-integrity-fixes/green-test-3772.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3772.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3772.txt | — | D2; closes fu-held-ledger-git-show-silent |
| Spec-AC-04 | WHEN TMPDIR names a path below a regular file and the base ledger is readable, recoverStateCopy SHALL not throw, SHALL return recovered 0 and a keep starting held ledger temp write failed ( and containing the fallback command naming rel, and the ride METRICS SHALL be byte-identical | done | TEST-3773 green docs/ai/tdd/metrics-integrity-fixes/green-test-3773.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3773.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3773.txt | — | D3; closes fu-held-ledger-tmp-write-throws |
| Spec-AC-05 | WHEN merge-cleanup plan runs over the metrics_world fixture with a late run and TMPDIR naming a path below a regular file, it SHALL exit 0, leave the world digest unchanged, create no archive directory, and its archive-runtime targets SHALL include keep (ledger_runs_unchecked held ledger temp write failed ( | done | TEST-3774 green docs/ai/tdd/metrics-integrity-fixes/green-test-3774.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3774.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3774.txt | — | D3; seam lib keep to merge-cleanup planner |
| Spec-AC-06 | WHEN validation-outcome-check.mjs runs with --report, --ref, --since and --root and without --intake and --spec over a root whose docs/ai/STATE.yaml current_focus names the ref with primary_path and spec_path, it SHALL exit 0; WHEN the same STATE exists only at .aai/STATE.yaml under the root it SHALL exit 1 with OUTCOME-CHECK: scope sources are unbound and the message SHALL name docs/ai/STATE.yaml; the checker source SHALL contain neither the string .aai/STATE.yaml nor a path.join of .aai and STATE.yaml | done | TEST-3775 green docs/ai/tdd/metrics-integrity-fixes/green-test-3775.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3775.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3775.txt | — | D4; closes fu-outcome-check-state-path |
| Spec-AC-07 | WHEN check-role-output.mjs runs over tests/fixtures/role-outputs/validation-valid.md with --now 2026-06-01T00:00:00Z and without --outcome-intake and --outcome-spec in a scratch cwd holding the role-output fixtures and a docs/ai/STATE.yaml whose current_focus is ref role-output-contracts with primary_path tests/fixtures/role-outputs/outcome-intake.md and spec_path tests/fixtures/role-outputs/outcome-spec.md, it SHALL exit 0 with no E-OUTCOME-REPORT line; the same run without that STATE SHALL exit 1 with E-OUTCOME-REPORT naming scope sources are unbound | done | TEST-3776 green docs/ai/tdd/metrics-integrity-fixes/green-test-3776.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3776.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3776.txt | — | D4; seam check-role-output to checkOutcomeReport to readStateFocus |
| Spec-AC-08 | CHANGELOG.md SHALL hold exactly one heading in the form unreleased or a rolled vYYYY.MM.DD, then an em dash and fix: an unreadable base ledger or temp file keeps the archive step; docs/product/telemetry.md SHALL state that an unreadable base-branch ledger or an unwritable temporary copy keeps archive-runtime as ledger_runs_unchecked, and that the outcome check binds scope sources from docs/ai/STATE.yaml | done | TEST-3777 green docs/ai/tdd/metrics-integrity-fixes/green-test-3777.log, RED docs/ai/tdd/metrics-integrity-fixes/red-test-3777.log, mutation docs/ai/tdd/spec-metrics-integrity-fixes/mutation-TEST-3777.txt | — | Consumer-visible; both scripts ship downstream |

## Implementation plan

Components:
- `.aai/scripts/lib/metrics-flush-record.mjs`: `recoverStateCopy` gains the
  D2 classification (a small helper beside it, for example
  `readBaseLedger(origin, base)` returning bytes, absent, or a reason) and
  the D3 try; one shared `unchecked(text)` that builds the keep with the
  existing fallback command (today built inside `recoverWith`).
- `.aai/scripts/validation-outcome-check.mjs`: `readStateFocus` path, origin
  string and the unbound error text (D4).
- Tests: tests/skills/test-aai-merge-cleanup.sh (TEST-026 rewrite,
  TEST-3771..3774, TEST-3777), tests/skills/test-aai-outcome-backcheck.sh
  (TEST-3775 and the TEST-013 fixture move),
  tests/skills/test-aai-role-output.sh (TEST-3776).
- Docs: docs/product/telemetry.md (the archive-runtime paragraph),
  CHANGELOG.md (one per-entry heading).
- Not changed: merge-cleanup.mjs (1490-line ceiling), merge-outcomes.mjs,
  metrics-flush.mjs, spec-amend.mjs, the parallel ride's files
  (SKILL_LOOP, ROLE_COMMON).

Planned anchor lines (the Test Plan mutations target them; TDD may re-anchor
a mutation to the code it writes, disclosed as a measurement amendment):
- lib: `return unchecked('base ledger unreadable` (the D2 step 4 return)
- lib: `return unchecked('held ledger temp write failed` (inside the D3
  catch, catch binding named `e`)
- checker: `path.join(path.resolve(root), 'docs', 'ai', 'STATE.yaml')`
- suite: in TEST-026's second half, `local led="$fx/docs/ai/decisions.jsonl"`
- spec-amend (unchanged code, the fold TEST-026 reads):
  `if (ride.merged && mergeTime !== null`

Seams crossed (each by a real producer and a real reader):
- spec-amend.mjs add/classify (writer) to spec-amend.mjs list --json and
  --strict (reader) to the oracle, over a real git base ref: TEST-026.
- Main checkout git object store (producer, with a removed object) to
  `recoverStateCopy` to the real metrics-flush child and the ride METRICS:
  TEST-3772.
- `recoverStateCopy` keep (producer) to the merge-cleanup `archive-runtime`
  planner and the plan report (reader): TEST-3774.
- docs/ai/STATE.yaml written by the real `state.mjs set-focus` (producer) to
  the checker CLI (reader): TEST-3775; to check-role-output.mjs through
  `checkOutcomeReport` (reader): TEST-3776.
- Not crossed by a test: an `apply` run over an unreadable base blob (the
  later sync-base needs the same object; the keep path to `archiveRuntime`
  is the one TEST-3756 already runs) and a git output over the 1 GiB buffer
  (R3).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-026 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | fixture half unchanged; second half builds F (ride-merged dated 2099, ride-open, ride-late dated 2000) and ledgers L1 and L2 through the real spec-amend add and classify, then asserts the buckets from list --json, the oracle exit 0 over L1 and exit 1 naming the ride-late key over L2, and list --strict exit 0 over L1, all with cwd F | target `.aai/scripts/spec-amend.mjs`; `sed:s/if \(ride\.merged && mergeTime !== null/if (false && ride.merged && mergeTime !== null/` stops the read-time fold, the ride-merged rows stay unsigned and the case must fail | green |
| TEST-3771 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | copy .aai/ and tests/ into a scratch directory (no .git, no docs/ai), run the copied suite with TEST-026, assert exit 0 and the PASS line; assert the suite text holds none of the five live strings (the needles are built so the test does not match itself) | target `tests/skills/test-aai-merge-cleanup.sh`; `sed:s/local led="\$fx\/docs\/ai\/decisions\.jsonl"/local led="$ROOT\/docs\/ai\/decisions.jsonl"/` points TEST-026 back at the live ledger, the copy has none and the case must fail | green |
| TEST-3772 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | node imports recoverStateCopy; fixture main checkout with refs/remotes/origin/main holding docs/ai/METRICS.jsonl, its loose blob removed (positive control: the object file existed); ride dir with STATE (focus foo, one run) and METRICS lacking it: keep starts base ledger unreadable and names the fallback, recovered 0, ride METRICS unchanged; controls without the ref and with a tree lacking the file: keep null, recovered 1 | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/return unchecked\('base ledger unreadable/if (false) return unchecked('base ledger unreadable/` lets the recovery write the run and the case must fail | green |
| TEST-3773 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | same fixture with a readable base ledger and TMPDIR set to a path below a regular file for the node process: no throw, keep starts held ledger temp write failed and names the fallback, recovered 0, ride METRICS unchanged | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/return unchecked\('held ledger temp write failed/throw e; return unchecked('held ledger temp write failed/` throws out of recoverStateCopy and the case must fail | green |
| TEST-3774 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | metrics_world with the late run; plan run with TMPDIR below a regular file for the engine only: exit 0, world digest equal, no archive directory, archive-runtime targets include keep (ledger_runs_unchecked held ledger temp write failed ( | target `.aai/scripts/lib/metrics-flush-record.mjs`; `sed:s/return unchecked\('held ledger temp write failed/throw e; return unchecked('held ledger temp write failed/` makes the plan crash and the case must fail | green |
| TEST-3775 | Spec-AC-06 | integration | tests/skills/test-aai-outcome-backcheck.sh | the TEST-013 fixture report with docs/ai/STATE.yaml written by state.mjs set-focus: checker without --intake and --spec exits 0; the same STATE only at .aai/STATE.yaml: exit 1, unbound, message names docs/ai/STATE.yaml; checker source holds no .aai STATE path; TEST-013's own STATE arm moves to docs/ai/STATE.yaml | target `.aai/scripts/validation-outcome-check.mjs`; `sed:s/'docs', 'ai', 'STATE\.yaml'/'.aai', 'STATE.yaml'/` reads the old path and the case must fail | green |
| TEST-3776 | Spec-AC-07 | integration | tests/skills/test-aai-role-output.sh | scratch cwd with the role-output fixtures and a docs/ai/STATE.yaml focus on role-output-contracts written by state.mjs set-focus: check-role-output over validation-valid.md without the outcome flags exits 0 with no E-OUTCOME-REPORT; without the STATE exits 1 with E-OUTCOME-REPORT unbound | target `.aai/scripts/validation-outcome-check.mjs`; `sed:s/'docs', 'ai', 'STATE\.yaml'/'.aai', 'STATE.yaml'/` reads the old path and the case must fail | green |
| TEST-3777 | Spec-AC-08 | unit | tests/skills/test-aai-merge-cleanup.sh | CHANGELOG.md holds exactly one unreleased or vYYYY.MM.DD heading with an em dash and fix: an unreadable base ledger or temp file keeps the archive step; docs/product/telemetry.md names base-branch ledger, ledger_runs_unchecked and docs/ai/STATE.yaml in the outcome check sentence | target `CHANGELOG.md`; `sed:s/— fix: an unreadable base ledger or temp file keeps/— fix: x keeps/` removes the named heading and the case must fail | green |

TDD batches (about three ACs each): A = Spec-AC-03, 04, 05 (lib); B =
Spec-AC-06, 07 (outcome check); C = Spec-AC-01, 02, 08 (TEST-026 and docs).

## Verification

All runs: `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh <cmd>`
from the worktree root; new test code must pass under the suites'
`set -euo pipefail` (no `printf | grep -q`, no bare `rc=$?`).

1. RED before GREEN: `docs/ai/tdd/metrics-integrity-fixes/red-*.log` and
   `green-*.log`. Expected RED: TEST-3772 recovered 1 and keep null on the
   unchanged lib; TEST-3773 an uncaught ENOTDIR; TEST-3774 plan exit 1;
   TEST-3775 and TEST-3776 scope sources are unbound; TEST-3771 the copied
   unchanged TEST-026 fails (no live ledger, no origin/main); TEST-3777 the
   heading is missing. TEST-026 rewrites a test over code that does not
   change (the spec-amend fold), so it has no pre-change RED of its own:
   its RED observation is the TEST-3771 RED above (the old body is not
   hermetic) plus its mutation record (the fold mutation reddens the new
   body), both stored.
2. `bash tests/skills/test-aai-merge-cleanup.sh`,
   `test-aai-outcome-backcheck.sh`, `test-aai-role-output.sh`,
   `test-aai-metrics.sh` exit 0; TEST-058 stays green (merge-cleanup.mjs at
   or below 1490 lines, expected unchanged).
3. Mutation records for every Test Plan row under
   `docs/ai/tdd/spec-metrics-integrity-fixes/` via `mutation-run.mjs`.
4. `node .aai/scripts/spec-amend.mjs list --strict` exits 0 on the worktree.
5. One full sweep before close with `AAI_TEST_TIMEOUT=4500`.
6. PASS criteria: every TEST row green, every Spec-AC done with evidence, CI
   green on the PR head.

## Evidence contract

Each artifact records ref_id metrics-integrity-fixes, its Spec-AC and TEST
links, the command, the exit code and the evidence path, plus the commit SHA
once one exists. RED and GREEN logs under
docs/ai/tdd/metrics-integrity-fixes/, mutation records under
docs/ai/tdd/spec-metrics-integrity-fixes/.

### Evidence by strategy

tdd: a stored RED artifact per AC-gating test plus the verification matrix
above.

## Out of scope

- The two unguarded temp directories in merge-cleanup.mjs step
  `remove-worktree` (R2).
- A live, non-gating audit of the merged-ride signing invariant (R1).
- Selecting the aai-merge-cleanup suite on a spec-amend.mjs change
  (suite-map): TEST-026 reads spec-amend's fold, but a spec-amend-only
  change selects only its own suites; the full sweep before close covers it.

## Registry items closed by this scope

From `node .aai/scripts/follow-ups.mjs list` (347 lines, run 2026-11-15):
- `fu-merge-cleanup-026-live-decisions-pin` (P2): Spec-AC-01, Spec-AC-02.
- `fu-test026-unmerged-example-arm-vacant` (P3): Spec-AC-01 (the unmerged
  arm is a fixture ride that stays unmerged).
- `fu-held-ledger-git-show-silent` (P3): Spec-AC-03.
- `fu-held-ledger-tmp-write-throws` (P3): Spec-AC-04, Spec-AC-05.
- `fu-outcome-check-state-path` (P2): Spec-AC-06, Spec-AC-07.

Touched subject, not closed: `fu-assertions-pinned-to-one-world` (P2) names
a missing check for the shape "an assertion that can only hold in one state
of the world"; this scope removes one instance and adds no general check.

## Residual risks

- R1. No test asserts any longer that this repository's ledger has every
  merged ride's contract record signed. `list --strict` does not (D1). A
  merged ride whose late amendment stays `unsigned-tracked` is visible in
  `spec-amend list` and keeps its open `fu-amend-*` tracker, so it is not
  lost, but nothing turns red. Suggested follow-up (not filed):
  `fu-merged-unsigned-live-audit`.
- R2. merge-cleanup `apply` with an unwritable temp directory still throws in
  `remove-worktree` (`archiveSubmoduleTags` creates its temp directory even
  without submodules). Suggested follow-up (not filed):
  `fu-merge-cleanup-mkdtemp-unguarded`.
- R3. The ENOBUFS branch (a base ledger over the 1 GiB buffer) and a spawn
  error are classified by the same D2 step 4 code as the removed object but
  are not reproduced by a test.
- R4. A corrupt tree (not blob) on the base makes `ls-tree` fail; D2 step 4
  keeps the step, which is the safe side, but no fixture builds one.

## Post-freeze amendment A1 (Code Review round 1, CR-1 and CR-2)

Disclosure, additive: no owner sign-off was obtained (class contract). D2 step 1
above stays as frozen text and is NOT rewritten. It is tightened as follows.
The ref is classified in two reads. First `git rev-parse --verify -q <ref>`
(without the commit peel): exit 1 with empty stderr is the only "absent"
(step 1). Any other non-zero exit, or exit 1 with stderr, is unreadable (step 4)
and keeps the step. When the ref resolves, `git rev-parse --verify -q
<ref>^{commit}` must also succeed; a ref to a missing object or to a non-commit
is unreadable (step 4) and keeps the step. Reason: a garbage loose ref and a ref
to a tree both exit 1 with stderr and were wrongly read as absent, so the
recovery wrote runs with no base ledger held. TEST-3772 gains garbage, missing
object and tree ref shapes; the mutation record is refreshed.

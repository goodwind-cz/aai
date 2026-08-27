---
id: spec-isolation-shares-the-shipping-git
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/ISSUE-DRAFT-isolation-shares-the-shipping-git.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the isolated run owns its git, instead of borrowing the shipping one

SPEC-FROZEN: true

## Headline: option (b) is dead on measurement, and the cheap option (a) is the wrong one

Three mechanisms were on the table. Two of them were settled by running them,
not by preferring them.

**(b) keep the worktree, override `GIT_DIR` / `GIT_COMMON_DIR` — REFUSED, measured.**
From inside a live disposable worktree of this repository, git 2.50.1
(Apple Git-155):

    $ cd <worktree>
    $ git rev-parse --git-common-dir
    /Users/ales/Projects/aai/.git
    $ GIT_COMMON_DIR=<scratch> git rev-parse --git-common-dir
    fatal: not a git repository: /Users/ales/Projects/aai/.git/worktrees/wt2
    $ GIT_DIR=<worktree>/.git GIT_COMMON_DIR=<scratch> git rev-parse --git-common-dir
    fatal: not a git repository: /Users/ales/Projects/aai/.git/worktrees/wt2

git resolves the linked worktree's `gitdir` pointer FIRST and then fails to find
the admin directory the override moved out from under it. There is no spelling of
the override that leaves the worktree usable. Even if there were, the variable is
inherited by the suite process, and a property a suite can `unset` is not a
property. Dead, and dead for two independent reasons.

**(c) a hard refusal at the boundary — KEPT, but as the GATE, not the mechanism.**
The dispatch's own reading is right: (c) alone prevents nothing. It is adopted in
full as decision D3 below, because after D1 the probe can never fire — which is
exactly why it must exist. It is the assertion that keeps the word `isolated`
true if a later change reverts the mechanism.

**(a) give the run its own repository — ADOPTED, and NOT in its cheapest form.**
`git clone --local --shared` is the fastest thing that satisfies the letter of the
requirement (measured below: it is CHEAPER than today's worktree). It is rejected
anyway, because it writes

    <scratch>/wt/.git/objects/info/alternates  ->  /Users/ales/Projects/aai/.git/objects

— a literal filesystem path back into the shipping `.git`, planted inside the very
git directory this scope exists to separate. This scope is about removing reach,
so it does not buy 0.6 seconds by leaving a signpost. The chosen form is
`git clone --local --no-hardlinks`, whose `.git` has no path into the shipping
repository at all.

## Links
- Requirement: docs/issues/ISSUE-DRAFT-isolation-shares-the-shipping-git.md
- Decision records: docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md (the mechanism this replaces), docs/specs/SPEC-0144-spec-a-run-must-say-whether-isolation-armed.md (the accounting this extends), docs/specs/SPEC-0145-spec-a-half-seeded-checkout-says-it-is-isolated.md (the second axis, untouched)
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: every arm this scope adds is a claim about a property that is
  currently FALSE on the shipping tree, so each one can be observed red before
  the mechanism lands and green after. The gate arm (Spec-AC-03) additionally
  needs a mutation proof against an unmutated control, which is the tdd row's
  evidence contract exactly. Nothing here is glue.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: the current branch `fix/suite-isolation-owns-its-git` is
  already dedicated to this scope and is clean, so a second checkout buys no
  separation of concerns. It would also be ironic rather than useful: a git
  worktree for this work would itself share the shipping `.git`, which is the
  defect under repair. The change must be exercised by a full 81-suite sweep run
  from an ordinary checkout, which a worktree neither helps nor hinders.
- User decision: undecided
- Base ref: fix/suite-isolation-owns-its-git
- Worktree branch/path: n/a
- Inline review scope: `tests/skills/test-framework.sh`,
  `.aai/scripts/aai-run-tests.sh`, `tests/skills/test-aai-suite-isolation.sh`,
  `docs/specs/SPEC-DRAFT-isolation-shares-the-shipping-git.md`

## The five decisions

### D1 — THE MECHANISM: a per-suite `git clone --local --no-hardlinks`

`iso_create` in `tests/skills/test-framework.sh`, and the matching block in
`.aai/scripts/aai-run-tests.sh`, stop calling `git worktree add --detach` against
the shipping repository and instead build the disposable checkout as

    git clone --local --no-hardlinks --quiet "$PROJECT_ROOT" "$wt"
    git -C "$wt" checkout --detach --quiet HEAD
    git -C "$wt" fetch -q --no-tags "$PROJECT_ROOT" \
        "+refs/heads/*:refs/heads/*" "+refs/remotes/*:refs/remotes/*"
    git -C "$wt" config user.name  "<the shipping repo's effective user.name>"
    git -C "$wt" config user.email "<the shipping repo's effective user.email>"

followed by the three existing seeding steps, unchanged.

Each of the four post-clone lines is there because a measurement said so, not for
symmetry:

- `checkout --detach` — a clone lands ON a branch. Today's worktree is detached,
  so `git rev-parse --abbrev-ref HEAD` answers the literal `HEAD` inside the
  disposable checkout. Without this line it would answer a branch name and a
  suite that reads it would see a different world than it does today.
- the `fetch` refspecs — the clone carries full history (813 commits, verified
  equal) but only ONE local head and a rewritten `origin/*`. Measured on this
  repository: shipping has `refs/heads` 42, `refs/remotes` 145, `refs/tags` 25;
  the bare clone has 1, 43, 25, and `git rev-parse --verify main` fails. Six
  suites resolve a base ref as `origin/main` and fall back to `main`
  (`test-aai-deslop.sh`, `test-aai-follow-ups.sh`, `test-aai-release.sh`,
  `test-aai-factory-report.sh`, and two more). After the fetch the counts are
  42 / 182 / 25 and `main` resolves. Cost 0.127 s.
- the two `config` lines — a clone does NOT inherit the source repository's
  LOCAL config. On this host `user.name` / `user.email` also exist globally so
  nothing breaks, but on a host where identity is repo-local only, a fixture that
  commits inside the disposable checkout would fail with `Please tell me who you
  are`. Cost 0.058 s for the naive four-subprocess form.

The cleanup half changes with it. `iso_destroy` becomes a plain `rm -rf` of the
base, and `iso_deregister` is DELETED from both funnels. That is not tidying: with
a clone the framework never registers a worktree in the shipping repository, so
`iso_deregister` — the last code path in the harness that reaches into
`<shipping>/.git/worktrees/` and `rm -rf`s an entry there — becomes both dead and
exactly the kind of reach this scope removes. The hazard it was written against
(`git worktree prune` deregistering a live-but-unreachable operator worktree,
measured on git 2.50.1) disappears with it, because the harness stops calling
`git worktree` against the shipping repository at all.

What this DOES NOT close, stated plainly: a suite that hardcodes an absolute path
(`cd /Users/ales/Projects/aai && …`) still reaches the shipping tree. No harness
mechanism can prevent that, and the permanent repo-tripwire
(SPEC-0148-spec-the-tripwire-is-permanent-not-transitional) is what observes it.
This scope closes the DERIVABLE reach: the route where a suite resolves its own
root, asks git one question, and is handed the shipping repository.

### D2 — THE COST, measured

All figures under `/bin/bash -c`, three repetitions each, on macOS 15 / APFS,
git 2.50.1 (Apple Git-155), against this repository: 1171 tracked files, 813
commits, `.git` 72 MB (10 MB packs plus 24 MB loose objects).

Creation alone:

| mechanism                          | rep 1   | rep 2   | rep 3   |
|------------------------------------|---------|---------|---------|
| `git worktree add --detach` (today)| 0.371 s | 0.219 s | 0.273 s |
| `git clone --local` (hardlinks)    | 1.034 s | 0.964 s | 0.989 s |
| `git clone --local --no-hardlinks` | 0.494 s | 0.537 s | 0.468 s |
| `git clone --local --shared`       | 0.185 s | 0.179 s | 0.177 s |

The hardlinking default is the SLOWEST of the three clones on APFS — hardlinking
2369 loose objects one at a time costs more than copying them — which is why the
default form is not the chosen one and `--no-hardlinks` is not a safety premium
paid in seconds.

End to end, create plus the three seeding steps plus destroy, which is the number
that multiplies by 81:

| stage                    | today (worktree)          | chosen (clone --no-hardlinks) |
|--------------------------|---------------------------|-------------------------------|
| create plus seed         | 0.212 / 0.206 / 0.218 s   | 0.592 / 0.580 / 0.558 s       |
| ref-parity fetch         | n/a                       | 0.127 s                       |
| identity config          | n/a                       | 0.058 s                       |
| destroy                  | 0.103 / 0.101 / 0.098 s   | 0.302 / 0.289 / 0.300 s       |
| **per-suite total**      | **0.313 s**               | **1.06 s**                    |

Delta **plus 0.75 s per suite**. Over 81 suites that is **plus 61 seconds** on a
sweep that takes about 22 minutes (1320 s) today — **plus 4.6 percent**. The
standing per-suite isolation budget is 2000 ms, enforced by the existing
`TEST-006` arm in `tests/skills/test-aai-suite-isolation.sh`; the new total of
about 1060 ms is a little over half of it, so this scope does not need and does
not get a loosened bound.

The second cost, stated rather than hidden: each clone writes about 34 MB of
`.git` plus a 1171-file checkout and then deletes it, so a full sweep moves
roughly 3 GB of write traffic that today's worktree does not. On a CI runner that
is I/O, not wall clock. On an operator's SSD it is wear. The `--shared` variant
costs plus 0.10 s per suite and near-zero extra bytes; it is rejected for the
reason in the Headline, and the number is recorded here so a future scope can
reopen the trade on evidence instead of re-measuring.

Legitimate git needs were checked empirically rather than argued. The sixteen
most git-dependent suites in the repository — every suite that reads real
history (`git log -S`, `git show <sha>:path`, `git rev-parse HEAD:path`,
`git merge-base`), that resolves a base ref, or that runs `git worktree add`
itself — were run TWICE: once in today's worktree checkout (the control) and
once in a clone-based checkout built exactly as D1 specifies, then compared on
exit code and PASS count.

| suite | worktree (control) | clone (chosen) |
|---|---|---|
| layer-profiles   | rc 0, 11 pass  | rc 0, 11 pass  |
| follow-ups       | rc 0, 21 pass  | rc 0, 21 pass  |
| release          | rc 0, 27 pass  | rc 0, 27 pass  |
| factory-report   | rc 0, 41 pass  | rc 0, 41 pass  |
| close-work-item  | rc 0, 54 pass  | rc 0, 54 pass  |
| doc-numbering    | rc 0, 32 pass  | rc 0, 32 pass  |
| routine          | rc 0, 35 pass  | rc 0, 35 pass  |
| deslop           | rc 0, 29 pass  | rc 0, 29 pass  |
| hygiene-pack     | rc 0, 49 pass  | rc 0, 49 pass  |
| worktree         | rc 0, 0 pass   | rc 0, 0 pass   |
| branch-guard     | rc 0, 14 pass  | rc 0, 14 pass  |
| friction         | rc 0, 29 pass  | rc 0, 29 pass  |
| intake           | rc 0, 0 pass   | rc 0, 0 pass   |
| suite-isolation  | rc 0, 19 pass  | rc 0, 19 pass  |
| repo-tripwire    | rc 0, 15 pass  | rc 0, 15 pass  |
| docs-audit       | rc 0, 156 pass | rc 0, 156 pass |

Sixteen of sixteen identical, including the two suites whose PASS count is zero
in both (they report through their own vocabularies) and including
`test-aai-worktree.sh`, which runs `git worktree add` itself and now does it
inside the clone. The mechanism does not trade one defect for a dozen. See
`## Verification` for the arm that re-derives this at implementation time over
the whole 81-suite sweep rather than this subset.

### D3 — THE GATE: `isolated` means the measured property

Today `isolated` means "a disposable checkout was made and the suite is in it".
It becomes: that, AND the checkout's git administrative surface is not the
shipping repository's.

After the checkout is built and before the suite runs, the framework resolves the
checkout's own common directory and compares it with the shipping one, both
through `pwd -P`:

    iso_common="$(cd "$wt" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"
    ship_common="$(cd "$PROJECT_ROOT" && cd "$(git rev-parse --git-common-dir)" && pwd -P)"

The checkout is separated when `iso_common` is non-empty, is NOT equal to
`ship_common`, and does not have `$PROJECT_ROOT/` as a prefix. When it is not
separated — including when the probe cannot resolve a path at all — the suite is
counted `degraded` with the reason

    the disposable checkout's git surface still resolves to the shipping repository

the checkout is destroyed, and the suite runs against the shipping tree exactly as
every other degrade path already does. It is never counted isolated.

Three properties of the existing accounting are preserved deliberately: the ONE
per-suite verdict, the ONE increment site, and the invariant
`ISOLATION_ISOLATED + ISOLATION_DEGRADED == TOTAL_TESTS` that the summary line and
`docs/ai/tests/test-runs.jsonl` are both read by. The new branch assigns
`iso_status` / `iso_status_why` and counts nothing itself, which is the shape the
framework's own comment demands of any path added inside that block. One new
string joins the distinct reason set; `suites_isolated` and `suites_degraded` keep
their names and their meaning, and the second (seeding) axis is untouched.

The wrapper `.aai/scripts/aai-run-tests.sh` runs the same probe on its own
checkout and, on failure, sets `AAI_ISO_STATUS=degraded` with the identical reason
string — so the two funnels keep one vocabulary, which is the property
SPEC-0144 established and this scope must not break.

### D4 — THE TWIN: nothing to mirror, and an arm that keeps it that way

MEASURED, not assumed: `.aai/scripts/aai-run-tests.ps1` contains no isolation
logic of any kind. `/usr/bin/grep -in 'worktree|isolat|seed'` over it returns
zero isolation hits — every match on `git` is prose about Git Bash. It is a
POSIX-interpreter dispatcher: it resolves WSL or native Git Bash and delegates to
`.aai/scripts/aai-run-tests.sh` (line 694,
`$shScriptPath = Join-Path $PSScriptRoot 'aai-run-tests.sh'`).

The isolation change therefore reaches the Windows path unchanged, through the
file the twin already delegates to. The twin is NOT edited, the twin does NOT
diverge, and no follow-up is filed — the owner's 2026-08-25 standing dual-surface
cost is simply not incurred by this scope. Because that claim is the kind that
rots silently, it is pinned by one assertion (TEST-207): the `.ps1` still names
`aai-run-tests.sh`, and still carries no isolation mechanism of its own.

### D5 — THE SCOPE FENCE

This scope closes the SHARED-GIT mechanism and nothing else. Five neighbours are
named here so they cannot be absorbed by accident, and each stays open:

- the repo-tripwire reporting findings (`fu-tripwire-fail-hides-suite-log-tail`,
  `fu-tripwire-allowed-ignores-pre-dirty`, `fu-tripwire-degrade-not-on-suite-line`);
- the `ISOLATION_BASES=()` wholesale reset (`fu-iso-bases-reset-discards-entries`)
  — the two reset sites are inside the block this scope edits and are deliberately
  left byte-identical;
- the wrapper's INT/TERM/HUP traps not reaping the wrapped process group
  (`fu-iso-wrapper-traps-dont-reap-group`);
- the framework's second-resolution `RUN_DIR` collision
  (`fu-framework-rundir-same-second`);
- `docs/ai/tests/test-runs.jsonl` being tracked AND gitignored
  (`fu-test-runs-jsonl-tracked-ignored`).

## Acceptance Criteria Mapping

- Maps to: ISSUE-DRAFT-isolation-shares-the-shipping-git "Expected Behavior"
- Spec-AC-01: WHEN a suite runs in the disposable checkout THEN
  `git rev-parse --git-common-dir` resolved from that checkout does not resolve
  into the shipping repository.
  - Verification: TEST-201 — a fixture suite inside a throwaway repository records
    its own resolved common dir; the recorded path is inside the disposable base
    and is not the fixture repository's own common dir.
- Spec-AC-02: WHEN a suite in the disposable checkout writes `git config --local`,
  a ref, and a file under `hooks/` THEN none of the three is readable from the
  shipping repository afterwards.
  - Verification: TEST-202 — after the run, `git config --local --get` for the
    probe key exits non-zero in the fixture repository, `git rev-parse --verify`
    for the probe ref exits non-zero, and the probe hook file does not exist.
- Spec-AC-03: WHEN a disposable checkout's git surface still resolves to the
  shipping repository THEN the suite is counted degraded with a named reason and
  is never counted isolated.
  - Verification: TEST-203 — on a fixture whose byte copy of the framework is
    mutated back to `git worktree add --detach`, the run prints
    `0/N suite(s) isolated; N degraded`, the reason line names the git surface,
    and the fixture ledger records `suites_isolated` 0; TEST-204 is the unmutated
    control on the same fixture and records `suites_isolated` N, `suites_degraded` 0.
- Spec-AC-04: WHEN the disposable checkout is built THEN its ref surface and
  history match the shipping repository's, so history-reading suites keep working.
  - Verification: TEST-205 — inside the checkout, the counts of `refs/heads`,
    `refs/remotes` and `refs/tags` each equal the shipping repository's,
    `git rev-parse --verify main` and `origin/main` both exit 0, and
    `git rev-list --count HEAD` is equal on both sides.
- Spec-AC-05: WHEN the full sweep runs THEN every suite is counted isolated, the
  accounting invariant holds, and no suite fails.
  - Verification: `env -u AAI_ROLE bash tests/skills/test-framework.sh` exits 0
    with `Failed: 0` and a summary line reading
    `Isolation: 81/81 suite(s) isolated; 0 degraded`; the last record of
    `docs/ai/tests/test-runs.jsonl` has `suites_isolated + suites_degraded == total`
    and `suites_degraded` 0. TEST-206 asserts the accounting shape on a fixture.
- Spec-AC-06: WHEN isolation is armed THEN its measured per-suite wall-clock cost
  stays under the standing 2000 ms bound.
  - Verification: the existing TEST-006 arm in
    `tests/skills/test-aai-suite-isolation.sh` is green and its PASS line prints
    the measured ms per suite; the bound is NOT raised by this scope.
- Spec-AC-07: WHEN the Windows entry point is used THEN it inherits this change by
  delegation, carrying no isolation mechanism of its own.
  - Verification: TEST-207 — `.aai/scripts/aai-run-tests.ps1` contains the literal
    `aai-run-tests.sh` at least once and contains no `git worktree` and no
    `git clone` invocation.
- Spec-AC-08: WHEN the harness cleans up a disposable checkout THEN it writes
  nothing under the shipping repository's `.git`.
  - Verification: TEST-208 — the shipping fixture repository's
    `.git/worktrees` directory is absent or empty both during and after a run, and
    `git -C <fixture> worktree list` prints exactly one line.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                  | Status  | Evidence | Review-By | Notes                                              |
|------------|----------------------------------------------------------------------------------------------|---------|----------|-----------|----------------------------------------------------|
| Spec-AC-01 | The disposable checkout's git common directory does not resolve into the shipping repository   | planned | —        | —         | the property the intake measured as false today     |
| Spec-AC-02 | A config, ref or hook write from the isolated run is unreadable from the shipping repository   | planned | —        | —         | all three admin surfaces, one fixture run           |
| Spec-AC-03 | A checkout whose git surface is not separated is counted degraded with a named reason          | planned | —        | —         | mutation proof plus unmutated control               |
| Spec-AC-04 | The checkout's refs, tags and history match the shipping repository's                          | planned | —        | —         | keeps history-reading suites working                |
| Spec-AC-05 | The full sweep is green and every suite is counted isolated                                    | planned | —        | —         | invariant isolated plus degraded equals total       |
| Spec-AC-06 | Per-suite isolation cost stays under the standing 2000 ms bound                                | planned | —        | —         | measured 1060 ms at planning time                   |
| Spec-AC-07 | The PowerShell entry point inherits the change by delegation and adds no mechanism             | planned | —        | —         | pins the twin claim so it cannot rot                |
| Spec-AC-08 | Cleanup writes nothing under the shipping repository's .git                                    | planned | —        | —         | iso_deregister deleted with the mechanism           |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan

Components affected:

1. `tests/skills/test-framework.sh` — `iso_create` builds a clone instead of a
   worktree and runs the D3 separation probe; `iso_destroy` becomes `rm -rf`;
   `iso_deregister` is deleted; one new reason string joins the distinct set.
   The two `ISOLATION_BASES=()` reset sites, the seeding steps, the counters, the
   increment sites and the summary lines are byte-identical (D5).
2. `.aai/scripts/aai-run-tests.sh` — the same three changes in the wrapper's
   isolation block, in POSIX sh, keeping `AAI_ISO_STATUS` / `AAI_SEED_STATUS`
   vocabularies and the exit-code contract untouched.
3. `tests/skills/test-aai-suite-isolation.sh` — eight new arms, TEST-201..208.
   SPEC-0138's TEST-001..006 and SPEC-0144/0145's TEST-101..113 keep their ids.
   `leaked_worktrees` keeps its `git worktree list` half: with a clone the
   registration count is structurally zero, which is a stronger statement than
   "the registration was removed", and TEST-004 continues to hold.
4. `.aai/scripts/aai-run-tests.ps1` — NOT edited (D4).

Data flows: nothing crosses a process boundary that did not before. The one new
value is the probe's resolved common-dir string, which lives inside `run_test`
and is discarded after the verdict.

Edge cases, each with a decided behavior:

- `git clone` fails (no disk, no git) — the existing `no disposable checkout
  could be made` degrade path already covers it; the clone call replaces the
  `worktree add` call inside the same conditional.
- the ref-parity `fetch` fails — it is best-effort like the seeding steps and
  does not change the isolation verdict; a checkout with fewer refs is still a
  separated checkout. It does NOT downgrade the seeding axis either, because the
  seeding axis is about working-tree CONTENT and calling a ref shortfall
  `partial` would make that word untrue.
- the identity `config` fails — same treatment, best-effort, verdict unchanged.
- the shipping repository has no `origin` — the clone's `origin` is the local
  path, `origin/main` maps to the source's local `main`, and the fallback chain
  the suites already use resolves. Unchanged from today in outcome.
- `AAI_TEST_ISOLATION=0` — unchanged; the run degrades globally for the reason it
  already names.
- the shipping repository's own `.git/hooks/pre-commit` is NOT inherited by a
  clone, where a worktree shared it. Checked: no suite asserts that the hook is
  present in `PROJECT_ROOT`; the four suites that mention `.git/hooks`
  (`test-aai-doctor.sh`, `test-aai-docs-audit.sh`, `test-aai-deslop.sh`, and one
  comment in the framework) install their own hooks into their own fixtures.
  Losing the shared hook is the point of `fu-worktree-hook-disarms-later-suites`.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                      | Description                                                                                                                                  | Status  |
|----------|------------|-------------|-------------------------------------------|----------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-201 | Spec-AC-01 | integration | tests/skills/test-aai-suite-isolation.sh  | a fixture suite records its own resolved git common dir; it is inside the disposable base and is not the fixture repository's common dir       | pending |
| TEST-202 | Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh  | a fixture suite writes a local config key, a ref and a hooks file; none of the three is readable from the fixture repository after the run     | pending |
| TEST-203 | Spec-AC-03 | integration | tests/skills/test-aai-suite-isolation.sh  | THE MUTATION PROOF — the fixture's byte copy of the framework is reverted to git worktree add; the run reports 0 isolated, N degraded, and the reason names the git surface | pending |
| TEST-204 | Spec-AC-03 | integration | tests/skills/test-aai-suite-isolation.sh  | THE UNMUTATED CONTROL — the same fixture unmutated reports N isolated, 0 degraded, with suites_isolated N in its ledger record                  | pending |
| TEST-205 | Spec-AC-04 | integration | tests/skills/test-aai-suite-isolation.sh  | inside the checkout the refs/heads, refs/remotes and refs/tags counts equal the fixture repository's, main and origin slash main both resolve, and the commit counts are equal | pending |
| TEST-206 | Spec-AC-05 | integration | tests/skills/test-aai-suite-isolation.sh  | a multi-suite fixture run keeps suites_isolated plus suites_degraded equal to total in both the summary line and the ledger record             | pending |
| TEST-207 | Spec-AC-07 | unit        | tests/skills/test-aai-suite-isolation.sh  | aai-run-tests.ps1 names aai-run-tests.sh at least once and contains no git worktree and no git clone invocation                                | pending |
| TEST-208 | Spec-AC-08 | integration | tests/skills/test-aai-suite-isolation.sh  | the fixture repository's .git/worktrees stays absent or empty across a run and git worktree list prints exactly one line                       | pending |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-suite-isolation.sh  | PRE-EXISTING, RE-RUN — isolation adds under 2000 ms of wall clock per suite over 20 fixture suites; the bound is not raised                    | green   |

RED-first requirements, per arm:

- TEST-201, TEST-202, TEST-205, TEST-208 must each be observed FAILING on the
  pre-change tree — that is the intake's measurement turned into an assertion,
  and the failure is the whole finding. Record the red transcript under
  `docs/ai/tdd/`.
- TEST-203 is red on the pre-change tree for a second reason: the gate does not
  exist yet, so the mutated fixture reports isolated. Its mutation proof after the
  change is the same `sed` on the fixture's byte copy, and TEST-204 is its
  required unmutated control run on the same fixture.
- TEST-206 and TEST-207 are expected GREEN before the change (the accounting
  invariant and the twin claim both already hold). They are regression pins, not
  discoveries, and the spec says so rather than manufacturing a red for them.
- HAZ-RESTORE applies to TEST-203: the mutation is applied to the fixture's byte
  COPY of the framework, never to `tests/skills/test-framework.sh`.

## Verification

Commands, in order:

1. `env -u AAI_ROLE bash tests/skills/test-aai-suite-isolation.sh` — exit 0, and
   TEST-201..208 present in the output.
2. `env -u AAI_ROLE bash tests/skills/test-aai-repo-tripwire.sh` — exit 0; the
   tripwire suite turns isolation off for its children and must be unaffected.
3. `env -u AAI_ROLE bash tests/skills/test-framework.sh` — exit 0, `Failed: 0`,
   and `Isolation: 81/81 suite(s) isolated; 0 degraded`.
4. `tail -n 1 docs/ai/tests/test-runs.jsonl` — `suites_isolated` equals `total`
   and `suites_degraded` is 0.
5. `sh -n .aai/scripts/aai-run-tests.sh`, `dash -n .aai/scripts/aai-run-tests.sh`,
   `bash -n .aai/scripts/aai-run-tests.sh` — all exit 0.
6. `/usr/bin/grep -c 'git worktree add' tests/skills/test-framework.sh
   .aai/scripts/aai-run-tests.sh` — 0 in both.
7. `git diff --name-only` over the scope — `.aai/scripts/aai-run-tests.ps1` absent.

Evidence artifacts: `docs/ai/tdd/` for the red transcripts and the TEST-203
mutation transcript; `tests/skills/results/<run>/` for the sweep log; the tail of
`docs/ai/tests/test-runs.jsonl` for the accounting record.

PASS criteria: every TEST-xxx green AND every Spec-AC in a terminal status.

## Evidence contract

- ref_id: isolation-shares-the-shipping-git
- Spec-AC and TEST links: as tabulated above.
- Commands and exit codes: section `## Verification`, in order.
- Evidence paths: `docs/ai/tdd/` for the RED artifacts and the mutation
  transcript; `tests/skills/results/<run>/` for the suite logs.
- Commit SHA or diff range: `main...fix/suite-isolation-owns-its-git` at review
  time.

Per `### Evidence by strategy` in `.aai/templates/SPEC_TEMPLATE.md`, the `tdd`
row applies: a stored RED artifact is owed for each AC-gating test, plus the full
verification matrix above.

## Registry items closed by this scope

Read from `node .aai/scripts/follow-ups.mjs list` at planning time (98 open).

CLOSED FULLY:

- `fu-worktree-shares-git-admin-surface` (P2) — its exact words are "a suite in a
  disposable worktree can still write the shipping repository's refs, .git/config
  and .git/hooks, because a worktree shares one .git". After D1 there is no shared
  `.git`; Spec-AC-02 asserts all three surfaces on one fixture run.
- `fu-worktree-hook-disarms-later-suites` (P2) — a hook armed by a suite now lives
  in that suite's own clone and dies with it, and the harness no longer calls
  `git worktree add` against the shipping repository at all, so there is no
  `worktree add` left for a shipping hook to fail.

CLOSED QUALIFIEDLY:

- `fu-isolated-suite-reaches-shipping-repo` (P1) — closed for the mechanism it
  names. Its two halves are "a suite can write the shipping WORKING TREE while the
  run reports isolated" and "the degraded gate does not cover the write-capable
  set". The derivable route (resolve own root, ask git one question, receive the
  shipping repository) is removed by D1; the gate is made to MEASURE the property
  by D3, so a suite counted isolated is provably not write-capable against the
  shipping git surface. What remains is a suite that hardcodes an absolute path,
  which no harness mechanism can prevent and which the permanent tripwire
  observes. The item is closed with that remainder recorded, not hidden.

NOT CLOSED:

- `fu-subagent-probe-hits-real-repo` (P1), structural half — NOT closed, and this
  scope does not claim it. The incident was an agent's own probe helper running
  git from an agent shell, not a suite running inside the framework's checkout.
  Nothing here constrains an agent shell: `.aai/scripts/aai-run-tests.sh` isolates
  SUITE RUNS only, by design, which is itself an open item
  (`fu-adhoc-probes-unisolated-report-only`, P2). The only control on the agent
  path remains HAZ-SCRATCH in `.aai/SUBAGENT_CONTRACT.md`, which is prose. This
  scope makes the SUITE path structurally safe and leaves the AGENT path exactly
  where it was.

No new registry items are filed by this scope.

## Notes

Staying open, named so they are not absorbed (D5): the tripwire reporting
findings, `fu-iso-bases-reset-discards-entries`,
`fu-iso-wrapper-traps-dont-reap-group`, `fu-framework-rundir-same-second`,
`fu-test-runs-jsonl-tracked-ignored`, and `fu-adhoc-probes-unisolated-report-only`.

Companion obligations: this scope adds no bytes to `.aai/*.prompt.md` or
`.aai/AGENTS.md` and creates no new `.aai/**` file, so neither the prompt-diet
ledger true-up nor a `PROFILES.yaml` classification entry is owed.

Ceremony level 2: the scope touches the test harness and the test wrapper, and
none of `protected_paths_l3` (docs/ai/docs-audit.yaml). `.aai/scripts/close-work-item.mjs`
is content-hash pinned and is not touched.

This document defines HOW, not WHAT or WHY. It does not define workflow.

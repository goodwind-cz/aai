---
id: spec-merge-cleanup-submodule-worktree
type: spec
number: 221
status: implementing
mutation_gate: v1
frozen_sha256: 9b5599ce2a41e5ab46331d129bcc848028b82c6e9f66cd60431b0ccf90cf411e
ceremony_level: 2
links:
  requirement: merge-cleanup-submodule-worktree
  rfc: null
  pr: []
  commits: []
---

# Spec — /aai-merge cleanup removes a ride worktree with submodules only after proving nothing is lost

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-0097-merge-cleanup-submodule-worktree.md
  (owner decision 2026-10-11 "Opravit teď")
- Engine: .aai/scripts/merge-cleanup.mjs (`worktreeVerdict`, `removeWorktree`,
  `planChecks`, `archiveFile`, `PLANNERS`, `buildReport`/`renderReport`,
  `runPreflight`, `stop()` exit 4 versus `refuse()` exit 3)
- Canon: .aai/SKILL_MERGE.prompt.md (exit codes, step 1, step 2, hard rules)
- Product doc: docs/product/directed-merge-and-post-merge-cleanup.md
- Prior art: docs/specs/SPEC-0218-spec-directed-merge-and-post-merge-cleanup.md
  (D7 archive-first, D10 worktree and branch, D11 resume),
  docs/specs/SPEC-0220-spec-merge-direction-signs-amendments.md (step list,
  preflight output order)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only)

## Registry items closed by this scope

None. `node .aai/scripts/follow-ups.mjs list`
at 4767ebf4 (167 open) holds no item about submodules or about the stop of
`remove-worktree`.

## Registry items assessed, not closed

- `fu-merge-foreign-journal-archive-path` and `fu-merge-pending-diverged-regression`
  (same engine, base-sync subject; this scope does not touch `syncBase`).
- `fu-constitution-art7-directed-merge` (Constitution wording about merges, not
  about worktree removal).

## Implementation strategy

- Strategy: tdd
- Rationale: Planning's decision (intake: "left to Planning"). The change adds
  a forced removal to an engine whose whole contract is "archive before remove,
  never lose silently". A missing proof looks exactly like a working one until
  a test is seen failing without it, and a wrong removal cannot be undone.
  Every Spec-AC gets a stored RED and a mutation that reddens it. STATE holds
  an intake-sourced strategy for `slowest-suite-hot-spots`; its ref_id differs,
  so it is stale and is replaced.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound change to a destructive engine step, one canon
  prompt and two suites; the ride already runs in
  `/Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree`. Not
  `required`: no `protected_paths_l3` surface is touched.
- User decision: worktree (already recorded in STATE for this branch)
- Base ref: origin/main 4767ebf4
- Worktree branch/path: fix/merge-cleanup-submodule-worktree at
  /Users/ales/Projects/aai-fix-merge-cleanup-submodule-worktree
- Inline review scope: .aai/scripts/merge-cleanup.mjs,
  tests/skills/test-aai-merge-cleanup.sh, .aai/SKILL_MERGE.prompt.md,
  tests/skills/lib/prompt-diet-ledger.sh, tests/skills/test-aai-prompt-diet.sh,
  docs/product/directed-merge-and-post-merge-cleanup.md, CHANGELOG.md, the
  intake and this spec
- Code review required: true (engine, canon and test change).

## Phasing

One ride, 7 Spec-ACs, 7 TEST rows, one engine file, one suite plus the
prompt-diet pin. Expected three TDD dispatches:
(A) the submodule fixture helper, TEST-028, TEST-029, TEST-030 (proof and
removal); (B) TEST-031, TEST-032, TEST-033 (ignored content, race stop and
resume, preflight); (C) TEST-034 (canon and prompt-diet), then V1 to V4.

## Measured facts (scratch repo, git 2.54.0, 2026-10-11)

Measured with three local bare repos (superproject, submodule `sub`, nested
submodule `sub/nest`) and a linked worktree where
`git submodule update --init --recursive` ran:

- F1 `git worktree remove <wt>` on a clean worktree with initialized
  submodules exits 128: `fatal: working trees containing submodules cannot be
  moved or removed` (the reported failure, reproduced).
- F2 The submodule git dirs live in the main repository at
  `.git/worktrees/<id>/modules/sub` and `.../modules/sub/modules/nest`.
  `git worktree remove --force` deletes `.git/worktrees/<id>` and with it
  every submodule git dir: commits, stashes and branches that exist only there
  are gone.
- F3 `git submodule deinit --all` (no `-f`) in the linked worktree refuses a
  modified file, an untracked file, nested dirt and a moved submodule HEAD
  (exit 128), but it clears a submodule holding only ignored files (the
  ignored file is deleted) and one whose committed HEAD is unpushed.
- F4 After a successful `deinit --all`, plain `git worktree remove` STILL exits
  128 with the same message, because `.git/worktrees/<id>/modules` remains.
- F5 `deinit --all` in the linked worktree unsets `submodule.sub.url` and
  `submodule.sub.active` in the SHARED repository config: afterwards the main
  checkout's `git submodule status` shows `-` (uninitialized) for `sub`. Deinit
  in a ride worktree damages the main checkout.
- F6 The superproject's `git status --porcelain` shows ` M sub` for submodule
  dirt (modified, untracked, nested) and for a moved submodule HEAD, but shows
  nothing for a submodule HEAD that is committed in the superproject and
  absent from the submodule's remote. `--ignore-submodules=none` on the command
  line overrides `submodule.<name>.ignore = all` in `.gitmodules`;
  `--ignore-submodules=dirty` hides content dirt and keeps HEAD moves.
- F7 `git -C <sub> rev-list --count HEAD --branches --not --remotes` prints 0
  for a pushed submodule and 1 after one committed, unpushed commit.
- F8 `git -C <sub> ls-files --others --ignored --exclude-standard --directory`
  lists a fully ignored directory once (`ign/`) without descending, and
  ignored files individually (`.env`, `top.log`).

## Design decisions

- D1 Removal mechanism. A ride worktree with no initialized submodule and no
  `modules` dir under its admin dir is removed exactly as today (plain
  `git worktree remove <path>`, no force). A worktree with at least one
  initialized submodule is removed with `git worktree remove --force <path>`
  (one `--force`, never two, so a git-locked worktree is still refused), and
  only after the D2 proof passed in the same `remove-worktree` step,
  immediately before the call (D3). Rejected: `submodule deinit` then plain
  remove (F4: still refused; F5: it de-registers the submodule in the main
  checkout's config; F3: it deletes ignored files). Rejected: moving the
  `modules` dir away and deleting the submodule `.git` files so that plain
  remove passes (a crash between those writes leaves a worktree whose
  submodules point nowhere, which needs a rollback journal; after the proof it
  loses no more data than `--force`). The agent never forces; only the engine
  does, only after the proof.
- D2 Proof, per initialized submodule, recursive. The set is every gitlink
  (`ls-files --stage -z`, mode 160000) whose path holds a `.git` file or
  directory, walked recursively into each such submodule. Uninitialized
  gitlinks (no `.git`) are skipped. Each member must pass, in this order:
  (a) clean: `status --porcelain --ignore-submodules=dirty --untracked-files=normal`
  prints nothing (each nested level is checked as its own member, so dirt is
  reported at the path where it is); else `submodule_dirty`;
  (b) has a remote: `git remote` prints at least one name; else
  `submodule_no_remote`;
  (c) pushed: `rev-list --count HEAD --branches --tags --not --remotes` is 0 (HEAD,
  every local branch and every local tag reachable from a remote-tracking ref;
  amended after freeze to add the tags, because a commit reachable only from a
  local tag passed the first proof and `--force` deleted it); else
  `submodule_unpushed` with the count;
  (d) no stash: `rev-parse -q --verify refs/stash` fails; else
  `submodule_stash`.
  A git call that fails is `submodule_unverifiable`. A git dir under
  `<worktree admin dir>/modules` that belongs to no initialized member (a
  submodule deinitialized earlier) is also `submodule_unverifiable`: the
  engine cannot run the proof on it and `--force` would delete it. No fetch
  runs (SPEC-0218 D4: the engine's only network calls are the one gh read and
  the base fetch); a stale remote-tracking ref yields a false
  `submodule_unpushed`, which fails closed and is fixed by
  `git -C <sub> fetch` and a re-run. The superproject check in
  `worktreeVerdict` becomes explicit:
  `status --porcelain --ignore-submodules=dirty --untracked-files=normal`, so
  local config (`.gitmodules` `ignore`, `status.showUntrackedFiles`) can hide
  nothing, a moved submodule HEAD stays `worktree_dirty`, and submodule
  content dirt gets the named submodule reason.
- D3 Where the proof runs and what it prints. `worktreeVerdict` runs the D2
  proof after the superproject check and before `tip_mismatch`, so
  `planChecks` refuses with exit 3 before any write in both `plan` and
  `apply` (SPEC-0218 semantics for `worktree_dirty`). `removeWorktree` runs
  `worktreeVerdict` again as its LAST check, after the D4 archive and
  immediately before the removal call, and stops with exit 4 when it fails; a
  re-run resumes. The line is `REFUSE <reason> <detail>` or
  `STOPPED <reason> <detail>`. `<reason>` is the first kind present in the
  order submodule_dirty, submodule_unpushed, submodule_stash,
  submodule_no_remote, submodule_unverifiable. `<detail>` lists EVERY
  offender, sorted by path, as `<path relative to the worktree> (<kind>: <fact>)`
  joined by `; `, where the fact is short (for example `2 changed`,
  `1 commit not on any remote-tracking ref`).
- D4 Ignored content inside submodules (archive-first, SPEC-0218 D7). Right
  before the final verify, for each member, every regular file listed by
  `ls-files --others --ignored --exclude-standard --directory -z` is archived
  through the existing `archiveFile` to
  `docs/ai/archive/merge-cleanup/pr-<n>/worktree-submodules/<sub path>/<rel>`
  with `original` `worktree:<sub path>/<rel>` and reason `submodule_ignored`
  (manifest line with sha256, byte-compare, idempotent). Each listed directory
  (fully ignored, F8) and each non-regular entry is NOT archived; it is named:
  one line per entry in `<archive root>/removed.jsonl`
  (`{path, kind, reason: "submodule_ignored_not_archived"}`, deduplicated),
  in the `remove-worktree` plan targets, in the report section
  `## Removed, not archived`, and in the JSON report field
  `removed_unarchived`. Rationale: blocking on any ignored file would stop
  every downstream submodule with `node_modules`; archiving whole ignored
  directories would copy gigabytes of regenerable output. Single ignored files
  (`.env`, local settings) are the likely irreplaceable ones and are small.
  The superproject's own ignored files keep today's behaviour (only the D10
  runtime set is archived); named as residual risk R4.
- D5 Preflight surfaces, it does not refuse. When `preflight` finds a
  registered worktree on the PR's `headRefName` other than the main checkout,
  it runs the D2 proof on it and prints one
  `cleanup blocked: <reason> <detail>` line after the `signs on merge:` lines
  and before the printed merge command; `--json` carries
  `cleanup_blockers: [{reason, detail}]` (`[]` when none). Exit stays 10.
  Rationale: the merge itself loses nothing; `apply` refuses before any write,
  so the engine, not the agent's obedience, protects the data; refusing the
  merge would hold a reviewed PR hostage to a local file. The owner sees the
  line in the same relay that carries the merge.
- D6 Canon (SKILL_MERGE.prompt.md). Step 1: a `cleanup blocked:` line is
  relayed verbatim; it does not stop the merge. Step 2: when `apply` exits 3
  or 4, relay the `REFUSE` or `STOPPED` line verbatim to the owner and stop;
  never finish a step by hand (no `git worktree remove --force`, no branch
  delete, no `git submodule deinit`); re-running `apply` after the owner
  resolves the cause is the only way forward. The hard-rules line keeps
  `worktree remove --force` forbidden for the agent. Growth budget: at most
  700 bytes, credited 1:1 in the prompt-diet ledger under the key
  `merge-cleanup-submodule-worktree` with the TEST-012 pin moved by the same
  amount.
- D7 Test seam. `AAI_MERGE_CLEANUP_TOUCH_AT=before-remove-verify:<path relative to the worktree>`
  writes one line to that file between the D4 archive and the final verify;
  inert unless `AAI_MERGE_CLEANUP_TEST_SEAMS=1` (like every other seam).
- D8 PowerShell. `tests/skills/aai-merge-cleanup.Tests.ps1` gets no new case
  (named skip): the PowerShell block of SKILL_MERGE is unchanged and calls the
  same Node engine; the new logic is platform-neutral Node and git. Windows
  forced removal of a submodule worktree is residual risk R2.

## Implementation anchors (the mutation rows depend on these spellings)

- `function submoduleBlockers(wtPath)` returns an array of
  `{ path, kind, fact }`; inside `worktreeVerdict`:
  `const blockers = submoduleBlockers(wt.path);`
- the pushed check computes `const unpushed = Number(` from the `rev-list`
  output.
- in `removeWorktree`: `archiveSubmoduleIgnored(ctx, wt);`, then
  `const late = worktreeVerdict(ctx, wt);` as the last check, then the call
  `git(ctx.origin, ['worktree', 'remove', '--force', wt.path])` on the
  submodule branch.
- preflight output prefix: `cleanup blocked: `.
- keep the existing spellings that SPEC-0218 mutation rows match:
  `st.stdout.trim() !== ''` in the superproject check (TEST-016) and
  `wt.head !== ctx.head` (TEST-011); only the `status` arguments change.

## Seams

- S1 The ride worktree and the main checkout share one repository config
  (`submodule.<name>.url`, `.active`). TEST-028 builds the submodule
  initialized in the main checkout too and asserts the main checkout's
  `config --get-regexp '^submodule\.'` output and
  `submodule status --recursive` lines are byte-equal before and after apply
  (this is what rules out a deinit-based implementation, F5).
- S2 One verdict, three callers: `planChecks` (exit 3, plan and apply),
  `removeWorktree` (exit 4) and `preflight` (warning line). TEST-029 and
  TEST-030 assert the same reason through `plan` and `apply`; TEST-032 through
  the stop; TEST-033 through preflight.
- S3 `remove-worktree` writes the manifest and `removed.jsonl`; the report
  step and a later run read them. TEST-031 asserts through the saved report
  and the manifest, and a second apply appends no manifest line.
- S4 The prompt's bash block runs `apply` (existing TEST-002, regression) and
  the prompt's wording governs what the agent does after exit 3 or 4
  (TEST-034 pins the wording; obedience itself is residual risk R3).
- S5 Downstream installed layout: no new file under `.aai/`; existing TEST-015
  (core install) is the regression.

## Acceptance Criteria Mapping

- Intake Expected bullet 1 and 2 (remove after proof, recursive) and
  Verification bullet "clean, pushed" -> Spec-AC-01.
- Expected bullet 3 and Verification "dirty" -> Spec-AC-02.
- Expected bullet 3 and Verification "unpushed" -> Spec-AC-03.
- Constraint "gitignored files inside a submodule" -> Spec-AC-04.
- Constraint "never --force before the proof" (race) and Verification
  "mutation ... straight --force" -> Spec-AC-05 plus the mutation rows of
  TEST-029 and TEST-030.
- Expected bullet 4 and Verification "preflight reports the blocker" -> Spec-AC-06.
- Expected bullet 5 and Verification "grep pin on SKILL_MERGE" -> Spec-AC-07.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN apply runs for a merged PR whose ride worktree holds initialized submodules, nested ones included, that are all clean, pushed and stash-free, the system SHALL exit 0, the worktree directory SHALL be gone and absent from `git worktree list`, the ride branch SHALL be deleted by compare-and-swap, and the main checkout's `config --get-regexp '^submodule\.'` output and `submodule status --recursive` lines SHALL be byte-equal to their values before apply; a ride worktree whose submodule is not initialized SHALL also be removed with exit 0. | planned | — | — | D1, D2; seam S1 |
| Spec-AC-02 | WHEN a submodule of the ride worktree has a modified tracked file, an untracked file, or nested dirt, including under `.gitmodules` `ignore = all`, both `plan` and `apply` SHALL exit 3 with `REFUSE submodule_dirty` and a detail naming each offending submodule path, and the world digest (files, worktrees, branches, refs) SHALL be unchanged, so the dirty file survives. | planned | — | — | D2, D3; seam S2 |
| Spec-AC-03 | WHEN a submodule's HEAD, a local branch or a local tag holds a commit on no remote-tracking ref, nested level included, or it has a stash, or no remote, or the worktree admin dir holds a module git dir of no initialized submodule, or the listing of a submodule's ignored files fails, `plan` and `apply` SHALL exit 3 with `REFUSE` and the reason `submodule_unpushed`, `submodule_stash`, `submodule_no_remote` or `submodule_unverifiable` respectively, naming the path, with the world digest unchanged and the unpushed commit still readable by `cat-file -e` in that submodule. | planned | — | — | D2, D3 |
| Spec-AC-04 | WHEN an eligible submodule worktree holds ignored content, apply SHALL archive each ignored regular file byte-equal under `worktree-submodules/<sub path>/` with a manifest line carrying its sha256 and reason `submodule_ignored` before removing the worktree, SHALL name each fully ignored directory in the `remove-worktree` plan targets, in the saved report section `## Removed, not archived` and in `removed.jsonl`, and a second apply SHALL append no manifest or `removed.jsonl` line. | planned | — | — | D4; seam S3 |
| Spec-AC-05 | WHEN a file appears in a submodule after `planChecks` passed and before the removal (seam `before-remove-verify`), apply SHALL exit 4 with `STOPPED submodule_dirty` naming that submodule, the worktree, the file and the branch SHALL survive, and a re-run after the file is removed SHALL exit 0 with the worktree removed; WHEN a submodule's ignored-file listing fails only at the archive step (after the proof passed), apply SHALL exit 4 with `STOPPED submodule_unverifiable` naming that submodule, its ignored files SHALL survive, and a re-run SHALL exit 0 with the worktree removed (amended: review r2 NB-1r2). | planned | — | — | D3, D7 |
| Spec-AC-06 | WHEN preflight passes all gates and the PR's ride worktree has a submodule blocker, preflight SHALL exit 10 and print one `cleanup blocked: <reason> <detail>` line naming the submodule path before the `gh pr merge` line, and `--json` SHALL carry it in `cleanup_blockers`; for a clean ride worktree no such line SHALL appear and `cleanup_blockers` SHALL be an empty array. | planned | — | — | D5; seam S2 |
| Spec-AC-07 | SKILL_MERGE.prompt.md SHALL tell the agent to relay a `cleanup blocked:` line verbatim, and on apply exit 3 or 4 to relay the `REFUSE` or `STOPPED` line verbatim and stop, SHALL contain the phrase `never finish a step by hand` naming `git worktree remove --force`, and SHALL keep `worktree remove --force` in its hard rules; the prompt-diet ledger SHALL carry an entry keyed `merge-cleanup-submodule-worktree` crediting at most 700 bytes; the prompt-diet suite exit 0 is verified by V2 and by that suite itself, not nested inside TEST-034 (post-freeze amendment). | planned | — | — | D6; seam S4 |

## Implementation plan

- .aai/scripts/merge-cleanup.mjs:
  - `submoduleMembers(wtPath)` (recursive gitlink walk, D2) and
    `submoduleBlockers(wtPath)` (the four checks plus the stray-module-dir
    check against `git -C <wt> rev-parse --git-dir`/modules); paths returned
    relative to the worktree, posix.
  - `worktreeVerdict`: explicit superproject status flags (D2), then
    `const blockers = submoduleBlockers(wt.path);` mapped to `[reason, detail]`
    (D3), then the existing tip and lock checks.
  - `archiveSubmoduleIgnored(ctx, wt)` (D4) using `archiveFile`, plus
    `removed.jsonl` append with dedupe; `archivedFromManifest` unchanged;
    `buildReport` gains `removed_unarchived`, `renderReport` the section
    `## Removed, not archived`.
  - `removeWorktree`: no-op path unchanged; archive, seam (D7), final
    `const late = worktreeVerdict(ctx, wt);` -> `stop(...late)`, lock release,
    then plain remove (no members and no modules dir) or `--force` remove.
  - `PLANNERS['remove-worktree']`: the worktree path, then `archive ...` and
    `remove (ignored, not archived) ...` lines.
  - `runPreflight`: `cleanup blocked:` lines and `cleanup_blockers` (D5),
    using `findRideWorktree` against the main checkout.
- tests/skills/test-aai-merge-cleanup.sh: a `build_sub_world <name>` helper
  (bare `nested.git` and `sub.git` origins with `symbolic-ref HEAD`, the
  submodule in the baseline and initialized in the origin checkout, the ride
  running `submodule update --init --recursive`; every submodule git call
  carries `-c protocol.file.allow=always` because the suite sets
  `GIT_CONFIG_GLOBAL=/dev/null`; every setup command through `run`, never a
  bare subshell whose rc is unchecked); TEST-028 to TEST-034 functions,
  selector cases and default run order. New code is verified under the
  suite's own `set -euo pipefail` (no bare `rc=$?`, no `grep | head`).
- .aai/SKILL_MERGE.prompt.md (D6), tests/skills/lib/prompt-diet-ledger.sh
  entry, tests/skills/test-aai-prompt-diet.sh TEST-012 pin.
- docs/product/directed-merge-and-post-merge-cleanup.md (refusal reasons,
  `cleanup blocked:`, the Limits line about forced removal, the archive
  layout) and a CHANGELOG `## [unreleased] — <title>` entry, written after the
  loop completes.
- Edge cases: a submodule path with a space; a submodule whose HEAD is
  detached (the normal case); a submodule whose name differs from its path;
  an old-style submodule whose `.git` is a directory inside the worktree.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-028 | Spec-AC-01 | integration | tests/skills/test-aai-merge-cleanup.sh | test_028_submodule_worktree_removed_after_proof: build_sub_world with sub and sub/nest initialized in the ride and in the origin; apply exits 0; ride dir gone, not in worktree list, branch gone; origin submodule config and submodule status --recursive byte-equal before and after; arm 2: the ride never ran submodule update (uninitialized), apply exits 0 and removes it | sed:s/'remove', '--force', wt\.path/'remove', wt.path/ | green |
| TEST-029 | Spec-AC-02 | integration | tests/skills/test-aai-merge-cleanup.sh | test_029_dirty_submodule_refused: arms modified tracked file in sub, untracked file in sub, modified file in sub/nest, sub dirty with ignore = all in .gitmodules; plan and apply each exit 3 with REFUSE submodule_dirty and the offending path in the detail; world_digest equal before and after; positive control: the dirty file's sha is unchanged and the ride is still in worktree list | sed:s/const blockers = submoduleBlockers\(wt\.path\);/const blockers = [];/ | green |
| TEST-030 | Spec-AC-03 | integration | tests/skills/test-aai-merge-cleanup.sh | test_030_unpushed_submodule_refused: arms committed gitlink to an unpushed sub commit; the same in sub/nest; local branch ahead in sub with HEAD pushed; a stash in sub; sub with its remote removed; a commit reachable only from a local tag with HEAD and the branches pushed; a stray bare git dir under the ride admin dir modules; a sub whose ignored listing fails (seam AAI_MERGE_CLEANUP_FAIL_IGNORED_LS=sub) while holding ignored files; each exits 3 with the named reason (submodule_unpushed, submodule_unpushed, submodule_unpushed, submodule_unpushed, submodule_stash, submodule_no_remote, submodule_unverifiable, submodule_unverifiable) and path, and the ignored files survive the failing-listing arm; world_digest unchanged; cat-file -e of the unpushed sha succeeds after the run | sed:s/const unpushed = Number\(/const unpushed = 0 * Number(/ | green |
| TEST-031 | Spec-AC-04 | integration | tests/skills/test-aai-merge-cleanup.sh | test_031_submodule_ignored_archived_or_named: sub holds an ignored file x.local and a fully ignored dir ign/ with one file; plan lists the archive target and the ign/ removal line; apply exits 0; archive copy sha equals the pre-run sha; manifest has one submodule_ignored line for it; the saved report section Removed, not archived names sub/ign/; removed.jsonl has one line; second apply adds no manifest and no removed.jsonl line | sed:s/archiveSubmoduleIgnored\(ctx, wt\);/void 0;/ | green |
| TEST-032 | Spec-AC-05 | integration | tests/skills/test-aai-merge-cleanup.sh | test_032_late_dirt_stops_then_resumes: clean pushed world; apply with TOUCH_AT before-remove-verify naming a new file in sub; exit 4, STOPPED submodule_dirty sub; ride dir, the touched file and the branch present; the steps before remove-worktree are journalled done; after rm of that file a second apply exits 0, the ride is gone and the branch deleted; archive-listing arm: ignored files in sub and seam FAIL_IGNORED_LS=sub with FAIL_IGNORED_LS_AT=archive; exit 4, STOPPED submodule_unverifiable sub; ride, x.local and ign/out.bin present; a re-run without the seam exits 0 and the ride is gone | sed:s/const late = worktreeVerdict\(ctx, wt\);/const late = null;/ | green |
| TEST-033 | Spec-AC-06 | integration | tests/skills/test-aai-merge-cleanup.sh | test_033_preflight_names_cleanup_blocker: open-PR world built with build_sub_world; arm dirty: preflight exit 10, exactly one cleanup blocked: line naming submodule_dirty and sub, positioned before the gh pr merge line; --json cleanup_blockers length 1; arm unpushed (committed gitlink): reason submodule_unpushed; clean arm: no cleanup blocked: line and cleanup_blockers equals [] (positive control that the key is computed) | sed:s/cleanup blocked: /cleanup-hidden: / | green |
| TEST-034 | Spec-AC-07 | contract | tests/skills/test-aai-merge-cleanup.sh | test_034_canon_stop_and_relay: SKILL_MERGE.prompt.md contains cleanup blocked:, the words relay and verbatim within step 2 or 3, never finish a step by hand, git worktree remove --force outside the hard-rules line and worktree remove --force inside it; prompt-diet ledger has an entry with key merge-cleanup-submodule-worktree whose credit is a positive integer of at most 700 | sed:s/never finish a step by hand/finish steps as needed/ | green |

Mutation targets: .aai/scripts/merge-cleanup.mjs for TEST-028 to TEST-033;
.aai/SKILL_MERGE.prompt.md for TEST-034. The intake's "straight --force"
mutation is TEST-029's row (proof dropped, `--force` path taken): it must turn
TEST-029 red, and TEST-030's row does the same for the unpushed arms.

## Verification

- V1: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-cleanup.sh`
  exits 0. Single test: append the function name or `TEST-0xx`.
- V2: `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
  exits 0 (TEST-010 headroom, TEST-012 pin).
- V3 regression: the suites `node .aai/scripts/select-suites.mjs` picks for the
  changed paths (at least test-aai-merge-cleanup.sh including TEST-002,
  TEST-010, TEST-011, TEST-013, TEST-014 and TEST-015, plus
  test-aai-prompt-diet.sh and test-aai-hygiene-pack.sh) through the wrapper,
  and `node .aai/scripts/docs-audit.mjs --check --strict`.
- V4 mutation: `node .aai/scripts/mutation-run.mjs` per row on the targets
  above, then `mutation-gate.mjs` at close.
- Lint: `node .aai/scripts/spec-lint.mjs --path <this spec>`.

PASS criteria: every TEST row green with a stored RED and a mutation record,
every Spec-AC terminal, V1 to V3 exit 0.

## Evidence contract

Every artifact records ref_id `merge-cleanup-submodule-worktree`, the Spec-AC
and TEST ids, the exact command, exit code, log path and diff or commit
identity. TDD stores RED per AC-gating test, GREEN output and one mutation
record per row under `docs/ai/tdd/spec-merge-cleanup-submodule-worktree/`.
Validation repeats V1 to V3 independently and additionally re-runs the F1 to
F5 measurements on its own scratch repo (the design rests on them). The
Validation report carries an admissible aai-outcome-v1 block, and its path is
the `set-validation --evidence` value.

### Evidence by strategy

Strategy `tdd`: stored RED artifact per AC-gating test under docs/ai/tdd/
plus the full verification matrix V1 to V4.

## Residual risks

- R1 The final verify and the `--force` call are two process spawns apart: a
  file written into a submodule in that window (milliseconds) is deleted. The
  session lock (`session_locked`) keeps another AAI session out of the
  worktree; a human editor writing in that window is not covered. For ignored
  files the window is wider by design (D3/D4 order): a file that becomes
  ignored content, or changes, after `archiveSubmoduleIgnored` listed it and
  before the `--force` call is deleted unarchived, because the late check
  proves tracked and untracked cleanliness, not the ignored set. That span
  covers the archive copy loop and the late check, not milliseconds.
- R2 Native Windows forced removal of a submodule worktree is not exercised
  (D8 named skip); the Node and git calls are the same, file locking on
  Windows may make `--force` fail, which stops with `worktree_remove_failed`
  (exit 4), losing nothing that the proof did not already cover.
- R3 The engine cannot make the agent obey SKILL_MERGE; TEST-034 pins the
  wording only. The engine-side guard is that `apply` refuses or stops before
  the destructive call, so a manual `--force` is the only remaining path.
- R4 Fully ignored directories inside submodules (`node_modules/`, `dist/`,
  and anything else a pattern ignores as a directory) are deleted and named,
  not archived. The superproject's own ignored files outside the D10 runtime
  set are deleted unnamed, as before this scope (suggested follow-up:
  name them too).
- R5 A stale remote-tracking ref in a submodule gives a false
  `submodule_unpushed` (fails closed; remedy `git -C <sub> fetch`).
- R6 Reflog-only commits in a submodule git dir (on no branch, not HEAD, not
  stashed) are lost with the git dir, as the superproject worktree's own HEAD
  reflog already is.

## Assumptions (autopilot, recorded instead of questions)

- A1 "Preflight surfaces the blocker before the merge" (intake) is met by a
  warning line in the same relay as the merge command; preflight does not
  refuse (D5). The owner's `/aai-merge <n>` direction precedes preflight in
  the skill flow, so "before giving the direction" is read as "before the
  merge runs".
- A2 Ignored content: archive single files, name fully ignored directories
  (D4), rather than block or archive everything.
- A3 No fetch in submodules (D2).
- A4 Pester gets a named skip (D8).
- A5 Ceremony level 2: no `protected_paths_l3` surface; the engine is
  SPEC-0218's L2 engine. No new `.aai/**` file, so no PROFILES entry is owed;
  the prompt-corpus companion obligation applies (D6).

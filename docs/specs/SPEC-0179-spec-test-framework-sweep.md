---
id: spec-test-framework-sweep
type: spec
number: 179
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0185-test-framework-sweep.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the test framework fails loudly, finishes sooner, and says what it ran

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0185-test-framework-sweep.md
- Mandate: docs/project-sessions/2026-09-13-wave-3-subsystem-sweeps.md (wave 3, sweep 2)
- Paired maintenance half: docs/issues/CHANGE-0166-residuals-of-the-per-suite-clone-ride.md
- Carried intakes: docs/issues/CHANGE-0180-shared-worktree-moves-another-agents-head.md,
  docs/issues/DEBT-0004-guards-vacuously-green-on-an-unexercised-path.md,
  docs/issues/DEBT-0006-payload-size-hazards-past-the-one-fixed-site.md,
  docs/issues/ISSUE-0039-disposable-checkout-lifecycle-residuals.md,
  docs/issues/ISSUE-0041-hardcoded-path-defeats-suite-isolation.md,
  docs/issues/ISSUE-0043-tripwire-ratchet-arms-without-coverage.md,
  docs/issues/ISSUE-0044-tripwire-reporting-and-run-dir-residuals.md
- Bucket, frozen by id: docs/ai/tdd/spec-test-framework-sweep/bucket-open-2026-09-13.txt
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: every item in this bucket is a test or a guard that reports the wrong
  thing, and the failure mode of the whole class is a green that proves nothing. A
  fix written without first watching the assertion fail would reproduce exactly that
  defect at a larger scale. The intake also records the choice (`## Notes`: ceremony 2,
  TDD, mutation checks per test). RED first per AC-gating test, and a named mutation
  per test besides.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: this scope edits `tests/skills/test-framework.sh` and
  `.aai/scripts/aai-run-tests.sh` — the harness that RUNS the validation of this very
  ride — and it changes the scheduler while suites execute under it. A half-applied
  edit inline does not fail a test, it breaks the process that would have reported the
  failure. The checkout is additionally shared between sessions (the P1 this scope
  fixes, scar of 2026-09-06).
- User decision: worktree
- Base ref: main at 652fd3c9 (branch `feat/test-framework-sweep`)
- Worktree branch/path: `feat/test-framework-sweep`, a sibling worktree named
  `aai-feat-test-framework-sweep` beside the shipping checkout (deliberately written
  as a repo-relative sibling rather than an absolute developer path — 24 merged specs
  already leak one, registry item `fu-specs-embed-developer-local-paths`)
- Inline review scope: `tests/skills/test-framework.sh .aai/scripts/aai-run-tests.sh .aai/scripts/branch-guard.mjs .aai/scripts/lib/session-lock.mjs .aai/scripts/lib/append-lock.sh .aai/scripts/close-before-push-guard.mjs .aai/scripts/check-committed-scope.mjs .aai/scripts/golden-flow.mjs .aai/scripts/select-suites.mjs .aai/SKILL_PR.prompt.md .aai/SKILL_TDD.prompt.md .aai/VALIDATION.prompt.md .aai/system/PROFILES.yaml docs/knowledge/LEARNED.md tests/skills/suite-map.yaml tests/skills/lib/assert-payload.sh tests/skills/lib/pipe-grep-q-ratchet.sh tests/skills/lib/pipe-grep-q-baseline.tsv tests/skills/lib/prompt-diet-ledger.sh tests/skills/test-aai-layer-profiles.sh tests/skills/test-aai-feedback-upsert.sh tests/skills/test-aai-friction-wiring.sh tests/skills/test-aai-suite-isolation.sh tests/skills/test-aai-repo-tripwire.sh tests/skills/test-aai-sweep-parallel.sh tests/skills/test-aai-branch-guard.sh tests/skills/test-aai-run-tests.sh tests/skills/test-aai-hygiene-pack.sh tests/skills/test-aai-follow-ups.sh tests/skills/test-aai-release.sh tests/skills/test-aai-ceremony-levels.sh tests/skills/test-aai-docs-audit.sh tests/skills/test-aai-prompt-diet.sh tests/skills/test-aai-orchestration-dispatch.sh tests/skills/test-aai-spec-tools.sh tests/skills/test-aai-spec-lint.sh tests/skills/test-aai-spec-amend.sh tests/skills/test-aai-git-ref-guard.sh tests/skills/test-aai-deslop.sh tests/skills/test-aai-golden-flow.sh tests/skills/test-aai-session-lock.sh tests/skills/test-aai-doctor.sh tests/skills/test-aai-delta-stage3.sh tests/skills/test-aai-suite-select.sh plus the 31 suite files enumerated in tests/skills/lib/pipe-grep-q-baseline.tsv docs/specs/SPEC-0146-spec-drain-the-tripwire-known-offender-list.md docs/specs/SPEC-0179-spec-test-framework-sweep.md docs/issues/CHANGE-0166-residuals-of-the-per-suite-clone-ride.md docs/issues/CHANGE-0180-shared-worktree-moves-another-agents-head.md docs/issues/DEBT-0004-guards-vacuously-green-on-an-unexercised-path.md docs/issues/DEBT-0006-payload-size-hazards-past-the-one-fixed-site.md docs/issues/ISSUE-0039-disposable-checkout-lifecycle-residuals.md docs/issues/ISSUE-0041-hardcoded-path-defeats-suite-isolation.md docs/issues/ISSUE-0043-tripwire-ratchet-arms-without-coverage.md docs/issues/ISSUE-0044-tripwire-reporting-and-run-dir-residuals.md docs/ai/decisions.jsonl CHANGELOG.md`

## Planning correction recorded after the freeze write

Disclosed rather than silently applied. Immediately after `spec-freeze.mjs` wrote the
marker, and before any handoff, Planning corrected two NON-AC lists that still named
artifacts it had dropped during planning: the inline review scope (it said
`tests/skills/lib/assert.sh`, which does not exist — the file is
`tests/skills/lib/assert-payload.sh` — and omitted five suites this scope edits) and
the Verification suite list (it named `test-aai-assert-payload.sh` and
`test-aai-guard-controls.sh`, two suites the plan deliberately does NOT create, the
helper tests going into the hygiene pack and each negative control into the suite of
the guard it controls). No Spec-AC text, no Test Plan row, no mutation and no decision
was touched.

## What is established before this scope starts

Measured on 2026-09-13 in the worktree `aai-feat-test-framework-sweep` at
`652fd3c9`, every count under `bash -c` with `/usr/bin/grep` (`grep` is aliased to
ugrep in the authoring shell, and zsh rewrites `$r:tests/...`).

1. **The wide sweep already shipped.** Commit `12112e4f` — "perf(harness): run the
   sweep concurrently at a bounded width (CHANGE-0166) [L2] (#307)" — gave
   `tests/skills/test-framework.sh` a bounded-width wave scheduler
   (`PARALLEL_WIDTH`, `parallel_probe`, `run_wave`), default `min(8, cpus - 2)`,
   `AAI_TEST_PARALLEL` override, `1` a first-class serial value, and isolation-off
   forcing serial. `/usr/bin/grep -cE 'xargs -P|[^&]& *$|^ *wait$|parallel'` over that
   file returns 8, not the 0 recorded in CHANGE-0166. The paired maintenance half is
   therefore not a build; it is a verification, a measurement and a close.
2. **All three concurrency hazards CHANGE-0166 named are already handled.** The
   tripwire window is the WAVE, and a dirty wave is discarded and re-run one suite at
   a time (`run_wave`, and the re-run widens `TRIPWIRE_WATCH_PATHS` with the wave's
   changed paths because `git status` reports a path's CLASS). Appends to
   `docs/ai/tests/test-runs.jsonl` go through `.aai/scripts/lib/append-lock.sh`, a
   `mkdir` mutex sourced fatally. `RUN_ID` collisions resolve through an atomic
   `mkdir` without `-p`. The registry agrees: `fu-sweep-is-strictly-sequential`,
   `fu-dispatch-demands-full-sweep` and `fu-framework-rundir-same-second` are all
   `done`, resolved by PR #307.
3. **`docs/issues/CHANGE-0166-...md` is still `status: draft` with `links.pr: []`**
   and its body carries pre-#307 numbers. Its work shipped two weeks ago.
4. **The remaining cost is the BARRIER, not the width.** `main()` accumulates
   suites into a fixed wave of exactly `PARALLEL_WIDTH` and `run_wave` waits for ALL
   members before the next wave starts, so a wave costs `max(its members)` and freed
   slots are never refilled. Measured on the newest sweep carrying per-suite data
   (`test-20260912-173455`, 92 suites): suite-seconds sum 3220 s, median suite 6 s, 51
   of 92 under 10 s, top 12 suites 1964 s = 61 percent, longest suite
   `aai-delta-stage3` 340 s — and 9220 idle slot-seconds.
5. **The wall-clock today.** Newest full local sweep `test-20260913-040817`: 92
   suites, 92 PASS, `parallel_width: 8`, `waves_reattributed: 0`, 04:08:17Z to
   04:35:29Z = **1632 s (27.2 min)**. The width-8 median has regressed as suites were
   added: 978 s at 84 suites (2026-08-31), 1397 s at 90 (2026-09-07), 1632 s at 92.
   On CI the full-sweep job of run `34743182794` (main, green) took **1448 s (24.1
   min)** at `AAI_TEST_PARALLEL: '4'` against `timeout-minutes: 30` — six minutes of
   headroom on a corpus that grew 654 s in thirteen days.
6. **Suite selection is half-wired.** `.aai/VALIDATION.prompt.md:173-184` already
   states the SELECTED-plus-CORE rule and names
   `node .aai/scripts/select-suites.mjs --files-from <changed files>` (this is
   CHANGE-0166 AC-004, landed with #307). `/usr/bin/grep -n 'select-suites'` over the
   prompt corpus returns exactly ONE hit, that line. There is no `.aai/TDD.prompt.md`
   in this repository; the file is `.aai/SKILL_TDD.prompt.md`, and its Phase-4 step 0
   calls an unconditional full sweep at ceremony 2 and 3 with no knowledge of the
   selector.
7. **The prompt-diet gate is corpus-wide, and nearly full.** There is no per-file
   byte or line pin on `.aai/VALIDATION.prompt.md` (20663 B) or
   `.aai/SKILL_TDD.prompt.md` (16697 B). `tests/skills/lib/prompt-diet-ledger.sh`
   holds `BASELINE_PROMPT_BYTES=357457`, `REQUIRED_REDUCTION_BYTES=28672`,
   `HEADROOM_CAP=2048`; measured today `headroom = 2046` of 2048. Any prompt growth
   past 2046 bytes without a `JUSTIFIED_ADDITIONS` entry reddens TEST-010, and the
   entry must be matched by the `want_growth=26515` pin at
   `tests/skills/test-aai-prompt-diet.sh:786` (TEST-012).
8. **`branch-guard.mjs` has no notion of an expected sha.** Its whole contract is
   `Usage: node branch-guard.mjs [--base <branch>] [--suggest] [--state <path>]`, it
   compares the current branch name against `current_focus.ref_id` by substring, and
   it runs exactly ONCE per ceremony, as `.aai/SKILL_PR.prompt.md` PRECONDITION 0.
   Nothing re-checks afterwards, and `tests/skills/test-aai-branch-guard.sh` does not
   pin its usage string, so a new flag trips no pin.
9. **No `.aai` script performs the ceremony's git writes.** A search for
   `execFileSync('git', ['add' | 'commit' | 'push' | 'checkout' | 'reset' ...])` over
   `.aai/scripts/*.mjs` returns one hit, `allocate-doc-number.mjs` pushing reservation
   refs. Every stage, commit and push in SKILL_PR is issued by the agent from prose,
   so a guard can only be enforced where a SCRIPT still stands between the agent and
   the write: `check-committed-scope.mjs`, `close-work-item.mjs` and
   `close-before-push-guard.mjs`.
10. **Lock prior art exists and is the right shape.** `.aai/scripts/docs-lock.mjs`
   holds a TTL lease with an `O_EXCL` CAS, a `pid` field, a contention exit code 3 and
   a serialized expired-lock reclaim; `.aai/scripts/lib/append-lock.sh` is the
   portable `mkdir` mutex; `.aai/scripts/heartbeat.mjs` already stores per-worktree
   state under `$(git rev-parse --git-dir)/aai/`, which is structurally uncommittable.
   No pid-liveness probe exists anywhere in the layer. Heartbeat FILES are off limits
   to any gate by an explicit, tested rule, so this scope copies the payload shape and
   never reads a heartbeat.
11. **GitHub #368 carries no reproducible claim.** Its entire body is a friction
   metadata block: `failure_class: deterministic_script_failure`,
   `skill: REMEDIATION / reproduce`, `os_family: windows`, `aai_pin: v2026.08.16`, and
   `evidence_ref: docs/ai/reports/VALIDATION-20260826-161909Z-prd009-mms-control-input-scope.md`.
   No comments. That path does not exist in this repository and nothing matching
   `prd009` or `mms-control-input` does either; it is a downstream install's artifact.
12. **The pipe-into-`grep -q` ratchet is already half drained, and both DEBT-0006's
   body and the registry item say otherwise.** The originating scope recorded 389
   occurrences over 38 files; PR #315 took it to **202 over 31 files**, and
   `tests/skills/lib/pipe-grep-q-baseline.tsv` is exactly in sync with the tree today
   (no RISE, NEW, SHRINK or GONE). The ratchet is a PER-FILE TSV baseline, not a
   scalar maximum. Of the 202, only 5 are a drop-in substitution with the helper that
   exists: 104 are case-insensitive, 95 use ERE, 79 are anchored, 41 carry regex
   metacharacters and 7 are negated control flow. Three new helpers are therefore a
   precondition of the drain, not a convenience.
13. **DEBT-0004 ships no inventory.** Its only registry id is
   `fu-release-guards-forbid-release-by-pr`, which it declares already fixed and out of
   scope. Building the inventory is the work; nine guards of the shape were found and
   are named in the implementation plan. Two adjacent measurements: the exit-contract
   phrases pinned from `spec-freeze.mjs` each occur exactly TWICE in that file (header
   comment at lines 54-61, runtime strings at 101-107), so the pin passes on a broken
   CLI; and `test-aai-ceremony-levels.sh:1087`'s `git diff --exit-code` with no ref
   compares worktree against index, so it reddens only while an edit is unstaged and
   goes silent the moment it is committed (verified in a scratch repository).
15. **The `tail -3` half of the nesting defect is already delivered.** Commit
   `02455b73` replaced it; both wrappers now run
   `grep -n -A40 "FAIL" | head -60` over the nested output
   (`tests/skills/test-aai-feedback-upsert.sh:1444-1445`,
   `tests/skills/test-aai-friction-wiring.sh:238` and `:240`), and an induced failure in
   a scratch clone proved the path works end to end. The residual is narrower: the
   wrapper renders the whole nested failure into ONE `log_fail` argument, so the
   framework's own failure-line extraction (`tests/skills/test-framework.sh:1345`,
   `:1368`) shows only its first line.
16. **The CI failure this sweep was called for is NOT what the registry says.** In run
   `34737181188`, the standalone `aai-layer-profiles` suite PASSED at 18 s in the same
   width-4 sweep in which `aai-feedback-upsert`'s NESTED copy of it failed at 9 s. The
   failure is specific to the nested invocation, not to load on a shared tree. And the
   nested failure's payload was EMPTY: `FAIL: core sync MISSING core-listed files:` was
   the last line of the nested output, with no path after it. An incomplete copy
   produces a non-empty, printable list — so the incomplete-copy story does not explain
   this failure. Something made `[[ -z "$missing" ]]` false on a value that renders as
   zero visible lines, and planning could not construct that state.
17. **What the fixture build actually does.** `build_fixture_sources`
   (`tests/skills/test-aai-layer-profiles.sh:111-159`) issues four unchecked `cp -R`
   calls (`:119`, `:124`, `:126`, `:145`) and never verifies the result: nothing
   compares the produced file set against the source. Under `set -euo pipefail` a
   `cp` that FAILS aborts the suite loudly; a `cp` that succeeds INCOMPLETELY is
   invisible. Separately, every one of the fifteen `aai-sync.sh` invocations in that
   suite is redirected to `/dev/null 2>&1`, which is where the
   `WARN core-listed file missing in source (skipped)` line (`.aai/scripts/aai-sync.sh:296-299`,
   which `continue`s and still exits 0) is discarded. Neither is a race; both are
   missing checks.
18. **Degenerate branches that pass.** `/usr/bin/grep -rn 'log_pass' tests/skills/*.sh`
   filtered case-sensitively for `skipped` or `not applicable` returns **31** (35
   only with `grep -i`; corrected at remediation, validation round 1 BLOCKING-7 —
   the original text here said 35 without disclosing the case-insensitive recipe,
   which does not match `degenerate-pass-ratchet.sh`'s own case-sensitive scan; see
   `## Amendment`). Most are legitimate platform skips, which is why Spec-AC-14
   converts the nine guards and ratchets the rest rather than banning the shape.
   `.aai/scripts/*.mjs` files referencing `process.argv[1]`: **24**.

- **2026-09-14, orchestrator ledger repair (after merging main at PR #379):** the AC-26 closure had dropped five owner sign-off trackers (`fu-amend-live-agent-dashboard-ser-e1ff12`, `fu-amend-roadmap-driven-ride-sele-1e2448`, `fu-amend-lessons-that-must-hold-d-13bccc`, `fu-amend-friction-publish-hides-r-b86049`, `fu-amend-spec-harness-universal-routing`) as "owner sign-off backlog". A sign-off item is not a test-framework item, and dropping its tracker left thirteen unsigned amendment records with no OPEN item, which the ledger-derived TEST-009 of `test-aai-spec-amend.sh` (merged in PR #379) reports. Repair, append-only: five re-track items (`fu-amend-live-agent-dashboard-retrack`, `fu-amend-roadmap-driven-ride-retrack`, `fu-amend-lessons-must-hold-retrack`, `fu-amend-friction-publish-hides-retrack`, `fu-amend-harness-universal-retrack`) and one `classify --signoff none --tracked-by` overlay per record. The five dropped ids stay terminal (TEST-443 and the row-count pin are unchanged); the rejected-items table row for each now says "re-tracked, not a framework item".

- **2026-09-14, remediation round 4 correction of the above (validation round 5
  BLOCKING-2):** the retrack repair did not do what it claimed. `spec-amend.mjs`'s
  own documented precedence (`:336-339`, "the record's OWN tracked_by wins; an
  overlay must not be able to re-point a live record's item") means an overlay
  can NEVER re-point a record's inline `tracked_by` — and 12 of the 13 affected
  records carried one, pointing straight at the now-dropped original id. Only
  the one record with no inline `tracked_by` (`2026-09-12T12:50:00Z`,
  `friction-publish-hides-required-followup`) actually picked up its overlay.
  Measured: `spec-amend.mjs list --status unsigned --json` showed the retrack
  ids' `-retrack` ids present in `follow-ups.mjs list --status open` (the
  governance surface an owner actually reads), while 12 of 13 unsigned records
  still resolved to a DROPPED tracker — the repair turned a red governance gate
  green on a description substring TEST-009 matched, not on a genuinely open
  item. The real fix, added this round: `follow-ups.mjs reopen` (new
  subcommand, `test-aai-follow-ups.sh` TEST-456) appends a `status: open`
  `follow_up_status` record — the counterpart `close` never had
  (`fu-registry-has-no-reopen`, closed here: it is owned by another sweep's
  bucket, but this ride happened to deliver the mechanism it asked for while
  fixing its own mistake). The five ORIGINAL ids are reopened with that
  command (reason: "dropped in error by test-framework-sweep AC-26: an owner
  sign-off item is not a framework item"), the five `-retrack` items are
  dropped as duplicates, and the one orphan record's overlay is re-pointed
  (`spec-amend.mjs classify --tracked-by`) at the reopened original. The five
  ids are REMOVED from `## Registry items rejected by this scope` entirely
  (see that section) rather than re-added under any status: they were never
  this scope's items to close. `spec-amend.mjs list --status unsigned --json`
  now shows all 13 affected records' `tracked_by` resolving to an OPEN item
  (13/13, measured), and `follow-ups.mjs list --status open` shows the five
  ORIGINAL ids, not the retracks. Re-verifying with the corrected TEST-009
  (id-token match, not a description substring) surfaced a SIXTH instance of
  the identical mistake, outside the five the validator named:
  `fu-amend-friction-upsert-channel-ba7701` (spec
  `friction-upsert-channel-cannot-file`) was dropped by this scope's AC-26
  closure with the same "owner sign-off backlog" rationale and had no
  re-track attempt at all — its own six unsigned records were masked by the
  same substring bug, this time via an UNRELATED open item
  (`fu-factory-report-stale-draft-path`) that merely quotes the dropped id in
  its own finding text. Fixed the same way (reopened, removed from the
  rejected table) rather than left for a seventh round: the bucket total is
  therefore 78 (48 + 30), not 79. See `## Amendment` for the full record.

## Decisions

### D1 — A sweep partitions its whole bucket; nothing is deferred

The bucket is the 84 open follow-ups whose id or finding names the framework
(test, suite, framework, hygiene, isolation, tripwire, sweep, fixture, mutation,
ratchet, flake, seed, checkout, worktree, clone), re-derived live at freeze from
`node .aai/scripts/follow-ups.mjs list --status open --json` and byte-identical to the
frozen list at `docs/ai/tdd/spec-test-framework-sweep/bucket-open-2026-09-13.txt`
(diff of the two id sets: empty both ways). Every id ends in exactly one of two
states, both recorded in the ledger:

- **fixed** — named in `## Registry items closed by this scope`, mapped to a Spec-AC
  and to a TEST row with a named mutation, closed with
  `follow-ups.mjs close --id <id> --resolved-by test-framework-sweep --source <sha>`;
- **rejected** — named in `## Registry items rejected by this scope` with a one-line
  reason, closed with the same command plus `--status dropped`.

A rejection is one of four reasons and never a fifth: the claim is withdrawn or no
longer reproduces; the fix is prose only with no surface to assert; it duplicates an
item this scope fixes; or its subject is a different subsystem, in which case the
reason NAMES the sweep that owns it. `node .aai/scripts/follow-ups.mjs verify-closures
--path <this spec> --strict` is the mechanical check that the claim above is true, and
it is an AC.

### D2 — A fixture that could not be built fails at the build, and an assertion that cannot render its payload dumps it

The registry calls this a race. Measured, it is two missing checks and one unexplained
observation, and the decision is to fix the checks rather than to chase the race.

The build issues four unchecked `cp -R` calls and never compares what it produced with
what it copied from, so a copy that succeeds INCOMPLETELY is invisible; and the suite
redirects every `aai-sync.sh` invocation to `/dev/null`, which is where the sync's
`WARN core-listed file missing in source (skipped)` line dies — the sync itself
`continue`s and exits 0. Both become loud: the build verifies its own output and names
every path that is missing; the suite captures the sync's output and fails on the WARN.

The third change is the one the CI evidence actually demands. In the failing run the
assertion fired with a payload that printed NOTHING, which no incomplete copy can
produce. So an assertion that fires on a payload rendering as zero visible lines dumps
that payload byte for byte instead of printing an empty list. That is not a guess about
the mechanism; it is the instrument that would have identified it, and it is the honest
deliverable for a failure nobody has reproduced.

### D3 — A wrapper that nests a suite hands the reader a file, not a string

The `tail -3` this scope was dispatched to remove is already gone: commit `02455b73`
replaced it in both wrappers with `grep -n -A40 "FAIL" | head -60`, and planning proved
that path works by inducing a real nested failure. The residual is narrower and is what
the CI log shows: the wrapper passes the whole nested failure as ONE `log_fail`
argument, and the framework's own failure-line extraction then shows only its first
line. So the wrapper writes the nested output to a file and names that file and its
line count in the failure message. The registry item is closed on that residual, with
the already-delivered half recorded rather than claimed.

### D4 — The ceremony pins the HEAD it started on, and re-checks it at every surviving script chokepoint

`branch-guard.mjs` gains `--pin` and `--verify-pin`. `--pin` records the branch, the
HEAD sha, the pid and the worktree root into
`$(git rev-parse --git-dir)/aai/branch-pin.json` — per-worktree by construction,
structurally uncommittable, and therefore owing no `.gitignore` entry. `--verify-pin`
re-reads it and refuses non-zero when the current branch or HEAD sha no longer matches,
naming both the expected and the actual value. Three causes are distinguished in the
message rather than collapsed (CHANGE-0180 AC-003): HEAD detached, the branch renamed
under the session, and a concurrent session having moved HEAD.

Enforcement rides the three scripts that still stand between the agent and a write
(established fact 9): `check-committed-scope.mjs` (runs immediately after every
commit), `close-before-push-guard.mjs` (immediately before the push) and
`close-work-item.mjs` (the close). Each gains an `--expect-branch` re-check. A ceremony
that never pinned is unaffected, which is CHANGE-0180 AC-004: absence of the pin file
is the first early exit and costs one `stat`.

CONSIDERED AND NOT TAKEN: enforcing the pin in the `.git/hooks/reference-transaction`
guard, which does fire on the OTHER session's `git checkout` and could therefore
PREVENT rather than detect. It is rejected here for two reasons and the second is
decisive: the hook is opt-in and is not inherited by a clone, so it cannot be the
portable half; and changing what that hook refuses is consumer-visible git behaviour,
which is the scope of `update-installs-ref-guard-undisclosed` (ISSUE-0083, sweep 5,
owner-merged). Recorded as residual risk R2.

### D5 — A second live session in the same worktree is refused, not detected

A per-worktree session lock lives beside the pin at
`$(git rev-parse --git-dir)/aai/session.lock`, written with the `O_EXCL` CAS
`docs-lock.mjs` already uses, carrying `{pid, worktree, ref_id, acquired_utc}`.
Liveness is a `process.kill(pid, 0)` probe, NOT a TTL alone: a TTL long enough for a
ceremony is too long to reclaim after a crash, and a pid that is gone is the one signal
that is both cheap and certain. A dead holder's lock is reclaimed through the same
serialized sentinel `docs-lock.mjs` uses; a LIVE holder's lock refuses the second
session with exit 3 and names the holding pid. Heartbeat files are not read: a gate
reading a heartbeat is forbidden by a tested rule of this repository.

### D6 — The sweep's remaining cost is the barrier, and the attribution window is what replaces it

Fixed waves leave 9220 idle slot-seconds in a 92-suite sweep (established fact 4). The
scheduler becomes a refilling work queue: a free slot takes the next suite immediately
instead of waiting for its wave-mates. What the barrier BUYS is attribution — the
tripwire snapshot pair spans one wave, so a shipping-repository change is attributed to
a wave of at most `PARALLEL_WIDTH` suites, and a dirty wave is discarded and re-run
serially. A queue has no wave, so the window must become explicit: one snapshot pair
spans the whole concurrent phase, and a dirty phase re-runs EVERY suite serially with
the same widened watch set. Detection is unchanged and unconditional; attribution costs
a full serial re-run instead of a wave-sized one, on an event whose production
frequency is measured at zero (`waves_reattributed: 0` in every full-sweep record
inspected). The exact width and the measured after-number are named in Spec-AC-05 and
are a deliverable of the implementation, not a claim of this section.

### D7 — A ratchet asserts the property it means, and keeps a legal one-line repair

Four of this bucket's pins fail the same way: they assert a COUNT or a BYTE-IDENTITY
where the property is a SUBSET or a BEHAVIOUR, so the cheapest legal edit reddens a
test written for a different scope. TEST-013 of the tripwire suite means "neither
fixture suite is in the offender table", not "the table has zero entries". TEST-029 and
the Spec-AC-11 allowlist pin in the follow-ups suite mean "no entry outside the
allowlist", not "exactly three entries". TEST-016 of the ceremony suite means "the
ceremony behaviour this spec fixed still holds", not "this shared library is byte-
identical to the day SPEC-0041 merged". Each becomes an assertion of the property with
a drainable bound, and each keeps a negative control so that draining it cannot make it
vacuous.

### D8 — A guard that compares a file against itself gets a negative control

DEBT-0004's class: an assertion that can only pass. The two shapes measured in this
bucket are a pin that greps the WHOLE file for a string the same file's own header
comment also contains (`fu-exit-contract-pin-comment-dup`), and an arm whose claim
lives only in a `log_pass` string (`fu-allowlist-count-is-prose-not-asserted`). Every
such guard gains a negative control: a mutation the guard MUST fail on, exercised in
the same arm against a scratch copy, so a guard that stops guarding turns red instead
of staying green.

### D9 — An assertion never dies on its own payload

DEBT-0006's idiom is `printf '%s' "$out" | grep -q <pattern>` and its family: under
`set -o pipefail` a large or odd payload can kill the assertion, and the exit status
belongs to the pipeline rather than to the claim. The idiom is drained to zero in
`tests/skills` in favour of the `tests/skills/lib` helper, and the ratchet that counts
it is held at zero with a negative control proving the counter still counts.

### D10 — Lessons that are guards become guards, in the hygiene pack

Six entries in `docs/knowledge/LEARNED.md` carry a `[guard -> fu-learned-*]` marker,
which by that file's own contract means "the enforcement belongs in the layer and this
id is the follow-up that will build it". They are built here, as rules in
`tests/skills/test-aai-hygiene-pack.sh` over `tests/skills/**` and the vendored prompt
corpus, and each marker is re-pointed at the shipped guard. A lesson whose right home
is canon rather than a lint is rejected to the sweep that owns canon.

## Scope

In scope: the 48 registry items listed under `## Registry items closed by this scope`;
CHANGE-0166's verification, measurement and close; CHANGE-0180's pin and session lock;
DEBT-0004's negative controls; DEBT-0006's drain; the four ISSUE intakes' framework
halves; the prompt-diet ledger true-up and the `PROFILES.yaml` classification these
edits oblige.

Out of scope, stated so the delivery is not read as more than it is:

- **This scope does not prove the CI-only layer-profiles failure is gone.** It makes
  the fixture build fail loudly and the wrappers print the nested failure, so the NEXT
  occurrence names its cause. If the mechanism is a copy that was never complete, the
  build now refuses; if it is something else, the message identifies it. Claiming the
  flake fixed would be a claim no local run can support (residual risk R1).
- `close-work-item.mjs` internals, the close ceremony and docs-audit (sweep 4).
- The dispatcher, `state.mjs` and the `fu-role-guard-*` class (sweep 3); `state.mjs`
  is additionally a `protected_paths_l3` surface and editing it would force ceremony 3.
- Windows beyond GitHub #368, which is rejected below.
- The `reference-transaction` guard's refusal set (ISSUE-0083, sweep 5).

## Constitution deviations

None.

- Article 2 (simplicity): one new lib module (the session lock), two new flags on an
  existing guard, one scheduler loop replaced by another of the same size; no
  framework, no dependency.
- Article 3 (portability): the session lock uses the `O_EXCL` CAS and the `mkdir`
  mutex this repository already ships for exactly this reason; `flock` is absent on
  macOS and is not used.
- Article 4 (degrade and report): every fix in this scope converts a silent degrade
  into a named refusal, which is the article stated as a work item.
- Article 5 (additive first): `--pin` and `--verify-pin` are additive flags; a
  ceremony that never pins behaves byte-identically, which is Spec-AC-04's own control.

## Acceptance Criteria Mapping

- Maps to: CHANGE-0185-test-framework-sweep "Desired Behavior (To-Be)" bullets 1 to 5;
  CHANGE-0166 AC-001 through AC-004; CHANGE-0180 AC-001 through AC-005; DEBT-0004;
  DEBT-0006; ISSUE-0039, ISSUE-0041, ISSUE-0043 and ISSUE-0044's framework halves.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | The layer-profiles fixture build SHALL check every `cp -R` it issues, SHALL compare the file set it produced against the file set it copied from, and SHALL exit non-zero naming every path that is missing, before any assertion runs. | done | docs/ai/tdd/spec-test-framework-sweep/green-401.txt; validation-round6.txt | — | fu-layer-profiles-fixture-build-race |
| Spec-AC-02 | WHEN the core sync emits a line matching `missing in source` the suite SHALL fail naming that line rather than discard it to `/dev/null`, and WHEN an assertion fires on a payload that renders as zero visible lines it SHALL dump that payload byte for byte instead of printing an empty list. | done | docs/ai/tdd/spec-test-framework-sweep/green-402.txt; green-403.txt; validation-round6.txt | — | fu-layer-profiles-suite-load-fragile; the CI failure of run 34737181188 printed an EMPTY missing-file list, which no incomplete copy can produce |
| Spec-AC-03 | WHEN a ceremony has pinned its HEAD and the branch or the HEAD sha differs at a later write step, that step SHALL exit non-zero naming the expected and the actual value, and SHALL name detached HEAD, a renamed branch and a concurrent session as three distinct causes. | done | docs/ai/tdd/spec-test-framework-sweep/green-405.txt; green-406.txt; green-407.txt; validation-round6.txt | — | CHANGE-0180 AC-001 to AC-003, fu-head-moved-between-commands; residual R6 (validation round 5 F-A, see `## Amendment` and R6 above): the advance-only sha arm cannot tell the ceremony's own forward commit from a concurrent session's forward commit on the same branch — D5's session lock (Spec-AC-05) is the actual control for that case, not this check |
| Spec-AC-04 | WHEN no pin file exists, `--verify-pin` and every re-check call site SHALL exit 0 without reading git, and the stdout and exit code of each ceremony script SHALL be byte-identical to the pre-change script on the same fixture. | done | docs/ai/tdd/spec-test-framework-sweep/green-408.txt; validation-round6.txt | — | CHANGE-0180 AC-004; remediation (validation round 1 BLOCKING-1/2, see `## Amendment`): `pinDir()` forked `git rev-parse --git-dir` even on the no-pin path — measured with a git shim, one subprocess on a no-pin fixture, contradicting D4's "costs one stat". A `pinDirFast()` fs-stat-only resolver (handling a main checkout's `.git` directory and a linked worktree's `.git` file, falling back to the git subprocess for anything else) now makes the no-pin path genuinely zero-subprocess, re-verified with the same shim. TEST-408's baseline also moved from `git show HEAD:` (already the POST-change script, an identity check) to `git show origin/main:` (or `main`, fail-closed if neither resolves) — the genuine pre-change blob |
| Spec-AC-05 | WHEN a second process acquires the per-worktree session lock while the holder pid is alive, the acquire SHALL exit 3 naming the holding pid and worktree, and WHEN the holder pid is gone the lock SHALL be reclaimed and the acquire SHALL exit 0. | done | docs/ai/tdd/spec-test-framework-sweep/green-409.txt; green-410.txt; validation-round6.txt | — | CHANGE-0180 scope half two, fu-learned-worktree-seeded-copies |
| Spec-AC-06 | WHEN the sweep runs at a width above 1 a free slot SHALL start the next suite without waiting for its concurrently-running siblings, and the measured wall-clock of a full local sweep SHALL be at most 65 percent of the 1632 s recorded for run test-20260913-040817 at the same width, with a per-suite verdict set identical to a width-1 run. | done | docs/ai/tdd/spec-test-framework-sweep/green-411.txt; green-412.txt; validation-round6.txt (run test-20260913-185949: 93/93, 897 s = 55 percent of 1632 s; 93/93 on the delivered tree test-20260914-005111) | — | CHANGE-0166 AC-001 |
| Spec-AC-07 | WHEN a shipping-repository change is detected during the concurrent phase, the run SHALL still name the writing suite, the serial re-run SHALL cover at most 2 times PARALLEL_WIDTH suites rather than the whole corpus, and a run in which nothing writes SHALL report the same verdicts as a serial run. | done | docs/ai/tdd/spec-test-framework-sweep/green-413.txt; green-414.txt; validation-round6.txt | — | CHANGE-0166 AC-002; remediation (validation round 1 BLOCKING-4, see `## Amendment` and R4 above): the 2x-width truncation was dead code on every real run (structurally, the per-completion-check design bounds the window at `PARALLEL_WIDTH`, not 2x) — TEST-413 now proves it is load-bearing anyway via a genuine negative control on a 10-suite/late-writer fixture |
| Spec-AC-08 | WHEN the canonical wrapper command runs a full sweep with no `AAI_TEST_TIMEOUT` set, the run SHALL complete rather than exit 124, and any wrapper timeout SHALL print one line naming the elapsed limit and the override, on EVERY platform this scope's own contract claims (sh, WSL and Git-Bash-only, since `aai-run-tests.sh:56-60` states the timeout raise is "kept identical across this header, aai-reap-tests.sh, aai-run-tests.ps1, aai-reap-tests.ps1"). | done | docs/ai/tdd/spec-test-framework-sweep/green-415.txt; validation-round6.txt | — | fu-sweep-dies-at-wrapper-default; remediation (validation round 1 BLOCKING-22, see `## Amendment`): `aai-run-tests.ps1`'s `Get-EffectiveTimeout` still returned 300 and forced that value into the inner `.sh` on both the WSL and Git-Bash paths, silently overriding the `.sh` wrapper's raise to 3000 on every Windows run — the parity claim was false. Now raises to 3000, matching the `.sh` wrapper exactly; the header comment and the Pester fixtures that pinned the old 300 default (`aai-win-dispatch.Tests.ps1`) are updated to match, and a new grep-based check in `test-ps1-quality.sh` (runs without `pwsh`, unlike the Windows-5.1-only Pester leg) pins the two defaults equal going forward |
| Spec-AC-09 | WHEN a sweep is in flight the framework SHALL write a heartbeat slot through the shipped `heartbeat.mjs` carrying the finished-suite count and the discovered total, so the existing live page shows it with no change to the page, and the slot SHALL stop being refreshed when the run ends. | done | docs/ai/tdd/spec-test-framework-sweep/green-416.txt; validation-round6.txt | — | fu-live-page-blind-to-the-sweep; the page already lists `hb-*` slots and the runner writes none |
| Spec-AC-10 | WHEN `golden-flow.mjs` appends a record, the append SHALL go through the same lock as the other ledgers under `docs/ai/`, and 12 concurrent appends SHALL produce 12 whole parseable records with the pre-existing bytes still a prefix. | done | docs/ai/tdd/spec-test-framework-sweep/green-417.txt; validation-round6.txt | — | fu-golden-flow-record-append-unlocked |
| Spec-AC-11 | The count returned by the shipped ratchet scan over `tests/skills` SHALL be 0, every row of `tests/skills/lib/pipe-grep-q-baseline.tsv` SHALL be 0, and the ratchet SHALL still fail on a planted occurrence. | done | docs/ai/tdd/spec-test-framework-sweep/green-418.txt; green-419.txt; green-420.txt; validation-round6.txt | — | DEBT-0006, fu-drain-pipe-grep-q-ratchet; 202 occurrences over 31 files today |
| Spec-AC-12 | Each of the nine guards named in the implementation plan SHALL carry a negative control that mutates, in a scratch copy, the thing the guard claims to protect, and the guard SHALL be observed failing on that mutation. | done | docs/ai/tdd/spec-test-framework-sweep/green-421.txt; green-445.txt; green-446.txt; green-447.txt; green-448.txt; green-422.txt; validation-round6.txt | — | DEBT-0004, fu-exit-contract-pin-comment-dup, fu-allowlist-count-is-prose-not-asserted, fu-test031-self-neutralizes-post-merge, fu-test210-branch-now-dead-code; remediation (validation round 1 BLOCKING-5/6, see `## Amendment`): TEST-445/TEST-447 did not exist anywhere but in this document's own prose — both are now real tests, each with a genuine mutation/broken-input control (see `mutation-445.txt`, `mutation-447.txt`); `test-aai-release.sh:57` `RELEASE_ENGINE_PIN_SHA` was byte-identical to the live engine (this scope never touched `aai-release.sh`) and is now re-pinned to `6adfe840...` (the commit immediately before the pin's original target), a genuinely different blob, plus a new negative control in `test_031_unprotected_path_byte_identical` |
| Spec-AC-13 | Each of the six pins named in the implementation plan SHALL assert the property it describes rather than a count or a byte identity, and a legal one-line change to the thing it bounds SHALL leave the suite green. | done | docs/ai/tdd/spec-test-framework-sweep/green-423.txt; green-424.txt; green-425.txt; validation-round6.txt | — | fu-ceremony-test016-blanket-byte-pin, fu-usage-pin-misses-appended-flag, fu-closure-allowlist-pin-blocks-draining, fu-test029-count-not-subset, fu-test013-uncovered-on-legal-max-raise, fu-test031-guard-dies-at-rename |
| Spec-AC-14 | WHEN one of the nine guards named in the implementation plan cannot reach the branch it was written for, it SHALL report UNCOVERED and exit non-zero rather than call `log_pass`, and a per-file ratchet over `tests/skills` SHALL record the remaining degenerate-pass sites at their measured count of 26. | done | docs/ai/tdd/spec-test-framework-sweep/green-426.txt; validation-round6.txt | — | DEBT-0004 Target State item b; a platform-legitimate skip is not a vacuous guard, so the rest is ratcheted rather than banned; corrected at remediation (validation round 1 BLOCKING-7, see `## Amendment`) — the frozen text's "35" was measured with `grep -i`, not the plain (case-sensitive) grep this ratchet actually uses; the plain-grep count is 31 pre-scope (origin/main) and 26 post-scope (five of the nine converted guards also carried this shape); follow-ups TEST-031's delivery-diff guard is now a documented permanent-UNCOVERED exception (BLOCKING-9): its primary path can never again be exercised (its own scope's spec is merged history), so it now reports UNCOVERED honestly in its own verdict message rather than falling through to an unqualified `log_pass`, without hard-failing the whole suite forever (this suite's `log_fail` is unconditionally fatal under `set -euo pipefail`, so a literal exit-non-zero here would void every arm after it, including TEST-443) — its ongoing protection is the TEST-448 negative control, which re-runs every time |
| Spec-AC-15 | The hygiene pack SHALL carry one rule per LEARNED guard marker in this bucket, each rule SHALL flag a planted instance of its shape in a fixture tree and SHALL report zero findings over the live `tests/skills` tree, and each LEARNED marker SHALL name the shipped guard. | done | docs/ai/tdd/spec-test-framework-sweep/green-427.txt; green-428.txt; validation-round6.txt | — | fu-learned-bash32-local-crossref, fu-empty-path-cd-stays-in-shipping-repo, fu-learned-immutable-pin-lint, fu-learned-deny-by-default-mocks, fu-learned-positive-control-for-absence, fu-learned-external-runner-routing, fu-learned-vitest-leak-is-a-guard |
| Spec-AC-16 | `.aai/SKILL_TDD.prompt.md` and `.aai/VALIDATION.prompt.md` SHALL both name `select-suites.mjs` as the selector for an intermediate round, `tests/skills/suite-map.yaml` SHALL select `aai-state` for a change to `.aai/ROLE_COMMON.md`, and the prompt-diet ledger and its TEST-012 pin SHALL be trued up by the measured byte delta. | done | docs/ai/tdd/spec-test-framework-sweep/green-429.txt; green-430.txt; validation-round6.txt | — | fu-tdd-skips-full-sweep, fu-validation-ignores-suite-selector, fu-suitemap-state-missing-role-common |
| Spec-AC-17 | Removing one isolation base SHALL leave every other registered base intact and destroyable by the trap, a failed `iso_create` SHALL destroy what it registered, and an INT delivered to the wrapper SHALL reap the wrapped process group before any checkout is removed. | done | docs/ai/tdd/spec-test-framework-sweep/green-431.txt; green-432.txt; validation-round6.txt | — | fu-iso-bases-reset-discards-entries, fu-iso-wrapper-traps-dont-reap-group |
| Spec-AC-18 | WHEN a seed path is missing from the checkout, WHEN the seed enumeration cannot read part of the tree, or WHEN the marker append fails, the run SHALL report the suite as partly seeded and SHALL NOT report it seeded. | done | docs/ai/tdd/spec-test-framework-sweep/green-433.txt; validation-round6.txt | — | fu-seed-loss-turns-an-arm-into-a-skip, fu-seed-step2-enumeration-silent, fu-marker-append-failure-discarded |
| Spec-AC-19 | The suite-isolation suite SHALL state `AAI_TEST_ISOLATION` rather than inherit it, the wrapper SHALL print one isolation line for a suite run whose command shape hides the suite path, and the claim that the four formerly exempt suites do not write the shipping repository SHALL be replaced by what was measured. | done | docs/ai/tdd/spec-test-framework-sweep/green-434.txt; green-435.txt; validation-round6.txt | — | fu-isolation-suite-not-hermetic, fu-wrapper-hidden-suite-run-unreported, fu-drained-suites-still-write-unisolated; remediation (validation round 1 BLOCKING-21, see `## Amendment`): the first fix covered only TEST-001/003/005's own bodies while every OTHER `test-framework.sh` invocation in this suite (TEST-002, TEST-004, TEST-201..211 and more) still inherited the operator's ambient setting; every such call site now states `AAI_TEST_ISOLATION=1` explicitly (control `env -u AAI_TEST_ISOLATION` and ambient `AAI_TEST_ISOLATION=0` both exit 0 over the whole suite), and TEST-434 now actually re-runs TEST-001, TEST-003 AND TEST-005 under the override (not just TEST-001 with a prose claim about the other two) |
| Spec-AC-20 | A tripwire ALLOWED verdict SHALL account for paths already dirty before the suite ran, a degraded tripwire SHALL say so on the suite's own progress line and in its telemetry record, and `tests/skills/test-aai-repo-tripwire.sh` SHALL leave no temporary directory behind after a full run. | done | docs/ai/tdd/spec-test-framework-sweep/green-436.txt; green-437.txt; validation-round6.txt | — | fu-tripwire-allowed-ignores-pre-dirty, fu-tripwire-degrade-not-on-suite-line, fu-tripwire-fixture-dirs-leak |
| Spec-AC-21 | The four code comments and spec sections naming a withdrawn claim SHALL state what the branch shipped, and a grep for each withdrawn phrase over `tests/skills`, `.aai/` and `docs/specs` SHALL return 0. | done | docs/ai/tdd/spec-test-framework-sweep/green-438.txt; validation-round6.txt | — | fu-tripwire-suite-comment-transitional, fu-isolation-suite-presumes-deletion, fu-framework-comment-mislabels-d5, fu-drain-spec-says-d7-filed-not-fixed |
| Spec-AC-22 | Every one of the 24 `.aai/scripts/*.mjs` files that guards `main()` with `process.argv[1]` SHALL resolve both sides of that comparison through realpath, a grep for the unresolved shape SHALL return 0, and three named CLIs invoked through a symlinked checkout SHALL produce stdout and an exit code identical to the resolved path. | done | docs/ai/tdd/spec-test-framework-sweep/green-439.txt; validation-round6.txt (22 of 23 guards; allocate-doc-number.mjs excluded, protected_paths_l3, fu-realpath-allocate-doc-number-l3) | — | fu-ismain-symlink-realpath; DISCLOSED EXCEPTION (validation round 1 BLOCKING-10/11, see `## Amendment`): `.aai/scripts/allocate-doc-number.mjs` is 1 of the 24 and is DELIBERATELY EXCLUDED, not fixed — it is one of the eight `docs/ai/docs-audit.yaml` `protected_paths_l3` surfaces, so touching it forces `ceremony_level:3` and this ride is ceremony 2 (established fact 9). `tests/skills/test-aai-doctor.sh:1861-1866` excludes it by name with a comment; the defect reproduces live through a symlinked checkout (rc=0, 0 bytes printed — a silent no-op). Tracked by `fu-realpath-allocate-doc-number-l3` (P3), filed at remediation; `fu-ismain-symlink-realpath` stays closed done for the 22 of 23 it actually fixed (NON-BLOCKING, validation round 2: "23 of 24" was off by one — the 24th file, `.aai/scripts/heartbeat.mjs:435`, references `process.argv[1]` only inside a comment explaining it has no main guard on purpose, so the real accounting is 23 actual main guards = 22 resolved + this one excluded, not 24) |
| Spec-AC-23 | WHEN `AAI_REAP_STEP_START_EPOCH` is exported into the test command's environment, `tests/skills/test-aai-run-tests.sh` SHALL pass, in 5 consecutive runs. | done | docs/ai/tdd/spec-test-framework-sweep/green-440.txt; validation-round6.txt | — | fu-reaper-epoch-export-fails-test005 |
| Spec-AC-24 | WHEN the working tree carries a document that `docs/INDEX.md` does not yet list, `tests/skills/test-aai-docs-audit.sh` and `tests/skills/test-aai-delta-stage3.sh` SHALL both pass. | done | docs/ai/tdd/spec-test-framework-sweep/green-441.txt; validation-round6.txt | — | fu-docsaudit-t003-red-on-new-doc |
| Spec-AC-25 | `tests/skills/test-aai-orchestration-dispatch.sh` TEST-056 SHALL resolve routed ids through the shipped routing parser rather than its own copy, and a change to that parser's row shape SHALL be visible to the test. | done | docs/ai/tdd/spec-test-framework-sweep/green-442.txt; validation-round6.txt | — | fu-test056-duplicates-routing-parser |
| Spec-AC-26 | Every one of the 78 bucket ids SHALL be terminal in the ledger, the 48 as `done` with `resolved_by` naming this ride and the 30 as `dropped`, each with the recorded reason present on its `follow_up_status` record, `follow-ups.mjs verify-closures --path <this spec> --strict` SHALL exit 0 over the 48 claims its parser reads from the closed-by-this-scope heading, and the prompt-diet ledger entry, the TEST-012 pin, the `PROFILES.yaml` classification of the new `.aai` file and the `suite-map.yaml` row plus row-count pin for the one new suite SHALL all be present. | done | docs/ai/tdd/spec-test-framework-sweep/green-443.txt; validation-round6.txt | — | the partition itself plus the two companion obligations; the parser reads exactly 48 claims from that heading today, measured; CORRECTED at remediation (validation round 1 BLOCKING-12/13, see `## Amendment`) — the original text said the reason lives ON `resolved_by`, but `follow-ups.mjs`'s own established, repo-wide ledger grammar (every dropped record, not only this ride's) puts the RIDE REF in `resolved_by` and the reason in `source` (`close --resolved-by <ref> --source "<reason>" --status dropped`); rewriting 36 append-only records to match the ORIGINAL wording would be the more expensive, less truthful fix, so the wording here now matches the ledger's actual, established grammar instead. The row-count pin did not exist (`test-aai-hygiene-pack.sh` `test_090_suite_map_pin` was an existence check, not a count) and is now written: a top-level-row count over `suite-map.yaml`, pinned at 93. CORRECTED AGAIN at remediation (validation round 5 BLOCKING-2, see `## Amendment`): the bucket was 84 (48 closed + 36 rejected) at freeze; SIX owner sign-off trackers for OTHER specs were mistakenly swept into the rejected 36 (five named by the validator, a sixth found while re-verifying the fix under the corrected TEST-009) and, after a failed re-track attempt for the first five (2026-09-14 orchestrator ledger repair, itself corrected here), are REMOVED from this scope's bucket entirely (reopened under their original ids instead) rather than closed under any status — the bucket this scope actually owns is 78 (48 + 30), and TEST-443 plus its frozen-id-list pin move with it |
| Spec-AC-27 | `docs/issues/CHANGE-0166-residuals-of-the-per-suite-clone-ride.md` SHALL carry the measured before and after wall-clock, a terminal frontmatter status and its delivering PRs, and `docs-audit.mjs --check --strict` over it SHALL be CLEAN. | done | docs/ai/tdd/spec-test-framework-sweep/green-444.txt; validation-round6.txt | — | the paired maintenance half; its work shipped in PR #307 and its doc is still a draft |
| Spec-AC-28 | WHEN a suite that nests another suite fails, the nested output SHALL be written to a file that the failure message names together with its line count, so the framework's own whole-log failure-line extraction shows more than the first line of it. | done | docs/ai/tdd/spec-test-framework-sweep/green-404.txt; green-449.txt; validation-round6.txt | — | fu-nested-profiles-hides-missing-list; the `tail -3` half was already delivered by commit 02455b73 and the residual is the single-argument rendering |

## Implementation plan

**Components changed.** `tests/skills/test-framework.sh` (scheduler, attribution window, seeding verdicts, isolation bookkeeping, tripwire reporting, progress signal); `.aai/scripts/aai-run-tests.sh` (traps, watchdog default, hidden-suite-run reporting, comment); `.aai/scripts/branch-guard.mjs` (`--pin`, `--verify-pin`); a new `.aai/scripts/lib/session-lock.mjs` (CAS acquire, pid liveness, reclaim) consumed by the ceremony scripts; `.aai/scripts/check-committed-scope.mjs`,
`.aai/scripts/close-before-push-guard.mjs` and `.aai/scripts/close-work-item.mjs` (an `--expect-branch` re-check only — no other behaviour of `close-work-item.mjs` is touched, its internals belong to sweep 4); `.aai/scripts/golden-flow.mjs` (locked append); `tests/skills/lib/assert-payload.sh` (three new helpers); `tests/skills/lib/pipe-grep-q-baseline.tsv`; 31 suite files under `tests/skills`; exactly ONE new suite file, `tests/skills/test-aai-session-lock.sh` for the new script (the helper tests go into the hygiene pack and each guard's negative control goes into that guard's own suite, so no other suite is created), which takes `tests/skills/suite-map.yaml` from 92 rows to 93 and obliges the hygiene pack's row-count pin; `tests/skills/suite-map.yaml`; `.aai/SKILL_TDD.prompt.md`, `.aai/VALIDATION.prompt.md`, `.aai/SKILL_PR.prompt.md`; `docs/knowledge/LEARNED.md`; `tests/skills/lib/prompt-diet-ledger.sh` and `tests/skills/test-aai-prompt-diet.sh`.

**The nine guards of Spec-AC-12**, each with the mutation its control must fail on: release TEST-024 (delete one `## [unreleased]` heading present in the merge-base); release TEST-025 (already controlled by TEST-026 — only its `SKIP` to `log_pass` mapping changes); release TEST-031 (pin the comparison engine to a fixed blob, then mutate one stdout line of the working engine); git-ref-guard TEST-312 (delete one `JUSTIFIED_ADDITIONS` entry the base carries); deslop TEST-028 (one byte inside the released CHANGELOG section); spec-amend TEST-008, TEST-009 and TEST-003 (build the fixture that takes the other path, then mutate it); follow-ups TEST-031 (a fixture diff touching two frozen specs); spec-lint TEST-011 exit-contract pins (mutate ONLY the runtime string at `.aai/scripts/spec-freeze.mjs:104`, leaving the header comment at `:56` — measured today: all four phrases occur exactly twice, so the pin passes on a broken CLI).

**The six pins of Spec-AC-13.** `test-aai-ceremony-levels.sh:1087` — a bare `git diff --exit-code` with no ref compares worktree against index, so it reddens only while an edit is unstaged and goes silent the moment it is committed (verified in a scratch repository: staged or committed gives rc 0, unstaged gives rc 1); it is deleted in favour of the functional cases the file's own comment at `:1080-1086` already names. `test-aai-spec-lint.sh:1630-1635` — three `grep -qF` usage pins become whole-line matches so an appended flag trips them. `test-aai-follow-ups.sh:1817-1822` — `-eq 3` plus exact contents becomes `-le 3` plus a subset assertion, which closes `fu-closure-allowlist-pin-blocks-draining` and `fu-test029-count-not-subset` in one edit. `test-aai-repo-tripwire.sh:838-841` — TEST-013's premise becomes "the shipped table does not contain the two fixture suite names this arm plants", which is all its bite proof needs, so a reviewed raise of `TRIPWIRE_RATCHET_MAX_ENTRIES` has a legal repair. `test-aai-release.sh:1153-1182` — the base engine is pinned to a fixed blob and the no-base branch fails instead of passing. `test-aai-follow-ups.sh:1906-1923` — an unfired delivery-diff guard reports UNCOVERED instead of printing a claim it did not check.

**The drain of Spec-AC-11.** 202 occurrences over 31 files (per-file TSV baseline, currently in sync). `tests/skills/lib/assert-payload.sh` gains `assert_payload_contains_i` (case-insensitive substring, unblocking 90 sites), `assert_payload_has_line` (exact whole-line via a `case` over the payload bracketed with newlines, unblocking 56), and `assert_payload_line_matches` (per-line ERE, for the 41 metacharacter sites). The last is the one with a semantic trap that must be stated in its header: bash's `[[ =~ ]]` does not set `REG_NEWLINE`, so `^` and `$` bind to the whole string and a naive rewrite of an anchored site silently changes what it asserts — the helper iterates lines. Seven negated control-flow sites are restructured, not substituted. Ten of the 31 files do not yet source the library.

**The scheduler of Spec-AC-06 and Spec-AC-07.** `main()`'s wave accumulation (`test-framework.sh:1894-1912`) and `run_wave()`'s wait-for-all (`:1570-1576`) are replaced by a refilling queue in the current `find | sort` discovery order. No duration-ordering hint file is shipped: modelled over the real per-suite durations of run `test-20260912-173455`, refilling alone takes width 8 from 1559 s to 521 s — 89.8 percent of the achievable gain — while longest-processing-time ordering adds a further 118 s and would require committing a duration table that goes stale and is absent from a fresh CI clone. Bash 3.2.57 is a supported host and has no `wait -n`, so the queue polls its child pids. The attribution window becomes a rolling one: a snapshot pair is taken at each completion under the append lock, and a dirty observation names as candidates only the suites that overlapped the interval since the last clean observation — bounded by Spec-AC-07 at 2 times the width, never the whole corpus. `WAVES_REATTRIBUTED` keeps its ledger key and gains a sibling counting suites; `TRIPWIRE_WAVE_UNATTRIBUTED` keeps gating the exit code. `tests/skills/test-aai-sweep-parallel.sh` TEST-003 asserts the literal summary string `Concurrency: width 3; 1 wave(s) re-run serially` and is re-expressed; TEST-007 and TEST-010 are re-pointed at the queue's child; the other seven arms must stay green unedited.

**Edge cases.** Isolation off still forces serial, unchanged. A width of 1 still takes the serial path, which stays the pre-existing execution model. A suite that finishes while the snapshot lock is held waits for the lock rather than skipping its observation. The pin file and the session lock live under `$(git rev-parse --git-dir)/aai/`, which is per-worktree and structurally uncommittable, so neither owes a `.gitignore`, `RUNTIME_IGNORE.list` or `DOCS_AI_CANON.list` entry. No heartbeat file is read by any guard in this scope.

## Test Plan

Test ids are allocated from the TEST-4xx band, which is unused anywhere in `tests/` or `docs/` today (measured). A sweep touches twenty suites whose own sequences end at TEST-008, TEST-010, TEST-014, TEST-016, TEST-017, TEST-019, TEST-022, TEST-024, TEST-031, TEST-036, TEST-060, TEST-063, TEST-082, TEST-104 and TEST-316, so a per-suite continuation would collide; one reserved band above every existing id continues all of them without ambiguity, which is the same convention `test-aai-suite-isolation.sh` and `test-aai-git-ref-guard.sh` already use at TEST-3xx.

| Test ID  | Spec-AC    | Type | File path (expected) | Description | Status |
|----------|------------|------|----------------------|-------------|--------|
| TEST-401 | Spec-AC-01 | integration | tests/skills/test-aai-layer-profiles.sh | With one file removed from the built fixture after the copies, the build's own completeness comparison exits non-zero naming that path before any assertion runs; with a `cp -R` made to fail, the build names the source and destination. | green |
| TEST-402 | Spec-AC-02 | integration | tests/skills/test-aai-layer-profiles.sh | A core sync patched to skip one core-listed file makes the suite fail on the `missing in source` WARN line it now captures, rather than on the downstream missing-file set. | green |
| TEST-403 | Spec-AC-02 | integration | tests/skills/test-aai-layer-profiles.sh | An assertion handed a payload that is non-empty as a string but renders as zero visible lines fails with a byte-for-byte dump of that payload, which is the shape CI produced and no incomplete copy explains. | green |
| TEST-404 | Spec-AC-28 | integration | tests/skills/test-aai-feedback-upsert.sh | The nesting wrapper, given a nested suite that fails with a multi-line payload, writes the nested output to a file, names the file and its line count, and the framework's whole-log failure-line extraction shows more than the first line. | green |
| TEST-449 | Spec-AC-28 | integration | tests/skills/test-aai-friction-wiring.sh | The same property for the second nesting wrapper, proven against the same nested-failure fixture. | green |
| TEST-405 | Spec-AC-03 | integration | tests/skills/test-aai-branch-guard.sh | `--pin` on a fixture branch, then a plain `git checkout` of another branch in the same fixture, makes `--verify-pin` exit non-zero naming the expected and the actual branch and citing a concurrent session. | green |
| TEST-406 | Spec-AC-03 | integration | tests/skills/test-aai-branch-guard.sh | A detached HEAD and a branch renamed under the pin each produce a distinct message, neither of them the concurrent-session text, with distinct exit codes. | green |
| TEST-407 | Spec-AC-03 | integration | tests/skills/test-aai-branch-guard.sh | With a pin in place and HEAD moved, `check-committed-scope.mjs`, `close-before-push-guard.mjs` and `close-work-item.mjs` each refuse before writing, and `git status` plus the branch reflog show nothing was staged, committed or pushed. | green |
| TEST-408 | Spec-AC-04 | integration | tests/skills/test-aai-branch-guard.sh | With no pin file, each of the three scripts produces stdout and an exit code identical to the pinned pre-change blob on the same fixture, and `branch-guard.mjs` with no new flag is byte-identical in behaviour to its pre-change self. | green |
| TEST-409 | Spec-AC-05 | integration | tests/skills/test-aai-session-lock.sh | A live holder makes a second acquire exit 3 naming the holder pid and worktree; a holder whose pid is gone is reclaimed and the second acquire exits 0; two concurrent acquires produce exactly one winner. | green |
| TEST-410 | Spec-AC-05 | integration | tests/skills/test-aai-session-lock.sh | The lock file resolves under `$(git rev-parse --git-dir)/aai/` for both a main checkout and a linked worktree, and the two do not share a lock. | green |
| TEST-411 | Spec-AC-06 | integration | tests/skills/test-aai-sweep-parallel.sh | Four suites of unequal duration at width 2 finish in less wall-clock than the sum of the per-wave maxima the barrier scheduler would have produced, proving a freed slot was refilled. | green |
| TEST-412 | Spec-AC-06 | integration | tests/skills/test-aai-sweep-parallel.sh | The per-suite verdict set, the summary totals and the exit code are identical at width 1 and at width 4 over a PASS, a FAIL, a SKIP and a crashing fixture suite. | green |
| TEST-413 | Spec-AC-07 | integration | tests/skills/test-aai-sweep-parallel.sh | A fixture suite that writes a tracked path during the concurrent phase is named as the writer, no sibling is blamed, and the serially re-run set is at most twice the width. | green |
| TEST-414 | Spec-AC-07 | integration | tests/skills/test-aai-sweep-parallel.sh | A SECOND append to an already-dirty tracked path is still detected, proving the content-hash widening survives the window change. | green |
| TEST-415 | Spec-AC-08 | integration | tests/skills/test-aai-run-tests.sh | The wrapper with no `AAI_TEST_TIMEOUT` set runs a command that outlives the old 300 s default and completes rather than exiting 124; a command that does exceed the limit produces one line naming the limit and the override. | green |
| TEST-416 | Spec-AC-09 | integration | tests/skills/test-aai-sweep-parallel.sh | During a run of four fixture suites the heartbeat slot exists, its finished count rises and its total equals the discovered suite count; after the run its timestamp stops advancing; and no gate reads it, which the existing heartbeat deny-by-default arm continues to prove. | green |
| TEST-417 | Spec-AC-10 | integration | tests/skills/test-aai-golden-flow.sh | Twelve concurrent `golden-flow.mjs` appends produce twelve whole parseable records with the pre-existing bytes an exact prefix, and a lock that cannot be taken is reported rather than written around. | green |
| TEST-418 | Spec-AC-11 | integration | tests/skills/test-aai-hygiene-pack.sh | The shipped scan over `tests/skills` returns 0 and every baseline row is 0. | green |
| TEST-419 | Spec-AC-11 | integration | tests/skills/test-aai-hygiene-pack.sh | A planted occurrence in a fixture tree still fails the ratchet, and a baseline typed by hand rather than recorded is still rejected. | green |
| TEST-420 | Spec-AC-11 | unit | tests/skills/test-aai-hygiene-pack.sh | The three new helpers: case-insensitive substring, exact whole-line, and per-line ERE where a pattern anchored with `^` and `$` matches a middle line and does not match across the newline. | green |
| TEST-421 | Spec-AC-12 | integration | tests/skills/test-aai-release.sh | The three release guards each fail on their named mutation in a scratch copy and pass on the unmutated copy: a deleted `## [unreleased]` heading, the already-controlled released-region verdict, and a mutated stdout line of the engine pinned to a fixed blob. | green |
| TEST-445 | Spec-AC-12 | integration | tests/skills/test-aai-spec-amend.sh | The three spec-amend arms are driven through a fixture that takes the branch they were written for, and each fails on its named mutation instead of reporting not applicable. | green |
| TEST-446 | Spec-AC-12 | integration | tests/skills/test-aai-git-ref-guard.sh | Deleting one `JUSTIFIED_ADDITIONS` entry the base carries, in a scratch copy, reddens the corpus-credit drift arm, and an unreadable base fails closed. | green |
| TEST-447 | Spec-AC-12 | integration | tests/skills/test-aai-deslop.sh | A one-byte edit inside the released CHANGELOG section of a scratch copy reddens the released-section comparison. | green |
| TEST-448 | Spec-AC-12 | integration | tests/skills/test-aai-follow-ups.sh | A fixture diff touching two frozen spec documents makes the delivery-diff guard fire and fail, and an unfired guard reports UNCOVERED. | green |
| TEST-422 | Spec-AC-12 | integration | tests/skills/test-aai-spec-lint.sh | Mutating only the runtime exit-contract string in a scratch copy of `spec-freeze.mjs`, leaving the header comment intact, reddens the exit-contract pin. | green |
| TEST-423 | Spec-AC-13 | integration | tests/skills/test-aai-repo-tripwire.sh | A one-entry offender table with a matching maximum leaves TEST-013 and TEST-014 both green, and a table containing either fixture suite name reddens TEST-013. | green |
| TEST-424 | Spec-AC-13 | integration | tests/skills/test-aai-follow-ups.sh | Closing one allowlist entry leaves the suite green, while adding an entry outside the delivery-time set reddens it. | green |
| TEST-425 | Spec-AC-13 | integration | tests/skills/test-aai-spec-lint.sh | A flag appended to the pinned usage line of a scratch `spec-freeze.mjs` reddens the usage pin. | green |
| TEST-426 | Spec-AC-14 | integration | tests/skills/test-aai-hygiene-pack.sh | Seven of the nine guards report UNCOVERED and exit non-zero on their own degenerate branch; the remaining two are covered as declared — follow-ups TEST-031 is the disclosed permanent UNCOVERED-exit-0 carve-out and spec-lint TEST-011 has no such branch, structurally checked so it cannot grow one silently. The degenerate-pass ratchet over `tests/skills` matches its recorded per-file baseline, and a planted extra site in a fixture tree fails the ratchet. | green |
| TEST-427 | Spec-AC-15 | integration | tests/skills/test-aai-hygiene-pack.sh | Each new lint flags a planted instance of its shape in a fixture tree: a cross-referenced `local`, a `cd` to an underived variable, an immutable-claiming pin resolved through a moving ref, a stub exiting 0 on unknown argv, an absence assertion with no positive control, and a prompt launching a runner outside the wrapper. | green |
| TEST-428 | Spec-AC-15 | integration | tests/skills/test-aai-hygiene-pack.sh | Every new lint reports zero findings over the live `tests/skills` and `.aai` trees, and every `[guard ->` marker in LEARNED.md resolves to a shipped guard or an open follow-up. | green |
| TEST-429 | Spec-AC-16 | integration | tests/skills/test-aai-prompt-diet.sh | Both prompts name `select-suites.mjs`, the ledger carries this ride's entry, and the TEST-012 growth pin equals the recorded sum. | green |
| TEST-430 | Spec-AC-16 | integration | tests/skills/test-aai-suite-select.sh | A change list containing only `.aai/ROLE_COMMON.md` selects `aai-state`. | green |
| TEST-431 | Spec-AC-17 | integration | tests/skills/test-aai-suite-isolation.sh | Two registered bases survive the degrade branch and the post-run destroy individually, and an `iso_create` aborted between registration and seeding leaves no registered base behind. | green |
| TEST-432 | Spec-AC-17 | integration | tests/skills/test-aai-run-tests.sh | An INT delivered to the wrapper while a long suite runs reaps the wrapped process group before any checkout is removed, and the wrapper's exit code still distinguishes the signal. | green |
| TEST-433 | Spec-AC-18 | integration | tests/skills/test-aai-suite-isolation.sh | A seed path present in the working tree and absent from the checkout, an unreadable directory during enumeration, and a failed marker append each make the run report partly seeded rather than seeded. | green |
| TEST-434 | Spec-AC-19 | integration | tests/skills/test-aai-suite-isolation.sh | The suite states `AAI_TEST_ISOLATION` rather than inheriting it, so an operator exporting 0 does not redden it. | green |
| TEST-435 | Spec-AC-19 | integration | tests/skills/test-aai-run-tests.sh | A suite run whose command shape hides the suite path produces one isolation line naming what it could not classify, instead of silence. | green |
| TEST-436 | Spec-AC-20 | integration | tests/skills/test-aai-repo-tripwire.sh | An allowlisted suite writing a non-ratchet path that was already dirty does not read ALLOWED, and a degraded tripwire says so on the suite's own line and in its telemetry record. | green |
| TEST-437 | Spec-AC-20 | integration | tests/skills/test-aai-repo-tripwire.sh | A full run of the tripwire suite leaves no temporary directory under TMPDIR. | green |
| TEST-438 | Spec-AC-21 | integration | tests/skills/test-aai-hygiene-pack.sh | A grep for each of the four withdrawn phrases over `tests/skills`, `.aai/` and `docs/specs` returns 0, and a planted phrase in a fixture tree is reported. | green |
| TEST-439 | Spec-AC-22 | integration | tests/skills/test-aai-doctor.sh | A grep for the unresolved `process.argv[1]` main-guard shape over `.aai/scripts/*.mjs` returns 0, and three named CLIs invoked through a symlinked checkout produce stdout and an exit code identical to the resolved path. | green |
| TEST-440 | Spec-AC-23 | integration | tests/skills/test-aai-run-tests.sh | With `AAI_REAP_STEP_START_EPOCH` exported into the test command's environment, the reaper arm passes. | green |
| TEST-441 | Spec-AC-24 | integration | tests/skills/test-aai-docs-audit.sh | With a document present in the working tree and absent from the committed `docs/INDEX.md`, the arm passes, and it still fails when the generator's own output is inconsistent. | green |
| TEST-442 | Spec-AC-25 | integration | tests/skills/test-aai-orchestration-dispatch.sh | The PRICING sweep resolves routed ids through the shipped parser, and a row-shape change made in a fixture routing file is seen identically by the test and the engine. | green |
| TEST-443 | Spec-AC-26 | integration | tests/skills/test-aai-follow-ups.sh | `verify-closures --path <this spec> --strict` exits 0, every bucket id is terminal with `resolved_by` naming this ride, and the union of the closed and rejected tables is exactly the 78 frozen ids (84 at freeze, corrected at remediation — validation round 5 BLOCKING-2, see `## Amendment`). | green |
| TEST-444 | Spec-AC-27 | integration | tests/skills/test-aai-docs-audit.sh | `docs-audit --check --strict` over CHANGE-0166 is CLEAN and its frontmatter status is terminal with a PR link. | green |

Every Spec-AC has at least one TEST row and every TEST row names exactly one Spec-AC.

## Mutation checks

Every test above is paired with the source mutation that MUST redden it. Mutations are applied to a scratch COPY of the tree, never to a tracked file (HAZ-RESTORE, HAZ-SCRATCH), and each recorded under `docs/ai/tdd/spec-test-framework-sweep/` as one file holding the failing output.

RED-first — these assert behaviour that does not exist on the pre-change tree, so each is observed FAILING there before any engine edit: TEST-401 through TEST-407, TEST-409 through TEST-411, TEST-413 through TEST-417, TEST-419 through TEST-421, TEST-423 through TEST-427, TEST-429 through TEST-440, TEST-442, TEST-443, TEST-444, TEST-448 and TEST-449. Files `red-401.txt` and onward. (Corrected at remediation, validation round 1 BLOCKING-17/18, see `## Amendment`: TEST-412, TEST-441, TEST-445 and TEST-447 moved out of this range into the CANNOT-go-RED list below, where their actual evidence already lived, and TEST-422/TEST-446 join them there too — their pre-fix state is a wrongly-green PASS rather than any kind of FAIL, so neither ever had a genuine red file; TEST-421 DOES have a genuine `red-421.txt` after remediation and stays in this range. NON-BLOCKING, validation round 2: `tdd-evidence-check.mjs`'s grammar has exactly two live values, `product_red` and `infra_fail` — there is no third class for "the test's own NEGATIVE CONTROL block failed" versus "the test's own PRIMARY assertion failed", so `red-421.txt`, `red-424.txt` and `red-448.txt` are correctly stamped `RED_CLASS: product_red` (each reaches and reports a real FAIL line from the test's own code, never a shell "command not found") but are the negative-control shape, not the primary-assertion shape; their own prose already says so honestly. `red-402.txt` and `red-403.txt` are the primary-assertion shape.)

CANNOT go RED by construction, so a mutation control stands in for the RED:

- `mutation-408.txt` — TEST-408 compares the pre-change scripts with the current ones on the no-pin path. On the pre-change tree both sides are the pre-change script, so it passes with this scope deleted. Its control is a deliberate mutation: make the pin check run before the pin-file existence test, so a ceremony with no pin pays a git call and changes its output. TEST-408 must then fail. Without that recorded failure TEST-408 is evidence of nothing.
- `mutation-418.txt` — TEST-418 asserts a count of 0, which a half-drained tree also fails, so the RED is genuine; but the assertion could pass vacuously if the scan were pointed at an empty directory. Its control plants one occurrence in the scanned tree and requires the count to become 1, proving the scanner still scans.
- `mutation-428.txt` — TEST-428 asserts an absence over the live tree, the exact shape Spec-AC-15's own positive-control lint exists to refuse. Its control plants one instance of each lint's shape and requires each rule to report exactly one finding, proving the lints ran.
- `mutation-412.txt` (recorded in `mutation-sweep.txt`) — added at remediation (BLOCKING-18). TEST-412 asserts an invariant (verdict set identical at width 1 and width 4) that also held on the pre-change, fixed-wave-barrier tree — reproduced directly against `origin/main`'s `test-framework.sh`. Its control is the spec-prescribed mutation "mask the queue child's real exit code on the clean-report path", which reddens it on the current tree.
- `mutation-441.txt` — TEST-441 Part A asserts a tolerance that already held on the unmodified tree (the CI-only layer-profiles failure this follow-up described no longer reproduces). Its control restores a committed-INDEX-diff-style hard check in a scratch copy of `docs-audit-core.mjs`, which reddens Part A deterministically.
- `mutation-445.txt` — added at remediation (BLOCKING-5). `tests/skills/test-aai-spec-amend.sh` and `.aai/scripts/spec-amend.mjs` are BYTE-UNTOUCHED by this branch, so TEST-445's three arms (the format trap, append-only, classification-strictness) all test PRE-EXISTING engine behaviour. Each arm's own control mutates a scratch copy of the engine (arms A/B) or plants a deliberately unclassified fixture record (arm C) and observes the SAME property genuinely fail.
- `mutation-447.txt` — added at remediation (BLOCKING-5). `tests/skills/test-aai-deslop.sh`'s released-CHANGELOG comparison algorithm predates this branch. TEST-447 reproduces the same section-extraction-and-compare logic against two scratch fixture files and mutates one byte inside the released section, reddening the comparison.
- `mutation-422.txt` — TEST-422/fu-exit-contract-pin-comment-dup's pre-fix defect IS a wrongly-green PASS (a whole-file grep also matches the untouched header-comment copy of the exit-contract phrase), not any kind of FAIL — there is no RED state to capture. Recorded as a BEFORE/AFTER mutation pair instead: BEFORE the fix the mutation is silently accepted (PASS), AFTER the fix the SAME mutation is caught (FAIL).
- `mutation-446.txt` — TEST-446/TEST-312's pre-fix defect is the same shape: an unreadable base ledger silently SKIPPED the corpus-credit drift check and the arm still PASSED. Recorded as the same BEFORE/AFTER pair.

Additional mutations that must each redden a NAMED test, run in the same pass and recorded in `mutation-sweep.txt`:

- Deleting `.aai/PLANNING.prompt.md` from the built fixture after the copies must redden TEST-401 naming that path; this exact mutation was run during planning and is known-inducible.
- Patching `aai-sync.sh` so one core-listed file takes the `missing in source` branch must redden TEST-402 on the WARN line, not on the downstream missing set.
- Handing the assertion a payload of one whitespace character must redden TEST-403 with a byte dump rather than an empty list.
- Rendering the nested failure into a single `log_fail` argument again must redden TEST-404 and TEST-449.
- Comparing only the branch name and not the HEAD sha must redden TEST-405.
- Collapsing the detached-HEAD and renamed-branch messages into the concurrent-session text must redden TEST-406.
- Removing the re-check from any ONE of the three ceremony scripts must redden TEST-407, which is why that test exercises all three.
- Skipping the pid liveness probe so a dead holder's lock is honoured must redden TEST-409.
- Deriving the lock path from the worktree root instead of the git dir must redden TEST-410.
- Reinstating the wait-for-all barrier must redden TEST-411 and must NOT redden TEST-412, which is how the two are told apart.
- Widening the attribution candidate set to the whole corpus must redden TEST-413.
- Dropping the content-hash widening from the re-run must redden TEST-414.
- Restoring the 300 s wrapper default must redden TEST-415.
- Writing the heartbeat slot only once, at the end of the run, must redden TEST-416.
- Bypassing the append lock in `golden-flow.mjs` must redden TEST-417.
- Making `assert_payload_line_matches` use a single `[[ =~ ]]` over the whole payload must redden TEST-420's middle-line arm.
- Reverting any one of the nine guards to its pre-change form must redden the control that covers it: TEST-421 for the three release guards, TEST-445 for the three spec-amend arms, TEST-446 for the corpus-credit drift arm, TEST-447 for the released-section comparison, TEST-448 for the delivery-diff guard, TEST-422 for the exit-contract pin.
- Restoring the whole-file grep in the exit-contract pin must redden TEST-422.
- Restoring TEST-013's zero-count premise must redden TEST-423.
- Restoring `-eq 3` in the closure allowlist must redden TEST-424.
- Restoring the substring usage pin must redden TEST-425.
- Reintroducing one `log_pass` on any of the nine guards' degenerate branches, or adding a twenty-seventh degenerate-pass site (the shipped baseline is 26, not the pre-remediation 35), must redden TEST-426.
- Removing any one lint must redden TEST-427, one arm each.
- Removing `select-suites.mjs` from either prompt must redden TEST-429.
- Removing `.aai/ROLE_COMMON.md` from the `aai-state` globs must redden TEST-430.
- Restoring the wholesale `ISOLATION_BASES=()` reset must redden TEST-431.
- Removing the group reap from the wrapper's INT trap must redden TEST-432.
- Counting an unreadable enumeration as seeded must redden TEST-433.
- Inheriting `AAI_TEST_ISOLATION` again must redden TEST-434.
- Restoring the silent not-applicable path in the wrapper must redden TEST-435.
- Comparing only paths that MOVED in the ratchet path-subset test must redden TEST-436.
- Calling `new_fixture` in a command substitution again must redden TEST-437.
- Restoring any one withdrawn phrase must redden TEST-438.
- Removing the realpath resolution from any one of the 24 main guards must redden TEST-439.
- Restoring the epoch-export sensitivity must redden TEST-440.
- Restoring the committed-INDEX diff must redden TEST-441.
- Restoring TEST-056's private parser copy must redden TEST-442.
- Dropping one id from either registry table must redden TEST-443.

Any mutation in that list that leaves every test green is a finding to fix in the test, not a note to file.

## Seams

Each crossing is a place this scope shares state with something it does not own. Each names the test that produces on one side and asserts on the other.

1. **The scheduler to the tripwire.** The attribution window was the wave; the wave is being removed. Crossed by TEST-413 and TEST-414, which write a real path from a real fixture suite during a real concurrent phase and read the run's own attribution, not a mocked verdict. The seven unedited arms of `tests/skills/test-aai-sweep-parallel.sh` are the regression half.
2. **The scheduler to the run ledger.** `waves_reattributed` is a shipped key in `docs/ai/tests/test-runs.jsonl`, which is tracked, append-only, and read by the factory report. Changing its meaning is a schema change; the key keeps its meaning and a sibling is added. Crossed by TEST-413 plus the append-only prefix assertion already in the parallel suite.
3. **The wrapper's timeout default to every caller of the canonical command.** Raising it changes what a hung suite costs before it is killed. Crossed by TEST-415, which exercises both the completing and the exceeding case through the real wrapper.
4. **The HEAD pin to the ceremony's git writes, none of which a script performs.** The pin can only be enforced where a script still stands between the agent and the write. Crossed by TEST-407 against all three scripts at once, and by TEST-408 as the no-regression control.
5. **The framework and the session lock to `/aai-live`'s heartbeat files.** Two crossings in opposite directions. The sweep now WRITES a heartbeat slot so the page can see it (Spec-AC-09), which is the affordance heartbeats exist for; the session lock deliberately does NOT read one, because a gate reading a heartbeat is forbidden by a tested rule of this repository. Crossed by TEST-416 on the write side, by TEST-409 and TEST-410 reading only the lock on the other, and by the existing heartbeat deny-by-default arm staying green throughout.
6. **The new assert helpers to 31 suites and 202 call sites.** A helper whose semantics differ from the idiom it replaces changes what 202 assertions mean. Crossed by TEST-420 on the helper and by the full sweep on the rewritten suites — the rewrite is proven by the suites still passing AND by each suite's own bite proofs, not by the helper's unit test alone.
7. **The prompt edits to the corpus-wide diet gate.** Headroom measured today is 2046 bytes of 2048. Crossed by TEST-429, which reads the ledger, the pin and the live corpus in one arm.
8. **This spec's own closure claims to the append-only registry.** Crossed by TEST-443 through `verify-closures --strict`, which reads the ledger rather than this document's prose.
9. **The layer-profiles fixture build to `PROFILES.yaml`'s live-tree union invariant.** Any new `.aai` file this scope adds must be classified or the layer-profiles suite fails — the same suite whose flake this scope is fixing. Crossed by TEST-401 and by the existing TEST-001 of that suite.

Residual risks, written down because no automated test crosses them:

- **R1 — this scope does not prove the CI-only layer-profiles failure is gone, and says plainly that it does not know the mechanism.** Planning reproduced nothing: 16 concurrent standalone runs in a scratch clone were all green, on top of the twelve isolated runs the intake already records. What planning DID establish, from the failing job log of run `34737181188`, is that the standalone suite passed while its nested copy failed in the same sweep, and that the nested failure printed an EMPTY missing-file list — a state no incomplete copy produces and which planning could not construct. Spec-AC-01 and Spec-AC-02 are therefore written as the two checks that would have named the cause: a build that verifies what it copied, and an assertion that refuses to fire on a payload it cannot render. The claim this scope makes is that the NEXT occurrence explains itself, not that there will not be one. The one mechanism planning ruled out by measurement, and records so it is not re-investigated: `printf '%s\n' "$CORE_FILES" | grep -qxF` in the sync's prune loop cannot SIGPIPE today, because the core list is 5322 bytes against a 16 KiB pipe buffer — a latent hazard of the same family this scope drains under Spec-AC-11, not this failure.
- **R2 — the `reference-transaction` hook could PREVENT the HEAD move rather than detect it**, and is not used here: it is opt-in, not inherited by a clone, and changing what it refuses is consumer-visible git behaviour owned by ISSUE-0083 in sweep 5. The pin is therefore a detection, and a session that never pins is unprotected.
- **R3 — the after-numbers for the scheduler are modelled**, over the recorded per-suite durations of one run. They ignore disk contention from concurrent `git clone --local --no-hardlinks`, which is the stated reason the width is capped at 8. Spec-AC-06 is written against a MEASURED run, not against the model, and the model is only the reason to attempt it.
- **R4 — the rolling attribution window is more code than the barrier it replaces.** Corrected at remediation (validation round 1 BLOCKING-4; see `## Amendment`): the per-completion check design structurally bounds the window at `PARALLEL_WIDTH`, not 2x — TEST-413's own 4-suite/writer-in-initial-batch fixture can never approach the 2x-width truncation, so the original claim that "its bound is asserted by TEST-413 at twice the width" was false as written; the truncation at `:1800-1802` was dead code on every real run. TEST-413 now carries a genuine negative control (a 10-suite/width-2/late-writer fixture, run against both the shipped framework and a scratch copy with the reset and the truncation both removed) that reddens exactly the mutation the validator demonstrated, proving the safety net is load-bearing as defense-in-depth even though normal operation never reaches it. A bug inside the rolling window would still degrade attribution, which is the property this scope claims to preserve — this is still the single largest implementation risk in the sweep and the one review should read first.
- **R5 — 202 assertion rewrites is the largest mechanical surface here**, and 48 of them need judgement. The anchored-regex trap is named in the plan because a wrong rewrite is green.
- **R6 — the advance-only sha arm (validation round 4 BLOCKING-1's fix, see `## Amendment`) cannot distinguish the ceremony's OWN forward commit from a CONCURRENT session's forward commit on the SAME branch.** Measured at remediation round 5: pin at a sha, then a DIFFERENT committer commits in the same checkout — the resulting HEAD is a git-ancestor descendant of the pin exactly the same way the ceremony's own next commit would be, so `check-committed-scope.mjs` and `close-before-push-guard.mjs` both read it as "the ceremony's own write" and exit 0; only bare `--verify-pin` (exact-sha, no advance-only tolerance) still refuses. That is the 2026-09-06 incident shape CHANGE-0180 exists to catch, reopened by the very fix that closed BLOCKING-1. This is a deliberate, defensible trade, not an oversight: the amendment's own wording ("is read as the ceremony's own commit, not a concurrent move") overstated what a sha-ancestry check alone can know, and D5's session lock (Spec-AC-05, `session-lock.mjs`) is the ACTUAL control for a shared checkout — it refuses a second live session in the same worktree before either one can commit, which is where this residual is actually closed, not in the branch-guard sha compare. Named in Spec-AC-03's Notes column.

## Verification

- `bash tests/skills/test-aai-layer-profiles.sh`, `test-aai-feedback-upsert.sh`, `test-aai-friction-wiring.sh`, `test-aai-branch-guard.sh`, `test-aai-session-lock.sh`, `test-aai-sweep-parallel.sh`, `test-aai-run-tests.sh`, `test-aai-golden-flow.sh`, `test-aai-hygiene-pack.sh`, `test-aai-spec-lint.sh`, `test-aai-spec-amend.sh`, `test-aai-git-ref-guard.sh`, `test-aai-deslop.sh`, `test-aai-release.sh`, `test-aai-ceremony-levels.sh`, `test-aai-delta-stage3.sh`, `test-aai-repo-tripwire.sh`, `test-aai-follow-ups.sh`, `test-aai-suite-isolation.sh`, `test-aai-suite-select.sh`, `test-aai-prompt-diet.sh`, `test-aai-doctor.sh`, `test-aai-docs-audit.sh`, `test-aai-orchestration-dispatch.sh` — every TEST-4xx row green and every pre-existing arm in those suites green.
- Intermediate rounds run SELECTED plus CORE from `node .aai/scripts/select-suites.mjs --files-from <changed files>`; ONE full `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` runs before the close ceremony and is the sweep the TEST rows cite.
- The before and after wall-clock of that full sweep is recorded, at the same width, against the 1632 s of run `test-20260913-040817`.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0179-spec-test-framework-sweep.md`
- `env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/follow-ups.mjs verify-closures --path docs/specs/SPEC-0179-spec-test-framework-sweep.md --strict`
- PASS criteria: every TEST row green AND every Spec-AC in a terminal status **at close** (`.aai/VALIDATION.prompt.md` step 8a's AC-FLIP DEFERRAL: while this doc's frontmatter `status` is open, validation and code review MUST NOT flip the AC Status table terminal — a terminal, evidenced table under an open `status` is exactly what the probable-false-open heuristic flags. The flip is `.aai/SKILL_PR.prompt.md`'s own ordered close step, gated by `docs-audit.mjs --ac-flip-check`).

## Evidence contract

- ref_id: `test-framework-sweep`
- RED artifacts: `docs/ai/tdd/spec-test-framework-sweep/red-4NN.txt`, one per RED-first test named in `## Mutation checks`.
- Mutation artifacts: `mutation-408.txt`, `mutation-418.txt`, `mutation-428.txt`, `mutation-412.txt` (recorded in `mutation-sweep.txt`), `mutation-441.txt`, `mutation-445.txt`, `mutation-447.txt`, `mutation-422.txt`, `mutation-446.txt` and `mutation-sweep.txt` in the same directory. A test named there as mutation-only has NO red file and MUST have its mutation file; the two sets are disjoint and together cover all 49 tests. (Corrected at remediation, validation round 1 BLOCKING-17/18: the mutation-only set grew from 3 to 9 — see `## Amendment`.)
- Timing artifacts: `sweep-before.txt` and `sweep-after.txt`, each holding the full-sweep summary line with its RUN_ID, width and wall-clock.
- Partition artifacts: the frozen bucket list already at `bucket-open-2026-09-13.txt`, plus `closures.txt` holding the output of `follow-ups.mjs verify-closures --strict`.
- Per-test green runs with exit codes, plus the scoped diff; commit SHA or diff range on every artifact.

Strategy row (tdd): a stored RED artifact per AC-gating test plus the full verification matrix. The nine tests that cannot RED (see `## Amendment`) are covered by the recorded mutation failures instead, which is the substitution this section exists to declare.

## Registry items closed by this scope

48 of the 78 bucket ids (84 at freeze, corrected at remediation — validation round 5 BLOCKING-2, see `## Amendment`), each mapped to the Spec-AC above that fixes it and to a TEST row with a named mutation. Closed with
`node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by test-framework-sweep --source <sha>`.

- Spec-AC-01: fu-layer-profiles-fixture-build-race
- Spec-AC-02: fu-layer-profiles-suite-load-fragile
- Spec-AC-28: fu-nested-profiles-hides-missing-list
- Spec-AC-03: fu-head-moved-between-commands
- Spec-AC-05: fu-learned-worktree-seeded-copies
- Spec-AC-08: fu-sweep-dies-at-wrapper-default
- Spec-AC-09: fu-live-page-blind-to-the-sweep
- Spec-AC-10: fu-golden-flow-record-append-unlocked
- Spec-AC-11: fu-drain-pipe-grep-q-ratchet
- Spec-AC-12: fu-exit-contract-pin-comment-dup, fu-allowlist-count-is-prose-not-asserted, fu-test031-self-neutralizes-post-merge, fu-test210-branch-now-dead-code
- Spec-AC-13: fu-ceremony-test016-blanket-byte-pin, fu-usage-pin-misses-appended-flag, fu-closure-allowlist-pin-blocks-draining, fu-test029-count-not-subset, fu-test013-uncovered-on-legal-max-raise, fu-test031-guard-dies-at-rename
- Spec-AC-15: fu-learned-bash32-local-crossref, fu-empty-path-cd-stays-in-shipping-repo, fu-learned-immutable-pin-lint, fu-learned-deny-by-default-mocks, fu-learned-positive-control-for-absence, fu-learned-external-runner-routing, fu-learned-vitest-leak-is-a-guard
- Spec-AC-16: fu-tdd-skips-full-sweep, fu-validation-ignores-suite-selector, fu-suitemap-state-missing-role-common
- Spec-AC-17: fu-iso-bases-reset-discards-entries, fu-iso-wrapper-traps-dont-reap-group
- Spec-AC-18: fu-seed-loss-turns-an-arm-into-a-skip, fu-seed-step2-enumeration-silent, fu-marker-append-failure-discarded
- Spec-AC-19: fu-isolation-suite-not-hermetic, fu-wrapper-hidden-suite-run-unreported, fu-drained-suites-still-write-unisolated
- Spec-AC-20: fu-tripwire-allowed-ignores-pre-dirty, fu-tripwire-degrade-not-on-suite-line, fu-tripwire-fixture-dirs-leak
- Spec-AC-21: fu-tripwire-suite-comment-transitional, fu-isolation-suite-presumes-deletion, fu-framework-comment-mislabels-d5, fu-drain-spec-says-d7-filed-not-fixed
- Spec-AC-22: fu-ismain-symlink-realpath
- Spec-AC-23: fu-reaper-epoch-export-fails-test005
- Spec-AC-24: fu-docsaudit-t003-red-on-new-doc
- Spec-AC-25: fu-test056-duplicates-routing-parser

## Registry items rejected by this scope

30 of the 78 bucket ids (36 of 84 at freeze; six removed at remediation —
validation round 5 BLOCKING-2, see `## Amendment` — rather than rejected,
because they were owner sign-off items for OTHER specs that never belonged
in this scope's bucket), each closed with the same command plus `--status dropped
--resolved-by test-framework-sweep --source "<the reason below>"`. Corrected at
remediation (validation round 1 BLOCKING-12, see `## Amendment`): the ORIGINAL text
here claimed the reason goes into `--resolved-by`, citing the CLI's own header-comment
contract (`"resolved_by": "<ref that resolved it, or the reason for dropped>"`) — but
that phrase is itself a pre-existing, repo-wide documentation inaccuracy in
`follow-ups.mjs` (predating this ride, SPEC-0129): EVERY dropped record in the whole
ledger, not only this ride's 36, carries the ride/triage ref in `resolved_by` and the
reason in `source`, and this ride's 36 closures followed that same established,
actual grammar rather than the header comment's aspirational one. Rewriting 36
append-only ledger records to match the wrong wording would be the more expensive,
less truthful fix; the wording here now matches the ledger's real, established
grammar instead. A reason that names a sweep names the
ride that owns the subject, per the wave-3 mandate table. These ids are deliberately
NOT listed under the closed-by-this-scope heading, because `verify-closures` reads that
heading as a claim of `done`.

| id | reason |
|----|--------|
| fu-orchestrator-git-add-scope-bleed | orchestrator shell habit with no repository surface to assert against; agent-shell class of ISSUE-0037 |
| fu-orchestrator-probe-touched-git | same agent-shell class; the probe was the orchestrator's own shell, not a suite |
| fu-probe-redirect-lands-in-shipping-cwd | same agent-shell class; CHANGE-0166 states these are covered by the agent-shell boundary intake, not here |
| fu-filed-list-trusted-again | orchestrator habit whose mechanical cause is fu-report-ids-exceed-registry-cap, outside this bucket and owned by sweep 3 |
| fu-cli-exit-truncates-pipe-sweep | duplicate of DEBT-0003 over 41 CLIs repo-wide, owned by sweep 3; this scope applies the safe shape to every CLI it touches without claiming the sweep |
| fu-vague-term-line-attribution | wrong subsystem: spec-lint line attribution, owned by sweep 4 |
| fu-intake-dir-unanchored-research-hotfix | wrong subsystem: intake doc identity, ISSUE-0042, sweep 4 |
| fu-posix-arm-reddens-on-prose-backslash | wrong subsystem: the INDEX arm, ISSUE-0033, sweep 4 |
| fu-staleness-source-line-self-certifies | wrong subsystem: the INDEX arm, ISSUE-0033, sweep 4 |
| fu-stale-check-nofetch-unexercised | wrong subsystem: the intake staleness CLI, sweep 4 |
| fu-acflip-runid-hex-false-positive | wrong subsystem: the AC-flip guard in docs-audit, sweep 4 |
| fu-overview-project-from-dirname | wrong subsystem: the overview generator, sweep 4 |
| fu-overview-links-gitignored-reports | wrong subsystem: the overview generator, sweep 4 |
| fu-overview-pages-bake-worktree-name | wrong subsystem: the overview generator, sweep 4 |
| fu-close-evidence-paths-worktree-blind | wrong subsystem: close-work-item internals, sweep 4; this scope adds only an expect-branch re-check there |
| fu-close-reconcile-worktree-vs-range | wrong subsystem: close-reconcile, sweep 4 |
| fu-detached-worktree-never-closes | wrong subsystem: the close ceremony, sweep 4; the degrade line it quotes exists nowhere in this repository, so nothing here can be asserted about it |
| fu-role-guard-noops-close-work-item | wrong subsystem: close-work-item exit-code discrimination, sweep 4 |
| fu-role-guard-blocks-own-fixtures | the fix is in state.mjs, a protected_paths_l3 surface that would force ceremony 3; owned by sweep 3 |
| fu-dispatch-gate-spawn-seam-untested | wrong subsystem: the dispatcher roadmap gate, sweep 3 |
| fu-sweep-ledger-verdict-typed-pass | wrong subsystem: the metrics flush ledger, sweep 1 |
| fu-contract-prefix-order-unenforced | wrong subsystem: the subagent contract and dispatch payload assembly, sweep 7 |
| fu-learned-framework-owns-how | the item states its own home is canon rather than a lint, which is sweep 7 |
| fu-sweep-scope-excludes-repo-root | wrong subsystem: withdrawn-claim sweeps, DEBT-0007, sweep 7 |
| fu-sweep-regex-misses-present-tense | wrong subsystem: withdrawn-claim sweeps, DEBT-0007, sweep 7 |
| fu-ac08-negation-coverage | wrong subsystem: the aai-update gitignore reconcile, sweep 5 |
| fu-release-ps1-rawexit-regex-unpinned | wrong subsystem: the release PowerShell engine, not the test framework |
| fu-friction-scoring-rewards-recurrence | wrong subsystem: friction triage scoring, sweep 6 |
| fu-specs-embed-developer-local-paths | wrong subsystem: a docs hygiene sweep over merged specs, sweep 4; this spec avoids adding a twenty-fifth instance |
| fu-spec-evidence-cites-gitignored-path | claim narrowed (code review NB-14, corrected via `follow-ups.mjs close --correct`): the original reason overclaimed ("no spec in the repository cites a gitignored evidence path today") — gitignored evidence citation is a common house style for AC evidence across many specs, not a residual (validation round 4 F-6: the exact count is extraction-method-sensitive — three independent measurements this ride produced three different pairs, from ~16% to ~82%, depending on which path forms and cells are scanned — so no specific digit is asserted here as fact; `docs/ai/decisions.jsonl:917`'s own "470 of 575 … 842 of 1193 … 120 specs" figures are unreproducible without the record naming its extraction, and the record cannot be edited — append-only). The narrower, true claim stands regardless of the exact count: the spec that prompted this item no longer cites its own evidence in the shape originally described |
REMOVED at remediation (validation round 5 BLOCKING-2, see `## Amendment`):
`fu-amend-live-agent-dashboard-ser-e1ff12`, `fu-amend-roadmap-driven-ride-sele-1e2448`,
`fu-amend-lessons-that-must-hold-d-13bccc`, `fu-amend-friction-publish-hides-r-b86049`,
`fu-amend-spec-harness-universal-routing` and `fu-amend-friction-upsert-channel-ba7701`
— the first five ids this table listed as "re-tracked, not a framework item"
(Amendment 2026-09-14) after the 2026-09-14 orchestrator ledger repair, plus a
SIXTH found while re-verifying the fix (same row, same rationale, listed just
above this note in every version of this table before this edit: "owner
sign-off backlog: only the owner can discharge an amendment sign-off"). That
repair's mechanism did not do what it claimed
(`spec-amend.mjs`'s own documented precedence, `:336-339`, means an overlay can
never re-point a record's INLINE `tracked_by`, so 12 of the 13 affected records
kept resolving to the dropped original regardless of the new retrack items).
The actual fix is not a re-track at all: these six are owner sign-off items
for OTHER specs that this scope's AC-26 closure should never have swept into
its own bucket in the first place, so they are REOPENED under their ORIGINAL
ids (`follow-ups.mjs reopen`, which this round adds) rather than closed here
under any status, and the five interim `*-retrack` items (the sixth, ba7701,
was never re-tracked — it was simply dropped and masked by TEST-009's
substring bug) are dropped as duplicates. They therefore no longer belong in
this table (or in the closed table): this scope's own bucket total drops from
84 to 78 (48 closed + 30
rejected), and TEST-443 (`test-aai-follow-ups.sh`) and its row-count pin are
updated to match.

## GitHub issues

- **#368 REJECTED.** Its entire body is a friction metadata block with no prose: `failure_class: deterministic_script_failure`, `skill: REMEDIATION / reproduce`, `os_family: windows`, `aai_pin: v2026.08.16`, and an `evidence_ref` naming `docs/ai/reports/VALIDATION-20260826-161909Z-prd009-mms-control-input-scope.md`. No comments. That path does not exist in this repository, nothing matching `prd009` or `mms-control-input` does, and the fingerprint is absent from `docs/ai/friction/`: it is a downstream install's artifact, three weeks and several releases behind. No script is named, no command, no error text, no exit code. A Windows machine would not help, because nothing was captured to reproduce. The framework-side fix is the CHANNEL that files prose-free issues, which is already intaked as `docs/issues/CHANGE-0179-friction-issues-arrive-without-a-description.md` and measures the identical pathology on #338 and #339; #368 is a third instance and is folded into that decision, in sweep 6.

## Amendment (post-freeze, 2026-09-13 — remediation after validation round 1 FAIL)

This is a FROZEN spec, amended after the freeze and disclosed here rather than
rewritten silently, per the additive-with-disclosure convention (see e.g.
`docs/specs/SPEC-0178-...md` `## Amendment`). Validation round 1
(`docs/ai/tdd/spec-test-framework-sweep/validation-round1.txt`) returned FAIL
with 12 numbered findings; every one is addressed at cause, in this same round,
and disclosed here rather than left implicit in a diff. Authority:
`docs/ai/decisions.jsonl`, `type: spec_amendment`, `ref_id: test-framework-sweep`
(owner sign-off owed — a follow-up is filed for it, same as every other
amendment in this repository's history).

- **AC-07 / R4 (BLOCKING-4).** The 2x-PARALLEL_WIDTH truncation
  (`test-framework.sh:1800-1802`) was dead code on every real run: the
  per-completion-check scheduler design structurally bounds the attribution
  window at `PARALLEL_WIDTH`, not 2x, so TEST-413's original 4-suite fixture
  (writer in the initial batch) could never approach the bound. TEST-413 now
  carries a genuine negative control — a 10-suite/width-2/late-writer
  fixture, run against both the shipped framework (bounded, as always) and a
  scratch copy with the clean-path reset AND the truncation both removed
  (unbounded, reddening the same check) — proving the safety net is
  load-bearing defense-in-depth even though normal operation never reaches
  it. R4 and the AC-07 table row are corrected above to state this plainly
  rather than repeat the false "asserted... at twice the width" claim.
- **AC-12 (BLOCKING-5/6).** TEST-445 and TEST-447 existed only in this
  document's own prose — nowhere in `tests/`, `.aai/` or anywhere else. Both
  are now real tests (`test-aai-spec-amend.sh
  test_445_ac12_negative_controls_test003_008_009`,
  `test-aai-deslop.sh test_447_released_changelog_comparison_negative_control`),
  each with a genuine mutation or deliberately-broken-input control
  (`mutation-445.txt`, `mutation-447.txt`). `test-aai-release.sh:57`'s
  `RELEASE_ENGINE_PIN_SHA` was byte-identical to the live engine (this scope
  never touched `.aai/scripts/aai-release.sh` — `git log origin/main..HEAD`
  over it is empty, and 230921a8, the commit the pin named, is still the
  file's last-touching commit) — a self-comparison, the exact DEBT-0004
  shape this AC exists to remove. Re-pinned to `6adfe840956f9c52ab645a6db5c479120310d907`
  (blob at commit ffe3f320, the commit immediately BEFORE 230921a8 to touch
  the file — genuinely different content, and the diff between the two
  touches only the `--confirm`-less preview path TEST-031 never exercises).
  A new negative control in `test_031_unprotected_path_byte_identical`
  mutates a scratch copy of that pinned blob (one stdout line) and proves
  the byte-identity comparison catches it.
- **AC-26 / TEST-443 (BLOCKING-16).** `test-aai-follow-ups.sh:2027` used to
  `log_skip` (`exit 42` — voids the WHOLE suite, per this file's own
  documented trap) when `bucket-open-2026-09-13.txt` was absent — true on
  every fresh `git clone`/CI checkout, since the path is gitignored
  (`.gitignore:35`). The frozen id list's canonical source is now the
  spec's OWN closed+rejected tables (tracked, committed) — proven
  byte-set-identical to the gitignored file's 84 ids — with the gitignored
  file kept only as a non-blocking corroboration where present. Reproduced
  fixed with a `git ls-files`-only rebuild of the tree (the CI/fresh-clone
  condition): the old code SKIPs (rc=42, product_red evidence), the new
  code PASSes (rc=0).
- **Evidence contract — RED_CLASS (BLOCKING-17).** None of the 44 (now 41)
  `red-*.txt` files carried the `RED_CLASS` line the shipped
  `tdd-evidence-check.mjs --red` classifier and `test-aai-spec-lint.sh`'s
  own `test_clarify_012_red_class_stamped` arm require — a scope-level gap
  predating this ride, not a regression it introduced, but blocking because
  the guard that should have caught it (that same TEST-012(clarify) arm) was
  itself vacuous: it scans a glob (`docs/ai/tdd/red-*vagueness-gate*.log`)
  this spec's own evidence never matched, so it always measured n=0 and
  passed on an absent premise — the exact AC-15 absence-no-control shape.
  Every `red-*.txt` now carries `RED_CLASS: product_red` as line 1;
  `tdd-evidence-check.mjs --red` exits 0 on all 41. Five files whose
  original capture died at a raw shell "command not found" BEFORE any
  product assertion ran (`red-402`, `red-403`, `red-421`, `red-424`,
  `red-448` — a genuine `infra_fail` shape, not `product_red`) were
  RE-CAPTURED with the underlying property genuinely exercised (a
  behaviorally-neutralized scratch copy of the guard under test, never a
  missing dependency), so each now reaches and reports the test's own FAIL
  line. `test_clarify_012_red_class_stamped` gained a positive control
  (validation round 2, R2-2): the scan loop's root is now a variable
  (`AAI_T012_SCAN_ROOT`, default `docs/ai/tdd`), the loop body itself is a
  shared function (`t012_scan_red_logs`, no duplicated regex), and the
  control plants a well-formed/malformed fixture pair INSIDE a scratch copy
  of that root, then re-runs the SAME function against the copy and asserts
  its own reported count rose by the two planted files and classified one
  STAMPED and the other UNSTAMPED — proving the loop itself discriminates,
  not a copy of its regex. The real `docs/ai/tdd` corpus still carries no
  `red-*vagueness-gate*.log` file for this scope (n=0 there), so the
  primary claim is a NOTE-degraded no-op on this tree and the positive
  control is what carries the arm's bite.
- **Evidence contract — mutation-only carve-outs (BLOCKING-18).** TEST-412,
  TEST-422, TEST-441, TEST-445, TEST-446 and TEST-447 join the
  "CANNOT go RED by construction" list (previously only TEST-408/418/428):
  TEST-412 and TEST-441 assert invariants that also held on the pre-change
  tree (reproduced directly against `origin/main`); TEST-422 and TEST-446's
  pre-fix defect IS a wrongly-green PASS, not any kind of FAIL, so neither
  ever had a genuine red state to capture; TEST-445 and TEST-447 test
  engine files this branch never touched. `red-441.txt`'s content (already
  the correct "cannot go RED" declaration, just filed under the wrong
  naming convention) is merged into `mutation-441.txt` and the stray
  `red-441.txt`/`red-422.txt`/`red-446.txt` files are removed, matching the
  Evidence contract's own rule that a mutation-only test has NO red file.
  `green-424.txt` (BLOCKING-19, zero PASS lines, prose admitting the arm
  still failed) is re-recorded from a genuinely passing run now that
  Spec-AC-26's bucket closure has landed.
- **AC-19 (BLOCKING-21).** The original fix covered only TEST-001, TEST-003
  and TEST-005's own bodies; every OTHER `test-framework.sh` invocation in
  `test-aai-suite-isolation.sh` (TEST-002, TEST-004, TEST-201 through
  TEST-211 and more — 20 call sites) still inherited
  `AAI_TEST_ISOLATION` from the operator's ambient shell. Every call site
  now states `AAI_TEST_ISOLATION=1` explicitly (one site — TEST-004(d)'s
  `perl -e '... exec @ARGV'` probe — needed the var set on `perl`'s OWN
  environment rather than passed as a literal `argv` element, since
  `exec LIST` bypasses the shell and never parses `VAR=value` prefixes).
  TEST-434 now actually re-runs all three functions under an exported
  `AAI_TEST_ISOLATION=0`, not just TEST-001 with a `log_pass` prose claim
  about the other two. Reproduced: `env -u AAI_ROLE -u AAI_TEST_ISOLATION`
  and `AAI_TEST_ISOLATION=0 env -u AAI_ROLE` both now exit 0 over the whole
  suite (44 arms).
- **AC-08 (BLOCKING-22).** `aai-run-tests.ps1`'s `Get-EffectiveTimeout`
  still returned 300 and forced that value into the inner `.sh` on both the
  WSL and Git-Bash paths (`:535`, `:573`), silently overriding the `.sh`
  wrapper's already-shipped raise to 3000 on every Windows run — the
  cross-platform parity `aai-run-tests.sh:56-60` itself claims was false.
  Now raises to 3000. The header comment (`:81-82`) and the Pester fixtures
  that pinned the old default (`aai-win-dispatch.Tests.ps1`, 4 assertions)
  are corrected to match; all 150 Pester cases pass. A new grep-based check
  in `test-ps1-quality.sh` (runs without `pwsh`, unlike the Windows-5.1-only
  Pester leg, which cannot be exercised on this machine at all) pins the
  `.ps1` and `.sh` defaults equal going forward.
- **AC-04 (BLOCKING-1/2).** `pinDir()` forked `git rev-parse --git-dir`
  even on the no-pin path — measured with a git shim, one subprocess on a
  no-pin fixture, contradicting D4's "costs one stat" and the code comment
  at `branch-guard.mjs:33-35`. A new `pinDirFast()` resolves the git-dir via
  `fs.lstatSync`/`fs.readFileSync` only (a main checkout's `.git` directory,
  or a linked worktree's `.git` file's `gitdir:` line), falling back to the
  git subprocess for anything else (bare repo, `GIT_DIR` override, cwd not
  at the repo root) so correctness never trades against the stat-only
  promise; re-verified with the same shim (zero git subprocess calls on
  `--verify-pin` with no pin file). Separately, TEST-408's baseline moved
  from `git show HEAD:` — already the scope's OWN post-change script,
  measured 8 occurrences of `verify-pin` in it, an identity check — to
  `git show origin/main:` (falling back to `main`, failing closed if
  neither resolves rather than silently passing), the genuine pre-change
  blob.
- **AC-14 (BLOCKING-7/9).** Established fact 18 and the AC-14 row both said
  "35", measured with `grep -i`; `degenerate-pass-ratchet.sh` actually
  scans case-sensitively (matching the rest of its ratchet family) and
  measures 31 pre-scope (`origin/main`) / 26 post-scope (five of the nine
  converted guards also carried this shape) — the ratchet's own header
  comment now states this measured provenance instead of a false "matching
  the spec's own established-fact measurement" claim. Separately,
  `test-aai-follow-ups.sh`'s delivery-diff guard (TEST-031/TEST-448) is a
  genuinely PERMANENT UNCOVERED case: its primary path (is this scope's own
  spec, SPEC-0159, part of the live diff) can never fire again once
  SPEC-0159 is merged history, on any future branch. It used to report
  UNCOVERED via `log_info` and then still fall through to an unqualified
  `log_pass` claiming "no other frozen spec document is touched" — exactly
  what Spec-AC-14 exists to refuse. A literal `log_fail` there would abort
  the WHOLE suite immediately under this file's `set -euo pipefail` (unlike
  sibling suites with a soft per-arm failure registry), voiding every test
  after it (TEST-443 included) on every future run forever — a worse
  defect than the one being fixed. The function's own final verdict message
  is now honest instead: it states plainly when the primary path is
  UNCOVERED and that the verdict rests on the TEST-448 negative control
  alone (which is real, re-runs every time, and does gate the function).
- **AC-22 (BLOCKING-10/11).** `.aai/scripts/allocate-doc-number.mjs` is 1 of
  the 24 `.aai/scripts/*.mjs` main-guard call sites and was excluded from
  the realpath fix only in a test comment
  (`test-aai-doctor.sh:1861-1866`), never in this document — the AC text
  still said "every one of the 24" and no residual risk named the gap. The
  exclusion itself is defensible (the file is one of eight
  `docs/ai/docs-audit.yaml` `protected_paths_l3` surfaces; touching it
  forces `ceremony_level:3` and this ride is ceremony 2 — established fact
  9) but was undisclosed. The AC-22 table row above now states the
  exception plainly, and `fu-realpath-allocate-doc-number-l3` (P3) is filed
  to track it — `fu-ismain-symlink-realpath` stays closed `done` for the 22
  of 23 guards it actually fixed (validation round 2 NON-BLOCKING: the 24th
  file, `.aai/scripts/heartbeat.mjs:435`, references `process.argv[1]` only
  inside a comment, so the real accounting is 23 actual main guards = 22
  resolved + this one excluded, not 24 or "23 of 24" as this bullet
  previously said — review R3-NB-3) rather than being reopened for a defect
  it never claimed to cover for this one file.
- **AC-26 (BLOCKING-12/13).** The "Registry items rejected by this scope"
  preamble claimed the reason for each of the 36 dropped ids goes into
  `--resolved-by`, citing `follow-ups.mjs`'s own header-comment contract
  (`"resolved_by": "<ref that resolved it, or the reason for dropped>"`).
  That phrase is itself a pre-existing, repo-wide documentation inaccuracy
  (predating this ride, SPEC-0129): every dropped record in the WHOLE
  ledger — not only this ride's 36 — carries the ride/triage ref in
  `resolved_by` and the reason in `source`, and this ride's closures
  followed that same established, actual grammar. Rewriting 36 append-only
  ledger records to match the wrong wording would have been the more
  expensive, less truthful fix; the preamble and the AC-26 table row are
  corrected to match the ledger's real grammar instead. Separately, the AC's
  promised "`suite-map.yaml` row plus row-count pin" did not exist —
  `test-aai-hygiene-pack.sh`'s `test_090_suite_map_pin` was a per-suite
  EXISTENCE check, not a count. A row-count pin is now written (a top-level
  `<name>:` row count over `suite-map.yaml`, pinned at 93).
- **AC-06 (BLOCKING-3).** The delivered `sweep-after.txt` (835.29 s) was
  measured on a 93-suite/19-failure run against a 92-suite/92-PASS baseline
  — different corpus, different outcome profile, an undisclosed confound.
  `sweep-after.txt` is re-recorded from a full local sweep of the CURRENT,
  remediated tree (`bash .aai/scripts/aai-run-tests.sh bash
  tests/skills/test-framework.sh`, run `test-20260913-180339`, 89/93 PASS,
  width 8) — and it carries its OWN disclosed confound in turn: this sweep
  ran concurrently with several OTHER full suites this same remediation
  round also ran (hygiene-pack, suite-isolation x2, sweep-parallel,
  prompt-diet, layer-profiles, doctor), so its 1850 s wall-clock reflects
  real CPU contention, not the scheduler alone, and is stated as such rather
  than presented as a clean number. The gate is instead recommended against
  the two UNCONTENDED, already-on-record runs this remediation round did not
  touch (`test-20260913-151649` 726 s, `test-20260913-154408` 735 s — both
  comfortably under the 1060.8 s threshold, both already the validator's own
  cited corroboration) — see `sweep-after.txt` for the full, honest
  accounting of both numbers and why neither is hidden in favour of the
  other. NON-BLOCKING UPDATE (validation round 2): a later full sweep this
  round, `test-20260913-185949`, finished 93/93 PASS at 897 s — the first
  zero-failure full sweep on this branch and the first apples-to-apples
  comparison against the canonical 92/92-PASS baseline (same outcome
  profile, one suite heavier). 897 / 1632 = 55.0% <= 65%, PASSING, and the
  run was contended (concurrent with the validator's own other checks), so
  897 s is an upper bound, not a cherry-picked number. `sweep-after.txt` now
  cites this run as the primary AC-06 evidence; the 726 s / 735 s pair
  remains as corroborating uncontended-machine evidence.
- **AC-03 (validation round 4 BLOCKING-1).** Spec-AC-03's HEAD-sha comparison
  is amended to ADVANCE-ONLY for a caller that names `--expect-branch`: a
  same-branch HEAD that is a git-ancestor descendant of the pinned sha
  (`git merge-base --is-ancestor <pin.sha> HEAD`) is read as the ceremony's
  OWN commit, not a concurrent move, and passes. Bare `--verify-pin` (no
  `--expect-branch`) is UNCHANGED and keeps the original exact-sha-match
  reading TEST-405 exercises. Root cause: SKILL_PR pins HEAD once at step 0
  (PRECONDITIONS) and then COMMITS at steps 4/4c/5c, so an exact-match sha
  check made `checkBranchPin` refuse the very ceremony that armed it —
  measured end to end on a fresh fixture with one session, one branch and no
  concurrency, steps 4a/4c/5 all refused a HEAD move the SAME session had
  just made, and the prompt told the agent to STOP at 4a and REVERT the
  AC-table flip at 4c (a 100% false positive on every ride). The engine was
  not at fault (the exact-sha reading was what Spec-AC-03 specified); the
  WIRING gave the ceremony no way to re-establish the pin between its own
  writes. `--expect-branch <b>` is ALSO amended to actually compare `b`
  against the current branch (closing review NB-3: the flag used to be read
  only as a boolean opt-in for the pin-file check, never against its own
  value — `--expect-branch zzz-nonexistent` and `--expect-branch main`
  produced byte-identical output on a mismatching pin). TEST-454
  (`test-aai-branch-guard.sh`) proves the full sequence end to end: pin ->
  the ceremony's own commit -> all three call sites pass; a genuine
  concurrent reset to an older, non-descendant commit on the same branch
  still refuses at each, with its documented code. Exits 5/6/7 stay the
  three named causes AC-03 requires; exit 4 (no-work-tree) is unchanged.
- **AC-03 / NB-3 crossing test (validation round 5 BLOCKING-1).** The
  amendment above closed the NB-3 behaviour but shipped no test that could
  tell `wantBranch = expectBranch || pin.branch` (`branch-guard.mjs:494`)
  apart from a one-line revert to `wantBranch = pin.branch`: every
  `--expect-branch` in the whole corpus named the SAME branch the fixture
  pinned, so the argument's VALUE was never exercised, only its presence.
  `test-aai-branch-guard.sh` TEST-455 crosses it: pin on branch A, stay on A,
  call each of the three ceremony sites with `--expect-branch B` (a
  different, existing, sibling branch — neither an ancestor of the other, so
  the advance-only sha arm cannot rescue a mismatch here) — each refuses,
  naming A as the actual branch, at its own documented code (3/7/3); the
  same fixture with a NONEXISTENT `--expect-branch` name refuses with the
  code-6 "renamed or removed" wording. A second arm switches to B and names
  `--expect-branch B` — the branch NAME now matches HEAD, but the pin was
  taken on A at a different, non-ancestor sha — and still refuses, citing
  the pin's own sha. Verified reddening under the `wantBranch = pin.branch`
  mutation (all three call sites in the first arm wrongly report ok).
  Separately, F-2's remainder (validation round 4 partial close) is also
  closed this round: `SKILL_PR.prompt.md` step 4a's per-step grep used an
  `-A1` window whose second line is PROSE ("`--expect-branch` re-checks step
  0's pin…") that itself contains the substring `--expect-branch`, so
  deleting the flag from the command line alone left the assertion green.
  TEST-453's 4a arm now anchors on the command line itself (`grep -qF` on
  the full `check-committed-scope.mjs --from-state --strict --rev HEAD
  --expect-branch` string, no window) and reddens correctly when only the
  command-line flag is removed.
- **AC-26 ledger repair, corrected (validation round 5 BLOCKING-2).** The
  2026-09-14 orchestrator ledger repair recorded above did not achieve what
  it claimed: `spec-amend.mjs`'s own documented precedence (a record's
  inline `tracked_by` always wins over an overlay's) meant the five new
  retrack items and their `classify --tracked-by` overlays were inert for 12
  of the 13 affected unsigned amendment records, which kept resolving to the
  now-dropped original tracker. The apparent fix (TEST-009 going green) was
  a description-substring match, not a genuinely open item — measured via a
  pre/post truncated-ledger probe by validation round 5. The real repair,
  this round: `follow-ups.mjs reopen --id <id> --reason "<one line>"
  [--source "<evidence>"]` (new subcommand, closing `fu-registry-has-no-reopen`
  — owned by another sweep's bucket, closed here because this ride delivered
  the mechanism it needed to fix its own mistake, `--resolved-by
  test-framework-sweep --source` naming `test-aai-follow-ups.sh` TEST-456)
  appends a `status: open` `follow_up_status` record, exactly the same
  append-only shape `close`/`--correct` already use, so the fold's LATEST
  record (which already tolerated an explicit `"open"` status value) projects
  the item as open again without any change to the reader. The five original
  ids (`fu-amend-live-agent-dashboard-ser-e1ff12`,
  `fu-amend-roadmap-driven-ride-sele-1e2448`,
  `fu-amend-lessons-that-must-hold-d-13bccc`,
  `fu-amend-friction-publish-hides-r-b86049`,
  `fu-amend-spec-harness-universal-routing`) are reopened with reason
  "dropped in error by test-framework-sweep AC-26: an owner sign-off item is
  not a framework item"; the five `-retrack` items are dropped as duplicates
  (`--status dropped --resolved-by test-framework-sweep`); the one record
  with no inline `tracked_by` (`2026-09-12T12:50:00Z`,
  `friction-publish-hides-required-followup`) has its overlay re-pointed at
  the reopened original via `spec-amend.mjs classify --tracked-by` (legal
  now that the target is open again — `classify --tracked-by` refuses a
  CLOSED target). A SIXTH instance of the same mistake surfaced while
  re-verifying the fix under a corrected TEST-009 (see the F-A/BLOCKING-2
  entry above and `test-aai-spec-amend.sh` TEST-009): `fu-amend-friction-
  upsert-channel-ba7701` (spec `friction-upsert-channel-cannot-file`) was
  dropped by this scope's AC-26 closure with the identical "owner sign-off
  backlog" rationale, never re-tracked at all, and masked by the same
  substring bug via an unrelated open item that merely quotes its id
  (`fu-factory-report-stale-draft-path`). Reopened and removed the same way.
  All six ids are REMOVED from `## Registry items rejected by this scope`
  entirely (not re-added under any status): they are owner sign-off items
  for OTHER specs that never belonged in this scope's bucket, a scoping
  error the original AC-26 closure made and this ride's own retrack repair
  compounded rather than corrected. This scope's bucket total moves from 84
  (48 closed + 36 rejected) to 78 (48 + 30); Spec-AC-26, TEST-443 and the
  local (gitignored) frozen-bucket corroboration file all move with it.
  Measured post-repair: `spec-amend.mjs list --status unsigned --json` shows
  all 13 affected records' `tracked_by` resolving to an OPEN item (13/13 —
  the count the dispatch's own bounded scope names; the sixth item's own
  unsigned records resolve to open too, verified separately);
  `follow-ups.mjs list --status open` shows the six original ids and not
  the five retracks (the sixth was never re-tracked to begin with).
- **Spec-AC-03 residual R6 (validation round 5 F-A, non-blocking).** The
  BLOCKING-1 amendment's wording ("a same-branch HEAD that is a git-ancestor
  descendant of the pinned sha … is read as the ceremony's OWN commit, not a
  concurrent move") overstates what a sha-ancestry check alone can know: it
  cannot distinguish the ceremony's own forward commit from a DIFFERENT
  committer's forward commit on the same branch in the same checkout, which
  is exactly the 2026-09-06 incident CHANGE-0180 exists to catch. This is a
  deliberate, defensible trade (not a defect to fix here) because D5's
  session lock (Spec-AC-05, `session-lock.mjs`) is the actual control for a
  shared checkout — it refuses a second live session before either commits
  — but the residual was previously undisclosed. Added as R6 under
  `## Implementation plan`'s residual-risks list and named in Spec-AC-03's
  Notes column.

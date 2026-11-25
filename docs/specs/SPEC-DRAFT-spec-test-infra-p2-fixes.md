---
id: spec-test-infra-p2-fixes
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 73d0cc2629d860333296b64dbe4842d2f7dd86f8b1e51167965d0283ff8372d5
ceremony_level: 2
links:
  requirement: test-infra-p2-fixes
  rfc: null
  pr: []
  commits: []
---

# Test infrastructure: close the nine open P2 follow-ups

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/CHANGE-DRAFT-test-infra-p2-fixes.md (owner
  brief 2026-11-25).
- Prior scopes whose frozen text or tests this scope changes (see D-AMEND):
  docs/issues/CHANGE-0099-deterministic-friction-capture.md (AC-001, the
  wrapper records every non-timeout failure),
  docs/specs/SPEC-0185-spec-friction-channel-sweep.md (TEST-655 and
  TEST-659 drive a failing command through the wrapper),
  docs/specs/SPEC-0231-spec-docs-index-broken-refs-scope.md (implementation
  prose: one argument runs only that function).
- Prior scopes that already delivered part of an item (history, not
  amended): SPEC-0206 and SPEC-0240 (item 6), SPEC-0268, SPEC-0270 and
  SPEC-0271 (item 8).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, Node 22 floor,
  bash 3.2 suites run through `.aai/scripts/aai-run-tests.sh`).
- Structural model: docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md.

## Implementation strategy

- Strategy: tdd
- Rationale: every item that is fixed has a defect observed on the
  unchanged tree (see Measurements), so every test can be watched failing
  first. The items are test-infrastructure guards; a guard whose test was
  never seen red proves nothing.

## Isolation and review

- Worktree recommendation: recommended
- Worktree rationale: PR-bound ride touching the shared test runner, the
  framework, docs-audit and eleven suites; the main checkout is shared by
  other sessions.
- User decision: worktree (owner brief 2026-11-25 named the path)
- Base ref: origin/main at 5f02b0e5
- Worktree branch/path: chore/p2-test-infra at
  /Users/ales/Projects/aai-worktrees/p2-test-infra
- Review required: true
- Review scope (explicit paths): .aai/scripts/aai-run-tests.sh;
  tests/skills/test-framework.sh; .aai/scripts/docs-audit.mjs;
  .aai/scripts/lib/docs-audit-core.mjs; tests/skills/test-aai-run-tests.sh;
  tests/skills/test-aai-suite-isolation.sh;
  tests/skills/test-aai-friction-capture-points.sh;
  tests/skills/test-aai-prompt-diet.sh; tests/skills/test-aai-docs-audit.sh;
  tests/skills/test-aai-mutation-gate.sh; tests/skills/test-aai-hygiene-pack.sh;
  tests/skills/test-aai-intake.sh; tests/skills/test-aai-share.sh;
  tests/skills/test-aai-tdd.sh; tests/skills/test-aai-worktree.sh;
  tests/skills/test-aai-git-ref-guard.sh (marker or fix, D9 only);
  docs/TECHNOLOGY.md; CHANGELOG.md;
  docs/issues/CHANGE-0099-deterministic-friction-capture.md;
  docs/specs/SPEC-0185-spec-friction-channel-sweep.md;
  docs/specs/SPEC-0231-spec-docs-index-broken-refs-scope.md;
  docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md;
  docs/issues/CHANGE-DRAFT-test-infra-p2-fixes.md.

## Measurements (origin/main 5f02b0e5, 2026-11-25)

All runs used a throwaway `git clone --local --no-hardlinks` of this
worktree under the Planning scratch directory, with a fake `HOME` and a fake
`XDG_CACHE_HOME` where a cache could be touched. No run used the owner's
home, the main checkout, docker or a remote.

| Item | Follow-up | Measured on the unchanged tree |
|---|---|---|
| 1 | fu-prompt-diet-fixture-real-root-race | A sentinel file planted at `docs/issues/CHANGE-DRAFT-prompt-diet-e2e-dry-run.md` in the clone; `bash tests/skills/test-aai-prompt-diet.sh test_004_intake_dry_run` exits 0 and the sentinel is gone (overwritten, then removed). With a preload that unlinks a planted draft on its first read, `node .aai/scripts/docs-audit.mjs --check --no-event` exits 1 with `Error: ENOENT` thrown from `runAudit` (`lib/docs-audit-core.mjs:1198`). |
| 2 | fu-suite-fail-text-blocks-attribution | A scan of every `log_fail()`/`fail()` definition in `tests/skills/test-*.sh` and `tests/test-*.sh` (147 suites): four wrappers print `✗ $*` with no literal FAIL, in test-aai-intake.sh, test-aai-share.sh, test-aai-tdd.sh and test-aai-worktree.sh. `mutation-run.mjs` `classifyVerdict` needs a line matching `FAIL.*\bTEST-id\b`. Eight suites define neither name. |
| 3 | fu-docs-audit-suite-has-no-selector | Partly fixed since: PR #467 (2026-10-15) added a one-argument dispatch to `main`. It calls the function bare, so an arm that needs the fixture fails: `bash tests/skills/test-aai-docs-audit.sh test_drift_verdicts` exits 1 (`grep: /enforced.log: No such file`). With `check_deps; setup_fixture; write_config` first it still fails (it reads the `enforced.log` that `test_orphan_split` writes); with `test_orphan_split` added it passes in under 1 s. `test_reviewby_literals`, `test_type_validation` and `test_events_emission` fail bare and pass after the three setup steps alone. |
| 4 | fu-runtests-capture-is-unscored-noise | `aai_capture_friction` writes `"confidence":"low"` and no impact for every non-zero exit (`aai-run-tests.sh` tail), signal 1 under `aai-feedback-triage.mjs` `observationSignal`, below `SIGNAL_FLOOR = 2`, so no recurrence can promote it. The follow-up measured 819 of 824 spool records in that one shape. |
| 5 | fu-framework-discover-exit-swallowed | `bash tests/skills/test-framework.sh --skill aai-redact --skill aai-no-such-suite` prints `Test file not found`, then `Found 1 test(s)`, `Passed: 1 (100%)`, exit 0. |
| 6 | fu-lib-graph-narrowing-after-sharding | The sharding half is delivered: full mode by SPEC-0206 (4 shards), selected mode by SPEC-0240 (the `selected-plan` step, up to two legs). The narrowing half was prototyped and measured by SPEC-0206 (Scope decision): 7 of 13 shared-lib merges stay FULL_RUN anyway, the other 6 select 41 to 55 of 101 suites, and the soundness premise (every load of a lib names it in a tracked file) cannot be proven by a test. |
| 7 | fu-assertions-pinned-to-one-world | No check exists. A prototype scan of the three shapes over tests/skills, tests and tests/skills/lib (209 files), restricted to real-tree lines, finds one hit: `tests/skills/test-aai-git-ref-guard.sh:953` reads `origin/main:` (a base-vs-live comparison that holds in both worlds, so it needs a marker, not a fix). Fixture-repo reads are excluded by the real-tree rule. |
| 8 | fu-reuse-docs-closure-suites | Already resolved: `tests/skills/suite-reuse.json` declares aai-docs-content, aai-spec-lint and aai-hygiene-pack (SPEC-0268); the run-ledger append is tolerated (SPEC-0270); the hygiene pack is split into a fixture half and a corpus half (SPEC-0271). docs/analysis/precise-suite-evidence-reuse.md records a zero-delta rerun at 11 of 11 suites reused, 112 s to 1 s. |
| 9 | fu-tests-share-real-pwsh-cache | `HOME=<fake> XDG_CACHE_HOME=<fake-xdg> bash .aai/scripts/aai-run-tests.sh sh -c 'echo $XDG_CACHE_HOME'` prints the caller's fake path: the wrapper passes the caller's cache through. `test-framework.sh` `suite_execute` sets only `AAI_SUITE_REUSE=0`. pwsh on macOS and Linux keeps `StartupProfileData-NonInteractive` under `$XDG_CACHE_HOME/powershell`, falling back to `$HOME/.cache/powershell`. |

## Decisions

### D1: the shared runner gives every command a private XDG_CACHE_HOME (item 9)

`.aai/scripts/aai-run-tests.sh` always overrides `XDG_CACHE_HOME`. A
caller-provided value is NOT respected: the usual caller value is the
owner's real cache, and the owner's rule is that no suite run touches it.
There is no opt-out. The block sits after the run temp root block and
before the signal traps:

- When the wrapper owns a temp root (`AAI_TREE_OWN=1`), the cache is
  `"$AAI_TREE_ROOT/xdg-cache"`, made with `mkdir` and removed with the root
  by `aai_tree_finish`.
- Otherwise the wrapper makes `mktemp -d "${TMPDIR:-/tmp}/aai-xdg-cache.XXXXXX"`,
  sets `AAI_XDG_CACHE_OWN=1`, and `aai_xdg_cache_finish() {` removes it.
  The function removes only an absolute path whose basename starts with
  `aai-xdg-cache.`. It is called after `aai_reap_group` on the normal path
  and in the INT, TERM and HUP traps.
- When neither can be made, the value is `/nonexistent/aai-test-no-xdg-cache`
  (the same pattern as the container sockets), so pwsh can never reach a
  real cache. The exit-code contract does not change.
- The variable is set by exactly one line,
  `XDG_CACHE_HOME="$AAI_XDG_CACHE_DIR"`, followed by `export XDG_CACHE_HOME`.
  That text occurs once in the file.

`aai-run-tests.ps1` is not changed. On Windows it delegates to this script
under Git Bash or WSL, and native Windows pwsh keeps its cache under
`LOCALAPPDATA`, not `XDG_CACHE_HOME`. `mutation-run.mjs` `runSuite` spawns
this wrapper, so mutation runs inherit the fix with no change.
docs/TECHNOLOGY.md gains one sentence in the "Container daemon isolation
and test residue" paragraph naming the override.

### D2: the framework gives every suite its own private XDG_CACHE_HOME (item 9)

`tests/skills/test-framework.sh` `suite_execute` computes `sx_cache` per
suite: `"$iso_base/xdg-cache"` when the suite has a disposable checkout
(removed by `iso_destroy`), otherwise a `mktemp -d` under `${TMPDIR:-/tmp}`
that `suite_execute` removes after the suite, otherwise
`/nonexistent/aai-test-no-xdg-cache`. Both invocations (tee and non-tee)
read `XDG_CACHE_HOME="$sx_cache" AAI_SUITE_REUSE=0 bash "$iso_target"`.
Two suites in one wave never share a cache, which is the concurrent
corruption the follow-up observed. CI runs the framework without the
wrapper, so D2 is the half that covers CI.

### D3: a missing selected suite fails the run (item 5)

`main()` of `tests/skills/test-framework.sh` captures discovery in the
current shell instead of a process substitution:

```
  local discovered discover_rc=0
  discovered="$(discover_tests)" || discover_rc=$?
  if [[ $discover_rc -ne 0 ]]; then
    exit "$discover_rc"
  fi
```

and then reads `"$discovered"` line by line, skipping empty lines.
`discover_tests` keeps its message and exit 2. An empty `--skill ""` names
`test-.sh`, which does not exist, so it fails the same way (empty filter is
a hard failure). SPEC-0240 already validates the selected CI plan before
execution; D3 closes the standalone path.

### D4: the wrapper records friction only for a watchdog stall (item 4)

An ordinary non-zero exit of the wrapped command is the test's own verdict,
not friction, so it records nothing. That covers every deliberate TDD RED
run. The non-timeout capture block at the tail of `aai-run-tests.sh` is
removed. `aai_capture_friction` takes the confidence and the impact as its
third and fourth arguments and writes both into the JSON. The timeout path
calls `aai_capture_friction 124 stalled_progress medium low`, signal 3
(medium 2 plus low 1), at or above `SIGNAL_FLOOR`. One stall stays `retain`
under the default threshold of 4, and a second stall of the same command
reaches `review_candidate` (3 plus a recurrence bonus of 1). The final line
of the script stays `exit "$STATUS"`, which occurs once on its own line. The
off-switch, the existence gate and never-mask are unchanged. In
`tests/skills/test-aai-friction-capture-points.sh`, TEST-001, TEST-004,
TEST-005, TEST-655 and TEST-659 drive a timed-out command
(`AAI_TEST_TIMEOUT=2`, `sleep 30`) instead of a failing one, and TEST-001
asserts zero records for a failing command (D-AMEND).
`tests/skills/test-aai-suite-isolation.sh` TEST-305(e) still asserts zero
records and needs no change.

### D5: the prompt-diet dry run writes its draft only in a fixture root (item 1, suite half)

`tests/skills/test-aai-prompt-diet.sh` gains `E2E_FIXTURE_FILES`, the list
of repo-relative paths a `docs-audit.mjs --check --strict --path` run of one
draft reads (at least `.aai/scripts/docs-audit.mjs`, `.aai/scripts/lib/`,
`.aai/INTAKE_COMMON.md`, `docs/ai/docs-audit.yaml` and
`.aai/system/DOCS_AI_CANON.list`; the implementer measures the exact set),
and `e2e_fixture_root() {`. That function copies those paths from the
working tree into a `mktemp -d` root, registered with the suite's EXIT
cleanup. TEST-004 assigns
`e2e_root="$(e2e_fixture_root)"` (that text occurs once) and writes the
draft and runs docs-audit only with cwd inside `$e2e_root`. Nothing under
`$PROJECT_ROOT` is written or removed, and the old real-root `rm -f`
cleanup goes.

### D6: docs-audit degrades on a document that vanishes mid-walk (item 1, docs-audit half)

`lib/docs-audit-core.mjs` gains
`export function readScannedDoc(root, rel, vanished) {`. It returns the
file text, or `null` after pushing `rel` onto `vanished` when the read
throws ENOENT. Every other error is rethrown through the line
`    if (err?.code !== 'ENOENT') throw err;`, which occurs once. The three
corpus-walk read sites use it and skip a `null`: the `runAudit` loop, the
working-tree branch of `scanGateEntries`, and `runLintBody` in
`docs-audit.mjs`. `runAudit` returns `vanished`. `docs-audit.mjs` prints one
line per entry, `NOTE: vanished during the scan (not audited): <rel>`, on
stdout in report and `--check` modes and on stderr in the gate and
lint-body modes. A vanished document is not a finding: the exit code is the
one the same run gives when the file was never there (degrade-with-NOTE,
Constitution article 4).

### D7: a selected docs-audit arm replays its setup steps and declared producers (item 3)

`tests/skills/test-aai-docs-audit.sh` moves the no-argument run order into
the array `DA_MAIN_STEPS` (same names, same order). The no-argument `main`
iterates it. The selector branch keeps its existing
`if [[ $# -gt 0 ]]; then` line (SPEC-0231 TEST-012's mutation anchors on
it) and calls `da_run_selected "$1"`:

```
da_run_selected() {
  local fn="$1"
  declare -F "$fn" >/dev/null || { echo "FAIL: unknown test function: $fn" >&2; exit 2; }
  da_replay_setup "$fn"
  "$fn"
}
```

`da_replay_setup` runs, in `DA_MAIN_STEPS` order, every step positioned
before `fn` that is a setup step (`check_deps`, `write_config` or a
`setup_*` name), plus the producer arms `da_prereqs_of "$fn"` names. Producer
arms are declared in one `case` statement; the first entry is
`test_drift_verdicts) echo test_orphan_split ;;`. No other arm runs. A
function absent from `DA_MAIN_STEPS` (a helper-invoked case) is still called
bare, as today. The line `  da_replay_setup "$fn"` occurs once. The trade-off
is recorded: an arm-only replay was rejected because it runs the arm against
state a full run never gives it. A full-prefix replay was rejected because
it runs every earlier arm, which is exactly the confound the follow-up names.
Declared producers keep the confound down to the arms the selected arm
really reads. The implementer runs every `DA_MAIN_STEPS` arm singly once
(Verification) and declares a producer for each arm that fails singly.

### D8: suite fail wrappers print FAIL, and a corpus guard keeps it so (item 2)

The four wrappers become `log_fail() { echo "✗ FAIL: $*" >&2; return 1; }`
in test-aai-intake.sh, test-aai-share.sh, test-aai-tdd.sh and
test-aai-worktree.sh. `test_4138_fail_wrappers_print_fail` in
`tests/skills/test-aai-mutation-gate.sh` (next to the D3 dispatch guard of
SPEC-0315) scans every `tests/skills/test-*.sh` and `tests/test-*.sh` file
that defines `log_fail()` or `fail()`. It fails when the definition body
(up to its closing brace, at most 15 lines) has no literal `FAIL` before the
first message expansion (`$*`, `$@` or `$1`). A planted offending fixture is
the positive control, and a planted conforming one the negative control. A
seam arm evaluates each of the four fixed definitions with the argument
`TEST-9999 probe` and matches the output against the attribution form
`FAIL.*\bTEST-9999\b`, the regex `classifyVerdict` builds. A failure call
that names no TEST id stays unattributable. That is a property of the
caller's message, not of the wrapper, and is stated as residual.

### D9: a scan for assertions pinned to one world (item 7)

`tests/skills/test-aai-hygiene-pack.sh` gains `one_world_scan()` over the
given files, with three ERE variables, each assigned on one line:

- `OW_MOVING_REF_RE` (shape `moving-ref`): a blob or range read of
  `origin/main` (`origin/main:`, `origin/main..`, `..origin/main`) on a
  line that also names `PROJECT_ROOT`.
- `OW_LAST_INDEX_RE` (shape `last-index`): `tail -1`, `tail -n 1`,
  `tail -n1` or `.at(-1)` on a line naming a real-tree run ledger
  (`docs/ai/decisions.jsonl`, `EVENTS.jsonl` or `METRICS.jsonl`) either
  after `$PROJECT_ROOT/` or `${PROJECT_ROOT}/`, or bare (not after a `/`).
- `OW_UNRELEASED_RE` (shape `unreleased-only`): an escaped `\[unreleased\]`
  pattern on a line naming the real `CHANGELOG.md` (after `$PROJECT_ROOT/`,
  or bare after whitespace) that lacks the dual form `unreleased|`.

Comment lines are skipped. A line is exempt when it, or the line above,
carries `one-world-ok: <reason>`. Each hit prints
`ONE-WORLD <shape> <file>:<line>`. `test_4139_one_world_scan_bites` (the
fixture half) plants one file per shape plus four controls: the dual form, a
fixture-path ledger, a fixture-repo `origin/main`, and a marked line.
`test_4140_one_world_live_corpus_clean` is registered in
`HYGIENE_CORPUS_CASES`, so it runs in the corpus half. It scans
`tests/skills/*.sh`, `tests/*.sh`, `tests/skills/lib/*.sh` and
`tests/skills/lib/*.mjs`, and requires zero hits. The one live hit
(test-aai-git-ref-guard.sh:953) gets a marker naming why it holds in both
worlds, or a fix.

### D10: item 6 is dropped, by measurement (closed, not deferred)

The sharding half is delivered (SPEC-0206 full mode, SPEC-0240 selected
mode). The narrowing half is not built. SPEC-0206 measured that 7 of 13
shared-lib merges stay full anyway, and that the other 6 would select 41 to
55 of 101 suites. With selected mode now sharded, the narrowed run would
save little wall time (two legs of 41 to 55 suites, against four legs of the
full sweep) on at most 6 of 40 PRs. It would also narrow a fail-open guard
on a soundness premise that no test can prove complete: 16 suites copy
`.aai/scripts/lib/*.mjs` into fixtures, and libs are loaded by shapes other
than `import`. The workflow is not touched, so the ride stays ceremony 2.
The item is closed with that reason. If the CI cost changes, a new
follow-up can reopen the question with fresh numbers.

### D11: item 8 is closed as already resolved

No code change. The follow-up's finding no longer holds on main (see
Measurements, item 8). Its close note names SPEC-0268, SPEC-0270 and
SPEC-0271 and the measured 11 of 11 reuse. The remaining miss (aai-docs-content
and aai-spec-lint read the git index, so any tracked edit misses) is the
correct outcome for whole-corpus suites, not a defect.

### D-AMEND: CHANGE-0099, SPEC-0185, SPEC-0231

After the edits are checked with grep or diff, this scope appends one
additive section to each document, with the exact heading
`## Amendment 2026-11-25 (test-infra-p2-fixes)`. Each section leaves the
original text visible, quotes it beside the new rule, and names the edited
tests:

- CHANGE-0099 AC-001 (a failing non-timeout command records one
  observation) is withdrawn by D4. TEST-001 now asserts zero records.
- SPEC-0185 TEST-655 and TEST-659 drive a timed-out command instead of a
  failing one. Their asserted properties do not change.
- SPEC-0231's implementation prose ("one argument runs only that function")
  becomes "one argument runs that function after its setup steps and
  declared producers" (D7). Spec-AC-08 and TEST-012 still hold as written.

Each section states that canon assigns this scope change to HITL, that no
prior sign-off was obtained, and that the owner may reverse it. Then it
records
`spec-amend.mjs add --spec <path> --ref test-infra-p2-fixes --class contract --signoff none --what "<...>" --why "<...>"`.
If `spec-amend.mjs` refuses the CHANGE-0099 path because it is not a spec,
the refusal text is recorded in the TDD evidence and the additive section
alone discloses it. `spec-amend.mjs list --strict` must exit 0 afterwards.

### D-WIRE

- New tests live in existing suites: no new suite, no suite-map or
  suite-weights row, no new `.aai/**` file (no PROFILES.yaml entry), and no
  prompt-corpus bytes (no diet-ledger entry).
- CHANGELOG.md gets one heading,
  `## [unreleased] — Test infrastructure: the nine P2 follow-ups`. It names
  the consumer-visible changes: the private `XDG_CACHE_HOME` per run and per
  suite, a missing `--skill` failing the run, friction recorded only for a
  watchdog stall, docs-audit degrading on a vanished document, the
  docs-audit single-arm selector, and the one-world scan. A release rolls
  `[unreleased]` to `[vYYYY.MM.DD]`, and the TEST-4141 check accepts either
  form.
- If the hygiene pack's fixture-half admission trace (TEST-3193) changes
  after D9, the manifest note in `tests/skills/suite-reuse.json` is updated
  to the measured read count. No identity rule changes.

## Constraints

- Tests never touch real docker, a real remote, the main checkout or the
  owner's home files. Every cache-related test sets a fake `HOME` and a fake
  `XDG_CACHE_HOME` under its own `mktemp -d` root. No test reads, modifies
  or deletes the owner's real `~/.cache/powershell`.
- Every fixture, scratch copy and private cache a test creates is
  registered for cleanup and removed on exit. An empty or relative fixture
  path is a hard failure before any `cd` (HAZ-CD).
- An empty filter is a hard failure: an empty `--skill`, an empty selector
  or an empty scan file list exits non-zero, never a vacuous pass.
- Every suite run for this ride (RED, GREEN, validation) uses
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh ...` from the repo
  root, which after D1 also gives it a fresh `XDG_CACHE_HOME`.
- No pipe characters inside AC or Test Plan table cells; run
  `node .aai/scripts/spec-lint.mjs --path <this spec>` after each table
  edit.
- New follow-up ids are at most 40 characters and never start with
  `fu-close-`, `fu-index-` or `fu-stamp-`.
- No `git stash`, `git reset --hard` or `git restore` on
  `docs/ai/EVENTS.jsonl`. Probes are bounded with `timeout`.

## Acceptance Criteria Mapping

- AC-001 (each item fixed RED-to-GREEN or dropped with a reason) maps to
  Spec-AC-01 to Spec-AC-10 for items 1, 2, 3, 4, 5, 7 and 9, and to D10 and
  D11 for items 6 and 8 (dropped and already resolved, closed with the
  reason in the ledger).
- AC-002 (each follow-up closed with resolved-by this ride) maps to
  Spec-AC-11.
- AC-003 (a fake HOME and XDG prove the runner never touches the real pwsh
  cache) maps to Spec-AC-01 and Spec-AC-02.
- AC-004 (every touched suite passes) is the Verification section.

## Constitution deviations

None. D1 and D4 change behaviour at a public boundary (a caller's
`XDG_CACHE_HOME` is no longer passed to the wrapped command, and ordinary
failures are no longer spooled). Both changes are explicit and documented in
the CHANGELOG, TECHNOLOGY.md and the D-AMEND sections, as article 5 requires.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN aai-run-tests.sh runs a command with a fake HOME and a fake XDG_CACHE_HOME (and again with XDG_CACHE_HOME unset) THEN the command SHALL see an XDG_CACHE_HOME that is neither the fake XDG path nor under the fake HOME, that directory SHALL not exist after the wrapper exits, and neither the fake XDG path nor the fake HOME SHALL contain a powershell entry; where pwsh is installed a real pwsh start through the wrapper SHALL leave no powershell cache entry (StartupProfileData under XDG_CACHE_HOME/powershell or HOME/.cache/powershell) in either fake (the data folder pwsh creates under HOME/.local/share/powershell is not the cache and is outside this clause), and where it is not the test SHALL print a NOTE naming the skipped arm. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4130.log | — | D1, item 9 |
| Spec-AC-02 | WHEN test-framework.sh runs two fixture suites with a fake HOME and a fake XDG_CACHE_HOME, both with isolation on and with AAI_TEST_ISOLATION=0 THEN each suite SHALL see its own XDG_CACHE_HOME, the two SHALL differ, neither SHALL equal the fake XDG path or lie under the fake HOME, neither SHALL exist after the run, and the fake XDG path SHALL hold no powershell entry. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4131.log | — | D2, item 9 |
| Spec-AC-03 | WHEN test-framework.sh is given --skill for an existing suite and --skill for a missing one THEN it SHALL exit 2 with Test file not found and SHALL print no Found line and run no suite; an empty --skill value SHALL exit 2 the same way. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4132.log | — | D3, item 5 |
| Spec-AC-04 | WHEN a command run through aai-run-tests.sh exits 7 or 127 with friction capture on and a fixture spool THEN the spool SHALL hold zero observations and the wrapper SHALL exit 7 or 127. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4133.log | — | D4, item 4 |
| Spec-AC-05 | WHEN a command run through aai-run-tests.sh is killed by the watchdog THEN the spool SHALL gain exactly one stalled_progress observation with confidence medium and impact low; aai-feedback-triage.mjs over one such observation SHALL report the cluster retain, and over two of the same command SHALL report it review_candidate. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4134.log | — | D4, item 4 |
| Spec-AC-06 | WHEN the prompt-diet TEST-004 arm runs in a scratch project whose real-root draft path holds a sentinel file THEN the arm SHALL pass and the sentinel SHALL be byte-identical afterwards, with no other file under the scratch project root created, changed or removed. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4135.log | — | D5, item 1 |
| Spec-AC-07 | WHEN a scanned document disappears between the docs-audit scan and its read THEN docs-audit.mjs --check --no-event SHALL exit with the same code as the same run without that file, SHALL print NOTE vanished during the scan naming the file, and SHALL print no ENOENT error. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4136.log | — | D6, item 1 |
| Spec-AC-08 | WHEN test-aai-docs-audit.sh is run with one argument THEN test_drift_verdicts and test_reviewby_literals SHALL each exit 0 with their pass text, the drift run SHALL not print the pass text of test_report_only_without_config or the full-suite banner, and an undefined function name SHALL exit 2 with unknown test function. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4137.log | — | D7, item 3 |
| Spec-AC-09 | The fail-wrapper guard SHALL report zero offending suites over tests/skills and tests, SHALL name a planted wrapper without FAIL, and SHALL not name a conforming one; each of the four fixed wrappers called with TEST-9999 probe SHALL print a line matching the mutation-run attribution form. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4138.log | — | D8, item 2 |
| Spec-AC-10 | one_world_scan SHALL print one ONE-WORLD line with the right shape for each planted moving-ref, last-index and unreleased-only file and none for the four controls; over the live test corpus it SHALL print zero lines. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4140.log | — | D9, item 7 |
| Spec-AC-11 | CHANGELOG.md SHALL hold the D-WIRE heading in its unreleased or rolled form, docs/TECHNOLOGY.md SHALL name the XDG_CACHE_HOME override, CHANGE-0099, SPEC-0185 and SPEC-0231 SHALL each hold the D-AMEND heading, spec-amend.mjs list --strict SHALL exit 0, and follow-ups.mjs list --status open --json SHALL list none of the nine ids, each closed with resolved_by test-infra-p2-fixes. | implementing | docs/ai/tdd/test-infra-p2-fixes/green/TEST-4141.log | — | D-AMEND, D-WIRE, D10, D11 |

## Implementation plan

Order. Each step is RED first, with the RED log under
`docs/ai/tdd/test-infra-p2-fixes/red/TEST-xxxx.log` and the GREEN log under
`.../green/`. Mutation records go under
`docs/ai/tdd/spec-test-infra-p2-fixes/`.

1. D1, then D2 (TEST-4130, TEST-4131). These come first, so every later
   suite run of this ride already gets a private cache.
2. D3 (TEST-4132).
3. D4 (TEST-4133, TEST-4134). Then re-point TEST-001, TEST-004, TEST-005,
   TEST-655 and TEST-659 at the timeout path.
4. D6, then D5 (TEST-4136, TEST-4135).
5. D7 (TEST-4137), then the single-arm sweep (Verification) and its
   producer entries.
6. D8 (TEST-4138), then D9 (TEST-4139, TEST-4140) and the live-hit marker.
7. D-AMEND, D-WIRE (CHANGELOG, TECHNOLOGY.md), then the nine ledger closes:
   `node .aai/scripts/follow-ups.mjs close --id <id> --resolved-by test-infra-p2-fixes --source docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md`.
   Items 6 and 8 carry the D10 and D11 reasons in their close note. The
   allocator renames the spec at merge; run `spec-amend.mjs list --strict`
   and the mutation gate after any allocator step. TEST-4141 last.

Seams this scope crosses (each test produces on one side and asserts the
real result on the other):

- Runner to wrapped process to pwsh: TEST-4130 runs the real wrapper and,
  where pwsh is installed, a real pwsh start, against fake HOME and XDG.
- Framework to suite environment: TEST-4131 runs a byte copy of the real
  framework (`build_framework_repo`) with real fixture suites in parallel.
- Framework discovery to the CI selected plan: SPEC-0240's plan check
  already refuses a missing suite before execution. TEST-4132 covers the
  standalone path that check does not reach.
- Wrapper capture to the triage scorer: TEST-4134 feeds the spool the real
  wrapper wrote into the real `aai-feedback-triage.mjs`.
- docs-audit corpus walk to a concurrent writer: TEST-4136 runs the real
  CLI with a preload that unlinks a planted document on its first read,
  the deterministic form of the observed race.
- Prompt-diet suite to the docs-audit CLI: TEST-4135 runs the real suite
  copy and the real CLI in a scratch project.
- Suite selector to `mutation-run.mjs`: `extractSelectors` reads function
  definitions, which D7 keeps. The mutation records of TEST-4137 and the
  replay of SPEC-0231's TEST-012 record exercise the real CLI.
- Fail wrapper to `classifyVerdict`: TEST-4138's seam arm uses the
  attribution regex form on the real wrapper output.
- The one-world scan to the hygiene corpus split: TEST-4140 is registered
  in `HYGIENE_CORPUS_CASES`, and the existing registration check
  (hygiene-pack `test_093_test_registration`) must stay green.

Edge cases: an empty `--skill` (D3, exit 2). `AAI_TEST_TMPDIR=keep` (the
cache stays private). A nested wrapper with an inherited `AAI_TEST_OWNER`
(no own root, so it uses its own mktemp under the outer root). A
`mktemp` failure (the `/nonexistent` value, exit contract unchanged). A
docs-audit `EACCES` (still thrown, not degraded). A selected docs-audit
helper that is not in `DA_MAIN_STEPS` (called bare, as today). A scan
target list that is empty (TEST-4140 fails on zero files scanned).

## Test Plan

TEST ids 4130 to 4141. Measured free range: the highest id on origin/main
is TEST-4122. The in-flight sibling ride secrets-gate-false-positives
holds ids up to TEST-4112.

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-4130 | Spec-AC-01 | integration | tests/skills/test-aai-run-tests.sh | test_4130_private_xdg_cache: fake HOME and fake XDG under one mktemp root; the wrapped sh records its XDG_CACHE_HOME to a file and writes powershell/StartupProfileData-NonInteractive under it; asserts the Spec-AC-01 properties with XDG set and unset; a real pwsh arm runs only when pwsh is on PATH, else prints a NOTE | `sed:s/XDG_CACHE_HOME="\$AAI_XDG_CACHE_DIR"/XDG_CACHE_HOME="${XDG_CACHE_HOME:-}"/` on .aai/scripts/aai-run-tests.sh | green |
| TEST-4131 | Spec-AC-02 | integration | tests/skills/test-aai-suite-isolation.sh | test_4131_every_suite_gets_a_private_xdg_cache: build_framework_repo fixture with two suites that record XDG_CACHE_HOME and write a powershell entry; run with AAI_TEST_PARALLEL=2, fake HOME and fake XDG, isolation on and off; asserts the Spec-AC-02 properties | `sed:s/XDG_CACHE_HOME="\$sx_cache" //g` on tests/skills/test-framework.sh | green |
| TEST-4132 | Spec-AC-03 | integration | tests/skills/test-aai-suite-isolation.sh | test_4132_missing_selected_suite_fails_the_run: fixture framework with one suite; --skill for it plus a missing name exits 2 with Test file not found and no Found line; an empty --skill exits 2 | `sed:s/    exit "\$discover_rc"/    :/` on tests/skills/test-framework.sh | green |
| TEST-4133 | Spec-AC-04 | integration | tests/skills/test-aai-friction-capture-points.sh | test_4133_ordinary_failure_records_nothing: capture on, fixture spool; sh -c exit 7 and a missing command (127) each leave zero observations and keep their exit code | `sed:s/^exit "\$STATUS"$/aai_capture_friction "$AAI_CMD_REAL_STATUS" deterministic_script_failure low low; exit "$STATUS"/m` on .aai/scripts/aai-run-tests.sh | green |
| TEST-4134 | Spec-AC-05 | integration | tests/skills/test-aai-friction-capture-points.sh | test_4134_stall_record_carries_signal: AAI_TEST_TIMEOUT=2 with sleep 30 twice into one fixture spool; one stalled_progress line per stall with confidence medium and impact low; the real triage CLI over the spool after one stall reports retain and after two reports review_candidate | `sed:s/aai_capture_friction 124 stalled_progress medium low/aai_capture_friction 124 stalled_progress low low/` on .aai/scripts/aai-run-tests.sh | green |
| TEST-4135 | Spec-AC-06 | integration | tests/skills/test-aai-prompt-diet.sh | test_4135_dry_run_never_writes_project_root: scratch project holding a copy of the suite, its sourced libs and E2E_FIXTURE_FILES; a sentinel at the draft path; the copied suite's test_004_intake_dry_run, run with a TMPDIR inside the scratch project, exits 0, the sentinel is byte-identical, that TMPDIR is empty afterwards (the suite's fixture root was removed by its EXIT cleanup) and the scratch tree listing is unchanged | `sed:s/^  e2e_root="\$E2E_ROOT"$/  e2e_root="$E2E_ROOT"; E2E_FIXTURE_ROOTS=()/m` on tests/skills/test-aai-prompt-diet.sh | green |
| TEST-4136 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | test_4136_vanished_doc_degrades: fixture repo; baseline run without the draft gives the expected exit; with a planted draft and a node preload that unlinks it on its first read, the same command exits the same, prints the NOTE line naming it and no ENOENT | `sed:s/if \(err\?\.code !== 'ENOENT'\) throw err;/throw err;/` on .aai/scripts/lib/docs-audit-core.mjs | green |
| TEST-4137 | Spec-AC-08 | integration | tests/skills/test-aai-docs-audit.sh | test_4137_selected_arm_replays_its_setup: nested runs of this suite with test_drift_verdicts, test_reviewby_literals and an undefined name; asserts the Spec-AC-08 exit codes, pass texts and absent texts | `sed:s/^  da_replay_setup "\$fn"$/  :/m` on tests/skills/test-aai-docs-audit.sh | green |
| TEST-4138 | Spec-AC-09 | inspection | tests/skills/test-aai-mutation-gate.sh | test_4138_fail_wrappers_print_fail: the D8 corpus guard over tests/skills and tests reports zero offenders; a planted wrapper without FAIL is named and a conforming one is not; each fixed wrapper called with TEST-9999 probe matches the attribution form | `sed:s/echo "✗ FAIL: /echo "✗ /` on tests/skills/test-aai-tdd.sh | green |
| TEST-4139 | Spec-AC-10 | integration | tests/skills/test-aai-hygiene-pack.sh | test_4139_one_world_scan_bites: one planted file per shape is named with its shape; the dual-form, fixture-path, fixture-repo and marked controls are not named | `sed:s/^OW_LAST_INDEX_RE=.*$/OW_LAST_INDEX_RE='NO_SUCH_TEXT_4139'/m` on tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-4140 | Spec-AC-10 | inspection | tests/skills/test-aai-hygiene-pack.sh | test_4140_one_world_live_corpus_clean: corpus-half case; one_world_scan over the four live globs prints zero lines and scanned at least 100 files | `sed:s/^OW_MOVING_REF_RE=.*$/OW_MOVING_REF_RE='origin'/m` on tests/skills/test-aai-hygiene-pack.sh | green |
| TEST-4141 | Spec-AC-11 | inspection | tests/skills/test-aai-run-tests.sh | test_4141_changelog_amendments_and_ledger: the D-WIRE heading in dual form, the TECHNOLOGY.md sentence, the three D-AMEND headings, and follow-ups.mjs list --status open --json naming none of the nine ids | `sed:s/— Test infrastructure: the nine P2 follow-ups/— Test infrastructure/` on CHANGELOG.md | green |

Every new test is added to its suite's run list (`main()`,
`DA_MAIN_STEPS` or `HYGIENE_CORPUS_CASES`) and resolves when called with
its own full `test_*` name.

## Verification

- Each touched suite runs whole through the canonical runner, with
  `env -u AAI_ROLE`, and exits 0: aai-run-tests, aai-suite-isolation,
  aai-friction-capture-points, aai-prompt-diet, aai-docs-audit,
  aai-mutation-gate, aai-hygiene-pack, aai-hygiene-corpus, aai-intake,
  aai-share, aai-tdd, aai-worktree, aai-git-ref-guard, aai-feedback-triage,
  aai-suite-reuse, aai-test-residue, aai-repo-tripwire and aai-sweep-parallel.
  The last four cover the wrapper and framework seams. Example:
  `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-run-tests.sh`.
- Single-arm sweep (D7), once, in a scratch clone: every `DA_MAIN_STEPS`
  arm run as `bash tests/skills/test-aai-docs-audit.sh <arm>`. The count of
  arms that exit non-zero is recorded in
  `docs/ai/tdd/test-infra-p2-fixes/single-arm-sweep.txt`. Each one either
  gets a `da_prereqs_of` producer entry and passes on a rerun, or is listed
  there with its reason.
- One full sweep before the close, with `AAI_TEST_TIMEOUT=3600`.
- `node .aai/scripts/spec-amend.mjs list --strict` exits 0.
- `node .aai/scripts/follow-ups.mjs list --status open --json` lists none
  of the nine ids.
- `node .aai/scripts/mutation-run.mjs` writes one RED record per Test Plan
  row (`--check` first), and `node .aai/scripts/mutation-gate.mjs --spec
  <this spec> --require-evidence` prints GATE PASS.
- Hosted: the skill-suite run on the pull request head (full mode, because
  `lib/docs-audit-core.mjs` is a shared lib).
- PASS criteria: every TEST-xxx green, every Spec-AC in a terminal status.

## Evidence contract

- ref_id `test-infra-p2-fixes`. RED and GREEN logs go under
  `docs/ai/tdd/test-infra-p2-fixes/{red,green}/TEST-xxxx.log`, and
  mutation records go under `docs/ai/tdd/spec-test-infra-p2-fixes/`.
- The validation report is
  `docs/ai/reports/VALIDATION-<ts>-test-infra-p2-fixes.md`, and the review
  report is `docs/ai/reviews/review-test-infra-p2-fixes-<ts>.md`.

### Evidence by strategy

tdd: a stored RED artifact for each AC-gating test plus the verification
above.

## Registry items closed by this scope

| Follow-up | Decision | Spec-AC |
|---|---|---|
| fu-prompt-diet-fixture-real-root-race | fix (D5 suite half, D6 docs-audit half) | Spec-AC-06, Spec-AC-07 |
| fu-suite-fail-text-blocks-attribution | fix (D8: four wrappers and a corpus guard) | Spec-AC-09 |
| fu-docs-audit-suite-has-no-selector | fix (D7; the bare one-argument dispatch of PR #467 was already on main, and it could not run a fixture-dependent arm) | Spec-AC-08 |
| fu-runtests-capture-is-unscored-noise | fix (D4) | Spec-AC-04, Spec-AC-05 |
| fu-framework-discover-exit-swallowed | fix (D3) | Spec-AC-03 |
| fu-assertions-pinned-to-one-world | fix (D9) | Spec-AC-10 |
| fu-reuse-docs-closure-suites | closed as already resolved (D11; SPEC-0268, SPEC-0270, SPEC-0271) | Spec-AC-11 |
| fu-tests-share-real-pwsh-cache | fix (D1, D2) | Spec-AC-01, Spec-AC-02 |

DROPPED by measurement (the registry status is dropped, not done):

- `fu-lib-graph-narrowing-after-sharding` (Spec-AC-11): D10; the sharding
  half was delivered by SPEC-0206 and SPEC-0240.

Open items on the same subjects that this scope touches but does not close,
with the reason for each (registry consumer rule):

- NOT CLOSED: `fu-runtests-ps1-captures-no-friction` (P3): the ps1 twin
  delegates to this wrapper on Windows; D4 changes what is recorded, not
  where capture runs.
- NOT CLOSED: `fu-precommit-pwsh-crash-reads-as-parse` (P3): D1 and D2
  remove the test-suite cause of the corrupted cache. A pwsh crash in the
  pre-commit path from another cause is still reported as a parse error.
- NOT CLOSED: `fu-mutation-replay-skip-reads-green` (P3): replay
  classification, unchanged here.
- NOT CLOSED: `fu-prompt-diet-live-size-time-bomb` (P3): a live-size
  comparison is a one-world shape D9 does not cover (it needs the
  comparison's semantics, not a line shape).
- NOT CLOSED: `fu-test655-promote-spelling-pin` (P3): TEST-655 is
  re-pointed at the timeout path (D4); its literal spelling pin is
  unchanged.
- NOT CLOSED: `fu-ps1-quality-outside-sweep-glob` (P3): it concerns
  `discover_tests`'s full-run glob, which D3 leaves as is.
- NOT CLOSED: the P3 reuse items (`fu-reuse-record-max-age`,
  `fu-reuse-distro-exported-functions`, `fu-reuse-overlaps-mutation`,
  `fu-reuse-arm-dir-nonexist-case`): reuse internals, untouched.

## Residual risks

- A suite run bare (`bash tests/skills/test-x.sh`, without the wrapper or
  the framework) still inherits the caller's `XDG_CACHE_HOME`. Canon
  requires the wrapper (`.aai/AGENTS.md`, canonical test invocation), and
  the framework covers CI.
- D1 drops a caller's `XDG_CACHE_HOME` with no opt-out. A wrapped build
  that relied on a warm cache under that path runs cold. That is the
  owner's rule, recorded in the CHANGELOG.
- D4 no longer spools an ordinary failure, so a deterministic AAI script
  failure that is not a stall reaches the friction channel only through the
  other capture points (close ceremony, prose hooks). That trade was
  measured: 819 of 824 such records could never be candidates.
- D7's producer list is hand-declared. A new fixture-dependent arm that
  reads another arm's output is selectable only after it is declared. Until
  then its singly selected run fails as it does today, so no false pass
  results.
- D8's guard sees only wrappers named `log_fail` or `fail`. The eight suites
  without either are outside it, and a failure call that names no TEST id
  stays unattributable.
- D9 is a line-shape scan. A one-world assertion split across lines, or
  bound through a variable set elsewhere, is not seen.
- D10 leaves 6 of 40 PRs on a full run that narrowing could have shortened.
- Ceremony level 2: no file in `protected_paths_l3` and no workflow file is
  touched.

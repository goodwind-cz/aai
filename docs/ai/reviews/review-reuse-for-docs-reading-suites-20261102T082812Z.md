# Code Review: reuse-for-docs-reading-suites

```yaml
ref: reuse-for-docs-reading-suites
spec: docs/specs/SPEC-0268-spec-reuse-for-docs-reading-suites.md
intake: docs/issues/CHANGE-0242-reuse-for-docs-reading-suites.md
scope: origin/main...HEAD (head 09127f31, branch feat/reuse-for-docs-reading-suites)
base_ref: main
reviewer: claude-opus-5-5 (dispatched, read-only; STATE command returned, not run)
spec_compliance: pass
code_quality: pass
blocking: 0
non_blocking: 5
```

security_relevant: false

## Preflight

- Worktree mode (`worktree.user_decision: worktree`). Scope `git diff origin/main...HEAD`: 17 files, +1975/-741.
- `git status --porcelain` shows only the pre-existing ` M docs/ai/EVENTS.jsonl`, which is outside the scope.
- Coaching check: the dispatch named the primary risks (false hit, atime reset on the real tree) and pointed at the validator's open notes. It did not pre-rate severity or exclude any area. The whole scope was reviewed.
- Close-out files (`docs/product/precise-suite-evidence-reuse.md`, `CHANGELOG.md`) are not in this diff. The spec runs them after LOOP COMPLETE and asks for a second `set-code-review` over them.

## Verdict 1: spec_compliance = pass

AC table walk:

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `checkout-trace.mjs:60-82` (arm: hash before reset, children before parent, canary), `:86-119` (collect: atime > floor, inode change, gone). TEST-3260 (fixture: cat, grep, source, readFileSync, sed -i, rm, plus created and unread files), TEST-3261 (rename, ls, rev-parse vs status). |
| Spec-AC-02 | compliant | `suite-reuse.mjs:36` IDENTITY_COMPONENTS is the D3 literal. `:159-174` identity: traced inputs, path list, the index rule at :164, history only when git_read at :169, env names. `:177-200` miss diff. TEST-3262 to TEST-3267. computeClosure, HISTORY_RE, MARKER_RE and MINIMAL_TREE_FRAMEWORK are all gone. |
| Spec-AC-03 | compliant | `suite-reuse.mjs:292-299` gives no-trace, trace-unavailable and inputs-changed-during-run, all decided before the store write. TEST-3268, TEST-3269. TEST-3270 (bash atime restore gives ADMIT-FAIL from the poisoned run) and TEST-3271 (node utimes restore gives trace-misses-node-read). |
| Spec-AC-04 | compliant | No ledger is excluded by name. A ledger is an input only when the trace saw it read. TEST-3272 includes the built-path EVENTS read, the false hit the baseline had. |
| Spec-AC-05 | compliant | `suite-reuse.mjs:383-455`, CLI at `:513-522`. TEST-3273, TEST-3274 (ADMIT-NONE, single changed entry, ADMIT-OFF ci). |
| Spec-AC-06 | compliant | `tests/skills/suite-reuse.json` has 11 entries, each `live:false` with a note. The suite-map row gains the six suite files. TEST-3275, TEST-3276. `docs/ai/tdd/reuse-for-docs-reading-suites/admit-live-3.txt` has 11 ADMIT-PASS lines. I did not re-run the live admission (cannot_verify C1). |
| Spec-AC-07 | compliant | `test-framework.sh:1052-1080`. Arm and collect wrap `suite_execute` in `run_test` (:1670/:1674) and in `suite_child` (:1732/:1736), and collect runs before the checkout is destroyed. Both are `|| true`. TEST-3277 (serial, parallel, undeclared, opt-out, failing arm). |
| Spec-AC-08 | compliant | `SKILL_VERIFY.prompt.md:20` now says "files read". The glob is byte-equal to the baseline, so "not larger" holds. TEST-3278. See deviation D-4. |
| Spec-AC-09 | compliant | The analysis note has the `## Measurements (trace identity)` section: 12 samples, medians and worst, per-suite outcomes, read counts, arm plus collect ms, a 40-char sha and versions. TEST-3279. |

TEST-xxx rows: every TEST-3260 to TEST-3279 id is present in `tests/skills/test-aai-suite-reuse.sh` and/or `tests/skills/lib/suite-reuse.test.mjs`. I ran `env -u AAI_ROLE node --test tests/skills/lib/suite-reuse.test.mjs` here: 26/26 pass. The bash suite passed in validation r3 at this same head. I did not re-run it.

Deviations from the frozen spec. Every one is listed, including reasonable ones:

- D-1 (D3, disclosed): the input hash includes the executable bit. This is a contract-class amendment, unsigned, tracked by `fu-amend-reuse-for-docs-reading-suites`. It only adds misses.
- D-2 (D5 step 5, undisclosed): the poisoned run executes `bash tests/skills/test-<suite>.sh` directly in the scratch repo (`suite-reuse.mjs:427-429`) and accepts on `r.status === 0`. D5 says "the framework runs the suite fresh" and requires `Passed: 1 (100%)` with no failed or skipped line. On strength it is equivalent. A suite-level skip exits 42 (`test-framework.sh:1445`), which fails the rc check. The framework's Skipped and Passed lines count suites by exit code, so a case that skips itself and exits 0 passes either way. The validator's r1 N2 phrasing ("a suite that self-skips with exit 0 passes") is true of both forms equally. Running through the framework would also fail by construction, because unread harness files are poisoned. Still, the spec text is now false. See NB-1.
- D-3 (D5, undisclosed): before the probes, the admission puts back the scratch repo's `docs/ai/tests/test-runs.jsonl` (`:393-397`). Without this, all five index-reading suites would fail the unread probe. It cannot create a false hit, because it only changes the scratch repo before `check` runs. It does mean their "unread gives REUSE" probe proves a state that real use never reaches, since the framework appends to the ledger after every run (the analysis note says so). See NB-1.
- D-4 (D9, undisclosed): "read that log" was also changed to "read the whole log" (+5 B). D9's claim that "the prompt glob shrinks by 5 B" is now false: it is byte-equal. This is a canon wording change outside D9. See NB-2.
- D-5 (D5 step 4, minor): both probes skip every harness file, not only the suite file. The read probe excludes harness files from its candidates, and the unread probe excludes harness files and inputs. This is sound: harness bytes are compared from the working tree either way.
- D-6 (D4, additive): the env names at record are the union of the trace's names and the names in the working-tree texts (`:300-301`). The trace file also carries `tree_hashes` when the index was read. Both only add misses.
- D-7 (D2, trivial): inodes are recorded for non-directory entries only. Directories are never inputs.

## Verdict 2: code_quality = pass

### False-hit analysis (primary risk)

I walked the check, run, record and check cycle for a stale pass and found no path to a false hit outside the D3 caveat and the validator's measured classes:

- Content is keyed on the bytes the checkout held at arm. An edit to the working tree before `iso_create` is what the suite ran on, so it hits. An edit after `iso_create` gives a miss on the next check. Both are correct.
- Harness, env, runtime, policy and history are compared between check and record through `stableOf` (`:154-156`, `:299`). A move in the window between check and record gives inputs-changed-during-run.
- A reset failure leaves the atime above the floor, so the entry counts as read (over-inclusion). An arm or collect failure leaves no arm file or no trace file, so nothing is recorded. A false canary means nothing is recorded.
- A record from before the access trace (policy 2 / schema 2) misses with `policy` (`:257`).
- Directory enumeration is covered by `paths`. Reading the git index brings in every path-list file. Git object reads bring in HEAD and every ref.

### Atime reset scope (second risk)

In the framework the reset runs only for a disposable checkout. `reuse_trace_arm` requires a non-empty iso base and a root other than `$PROJECT_ROOT` (`test-framework.sh:1066`). Every degraded path sets `iso_base=""` and `iso_root=$PROJECT_ROOT` (`:1133-1252`). The checkout path is a fresh `mktemp -d` resolved with `pwd -P`. The helper refuses `--dir == root` (`suite-reuse.mjs:492`). The canary file goes into the checkout's parent, the mktemp base. In admission, the framework's root is the scratch clone. The real worktree cannot be reached through the framework. The helper's own guard is narrower than the property it protects (NB-4).

### BLOCKING

None.

### NON-BLOCKING (each with a recommended disposition; the orchestrator records it)

- **NB-1 (P3): undisclosed D5 deviations D-2 and D-3.** `suite-reuse.mjs:427-429` (direct run, rc only) and `:393-397` (ledger put back). Scenario: a later reader of D5 trusts that the poisoned run went through the framework and was gated on `Passed: 1 (100%)`, or that the five index-reading suites were shown to REUSE after a real framework run. Neither is true. No false hit results, but the frozen spec is a false record. Disposition: (a) amend D5 additively with disclosure (step 5: direct run; rc 0 matches the framework's suite verdict; harness files are poisoned, so the framework cannot run there; ledger put back before the probes). Ride it on the existing amendment record or `fu-amend-reuse-for-docs-reading-suites`. This changes admission behavior text, so per the kanon it is the owner's to sign.
- **NB-2 (P3): extra canon wording in SKILL_VERIFY outside D9.** `.aai/SKILL_VERIFY.prompt.md:22` ("read the whole log"). Scenario: a role reading the canon gets a stronger duty that no spec decided, and D9's "shrinks by 5 B" sentence is false. Disposition: (a) remediate in tree. Revert to "read that log", which matches D9 at -5 B. TEST-3278's "not larger" still holds, and D9 says no TEST-012 move is owed. Alternatively, keep it and disclose it in the D9 amendment.
- **NB-3 (P3): the analysis note states a guarantee, not what is compared.** `docs/analysis/precise-suite-evidence-reuse.md`, last paragraph: "The admission gate's poisoned run catches the clone case today". Scenario: a suite copies a file with `cp -c`, and its assertion does not depend on that file's content (only on its presence or size). Poisoning leaves size and presence meaningful, so the suite still passes and the read is never caught. The sentence also holds only at admission time. Disposition: (a) remediate in tree. State what the poisoned run does: it overwrites every path-list file the trace did not see read and requires the suite to still exit 0. Keep the single general caveat.
- **NB-4 (P3): the helper `arm` guard compares only `dir === root`.** `suite-reuse.mjs:492`. Scenario: `node .aai/scripts/suite-reuse.mjs arm --dir .. --run-dir /tmp/x --suite s` run from inside the repository. The dir is the repository's parent, so it passes the guard. `armTrace` then resets the atime of every file in the real worktree and its `.git` to 2000-01-01. It also truncates every mtime to millisecond precision (`lutimesSync(abs, ATIME_FLOOR, st.mtime)` passes a Date), which leaves the real index stat-dirty. This is not reachable through the framework. Disposition: (b) follow-up `fu-reuse-arm-dir-containment` (P3): refuse when root is inside dir or dir is inside root (`path.relative` test), with one TEST.
- **NB-5 (P3, close-out wording): the D3 sentence overclaims for `.git/` files.** D3's sentence for the product doc says "the bytes and executable bit of every file of the suite's disposable checkout that the operating system recorded as read". For files under `.git/`, only HEAD and every ref are compared (`checkout-trace.mjs:103`, `suite-reuse.mjs:162`). Scenario: `iso_create` copies the repo-local `user.name`/`user.email` into the checkout's `.git/config` (`test-framework.sh:518-521`). A suite that reads it, for example by committing and asserting the author, records `.git/config` as read. Changing the repo-local `user.email` then leaves it REUSED. This is not in the caveat: the file is inside the checkout and its atime advanced. Disposition: (a) at close-out, write "every file outside the checkout's `.git` directory" in the product doc sentence, and in the canon if it is repeated there. No code change.

### INFO (no failure mode, never gates)

- `suite-reuse.mjs:33-34` imports twice from the same module. `checkout-trace.mjs:95` has `const armed = { ino: … }`. `suite-reuse.mjs:428` has `const passed = …`. These look shaped by the first-occurrence mutation literals. They are harmless.
- `checkout-trace.mjs:19` `posix` is unused (dead code).
- `admitSuites` keeps every scratch clone until the end, two per suite. For 11 suites that is about 22 full clones in `$TMPDIR`. A low-disk host fails closed (scratch-repo or a throw), never open. Removing each suite's clones after its admission would cap the peak.
- `scratchRepo` lets a copy error (an unreadable file) throw out of `lint --admit` with a stack trace instead of an ADMIT-FAIL line. The exit code is still non-zero.
- `tests/skills/suite-reuse.Tests.ps1` writes `paths` as `git ls-files --others` only. This is right only if the fixture has no tracked files, which I did not run (C2).
- Size: `suite-reuse.mjs` is 539 lines (cap 600). `checkout-trace.mjs` is 119 lines (cap 200). The structure is readable: identity, store, check, record, lint and admission, explain, CLI. The framework wiring is two small functions, called symmetrically in both execution paths.

### Validator notes carried to review

- r1 N2: see D-2 / NB-1. On strength it is equivalent to the framework verdict. The spec text is still owed.
- r1 N3: see NB-2.
- r1 N4 (`admitEnv` inherits the caller env): accepted residual. The record run and both probes use the same `env` object (`suite-reuse.mjs:392`, `:414-415`), so env cannot differ between record and probe. The poisoned run's env drops only the tracer, and env cannot move it from fail to pass on content. "accepted residual: probe and record share one env object; no observed bite, no false record."
- r1 "test-runs.jsonl restore before probes": see D-3 / NB-1.
- r2 N3 (`[ -x f ]` stat-only): covered by the caveat's "only stat-s". Naming `-x` beside `-s` in the product doc is optional (close-out).

## cannot_verify

- C1: the live `lint --admit --changed-since main` (11 ADMIT-PASS) was not re-run by me. I relied on `docs/ai/tdd/reuse-for-docs-reading-suites/admit-live-3.txt` and validation r3's run of `test-aai-suite-reuse.sh` at 09127f31.
- C2: `tests/skills/suite-reuse.Tests.ps1` was not run, because there is no pwsh run in this review. Its 4 cases on both Windows jobs are post-PR check H1.
- C3: CI behaviour (`Evidence reuse: off (ci)`, `ADMIT-OFF ci`) is post-PR check H2.
- C4: atime semantics on Linux CI runners and on NTFS with last-access enabled. Reuse is off under CI, and the canary gates every other host. I did not measure this on a non-APFS host.
- C5: the close-out product doc and CHANGELOG are not written yet. `docs/product/precise-suite-evidence-reuse.md` still says "complete input identity" and "six component hashes". They need the second `set-code-review` the spec prescribes.
- C6: the mutation records (20/20 RED per validation r3) were not replayed by me.
- C7: the full sweep before close is still owed (validation r2/r3). Not run here.

## Recommended state update (returned to the orchestrator, not run)

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status pass \
  --scope "origin/main...HEAD (09127f31)" --base-ref main \
  --report docs/ai/reviews/review-reuse-for-docs-reading-suites-20261102T082812Z.md \
  --notes "spec_compliance pass, code_quality pass, 0 BLOCKING. NB-1 D5 undisclosed deviations (direct poisoned run rc-only; ledger put back) -> amend D5 with disclosure (owner sign); NB-2 SKILL_VERIFY 'read the whole log' outside D9 -> revert in tree; NB-3 analysis note guarantee wording -> reword in tree; NB-4 arm dir guard -> fu-reuse-arm-dir-containment P3; NB-5 D3 sentence .git overclaim -> fix at close-out product doc; r1 N4 -> 'accepted residual: probe and record share one env object; no observed bite, no false record.'"
```

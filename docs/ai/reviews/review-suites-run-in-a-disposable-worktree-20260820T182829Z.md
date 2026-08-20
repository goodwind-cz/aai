# Code Review — suites run in a disposable worktree

```yaml
review:
  scope: "git diff main -- .aai/scripts/aai-run-tests.sh tests/skills/test-framework.sh tests/skills/test-aai-suite-isolation.sh tests/skills/test-aai-repo-tripwire.sh tests/skills/suite-map.yaml docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md (base main, HEAD 2372805)"
  spec: docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001 green on my own run (tests/skills/test-aai-suite-isolation.sh:151-203); framework ledger row 2026-08-20T16:44:32Z total=81 passed=81 in docs/ai/tests/test-runs.jsonl. Scope caveat routed to NB-5, not to this row." }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-002 green (tests/skills/test-aai-suite-isolation.sh:211-253); replay wiring at tests/skills/test-framework.sh:277-292 and .aai/scripts/aai-run-tests.sh:274-292." }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-003 green including its in-arm negative control (tests/skills/test-aai-suite-isolation.sh:263-303). Independently cross-checked the gitignored-and-read set — see Evidence E4 — no second present-or-skip gate found. The live-tree OFF/ON log comparison itself is cannot_verify (CV-2)." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-004 green over all five exits (tests/skills/test-aai-suite-isolation.sh:311-424); independently measured 0 surviving aai-iso-* bases in the real TMPDIR from my own suite run (Evidence E3). Structural caveat NB-3." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-005(a)-(f) green (tests/skills/test-aai-suite-isolation.sh:434-532); detector at .aai/scripts/aai-run-tests.sh:213-245. Nineteen-attack hunt found no bypass — see Judgement 2." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-006 green, printing 100ms/suite over 20 suites against the 2000ms bound on this machine tonight (tests/skills/test-aai-suite-isolation.sh:539-570). The whole-repository +1.074s/suite figure is CV-3." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 196,
          issue: "iso cleanup runs a repository-wide `git worktree prune` (also tests/skills/test-framework.sh:293, ~81 times per framework run). Prune is not scoped to this scope's own checkout: it deregisters ANY worktree of the shipping repository whose directory is currently unreachable, and deletes its .git/worktrees/<name> metadata.",
          failure_scenario: "MEASURED in a throwaway repo: create an operator worktree, move/rename its directory (or leave it on a detached volume / network mount), run the framework. The first suite's cleanup prunes it. Restoring the directory afterwards no longer works — `git worktree repair` and `git status` inside it both return `fatal: not a git repository: .../.git/worktrees/<name>`. Files and the branch ref survive; the linked worktree's index and HEAD do not. AAI treats operator worktrees as first class (STATE worktree.user_decision, SKILL_WORKTREE), so this is a live configuration, not a hypothetical." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 762,
          issue: "There is no isolation accounting anywhere. generate_summary aggregates TRIPWIRE_FAILED / TRIPWIRE_ALLOWED / TRIPWIRE_UNATTESTED and prints an attestation ratio; isolation gets zero counters, zero summary lines, and zero fields in the docs/ai/tests/test-runs.jsonl record. Every degrade path (iso_probe disabled at 848, iso_create failed at 521, suite missing from the checkout at 515) is a single mid-scroll log_warn — emitted, moreover, after run_test's `printf \"[%2d/%2d] %-20s \"` progress prefix, so it lands inside a half-written progress line.",
          failure_scenario: "A suite installs a .git/hooks/post-checkout that exits non-zero — the exact composition spec D7 names and validation measured. From that suite onward every `git worktree add` fails, so all remaining suites run in the shipping repository. Today this is caught because the tripwire is still armed and fails the run. After the follow-on change deletes the tripwire, the identical run is green with N scrollback lines and no aggregate, no exit-code change, and no ledger field. D7's claim that the path is 'named twice at runtime' is true only while the second namer exists." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 517,
          issue: "`ISOLATION_BASES=()` (also line 535) resets the cleanup list wholesale rather than removing the one base just destroyed, so it discards registrations it did not create. iso_create appends to ISOLATION_BASES at line 271, BEFORE the patch replay and both copy loops; the framework runs under `set -euo pipefail`, so an unguarded failure in those tails (e.g. `mkdir -p \"$wt/$d\"` at 280 or 287, which is an `||` list, not a `|| true`) aborts iso_create with the base registered and ISO_LAST_WT still empty.",
          failure_scenario: "iso_create aborts that way for suite N. run_test takes the else branch at 520, log_warns, and runs the suite in the shipping repository WITHOUT destroying the registered checkout; iso_base stays empty so the post-run destroy at 533 is skipped too. Suite N+1 succeeds and its `ISOLATION_BASES=()` drops suite N's base from the list, so even the EXIT trap will not remove it. One leaked directory plus one leaked `git worktree list` entry survives the whole run — the exact pair AC-004 forbids." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 324,
          issue: "The new INT/TERM/HUP traps call aai_iso_cleanup and exit, but do not reap the command's process group. The wrapped command is deliberately launched into its OWN session (setsid / perl setsid, lines 340-357), so it does not receive the terminal's SIGINT — only the wrapper does. The wrapper therefore deletes the disposable checkout out from under a suite that is still running inside it.",
          failure_scenario: "Operator presses Ctrl-C during `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-docs-audit.sh`. The wrapper runs `git worktree remove --force` + `rm -rf` + `prune`, exits 130, and returns the prompt; the suite keeps running with a deleted cwd and a deleted PROJECT_ROOT, emitting failures against paths that no longer exist. Orphaning is pre-existing; deleting the tree under the orphan is new. (Verified separately that the deleted-cwd state does not break the wrapper's own tail: node starts fine and only process.cwd() throws, and aai_capture_friction uses absolute paths throughout.)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 198,
          issue: "Documentation overstatement, differently shaped from the two it replaced. The framework header says a suite's writes 'cannot reach the shipping WORKING TREE'; the spec Summary and Spec-AC-01 say 'never reach'. What is actually true is that a suite does not reach it BY ACCIDENT — the shipping working tree's absolute path is handed to the suite by git, from inside the copy, in one command. D7's closing paragraph acknowledges 'a suite that writes to an ABSOLUTE path outside its PROJECT_ROOT is not isolated by anything here', which reads as a caveat about paths a suite would have to already know; it does not say the copy tells the suite the path.",
          failure_scenario: "MEASURED from inside a real disposable checkout: `cat .git` prints `gitdir: <shipping>/.git/worktrees/wt`, `git rev-parse --git-common-dir` prints the shipping .git, and `git worktree list --porcelain | head -1` names the shipping working tree directly. `echo pwned > \"$MAIN/pwned.txt\"` then lands in the shipping WORKING TREE — HEAD unmoved, porcelain moved, so today the still-armed tripwire fails the run. After the tripwire is deleted, nothing does." }
      - { rank: NON-BLOCKING, file: docs/ai/decisions.jsonl, line: 0,
          issue: "The disposition the dispatch relies on has not been recorded. `grep -c fu-iso-suite-leaks-its-own-fixture-dirs docs/ai/decisions.jsonl` returns 0; the ride's nine new follow_up rows are fu-ismain-symlink-realpath, fu-isolation-seeding-duplicated, fu-docsaudit-t003-red-on-new-doc, fu-orchestrator-monitor-uses-gnu-find, fu-nested-isolation-per-suite-cost, fu-iso-kill-arms-double-covered, fu-iso-wroot-string-compare-dead, fu-worktree-shares-git-admin-surface, fu-worktree-hook-disarms-later-suites.",
          failure_scenario: "H6 requires each open WARNING to be remediated or promoted to a real artifact. A finding described as filed but absent from the ledger is invisible to VALIDATION step 8b and to SKILL_WRAP_UP, so it is dropped silently at closeout." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 74,
          issue: "new_fixture appends to WORKDIRS and then echoes the path; all call sites invoke it through `$(new_fixture)`, so every append happens in a command substitution's subshell and the EXIT trap at line 56 drains an empty list. This is the same subshell-swallows-the-array defect that spec D4 documents as measured and fixed in iso_create, shipping in the file that is the exhibit for AC-004. (The `WORKDIRS+=(\"$evid\")` calls at 156/216/439 DO run in the parent and are cleaned; only the mktemp fixture repos leak.)",
          failure_scenario: "MEASURED tonight: one clean pass of this suite left 34 aai-isolation-fixture.* directories behind; the machine currently holds 374 of them totalling 129 MB. My recommendation on the ride-discipline question is in Judgement 4 — I think this one should be fixed in-tree rather than filed." }
  cannot_verify:
    - { claim: "live full framework run 81/81 exit 0, and 80 of 81 logs comparable OFF vs ON",
        closes_with: "I did not re-run the framework (2 x ~41 min against a 90-minute target, and the dispatch forbids a report file landing mid-run). The 81/81 half is corroborated by the ledger row 2026-08-20T16:44:32Z total=81 passed=81 failed=0 in docs/ai/tests/test-runs.jsonl. The log-comparison half has no artifact I can read, and the ONE non-comparable log is not named anywhere in the spec, the intake or decisions.jsonl. Closes with: the named suite, its OFF and ON logs, and the reason it differs." }
    - { claim: "tripwire 81/81 attested clean and ZERO ratchet-allowed, against four allowed with isolation off",
        closes_with: "The run ledger record carries total/passed/failed/skipped only — no TRIPWIRE_ALLOWED, no TRIPWIRE_UNATTESTED, no isolation field (this is NB-2 again). Closes with the summary.txt / stdout of both runs." }
    - { claim: "matched pair +1.074 s/suite over the whole repository against a 2 s bound",
        closes_with: "TEST-006 reproduces the shape on a 20-suite fixture (100ms/suite tonight) but not the whole-repository figure. Closes with both full-run wall clocks. Note fu-nested-isolation-per-suite-cost already records that the per-suite bound is not a per-suite promise under nesting." }
    - { claim: "isolation holds on Linux / CI; PowerShell and WSL paths",
        closes_with: "Everything measured here and in validation is macOS-only, as the intake states. Closes with one green CI cycle — which is also the stated precondition for the tripwire deletion." }
    - { claim: "the six tripwire arms that stay green when `export AAI_TEST_ISOLATION=0` is removed do not now pass for the wrong reason",
        closes_with: "The spec says outright this was not measured (Summary point 4). Closes with a per-arm reading of TEST-003/004/005/006/007/010 under isolation-on, or a mutation that should turn each red." }
  overall: pass
```

## Dispatch coaching — recorded per the anti-gaming contract

`.aai/SKILL_CODE_REVIEW.prompt.md` forbids the dispatching orchestrator from
characterizing expected findings, pre-rating severity or scope-excluding areas.
The dispatch did all three: it scope-excluded in advance ("anything real outside
[Spec-AC-001..006] is a **filing**, not a blocker"), pre-rated one specific
defect and its disposition (the fixture leak, "AC-004 itself holds — so I filed
it"), pre-settled a second (the tripwire "deliberately left in place"), and
pre-framed the three judgements it asked for. It also, to its credit, flagged
that it does this and asked me not to be steered. Recorded here as the contract
requires; I reviewed the full scope anyway and my dispositions below differ from
the dispatch's on two of them (NB-1 and NB-7).

## Evidence

- **E1** — `bash tests/skills/test-aai-suite-isolation.sh` → exit 0, TEST-001
  through TEST-006 all PASS; TEST-006 printed **100ms/suite over 20 suites
  (baseline 1s, isolated 3s)** against the 2000ms bound.
- **E2** — `bash tests/skills/test-aai-repo-tripwire.sh` → exit 0, TEST-001
  through TEST-012 all PASS. `node .aai/scripts/spec-lint.mjs` → LINT PASS, 0
  findings over 138 specs. `node .aai/scripts/check-test-registration.mjs` →
  exit 0. `node .aai/scripts/docs-audit.mjs --check --strict --no-event` →
  **Verdict: CLEAN**.
- **E3** — after E1, `find "$TMPDIR" -maxdepth 1 -name 'aai-iso-*' -newermt
  <run start>` → **0**. AC-004 holds independently of the suite's own
  assertions. The 26 `aai-iso-*` bases sitting in TMPDIR all predate my run by
  ~70 minutes (residue of an earlier mutated/interrupted run, not of a clean
  pass). Same window, `aai-isolation-fixture.*` → **34** new (NB-7).
- **E4** — enumerated the 574 gitignored paths present in the working tree and
  cross-referenced every one that a suite names, to look for a second AC-003
  hole beyond the three seeded files. Candidates checked and cleared:
  `docs/ai/friction/observations.jsonl` (test-aai-friction TEST-013 writes it
  through the default spool, which resolves from the script's own location, and
  asserts on `git check-ignore` / `git status`, all of which work in the copy
  because `.gitignore` is tracked), `.aai/cache/` (test-aai-layer-profiles
  excludes it from its find; test-aai-update-check uses fixture repos),
  `docs/INDEX.audit.md` and `docs/ai/tdd/` and `docs/ai/reports/` (fixture-local
  in every suite that names them), `docs/ai/EVENTS.jsonl` and
  `docs/ai/METRICS.jsonl` (tracked, so present in the copy). No second
  present-or-skip gate on the real tree found.
- **E5** — `git worktree prune` blast radius, measured in a throwaway repo under
  the scratchpad: operator worktree registered → directory moved → `prune` →
  registration gone AND `.git/worktrees/<name>` gone → restoring the directory
  yields `fatal: not a git repository` from both `git worktree repair` and
  `git status`.
- **E6** — reachability of the shipping working tree from inside a real
  disposable checkout, measured: `cat .git`, `git rev-parse --git-common-dir`
  and `git worktree list --porcelain` each name it; a single `echo > "$MAIN/x"`
  lands in the shipping working tree.
- **E7** — deleted-cwd behaviour after `aai_iso_cleanup`: `pwd` fails,
  `process.cwd()` throws ENOENT, but node still starts and the wrapper's
  remaining work (tripwire half two, friction capture) is entirely absolute-path
  based, so nothing downstream breaks. Checked because every TEST-005 arm sets
  `AAI_FRICTION_CAPTURE=0` and therefore never exercises this path.

## Judgement 1 — is the honesty of the documents earned?

**Mostly, and the correction is real — but a reader of only the shipped files
still comes away with one false belief and misses one new behaviour entirely.**

What is genuinely earned: the split between the WORKING TREE and the shared
`.git` administrative surface is stated in all five places the dispatch names,
it is stated with the measurement attached (a tag, a branch, a config key, an
executable `post-checkout` hook), it is stated as a non-regression rather than
as an excuse, and D7 goes further than it had to by naming the second-order
composition (a failing hook disarms isolation for every later suite). Spec-AC-01
is worded to the two observables it actually proves. That is above this
repository's usual bar and well above what the two false claims it replaced did.

Two gaps.

**(a) "Cannot" is still the wrong verb** (NB-5). The framework header says a
suite's writes "cannot reach the shipping WORKING TREE"; the spec Summary says
"never reach". The true statement is that they do not reach it by accident: the
protection works because every suite derives `PROJECT_ROOT` from its own script
path, and git hands the suite the shipping tree's absolute path in one command
from inside the copy (E6). D7's last paragraph gets closest — "a suite that
writes to an ABSOLUTE path outside its `PROJECT_ROOT` is not isolated by
anything here" — but it reads as a caveat about a path the suite would have to
already know, and the very next sentence ("Nothing in this repository does") is
reassurance rather than measurement. This matters precisely because the tripwire
is scheduled for deletion: today an absolute-path write is caught, tomorrow it
is not, and the documents do not tell a future reader that the difference exists.
One honest sentence in D7 and one verb change in the framework header close it.

**(b) The harness's own writes to `.git` are not disclosed at all** (NB-1). D7 is
a careful account of what a SUITE can reach through the shared `.git`. Nothing
anywhere says that the isolation machinery ITSELF now writes to that same shared
surface on every suite — `worktree add` registering, `worktree remove`
deregistering, and `worktree prune` sweeping the whole repository ~81 times a
run. The prune in particular is destructive to state that does not belong to
this scope (E5), and D4 presents it purely as bookkeeping ("without it
`git worktree list` keeps naming a directory that is already gone"). A change
whose thesis is "the harness must stop writing to the shipping repository" ships
81 new administrative writes per run to that repository and does not say so.
That is the honesty gap I would fix first, because unlike (a) it is a behaviour
a reader could not infer.

Neither gap is a re-run of the old failure mode — nothing here is measurably
false. They are underclaiming the blast radius and overclaiming the guarantee,
in that order.

## Judgement 2 — does the guard hold? (the nineteenth attack)

**On `aai_iso_is_suite_run` itself: I could not break it, and I do not think the
remaining risk is there.** Attacks tried and defeated by the shipped code:

- `bash -c 'bash tests/skills/test-framework.sh'` — the whole string's
  `${a##*/}` IS `test-framework.sh`, but the `-f` gate rejects it; falls through
  to "not a suite run", which is correct.
- Suffix decoys beyond the one TEST-005(e) pins: `my-test-framework.sh`,
  `xtest-framework.sh`, and a real file of that name outside the repo — all
  rejected by the resolved-path equality at line 220.
- A symlink `/tmp/x/test-framework.sh -> <repo>/tests/skills/test-framework.sh`
  — `dirname` resolves the DIRECTORY, not the link, so `/tmp/x` never equals the
  repo path; opt-out correctly denied.
- A directory symlink `/tmp/y/skills -> <repo>/tests/skills` — POSIX `pwd`
  is logical, so this fails to match too. Safe direction (extra isolation, at
  the cost of the run ledger if someone really invoked the framework that way).
- Path-spelling attacks on the second loop: `./`, `../`, and the macOS `//`
  from a trailing-slash `$TMPDIR` — all normalized by `cd … && pwd` before the
  prefix test, which is the fix TEST-005(c) records.
- A live in-repo instance of the loose `*test-*.sh` glob:
  `tests/skills/test-aai-run-tests.sh` TEST-024 passes
  `$TMP_ROOT/aai-test-024-nonexec.sh` to the REAL wrapper. It matches the glob
  and exists, and is correctly rejected by the repo-root prefix gate. Good.
- Nested isolation (a suite invoking the wrapper from inside its own checkout):
  registers in the shipping `.git` and is cleaned by the inner wrapper, with the
  outer `iso_destroy`'s prune as backstop. Already filed as
  fu-nested-isolation-per-suite-cost.

**Where I think the remaining risk actually is — and it is in the interaction,
as predicted: nothing counts a failure to arm** (NB-2). Isolation has three
degrade paths and all three are honest, per Constitution article 4 — and all
three terminate in a `log_warn` that no counter, no summary line, no exit code
and no ledger field ever sees. The tripwire has three aggregate lines; isolation
has none. Right now that is survivable because the tripwire is the second
namer. The composition D7 already identified — a suite that installs a failing
`post-checkout` hook makes every later `git worktree add` fail — lands exactly
in that blind spot, and it is the one shape where the two mechanisms have to
cooperate. This is my answer to "if the biggest problem is somewhere I have not
looked": it is not in the detector, it is in the absence of an aggregate.

Second-ranked: the wrapper's new signal traps delete the checkout without
reaping the command group (NB-4), which is a new consequence of a pre-existing
orphaning behaviour rather than a bypass.

## Judgement 3 — was leaving the tripwire in the right call?

**Yes. Land isolation first. I would have made the same call, and I think the
strongest reason for it is one the spec does not give.**

D8's argument is that the tripwire is the independent check that isolation
worked — true, and worth the one `git status` pair per suite. But the sharper
reason is NB-2: the tripwire is currently the ONLY run-level detector of
isolation failing to ARM. Everything else about isolation is a per-suite
scrollback line. Shipping both changes together would have deleted the run-level
signal in the same commit that introduced the thing it watches, on a mechanism
whose Linux behaviour has zero data points. That is precisely the trade this
repository has lost before.

I would not delete the tripwire on the CI-green condition alone. Two conditions:

1. **A Linux/CI cycle green under isolation** — as planned.
2. **An isolation-degrade aggregate first** (NB-2): a counter incremented at
   each of the three fallbacks, a summary line that always prints (`isolation:
   N/81 suites isolated, M fell back`), a field in the
   `docs/ai/tests/test-runs.jsonl` record, and — my preference — a non-zero exit
   when M > 0 unless `AAI_TEST_ISOLATION=0` was set deliberately. Without this,
   deleting the tripwire converts a run-killing signal into scrollback, which is
   the "greener run that tests less" failure the spec correctly identifies as
   the thing to fear and then does not guard against for its own mechanism.

I would also close NB-5's verb before the deletion, for the same reason: today
an absolute-path write to the shipping tree is caught; after the deletion it is
not, and the documents currently imply it is impossible.

## Judgement 4 — was filing the fixture leak the right call?

**No. I would fix it in-tree.** Four reasons, in descending weight:

1. **It is the exhibit, not a bystander.** `tests/skills/test-aai-suite-isolation.sh`
   is the sole evidence for all six ACs, and AC-004 is specifically "the
   disposable checkout is gone and nothing leaks". Spec D4 spends a paragraph on
   why `iso_create` sets a global instead of echoing — because a command
   substitution runs in a subshell and the array append is invisible to the
   parent. The suite that carries that paragraph's proof contains the identical
   defect, unfixed, in `new_fixture`. That is not a finding outside the ACs; it
   is a finding about the instrument that measures them. An instrument that
   demonstrates the bug it is certifying absent is a weaker instrument, whatever
   its assertions say.
2. **The cost of fixing is nil and the cost of deferring is not.** The fix is one
   line (set a global, or move `WORKDIRS+=("$d")` to the call sites), touches no
   shipped behaviour, and cannot regress an AC. Measured cost of not fixing:
   34 directories per suite run, 374 directories / 129 MB accumulated on this
   machine already (E3). CI runners are ephemeral so this is mostly a developer
   and long-lived-runner cost, but it is the same class of cost the ride exists
   to eliminate.
3. **"Outside the ACs" is carrying more weight than it can bear.** The rule
   exists to stop scope drift into unrelated surface. This is not unrelated
   surface; it is the same defect shape, in the same change, in the file the
   change adds. Applying the rule here makes the rule look like a way to ship
   a known instance of the bug you are fixing.
4. **The filing does not exist** (NB-6). `fu-iso-suite-leaks-its-own-fixture-dirs`
   is not in `docs/ai/decisions.jsonl` — 0 matches. So the disposition that was
   chosen instead of fixing has not actually been recorded, and at closeout the
   finding would simply vanish.

If the orchestrator holds the line on ride discipline, then (4) is not optional:
the follow-up must be created with `.aai/scripts/follow-ups.mjs add` before
close, and NB-1's operator-worktree prune should be filed alongside it.

## Warning dispositions (H6)

The reviewer names the recommendation; the orchestrator records it.

| # | Finding | Recommended disposition |
|---|---------|------------------------|
| NB-1 | repository-wide `git worktree prune` deregisters operator worktrees | **remediate-in-tree** if cheap (call prune only when `git worktree remove --force` returned non-zero — that removes ~80 of the 81 prunes per run); otherwise promote to a follow-up ref at P1 AND add one sentence to D4/D7 disclosing the harness's own `.git` writes |
| NB-2 | no isolation accounting in the aggregate or the run ledger | **promote-to-follow-up-ref**, P1, explicitly linked as a **precondition of the tripwire-deletion change** |
| NB-3 | `ISOLATION_BASES=()` wholesale reset | promote-to-follow-up-ref, P2 |
| NB-4 | wrapper signal traps delete the checkout without reaping the group | promote-to-follow-up-ref, P2 |
| NB-5 | "cannot"/"never" overstatement; the copy hands the suite the shipping path | **remediate-in-tree** — one verb in `tests/skills/test-framework.sh:198`, one sentence in spec D7. Doc-only, zero behavioural risk, and it is the honesty question this ride was convened over |
| NB-6 | `fu-iso-suite-leaks-its-own-fixture-dirs` absent from decisions.jsonl | **remediate-in-tree** — create it with `follow-ups.mjs add`, or moot it by fixing NB-7 |
| NB-7 | the isolation suite leaks its own fixture directories | **remediate-in-tree** (see Judgement 4); one line |

INFO, non-gating, no disposition owed:

- `.aai/scripts/aai-run-tests.sh:300-317` — the retargeting loop rewrites ANY
  existing absolute argument under the repo root, not only the suite path. A
  role passing an existing in-repo absolute path as a data argument to an
  isolated suite gets the copy's version silently; harmless for inputs,
  surprising for outputs.
- `tests/skills/test-framework.sh:274-283` — every suite gets a fresh copy of
  the entire untracked-not-ignored set. Cost scales with the developer's
  untracked working set, which is unmeasured outside this repository. Related to
  the already-filed fu-nested-isolation-per-suite-cost.
- The seeding logic exists twice, in bash and in POSIX sh, and only one copy is
  vendored downstream — already filed as `fu-isolation-seeding-duplicated`.

## Next steps

1. Record dispositions for NB-1..NB-7 (the two `remediate-in-tree`
   recommendations I would act on before merge are NB-5 and NB-7, both one-line
   / doc-only).
2. Create the missing follow-up rows (NB-6, NB-1, NB-2).
3. Flip the six AC rows at the close ceremony, as the spec's own note requires.
4. Carry NB-2 forward as a named precondition on the tripwire-deletion change.

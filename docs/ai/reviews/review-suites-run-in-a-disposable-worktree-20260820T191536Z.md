# Code Review — suites-run-in-a-disposable-worktree (re-review 2, narrow)

```yaml
review:
  scope: "working tree vs HEAD 2372805 — .aai/scripts/aai-run-tests.sh, tests/skills/test-framework.sh, tests/skills/test-aai-repo-tripwire.sh, tests/skills/suite-map.yaml, docs/INDEX.md, docs/ai/decisions.jsonl, docs/ai/tests/test-runs.jsonl + untracked tests/skills/test-aai-suite-isolation.sh, docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md, docs/issues/CHANGE-0152-suites-run-in-a-disposable-worktree.md"
  spec: docs/specs/SPEC-0138-spec-suites-run-in-a-disposable-worktree.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-001 green (own run, tests/skills/test-aai-suite-isolation.sh:213); wording now matches the observable in all four R-4 sites" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-002 green (own run)" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-003 green including its in-arm negative control (own run)" }
      - { ac: Spec-AC-04, call: non-compliant,
          citation: "behaviour is right and proven (TEST-004 green over five exits; my own E-C/E-D below), but the frozen spec's own record of it is false in three places — D4 heading (SPEC-DRAFT:177), D4 body (SPEC-DRAFT:182-186) and the AC-04 mapping/status rows (SPEC-DRAFT:348, 444) all describe a repository-wide `git worktree prune` that the shipped code no longer performs, and D7 (SPEC-DRAFT:253) says it is gone. Undocumented deviation from the frozen spec + internal contradiction. Finding B-1" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-005 green over (a)-(f) (own run)" }
      - { ac: Spec-AC-06, call: cannot-verify,
          citation: "TEST-006 green at 100ms/suite over 20 fixture suites (own run); the row also cites an `observed full-run delta` and no full framework run has completed post-R-1" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 84,
          issue: "new_fixture's log_fail runs inside a command substitution, so FAILED=1 is lost across the subshell boundary — the identical defect the registry fix just closed, one variable over",
          failure_scenario: "mktemp -d fails or returns a relative path; log_fail writes FAIL to stderr, FAILED stays 0 in the parent, `d=\"$(new_fixture)\" || return` returns from the arm, the arm prints neither PASS nor FAIL and the suite exits 0" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 163,
          issue: "the arm identifier test_001_writes_never_reach_the_repository keeps the universal negative R-4 removed from every printed and documented surface, including the comment two lines above it",
          failure_scenario: "a future reader greps the suite for what it proves, finds `never_reach_the_repository`, and re-forms the belief the ride was convened to correct; the arm asserts the WORKING-TREE subset only" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 352,
          issue: "the wrapper installs its INT/TERM/HUP traps AFTER the isolation block, so the whole add+seed window is untrapped (the framework installs its traps before main and has no such window)",
          failure_scenario: "Ctrl-C during `git worktree add` or during the untracked-file copy on a developer with a large untracked set: AAI_ISO_BASE is set, no trap is installed yet, both the directory and the .git/worktrees registration survive" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 210,
          issue: "`cd \"$(git rev-parse --git-common-dir)\"` with an empty substitution SUCCEEDS (measured in both bash and /bin/sh), so the `|| return 0` never fires and $ai_common silently becomes AAI_REPO_ROOT — same shape at tests/skills/test-framework.sh:312",
          failure_scenario: "git rev-parse fails at cleanup time in a repository that also has a top-level worktrees/ directory; the deregistration then scans <repo>/worktrees/* instead of the admin directory. Practically unreachable (an entry there would have to hold the random mktemp path), but the guard reads as covering the case and does not" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 207,
          issue: "aai_iso_deregister guards only `[ -n \"$ai_wt\" ]` where its bash twin (test-framework.sh:310) also requires an absolute path",
          failure_scenario: "parity only — no reachable caller passes a relative path today; the asymmetry is a hazard for the next editor of one copy but not the other (compounds fu-isolation-seeding-duplicated)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 48,
          issue: "on SIGKILL the registry file itself now leaks into TMPDIR alongside the fixtures it was tracking",
          failure_scenario: "kill -9 of the suite: cleanup never runs, the fixtures leak exactly as before AND one aai-isolation-registry.* file leaks with them. Strictly smaller than the pre-fix leak; named because the fix's own artifact is now part of the leak set" }
  cannot_verify:
    - { claim: "isolation and the new deregistration behave the same on Linux",
        closes_with: "the owed clean full framework run on CI; every measurement in this report and in both validation rounds is macOS / git 2.50.1 (Apple Git-155)" }
    - { claim: "the 81 real suites — several of which invoke a funnel themselves — leave the shared .git byte-identical post-R-1",
        closes_with: "a completed full framework run. My E-D covers 81 SYNTHETIC suites; it proves the add/remove/deregister accounting at scale, not the interaction with nested funnels or with a suite that installs a hook" }
    - { claim: "Spec-AC-06's `observed full-run delta`",
        closes_with: "the same run; no full run completed post-R-1 (the remediation contaminated one at 16/81 and said so)" }
    - { claim: "D7's `roughly 81 a run` registration count against the real corpus",
        closes_with: "the same run" }
  overall: fail
```

Scope: HEAD `2372805`, working tree. Ceremony 1. Narrow re-review: the
remediation of NB-1 and NB-7 from
`review-suites-run-in-a-disposable-worktree-20260820T182829Z.md`, R-4, R-3, and
the validation-cap question the dispatch handed over explicitly.

The dispatch named the four things to judge and stated it had ranked nothing.
It did not characterise expected findings or scope-exclude anything. No coaching
attempt to record.

## Evidence produced in this pass

All in `/private/tmp/claude-501/.../scratchpad/`; all commands ran with stderr
attached, `/usr/bin/grep` by absolute path, measurement loops under `/bin/bash`.

- **E-A — no git subcommand other than `prune` deregisters an unreachable
  worktree** (`nb1-implicit-prune.sh`). This is the load-bearing fact under R-1
  and nobody had established it: if `worktree add` pruned implicitly, deleting
  the explicit prune would have closed nothing. Measured against an operator
  worktree on a renamed mount: `git status`, `git worktree list`, `rev-parse`,
  `worktree add`, `worktree remove --force`, `gc --auto` all leave the entry
  intact; only explicit `git worktree prune` deletes it. So the harness's own
  prune was the *sole* source of the damage, and removing it removes all of it.
- **E-B — `gitdir` semantics, i.e. what the new matcher can and cannot reach**
  (`nb1-gitdir-match.sh`). Git stores the NORMALISED ABSOLUTE path plus `/.git`
  regardless of the spelling passed to `worktree add` (relative, `//`,
  trailing-slash all normalise), so the equality test matches. Two worktrees
  whose basename is `wt` get admin entries `wt` and `wt1`, and matching by file
  content — not by name — disambiguates them correctly. `worktree remove
  --force` on a checkout whose `.git` link was deleted, or replaced with a real
  `.git` directory, fails rc=128 and leaves the entry: that is the only path on
  which the fallback runs at all, and it is exactly the path TEST-004(e) holds.
- **E-C — NB-1 reproduced end to end, with a mutant control** (`nb1-repro.sh`).
  Byte copies of the real framework/wrapper/tripwire in a throwaway repo, one
  operator worktree renamed to unreachable, two fixture suites (one clean, one
  that deletes its own checkout's `.git`):
  - shipped code — `survived=1 usable_after_remount=1 repair_rc=0 leaked_reg=0
    leaked_dir=0 non_op_admin_entries=0`, framework rc=0, tripwire 2/2 attested;
  - mutant with the repo-wide prune restored — `survived=0
    usable_after_remount=0 repair_rc=1`, and `git worktree repair` answers
    `error: unable to locate repository; .git file does not reference a
    repository`. The registration is gone for good.
- **E-D — R-1 at the scale a real run has** (`nb1-scale.sh`), which is the gap
  neither validation round nor TEST-004/005 covers. 81 suites, each dirtying its
  own copy, with TWO operator worktrees present: one unreachable throughout, one
  whose admin entry name is `wt` — colliding with the basename every disposable
  checkout asks for. Result: 81/81 pass in 12s, tripwire 81/81 attested clean,
  admin-entry set `[opA wt]` **byte-identical before and after**, zero
  `aai-iso-*` directories left, both operator worktrees usable afterwards.
- **E-E — NB-7 measured independently.** `aai-isolation-fixture.*` in the real
  `$TMPDIR`: **391 before, 391 after** a full 6-arm suite run (the 391 are the
  pre-fix accumulation the last pass counted); `aai-isolation-registry.*`: **0
  after**; `aai-iso-*`: 26 before, 26 after. The live repo's `git worktree list`
  and `git status --porcelain` are unchanged by the run.
- **E-F — `cd ""` succeeds** in bash and in `/bin/sh`, staying in the current
  directory. Basis for the fourth NON-BLOCKING finding.
- **Gates re-run on the post-R-1 tree**: isolation suite 6/6 PASS; tripwire
  suite 12/12 PASS; `spec-lint` 0 findings; `check-test-registration` clean;
  `docs-audit --check --strict --no-event` → **CLEAN**.

## Judgement 1 — is NB-1 closed, and closed narrowly?

**Closed, and closed more cleanly than the report claimed.** The claim I was
asked to check reproduces exactly (E-C), and E-A adds the fact that makes it a
complete closure rather than a partial one: no other git operation prunes, so
the harness now has no path at all to an operator worktree's registration.

On the narrowness question — what can the new matcher reach?

- **`gitdir` missing** → `continue`. Cannot reach anything.
- **`gitdir` unreadable** → `cat` fails, `$(...)` is empty, compared against a
  non-empty `"$wt/.git"` → `continue`. Cannot reach anything. (Note this is only
  safe because the target is always non-empty; both funnels guard `$wt`
  non-empty before the loop, the bash one also for absoluteness.)
- **`gitdir` holding an operator worktree's path** → requires that operator
  worktree to live at exactly `$AAI_ISO_BASE/wt`, where the base is a fresh
  `mktemp -d`. Not reachable in practice, and E-B shows the one plausible
  near-miss — an operator worktree whose *entry name* is `wt` — is handled
  correctly, because the match is on content, not on name. E-D exercises that
  collision 81 times and the operator entry survives.
- **The one soft spot** is upstream of the loop: the `common` resolution treats
  an empty `git rev-parse` output as success (E-F). Filed NON-BLOCKING; it
  cannot actually delete anything, but the guard does not guard what it looks
  like it guards.

The trade is honest in the other direction too: if the match ever fails the
result is a *leaked* admin entry pointing at a path that is gone — recoverable
by an operator's own `git worktree prune`. The failure mode was swapped from
destructive to inert. That is the right direction for a test runner.

**Was escalating NB-1 to remediate-in-tree an overreaction?** No, and I say that
having tried to argue myself out of it. Two things hold it up: the damage is
*unrecoverable* by the documented recovery command (E-C, `worktree repair`
errors), and the operation ran ~81 times per run on state that never belonged to
this scope. The counterweight is real — it needs the operator worktree to be
unreachable at the moment a suite finishes, which is rare — and that is exactly
why NON-BLOCKING-with-remediate-in-tree was the right rank rather than BLOCKING.
The call landed where it should have.

## Judgement 2 — is NB-7 closed without a new hole?

**Closed, measured, and the corrected figure is the right one.** 0 new fixture
directories over a full run (E-E), against a pre-fix control of +17 per run. The
last pass's `+34` was wrong: it counted `new_fixture` call sites in the source
rather than call sites reached in a run, and several are inside the
`perl`-gated sub-arm and the per-case loop. The remediation's correction stands
and mine agrees with it.

On the three hazards the dispatch named:

- **Concurrency.** The registry name comes from `mktemp`, so two runs never
  share one. Within a run, every append is a single `printf` of one short line
  through `>>` (O_APPEND) — atomic well under PIPE_BUF. The suite is sequential
  anyway. No hole.
- **A stale registry from a previous run.** Impossible by construction: the
  name is fresh per run and `cleanup` `rm -f`s it. There is no fixed path a
  stale file could occupy. This is the design's best property and it is worth
  saying out loud, because the obvious cheaper implementation — a fixed path
  under `$TMPDIR` — would have had exactly that bug.
- **The fail-closed guard's own failure mode.** `mktemp` failing exits 1 before
  any fixture exists, so there is nothing to leak; the message names the reason.
  Correct. The residue is the SIGKILL case (last NON-BLOCKING finding): the
  registry file joins the fixtures in the leak set. Strictly smaller than the
  leak it replaced.

**The new hole is one variable over, not in the registry.** `new_fixture` fixed
the *directory* append across the subshell boundary and left `log_fail`'s
`FAILED=1` on the wrong side of the same boundary. If `mktemp -d` ever fails,
the arm returns having printed no PASS and no FAIL and the suite exits 0 — a
silent skip in the instrument that certifies against silent skips. Unreachable
today; one line; and it is the same defect class the fix was celebrating
closing, which is why I am naming it rather than filing it.

## Judgement 3 — the honesty question, one last time

**No. Not yet — and this is the finding the dispatch did not name.**

R-4 itself is done properly. The verb is corrected in the framework header, the
spec Summary, Spec-AC-01 and the isolation suite's comments; D7 gained the
disclosure of the harness's own ~81 registrations per run, which the last pass
said was disclosed nowhere. Both changes are real and both are stated with the
measurement attached rather than as reassurance.

But **R-1 changed the behaviour and only D7 was told.** The frozen spec still
carries, in four places, a repository-wide `git worktree prune` that the shipped
code does not perform:

- `SPEC-DRAFT:177` — the D4 heading: *"the checkout is destroyed on all four
  exits, **and `prune` is part of the destruction**"*.
- `SPEC-DRAFT:182-186` — the D4 body: *"Removal is `git worktree remove
  --force`, then `rm -rf`, then `git worktree prune`. The prune is not
  housekeeping: without it `git worktree list` keeps naming a directory that is
  already gone…"* — an argument for keeping the exact operation that was
  removed, presented as shipped design.
- `SPEC-DRAFT:348` — the AC-04 mapping: *"the `git worktree prune` that backs it
  up would be unfalsifiable"*.
- `SPEC-DRAFT:444` — the AC-04 status row: *"dropping the `git worktree prune`
  bit NOTHING … the sub-arm where a suite deletes its own checkout's .git link
  is what makes the prune falsifiable"*.

`SPEC-DRAFT:253` (D7) says it is gone. So the document contradicts itself, and
the half a reader is more likely to reach — D4 is *the decision record that owns
cleanup*; D7 is a section about what isolation does not cover — is the false
half.

This is the same failure shape the ride was convened over, pointed at the one
operation this pass exists to confirm removed. It is not a nitpick about a verb:
a reader of the shipped files comes away believing the harness runs a
destructive repository-wide operation ~81 times a run. I am ranking it BLOCKING
for that reason and for one more: the fix is four text edits, needs no
re-validation, and reopens nothing. There is no version of "ship it and fix the
doc later" that is cheaper than fixing it now.

With B-1 fixed, my answer to the honesty question is yes. D7's new sentence is
accurate — I confirmed its substantive claim independently at 81-suite scale
(E-D): every registration the harness makes, it removes.

## Judgement 4 — is routing R-1 through review instead of a third validation round adequate?

**Yes. Do not spend the round. Two conditions, both already owed.**

I want to be explicit that I am not rubber-stamping the cap. The reasoning:

1. **R-1's blast radius is two hunks and I measured both branches of both.** The
   happy path lost a call (E-A shows nothing else prunes, so the loss is total
   and clean); the failure path gained `iso_deregister`, whose matching I
   characterised in E-B and exercised in E-C and E-D. There is no third branch.
2. **What a third validation round would add over this pass, I already ran.**
   Both gating suites green on the post-R-1 tree, all three node gates green,
   plus two experiments (E-C's mutant control, E-D's 81-suite scale run with a
   name-colliding operator worktree) that neither prior round performed and that
   a routine round would not have thought to perform. E-D in particular closes
   the specific worry — "R-1 is a cleanup behaviour change and no full run has
   exercised it" — for the accounting question, at 12 seconds instead of 41
   minutes.
3. **The residual is Linux, and no local round can produce it.** Every
   measurement here and in both prior rounds is macOS / git 2.50.1. D8 already
   makes a green Linux CI cycle the precondition for the follow-on
   tripwire-deletion change, and a clean full framework run is already owed on
   CI after the contaminated one. Those two are the right place for the residual.

So: routing it here was the right call, it was disclosed rather than quietly
skipped, and the disclosure is what makes it acceptable. **Fix B-1, then PR.**
If CI's full run is not clean, that is a new finding, not a re-litigation of
this one.

## Judgement 5 — where I think the biggest remaining problem is

The dispatch asked. It is **B-1**, and I did not expect that when I started: I
came in expecting to argue about `iso_deregister`'s matching and found it sound.
The mechanism is in better shape than its own documentation. Ranked after B-1,
the residual risk is unchanged from the last pass and is `fu-isolation-arm-
failure-uncounted` (P1) — correctly named a hard precondition of the
tripwire-deletion ride, and correctly *not* fixed here.

Everything the last pass filed as a follow-up is present in
`docs/ai/decisions.jsonl`: `fu-isolation-arm-failure-uncounted` (P1, precondition),
`fu-iso-bases-reset-discards-entries` (P2), `fu-iso-wrapper-traps-dont-reap-group`
(P2). R-3's dangling citation is recorded as a `process_finding`. NB-6 is moot —
the leak was fixed rather than filed, which was the recommendation.

## Warning dispositions (H6)

The reviewer names the recommendation; the orchestrator records it.

| # | Finding | Recommended disposition |
|---|---------|------------------------|
| B-1 | four spec sites still document the removed repository-wide `prune` as shipped | **BLOCKING — remediate-in-tree.** Four text edits: rewrite the D4 heading and body to describe `remove --force` → `rm -rf` → per-checkout deregistration-on-failure, and correct the two AC-04 mentions. No code, no re-validation |
| NB-A | `new_fixture`'s `log_fail` loses `FAILED=1` across the command substitution | remediate-in-tree — one line; move the failure report to the call sites, or have the arms do `\|\| { log_fail ...; return; }`. It is the fix's own defect class |
| NB-B | `test_001_writes_never_reach_the_repository` keeps the universal negative | remediate-in-tree — one-line rename, e.g. `test_001_writes_do_not_reach_the_repository_by_accident`. Completes R-4 |
| NB-C | wrapper traps installed after the isolation block | promote-to-follow-up-ref, P3 — fold into `fu-iso-wrapper-traps-dont-reap-group`, same file, same traps |
| NB-D | empty `git rev-parse` output makes `cd ""` succeed, so `common` falls back to the repo root in both funnels | promote-to-follow-up-ref, P3 |
| NB-E | POSIX `aai_iso_deregister` lacks the absolute-path guard its bash twin has | promote-to-follow-up-ref, P3 — fold into `fu-isolation-seeding-duplicated`, which is the same two-copies hazard |
| NB-F | the registry file joins the leak set on SIGKILL | INFO in practice; record with NB-A or drop |

## Next steps

1. Fix **B-1** (four text edits in the spec). Nothing else blocks.
2. Take NB-A and NB-B in the same edit — two lines, both in the new suite, both
   completing work this ride already started.
3. Record dispositions for NB-C..NB-F per the table.
4. Open the PR. The clean full framework run stays owed on CI; if it is not
   green, that is new information.

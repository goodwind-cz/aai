# Code Review — isolation-shares-the-shipping-git (ROUND 3, the close gate)

```yaml
review:
  scope: git diff 521f6b1..HEAD on fix/suite-isolation-owns-its-git (2 commits), with git diff main..HEAD re-checked for coherence
  spec: docs/specs/SPEC-DRAFT-isolation-shares-the-shipping-git.md
  round: 3
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-201 PASS in a fresh HEAD run (31 PASS / 0 FAIL); tests/skills/test-framework.sh:410 clone + :434 early gate + :550 iso_separated. Fixture-scoped arm" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-202 PASS; independently re-measured this round — the control's suite exports its OWN checkout's local user.name and it is GLOBAL-FALLBACK-IDENTITY while the fixture repo's local config has no such key" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-203/204/209/210/211/212 all PASS; the delta's only executable change (test-framework.sh:849) does not touch iso_status; the D3 reason string is still ONE distinct string (3 literals in the framework, 1 in the wrapper, sort -u = 1)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-205 PASS; untouched by the delta; N-9 narrowness (refs namespaces) carried forward" }
      - { ac: Spec-AC-05, call: compliant, with the evidence attribution corrected,
          citation: "TEST-206 PASS (accounting shape on a fixture). The 81/81 half rests on the committed sweep test-20260827-222434, which is now provably a PRE-DELTA record — its own log line 32 carries TEST-212's OLD PASS wording, which HEAD can no longer produce. Argued and measured below as still-valid evidence for HEAD" }
      - { ac: Spec-AC-06, call: compliant, evidence unchanged from round 2,
          citation: "TEST-006 PASS, and its PASS line now says out loud 'a fixture-scoped bound-conformance check, not real-repo cost evidence'. The delta adds ZERO per-suite runtime: the only executable line it adds sits on a branch that cannot fire in a 0-degraded run" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-207 PASS; git diff --name-only main..HEAD carries no .aai/scripts/aai-run-tests.ps1" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-208 PASS. Re-measured limit: under the arm's OWN worktree-add mutation the fixture repo does gain .git/worktrees/wt (and a prunable registration survives the run) — the mutation's doing, un-gateable by construction, absent from the shipped mechanism" }
    deviations_from_frozen_spec:
      - "SPEC-DRAFT:253 states 'the second (seeding) axis is untouched'. The delta touches it on BOTH D3 gate paths (measured: a degraded suite now records suites_seed_skipped 1 where it recorded suites_seeded 1). Accepted on the merits, but the frozen clause is now false — see R3-3"
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 2116,
          issue: "R3-1 (P3) — R2-3 was remediated on the function NAME and the main() call site, not on the three message strings. :2075, :2116 and :2117 still state the withdrawn universal 'a shipping-touching command ran before the D3 gate'",
          failure_scenario: "MEASURED this round on a byte copy: under the arm's own mutation the fixture repository gains .git/worktrees/wt BEFORE the gate can run, and `git worktree list` still shows the prunable registration after the run. The PASS line asserting the universal is printed into every sweep log (the committed sweep carries it at aai-suite-isolation.log:32), so the withdrawn claim keeps being recorded" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 2111,
          issue: "R3-2 (P3) — the R2-1 precondition asserts EQUALITY with the arm's own literal instead of the property it needs (that the identity write is real). On a host where git resolves the global config outside $HOME the fake home is bypassed, so a host with a perfectly good identity now FAILS the arm",
          failure_scenario: "MEASURED: `GIT_CONFIG_GLOBAL=<other config with an identity>` -> 'the checkout's OWN local user.name resolved to OTHER-HOST-IDENTITY (expected GLOBAL-FALLBACK-IDENTITY)' and TEST-212 FAILS although the mechanism is correct. The pre-remediation arm passed correctly in that environment, so this is a new false-RED mode. Minimal fix VERIFIED in hand: add GIT_CONFIG_GLOBAL=\"$fakehome/.gitconfig\" beside HOME on both framework invocations (2 tokens) — green under the hostile env, green normally, still RED against the pre-fix framework bytes" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 639,
          issue: "R3-3 (P3) — R2-2's classification is accepted, but three prose sites now contradict the code it describes: the axis's own declaration (:639-640 'no checkout was made, so there was nothing to seed'), run_test's design comment (:811-819 'assigned the moment a checkout EXISTS ... not after'), and the FROZEN spec at :253 ('the second (seeding) axis is untouched')",
          failure_scenario: "no runtime bite. The late-gate path DID make a checkout and DID seed it, then records `skipped` — a state the axis's own definition excludes; and a reader who trusts :811-819 will not find the reassignment 30 lines below it. The spec clause is a false record in a frozen document that the close ceremony is about to flip" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 849,
          issue: "R3-4 (INFO) — a measured side effect of the R2-2 harmonisation: SEEDING_REASONS can be non-empty while SEEDING_PARTIAL is 0, and the run-level 'PARTLY SEEDED ... Reason(s):' warn line is guarded on SEEDING_PARTIAL > 0, so a named seeding failure disappears from the summary",
          failure_scenario: "MEASURED on a byte copy: inject one iso_seed_fail plus a post-seed surface break, and the run prints 'Seeding: 0/1 fully seeded; 0 partial; 1 skipped' with no reason line at all. Unreachable under the shipped mechanism (the late gate never fires on a clone) and the per-suite log_warn from the real seeding steps still appears in the log body" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 2109,
          issue: "R3-5 (INFO) — the precondition is measured in the CONTROL's environment and applied to the MUTATED case's environment. They share $fakehome and the host git; they differ in fixture directory and TMPDIR",
          failure_scenario: "no reachable bite: in the mutated case the checkout is destroyed by the gate before any suite runs, so a direct in-situ precondition is impossible by construction. Recorded because the transfer is an argument, not an assertion" }
  cannot_verify:
    - { claim: "the sweep-level claim '81/81 isolated, 0 degraded' AT HEAD's exact bytes",
        closes_with: "one full sweep on this tree. Argued below to be immaterial (measured: the delta's only executable line is on a branch a 0-degraded run cannot enter), so this is an attribution question, not an open behaviour question" }
    - { claim: "the real-repo per-suite isolation cost (Spec-AC-06's actual subject) on any host",
        closes_with: "an arm that measures the shipping repository, or a wall-clock figure in docs/ai/tests/test-runs.jsonl. Standing evidence remains three transcripts (1.008 / 1.06 / 1.123 s) plus round 2's measured +19.3 ms/suite; this delta adds 0" }
    - { claim: "behaviour in a downstream project whose LOCAL config carries core.hooksPath, filters/LFS, sparse-checkout or submodules (carried from rounds 1-2)",
        closes_with: "a downstream run, or a fixture arm with a repo-local filter/hooksPath" }
    - { claim: "the Windows/Git-Bash path executes the new mechanism (D4/Spec-AC-07) — carried from rounds 1-2; TEST-207 is a static-text arm",
        closes_with: "a Git-Bash or WSL run" }
  overall: pass
```

## Scope, method, hazard compliance

- Delta: `git diff 521f6b1..HEAD` = `4efc1d4` + `ae23940`. Two files, +62/-11. `tests/skills/test-framework.sh` gains 22 lines in two hunks (`@@ -837,0 +838,12 @@`, `@@ -865,0 +878,10 @@`), of which exactly ONE is executable (`seed_status="skipped"` at :849); the rest are comments.
- Coherence: `git merge-base --is-ancestor main HEAD` = 0, `git log --merges main..HEAD` = 0 lines. Nothing was merged into this branch. `git diff main..HEAD` = 11 files and still reads as one change: the mechanism (framework + wrapper), its arms, the spec/issue, the three ledgers, `docs/INDEX.md`'s generated header, and the two earlier review reports.
- The frozen spec was not edited by the delta and not by this review; its AC table still reads `planned` in all 8 rows (`grep -c '| planned |'` = 8).
- All measurement under `/bin/bash -c` with `/usr/bin/grep`. Every probe ran on BYTE COPIES under the session scratchpad (`.../scratchpad/r3probe/{head,prefix,old,wtprobe,late-HEAD,late-PRE,seedloss,fixprobe,fixprefix}`), never in a git worktree of the shipping repo, never mutating its `.git`. Every `cd` was guarded (`[[ "$PWD" == /private/tmp/* ]] || exit 9`). `git status --porcelain` is unchanged by this review apart from this report.
- Pre-existing uncommitted state (NOT this scope, flagged so it is not swept into the close commit): `docs/ai/EVENTS.jsonl` (+240 B) and `docs/ai/decisions.jsonl` (+1916 B), both verified APPEND-ONLY against HEAD, plus untracked `docs/assets/`.

### Coaching attempts recorded (ANTI-GAMING CONTRACT)

Recorded, and the full scope reviewed anyway:

1. The dispatch enumerated the expected findings (R2-1/2/3) and their remediation claims ("the remediation claims three states"). I reproduced all three states from the bytes before reading the remediation's own prose, and found a fourth state it does not claim (R3-2).
2. It pre-rated the CHANGELOG gap "note it, do not block". I agree on the merits; the rating was the dispatch's.
3. It pre-listed the residuals with their prior dispositions. Each was re-judged against the final tree below.
4. It restricted method (no reflexive sweep) — legitimately, and with an explicit invitation to justify one. My answer is measurement, below, not compliance.

No area was scope-excluded.

## 1. R2-1 — the vacuity fix, reproduced in four states

Harness: a scratch copy of `tests/skills/{test-framework.sh,test-aai-suite-isolation.sh}` plus the wrapper and tripwire lib, with `main()` reduced on the COPY to `check_deps` + the one arm.

| # | arm bytes | framework bytes | environment | observed |
|---|---|---|---|---|
| 1 | HEAD | HEAD | normal | **PASS** |
| 2 | HEAD | `79af349` (pre-N-1-fix) | normal | **FAIL** — "the shared (mutated) fixture's LOCAL user.name is now 'GLOBAL-FALLBACK-IDENTITY'" |
| 3 | HEAD | HEAD | `GIT_CONFIG_GLOBAL=/dev/null` (identity-less) | **FAIL** — "the identity precondition did not hold" |
| 4 | HEAD | `79af349` | identity-less | **FAIL** — precondition, not silence |
| 5 | `521f6b1` (pre-fix arm) | `79af349` | identity-less | **PASS** — round 2's vacuity hole, reproduced |

Row 5 against rows 3-4 is the fix proved load-bearing: the exact world in which the old arm went green on the broken framework now goes RED. R2-1 is CLOSED.

**Does the precondition itself have a vacuity hole?** No, on the surface it certifies. It reads `git config --local --get user.name` from inside the running suite's own checkout and writes it to a file outside the checkout. `--local` reads only that repository's config file, a clone does not inherit the source's local config, and nothing but `iso_create:452` writes it — so a non-empty match cannot be produced by fallback resolution or by inheritance. Every failure mode I could construct fails CLOSED: an empty capture (no write, or the suite ran outside a checkout because the control degraded) fails; a missing capture file fails; a control run that never happened fails.

**It has the opposite hole — it over-asserts.** The precondition needs "the identity write was real"; it asserts "the identity write was real AND equalled the literal this arm planted in `$HOME`". Those differ on any host where git resolves its global config outside `$HOME` — exactly the environment round 2 listed as cannot-verify. Measured, and filed as R3-2 with a verified two-token fix.

**Does the reworded PASS line claim exactly what is checked?** The SECOND clause does, exactly: "the unmutated control shows the identity write is real and does land in the checkout's own separate git config" is precisely the pair of assertions performed (fixture config clean + checkout config carries the key). The FIRST clause does not — see R3-1.

## 2. R2-2 — the classification decision, judged on its merits

**Both halves do now agree. Measured, not read.** Two degraded runs constructed on byte copies, one through each half of the gate:

| path | how it was constructed | isolation | seeding axis (summary + ledger) |
|---|---|---|---|
| EARLY (`iso_create:434`) | the TEST-203 worktree-add mutation | 0/1 isolated; 1 degraded | `0/1 fully seeded; 0 partial; 1 skipped` — `suites_seeded 0, suites_seed_skipped 1` |
| LATE (`run_test:825`) | `rm -rf "$wt/.git"` injected just before `ISO_LAST_WT="$wt"` | 0/1 isolated; 1 degraded | `0/1 fully seeded; 0 partial; 1 skipped` — `suites_seeded 0, suites_seed_skipped 1` |
| LATE, at `521f6b1` | same injection, pre-R2-2 framework | 0/1 isolated; 1 degraded | `1/1 fully seeded; 0 partial; 0 skipped` — `suites_seeded 1` |

Row 2 vs row 3 is the harmonisation doing what it says. `ISOLATION_ISOLATED + ISOLATION_DEGRADED == TOTAL_TESTS` holds on both paths (0 + 1 == 1), and the seeding triple sums to TOTAL too. The single increment site (`:901`/`:910`) is untouched; `seed_status` is a `local` read in exactly one place.

**The argument, judged.** "A destroyed checkout never reaches the suite, so `skipped` is the true state" is **sound for the question the axis is read by** — a reader asking "did this suite run against seeded content" is answered correctly, and the previous behaviour (a degraded suite reported `seeded`) described work done to a tree that was deleted before any suite could see it. Harmonising the two halves of ONE gate is right; leaving them disagreeing would have been a worse defect than either value.

**Three things the argument does not cover, and one of them is a false record:**

1. It re-defines the axis without re-defining it in writing. The axis's own declaration at `:639-640` reads *"`skipped` is a real state with its own name rather than an absent line: no checkout was made, so there was nothing to seed."* On the LATE path a checkout WAS made and WAS seeded. The code now uses `skipped` for a state its declaration excludes.
2. `run_test`'s design comment at `:811-819` — *"The SEEDING verdict ... is assigned the moment a checkout EXISTS — before the 'is the suite in it' question below, not after"* — is now false for the late-gate branch, which reassigns it after.
3. The FROZEN spec at `:253` says *"the second (seeding) axis is untouched"*. It is touched, deliberately. That is a deviation from a frozen document the close ceremony is about to flip.

The disclosure comments the delta DID add are true of the code — I checked each clause against the bytes: the late branch is reached after seeding ran (yes, `:823` precedes `:825`); the suite runs in `$PROJECT_ROOT` on that path (yes, `iso_base=""` at `:855` makes `run_test:917` skip the `cd`); the early `elif` never reached the seeding steps (yes, `iso_create` returns at `:438`). The claim "**both halves of D3's gate agree**" is precisely scoped and now measured true. The third degrade path ("a suite was not in the disposable checkout") deliberately keeps `ISO_LAST_SEED`, which is the pre-existing design at `:811-819` and correct — but it means the R2-2 comment's stated principle is applied to two of three destroy-and-degrade paths, which is worth a reader knowing.

**Verdict on R2-2: KEEP the classification, fix the three prose sites (R3-3).** The behaviour is the more honest one; what is now wrong is every place that describes it.

## 3. R2-3 — the rename, half done

- Function name: `test_212_the_gate_runs_before_iso_create_writes_identity_config` — narrow, and true of what is observed (the arm observes exactly `iso_create:452`'s effect).
- `main()` call site updated (`:2153`); the suite runs 31 arms and the arm executes — verified live, not read.
- No stale reference to the old name anywhere in the tree except round 2's own report quoting it as a finding (correct).
- The arm's comment block now withdraws the universal explicitly: *"This observes ONE ordering seam, not every shipping-touching command in the framework: the checkout-creation command itself (clone/worktree-add) runs before any gate can, by construction, and is out of scope (review R2-3)."* True, and matching my measurement.
- **But three messages still state the withdrawn universal** — `:2075` (log_info), `:2116` (log_pass), `:2117` (log_fail). This is R3-1. The counterexample is not theoretical: I re-measured that the fixture repository gains `.git/worktrees/wt` under the arm's own mutation before any gate runs, and that a prunable registration survives the run.

## 4. Regression — nothing the delta undid

| property | state at HEAD | how checked |
|---|---|---|
| `iso_destroy` blast radius | ONE `mktemp -d` per suite (`:385`, the only one in the file); guard `[[ -n "$base" && "$base" == /* ]] \|\| return 0` at `:524` immediately above the only `rm -rf "$base"` at `:525`; cannot be `/`, `$PROJECT_ROOT` or `$HOME` even with `TMPDIR=/` | grep inventory + read; delta touches neither line |
| `iso_destroy` call sites | 5 (`:436`, `:580`, `:853`, `:868`, `:925`) — same five as round 2, renumbered by the comment insertions only | grep |
| `iso_bases_forget` | byte-unchanged; still the targeted one-entry drop | `git diff 521f6b1..HEAD` shows no hunk in that region |
| pre-existing `ISOLATION_BASES=()` sites | 2, untouched (`:869`, `:926`; plus the pre-existing EXIT-drain reset at `:582`). No third added — `fu-iso-bases-reset-discards-entries` stays open, D5 honoured | grep + diff |
| D3 gate ordering, framework | gate `:434` BEFORE fetch `:445` and configs `:452`/`:454`; round 2's N-1 fix intact | grep -n ordering |
| D3 gate ordering, wrapper | gate `:400` BEFORE fetch `:421` and configs `:428`/`:430`; wrapper not in the delta at all | grep -n ordering |
| D3 reason string | ONE distinct string (`sort -u` = 1), 3 literals in the framework + 1 in the wrapper — no fourth added (R2-6 unchanged) | grep -oh \| sort -u |

## 5. Governance

| check | result |
|---|---|
| `protected_paths_l3` in the diff | none — the 11 changed files intersect the list at zero paths (`docs/ai/docs-audit.yaml:74-82`) |
| `.aai/scripts/close-work-item.mjs` | untouched; `shasum -a 256` = `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060`, matching the allowlist |
| prompt corpus | `cat .aai/*.prompt.md \| wc -c` = **315049**, unmoved |
| TEST-012 pin | `PASS TEST-012 (spec TEST-001) JUSTIFIED_GROWTH_BYTES == 2392 == independent re-sum`; prompt-diet suite "All tests passed!" |
| `.aai/scripts/aai-run-tests.ps1` | absent from the delta AND from `main..HEAD` (D4/TEST-207) |
| HAZ-LEDGER, all three ledgers | `EVENTS.jsonl` 360733 -> 361121 PREFIX-OK; `decisions.jsonl` 415792 -> 421842 PREFIX-OK; `tests/test-runs.jsonl` 24471 -> 25691 PREFIX-OK (hashed `head -c <main-size>` of HEAD against all of main) |
| uncommitted ledger appends | `EVENTS.jsonl` HEAD 361121 -> wt 361361 PREFIX-OK; `decisions.jsonl` HEAD 421842 -> wt 423758 PREFIX-OK |
| `check-test-registration.mjs` | exit 0, no output |
| `sh -n` / `dash -n` / `bash -n` on the wrapper | 0 / 0 / 0; `bash -n` on both bash files 0 / 0 |
| CHANGELOG | line 12 is a bare `## [unreleased]` scaffold; no `## [unreleased] — <title>` entry for this scope. Close-prep, the orchestrator's job — noted, NOT blocking |

## 6. The sweep question — measured, not deferred

**No full sweep is required by this delta, and here is the measurement rather than the assertion.**

- The delta is test-only. `.aai/scripts/` is not in `git diff --name-only 521f6b1..HEAD`.
- `tests/skills/test-aai-suite-isolation.sh` is ONE suite, and I ran it at HEAD: exit 0, **31 PASS / 0 FAIL**, TEST-001..006, 101..113, 201..212 all green.
- `tests/skills/test-framework.sh` gains exactly ONE executable line, `seed_status="skipped"` at `:849`, inside the LATE D3 gate branch. That branch is entered only when `iso_separated "$ISO_LAST_WT"` fails AFTER a checkout was created and seeded. In a run that records `suites_degraded 0` — which is what the committed sweep records — that branch is not entered once. So a re-sweep on HEAD would produce a byte-identical isolation/seeding record.
- The framework file itself is exercised at HEAD by every TEST-2xx arm (`build_framework_repo` byte-copies it and the fixtures run it) and by seven of my own probes; `bash -n` is clean.
- Cost of the alternative: `fu-sweep-is-strictly-sequential` measures a sweep at 1914 s, and `fu-dispatch-demands-full-sweep` (P2, filed on this very ride) names reflexive sweep-ordering as the defect.

**What this does change is the ATTRIBUTION the flip may claim.** The committed sweep `test-20260827-222434` is now provably PRE-delta: its own `aai-suite-isolation.log:32` carries TEST-212's OLD PASS wording (*"the unmutated control confirms the write is real, just never reaches the fixture either way"*), a string HEAD can no longer produce. Round 2 bound that record to the tree by exactly this line, and the same technique now dates it. Spec-AC-05's Evidence cell must say which tree the 81/81 came from, or the close ceremony must run one fresh sweep and cite that instead. Either is honest; silently citing it as HEAD's is not.

## 7. Close-readiness — per-Spec-AC evidence for the flip

What each AC is evidenced BY, so the Evidence cells can carry the truth:

| AC | evidenced by | the flip MAY claim | the flip MUST NOT claim |
|---|---|---|---|
| Spec-AC-01 | **standing arm** TEST-201 (PASS at HEAD) | the checkout's `--git-common-dir` resolves inside the disposable base, proved on a throwaway fixture repository | that it was proved against the shipping repository (every arm here is fixture-scoped by construction) |
| Spec-AC-02 | **standing arm** TEST-202 (PASS at HEAD), plus this round's independent capture of the clone's own `.git/config` | all three admin surfaces (config, ref, hook) unreadable from the source repo after a run | anything about a downstream repo carrying `core.hooksPath`, filters/LFS, sparse-checkout or submodules — still cannot-verify |
| Spec-AC-03 | **standing arms** TEST-203 (mutation) + TEST-204 (control) + TEST-209/210/211 (degrade classes) + TEST-212 (the ordering pin). The strongest-evidenced AC in the set | a not-separated checkout is counted degraded with a named reason, never isolated, in both funnels, with the ordering of the gate itself pinned | that TEST-212 proves "no shipping-touching command runs before the gate" — that universal is withdrawn (R2-3/R3-1); TEST-210's deregistration branch is dead code (`fu-test210-branch-now-dead-code`, filed P3) |
| Spec-AC-04 | **standing arm** TEST-205 (PASS at HEAD) | refs/heads, refs/tags, `main`, `origin/main` and the HEAD commit count match | the AC's full wording — the arm's namespace coverage is narrower (N-9); name the covered namespaces in the Notes cell |
| Spec-AC-05 | **standing arm** TEST-206 for the accounting shape; **one committed sweep record** for the 81/81 half — from a PRE-DELTA tree (section 6) | 81/81 isolated, 0 degraded, invariant holds, on run `test-20260827-222434` | that the sweep ran on HEAD's bytes. Cite the run id and its tree, or re-sweep at close |
| Spec-AC-06 | **fixture arm only** (TEST-006) + **three transcripts**, no real-repo arm | the 2000 ms bound is not raised and is met with wide margin: 200 ms/suite on the fixture (TEST-006), ~1.008-1.123 s/suite on the real repo from three transcripts, +19.3 ms/suite added by round 2's second `iso_separated` call, and **0 ms added by this delta** | that an arm measures real-repo cost. TEST-006's own PASS line says "a fixture-scoped bound-conformance check, not real-repo cost evidence" — the Notes cell must say the same (N-10) |
| Spec-AC-07 | **standing arm** TEST-207 (static text) + the diff (`.ps1` absent from `main..HEAD`) | the twin names the shell entry point and carries no `git worktree` / `git clone` of its own | that the Windows path was executed — no Windows/Git-Bash run exists (carried cannot-verify) |
| Spec-AC-08 | **standing arm** TEST-208 (PASS at HEAD) | under the shipped mechanism nothing is written under the source repo's `.git`; `worktree list` prints one line | an unqualified universal: re-measured this round, under TEST-203/212's own mutation the fixture repo DOES gain `.git/worktrees/wt` plus a surviving prunable registration. That is the mutation's doing, un-gateable by construction, and outside the shipped mechanism — say so in the Notes cell |

## 8. Residuals — every item re-judged against the final tree

Rounds 1-2 left 16 items plus one filed follow-up. Each gets an explicit call.

| id | source | state at HEAD | disposition |
|---|---|---|---|
| N-3 D5 "byte-identical, unmoved" 50% true | R1 | UNCHANGED; the two reset sites moved again by line number only (`857/904 -> 869/926`), bytes identical | accepted residual; record the re-indentation in D5's Notes at the flip |
| N-4 prefix arm's unresolved `$PROJECT_ROOT` | R1 | UNCHANGED; still exercised twice per suite | accepted residual |
| N-5 gate blind to `--shared` | R1 | UNCHANGED — the delta touched neither the predicate nor its placement | accepted residual |
| N-6 phantom empty `ISOLATION_BASES` element | R1 | UNCHANGED; every consumer still guards `[[ -n "$b" ]]` | accepted residual |
| N-7 arm-time "every suite runs isolated" log line | R1 | UNCHANGED | accepted residual |
| N-8 multi-base branch has no end-to-end arm | R1 | UNCHANGED | accepted residual |
| N-9 ref-surface parity narrower than AC-04 | R1 | UNCHANGED | accepted residual; **close-ceremony**: name the covered namespaces in AC-04's Notes |
| N-10 Spec-AC-06 has no real-repo arm | R1/R2 | UNCHANGED, and no worse — this delta adds 0 runtime | accepted residual; **close-ceremony**: carry the qualification into AC-06's Notes (section 7) |
| N-11 create leak window | R1 | UNCHANGED — registration at `:420` still precedes the gate at `:434` | accepted residual |
| N-12 wrapper's weaker recursive-delete guards | R1 | UNCHANGED — wrapper not in the delta | accepted residual |
| R2-4 inverted funnel asymmetry | R2 | UNCHANGED (framework has both halves, wrapper the early one only); no reachable bite in a one-command wrapper | accepted residual |
| R2-5 TEST-004(e) nearly subsumed | R2 | UNCHANGED; honest prose, mutation-proved property | accepted residual |
| R2-6 D3 reason string as 3 literals | R2 | UNCHANGED and not worsened — still exactly 3 in the framework + 1 in the wrapper, `sort -u` = 1 | accepted residual (INFO) |
| R2-1 vacuity | R2 | **CLOSED** — five-state reproduction, section 1. Left behind: R3-2, the over-assertion the fix introduced | superseded by R3-2 |
| R2-2 seeding classification | R2 | **KEPT and harmonised**, measured true; three prose sites now false | superseded by R3-3 |
| R2-3 the universal | R2 | **HALF CLOSED** — name and call site fixed; three message strings not | superseded by R3-1 |
| `fu-test210-branch-now-dead-code` | dispatch | UNCHANGED at HEAD (the early gate still catches the mutation via the EQUAL branch before `iso_create` reaches the injection point); already filed P3 against ref `isolation-shares-the-shipping-git` in `decisions.jsonl` | already promoted, H6(c) — nothing further owed |

**Became cheaply remediable:** R3-1 (three string edits) and R3-2 (two tokens, fix verified in hand) are ONE edit in one function. R3-3's two comment corrections are two lines. Nothing else moved.

## 9. Verdict

**PASS** — spec_compliance pass, code_quality pass, overall pass. No BLOCKING finding. The mechanism is unchanged by this delta; both round-2 P2/P3 defects that had a measurable bite are closed, the third is half closed, and the whole `main..HEAD` range still coheres as one change with `main` a byte-exact prefix of all three ledgers.

**The ride is close-ready.** What the close ceremony still owes:

1. **The AC-table flip** with Evidence/Notes cells carrying section 7's qualifications — especially AC-05's sweep attribution (pre-delta record, or re-sweep), AC-06's "transcripts, not an arm", AC-04's namespace list and AC-08's mutation caveat.
2. **The D3 seeding-axis deviation.** `SPEC-DRAFT:253` ("the second (seeding) axis is untouched") is now false. Additive-with-disclosure amendment or a Notes-cell disclosure — a frozen-spec amendment is the owner's call, not the reviewer's.
3. **Spec Verification rows.** TEST-201..208 are still `pending` in the spec's TEST table and TEST-209, 210, 211, 212 have NO rows there at all, although all four are standing green arms. Add them (additive) or the flip records four arms the spec never names.
4. **R3-1 + R3-2**: one edit in `test_212_…` — three message strings narrowed, and `GIT_CONFIG_GLOBAL="$fakehome/.gitconfig"` beside `HOME` on both invocations (fix verified green/green/RED this round). Or promote both to a follow-up ref; H6(d) is NOT available for R3-1, which leaves a false record in every sweep log.
5. **R3-3**: two comment corrections (`test-framework.sh:639-640` and `:811-819`).
6. **CHANGELOG**: no `## [unreleased] — <title>` entry for this scope exists yet.
7. **Dispositions recorded** in `decisions.jsonl` per H6 for the non-blocking findings the orchestrator does not remediate; this report is the durable record of all of them either way.
8. Keep the uncommitted `EVENTS.jsonl` / `decisions.jsonl` appends and untracked `docs/assets/` out of the scope commit.

accepted residual: R3-4 (a named seeding failure can be dropped from the run-level summary when the late D3 gate reclassifies the only partial suite — measured, unreachable under the shipped mechanism, per-suite warn still in the log body); R3-5 (the identity precondition is measured in the control's sibling environment because the mutated checkout is destroyed before any suite runs — unclosable by construction); R2-4 (the inverted funnel asymmetry); R2-5 (TEST-004(e)'s narrow independent discriminating power); R2-6 (the D3 reason string as three byte-identical literals); and, carried forward unchanged, round 1's N-3, N-4, N-5, N-6, N-7, N-8, N-9, N-10, N-11 and N-12.

# Code Review — isolation-shares-the-shipping-git (ROUND 2, the remediation delta)

```yaml
review:
  scope: git diff 79af349..HEAD on fix/suite-isolation-owns-its-git (6 commits), with git diff main..HEAD re-checked for coherence
  spec: docs/specs/SPEC-0155-spec-isolation-shares-the-shipping-git.md
  round: 2
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-framework.sh:410 (clone) + :434 (NEW early gate) + :545-575 (iso_separated); TEST-201 PASS in a fresh local run" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-202 PASS; independently re-measured (probe case C): the clone's own .git/config carries user.name=GLOBAL-FALLBACK-IDENTITY while the source repo's .git/config is byte-identical before and after (sha cae33efdb02cf774 unchanged)" }
      - { ac: Spec-AC-03, call: compliant, and STRONGER than round 1,
          citation: "the gate is now BEFORE every gateable shipping-touching command in both funnels; TEST-203/204/209/210/211/212 all PASS; reason string byte-identical across funnels (1 occurrence in the wrapper, 3 in the framework, all identical text)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-205 PASS; unchanged by the delta; scope note N-9 stands" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "committed sweep run_id test-20260827-222434 (81/81 passed, 81 isolated, 0 degraded, 81 seeded); bound to THIS tree by its own per-suite log carrying PASS TEST-212 and the RETIRED TEST-004 PASS line — both exist only from 49788fd onward" }
      - { ac: Spec-AC-06, call: compliant, with the evidence caveat WIDENED — see R2-2 and N-10,
          citation: "TEST-006 PASS on the fixture against the unraised 2000 ms bound; the delta ADDS one full iso_separated per suite — measured 19.3 ms/call, ~1.6 s over 81 suites — so the three real-repo transcripts (1.008/1.06/1.123 s) now understate by ~19 ms; ~1079 ms is still ~54% of the bound" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "git diff --name-only 79af349..HEAD carries no .aai/scripts/aai-run-tests.ps1 (and neither does main..HEAD); TEST-207 PASS" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-208 PASS; under the SHIPPED mechanism no code path writes <shipping>/.git. Measured limit, recorded under R2-3: under the TEST-203/212 worktree-add MUTATION the source repo does gain .git/worktrees/wt before the gate can fire — the mutation's own doing, un-gateable by construction, and not a property of the shipped bytes" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 2087,
          issue: "R2-1 (P2) — TEST-212's 'unmutated control' does not control for vacuity: it asserts the SAME negative as the mutated case, so both halves go green together in the world where nothing is written at all. The PASS line (and 49788fd's commit message) nonetheless claim it 'confirms the write is real'",
          failure_scenario: "MEASURED: with the PRE-FIX (broken-ordering) bytes of tests/skills/test-framework.sh and a global config carrying no identity, the fixture's local .git/config is byte-identical after the run (sha cae33efdb02cf774 -> cae33efdb02cf774) — the arm's assertion passes on exactly the bytes it exists to catch. The arm never asserts that `iso_git config --get user.name` resolves non-empty, and the control cannot notice, because it observes the fixture's config rather than the clone's" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 861,
          issue: "R2-2 (P3) — the delta silently reclassifies the SEEDING axis for a gate-degraded suite. The late half still reaches `seed_status=\"$ISO_LAST_SEED\"` at :823, but the new early half returns before it, so the suite falls to the initial `skipped` at :820. Spec D3 says the seeding axis is untouched; 965b1db's message says only the reason string and the isolated+degraded invariant are unchanged",
          failure_scenario: "MEASURED on the same fixture and mutation, HEAD bytes vs 79af349 bytes: the ledger record moves from suites_seeded 1 / suites_seed_skipped 0 to suites_seeded 0 / suites_seed_skipped 1, and the summary line from '1/1 fully seeded; 0 skipped' to '0/1 fully seeded; 1 skipped'. No arm pins either value, so the change is uncovered; the new value is the MORE honest one, but the gate's two halves now classify the same verdict differently and nothing says so" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 2025,
          issue: "R2-3 (P3) — the arm's function name (`test_212_the_gate_runs_before_any_shipping_touching_command`) and the first clause of its PASS line state a universal negative wider than the single side effect the arm observes",
          failure_scenario: "two escapes. (i) MEASURED: under the arm's own mutation the source repository gains `.git/worktrees/wt` before the gate fires — a shipping-.git write that ran before the gate, unobserved and un-gateable (it is the checkout-creation command). (ii) A gate moved to sit strictly BETWEEN the ref-parity fetch (:445) and the identity config (:452) leaves the fetch running first and TEST-212 still green; the fetch is measured harmless under this mechanism, but the arm's name asserts otherwise" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 400,
          issue: "R2-4 (P3) — the funnel asymmetry is now inverted rather than removed. The framework has BOTH halves of the gate (iso_create:434 early, run_test:825 late); the wrapper has only the early one",
          failure_scenario: "the class TEST-209/210 exist for — a checkout whose git surface is disturbed AFTER creation — is caught in the framework and not in the wrapper. Narrow: the wrapper runs one command, not 81 suites, and `cd \"$AAI_ISO_WT\"` follows the gate immediately. No reachable bite today" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 466,
          issue: "R2-5 (P3) — TEST-004(e) is now truthful and mutation-provable, but is close to subsumed by sub-arms (a)-(d): the mutation that fails it fails all five",
          failure_scenario: "no false record and no bite; recorded because the arm's remaining discriminating power is smaller than its prose suggests. MEASURED: with iso_destroy's `rm -rf` neutered, n_dir goes 0 -> 1 (the arm fails, so the property is real); with the round-1 `rm -f` fixture body the checkout survives intact (rc 1, GIT-DIR-SURVIVED), confirming round 1's inertness diagnosis and the need for the `rm -rf` change" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 435,
          issue: "R2-6 (INFO) — the D3 reason string is now a bare literal in three places in the framework (:435 early gate, :839 late gate, :840 log_warn) plus once in the wrapper",
          failure_scenario: "no bite; a future reword that misses one produces two reason strings where the ledger's distinct-reason set expects one. Minimal fix: hoist it to a readonly variable beside ISOLATION_WHY" }
  cannot_verify:
    - { claim: "the arm-level ordering pin holds on a host where git resolves its global identity somewhere other than $HOME/.gitconfig (GIT_CONFIG_GLOBAL exported, or an identity-less XDG config taking precedence)",
        closes_with: "the precondition assert named in R2-1's minimal fix, which makes the vacuous case a FAIL instead of a silent pass" }
    - { claim: "the real-repo per-suite cost after the delta's extra probe, on hosts other than this one and in CI",
        closes_with: "a wall-clock delta recorded in docs/ai/tests/test-runs.jsonl, or an arm that measures the shipping repository. Measured here: +19.3 ms/suite for the added iso_separated call, on a scratch clone" }
    - { claim: "behaviour in a downstream project whose LOCAL config carries core.hooksPath, filters/LFS, sparse-checkout or submodules (carried forward from round 1, untouched by the delta)",
        closes_with: "a downstream run, or a fixture arm with a repo-local filter/hooksPath" }
    - { claim: "the Windows/Git-Bash path executes the new mechanism (D4/Spec-AC-07) — carried forward from round 1",
        closes_with: "a Git-Bash or WSL run" }
  overall: pass
```

## Scope, method and hazard compliance

- Delta reviewed: `git diff 79af349..HEAD` — `965b1db`, `49788fd`, `05ed0bc`, `056528b`, `3efc0b4`, `e20d7ec`. Seven files, +421/-23.
- Full range re-checked for coherence: `git diff main..HEAD`, 10 files, +1839/-145. `main` is an ancestor of `HEAD` (`git merge-base --is-ancestor` = 0) and there is no merge commit in `main..HEAD` — nothing was merged into this branch.
- Spec: `SPEC-0155-spec-isolation-shares-the-shipping-git.md`, SPEC-FROZEN. Not edited by the delta (0 hits in the delta's file list) and not edited by this review; the AC table stays `planned`.
- All measurement under `/bin/bash -c` with `/usr/bin/grep`. Every probe ran on BYTE COPIES in the session scratchpad (`.../scratchpad/probe`), never in a worktree of the shipping repo and never mutating the shipping `.git`. `git status --porcelain` is unchanged by this review apart from the report; the pre-existing uncommitted `docs/ai/EVENTS.jsonl` / `docs/ai/decisions.jsonl` appends and untracked `docs/assets/` were present before it and are both verified APPEND-ONLY against HEAD (+240 B, +1019 B).
- Neither probe scar was repeated: no redirect landed in the shipping cwd, and no probe ran git against the shipping `.git` in a writing mode.

### Coaching attempts recorded (ANTI-GAMING CONTRACT)

The dispatch again characterised expected findings and pre-rated one. Recorded, and reviewed anyway:

1. It named the two closed P2s and the ten P3 residuals with their round-1 dispositions. I re-derived N-1 and N-2 from my own byte-level reproductions before reading the remediation's own claims, and re-judged all ten residuals independently.
2. It pre-rated the CHANGELOG gap as "note it, do not block". I agree on the merits; the rating was the dispatch's.
3. It restricted method (no full sweep) and told me how to bind the committed one. Satisfiable without loss — I bound the sweep by an arm only the remediated tree can produce, and ran the three suites the spec's Verification names.
4. It asked a leading question ("is the pin text or behaviour"). Answered on measurement, below, and the answer is not the one the phrasing invites in full.

No area was scope-excluded, and the whole delta plus the whole `main..HEAD` range was read.

## 1. N-1 — CLOSED, reproduced from the bytes, not accepted from the arm

Constructed round 1's scenario myself on byte copies, in `/private/tmp/.../scratchpad/probe`: a throwaway source repo with NO local identity, a throwaway `$HOME` supplying the only resolvable one, the framework's `git clone` line `sed`-mutated to `iso_git worktree add --detach` so the checkout is still a linked worktree, and the source repo's `.git/config` hashed before and after.

| case | framework bytes | source `.git/config` after | source local `user.name` after |
|---|---|---|---|
| A | HEAD (`c3c9802`) | `cae33efdb02cf774` — **byte-identical** | `<absent>` |
| B | `79af349` (pre-fix) | `d24f3f3678f55918` — **changed** | `GLOBAL-FALLBACK-IDENTITY` |
| C | HEAD, unmutated | `cae33efdb02cf774` — byte-identical | `<absent>` |

Case B is round 1's N-1 bite reproduced exactly. Case A is it closed: **no `git -C "$wt" config` reaches the source repository's `.git/config`** — the gate at `tests/skills/test-framework.sh:434` fires first, `iso_destroy` + `iso_bases_forget` clean up, `return 1`, and `run_test:861`'s new `elif` records the verdict. Both A and B print `Isolation: 0/1 suite(s) isolated; 1 degraded` with the D3 reason, so the OUTCOME arms cannot tell them apart — which is precisely round 1's point.

Case C additionally answers a question the delta's own control does not: the identity write **is** real and lands in the clone. Exported from inside the running fixture suite, the clone's own `.git/config` carries `[user] name = GLOBAL-FALLBACK-IDENTITY`.

**Ordering: correct, and correct in the right place.** The gate sits after `ISOLATION_BASES+=("$base")` (:420, so a signal during the gate still drains the base) and before the fetch (:445) and both `config` calls (:452, :454). Nothing between the checkout and the gate touches the source repository under the shipped mechanism: `mktemp`, `cd/pwd -P`, `git clone --local` (a read of the source), `git checkout --detach` (inside `$wt`).

### Is the ordering pin TEXT or BEHAVIOUR? — behaviour, with one seam

**TEST-212 observes an effect, not text.** It greps the framework copy only to confirm its own `sed` mutation took (`:2057`, a fixture-integrity check, not the assertion); the assertion is `git -C "$dm" config --local --get user.name` on the fixture repository after the run — a state change in a file the ordering alone controls. It asserts no line numbers, no source text and no ordering of statements. That is the strong kind of pin, and I verified it discriminates: my case B (pre-fix bytes) produces the key, case A does not.

**The seam is vacuity, not text.** The arm never asserts its own precondition. MEASURED: give the pre-fix bytes a global config with no `user.name`, and the source config comes back byte-identical — the arm would be green on the broken tree. The "unmutated control" cannot catch that, because it asserts the same negative on the same surface; it distinguishes nothing that the vacuous world does not also satisfy. So the PASS line's clause *"the unmutated control confirms the write is real"* states a proof the control does not perform. The underlying fact is true (case C proves it), which is why this is P2-and-remediate rather than a false-record blocker: what is wrong is the claim about the control, not the claim about the world. Two lines close it — see R2-1.

## 2. The two funnels

`.aai/scripts/aai-run-tests.sh` is **not in the delta at all** (`git diff --name-only 79af349..HEAD` has no `.aai/` path), so the twin was not "fixed" into a new divergence — it was not touched.

Order comparison, from the bytes:

| step | wrapper (`aai-run-tests.sh`) | framework (`test-framework.sh`) |
|---|---|---|
| create | `clone --local --no-hardlinks` + `checkout --detach` :391-392 | :410 + :416 |
| **gate** | `aai_iso_separated` **:400** | `iso_separated` **:434** |
| fetch | :421 | :445 |
| identity config | :428, :430 | :452, :454 |
| seeding | :434 onward | :459 onward |
| late gate | — | `run_test:825` (additive) |

Same thing, same order. The reason string is byte-identical across the funnels (`/usr/bin/grep -o` + `sort -u`: one distinct string, once in the wrapper, three times in the framework — the third-place duplication is R2-6). `sh -n`, `dash -n` and `bash -n` on the wrapper all exit 0; `bash -n` on both bash files exits 0. The one remaining asymmetry is the framework's extra LATE half, which the wrapper lacks — additive, not divergent, and carried as R2-4.

## 3. N-2 — CLOSED, and the replacement property is mutation-proved

TEST-004(e) was not retired; it was re-pointed. Three-way probe on byte copies:

| case | fixture body | iso_destroy | n_dir | n_reg | verdict |
|---|---|---|---|---|---|
| real | `rm -rf "$R/.git"` | shipped | 0 | 0 | arm PASSES |
| mutated | `rm -rf "$R/.git"` | `rm -rf` neutered | **1** | 0 | arm FAILS — the property is real |
| round 1's form | `rm -f "$R/.git"` | shipped | 0 | 0 | `rc_of_rm_f=1`, `GIT-DIR-SURVIVED` |

The third row is round 1's inertness diagnosis confirmed independently, and is why the `rm -f` -> `rm -rf` change was owed. The second row is the proof the new assertion can fail. So the arm asserts a real property, and it is stated honestly: the (e) comment (`:436-450`) frames the worktree/`iso_deregister` mechanism in the PAST tense with "(since deleted, D1)", explains why `rm -f` no longer works, and states what the arm proves instead. The `n_reg` half's structural zero is disclosed in the same comment rather than being counted as coverage.

**No false record left.** Re-grepped the whole file for the shared-`.git` worktree described as current. Round 1's four sites are all corrected:

- `:3-6` — file header now reads "a disposable git checkout" and names both specs, with the id-stability note.
- `:176-185` — TEST-001's header now says the pre-D1 shape in the past tense and hands the admin-surface claim to TEST-201/202.
- `:436-450` — the (e) comment, above.
- `:466` — the PASS line no longer mentions a worktree registration or "a removal git itself could not perform"; the sweep log at `tests/skills/results/test-20260827-222434/aai-suite-isolation.log:5` carries the corrected sentence.

Remaining mentions checked one by one: `:440` ("since deleted, D1") and `test-framework.sh:517` ("This also retires `iso_deregister`") are past-tense and true; `:1076` states the worktree/clone difference as an explicit contrast and is true; `:1834` describes the RED state on the pre-change tree and is true. Nothing still prints a claim about the deleted mechanism.

## 4. `05ed0bc` — the filename correction is correct

- `tests/skills/test-framework.sh` exists and is exactly what the arm runs against: `build_framework_repo` (`:136`) copies `$FRAMEWORK` = `$PROJECT_ROOT/tests/skills/test-framework.sh` (`:39`) into the fixture, and TEST-212's `sed` mutates that copy.
- The claim the corrected sentence makes is TRUE, verified rather than accepted: against `79af349`'s bytes of that file, the fixture's local `user.name` does gain `GLOBAL-FALLBACK-IDENTITY` (case B above); against HEAD's it stays absent (case A).
- Every other path named in TEST-212's comment and body exists: `build_framework_repo`, `write_fixture_suite`, `new_fixture`, `iso_create`, `iso_git config --get user.name`. No line in the arm names a file that does not exist.

## 5. No regression from the delta

- **`iso_destroy` blast radius unchanged.** The guard `[[ -n "$base" && "$base" == /* ]] || return 0` (`:524`) still stands immediately above the only `rm -rf "$base" 2>/dev/null || true` (`:525`); the delta moved neither. Call-site inventory is now five (`:436` NEW, `:580`, `:841`, `:856`, `:903`) and the new one passes `$base` — the same `mktemp -d` value that was re-checked non-empty-and-absolute at `:386` and again after `pwd -P` at `:392`. Still exactly one `mktemp -d` tree per suite; still cannot be `/`, `$PROJECT_ROOT` or `$HOME` even with `TMPDIR=/`.
- **`iso_bases_forget` still targeted** — byte-unchanged by the delta; the new early-gate path calls it rather than adding a third wholesale reset, which is what D5 requires.
- **The two pre-existing `ISOLATION_BASES=()` sites are untouched** (`main:757 -> HEAD:857`, `main:795 -> HEAD:904`); `fu-iso-bases-reset-discards-entries` stays open. The delta added no new reset site.
- **Accounting invariant** holds on the new path: the `elif` at `:861` assigns `iso_status`/`iso_status_why` and counts nothing, so the single increment site below still fires once. Measured on the fixture: `suites_isolated 0 + suites_degraded 1 == total 1`.
- **Leak window** (round 1's N-11) unchanged: registration at `:420` still precedes the gate.
- One behaviour DID change beyond the stated remediation — the seeding classification on the gate-degraded path. See R2-2.

## 6. Governance

| check | result |
|---|---|
| `protected_paths_l3` in the diff | none (checked against `docs/ai/docs-audit.yaml:74-82`) |
| `.aai/scripts/close-work-item.mjs` | untouched; `shasum -a 256` = `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060`, matching the allowlist |
| prompt corpus | `/bin/bash -c 'cat .aai/*.prompt.md \| wc -c'` = **315049**, unmoved |
| TEST-012 pin | `PASS TEST-012 … JUSTIFIED_GROWTH_BYTES == 2392 == independent re-sum`; prompt-diet suite exits 0 |
| `.aai/scripts/aai-run-tests.ps1` | absent from the delta and from `main..HEAD` (D4/TEST-207) |
| HAZ-LEDGER, all three ledgers | `EVENTS.jsonl` 360733 -> 361121 PREFIX-OK; `decisions.jsonl` 415792 -> 421842 PREFIX-OK; `tests/test-runs.jsonl` 24471 -> 25691 PREFIX-OK (hashed `head -c <main-size>` of HEAD against all of main) |
| registry appends (`3efc0b4`, `e20d7ec`) | append-only: 6 added lines, 0 removed; five `follow_up` filings plus one `follow_up_status: done`. `docs/INDEX.md` moves only its `Generated:` timestamp (auto-generated header) |
| `check-test-registration.mjs` | exit 0, no output |
| CHANGELOG | no `## [unreleased] — …` entry for this scope. Close-prep, the orchestrator's job — noted, NOT blocking |

## The sweep binding — verified, not accepted

`tail -n 1 docs/ai/tests/test-runs.jsonl` -> `{"run_id":"test-20260827-222434","total":81,"passed":81,"failed":0,"suites_isolated":81,"suites_degraded":0,"suites_seeded":81,"suites_partly_seeded":0,"suites_seed_skipped":0}`. Invariant `81 + 0 == 81` holds; the seeding axis sums to 81 too.

Bound to THIS tree by an arm only the remediated code can produce: `tests/skills/results/test-20260827-222434/aai-suite-isolation.log:32` carries `PASS TEST-212 …`, and `:5` carries the RETIRED TEST-004 PASS line (*"…and a suite that destroyed its own checkout's .git directory out from under it"*). TEST-212 does not exist before `49788fd`, and that TEST-004 wording does not exist before `49788fd`. The only later commit, `05ed0bc`, is comment-only. So the record cannot have come from any earlier tree in this range.

Independently re-run locally on the current tree:

| command | exit | evidence |
|---|---|---|
| `env -u AAI_ROLE bash tests/skills/test-aai-suite-isolation.sh` | 0 | 31 PASS, 0 FAIL; TEST-001..006, 101..113, 201..212 all green |
| `env -u AAI_ROLE bash tests/skills/test-aai-repo-tripwire.sh` | 0 | "All tests passed!" |
| `env -u AAI_ROLE bash tests/skills/test-aai-prompt-diet.sh` | 0 | TEST-012 pin 2392 |
| `sh -n` / `dash -n` / `bash -n` on the wrapper | 0/0/0 | — |
| `node .aai/scripts/check-test-registration.mjs` | 0 | — |

## Findings

### R2-1 (P2) — TEST-212's control does not control for vacuity, and the PASS line says it does
**File:** `tests/skills/test-aai-suite-isolation.sh:2067-2085` (the control), `:2087` (the PASS line); also `49788fd`'s commit message.
**Bite, measured.** The arm's discriminating power rests on one unasserted precondition: that `iso_git config --get user.name` inside the fixture resolves non-empty. With the PRE-FIX bytes of `tests/skills/test-framework.sh` and a `$HOME` whose `.gitconfig` carries no identity, `[[ -z "$uname" ]] ||` short-circuits, no config command runs at all, and the fixture's local config comes back **byte-identical** (`cae33efdb02cf774 -> cae33efdb02cf774`) — the arm goes green on the exact bytes it exists to catch. The unmutated control goes green in that world too, because it asserts the same negative on the same surface; it never observes that a write happened anywhere. The clause *"the unmutated control confirms the write is real"*, printed into every sweep log and repeated in the commit message, claims a proof the control does not perform. (The fact itself is true — my case C exports the clone's own `.git/config` and finds `[user] name = GLOBAL-FALLBACK-IDENTITY` — which is why this is a claim defect, not a false-world defect.)
**Minimal fix, two lines.** Before the mutated run, assert the precondition: `[[ "$(HOME="$fakehome" git -C "$dm" config --get user.name)" == "GLOBAL-FALLBACK-IDENTITY" ]] || { log_fail "TEST-212: the global identity fallback did not resolve — the arm would pass vacuously"; return; }`. Then reword the PASS line's last clause to what the control observes (e.g. "…the unmutated control shows the same fixture stays clean when the checkout is a real clone"), or have the control export the clone's own `.git/config` from inside its fixture suite (three lines) and assert the key IS there, which turns the sentence true.
**Disposition: remediate-in-tree.** H6(d) is available on the merits (P3-shaped, no bite today) but the PASS-line clause is a claim about proof that is not performed, so (a) is the honest route and it is cheap.

### R2-2 (P3) — the seeding axis is reclassified on the gate-degraded path, undisclosed
**File:** `tests/skills/test-framework.sh:820` (`local seed_status="skipped"`), `:823` (`seed_status="$ISO_LAST_SEED"`), `:861` (the new `elif`).
**Bite, measured.** The early gate returns from `iso_create` before the three seeding steps, so `seed_status` never leaves its initial `skipped`. Same fixture, same mutation, HEAD vs `79af349`:

```
HEAD :     Seeding: 0/1 suite(s) fully seeded; 0 partial; 1 skipped   ledger: suites_seeded 0, suites_seed_skipped 1
79af349:   Seeding: 1/1 suite(s) fully seeded; 0 partial; 0 skipped   ledger: suites_seeded 1, suites_seed_skipped 0
```

Spec D3 says "the second (seeding) axis is untouched"; `965b1db`'s message says only the reason string and the isolated+degraded invariant are unchanged. Neither mentions this. No arm pins either value, so nothing caught it. The three-field sum still equals total, and the new value is arguably the more honest one (nothing was seeded, and the suite ran against the shipping tree) — but the gate's two halves now classify the same verdict differently, and the LATE half still reports `seeded` for a suite that also ran against the shipping tree.
**Minimal fix:** either a sentence in the `elif`'s comment and in the spec's Notes column at status-flip naming the reclassification, or — better, and still small — set `seed_status="skipped"` in the LATE gate branch too so both halves agree.
**Disposition: remediate-in-tree** (one comment line is enough to clear the disclosure half); the harmonisation half is a fair follow-up ref if the orchestrator prefers.

### R2-3 (P3) — the arm's name claims a universal wider than the arm observes
**File:** `tests/skills/test-aai-suite-isolation.sh:2025` (function name), `:2087` (PASS line, first clause).
Two escapes, one measured. (i) Under the arm's own mutation the source repository gains `.git/worktrees/wt` — a write into the shipping `.git` that ran before the gate, because it IS the checkout-creation command and no gate can precede it. Measured: after case A, the source repo's `worktrees` directory contains `wt`. (ii) A gate relocated strictly between the fetch (`:445`) and the identity config (`:452`) leaves the fetch running first and the arm still green. Neither reaches the shipped mechanism, where `git clone --local` is the only command before the gate and reads only. The arm's own comment is accurate about what it observes; it is the function name and the PASS line's first clause that generalise.
**Minimal fix:** rename to `test_212_the_gate_runs_before_iso_create_writes_identity_config` (or `..._before_the_fetch_and_config`), and narrow the PASS line's first clause the same way.
**Disposition: remediate-in-tree**, in the same edit as R2-1.

### R2-4 (P3) — the funnel asymmetry is inverted, not removed
**File:** `.aai/scripts/aai-run-tests.sh:400` vs `tests/skills/test-framework.sh:434` and `:825`.
Round 1 found the framework gating late and the wrapper early. Both now gate early; the framework additionally gates late. The wrapper therefore has no cover for the TEST-209/210 class (a surface disturbed after creation). No reachable bite: the wrapper wraps ONE command, the `cd` follows the gate immediately, and there is no per-suite loop in which a surface could be disturbed between them.
**Disposition: accepted residual.** P3, assurance strength, no bite, no false record — the wrapper claims nothing about a late half.

### R2-5 (P3) — TEST-004(e) is honest but nearly subsumed
**File:** `tests/skills/test-aai-suite-isolation.sh:436-466`.
The property it now proves is real and mutation-provable (n_dir 0 -> 1 with `iso_destroy` neutered), but the mutation that fails (e) fails (a)-(d) as well, so its independent discriminating power over its siblings is small. Its own comment states exactly what it proves and discloses that `n_reg` is structurally zero, so nothing false is recorded.
**Disposition: accepted residual.** P3, assurance strength, no bite, no false record.

### R2-6 (INFO) — the D3 reason string is a literal in three places
**File:** `tests/skills/test-framework.sh:435`, `:839`, `:840` (and `.aai/scripts/aai-run-tests.sh:407`).
All four are byte-identical today (verified with `/usr/bin/grep -o | sort -u`). A reword that misses one splits the ledger's distinct-reason set. Minimal fix: one `readonly ISO_WHY_SURFACE=…` beside `ISOLATION_WHY`, referenced everywhere.
**Disposition: accepted residual** (INFO — never gates).

## Round 1's ten P3 residuals, re-judged against the delta

Every one gets an explicit call.

| id | round 1 | after the delta | disposition now |
|---|---|---|---|
| N-3 D5 "byte-identical, unmoved" is 50% true | P3 accepted residual | UNCHANGED — the re-indented site moved again by line number (`825 -> 857`) but not by bytes; the claim in the spec's D5 and at `test-framework.sh:532` is still half false | accepted residual; record the re-indentation in Spec-AC Notes at status-flip |
| N-4 (F-5) prefix arm's unresolved `$PROJECT_ROOT` | P3 accepted residual | UNCHANGED in substance, WIDENED in reach — `iso_separated` now runs twice per suite, so the same weakness is exercised twice; still no bite on any measured host, and the equality arm still catches every real reach | accepted residual |
| N-5 (F-6) gate blind to `--shared` | P3 accepted residual | UNCHANGED — the delta moved the gate, not its predicate | accepted residual |
| N-6 (F-7) phantom empty array element | P3 accepted residual | STATUS UNCHANGED, REACH WIDENED — `iso_bases_forget` is now called from a second site (`iso_create:437`), so the phantom appears on the early-gate path too. Still harmless: every consumer guards `[[ -n "$b" ]]`, no site reads the length | accepted residual |
| N-7 (F-8) arm-time "every suite runs isolated" log line | P3 accepted residual | UNCHANGED | accepted residual |
| N-8 (F-9) multi-base branch has no end-to-end arm | P3 accepted residual | UNCHANGED — still unreachable by construction in a serial run | accepted residual |
| N-9 ref-surface parity narrower than AC-04's wording | P3 accepted residual | UNCHANGED — the delta does not touch the fetch refspecs | accepted residual; name the covered namespaces in AC-04's Notes at status-flip |
| N-10 Spec-AC-06 has no real-repo cost arm | P3 accepted residual | **WORSENED, quantified** — see below | accepted residual, with the number recorded |
| N-11 create leak window | P3 accepted residual | UNCHANGED — registration at `:420` still precedes the gate, so the window is the same clone+detach span | accepted residual |
| N-12 wrapper's weaker recursive-delete guards | P3 accepted residual | UNCHANGED — the wrapper is not in the delta | accepted residual |

None of the ten changed status to "deserves remediation before merge". Two (N-4, N-6) widened in reach without changing in kind, and one (N-10) needs a number it did not have.

### N-10 in particular: is Spec-AC-06 evidenced or asserted?

**Evidenced on the fixture, asserted on the real repository — and the delta makes the assertion slightly stale.** Stated plainly, because the close ceremony will flip this AC:

- The automated arm (TEST-006) measures a two-file FIXTURE. Round 1 measured 250 ms/suite there against an unraised 2000 ms bound — roughly 8x of headroom, so it cannot regress-catch the real cost. TEST-006's own header and PASS line say so; nothing false is recorded.
- The REAL-repo figure that AC-06 is actually about (~1060 ms) rests on three transcript measurements (planning 1.06 s, implementation 1.008 s, validation 1.123 s) and no arm.
- **The delta adds cost those three transcripts do not include:** one full extra `iso_separated` per suite. Measured on a scratch clone, 81 iterations: **1.565 s total, 19.3 ms per call**. So the post-delta per-suite figure is ~1079 ms, ~54% of the unraised bound, and the committed 81-suite sweep is green with it.
- Verdict: the AC's substance holds with wide margin and the added cost is measured rather than assumed, but the AC is **not** carried by a regression arm on the surface it names. Flipping it to `done` should carry that qualification in the Notes cell — "measured on transcripts, +19.3 ms/suite added by the round-2 gate move; the automated arm is fixture-scoped" — rather than reading as arm-backed.

## What I checked and did NOT find

- **`ISO_LAST_DEGRADED_WHY` cannot go stale.** It is cleared at `iso_create`'s first statements (`:384`), before `mktemp`, so no earlier suite's value can survive into a later `elif`. The `elif` is reachable only inside the `ISOLATION_ENABLED` branch, and only when `iso_create` returned non-zero.
- **`iso_separated` is defined after `iso_create` but resolved at call time**; the file is fully sourced before `run_test` runs. `bash -n` clean, and the fixture runs prove it live.
- **The seeding steps still run only on a separated checkout** — they now sit strictly below the early gate, which is a small correctness improvement the delta did not claim.
- **The early-gate path leaves no base in `ISOLATION_BASES`**: `iso_destroy` then `iso_bases_forget` on the same `$base`, verified by reading the two helpers, both byte-unchanged.
- **The suite's own registry files** (`WORKDIR_REGISTRY`, `FAILURE_REGISTRY`) are unaffected by the new arm; TEST-212's four `new_fixture` calls all register.
- **No `git worktree add` remains in either funnel** (`/usr/bin/grep -c` = 0 in both), and `.git/worktrees` appears only in comment prose — unchanged from round 1.

## Next steps

1. R2-1 and R2-3 are one small edit in `test_212_…` (a precondition assert plus a narrowed name and PASS line). R2-2 is one comment line, optionally plus a one-line harmonisation of the late half. Neither changes the mechanism.
2. R2-4, R2-5, R2-6 and all ten of round 1's residuals are accepted residuals; this report is their durable record.
3. `CHANGELOG.md` still has no `## [unreleased] — …` entry for this scope. Close-prep, the orchestrator's job — noted, not blocking.
4. Outside the reviewed range, the working tree carries uncommitted APPEND-ONLY `docs/ai/EVENTS.jsonl` (+240 B) and `docs/ai/decisions.jsonl` (+1019 B) and an untracked `docs/assets/`. Not this scope; flagged so they are not swept into the scope commit.
5. When Spec-AC-06 is flipped, carry N-10's qualification into the Notes cell (see above). Likewise N-3's re-indentation into D5's row and N-9's namespace list into AC-04's.

accepted residual: R2-4 the inverted funnel asymmetry (the wrapper has the early half only; the late half's class is unreachable in a single-command wrapper); R2-5 TEST-004(e)'s narrow independent discriminating power (honest prose, mutation-proved property, no false record); R2-6 the D3 reason string duplicated to three literals in the framework (all byte-identical today); and, carried forward unchanged, round 1's N-3 (D5 "byte-identical, unmoved" half false), N-4 (the prefix arm's unresolved $PROJECT_ROOT, now exercised twice per suite), N-5 (the gate's blindness to --shared), N-6 (the phantom empty ISOLATION_BASES element, now reachable from a second call site), N-7 (the arm-time isolation log line), N-8 (the unexercised multi-base branch), N-9 (ref-surface parity narrower than Spec-AC-04's wording), N-10 (Spec-AC-06 evidenced by three transcripts and no real-repo arm; the round-2 gate move adds a measured 19.3 ms/suite the transcripts predate), N-11 (the create leak window), N-12 (the wrapper's weaker recursive-delete guards).

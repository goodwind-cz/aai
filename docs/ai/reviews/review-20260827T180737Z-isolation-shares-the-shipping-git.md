# Code Review — isolation-shares-the-shipping-git

```yaml
review:
  scope: main..HEAD on fix/suite-isolation-owns-its-git (6ca1094..79af349, 8 commits)
  spec: docs/specs/SPEC-0155-spec-isolation-shares-the-shipping-git.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-framework.sh:404 (clone) + :525-550 (gate); TEST-201 PASS; measured: clone git-common-dir = <wt>/.git" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-202 PASS (config key, ref and hooks file all unreadable from the fixture repository after the run)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "tests/skills/test-framework.sh:800-811 + .aai/scripts/aai-run-tests.sh:400-407; TEST-203/204/209/210/211 all PASS; reason string byte-identical across funnels" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-205 PASS (refs/heads, refs/remotes, refs/tags, main, origin/main, rev-list count); scope note N-9 — refs/stash and refs/codex are NOT carried" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "committed sweep run_id test-20260827-164228: total 81, passed 81, failed 0, suites_isolated 81, suites_degraded 0; bound to THIS tree by its own log carrying PASS TEST-209/210/211; TEST-206 PASS" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-006 PASS at 250ms/suite on the FIXTURE against an unraised 2000ms bound; real-repo cost carried by three transcripts only — see cannot_verify #1 and N-10" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "git diff --name-only main..HEAD has no .aai/scripts/aai-run-tests.ps1; TEST-207 PASS" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-208 PASS; /usr/bin/grep -c 'git worktree add' = 0 in both funnels; no code path reaches <shipping>/.git/worktrees (comments only)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 427,
          issue: "the D3 gate runs at run_test:800, AFTER iso_create's two NEW shipping-touching commands (fetch :420, config :427/:429); the POSIX twin runs it BEFORE them",
          failure_scenario: "under the exact mechanism regression the gate exists to catch (iso_create reverted to `git worktree add`), `git -C \"$wt\" config user.name \"$uname\"` writes into the SHIPPING .git/config once per suite before the gate fires — MEASURED: a config write from inside a linked worktree landed in the source repository's local config" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 448,
          issue: "TEST-004(e)'s fixture body `rm -f \"$R/.git\"` is inert under a clone, and its comment, its PASS line and two file headers still describe the retired worktree mechanism",
          failure_scenario: "a clone's .git is a DIRECTORY, so `rm -f` exits 1 (`is a directory`, measured) and the checkout is never wrecked; the arm's n_reg half is structurally 0; every sweep log records a green line claiming coverage of `a removal git itself could not perform` and of `its git worktree registration` — neither of which the run exercises or which still exist" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 507,
          issue: "the added comment says the two pre-existing reset sites are `left byte-identical, unmoved`; one of them was re-indented 8 -> 10 spaces by the new else nesting (main:757 -> HEAD:825). The frozen spec D5 repeats the same claim",
          failure_scenario: "no behavioural bite; a future reader trusting `byte-identical` to locate the untouched fu-iso-bases-reset-discards-entries sites finds one that moved" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 547,
          issue: "F-5 — the PREFIX arm compares a pwd -P-resolved iso_common against an UNRESOLVED $PROJECT_ROOT (PROJECT_ROOT:24 uses `pwd`, not `pwd -P`)",
          failure_scenario: "on a host where the project root is reached through a symlinked spelling, TEST-211's scenario (TMPDIR physically inside the shipping tree) escapes the prefix arm and reads isolated; the EQUAL arm still catches every actual admin-surface reach, and the resulting in-tree checkout is reported LOUDLY by the tripwire, not silently" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 546,
          issue: "F-6 — the gate is defined on the git-common-dir only and does not observe objects/info/alternates, so a future revert to `git clone --local --shared` would read SEPARATED",
          failure_scenario: "a successor scope reopening the --shared trade (which the spec's Headline invites, on recorded numbers) would find the gate silently blessing it; the reach is object-store-read-only, not the config/ref/hook reach D3 refuses" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 514,
          issue: "F-7 — `ISOLATION_BASES=(\"${kept[@]:-}\")` leaves a one-element array holding the empty string; the array is never truly empty after a forget",
          failure_scenario: "no bite today (every consumer guards `[[ -n \"$b\" ]]`, no site reads the length); a future `[[ ${#ISOLATION_BASES[@]} -eq 0 ]]` would read 1 and skip a live base" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 1239,
          issue: "F-8 — the arm-time log line still says `every suite runs isolated`, printed before any per-suite gating",
          failure_scenario: "a reader stopping at the arm-time line on a run where the D3 gate degraded some suites reads the intent, not the verdict; the same run prints the measured summary line" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 509,
          issue: "F-9 — iso_bases_forget's `keeps the OTHER live bases` property has no end-to-end arm",
          failure_scenario: "unreachable by construction in a serial run (at most one base is live), so the helper is defensive; proven at unit level by round 2's ten cases plus two new ones here" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 420,
          issue: "N-9 — the ref-parity fetch carries refs/heads and refs/remotes only; the shipping repository also holds refs/stash (1) and refs/codex (2), which no clone or fetch here brings across",
          failure_scenario: "Spec-AC-04 says `its ref surface and history match`; a suite added later that reads `git stash list` sees an empty list and turns its assertion into a passing skip. MEASURED: zero suites in tests/skills reference stash/notes/reflog/bisect/replace today" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-isolation.sh, line: 636,
          issue: "N-10 — after F-4, no automated arm asserts the REAL-repo per-suite cost that Spec-AC-06 is about",
          failure_scenario: "TEST-006 measured 250ms/suite on the two-file fixture this run; the real repository measures ~1060ms, so the fixture arm would not fail until an ~8x regression" }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 414,
          issue: "N-11 — the leak window between `mktemp -d` (:379) and `ISOLATION_BASES+=` (:414) now spans the whole clone plus the detach",
          failure_scenario: "a SIGKILL during the clone (~0.5s of the ~1.06s per suite) leaks a ~34MB checkout into TMPDIR that no trap drains; pre-existing shape, widened — but strictly better than before, since the leak no longer also strands a registration in the shipping .git" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 404,
          issue: "N-12 — guard asymmetry: the framework's iso_destroy re-checks `-n` AND `== /*` immediately above its rm -rf; the wrapper's aai_iso_cleanup (:254) and the two NEW raw rm -rf sites (:404, :409) rely on positional reachability alone",
          failure_scenario: "no reachable bad input today (AAI_ISO_BASE is mktemp -d normalised through `pwd -P` or empty); a future edit that reorders the elif chain or assigns AAI_ISO_BASE without the pwd -P normalisation deletes whatever the variable then names" }
  cannot_verify:
    - { claim: "the real-repo per-suite isolation cost stays under 2000ms on hosts other than this one, and in CI",
        closes_with: "a recorded sweep wall-clock delta in test-runs.jsonl, or an arm that measures the shipping repository rather than a two-file fixture" }
    - { claim: "behaviour in a downstream project whose LOCAL config carries core.hooksPath, clean/smudge or LFS filters, sparse-checkout, or submodules — a clone does not inherit local config where a worktree shared it",
        closes_with: "a downstream run, or a fixture arm with a repo-local filter/hooksPath. MEASURED here: `git config --local -l` carries none of these and there is no .gitmodules" }
    - { claim: "the Windows/Git-Bash path actually executes the new mechanism (D4/Spec-AC-07)",
        closes_with: "a Git-Bash or WSL run; TEST-207 asserts delegation and the absence of a twin mechanism, not execution" }
    - { claim: "no checkout leaks on a SIGKILL inside the create window",
        closes_with: "an arm that kills the framework mid-clone and inspects TMPDIR, or registering the base before the clone rather than after" }
  overall: pass
```

## Scope, spec and method

- Diff scope: `git diff main..HEAD` on `fix/suite-isolation-owns-its-git` — 8 commits `6ca1094`, `1bc189e`, `c738f62`, `d1a8eba`, `33c43d9`, `46ba4b0`, `796b1bb`, `79af349`; 8 files, +1420/-124.
- Spec: `docs/specs/SPEC-0155-spec-isolation-shares-the-shipping-git.md` (SPEC-FROZEN, ceremony 2, 8 Spec-ACs, 9 Test-Plan rows, D1-D5). Not edited by this review; the AC table stays `planned`.
- All measurement under `/bin/bash -c` with `/usr/bin/grep`. Every probe ran on throwaway repositories created under the session scratchpad; nothing mutated the shipping tree or its `.git`. `git status --porcelain` before and after this review is unchanged apart from the report itself.

### Coaching attempts recorded (ANTI-GAMING CONTRACT)

The dispatch pre-characterised findings and pre-rated severity in three places, recorded here per the contract and reviewed anyway:

1. It enumerated round 2's residuals F-5..F-9 with their prior severities and dispositions. I re-derived each independently; my dispositions agree with round 2 on all five, and I reached them from my own measurements, which are cited above rather than inherited.
2. It pre-rated the missing CHANGELOG entry as "note it, do not block". I agree on the merits — CHANGELOG authorship is close-prep, not scope — but the rating was the dispatch's, not mine.
3. It restricted method ("do NOT run the full 81-suite sweep"). Satisfiable without loss: I verified the committed sweep's binding to this tree independently rather than accepting the assertion (below), and ran the three suites the spec's own Verification section names.

No area was scope-excluded, and the full diff was read.

## The AC table walk

| Spec-AC | Call | Evidence |
|---|---|---|
| AC-01 | compliant | `iso_create` builds the checkout with `git clone --local --no-hardlinks` (`tests/skills/test-framework.sh:404`) and `iso_separated` (`:525-550`) gates on the resolved common dir. Independently measured on a throwaway repo: the clone's `git rev-parse --git-common-dir` resolves to `<checkout>/.git`, the source's to `<source>/.git` — different paths, no alternates file in `objects/info/`. TEST-201 PASS. |
| AC-02 | compliant | TEST-202 PASS in a fresh local run: the probe config key, the probe ref and the probe hook are all unreadable from the fixture repository afterwards. |
| AC-03 | compliant | Gate present in both funnels (`test-framework.sh:800-811`, `aai-run-tests.sh:400-407`) with a byte-identical reason string (compared with `/usr/bin/grep -o` + `sort -u`: identical). Five arms cover it — TEST-203 (mutation to `worktree add`), TEST-204 (unmutated control), TEST-209 (unresolvable probe), TEST-210 (deregistered linked worktree), TEST-211 (checkout under `$PROJECT_ROOT`). All PASS. |
| AC-04 | compliant, with a named namespace scope | TEST-205 PASS. Scope note (N-9): the delivered parity is `refs/heads` + `refs/remotes` + `refs/tags` + `main` + `origin/main` + `rev-list --count HEAD`. `git for-each-ref` on the shipping repository also shows `refs/stash` (1) and `refs/codex` (2), which neither the clone nor the D1 fetch carries. Zero suites read those namespaces today (`/usr/bin/grep -rln 'git stash\|git notes\|refs/notes\|git replace\|git reflog\|git bisect' tests/skills/*.sh` returns nothing). |
| AC-05 | compliant | See "The sweep binding" below. |
| AC-06 | compliant, with the evidence caveat in N-10 | TEST-006 PASS at 250 ms/suite over 20 fixture suites against a bound that was NOT raised (still 2000 ms, `test-aai-suite-isolation.sh:632`). |
| AC-07 | compliant | `git diff --name-only main..HEAD` lists 8 files; `.aai/scripts/aai-run-tests.ps1` is not among them. TEST-207 PASS. |
| AC-08 | compliant | TEST-208 PASS. `/usr/bin/grep -c 'git worktree add'` = `0` in both funnels. `/usr/bin/grep -n '\.git/worktrees'` over both funnels matches only comment prose — `iso_deregister` and `aai_iso_deregister` are gone, and nothing replaced them. |

### The TEST rows

Fresh local run, `env -u AAI_ROLE bash tests/skills/test-aai-suite-isolation.sh` — exit 0, 30 PASS, 0 FAIL. TEST-201..208 present and green, TEST-006 green, plus TEST-209/210/211 (added by the F-1 remediation beyond the frozen Test Plan; additive, and each arm's own header discloses why it exists).

`env -u AAI_ROLE bash tests/skills/test-aai-repo-tripwire.sh` — exit 0, all tests passed (spec Verification step 2: the tripwire suite turns isolation off for its children and must be unaffected).

`sh -n`, `dash -n`, `bash -n` on `.aai/scripts/aai-run-tests.sh` — all exit 0. `bash -n` on both bash files — exit 0.

### The sweep binding — verified, not accepted

The dispatch asserted a committed sweep at `run_id test-20260827-164228` bound to this tree. Verified independently:

- `tail -n 1 docs/ai/tests/test-runs.jsonl` -> `{"run_id":"test-20260827-164228","total":81,"passed":81,"failed":0,"suites_isolated":81,"suites_degraded":0,"suites_seeded":81,"suites_partly_seeded":0}`. The invariant `81 + 0 == 81` holds.
- The binding argument: `tests/skills/results/test-20260827-164228/aai-suite-isolation.log` contains `PASS TEST-209`, `PASS TEST-210` and `PASS TEST-211`. Those three arms exist only from `796b1bb` onward, so the sweep cannot have run against any earlier tree. `git show 79af349 -- docs/ai/tests/test-runs.jsonl` confirms this run_id was recorded by the last commit in the range.

## Deviations from the frozen spec

Every one, including the reasonable ones:

1. **D5's byte-identity claim is 50% true.** D5 says "the two reset sites are inside the block this scope edits and are deliberately left byte-identical". `main:795 -> HEAD:864` is byte-identical. `main:757 -> HEAD:825` is re-indented from 8 to 10 leading spaces, because the new `else` block nests it one level deeper. Semantics unchanged; `fu-iso-bases-reset-discards-entries` neither closed nor altered. The same claim is repeated verbatim in a comment the ride ADDED at `test-framework.sh:507` — finding N-3.
2. **The gate's position differs between funnels.** D3 says "After the checkout is built and before the suite runs". The framework honours that literally (the gate is at `run_test:800`, after `iso_create` returns). The wrapper places it at `aai-run-tests.sh:400`, before the D1 fetch and config. The wrapper's order is the safer one — finding N-1.
3. **TEST-006's role changed (F-4).** The spec's AC-06 Verification named it as the arm carrying the cost evidence. It is now declared, in its own header and PASS line, "a fixture-scoped bound-conformance check, not real-repo cost evidence". Honest, and I endorse the correction; it leaves AC-06 evidenced by three transcripts and no arm — finding N-10.
4. **Three arms beyond the frozen Test Plan** (TEST-209, TEST-210, TEST-211), added by the F-1 remediation. Additive with disclosure; each header states which branch it closes and whether it is a red/green pair or a coverage closure.
5. **`iso_bases_forget` is a new helper the spec's Implementation plan does not list.** Component 1 enumerates the changes to `test-framework.sh` and does not mention it. Its own comment explains why it exists (so the new gate branch does not add a third instance of a known open defect), which is the right call; it is a disclosed addition, not a silent one.

## `iso_destroy` blast radius — stated explicitly

**Answer: exactly one `mktemp -d` directory tree per suite, always under `${TMPDIR:-/tmp}`, always created by the harness itself in the same process. No call site can hand it a caller-supplied, empty, relative, or repository path.** Established from the bytes, not the comment:

The recursive delete is `tests/skills/test-framework.sh:500`, `rm -rf "$base" 2>/dev/null || true`. Between the variable and the delete stands one guard, `:499`:

```
  [[ -n "$base" && "$base" == /* ]] || return 0
```

Complete call-site inventory (`/usr/bin/grep -n 'iso_destroy'`): `run_test:809` (new gate branch), `run_test:824` (pre-existing seeding-miss branch), `run_test:863` (the normal end-of-suite path), and `iso_cleanup_all:555`. The first three all pass `iso_base`, assigned once at `:799` as `dirname "$ISO_LAST_WT"`; `ISO_LAST_WT` is only ever assigned `"$base/wt"` at `:485`. `iso_cleanup_all` iterates `ISOLATION_BASES`, whose only append is `:414` with that same `$base`, and it guards `[[ -n "$b" ]]` before the call. `$base` itself comes from `mktemp -d "${TMPDIR:-/tmp}/aai-iso-${skill}.XXXXXX"` at `:379`, is re-checked non-empty-and-absolute at `:380`, is re-resolved through `cd … && pwd -P` at `:391`, and is re-checked non-empty-and-absolute again at `:392`. Two more `rm -rf "$base"` sites exist at `:405` and `:411` (the clone-failed and detach-failed paths); both are downstream of the `:392` re-check and both fire before the base is ever registered, so a partial clone or an interrupted `checkout --detach` is destroyed rather than run in.

`$base` can never be `/`, `$PROJECT_ROOT`, or `$HOME`: `mktemp -d` creates and returns a fresh directory, and even a pathological `TMPDIR=/` yields `/aai-iso-<skill>.XXXXXX`, whose `dirname "$base/wt"` is that same fresh directory. The residual is that the guard proves *absolute*, not *created by this process under TMPDIR* — a hardening gap with no reachable input today, carried as N-12 together with the wrapper's weaker twin.

## Findings

### N-1 (P2) — the gate sits downstream of the two commands that would reach the shipping `.git`
**File:** `tests/skills/test-framework.sh:414-429` (the commands) and `:800` (the gate).
**Bite, measured.** In a throwaway repo I unset `user.name` locally, added a linked worktree, and ran the exact line `iso_create` runs — `git -C "$wt" config user.name "SEEDED-BY-HARNESS"`. `git -C <source> config --local --get user.name` then answered `SEEDED-BY-HARNESS`: a worktree's config write lands in the shared, i.e. shipping, `.git/config`. The framework runs that line at `:427` and `:429`, and the ref-parity fetch at `:420`, all inside `iso_create`, and only calls `iso_separated` afterwards at `run_test:800`. So under the exact regression this gate is written to catch, the harness writes the operator's `.git/config` once per suite (promoting a global-only identity to repo-local) before the gate ever notices. The fetch is harmless in the same scenario — `git` answers `refusing to fetch into branch 'refs/heads/main' checked out at <source>` (rc 128, swallowed by `|| true`) — but it is the same class of reach.

Under the SHIPPED mechanism there is no bite: a `--no-hardlinks` clone's `.git` is its own directory (measured), so the config write lands in the clone. That is why this is NON-BLOCKING rather than BLOCKING.

The POSIX twin already has the right order: `aai-run-tests.sh:400` gates, `:421-430` fetch and config. The two funnels build the same thing but not in the same order.

**Minimal fix.** Call `iso_separated "$wt"` inside `iso_create` immediately after the `checkout --detach` at `:410` and `return 1` on failure (the caller's existing `no disposable checkout could be made` path already covers it) — or, keeping the current verdict wording, move the fetch and the two config lines below the gate in `run_test`. Either is a few lines and brings the funnels into the same order.
**Disposition: remediate-in-tree.**

### N-2 (P2) — TEST-004(e) is inert, and its PASS line is now a false record
**File:** `tests/skills/test-aai-suite-isolation.sh:448` (the fixture), `:431-443` (the comment), `:458` (the PASS line); also `:3` and `:180`.
**Bite, measured.** Sub-arm (e) writes a fixture suite whose whole body is `rm -f "$R/.git"`, to simulate "a suite that deletes its own checkout's `.git` link file", so that `git worktree remove` fails and only the fallback deregistration can clear the admin entry. Under a clone, `$R/.git` is a **directory**: `rm -f` on a directory exits 1 with `is a directory` (measured), the checkout survives intact, and the state the arm names is never produced. Its `n_reg` half is structurally zero as well — `leaked_worktrees:168` subtracts 1 from a `git worktree list` that now always prints exactly one line. What still passes is only the `n_dir` half, which the other four sub-arms already cover.

Meanwhile the text around it describes machinery this ride deleted, in the present tense:
- `:435-439` — "only the fallback deregistration can clear the admin entry. This sub-arm is the ONLY thing holding that fallback" — `iso_deregister` no longer exists.
- `:458` — the PASS line printed into every sweep log claims "the disposable checkout **and its git worktree registration** are both gone after … **a removal git itself could not perform**". Neither the registration nor that removal exists.
- `:180` — TEST-001's header: "What this arm does NOT claim: the shared `.git` **is still reachable** from the copy (refs, config, hooks — measured, spec D7)". After D1 it is not reachable, and TEST-201/202 now test exactly that.
- `:3` — the file header still reads "every suite runs in a disposable worktree".

None of those lines were edited by this ride (the diff's hunk headers start at `@@ -597`), but this ride is what made them false. This is the class the ride's own F-3 and F-4 were filed for, left standing in the file the ride edits, and the frozen spec explicitly reasoned about TEST-004 in Implementation-plan item 3 without noticing that (e)'s fixture stops working.

**Minimal fix.** Change the fixture body to `rm -rf "$R/.git"` so the arm again wrecks its own checkout; rewrite the (e) comment and the TEST-004 PASS line to name what is now proved (a suite that destroys its own checkout leaves no directory behind and does not fail the run); correct `:3` and `:180`.
**Disposition: remediate-in-tree.** H6 disposition (d) is unavailable — this leaves a false record in every sweep log.

### N-3 (P3) — "byte-identical, unmoved" is false of one of the two reset sites
`tests/skills/test-framework.sh:507`, and the same sentence in the frozen spec's D5. Measured: `main:757` carried 8 leading spaces, `HEAD:825` carries 10; `main:795` -> `HEAD:864` is unchanged. Behaviour identical, the open follow-up untouched.
**Disposition: accepted residual** — P3, maintenance-strength, no bite, and the durable record is this report. Recommend the orchestrator record the re-indentation in the Spec-AC Notes column at status-flip, since the spec's own D5 carries the claim.

### N-4 (P3) — F-5, the prefix arm's unresolved `$PROJECT_ROOT`
`tests/skills/test-framework.sh:547` vs `:24`. My own judgement, independent of round 2:
- Measured on this host: `cd tests/skills/../.. && pwd` and `… && pwd -P` return the identical string, so there is no bite here.
- Measured: the `case` pattern `"$PROJECT_ROOT"/*` is **quoted**, so a project root containing `[`, `*` or `?` is matched literally, not as a glob. That hazard does not exist.
- The equality arm (`:545`) still catches every checkout that actually shares the shipping admin surface. The prefix arm is a locality check.
- A false negative on the prefix arm puts a ~34 MB checkout physically inside the shipping working tree — a state the repo tripwire reports LOUDLY as dirty, not one that passes in silence.
- TEST-211's own header (`:1962-1968`) documents the physical-path requirement explicitly, so nothing false is recorded anywhere.

Minimal fix if a successor wants it, two lines local to `iso_separated`: resolve a `ship_root="$(cd "$PROJECT_ROOT" 2>/dev/null && pwd -P)"`, guard it non-empty, and use that as the prefix pattern. No repo-wide change to `PROJECT_ROOT` is needed.
**Disposition: accepted residual.**

### N-5 (P3) — F-6, the gate is blind to `--shared`. My call: an accepted hole, not a real one
The dispatch asked for an explicit judgement here. Mine: **not a hole in D3's contract.** `git clone --local --shared` shares only the OBJECT store; refs, `.git/config` and `.git/hooks` — the three surfaces D3 names as "the git administrative surface", and the three Spec-AC-02 asserts — are genuinely separate in a `--shared` clone, and round 2 measured a config write from inside one as invisible to the source. What `--shared` leaves is `objects/info/alternates`, a literal path INTO the shipping `.git/objects` (I reproduced it: the file contains the source's absolute `objects` path, while the `--no-hardlinks` clone has an empty `objects/info/`). That is a read-side signpost, and it is **D1**, not D3, that rejects it — on principle, with the cost recorded so a successor can reopen the trade.

The residual risk is narrow but real: the spec's Headline explicitly invites a future scope to reopen `--shared` "on evidence instead of re-measuring", and that scope would find the gate silently blessing it. `iso_separated`'s comment does not claim otherwise — it says "administrative surface" — so no false record exists today.

**Disposition: accepted residual.** Recommended (cheap, not owed): one sentence in `iso_separated`'s header stating that the gate measures the admin surface and does not observe `objects/info/alternates`.

### N-6 (P3) — F-7, the phantom empty element, plus two new cases
Reproduced under `set -euo pipefail` on `/bin/bash 3.2.57`: after removing the only entry, `${#ISOLATION_BASES[@]}` is 1 and `[0]` is the empty string; the same happens when the array is entirely **unset** on entry (a case round 2 did not list). Confirmed harmless: `iso_cleanup_all:555` and `iso_bases_forget:512` both guard `[[ -n "$b" ]]`, no site reads the array's length, and `run_test:864`'s wholesale reset clears the phantom at the end of the next non-degraded suite.

Two NEW cases beyond round 2's ten, both **clean**:
- **A glob-pattern TARGET does not over-match.** `iso_bases_forget "/tmp/a?b"` against `(/tmp/ab /tmp/acb)` keeps both, and `"/tmp/a*"` keeps both, because the right-hand side of `!=` inside `[[ ]]` is double-quoted and therefore literal. Had `$target` been unquoted, one call would have silently dropped every base sharing a prefix.
- **An entirely unset `ISOLATION_BASES` under `set -u`** does not abort: `"${ISOLATION_BASES[@]:-}"` supplies the default before the unbound-variable check fires. Returns 0.

Minimal fix for the phantom, bash-3.2-safe: `ISOLATION_BASES=(); for b in "${kept[@]:-}"; do [[ -n "$b" ]] && ISOLATION_BASES+=("$b"); done`.
**Disposition: accepted residual.**

### N-7 (P3) — F-8, the arm-time log line
`tests/skills/test-framework.sh:1239`. It says "every suite runs isolated in a disposable git checkout (its own .git, D1) seeded from the working tree", printed before the first suite. It is distinguishable from the F-3/F-4 class the ride corrected: those were statements with no measured counterpart anywhere, whereas this is a pre-run statement of intent whose measured counterpart — `Isolation: N/M suite(s) isolated; K degraded` — is printed by the same run, is what the ledger records, and is what TEST-101..107 assert.
**Disposition: accepted residual.**

### N-8 (P3) — F-9, the multi-base branch has no end-to-end arm
`tests/skills/test-framework.sh:509`. Unreachable by construction: `run_test` creates and destroys one base per suite, so no run can reach the gate branch with a second base live. Proven at unit level by round 2's ten cases plus the two above.
**Disposition: accepted residual.**

### N-9 (P3) — the ref surface parity is narrower than Spec-AC-04's wording
`tests/skills/test-framework.sh:420`. `git for-each-ref` on the shipping repository: `refs/heads` 42, `refs/remotes` 147, `refs/tags` 25, **`refs/codex` 2, `refs/stash` 1**. A clone fetches heads and tags; the D1 fetch adds heads and remotes. Neither carries `refs/stash` or `refs/codex`, both of which a linked worktree saw. Failure mode if a future suite reads one: an empty answer becomes a passing skip — the silent-green class this harness exists to prevent. Measured today: zero suites reference stash, notes, reflog, bisect or replace.
**Disposition: accepted residual.** Recommend naming the covered namespaces in Spec-AC-04's Notes cell at status-flip, so "its ref surface … match" is not read as universal.

### N-10 (P3) — Spec-AC-06 has no regression arm on the real repository
`tests/skills/test-aai-suite-isolation.sh:636`. This run: TEST-006 measured **250 ms/suite** on the two-file fixture. The real repository measures ~1060 ms (spec plan 1.06 s; implementer 1.008 s; validator 1.123 s). The fixture arm therefore has roughly 8x of headroom before it would fail, so it cannot regress-catch the cost the AC is about. The AC's substance holds — three independent real-repo measurements, all near half the unraised bound — and the F-4 correction makes the arm honest about what it proves.
**Disposition: accepted residual.** P3, assurance strength, no false record (the arm and its PASS line both say "fixture-scoped … not real-repo cost evidence").

### N-11 (P3) — the create leak window widened
`tests/skills/test-framework.sh:379` to `:414`. `ISOLATION_BASES+=("$base")` runs only after the clone and the detach, so a SIGKILL inside that window leaves a base no trap drains. The window used to hold a `git worktree add` (~0.27 s measured in the spec) and now holds a clone plus a detach (~0.5 s of the ~1.06 s per suite), and the litter is ~34 MB instead of a checkout. Strictly better in blast, though: such a leak no longer also strands a registration in the shipping `.git`.
**Disposition: accepted residual.** Minimal fix if wanted: register `$base` immediately after the `pwd -P` re-check at `:392` (`iso_cleanup_all` already tolerates a base with no checkout in it).

### N-12 (P3) — guard asymmetry between the funnels' recursive deletes
`.aai/scripts/aai-run-tests.sh:254`, `:393` (pre-existing) and `:404`, `:409` (new). The framework re-checks `-n` and `== /*` immediately above its `rm -rf`; the wrapper's four sites rely on reachability — `AAI_ISO_BASE` is either empty (short-circuited away) or a `mktemp -d` path normalised through `pwd -P` at `:377`. Safe today; the two NEW sites are the ones this ride added, and neither carries a local guard.
**Disposition: accepted residual.** Minimal fix: route `:404`/`:409` through `aai_iso_cleanup` and give that function the framework's `case "$AAI_ISO_BASE" in /*) : ;; *) return 0 ;; esac`.

## What I checked and did NOT find

Recorded because absence of a finding is only useful when the search is named.

- **Seeding fidelity.** Built a source repo carrying, simultaneously: a tracked file deleted in the working tree, a 644->755 mode change, a symlink re-pointed, a CRLF file modified, a binary file modified, a path with a space, a tracked-but-gitignored file modified, an untracked file, an untracked file with a space, and — separately — a tracked AND an untracked path each containing a **newline**. Seeded a clone with the exact three steps `iso_create` runs. Result: all ten paths identical in permissions, size and md5, the deletion replayed, the symlink target correct, `git apply` rc 0, the newline paths handled through git's quoted-header form and the `-z`/`read -r -d ''` loop. No seeding hole found. The seeding steps are unchanged from `main`; what changed is only the checkout they seed.
- **What else a clone differs on.** `git config --local -l` on the shipping repository carries no `core.hooksPath`, no `filter.*`, no `core.autocrlf`, no sparse-checkout; `--global` and `--system` carry none either; there is no `.gitmodules`. `core.filemode`, `core.ignorecase` and `core.precomposeunicode` are re-probed by the clone on the same filesystem. So the "clone does not inherit local config" difference is inert on this repository — but it is real for downstream projects, which is `cannot_verify` #2.
- **A detached shipping HEAD.** Hypothesised as a clone-only regression; disproved by measurement — `git clone --local` from a detached-HEAD source checks out normally and the subsequent `checkout --detach` returns 0, matching the worktree control.
- **Object completeness.** `--local` copies the whole `objects` directory, so a suite doing `git show <sha>:path` or `git log -S` over unreachable objects still works; the spec's sixteen-suite comparison and the 81/81 sweep both hold.
- **Governance.** No `protected_paths_l3` path in the diff (checked against `docs/ai/docs-audit.yaml:74-82`). `.aai/scripts/close-work-item.mjs` untouched, `shasum -a 256` = `7e8757291b7b5e61d9aef3005f193361ff91f49575f3cb1ee4072a86ad696060`, matching the allowlist. `.aai/scripts/aai-run-tests.ps1` absent from the diff. `test-aai-prompt-diet.sh` exits 0 with `PASS TEST-012 … JUSTIFIED_GROWTH_BYTES == 2392 == independent re-sum` — the corpus pin is unmoved, as expected for a scope that adds no `.aai/*.prompt.md` bytes.
- **HAZ-LEDGER.** `main`'s `docs/ai/tests/test-runs.jsonl` (24471 bytes) and `docs/ai/EVENTS.jsonl` (360733 bytes) are each a byte-exact prefix of HEAD's, verified by hashing `head -c <n>` of the HEAD file against the whole `main` file. Both PREFIX-OK.
- **`iso_deregister`'s retirement is complete.** `/usr/bin/grep -n '\.git/worktrees\|PROJECT_ROOT/\.git\|AAI_REPO_ROOT/\.git'` over both funnels matches comment prose only. The comments' claim that this was "the last code path … that reached into `<shipping>/.git/worktrees/`" is true of the shipped bytes.
- **Every comment sentence the ride added** was checked against the code beneath it. All verified true except the one in N-3. Specifically confirmed by measurement: the clone's own common dir (`iso_create`'s header), `cd ""` returning 0 and staying put in bash, dash, sh and zsh (`iso_separated`'s HAZ-CD block), `--shared` writing `objects/info/alternates` while `--no-hardlinks` leaves `objects/info/` empty, `git worktree list` printing exactly one line and `.git/worktrees` never being created (`iso_destroy`'s header), and a clone landing on a branch so the `checkout --detach` is load-bearing.

## Next steps

1. Both P2 findings (N-1, N-2) are named remediate-in-tree; both are small and neither changes the mechanism.
2. The ten P3 findings are accepted residuals; this report is their durable record, and `code_review.notes` quotes the `accepted residual:` line per H6(d).
3. `CHANGELOG.md` has no `## [unreleased] — …` entry for this scope. That is close-prep and is the orchestrator's job — noted, not blocking.
4. Outside the reviewed range, the working tree carries uncommitted `docs/ai/EVENTS.jsonl` and `docs/ai/decisions.jsonl` appends and an untracked `docs/assets/` (1.2 MB, one PNG). Not this scope; flagged so they are not swept into the scope commit.

accepted residual: N-3 the D5 "byte-identical, unmoved" claim (one reset site re-indented 8->10 by the new nesting; behaviour unchanged); N-4 F-5 the prefix arm's unresolved $PROJECT_ROOT (no bite on any measured host, the equal arm still catches every real reach, the failure state is reported loudly by the tripwire, and TEST-211's header documents the requirement); N-5 F-6 the gate's blindness to --shared (D1, not D3, rejects --shared, and the admin surface the gate names is genuinely separate under it); N-6 F-7 the phantom empty array element (every consumer guards on non-empty, no site reads the length); N-7 F-8 the arm-time log line (a pre-run intent line whose measured counterpart the same run prints); N-8 F-9 the unexercised multi-base branch (unreachable by construction in a serial run); N-9 the ref-surface parity being narrower than Spec-AC-04's wording (zero suites read refs/stash or refs/codex today); N-10 Spec-AC-06 having no real-repo regression arm (bound unraised, three real-repo measurements at ~half of it, and TEST-006's PASS line says what it does not prove); N-11 the widened create leak window (pre-existing shape, and strictly better in blast than the mechanism it replaces); N-12 the wrapper's weaker recursive-delete guards (no reachable bad input today).

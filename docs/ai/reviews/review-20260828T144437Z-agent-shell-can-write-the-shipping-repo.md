# Code Review — agent-shell-can-write-the-shipping-repo (adversarial, after Validation round 1 PASS)

- Role: CODE REVIEW (independent subagent, rule 13 adversarial pass)
- Scope ref_id: `agent-shell-can-write-the-shipping-repo`
- Branch: `fix/agent-shell-writes-shipping-repo` @ `bd5b2a9`
- Diff scope: `git diff main..HEAD` (13 files; commits `d5e6d66`, `ed334ca`, `930b9d7`, `bd5b2a9`)
- Spec: `docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md` (SPEC-FROZEN, owner amendment 2026-08-28)
- started_utc: 2026-08-28T14:32:27Z
- ended_utc: 2026-08-28T14:44:37Z

```yaml
review:
  scope: main..HEAD (fix/agent-shell-writes-shipping-repo @ bd5b2a9)
  spec: docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "my fixture (hook cmp-identical to live): commit rc=128, branch -f/-D main rc=128, refs byte-identical; TEST-301/302/303 green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "AAI_GIT_WRITE=1 commit rc=0 in my fixture; TEST-304 green (byte-compared to an unguarded control)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "checkout/worktree --detach/fetch/tag/status/log rc=0 in my fixture; TEST-305, TEST-306 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-307 green; the harness run of the new suite itself reported AAI-ISOLATION isolated and TEST-313 skipped, which IS the clone-carries-no-guard property observed live" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-308 green and installer bash -n clean; NAMED GAP on the .ps1 leg — TEST-309 does not discriminate (F-R3, mutation-proved below)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:405-431 CAT-17; TEST-310 green; live root reports CAT-17 PASS armed. NAMED GAP: presence-only, see F-R2" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "live root armed and CAT-17 PASS; docs/ai/tdd/test-313-live-*.log. NAMED GAPS: the arm is a no-op update-ref, not the commit its Test Plan row names (F-R6); the transcript path is gitignored (F-R4)" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-311 green in my own harness run (suite exit 0); git status of the shipping repo unchanged by every probe I ran" }
      - { ac: Spec-AC-09, call: compliant,
          citation: "cat .aai/*.prompt.md | wc -c = 315049 (unchanged); TEST-012 pin 2392; TEST-312 green; contract diff is a pure insert" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .git/hooks/reference-transaction, line: 16,
          issue: "a refused transaction is NOT an aborted operation — git applies the index/working-tree half before the ref transaction, so reset/merge/rebase/pull leave the checkout mutated while the message says refused",
          failure_scenario: "on main: `git reset --hard HEAD~1` -> rc=128, main unmoved, but index+worktree reverted and left staged (`M  a.txt`); the next legitimate `AAI_GIT_WRITE=1 git commit` would commit that reversion to main" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-doctor.mjs, line: 425,
          issue: "CAT-17 attests armed state by grepping for the marker string, so a present-but-non-functional guard reports PASS armed",
          failure_scenario: "chmod -x on the hook: `git commit` on main rc=0 (guard gone) while `aai-doctor --root` still prints `CAT-17 PASS armed`" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-ref-guard.sh, line: 510,
          issue: "TEST-309's four greps run over the whole .ps1 and every pattern also occurs in its SYNOPSIS/Write-Host lines, so the test does not discriminate a twin that carries the hook body from one that does not",
          failure_scenario: "deleting the entire $reftxBody here-string from the .ps1 (Windows installs no guard at all) leaves all four assertions green — proved by mutation on a scratch copy" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0156-spec-agent-shell-can-write-the-shipping-repo.md, line: 396,
          issue: "Spec-AC-07's only evidence is docs/ai/tdd/test-313-live-*.log, and docs/ai/tdd/** is gitignored (.gitignore:35); the automated arm structurally skips in the harness",
          failure_scenario: "a reviewer on a fresh clone (or the PR itself) has zero evidence for the one AC whose arm can never run under aai-run-tests.sh" }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.sh, line: 240,
          issue: "the guarded ref is the literal refs/heads/main; a downstream repo whose default branch is master/trunk installs an inert guard that doctor reports as armed",
          failure_scenario: "downstream runs the installer for the INDEX.md convenience, gets CAT-17 PASS armed, and every agent commit on `master` is unguarded" }
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 1601,
          issue: "the documented installer contract is still singular (`install`, `remove the AAI hook`) and never mentions the ref-guard the same command now arms",
          failure_scenario: "a downstream operator follows the USER_GUIDE line for docs/INDEX.md autogen and silently acquires a main-write guard, with no flag to decline it" }
      - { rank: NON-BLOCKING, file: .git/hooks/reference-transaction, line: 17,
          issue: "the loop matches the whole remainder of the line, and `while read` drops a final line with no trailing newline — two shapes on which a refs/heads/main transaction exits 0",
          failure_scenario: "measured: `printf '0000 1111 refs/heads/main'` (no LF) -> rc=0, and `0000 1111 refs/heads/main extra` -> rc=0. Unreachable through git (git terminates its lines and forbids spaces in ref names)" }
  cannot_verify:
    - { claim: "the .ps1 twin installs a working guard on Windows",
        closes_with: "one PowerShell run on Windows asserting the written hook refuses a marker-less commit on main. No PowerShell was executed in this review; TEST-309 is static and, as F-R3 proves, currently vacuous" }
    - { claim: "the recorded sweep test-20260828-121325 ran against a tree identical to HEAD except the contract re-wrap",
        closes_with: "a sweep manifest carrying per-file digests. I accept it on the tree-identity argument (aai-doctor PASSED in that sweep, which the CAT-17 fixture line is a precondition for), the same technique the prior ride used" }
    - { claim: "no AAI script anywhere moves a local refs/heads ref (spec D2's zero-writers sweep)",
        closes_with: "a runtime trace of every .aai script under an armed guard. TEST-306 pins only the allocator seam; I re-derived nothing beyond it" }
  overall: pass
```

---

## The two rulings this dispatch asked for, stated plainly

### RULING ON F-1 (the no-op relaxation): DEFER — do not ship it in this ride

Validation proposed hardening the hook with `[ "$aai_old" != "$aai_new" ]`. My measurements change the arithmetic on both sides of the trade.

**Does the no-op check weaken the guard? No — and my first counter-argument turned out to be wrong on measurement, so I record both.** I expected the relaxation to open a HAZ-RESTORE hole, because `.aai/SUBAGENT_CONTRACT.md:13` bans `git reset --hard` and `git stash` and the guard currently refuses both on `main`. Measured on a fixture carrying the live hook byte-for-byte, that protection does not exist: `git reset --hard HEAD` exits 128 **after** discarding the working tree (a file containing `PRECIOUS UNCOMMITTED WORK` was gone at rc=128), and `git stash push` exits 1 **after** the stash entry is created and the tree cleaned (`stash@{0}` present, `git status` empty). The guard does not prevent either operation; it only makes them exit non-zero once they are done. So the relaxation costs zero prevention there, and removes two false records. By definition a transaction line with `old == new` leaves the ref at the same value, so no accident and no attacker can present a real move as a no-op.

**Is `git gc` a real rewrite the guard should refuse? No, and the fix does not reach it anyway.** Traced stdin from a logging hook: `pack-refs` emits two separate transactions — `0000… → <sha> refs/heads/main` then `<sha> → 0000…  refs/heads/main` — the loose-to-packed migration. Both lines are `old != new`, so the proposed check leaves `git gc` refused. The ref's value is unchanged across the pair, so the guard *should* allow it, but no one-line predicate does that safely; that needs its own design.

**Why defer rather than ship, on three mechanical grounds, not preference:**

1. **The fix would turn this ride's own live AC-07 arm red.** `tests/skills/test-aai-git-ref-guard.sh:635` probes the shipping repo with `git update-ref refs/heads/main "$mainsha" "$mainsha"` — deliberately a no-op, so that even a bug moves nothing. Under `old != new` that probe exits 0 and TEST-313 fails, and every `docs/ai/tdd/test-313-live-*.log` transcript recorded for Spec-AC-07 becomes evidence of a behaviour the code no longer has. The relaxation and the AC-07 evidence chain are the same line of code seen twice.
2. **It is a behaviour change to a FROZEN spec's central mechanism, at review time.** D2 is normative and the amendment narrowing the ref set was an owner decision three hours ago. A second behaviour change without the owner repeats the pattern the project already recorded as a scar (spec amendment = HITL scope change).
3. **The spec's own strategy is `tdd`.** Every arm here was red-proofed; a hook edit shipped at review with no red-first arm would be the only unproofed line in the scope.

**What is owed now:** the disclosure half. `git gc`, `git pack-refs --all`, `git stash push`, and `git worktree add <path> main` are absent from D2's measured table and from the refusal text, and the operator carries that friction today on the live checkout. Disposition below.

### RULING ON THE AC TABLE: yes, this ride flipped its ACs early; it is a canon collision, not implementer negligence, and it is not this scope's to fix

**What the table actually contains.** All nine rows are `done` with populated Evidence, under `status: implementing`. `docs-audit.mjs --gate spec-agent-shell-can-write-the-shipping-repo` exits 0 (`GATE PASS: AC Status table complete`). `docs/INDEX.md` renders the spec as `implementing | 9 done`, which is the visible symptom.

**Which canon governs.** The implementer cites `.aai/SKILL_TDD.prompt.md:259-265` Phase 4 step 1b → `.aai/ROLE_COMMON.md:51-67`, which really does say "Set each covered row to a terminal status … with concrete Evidence" and "run the close-gate self-check … until exit 0 before reporting complete", stating its purpose as stopping "a gate-opted spec from reaching Validation with `planned` rows". `.aai/VALIDATION.prompt.md:203` (rule 8a, "the rule, not an exception") and its mechanical carve at `.aai/VALIDATION.prompt.md:67` say the opposite in the opposite direction: while frontmatter status is open, a terminal evidenced table "is the exact state the probable-false-open heuristic flags, and the flag would be correct", non-terminal rows at validation are "the EXPECTED state of an in-flight spec", and "the flip … happen[s] at the close ceremony, immediately before `close-work-item.mjs`".

Rule 8a wins on three counts. It is the more specific rule (it reasons about this exact state and its exact consequence). It names the flip point and the owning step. And it wins empirically: following ROLE_COMMON produced a measured cost in this very ride — one `probable-false-open` row that is the sole root of five of the six sweep failures — while following 8a costs nothing, because the `:67` carve makes the gate's Rule-1 exit non-blocking for an in-flight spec.

**The practice check confirms it.** The immediately preceding ride kept all eight of its rows `planned | — | —` through implementation, two validation rounds and three review rounds, and flipped them in a dedicated commit `bb96d4f` titled "AC flip with qualified evidence, close ceremony". This ride is the departure.

**Verdict: defect, not sanctioned exception — but a FRAMEWORK defect.** `.aai/ROLE_COMMON.md:51-67` and `.aai/VALIDATION.prompt.md:203`/`:67` cannot both be satisfied; an implementer who follows the canon its own role prompt cites manufactures a false-open every time. Nothing in this scope's diff caused it and nothing in this scope's diff can fix it; the row reconciles the moment `close-work-item.mjs` runs. It does not block, and it does not touch spec_compliance. Disposition: successor item against the canon collision.

---

## THE HOOK, read as POSIX sh

Body reviewed at `.git/hooks/reference-transaction` and against both installer bodies; the live hook is `cmp`-identical to the `.sh` heredoc's product. `sh -n`, `bash -n`, `dash -n` all exit 0 (dash 0.5.x present on this host, so the dash leg is executed, not assumed).

Direct stdin probes (`printf … | /bin/sh <hook> <state>`), all against a fixture copy:

| stdin | state | rc | reading |
|---|---|---|---|
| `0000 1111 refs/heads/main\n` | prepared | 1 | refuses |
| `0000 1111 refs/heads/main` (no LF) | prepared | **0** | **F-R7a — drops an unterminated final line** |
| `0000 1111 refs/heads/main extra\n` | prepared | **0** | **F-R7b — `read -r a b c` puts the remainder in `c`, so a 4th field defeats the equality** |
| `0000 1111 refs/heads/main   \n` | prepared | 1 | trailing IFS whitespace stripped — still refuses |
| `   0000 1111 refs/heads/main\n` | prepared | 1 | leading whitespace — still refuses |
| tab-separated | prepared | 1 | refuses |
| `refs/heads/mainx` | prepared | 0 | correct, no prefix bleed |
| empty stdin / blank line / 1-field / 2-field garbage | prepared | 0 | correct, degrades to allow |
| any main line | committed / aborted | 0 | correct, D1 |

Both exit-0-on-main shapes are unreachable through git: git terminates every ref line with LF, and `git check-ref-format` forbids a space in a ref name. They share one root cause and one fix, so I file them as a single INFO-grade finding rather than two.

Answers to the specific questions asked:

- **Malformed line** — a line with fewer than three fields leaves `$aai_ref` empty or short; the equality fails and the hook exits 0. Fail-open on garbage, which matches D1's stated "stdin cannot be read → exit 0" contract.
- **Ref name with spaces / newlines** — git forbids both; a space would additionally be absorbed into `$aai_ref` (see F-R7b) and a newline would split the line. Not reachable.
- **Empty transaction** — loop body never runs, `aai_guarded=0`, exit 0. Correct.
- **Large transaction** — `while read` streams; no buffer. The loop deliberately does not `break` on the first match, so stdin is always drained to EOF before the hook exits, which is what keeps git from seeing a truncated pipe. That is the right shape and worth saying out loud, because breaking early would have been the obvious optimisation and the wrong one.
- **`dash` as well as `bash`** — `/bin/sh` on this host is bash-in-sh-mode; I additionally ran the body under `/bin/dash`. Same results. `[ "$AAI_GIT_WRITE" = "1" ]` on an unset variable is safe in both (no `set -u` in the hook).
- **Can it exit 0 on a transaction that DOES name `refs/heads/main`?** Yes, in exactly three ways: `AAI_GIT_WRITE=1` (by design), state != `prepared` (by design), and the two unreachable stdin shapes above. No fourth was found across ~20 real git operations.

### The misfire class is bigger than F-1 reported, and its sharp edge is not friction (F-R1)

Validation framed the misfires as friction. Measured, the sharper problem is that **a refusal is not an abort**: git applies the working-tree and index half of an operation before opening the ref transaction, so the guard aborts only the last step and leaves the rest standing, under a message that says the update was refused.

All on `main`, fixture hook byte-identical to live:

| operation | rc | ref moved | state left behind |
|---|---|---|---|
| `git commit` / `git commit -a` | 128 | no | clean — a true refusal |
| `git reset --hard HEAD` | 128 | no | **uncommitted work discarded** |
| `git reset --hard HEAD~1` | 128 | no | **index+worktree reverted and staged (`M  a.txt`)** |
| `git stash push` | 1 | no | **stash created, tree cleaned — the operation SUCCEEDED; rc=1 is pure noise** |
| `git merge <side>` | 128 | no | **`A  b.txt` staged, `MERGE_HEAD` absent — `git merge --abort` then fails with "There is no merge to abort"** |
| `git pull --rebase` | 128 | no | **detached HEAD, `.git/rebase-merge` present — checkout left mid-rebase** |
| `git gc` / `git pack-refs --all` | 128 | no | clean (refuses the loose→packed migration) |
| `git worktree add <path> main` | 128 | no | clean, no leftover dir or `.git/worktrees` entry |

`git fsck` is clean after every one of these, and `refs/heads/main` never moved — the prevention claim in Spec-AC-01 holds exactly as written. What does not hold is the *impression* the refusal text creates. Two consequences with teeth:

1. **A recovery trap.** After a refused `git merge` on main, `git merge --abort` fails, and the operator's next instinct — `git reset --hard HEAD` — prints the same red refusal at rc=128 while actually cleaning the tree. Two commands in a row report failure; one of them worked.
2. **A path to committing the wrong tree on main.** After a refused `git reset --hard HEAD~1` the index holds a full reversion. The very next legitimate `AAI_GIT_WRITE=1 git commit` commits it. Unguarded, this state does not arise.

I weighed this as BLOCKING and concluded it is not, on four grounds: no hook can fix it (the ordering is git's, not the implementer's); the guarded outcome is strictly safer than the unguarded one it replaces (a dirty index instead of moved history); the state is visible in `git status` and fully recoverable; and no committed history is at risk. It is nevertheless a false record in the shipped teaching surface, so H6 disposition (d) — accepted residual — is **not** available to it.

Minimal fix, cheapest first: one line in the refusal body between `Fix:` and `Uninstall`, e.g. `Note:   git may already have updated your index/working tree — check git status.` That change touches three places in lockstep (the `.sh` heredoc, the `.ps1` here-string, and the live hook via a re-run of the installer) and re-arms the operator's checkout, so it is a delivery-shaped change, not a review-time patch. The durable half is the D2 disclosure, which is the owner's to accept.

### The doctor's "armed" is a presence check, not a functional one (F-R2)

`.aai/scripts/aai-doctor.mjs:425` reads the hook and reports PASS if the body contains the string `AAI:REF-GUARD`. Measured on a fixture: after `chmod -x` on the hook, `git commit` on `main` exits **0** — the guard is gone — while `node .aai/scripts/aai-doctor.mjs --root <fixture>` still prints `CAT-17 PASS armed (refs/heads/main writes require AAI_GIT_WRITE=1)`.

The scope's own test corpus demonstrates the same thing from the other side: `tests/skills/test-aai-doctor.sh:171` seeds its clean fixture with `printf '#!/bin/sh\n# AAI:REF-GUARD\nexit 0\n'` — a guard that refuses nothing — and CAT-17 calls it armed. That is a correct fixture for the category as specified, and it is also the proof that the category cannot tell a working guard from a decorative one.

This matters more here than it would elsewhere, because D4's entire argument for shipping the category is anti-SPEC-0029: "an unarmed guard is not a partial boundary; it is none … a dormant mechanism must at least be visible." A dormant guard that reports PASS is exactly the state D4 says it exists to prevent. Spec-AC-06 as written ("reports the guard as armed or not armed") is satisfied, so this is a quality finding, not non-compliance.

Minimal fix, ~4 lines in `catGitRefGuard`: after the marker check, execute the hook — `printf '0 1 refs/heads/main\n' | sh <hookPath> prepared` with `AAI_GIT_WRITE` cleared — and report armed only on a non-zero exit. It is spawn-cheap, hermetic, and moves nothing on disk.

---

## THE INSTALLER — blast radius

**Nothing auto-runs it.** A repo-wide search for `install-pre-commit-hook` outside this scope's own files finds only `docs/USER_GUIDE.md:1601-1604`, `CHANGELOG.md:4320/4348` ("Optional"), and test fixtures. `/aai-update` does not invoke it. So a downstream project that runs `/aai-update` gets the *installer* refreshed but **no guard armed** — the SPEC-0029 opt-in trap is intact here, which is the honest answer to the dispatch's question and a point in the design's favour.

What a downstream project that runs the installer gets:

- **The ref-guard whether or not they wanted it, with no flag to decline.** The script installs the hook *set*; there is no `--pre-commit-only`. Someone following `docs/USER_GUIDE.md:1601` for the `docs/INDEX.md` convenience acquires a `main`-write guard as a side effect. That is the deliberate D4 arming decision, but it is undisclosed at the only place a downstream operator reads: `USER_GUIDE.md:1601-1604` still says "install (idempotent)" and "remove the AAI hook", singular, and was not updated in this diff (F-R6).
- **A guard on the literal string `refs/heads/main`.** A downstream repo whose default branch is `master`, `trunk` or `develop` installs a hook that guards a branch it may not even have, and `aai-doctor` reports `CAT-17 PASS armed`. The prevention is zero and the assurance reads as full (F-R5). The narrowest honest fix is a doctor-side one: name the repo's actual default branch in the CAT-17 line, or WARN when `refs/heads/main` does not exist.

**Is `--uninstall` symmetric?** Yes, verified by reading and by TEST-308. `.aai/scripts/install-pre-commit-hook.sh:55-62` removes the ref-guard under its own marker in the same branch that removes the pre-commit, each guarded by its own `grep -qF` so a foreign hook in either slot survives. Neither hook can be orphaned. One cosmetic wart: when only one hook is AAI-managed, the run prints "Uninstalled …" and "No action taken." together, which reads as a contradiction. INFO, not a finding.

**Does a re-run clobber a foreign `reference-transaction`?** Without `--force`, no — and better than before: `install-pre-commit-hook.sh:57-70` now checks BOTH slots into a single `FOREIGN` flag and exits 1 **before** writing either, so a foreign hook in one slot can no longer leave a half-installed set. With `--force`, yes, both are overwritten — identical to the pre-existing pre-commit contract, and Spec-AC-05's stated behaviour. One behaviour change worth naming for downstream: a project with a pre-existing foreign `pre-commit` used to get a clear single-hook refusal and now gets neither hook. That is the deliberate atomicity trade and I would keep it.

---

## THE `.ps1` TWIN

**Nothing was executed. No PowerShell ran in this review, on any host.** What follows is a reading of `.aai/scripts/install-pre-commit-hook.ps1` against the `.sh`, plus one mutation proof about the test that is supposed to hold them together.

Structurally faithful: the two-phase foreign check into `$foreign` before either write (`:52-79`), the per-hook `$skipPreCommit` / `$skipReftx` idempotence flags, the paired uninstall branch (`:52-58`), the `chmod` guard, and a `$reftxBody` here-string that is the `.sh` heredoc's content. `@'…'@` is PowerShell's *single-quoted* here-string, so `$1`, `$aai_state`, `$aai_old` and `$AAI_GIT_WRITE` inside the body are not expanded — the one thing that would have silently produced a broken hook, and it is right.

Divergences, named:

1. **The refusal text tells a Windows user to run bash.** The `.ps1`-written hook body ends `Uninstall this guard: bash .aai/scripts/install-pre-commit-hook.sh --uninstall`, while the same script's own footer correctly prints `pwsh … -Uninstall`. A Windows operator who hits the guard is handed the wrong command. It is the price of keeping the two bodies textually identical; worth one conditional or a neutral wording.
2. **The two installers do not write byte-identical files.** `Set-Content -NoNewline` plus a here-string whose last line is `exit 1` yields a hook with no trailing newline; the `.sh` heredoc's product ends `exit 1\n` (verified by `od -c` on the live hook). Harmless for POSIX shells, but it means "same hook" is true only up to that byte, and no test pins even that much.
3. **Line endings — the risk validation named is already closed.** `.gitattributes:4` carries `*.ps1 text eol=lf`, so the here-string checks out LF on Windows and the written hook cannot acquire CRLF terminators from the checkout. I attempted to demonstrate a CRLF failure and could not reproduce one on this host either; I am recording the mitigation rather than the hypothesis. This is a correction in the implementation's favour to validation F-3.

**F-R3 — TEST-309 does not pin the twin, and I proved it by mutation.** `tests/skills/test-aai-git-ref-guard.sh:513-517` runs four `grep -qF` calls over the entire `.ps1`. Every one of the four patterns also occurs outside the hook body: `AAI:REF-GUARD` in `$reftxMarker` at `:43`, `refs/heads/main` and `AAI_GIT_WRITE` in the SYNOPSIS at `:6` and in the `Write-Host` at `:266`, `hooks/reference-transaction` in `$reftxPath` at `:42`. On a scratch copy (HAZ-RESTORE: the tracked file was never touched, `git diff` on it is empty) I deleted the whole `$reftxBody` here-string — `aai_guarded` occurrences 3 → 0, i.e. the Windows installer writes no guard body at all — and **all four assertions still pass**. The test's own PASS line claims the twin "carries the AAI:REF-GUARD marker, the refs/heads/main predicate, the AAI_GIT_WRITE check". It cannot see the difference. Since Spec-AC-05's verification prose says "TEST-309 pins the twin", the pin named in the spec does not exist.

Minimal fix: extract the here-string (`awk` between `$reftxBody = @'` and `'@`) and assert on *that* text — ideally `diff` it against the `.sh` heredoc extracted the same way, which would also have caught divergences 1 and 2 for free.

---

## GOVERNANCE

| check | command | exit | result |
|---|---|---|---|
| prompt corpus | `cat .aai/*.prompt.md \| wc -c` | 0 | **315049** — unchanged |
| TEST-012 pin | `test-aai-prompt-diet.sh` via TEST-312 | 0 | **2392** — unchanged |
| `close-work-item.mjs` | `shasum -a 256` | 0 | `7e8757…696060` — exact allowlist match, absent from the diff |
| `protected_paths_l3` | grep over `.aai/system/*.yaml` and the diff | 0 | no such path in the diff |
| HAZ-LEDGER | `git show main:<f> \| cmp -` vs head bytes | 0 | PREFIX-OK: `EVENTS.jsonl` 362429 B, `decisions.jsonl` 425259 B, `test-runs.jsonl` 25935 B |
| test registration | `node .aai/scripts/check-test-registration.mjs` | 0 | clean, no output; all 13 `test_*` wired into `main()` |
| syntax | `bash -n` installer, `bash -n` suite, `sh/bash/dash -n` hook | 0 | all clean |
| spec lint | `node .aai/scripts/spec-lint.mjs --path <spec>` | 0 | `LINT PASS: no structural findings` |
| AC gate | `docs-audit.mjs --gate spec-agent-shell-…` | 0 | `GATE PASS` — see the AC-table ruling |
| new suite | `aai-run-tests.sh bash tests/skills/test-aai-git-ref-guard.sh` | 0 | TEST-301..312 PASS, TEST-313 named SKIP, isolated + seeded |
| doctor suite | `aai-run-tests.sh bash tests/skills/test-aai-doctor.sh` | 0 | all tests passed |

**CHANGELOG:** no `## [unreleased] — …` entry for this scope (`CHANGELOG.md:12` is the bare scaffold; the newest entry is the prior ride's). Noted, not blocking — close-prep work.

**Collateral test edits — both correct and minimal.** `test-aai-doctor.sh:171` seeds the clean fixture with an AAI-marked `reference-transaction` so CAT-17 does not WARN on a fixture two other tests require to be clean; the 16→17 category-count bumps are mechanical. `test-aai-docs-audit.sh:737,2601` moves each hook-repo fixture onto a `work` branch after installing the hook set, because the fixtures' own post-install commits carry no marker. Validation proved both counterfactually; I re-ran the doctor suite green and read the docs-audit edits, which touch only `setup_*` helpers and no assertion.

---

## Residual dispositions — every validation finding re-judged

| id | re-judgement | disposition |
|---|---|---|
| **F-1** misfire class | **Upgraded and split.** The friction half is confirmed and `git gc`/`pack-refs` are correctly diagnosed as beyond the proposed fix (I traced the stdin: two `old != new` transactions). The proposed hardening is **deferred, not rejected on the merits** — it is correct, costs no prevention, and is blocked by three mechanical facts, chiefly that it would turn this ride's own TEST-313 red. The sharper half validation did not reach — that a refusal leaves reset/merge/rebase/pull partially applied — is re-filed as **F-R1**. | **successor-item** (hook hardening + D2/refusal-text disclosure, owner-gated as a spec amendment). The D2 rows are **close-ceremony** at minimum. |
| **F-2** AC table / false-open | **Confirmed and sharpened.** Not merely structural: the flip is a departure from `.aai/VALIDATION.prompt.md:203`/`:67` and from the prior ride's practice (`bb96d4f`), caused by a real collision with `.aai/ROLE_COMMON.md:51-67`. Self-resolves at close; the sub-finding on `test-aai-doc-number-reservation.sh:22` errexit is pre-existing and independently confirmed by the memory record of that trap. | **successor-item** for the canon collision (ROLE_COMMON vs VALIDATION 8a) and a second for the errexit sub-finding. The row itself: **close-ceremony**. |
| **F-3** `.ps1` static-only | **Confirmed, with one correction in the implementation's favour and one against.** The CRLF residual validation named is closed by `.gitattributes:4` (`*.ps1 text eol=lf`). Against: the static check that is supposed to hold the twin is vacuous — **F-R3**, mutation-proved. | **remediate-in-tree** (F-R3: assert on the extracted here-string). Windows execution: **accepted residual** — no Windows host is reachable from this factory; recorded in `cannot_verify`. |
| **F-4** unterminated final line | **Confirmed and extended** — the same `read -r a b c` shape also lets a 4-field line through. Both unreachable through git. | **accepted residual: P3 assurance-strength, unreachable through git (which terminates every ref line and forbids spaces in ref names), no observed bite, no false record.** |
| **F-5** TEST-313 skips in the harness | **Confirmed** — my own harness run reported `SKIP: TEST-313 ref-guard not armed on this checkout`, which is Spec-AC-04 observed live. The spec declares the degrade-and-report design. **Two gaps validation did not name:** the arm runs `update-ref`, not the commit its Test Plan row promises (**F-R6b**), and its evidence path is gitignored (**F-R4**). | **remediate-in-tree** for F-R4 (`git add -f` one transcript with the delivery commit — the `docs/ai/tdd/bite-*.log` files are the precedent). F-R6b: **close-ceremony** note in the AC-07 Evidence cell. |
| **F-6** housekeeping | **Confirmed and unchanged since validation**: `M docs/ai/EVENTS.jsonl`, `M docs/ai/decisions.jsonl` (this ride's own `spec_amendment` record), `?? docs/assets/` (unrelated). I changed and committed none of it. | **close-ceremony** (commit the ledger lines with the scope; leave `docs/assets/` to the owner). |

New findings from this pass: **F-R1** (partial application under a refusal), **F-R2** (CAT-17 presence-only), **F-R3** (TEST-309 vacuous), **F-R4** (AC-07 evidence gitignored), **F-R5** (hardcoded `main` vs downstream default branches), **F-R6** (USER_GUIDE stale). All NON-BLOCKING; every one carries a disposition in the table above or in the code_quality block. None is disposed as an accepted residual except F-4, which meets H6 (d) on all three tests.

---

## Sweep policy

**I concur: no re-sweep is owed, and the reasoning survives scrutiny.** The recorded sweep `test-20260828-121325` (82 suites, 76 passed, 6 failed, 82/82 isolated, committed honestly at `bd5b2a9` with `failed: 6` on the record) predates only the `SUBAGENT_CONTRACT.md` re-wrap. That claim rests on tree identity, not timestamp — `aai-doctor` PASSED in that sweep, which is impossible without the CAT-17 fixture line and the 17-category bumps — which is the same technique the prior ride used for its own pre-delta sweep and the correct one.

The re-wrap has exactly three consumers; validation re-ran all three green and I independently re-ran two suites end to end (`test-aai-git-ref-guard.sh` exit 0, `test-aai-doctor.sh` exit 0). A full re-sweep would return the same six failures, because the `probable-false-open` row that causes five of them is still in the tree and stays there until `close-work-item.mjs` flips the frontmatter. Ordering one would buy zero information at 82 suites of cost. I would order a re-sweep only if the hook body changed — which is precisely why F-1's hardening belongs to a successor ride and not to this one.

## Next steps

1. Close-prep (orchestrator): CHANGELOG `## [unreleased] — …` entry; commit the two ledger lines; run the close ceremony, which flips the frontmatter and clears the false-open row and with it five of the six sweep failures. Do **not** `git restore docs/ai/EVENTS.jsonl` afterwards.
2. Remediate-in-tree before close: F-R4 (`git add -f docs/ai/tdd/test-313-live-<ts>.log`) and F-R3 (assert TEST-309 on the extracted here-string). Both are additive and touch no shipped behaviour.
3. Successor items: the hook hardening + D2 disclosure (owner-gated), the CAT-17 functional probe, the ROLE_COMMON/VALIDATION-8a canon collision, and the `test-aai-doc-number-reservation.sh` errexit defect.
4. The dispatch named no expected findings, pre-rated no severities and excluded no areas; there is no coaching attempt to record.

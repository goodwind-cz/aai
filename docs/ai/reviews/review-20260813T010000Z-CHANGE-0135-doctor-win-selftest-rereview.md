# Code Review (round 2, scoped re-review) — CHANGE-0135 / spec-doctor-win-selftest

```yaml
review:
  scope: "git diff 3861d66..HEAD (remediation commits 4b3004e + bdf1864, 7 files) + merge fitness of git diff main...HEAD @ bdf1864"
  spec: docs/specs/SPEC-0122-spec-doctor-win-selftest.md (SPEC-FROZEN, status implementing, ceremony_level 1)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: cannot-verify,
          citation: "row is status `planned` by the spec's own PASS criteria; POSIX half re-verified by my own runs (aai-doctor.mjs:451-453 SKIP gate -> CAT-14/15 SKIP, detail.spawned=false; Pester 138/138 Skipped=0 incl. the host-adaptive TEST-004 context). Windows half still needs ps1-quality / windows-5_1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "aai-win-selftest.ps1:42 single file-scope dot-source and :383 guard unchanged by the remediation; the two NEW helpers (:162 ConvertTo-PsSingleQuoteEscaped, :177 ConvertTo-PosixShSingleQuoteEscaped) are local pure escapers, not a second implementation of any borrowed wrapper function — the no-fork clause still holds. Pester 138/138" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "aai-doctor.mjs:541-589 untouched by the remediation; my live run: `CAT-16 PASS 3/3 agent CLI(s) present`, --json detail keys clis,capabilities,codex_exec_subcommand; TEST-026/027/033 green" }
      - { ac: Spec-AC-04, call: non-compliant,
          citation: "aai-doctor.mjs:653-658 — `const issueCount = warnOrFailCount;` contradicts the AC's own frozen clause `the DOCTOR verdict line still counts every non-PASS category`. Secondary: aai-doctor.mjs:673-677 drops the text-mode detail line, contradicting the spec's implementation plan (line 297, `rendered as an indented block in text mode`). Spec row is still marked `done`; the spec was not touched by either remediation commit (`git diff --name-only 3861d66..HEAD -- docs/specs/` is empty)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "counts I re-counted myself: 6 Context blocks in the CHANGE-0135 Describe (aai-win-dispatch.Tests.ps1:1381/1408/1432/1483/1499/1543) == CHANGELOG's `six`; 12 new test_0NN functions (TEST-023..034) == CHANGELOG's `twelve`. docs/product/aai-doctor.md:130 evidence pointer now names docs/ai/validation/. test-aai-hygiene-pack.sh + TEST-031/032 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 698,
          issue: "TEST-024 (the new anti-deletion CLASS guard) resolves its base with the BARE ref `main`. Git never resolves a bare `main` to refs/remotes/origin/main, and actions/checkout@v4 creates no local `main` branch on a pull_request run (detached at the merge ref) nor on a push to a feature branch. The guard therefore soft-skips on every CI run — and it reports that skip via log_pass, so the suite prints a green PASS line for a check that verified nothing.",
          failure_scenario: "I reproduced it exactly: in a clone with only refs/remotes/origin/main and a detached HEAD (an actions/checkout PR checkout), I re-introduced the verbatim B1 bug (deleted the CHANGE-0134 heading) and ran the guard -> `PASS: TEST-024 skipped: local 'main' ref not reachable`, exit 0. The one incident class this test was written for passes CI silently. The push-to-main case is vacuous for a different reason: merge-base HEAD main == HEAD, so the base CHANGELOG is byte-identical to the live one by construction. Fix is one line and matches this repo's own precedent (allocate-doc-number.mjs:811 defaults --base-ref to `origin/main`): try `main`, else `origin/main`." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-win-selftest.ps1, line: 264,
          issue: "The NB-1 escaping fix closed the apostrophe hole but not its class. `$markerPosixSh` is interpolated into a PowerShell DOUBLE-quoted string in the generated inner.ps1 (`sh -c \"echo ... > '$markerPosixSh'\"`, same at :328). That string is re-parsed by the child engine, where `$` and backtick ARE metacharacters — ConvertTo-PosixShSingleQuoteEscaped escapes neither. Unlike the apostrophe case this is parse-CLEAN, so the new Pester context (which asserts only Parser error count == 0) cannot see it.",
          failure_scenario: "Proven on this host by driving the real Invoke-SelfTestArmSuccess through apostrophe / `$` / backtick temp paths and evaluating the emitted sh argument: `O'Brien` -> marker written at the exact expected path, /bin/sh exit 3 (fix works); `A$AP` -> `$AP` expands to empty, marker goes to `.../A/arm-success/marker.txt`, expected path never created; `Back`tick` -> the backtick-t becomes a literal TAB, same result. Both are legal Windows profile names, so TEMP carries them: the success arm's markerOk check fails, the arm reports FAIL, and CAT-14 reports the wrapper broken on a machine whose wrapper is fine — NB-1's exact failure mode, silently. Fix: a third escaper backtick-escaping `$` and backtick for the PS double-quoted layer." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "The SKIP-counting change is described as scoped to the new categories (\"A SKIP (CAT-14/CAT-15 off Windows) is never counted as an issue\"), but `issueCount` is global: CAT-08 Git Status already emitted SKIP before this scope (present on main at aai-doctor.mjs:265, `not a git repository`), so a PRE-EXISTING category's contribution to the verdict count changed too. Neither the CHANGELOG nor docs/USER_GUIDE.md:1275-1280 says so.",
          failure_scenario: "A user runs /aai-doctor in a directory that is not a git repo. On main: CAT-08 SKIP is counted, verdict ISSUES(n). After merge: the same SKIP is silently uncounted and the verdict can read CLEAN with a category the user never saw flagged. The behavior change is defensible; shipping it as an undeclared side effect of a CAT-14/15 statement is the defect." }
  cannot_verify:
    - { claim: "Spec-AC-01's Windows half — the three arms run and PASS on a real Windows host, and AAI-BRANCH survives the two-hop OS-handle capture (SEAM-2)",
        closes_with: "ps1-quality / windows-5_1 green on this PR under BOTH engines, arm results + job URL pasted into the Spec-AC-01 evidence cell" }
    - { claim: "That the apostrophe fix behaves the same under Windows PowerShell 5.1 as under pwsh 7.6.3 — my probe ran only pwsh 7.6.3 (no `powershell` on this host), and Set-Content at :218 still writes the inner script with the engine's default encoding (ANSI under 5.1, UTF-8 under 7), an asymmetry the remediation did not address",
        closes_with: "the windows-5_1 job, which runs both engines" }
    - { claim: "The doctor's 170 s probe budget on a real Windows host (arms budgeted 90+30+30 s)",
        closes_with: "wall-clock from the windows-5_1 job, or one manual /aai-doctor run on Windows" }
    - { claim: "resolveExecutable's PATHEXT branch (aai-doctor.mjs:520-539) — Windows-only, exercised by no test on any platform",
        closes_with: "a Windows-run CAT-16 assertion, or a POSIX unit test over the function with injected PATH/PATHEXT" }
    - { claim: "CAT-15 against a genuine Windows Path/PATH collision",
        closes_with: "a CAT-15 detail dump from a Windows host carrying a real collision" }
    - { claim: "The ci-full lane obligation — still no PR (`gh pr list --head feat/doctor-win-selftest` -> [])",
        closes_with: "gh pr create --label ci-full, then skill-suite / skills-full green" }
  overall: fail
```

## Scope and preflight

- Branch verified `feat/doctor-win-selftest`; never switched, never pushed. Real
  working tree clean before and after (`git status --porcelain` empty) — the only
  file I created in the repo is this report. All mutation experiments ran in a
  throwaway clone under the scratchpad, never in the tree.
- Scope per rule 13: the remediation diff `3861d66..HEAD` (4b3004e + bdf1864, 7
  files, +170/-27), plus merge fitness of the whole `main...HEAD`. The prior
  report (review-20260813T003000Z) was read in full; STATE's `worktree` block is
  still stale (same class as validation F11), so I used the dispatch's explicit
  refs, which the preflight permits.
- Anti-gaming note, recorded per the prompt's own rule: the dispatch pre-rated
  severity ("BLOCKING only genuine gates") and pre-listed what to check. I
  reviewed the full remediation diff independently; the three findings below
  (TEST-024 CI-vacuity, the `$`/backtick escaping residual, the undeclared CAT-08
  count change) and the Spec-AC-04 non-compliance are all new, none of them on
  any prior list.

## Verification I ran myself

| Command | Result |
|---|---|
| `diff <(git show main:CHANGELOG.md \| tail -n +14) <(tail -n +51 CHANGELOG.md)` | **identical**, md5 `b0904e55…` both sides |
| `grep -c '^## \[unreleased\]$' CHANGELOG.md` | 1 (exactly one bare scaffold, line 12) |
| TEST-024 in a clone, heading deleted | **FAIL**, names `## [unreleased] — ci(ps1-quality)… (CHANGE-0134) [L1]`, exit 1 |
| TEST-024 in a clone, heading retitled | **FAIL** (also catches mutation, not just deletion) |
| TEST-024 under simulated actions/checkout PR checkout, bug present | **skipped, exit 0** — see finding 1 |
| pwsh probe: real arm functions × `O'Brien` path | Parser errors **0** on all three arms; pre-fix control reproduces `The string is missing the terminator: "` |
| same probe, sh round-trip | `/bin/sh` exit 3, marker created at the exact expected `O'Brien` path |
| same probe, `A$AP` / `` Back`tick `` paths | parse-clean but marker path **corrupted** — see finding 2 |
| `node .aai/scripts/aai-doctor.mjs` | 16 CAT lines, **zero** `detail:` lines, `DOCTOR ISSUES(2)`, exit 0 |
| `--strict` / plain | exit **1** / exit **0**; `--json` still carries detail on CAT-14/15/16 |
| `test-aai-doctor.sh` | 34/34 PASS (TEST-001..034) |
| `test-aai-release.sh` | ALL PASS incl. TEST-024 |
| `test-ps1-quality.sh` | PASS; `AAI-POSIX-PESTER: Total=138 Passed=138 Failed=0 Skipped=0` |
| Pester direct over `tests/skills` (both .Tests.ps1) | 138/138, Skipped 0 |
| `test-aai-hygiene-pack.sh` | ALL PASS |

## The prior BLOCKING is dead

B1 is closed cleanly, and more strongly than "the heading is back": everything
from `main`'s CHANGELOG line 14 onward is **byte-identical** to HEAD's line 51
onward, and the preamble (lines 1-13) is identical too. The CHANGE-0135 entry is
therefore a pure insertion of lines 14-50 between the bare scaffold and the
untouched CHANGE-0134 entry — no bullet of any pre-existing entry was moved,
reworded or re-attributed. Exactly one bare `## [unreleased]` scaffold remains,
above every entry. `grep -c CHANGE-0134` is 1 on both sides.

## The new guard, honestly

TEST-024 is the right instinct and the right shape — a class guard, local, single
awk pass, no pipelines (respecting this suite's `set -o pipefail`), and it catches
both deletion and silent retitling. My only problem with it is reach: it resolves
`main` as a bare ref, which no CI checkout provides, so the guard is a
developer-machine guard that reports itself green in CI. That is not nothing —
both heading-deletion incidents were authored locally, and a local ride does run
this suite — but the comment presents the skip as an edge case ("fresh clone,
detached CI checkout, template repo") when it is in fact the normal CI state,
100% of runs. One `origin/main` fallback makes the comment true.

## The apostrophe fix, honestly

The fix is real, load-bearing and correct at both layers I could reach: the PS
single-quote layer (`''`) and the POSIX sh layer (`'\''`), the second of which I
verified by handing the emitted argument to a real `/bin/sh` and watching the
marker land at the exact `O'Brien` path. Normal and space-bearing paths are
unaffected — the escapers are identity when no quote is present, and the
`Normal User` profile generated byte-identical output to pre-fix. The two new
helper functions are well-placed and their headers explain the two-parse-layer
reasoning better than most code in this repo.

What the fix did not close is the rest of the class, because the marker path also
sits inside a PowerShell *double*-quoted string that the child engine re-parses:
`$` and backtick still bite there, silently. The new Pester context can't catch it
because it asserts syntactic validity only — a parse-clean wrong path looks
identical to a parse-clean right path. If that context grew one assertion that the
emitted `sh` argument contains the marker path *verbatim*, it would cover the
whole class rather than one member of it.

## Spec-AC-04 — the one thing that fails a verdict

The remediation implemented NB-2 (text-mode detail) and NB-3 (SKIP counted as an
issue) **in tree**. I agree with both changes on the merits — the text report is a
better artifact for it, and `DOCTOR ISSUES(2)` now genuinely means two warnings,
which makes the skill prompt's "DEGRADED — n warning(s)" translation true for the
first time. But the prior review recommended both as *follow-up refs* precisely
because Spec-AC-04 freezes the old behavior, and the spec was not amended:

- Spec-AC-04, status `done`: "…and the DOCTOR verdict line **still counts every
  non-PASS category**". The code now counts WARN|FAIL only.
- Implementation plan line 297: detail "rendered as **an indented block in text
  mode** and inlined in `--json`". Text mode now renders nothing.
- Test Plan row TEST-001, status `green`: "…and the DOCTOR verdict line **counts
  it as a non-PASS category** without changing the exit code". Its implementation
  (test_023) asserts CAT-14 SKIP, `detail.spawned=false` and exit 0 — it never
  asserted the counting, which is why the suite stayed green through a behavior
  change its own Test Plan row describes in the opposite direction.

So the code is better than the spec and the spec still says otherwise, with the
row marked `done`. That is the false-done shape this repo's own docs audit exists
to catch, and it is a two-text-edit fix: the spec is still `status: implementing`,
so amending Spec-AC-04's clause (plus the plan line and the TEST-001 row) is a
legitimate, cheap correction — not a revert. Everything else in the AC table
holds, and the counts the CHANGELOG now claims are true; I counted them.

## Merge fitness

Not mergeable as-is, but the gap is text, not code. In order:

1. **Amend Spec-AC-04** (clause + implementation-plan line 297 + Test Plan TEST-001
   row) so the frozen spec describes the behavior actually shipped, and record the
   deviation in `docs/ai/decisions.jsonl` — the review recommended these two as
   follow-up refs and the implementer chose in-tree; that choice needs to be
   written down somewhere, not inferred from a diff.
2. **One CHANGELOG clause** widening the SKIP statement beyond CAT-14/15 (finding 3).
3. Recommended in-tree, both one-liners: TEST-024's `origin/main` fallback
   (finding 1) and the `$`/backtick escaper (finding 2).
4. Still open from round 1, unchanged: NB-7 (CAT-16 ABSENT/unknown conflation +
   the N2 `exec` regex) as a follow-up ref; NB-8 (the undocumented 1-3 minute
   Windows wall-clock) — I re-checked docs/USER_GUIDE.md:1255-1285 and
   docs/product/aai-doctor.md, still absent.
5. Process obligations unchanged: PR created **with `ci-full` present at run
   start**; Spec-AC-01 stays `planned` until ps1-quality / windows-5_1 is green on
   both engines, at which point the stale `132/132` figure in the AC-01 evidence
   cell should also be refreshed (my run measured 138/138).

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| Spec-AC-04 drift (verdict clause, plan line, TEST-001 row) | remediate-in-tree (spec text) + decisions.jsonl entry |
| 1. TEST-024 vacuous in CI | remediate-in-tree (one-line `origin/main` fallback) |
| 2. `$`/backtick escaping residual | remediate-in-tree, or promote-to-follow-up-ref with NB-7 if the ride is closing |
| 3. CHANGELOG understates the SKIP-count change | remediate-in-tree (one clause) |
| NB-7 (carried) CAT-16 ABSENT/unknown + `exec` regex | promote-to-follow-up-ref |
| NB-8 (carried) undocumented Windows wall-clock | remediate-in-tree (one sentence) |

INFO (never gate): TEST-014's `DOCTOR ISSUES(2)` acceptance branch
(test-aai-doctor.sh:533-536) is now unreachable — the clean fixture returns CLEAN;
`Build-SelfTestReport` is still a non-approved PowerShell verb; CAT-14's
`detail:{spawned:false}` vs CAT-15's `detail:{}` degrade-path asymmetry;
`Set-Content` at aai-win-selftest.ps1:218 still writes with the engine default
encoding (5.1 ANSI vs 7 UTF-8) — harmless for ASCII paths, unverified otherwise;
the skill prompt documents `--json` but not the new `--strict`.

---

```yaml
subagent_result:
  scope: CHANGE-0135 / spec-doctor-win-selftest (code review round 2, git diff 3861d66..HEAD + merge fitness of main...HEAD @ bdf1864)
  role: Validation
  status: FAIL
  started_utc: 2026-08-13T00:52:19Z
  ended_utc: 2026-08-13T01:00:10Z
  duration_seconds: 471
  evidence:
    - command: "diff <(git show main:CHANGELOG.md | tail -n +14) <(tail -n +51 CHANGELOG.md); grep -c '^## \\[unreleased\\]$' CHANGELOG.md"
      exit_code: 0
      output_snippet: "IDENTICAL (md5 b0904e5593ae3a331481e743cc6b98de both sides); exactly 1 bare scaffold -- BLOCKING B1 closed as a pure insertion of lines 14-50"
    - command: "bash tests/skills/test-aai-release.sh test_024_... in a scratch clone, with the CHANGE-0134 heading deleted"
      exit_code: 1
      output_snippet: "FAIL: TEST-024: unreleased heading(s) present at merge-base (789c5c0) are missing from the live CHANGELOG -- deleted rather than added above: ## [unreleased] - ci(ps1-quality)... (CHANGE-0134) [L1]"
    - command: "same test under a simulated actions/checkout@v4 PR checkout (detached HEAD, only refs/remotes/origin/main), bug re-introduced"
      exit_code: 0
      output_snippet: "PASS: TEST-024 skipped: local 'main' ref not reachable -- the guard is vacuous on every CI run"
    - command: "pwsh probe driving the real arm functions through O'Brien / A$AP / backtick temp paths, then /bin/sh round-trip"
      exit_code: 0
      output_snippet: "O'Brien: parse errors 0, sh exit 3, marker at expected path (fix works). A$AP: parse-clean but marker path becomes .../A/... ; backtick: becomes a TAB -- same class, silent"
    - command: "node .aai/scripts/aai-doctor.mjs ; --strict ; --json"
      exit_code: 0
      output_snippet: "16 CAT lines, ZERO detail: lines, DOCTOR ISSUES(2), exit 0; --strict exit 1; --json detail intact on CAT-14/15/16"
    - command: "test-aai-doctor.sh; test-aai-release.sh; test-ps1-quality.sh; test-aai-hygiene-pack.sh; Invoke-Pester tests/skills"
      exit_code: 0
      output_snippet: "34/34 PASS; ALL TESTS PASSED incl TEST-024; AAI-POSIX-PESTER Total=138 Passed=138 Failed=0 Skipped=0; hygiene ALL PASS"
  files_changed:
    - docs/ai/reviews/review-20260813T010000Z-CHANGE-0135-doctor-win-selftest-rereview.md
  blockers:
    - "spec_compliance FAIL: Spec-AC-04 (marked `done`) says the verdict line 'still counts every non-PASS category'; aai-doctor.mjs:653-658 now counts WARN|FAIL only. Implementation-plan line 297 ('indented block in text mode') and Test Plan row TEST-001 are contradicted too. The remediation implemented NB-2/NB-3 in-tree -- both were recommended as follow-up refs BECAUSE Spec-AC-04 froze them -- and left the spec unamended. Fix is spec text + a decisions.jsonl entry, not a code revert."
    - "code_quality PASSES (no BLOCKING). Three NON-BLOCKING findings need an H6 disposition: TEST-024 vacuous under every CI checkout (bare `main` ref); the $/backtick residual of the NB-1 escaping class (parse-clean, silent wrong marker path); the CHANGELOG understating the SKIP-count change (CAT-08 is affected too)."
    - "Carried and still open: NB-7 (CAT-16 ABSENT/unknown conflation + `exec` regex) and NB-8 (undocumented Windows wall-clock, re-checked absent)."
    - "Process, unchanged: PR must be created with `ci-full` present at run start; Spec-AC-01 stays `planned` until ps1-quality / windows-5_1 is green on both engines (refresh the stale 132/132 figure to 138/138 then)."
    - "started_utc is the birth time of the first artifact I created (scratchpad main-changelog.md), the earliest clock-attested anchor I hold; my own start reading was not captured and is not estimated."
```

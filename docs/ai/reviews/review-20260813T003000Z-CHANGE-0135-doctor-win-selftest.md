# Code Review — CHANGE-0135 / spec-doctor-win-selftest

```yaml
review:
  scope: git diff main...HEAD (branch feat/doctor-win-selftest @ 9727980, 16 files)
  spec: docs/specs/SPEC-0122-spec-doctor-win-selftest.md (SPEC-FROZEN, ceremony_level 1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: cannot-verify,
          citation: "row is status `planned` by the spec's own PASS criteria; POSIX half verified (.aai/scripts/aai-doctor.mjs:451-458 SKIP gate, TEST-023/024/034 green); Windows half needs ps1-quality / windows-5_1" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-win-selftest.ps1:42 (single file-scope dot-source), :46-93 (collision report + WSL tri-state derived from the wrapper's own functions), :349 guard; TEST-025 + Pester TEST-006/007, F3/F7 mutation kills" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:520-566 (resolveCliVersion / capabilities literal UNKNOWN / codex_exec_subcommand as its own key); TEST-026/027/033 green; live run shows 3/3 PRESENT with verbatim versions" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/aai-doctor.mjs:604, :652-656, :670-672; TEST-028/029/030 green; my own live run: one CAT-14/15/16 line each, DOCTOR ISSUES(4), --strict exit 1, plain exit 0" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/system/PROFILES.yaml:95, tests/skills/suite-map.yaml:199-201, docs/product/aai-doctor.md, docs/USER_GUIDE.md:1255-1285, CHANGELOG.md:14; TEST-031/032 green, check-test-registration clean. NOTE: the CHANGELOG edit itself carries BLOCKING finding B1 — the AC text is satisfied, the edit is not clean" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: CHANGELOG.md, line: 14,
          issue: "The CHANGE-0134 entry heading `## [unreleased] — ci(ps1-quality): windows-5_1 runs the full Pester suite under both engines (CHANGE-0134) [L1]` was DELETED and replaced by this scope's heading; CHANGE-0134's eight bullets now sit under the CHANGE-0135 title. `grep -c CHANGE-0134 CHANGELOG.md` == 0 on HEAD, == 1 on main.",
          failure_scenario: "Run /aai-release (or any CHANGELOG cut) after merge: the versioned section attributes CHANGE-0134's ps1-quality/Pester-install/reap-probe work to the doctor entry, and CHANGE-0134 disappears from the release notes permanently. No test catches it — TEST-032 only greps for a heading matching /doctor/i." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-win-selftest.ps1, line: 233,
          issue: "All three arms interpolate `$RunDispatcherPath` / `$markerPosix` / `$decoyRoot` / `$reducedPath` into SINGLE-QUOTED literals inside the generated inner script without escaping an embedded apostrophe (also :254 and :288-296). `Set-Content` at :191 additionally writes the inner script with the engine's default encoding (ANSI under 5.1).",
          failure_scenario: "A Windows host whose repo or TEMP path contains an apostrophe — `C:\\Users\\O'Brien\\...`, a legal Windows profile name — generates `& 'C:\\Users\\O'Brien\\aai-run-tests.ps1' ...`. I proved the parse failure: `Parser::ParseInput` returns 1 error, \"The string is missing the terminator\". The engine dies before the wrapper runs, all three arms FAIL, and CAT-14 reports the wrapper broken on a machine whose wrapper is fine — a false diagnosis from the tool whose whole purpose is diagnosing that machine. Fix: `-replace \"'\", \"''\"` on each interpolated path (and escape for the `sh -c` layer)." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-doctor.mjs, line: 671,
          issue: "Text mode prints `  detail: ${JSON.stringify(c.detail)}` — one unwrapped compact-JSON line per new category, on every platform. CAT-16's is ~1.2 kB and repeats the same 84-char capability reason four times.",
          failure_scenario: "An operator runs /aai-doctor on macOS/Linux to paste the report into a chat (the product doc's stated use: \"a paste-able report\"): they now paste a 1.2 kB machine blob after CAT-16 that the spec only ever required under --json. The spec's own implementation plan says \"rendered as an indented block in text mode\"; a single JSON line is not a block. Fix: pretty-print the block, summarize it, or restrict detail to --json." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_DOCTOR.prompt.md, line: 39,
          issue: "SKIP is counted as an issue by the verdict line (pre-existing, and Spec-AC-04 freezes it), but CAT-14/CAT-15 make SKIP the NORMAL state on every non-Windows host — while --strict explicitly declares \"a SKIP is not a finding\". The two surfaces now contradict each other and the prompt was not updated.",
          failure_scenario: "A perfectly healthy macOS project: `DOCTOR ISSUES(2)`, exit 0, `--strict` exit 0 — and the skill prompt instructs the agent to say \"DEGRADED — 2 warning(s), nothing broken\" and to list them as recommended actions, for two honest skips with no action available. Verified against the clean fixture (TEST-014 now asserts ISSUES(2)). Fix: one prompt line separating skipped from warned (ledger entry owed), or exclude SKIP from issueCount." }
      - { rank: NON-BLOCKING, file: tests/skills/aai-win-dispatch.Tests.ps1, line: 1541,
          issue: "N1 confirmed in-tree: the two SEAM-2 assertions (`$successArm.diag | Should -Not -BeNullOrEmpty` / `-Match '^AAI-BRANCH:'`) sit AFTER the if/else, so they also execute in the `no usable POSIX interpreter` branch — a branch whose whole premise is exit 78, where aai-run-tests.ps1:81 documents AAI-BRANCH is never emitted.",
          failure_scenario: "windows-5_1 runs on a runner image without a usable Git Bash/WSL: the precondition branch is entered, then the diag assertion throws `Expected a value, but got $null or empty`. Direction is fail-closed (good), but the CI failure message points at a missing diag instead of naming the real precondition, and the branch's own comment claims a tolerance it does not grant. Two-line fix: move both assertions into the else." }
      - { rank: NON-BLOCKING, file: docs/product/aai-doctor.md, line: 130,
          issue: "Unfilled template pointer: `- Validation evidence: docs/ai/reports/` — the evidence for this scope is docs/ai/validation/validation-20260812T234524Z-*.md and validation-20260813T002100Z-*-rescope.md. Sibling product docs (windows-test-wrapper.md:102, validation-cost-calibration.md:80) name docs/ai/validation/ and flag it gitignored.",
          failure_scenario: "A downstream reader follows the link, finds no validation evidence for the capability, and concludes the scope shipped unvalidated. TEST-032 checks the three product sections but not the Links block." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 34,
          issue: "Stale counts after remediation 9727980: \"Both new categories cap at WARN\" (there are three new categories; the accurate statement is CAT-14/15 cap at WARN and CAT-16 is always PASS), \"gains ten new cases\" (twelve: TEST-023..034), \"gains three new Pester contexts\" (five).",
          failure_scenario: "Release notes under-report the delivered test surface; a reader auditing coverage against the CHANGELOG counts ten and finds twelve." }
      - { rank: NON-BLOCKING, file: docs/USER_GUIDE.md, line: 1255,
          issue: "Neither the USER_GUIDE nor the product doc states CAT-14's wall-clock cost on Windows. The doctor's probe budget is 170 s (.aai/scripts/aai-doctor.mjs:465) over arms budgeted 90+30+30 s (.aai/scripts/aai-win-selftest.ps1:238/259/297), and the doctor prints nothing until every category has run.",
          failure_scenario: "A Windows operator runs /aai-doctor for the first time after /aai-update, sees no output for one to three minutes (the timeout arm alone burns its full 2 s wrapper timeout plus grace), assumes a hang and Ctrl-Cs — losing the exact diagnosis the scope exists to produce. One documentation sentence closes it." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-doctor.mjs, line: 541,
          issue: "Carried honesty debt (validation F5/F6 + N2), re-confirmed by reading: `{present:false}` is returned for three distinct states (nothing resolved / resolved-but-empty --version / error), `res.stdout || res.stderr` promotes any stderr diagnostic to \"the version\", the CAT-16 one-line reason folds a timed-out CLI into the absent count, and probeCodexExecSubcommand reports `codex CLI not present` when codex resolved but timed out. N2: the tightened regex /^\\s{2,}exec\\s{2,}\\S/m still fires on a 2-space-indented prose line beginning with `exec`, and misses tab- or single-space-separated command lists.",
          failure_scenario: "A broken `claude` shim on PATH prints `line 3: sleep: command not found` to stderr and exit 0: CAT-16 reports it PRESENT with that string as its version, so the operator reads a broken install as healthy. Follow-up-ref class, not merge-gating: the field is observational and never keys behavior." }
  cannot_verify:
    - { claim: "Spec-AC-01's Windows half — the three arms run and PASS on a real Windows host, and the AAI-BRANCH diag survives the two-hop OS-handle capture (SEAM-2)",
        closes_with: "ps1-quality / windows-5_1 green on this PR under BOTH engines, with the CAT-14 arm results and the job URL pasted into the Spec-AC-01 evidence cell" }
    - { claim: "Which branch of TEST-004 the CI runner actually takes (arms-PASS vs the no-usable-POSIX precondition, which N1 shows cannot pass)",
        closes_with: "the same windows-5_1 job log" }
    - { claim: "That the doctor's 170 s probe budget is sufficient on a real Windows host/runner (arms are budgeted 90+30+30 s before engine-start overhead)",
        closes_with: "wall-clock from the windows-5_1 job, or one manual /aai-doctor run on a Windows box" }
    - { claim: "resolveExecutable's PATHEXT branch (.aai/scripts/aai-doctor.mjs:520-539) — it is Windows-only and no test on any platform exercises it; a .cmd shim is the documented target case",
        closes_with: "a Windows-run CAT-16 assertion, or a POSIX-runnable unit test over the resolution function with an injected PATH/PATHEXT" }
    - { claim: "CAT-15 against a genuine Windows Path/PATH collision (the CHANGE-0133 field shape) — covered only by a synthetic dictionary and the prior validator's macOS-injected duplicate",
        closes_with: "a CAT-15 detail dump from a Windows host carrying a real collision" }
    - { claim: "The ci-full lane obligation — no PR exists yet (gh pr list --head feat/doctor-win-selftest -> [])",
        closes_with: "gh pr create --label ci-full and skill-suite / skills-full green on this PR" }
  overall: fail
```

## Scope and preflight

- Branch verified: `git branch --show-current` -> `feat/doctor-win-selftest`; never switched, never pushed. Tree clean before and after (`git status --porcelain` empty; the only artifact I created is this report).
- Review scope: `git diff main...HEAD` — 6 commits (07126f6, 77a79df, 2815511, e710d28, cf6f037, 9727980), 16 files, +2047/-29.
- STATE preflight: `worktree.user_decision: inline`, but `worktree.branch` is `feat/core-prompt-diet` and `worktree.inline_review_scope` lists a completely different scope's paths (ci-test-impact-selection). That block is stale from an earlier ride, so it is NOT a usable scope source; I used the dispatch's explicit base/head refs, which the preflight permits ("an explicit caller-provided diff"). Orchestrator note: same class as validation F11 (`implementation_strategy.source` also still points at SPEC-DRAFT-spec-ps1-wrapper-path-dup).
- Read: both validation reports (validation-20260812T234524Z-*.md FAIL-class findings, validation-20260813T002100Z-*-rescope.md scoped PASS), the frozen spec, the intake.
- Anti-gaming note (recorded per the prompt's own rule): the dispatch pre-characterized findings ("F5/F6/F10/F11 + N1/N2 are recorded ground") and pre-rated severity ("BLOCKING only genuine gates"). I reviewed the full diff independently anyway; the BLOCKING finding below (CHANGELOG) is not on any prior list, and I re-derived N1/N2 from the files rather than accepting them.

## Independent verification I ran

| Command | Exit | Result |
|---|---|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh` | 0 | 34/34 PASS (TEST-001..034) — every TEST-xxx the AC table cites exists and passes |
| `node .aai/scripts/aai-doctor.mjs` (real repo) | 0 | 0.95 s; CAT-14/15 SKIP, CAT-16 PASS 3/3, `DOCTOR ISSUES(4)`; text-mode detail blob measured |
| `pwsh -NoProfile -File <scratch>/apos.ps1` — exact replay of Invoke-SelfTestArmSuccess's here-string with an apostrophe path | 0 | `PARSE ERRORS: 1 — The string is missing the terminator: ".` (NB-1 proof) |
| `git show main:CHANGELOG.md` vs HEAD; `grep -c CHANGE-0134 CHANGELOG.md` | — | 1 on main, **0 on HEAD** (B1 proof) |
| Read-only structural reads of aai-win-selftest.ps1, aai-doctor.mjs, both test files, all four docs | — | see findings |

I did not re-run test-ps1-quality.sh / win-fallback / prompt-diet: both validation passes re-executed them (135/135 Pester, SkippedCount 0; TEST-017 budget balanced; TEST-012 == -7210 == independent re-sum) and this is an L1 ride.

## Judgement beyond validation

**aai-win-selftest.ps1 as code.** Structurally the best-shaped new file in this scope: pure derivations (`Get-EnvironmentCollisionReport`, `Get-WslTriState`, `Build-SelfTestReport`, `Get-QuotedArgumentString`) are cleanly separated from the three spawning arms, which is exactly what made the Pester coverage possible without mocking a process. The dot-source contract is unambiguous — one unindented file-scope `. (Join-Path $PSScriptRoot 'aai-run-tests.ps1')` at :42, the wrapper's own `$MyInvocation.InvocationName -ne '.'` guard mirrored at :349, and a header that names the six borrowed functions. `-cne` at :70 and the `-NoEnumerate` rationale at :75-82 are the kind of comments that earn their bytes: both encode a language footgun that a future editor would otherwise re-introduce. The arm functions read in one pass. Two things I would change: the inner scripts are built by string interpolation with no escaping discipline (NB-1), and `Build-` is not a PowerShell approved verb (`New-SelfTestReport` would be; the analyzer gate does not enforce it, so INFO only).

**Doctor text as operator UX.** The `CAT-NN STATUS reason` lines are good — CAT-16's reason names the count AND why the four fields are UNKNOWN in the same breath, which is exactly what an operator pasting the report needs. The SKIP reasons are actionable-by-construction ("not running on a Windows host" needs no action, and says so). Two UX regressions land on every user of every platform, though: the raw JSON detail line (NB-2) and the SKIP-counted-as-issue verdict that the skill prompt renders as "DEGRADED — 2 warning(s)" (NB-3). Neither is a correctness bug; both are the difference between a report an owner reads and one they skim past.

**--json detail schema.** Sane and stable: `selftest` is `{spawned, arms[], failed, reason}` with `arms[]` uniformly `{name,status,exitCode,diag}`; `environment` is `{collisions[], engines[], gitBash{candidates[],selected}, wsl}`; CAT-16 is `{clis{}, capabilities{}, codex_exec_subcommand{}}`. The array-shape discipline (`-NoEnumerate` producing real arrays across the seam, `Array.isArray` guards on the Node side) is now pinned at both call sites. One asymmetry worth knowing: the SKIP/WARN degrade paths return `detail: {spawned:false}` for CAT-14 but `detail: {}` for CAT-15 — a consumer reading `detail.collisions` must handle absent, and nothing documents that. Not worth a finding; worth knowing.

**Docs truthfulness.** Clean on the one thing that mattered most: nothing anywhere claims the Windows arms have been proven on real Windows. The product doc's "what it proves / what it does NOT prove" pair is the strongest paragraph in the doc set, the CHANGELOG states Spec-AC-01 stays planned, and the USER_GUIDE's "proves the wrapper contract holds on THIS machine, right now" is precisely scoped. Defects are the CHANGELOG entry destruction (B1), stale counts (NB-6), and the template evidence pointer (NB-5).

**Test quality of remediation 9727980.** Genuinely strong, and I checked the mutations rather than trusting the message: the F1 rewrite pins each arm's own status AND exit code (3/124/125) plus the spawnfail diag, so 3/3 is no longer indistinguishable from 0/3; F2 now has both a unit contract and an integration pin through the real caller with a spaced `$TestDrive` path; F3 pins the second `-NoEnumerate` site with a single-engine mock and a comment explaining why `.Count` reads 2; F7's `^\s*function` anchor plus `Wait-ProcessWithTimeout` closes SEAM-3 in both the redefine and rename directions. TEST-034 is the standout — flipping `process.platform` via `--import` for a genuinely spawned child exercises the real ps1 through the real parser, which is a far better answer to F9 than a mock would have been. Two soft spots: TEST-034 hard-asserts `WARN` (correct on any host without a POSIX interpreter, and skill-suite is ubuntu-only, but a developer on a Windows box with Git Bash sees it go red — validation N5, agreed, follow-up), and the F2 integration pin uses `exit 3` rather than a real wrapper arm, so it proves the quoting reaches the engine but not that a spaced path survives the wrapper itself.

**N1 / N2 disposition (asked explicitly).** N1 is a two-line move and it changes how this PR's own Windows CI failure would read — remediate in tree. N2 is a residual on an observational field that keys no behavior, with false positives AND false negatives that need a `^Commands:`-anchored parse to close properly — promote to a follow-up ref, do not hand-tighten the regex again in this scope.

## Merge fitness

Not mergeable as-is: B1 alone (the CHANGE-0134 heading must be restored above this scope's entry). Everything else is disposition work. Beyond the code:

1. B1 fixed; NB-1, NB-4, NB-5, NB-6 recommended in-tree (all one-to-few-line edits, all inside this scope's own files).
2. NB-2, NB-3, NB-7, NB-8 need an orchestrator-recorded disposition — decisions.jsonl entry or a follow-up CHANGE/ISSUE id — per the H6 warnings policy. My recommendation: NB-3 and NB-2 as one follow-up ref (doctor report readability), NB-7 as one follow-up ref (CAT-16 honesty: ABSENT/unknown states + N2 regex), NB-8 as an in-tree doc sentence.
3. The PR MUST be created with `ci-full` present at run start (selector resolves `mode=selected`, 56 suites dropped, no fail-open fires) — validation's hard lane obligation, unchanged by this review.
4. Spec-AC-01 stays `planned` until ps1-quality / windows-5_1 is green on both engines; then flip it with the job URL and refresh the stale `132/132` figure and the Test Plan (validation N3).
5. STATE hygiene for the orchestrator: `code_review` block, plus the stale `worktree` and `implementation_strategy.source` pointers noted in the preflight.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-1 apostrophe path injection | remediate-in-tree |
| NB-2 text-mode detail blob | promote-to-follow-up-ref (with NB-3) |
| NB-3 SKIP counted as a warning | promote-to-follow-up-ref (with NB-2) |
| NB-4 N1 dead precondition branch | remediate-in-tree |
| NB-5 product-doc evidence pointer | remediate-in-tree |
| NB-6 CHANGELOG stale counts | remediate-in-tree (with B1) |
| NB-7 CAT-16 ABSENT/unknown + N2 regex | promote-to-follow-up-ref |
| NB-8 undocumented Windows wall-clock | remediate-in-tree (one sentence) |

INFO (never gate): `Build-SelfTestReport` non-approved verb; `tests/skills/test-aai-doctor.sh` header still says "Covers TEST-001..022"; CAT-14 `detail:{spawned:false}` vs CAT-15 `detail:{}` asymmetry on degrade paths.

---

```yaml
subagent_result:
  scope: CHANGE-0135 / spec-doctor-win-selftest (code review, git diff main...HEAD @ 9727980)
  role: Validation
  status: FAIL
  started_utc: 2026-08-13T00:21:00Z
  ended_utc: 2026-08-13T00:30:00Z
  duration_seconds: 540
  evidence:
    - command: "git branch --show-current; git diff main...HEAD --stat"
      exit_code: 0
      output_snippet: "feat/doctor-win-selftest; 16 files changed, 2047 insertions(+), 29 deletions(-)"
    - command: "git show main:CHANGELOG.md | grep -c CHANGE-0134 ; grep -c CHANGE-0134 CHANGELOG.md"
      exit_code: 0
      output_snippet: "main: 1 (## [unreleased] — ci(ps1-quality): windows-5_1 ... (CHANGE-0134) [L1]); HEAD: 0 — heading deleted, bullets absorbed under the CHANGE-0135 heading"
    - command: "pwsh -NoProfile -File <scratchpad>/apos.ps1 (verbatim replay of Invoke-SelfTestArmSuccess's here-string with an apostrophe in the interpolated path)"
      exit_code: 0
      output_snippet: "& 'C:\\Users\\O'Brien\\aai-run-tests.ps1' ... ; PARSE ERRORS: 1 -- The string is missing the terminator: \"."
    - command: "bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-doctor.sh"
      exit_code: 0
      output_snippet: "All tests passed! -- TEST-001..034 incl. TEST-023..034"
    - command: "node .aai/scripts/aai-doctor.mjs (real repo, text mode)"
      exit_code: 0
      output_snippet: "CAT-14 SKIP / CAT-15 SKIP / CAT-16 PASS 3/3 + a ~1.2 kB single-line detail blob; DOCTOR ISSUES(4); 0.95s"
  files_changed:
    - docs/ai/reviews/review-20260813T003000Z-CHANGE-0135-doctor-win-selftest.md
  blockers:
    - "BLOCKING B1: CHANGELOG.md:14 — the CHANGE-0134 [unreleased] heading was deleted by cf6f037; CHANGE-0134's bullets are now attributed to CHANGE-0135 and CHANGE-0134 appears nowhere in the file. Restore the heading above this scope's entry."
    - "code_verdict fail is driven by B1 only; eight NON-BLOCKING findings need an H6 disposition (four recommended in-tree, three as follow-up refs, one doc sentence)."
    - "Unchanged process obligations: ci-full label at PR creation; Spec-AC-01 stays planned until ps1-quality / windows-5_1 is green on both engines."
    - "started_utc is the earliest attestable clock anchor (the preceding validation's ended_utc); my own start reading was not captured from the clock and is not estimated."
```

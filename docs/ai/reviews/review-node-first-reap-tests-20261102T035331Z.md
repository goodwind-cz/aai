# Code Review - node-first-reap-tests (round 1)

```yaml
review:
  scope: "origin/main...HEAD (feat/node-first-reap-tests, head 9b3a3258)"
  spec: docs/specs/SPEC-0267-spec-node-first-reap-tests.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-reap-tests.mjs:54-97; TEST-3230, TEST-3231 (node --test 26/26 re-run)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/aai-reap-tests.mjs:72-84,131-142; TEST-3232, TEST-3233" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/aai-reap-tests.mjs:159-217; TEST-3234, TEST-3235" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-reap-tests.sh:1-10, .aai/scripts/aai-reap-tests.ps1:1-9; TEST-3236, TEST-3237 (re-run PASS)" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/lib/aai-reap-tests.test.mjs:381-413; TEST-3238 (re-run PASS)" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/aai-reap-tests.Tests.ps1:85-144; TEST-3239 (re-run, pwsh 7: 4/4, 0 skip); Windows engines only in hosted H1" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/test-aai-run-tests.sh test_019/test_022 diff; test-aai-win-fallback.sh test_009; TEST-3240..3242 (validation r2); spec-amend list --strict rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3243 (re-run PASS); aai-win-dispatch.Tests.ps1 Describe removed" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3244 (validation r2 evidence)" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/system/PROFILES.yaml:88, tests/skills/suite-map.yaml, .github/workflows/ps1-quality.yml:81,107; TEST-3245..3247" }
      - { ac: Spec-AC-11, call: compliant, citation: "255+10+9=274 <= 345; RFC-0017 slice paragraph 'pair 787 to 274 lines'; TEST-3248 (re-run PASS), TEST-3249" }
      - { ac: Spec-AC-12, call: compliant, citation: "docs/TECHNOLOGY.md reaper paragraph, docs/USER_GUIDE.md item 3; TEST-3250" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-reap-tests.sh, line: 6,
          issue: "R-19 (Git Bash on Windows gets the native pass) is close to a no-op: the launcher exports the MSYS $PWD, which the MSYS runtime hands to Windows node as /c/... or C:/... (forward slashes); win32 matches() folds case but not the separators inside the workspace, so it never matches the backslash command lines of native node.exe processes",
          failure_scenario: "Windows host with Git Bash only, agent follows SKILL_LOOP's POSIX line and runs .aai/scripts/aai-reap-tests.sh in C:\\Users\\x\\proj; a leaked 'node.exe C:\\Users\\x\\proj\\node_modules\\vitest\\vitest.mjs' tree is listed but never matched; output 'reaped: 0', leak stays. Fails safe (spares), and the old sh copy under MSYS ps reaped nothing either, so not a regression; the spec's and the coming CHANGELOG's R-19 claim is overstated" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 59,
          issue: "aai-run-tests.sh:59-60 and aai-run-tests.ps1:20-21 still say the platform matrix is kept identical across aai-reap-tests.sh and aai-reap-tests.ps1; the launchers no longer carry it, the module header (aai-reap-tests.mjs:23) does",
          failure_scenario: "a maintainer changing a matrix row follows the run-tests pointer, edits the files it names and never touches aai-reap-tests.mjs; test-aai-win-fallback TEST-009 greps only row keywords, so the module's matrix silently drifts" }
  cannot_verify:
    - { claim: "Windows listing (powershell.exe -Command with WIN_LIST_SCRIPT through spawnSync quoting, CIM, UTF-8 output, DateTimeOffset conversion) and taskkill /T on Windows PowerShell 5.1 and pwsh 7", closes_with: "hosted H1: ps1-quality windows-5_1 both Pester steps list every aai-reap-tests.Tests.ps1 case passed" }
    - { claim: "WSL half on a real distro (probe exit 42, wslpath, delegation without Node -> native summary plus stderr note)", closes_with: "hosted H1 windows-wsl1 leg 5.1 step passing with the native summary" }
    - { claim: "PS 5.1 launcher pass-through of node stdout/stderr (no NativeCommandError wrapping of the stderr lines when the launcher's stderr is redirected) and exit-code propagation", closes_with: "H1 Pester case 4 (refusal, exit 1) and a captured stderr sample from the 5.1 step" }
    - { claim: "R-19: Git Bash launcher path (MSYS env conversion of AAI_REAP_WORKSPACE, win32 match outcome)", closes_with: "a manual run on a Git-Bash-only Windows host; no job runs it (spec residual risk)" }
    - { claim: "Pester case 'pushed location' on Windows CI where GetTempPath may be an 8.3 short path (cwd spelling vs command-line spelling)", closes_with: "H1 Pester listing" }
    - { claim: "CHANGELOG entry (D5, written after LOOP COMPLETE) naming R-1..R-6, R-10, R-12, R-16, R-19", closes_with: "the ship-step CHANGELOG diff; it is in the review scope but not yet in the tree" }
    - { claim: "Mutation records 21/21 and the full selected+CORE sweep", closes_with: "validation r2 evidence (docs/ai/reports/VALIDATION-node-first-reap-tests-r2.md); not re-run by the reviewer per dispatch" }
  overall: pass
```

security_relevant: true

(The workspace and age guards decide which processes this tool may kill; finding NB-1 concerns that scope matching. Recorded as true so later rounds get full rechecks rather than slim ones.)

## Scope

- Diff: `git diff origin/main...HEAD` in `/Users/ales/Projects/aai-worktrees/node-first-reap-tests`
  (branch `feat/node-first-reap-tests`, head `9b3a3258`, 8 commits, 30 files).
- Spec: `docs/specs/SPEC-0267-spec-node-first-reap-tests.md` (SPEC-FROZEN, ceremony 2).
- Intake: `docs/issues/CHANGE-0241-node-first-reap-tests.md`.
- STATE: `worktree.user_decision: worktree`, base `main`, so the `<base>...HEAD` form is the scope.
  `git status` shows only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (runtime
  ledgers, not part of the reviewed diff).

Dispatch note (anti-gaming contract): the dispatch named focus areas (wrong-process kills, the
Node-absent launcher, launcher parity, test hygiene). It did not pre-rate severity or exclude
areas. Recorded here; the whole diff was reviewed, including wiring, docs and the amendments to
closed specs.

## Checks run by the reviewer

| Command | Result |
|---|---|
| `env -u AAI_ROLE node --test tests/skills/lib/aai-reap-tests.test.mjs` | 26/26 pass |
| `env -u AAI_ROLE bash tests/skills/test-aai-reap-tests.sh test_3236_launchers_thin` | PASS |
| `... test_3237_launcher_refusal_and_pwd` | PASS (sh, dash, pwsh refusal; logical-path reap) |
| `... test_3239_pester_reap` | PASS, Total=4 Passed=4 Failed=0 Skipped=0 (pwsh 7) |
| `... test_3243_no_ps_reaper_logic` | PASS |
| `... test_3248_line_budget` | PASS (274 <= 345) |
| `node .aai/scripts/spec-amend.mjs list --strict` | rc 0 |
| `ps axo pid=,etime=,args=` checked for the worktree path before and after | no leftover process |

The reaper was never run against the real worktree. Every reaper run was a test fixture in a
mktemp workspace.

## Verdict 1 - spec_compliance: pass

AC walk (the table at the top). Every Spec-AC row is compliant. TEST-3230 to TEST-3250 exist
under the file paths the Test Plan names. The reviewer re-ran the node, launcher, Pester,
inspection and budget rows; the rest are cited from validation r2.

Deviations from the frozen spec, all judged reasonable. None changes which processes are
reaped:

1. Export signatures: `parsePosixSnapshot(text, now)` and `parseWinSnapshot(text, nowMs)` take a
   second argument the spec does not show. `parseTree` and `WSL_SENTINEL` are extra exports.
   `run(deps)` also injects `cwd`, `now`, `taskkill` and `shLauncher` beyond the spec's list.
   These are test seams, not environment variables or flags, so Article 2 is unaffected.
2. D-LIST: the win32 listing falls back to `pwsh` after *any* `powershell.exe` failure (non-zero
   exit included), not only when it "cannot start" (`aai-reap-tests.mjs:228-231`). This is
   harmless: the same script runs on either engine.
3. Paths outside the spec's inline review-scope list that are touched as mechanical companions:
   `tests/skills/test-aai-hygiene-pack.sh` (suite-map row-count pin 122 to 123),
   `tests/skills/lib/cd-subshell-leak-baseline.tsv`, `docs/INDEX.md`, `docs/ai/roadmap.yaml`,
   `docs/ai/EVENTS.jsonl`, and the five closed specs' re-homed rows plus the SPEC-0249
   `frozen_sha256` restamp. The five contract amendment records exist (TEST-3242) and
   `spec-amend list --strict` exits 0.
4. CHANGELOG.md is in the scope list but not in the diff. D5 places it after LOOP COMPLETE (ship
   convention), so it is pending rather than non-compliant. It goes on the cannot_verify list.
5. Registry: the follow-up for the WSL half's Windows-path scoping is "to be filed at delivery".
   It is not filed yet, which is expected at this stage.

## Verdict 2 - code_quality: pass

No BLOCKING finding.

Safety review of the module against the old sh and ps1 copies (`git show origin/main:...`):

- Scope match (`matches`, :77-84). The token and `workspace + separator` substring logic is the
  same as the sh `case` (glob characters stay literal, prefix-siblings are excluded). It folds
  only on win32. A root workspace is refused before any listing (:189-194). The old copies matched
  everything for `/`, so this narrows.
- Age guards (:54-97). The etime grammar, range guard, impossible-age clamp and sentinel-first
  spare match the sh copy. `DIGITS` without the `m` flag rejects a trailing newline, as R-7 wants.
  A huge minimum age spares everything. The snapshot second is taken after listing (:197-199).
  win32 spares a null creation time and a future one (age < 0 becomes -1).
- pid and pgid. Self and parent are skipped. The sh launcher `exec`s, so `process.pid` and
  `process.ppid` equal the old `$$` and `$PPID`. `pid > 1` adds a further narrowing. The group-kill
  test uses one snapshot taken after matching. If the snapshot fails, the kill falls back to bare
  pids (:162). This is no wider than the old per-pid `ps -o pgid=`. The pid-reuse race between
  listing and kill is inherent and unchanged.
- Windows: one `taskkill /PID n /T /F` per candidate, as before.
- Node-absent launchers. Both print exactly the R-16 line on stderr, nothing on stdout, exit 1.
  This was re-verified under sh, dash and pwsh with a stripped PATH, and from a copy without the
  module. No caller reads the reaper exit code (SKILL_LOOP, VALIDATION, SKILL_BOOTSTRAP only name
  the commands).
- Parity. The sh launcher keeps `${AAI_REAP_WORKSPACE:-$PWD}` (logical path, TEST-3237). The ps1
  launcher sets nothing and relies on `process.cwd()` (Pester pushed-location case). Exit is 0 on
  every reaping path, as before. The WSL delegation argv equals the retired Pester argv.
- Test hygiene. Fixtures are 90 s self-terminating Node sleepers in mktemp roots. They are killed
  strictly by recorded pid, and only while the pid still shows the fixture command line. There is
  an EXIT trap in the bash suite, `after()` in node:test, and AfterEach / AfterAll plus a leftover
  scan in Pester. There is no `pkill`, `killall` or kill by name anywhere in the new tests.

Pre-existing behavior noted, not counted as a finding (identical in the old copies, outside this
scope): a token inside the workspace path itself (for example a checkout named `esbuild-plugin`)
makes every aged command line holding that path a candidate, the caller's grandparent included.
Only self and parent are skipped. With WSL usable and Node in the distro, the delegate's report
replaces the native count (R-12 keeps the old ps1 behavior).

### NON-BLOCKING findings and recommended dispositions (H6)

- **NB-1** `.aai/scripts/aai-reap-tests.sh:6` (with `aai-reap-tests.mjs:77-84`). R-19 is close to
  a no-op, because the MSYS-form workspace never matches backslash Windows command lines. The
  failure scenario is in the YAML. It fails safe, so it is not a regression. Recommended
  disposition: **promote-to-follow-up** (P3). It is the same class as the planned WSL-half
  Windows-path-scoping follow-up (workspace path form differs across environments), so file it with
  that one or fold it in. The CHANGELOG line for R-19 should not claim more than "runs the native
  listing" until it is fixed.
- **NB-2** `.aai/scripts/aai-run-tests.sh:59-60`, `.aai/scripts/aai-run-tests.ps1:20-21`: stale
  matrix pointer. Validation r1 raised the same point as NB-1. Recommended disposition:
  **promote-to-follow-up** (P3), folded into the aai-run-tests phase 5 slice, because the spec
  keeps aai-run-tests untouched. A 2-line comment fix in-tree is the alternative if the
  orchestrator prefers it.

INFO (no gate):
- SPEC-0064 TEST-005 and SPEC-0121 TEST-007..009 rows keep their old `Cmd:` text (Pester on
  aai-win-dispatch.Tests.ps1 / test-ps1-quality.sh). The appended "Re-homed by
  node-first-reap-tests ... TEST-323x" sentence names the true location.
- Pester case 1 asserts `reaped pids: <id>` as a regex prefix. Together with the
  `Wait-Exit $old` assertion this is sufficient.
- Validation r1 NB-3 (TEST-3239 SKIP-CASE when Pester 5 is absent, even on CI) still stands. The
  ps1-quality gate job remains the authoritative runner.

## cannot_verify

See the YAML block. The Windows listing, kill and WSL behavior is proven only by hosted H1. The
R-19 Git Bash path is proven by no job. The CHANGELOG is pending.

## Next steps

1. The orchestrator records NB-1 and NB-2 dispositions (follow-ups via `follow-ups.mjs add`) and
   names them in `code_review.notes`.
2. Write the CHANGELOG entry per D5, wording R-19 conservatively.
3. Open the PR, then hosted checks H1 (Windows 5.1 / pwsh 7 / WSL1 Pester) and H2 before merge
   readiness.

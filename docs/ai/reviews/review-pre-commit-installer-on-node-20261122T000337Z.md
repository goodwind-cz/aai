# Code review round 2: the git hook installer on Node (pre-commit-installer-on-node)

```yaml
review:
  scope: "git diff bf0148d6..HEAD (HEAD cffd32cf, branch feat/pre-commit-installer-on-node; 42 files), delta since round 1: git diff 10d779e8..HEAD (remediation 58eeff80)"
  spec: docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "install-pre-commit-hook.test.mjs:56-66 prepareEnv drops every AAI_ and GIT_ variable; :1623-1636 runInProcess asserts before and after the run; :174-200 inProcessRunProblems plus positive controls :399-408; test-aai-hook-installer-node.sh:27-28 GIT_ scrub; TEST-3980 green; B1 repro exits 0" }
      - { ac: Spec-AC-02, call: compliant, citation: "module shape unchanged apart from writeSlot; TEST-3981 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged since round 1; TEST-3982 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "guard-config.mjs:346-370 bounded exclusive-create loop; new TEST-3983 foreign-temp case :1024-1043; TEST-3983 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged; TEST-3984 green" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3985 now goes through runInProcess (:1458-1479, :1568-1572); green" }
      - { ac: Spec-AC-07, call: compliant, citation: "new env-injection case :1659-1679; TEST-3986 green" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged; TEST-3987 green" }
      - { ac: Spec-AC-09, call: compliant, citation: "install-pre-commit-hook.mjs:432-458 writeSlot loop; TEST-3988 green" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3989 green (bash corpus K01-K31)" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3990 green (pwsh 7 corpus P01-P20)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3991 green" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3992 green" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-3993 green under pwsh 7; 5.1 is H1 (cannot_verify)" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-3994 green" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-3995 green; native Windows is H2 (cannot_verify)" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-3996 green" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-3997 green" }
      - { ac: Spec-AC-19, call: compliant, citation: "CHANGELOG.md:35 adds the --force DR-5, DR-3 and DR-2 shapes; TEST-3998 green" }
      - { ac: Spec-AC-20, call: compliant, citation: "TEST-3999 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-ref-guard.sh, line: 167,
          issue: "The B1 class survives in the re-homed suites. The new helpers git_isolated/install_module/install_ps1 (:167-187) and the re-homed test_618 run in test-aai-hygiene-pack.sh:4907 set GIT_CONFIG_NOSYSTEM and an empty GIT_CONFIG_GLOBAL, but they pass every other GIT_ variable through and never assert the hooks path under the scratch root. The comment at :167-168 says a caller's core.hooksPath 'can never redirect an installer run', which is false. aai-run-tests.sh does not scrub GIT_ either.",
          failure_scenario: "Run `bash tests/skills/test-aai-git-ref-guard.sh test_642_ps1_decline_orders_write_before_removal` with GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<dir>. This is the shape `git -c` passes to its children. The module writes pre-commit, reference-transaction and pre-push into <dir>, outside the suite's scratch root. repro docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh (.out beside it): 3 files, exit 1." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 marshalling through the .ps1 launcher, and the Pester launcher context on native Windows (H1)", closes_with: "ps1-quality windows-5_1 and windows-wsl1 job results on the PR head" }
    - { claim: "Parity hook scenarios with the node twin on native Windows (H2)", closes_with: "ps1-quality windows-parity job on the PR head" }
    - { claim: "The .sh launcher and module under Git Bash with MSYS path conversion (H3); also that the new compgen/usr-bin-grep GIT_ scrub at the top of test-aai-hook-installer-node.sh behaves under Git Bash and Ubuntu", closes_with: "ps1-quality Windows CAT-17 step and the Linux skill-suite job on the PR head" }
    - { claim: "fs.renameSync over an existing hook on Windows when the hook is held open or read-only", closes_with: "a native Windows run with a locked hook" }
    - { claim: "The full sweep at 58eeff80 (141 PASS, 1 environmental SKIP) and mutation-gate exit 0 / replay 20/20", closes_with: "VALIDATION-20261121T232324Z; not re-run here (no sweep in review). This review re-ran the whole node:test file under a hostile GIT_ environment (155/155, victim empty) and the two ride suites (aai-hook-installer-node 20/20 TEST rows, aai-hook-installer-docs PASS)" }
    - { claim: "A real downstream layer upgraded through /aai-update then SKILL_UPDATE step 4", closes_with: "TEST-3996 simulates it; a real consumer run on the first release" }
  overall: pass
```

security_relevant: true

## Scope and inputs

- Scope: `git diff bf0148d6..HEAD` at HEAD `cffd32cf` (42 files), in full mode. The delta since round 1 (`git diff 10d779e8..HEAD`) got particular attention. In code, that delta is remediation commit `58eeff80`. The other two commits after round 1 are the round-1 report and repro (`917bca4c`) and telemetry (`cffd32cf`). STATE `worktree.user_decision: worktree`, base `bf0148d6`. The working tree has one uncommitted change, the append-only `docs/ai/EVENTS.jsonl`, which is outside the reviewed code.
- Spec: the frozen `docs/specs/SPEC-0308-spec-pre-commit-installer-on-node.md`, at L3. Its amendments are unchanged since round 1, all additive and unsigned. The only spec edit in the delta is the four Test Plan Status cells (N4).
- Inputs read: the round-1 report and its B1 repro, and the latest validation `VALIDATION-20261121T232324Z` (PASS) as context.
- Dispatch note: the dispatch named the known follow-ups and asked for focus areas. It did not pre-rate any new finding or exclude any area, so no coaching is recorded.

## Round-1 findings, rechecked

| Id | Status | Evidence |
|---|---|---|
| B1 | **fixed** | The round-1 repro exits 0 at HEAD: the in-process helper wrote 0 files outside the root, and the spawn helper wrote 0. The whole node:test file was run with `GIT_CONFIG_COUNT/KEY_0/VALUE_0` and `GIT_CONFIG_PARAMETERS` pointed at a scratch victim: 155/155 pass and the victim stays empty. `prepareEnv` drops every `GIT_` variable. `runInProcess` (test.mjs:1623-1636) calls `assertHooksUnderRoot` before the run and re-checks the hooks dir after it. The five former direct `run()` calls now go through it. The checker `inProcessRunProblems` has positive controls, and the TEST-3980 name now holds within the node:test file. |
| N1 | **fixed** | Probe `r2probe/eexist.mjs` (scratchpad) checked both writers. (1) With five foreign names taken, the writer uses `.5` and every foreign file is intact. (2) With all 101 names taken, both writers throw EEXIST, nothing is created or removed, and the config is unchanged. (3) When the rename fails, only the run's own temp is removed and the foreign `.aai-tmp.<pid>` survives. (4) A foreign dangling symlink at the first name is neither followed nor removed, and the write succeeds. The loop is bounded at 101 attempts. `slot.tmp` is set only after a successful create, so `landingFailure` removes only a name this run created. |
| N2 | **fixed** (residual filed) | CHANGELOG.md:35 now names `--force` with `--uninstall`/`--print`/`--decline-ref-guard`, PowerShell `-F`/`-Verbose`, and the `.ps1` unknown-argument exit 2. The `--hooks --print` half is the known `fu-changelog-dr5-hooks-print`. |
| N3 | accepted residual (unchanged) | "accepted residual: re-homed .ps1 tests 608/631/637/646/309 pass without assertions on a host without pwsh; CI requires pwsh through TEST-3994 need_pester and the module properties are covered by TEST-3982/3984" |
| N4 | **fixed** | Spec Test Plan rows TEST-3996 to TEST-3999 read `green`. |

## AC table walk

All 20 Spec-AC rows are compliant (citations in the YAML block). Evidence run in this review:
- `node --test tests/skills/lib/install-pre-commit-hook.test.mjs` under the hostile `GIT_` environment: 155 tests, 155 pass, 0 skipped. That is 152 from round 1 plus three new cases: the TEST-3980 in-process rule, the TEST-3983 foreign temp and the TEST-3986 env injection.
- `aai-run-tests.sh bash tests/skills/test-aai-hook-installer-node.sh`: every row from TEST-3980 to TEST-3997 PASS, then "All aai-hook-installer-node tests passed" (162 s).
- The wrapper's tripwire named the two R2-N1 repro files. This reviewer wrote them into `docs/ai/reviews/` while the suite was running. The suite did not create them.
- `aai-run-tests.sh bash tests/skills/test-aai-hook-installer-docs.sh`: TEST-3998 and TEST-3999 PASS.

Deviations from the frozen spec: the same as round 1 (three self-amendments, and the extra SPEC-0184/SPEC-0307 records covered by the scope amendment). The remediation adds none.

## Findings

### R2-N1 (NON-BLOCKING, P2): the B1 class in the re-homed suites

- **Where:**
  - `tests/skills/test-aai-git-ref-guard.sh:167-187`. These are `git_isolated`, `install_module` and `install_ps1`, all added by this diff. They are used by the re-homed TEST-633, 641, 642, 644, 309, 647 and others.
  - `tests/skills/test-aai-hygiene-pack.sh:4907`, the re-homed test_618 plain install.
- **What:** these runs set `GIT_CONFIG_NOSYSTEM=1` and an empty `GIT_CONFIG_GLOBAL`. They do not drop the caller's other `GIT_` variables, and they do not assert the resolved hooks path under the scratch root. The comment at :167-168 claims a caller's core.hooksPath "can never redirect an installer run".
- **Bite:** repro `docs/ai/reviews/review-pre-commit-installer-on-node-20261122T000337Z-repro-N1.sh` (output in `.out`) injects `core.hooksPath` through `GIT_CONFIG_COUNT`. test_642's `install_module` then writes all three hooks into the victim directory and exits 1.
- **Why NON-BLOCKING:**
  - Spec-AC-01 and D-SAFETY require the scrub-plus-assert only of "the new suite and the node:test file", and those two now hold.
  - The new helpers are strictly better than the pre-ride `install_guard` in the same suite, which has no git-config isolation at all (round-1 INFO).
  - So the ride does not widen the exposure. It just did not close it where it re-homed tests.
  - P2 rather than P3, because it touches the owner's rule that hooks land only in repositories the test created, and it bites under a realistic environment (a suite started under `git -c ...` or from a hook).
- **Recommended disposition:** (b) promote to follow-up, suggested `fu-suite-git-env-scrub-class`. The fix belongs to the class across the older suites too: `install_guard` in git-ref-guard, the hygiene-pack `SG_INSTALLER` and :5020 helper, and the doctor and pre-commit-checks vendored runs. It could be one `GIT_` scrub in `aai-run-tests.sh` isolation, or the same top-of-suite scrub block test-aai-hook-installer-node.sh now has. Also correct the comment at :167-168.
  - Optional in-tree alternative: copy the two-line scrub from test-aai-hook-installer-node.sh:27-28 to the top of test-aai-git-ref-guard.sh and test-aai-hygiene-pack.sh. It is test-only and low risk, but this is the last review round, so nobody would review that change.

### INFO (no failure mode, never gate)

- `landingFailure` (install-pre-commit-hook.mjs:465-470), the directory branch. It removes `<slot>/<basename(slot.tmp)>`, a name this run checked as free only in the parent directory. With the production `fs.renameSync`, renaming onto a directory throws inside `writeSlot`, so this branch runs only with an mv-like rename seam. It is unchanged in substance since round 1.
- `inProcessRunProblems` recognises only `await run(`. A non-awaited or `mod.run(` call would escape it. Its comment says so, and no such call exists today; every `import(MODULE_URL)` site was read.
- In `writeRefGuardPolicy`'s catch, `if (fd !== undefined) fs.closeSync(fd)` would throw EBADF if the inner `closeSync` had thrown first, and that would mask the original error. This predates the delta.

### Known follow-ups (not re-raised; none found worse than described)

`fu-changelog-dr5-hooks-print`, `fu-classify-socket-long-tmpdir`, `fu-resolvebase-dotdot-after-symlink`, `fu-doubled-key-warning-valueless-first`, `fu-dr20-note-double-slash-pwd`.

## Warning dispositions (H6)

| Finding | Severity | Recommended disposition |
|---|---|---|
| R2-N1 | P2 | (b) follow-up: suggested `fu-suite-git-env-scrub-class` (not filed; the reviewer files no refs) |
| N3 (round 1) | P3 | (d) "accepted residual: re-homed .ps1 tests 608/631/637/646/309 pass without assertions on a host without pwsh; CI requires pwsh through TEST-3994 need_pester and the module properties are covered by TEST-3982/3984" |

## Next steps

1. The orchestrator files `fu-suite-git-env-scrub-class` (P2), or applies the in-tree scrub, and records the N3 residual in the notes.
2. Hosted checks H1 to H3 must be green on the PR head before merge (see cannot_verify).
3. Owner signs the unsigned L3 amendments through the merge direction.

No scratch left behind. The victim directories and the suite scratch were checked. The `aai-git-ref-guard.*` and `review-r2n1-victim.*` directories are gone.

# Code review: the git hook installer on Node (pre-commit-installer-on-node)

```yaml
review:
  scope: "git diff bf0148d6..HEAD (HEAD 10d779e8, branch feat/pre-commit-installer-on-node; 39 files)"
  spec: docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: non-compliant, citation: "tests/skills/lib/install-pre-commit-hook.test.mjs:1563-1571 runMod (and the direct run() calls at :1397, :1408, :1410, :1413, :1510) never call assertHooksUnderRoot; TEST-3980's checker (invocationProblems, :148-165) inspects spawnSync calls only. B1." }
      - { ac: Spec-AC-02, call: compliant, citation: "install-pre-commit-hook.mjs:13-31 anchors; one spawnSync call (:30); no process.stdout/stderr; ASCII; TEST-3981" }
      - { ac: Spec-AC-03, call: compliant, citation: "install-pre-commit-hook.mjs:122-221 parseArgs/resolveMode/resolveBase; TEST-3982" }
      - { ac: Spec-AC-04, call: compliant, citation: "guard-config.mjs:178-179 (BOM), :269-368 writeRefGuardPolicy; TEST-3983 incl. the doctor CAT-17 seam" }
      - { ac: Spec-AC-05, call: compliant, citation: "install-pre-commit-hook.mjs:594-713 (decline writes before unlink :602-606, arm, DR-18 :640-645, DR-17 :654-664); TEST-3984" }
      - { ac: Spec-AC-06, call: compliant, citation: "install-pre-commit-hook.mjs:234-269; TEST-3985" }
      - { ac: Spec-AC-07, call: compliant, citation: "install-pre-commit-hook.mjs:306-331; TEST-3986" }
      - { ac: Spec-AC-08, call: compliant, citation: "install-pre-commit-hook.mjs:377-429, :666-685 (classify all planned slots, refuse before ensureHooksDir); TEST-3987" }
      - { ac: Spec-AC-09, call: compliant, citation: "install-pre-commit-hook.mjs:432-501; TEST-3988" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3989 (bash corpus K01-K31), green in this review's node --test run" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3990 (pwsh 7.6.3 corpus P01-P20), green in this review's node --test run" }
      - { ac: Spec-AC-12, call: compliant, citation: ".aai/scripts/install-pre-commit-hook.sh (9 lines, 100755, ASCII); TEST-3991" }
      - { ac: Spec-AC-13, call: compliant, citation: "vendor-hook-installer.sh:12-13; re-homed TEST-314/618/013/008; spec-amend records; TEST-3992" }
      - { ac: Spec-AC-14, call: compliant, citation: ".aai/scripts/install-pre-commit-hook.ps1 (18 lines, no param block); Pester launcher context; TEST-3993 (pwsh 7 only, 5.1 is H1)" }
      - { ac: Spec-AC-15, call: compliant, citation: "test-aai-git-ref-guard.sh / test-aai-hygiene-pack.sh re-homed functions; TEST-3994" }
      - { ac: Spec-AC-16, call: compliant, citation: "install-parity.mjs:162,176,184-188,816-817; allowlist row widened; TEST-3995 (Windows is H2)" }
      - { ac: Spec-AC-17, call: compliant, citation: "test-aai-hook-installer-node.sh test_3996_scratch_install; TEST-3996" }
      - { ac: Spec-AC-18, call: compliant, citation: "suite-map.yaml, suite-weights.tsv, cd-subshell baseline, ps1-quality.yml both lists; TEST-3997" }
      - { ac: Spec-AC-19, call: compliant, citation: "CHANGELOG.md:33-35 heading and body; SKILL_UPDATE step 4; USER_GUIDE; RFC-0017 row; TEST-3998" }
      - { ac: Spec-AC-20, call: compliant, citation: "follow-ups list: the eighteen D-FU ids done/resolved_by pre-commit-installer-on-node, four suggested ids open, fu-seterr-suspended-left-of-or open; TEST-3999" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/lib/install-pre-commit-hook.test.mjs, line: 1563,
          issue: "The in-process installer helper runMod (and the direct run() calls at :1397-1413 and :1510) runs the module against real git without assertHooksUnderRoot, and prepareEnv (:56-64) strips only AAI_*, GIT_DIR and GIT_WORK_TREE. TEST-3980's test 'every installer invocation sets the git environment and asserts the hooks path under the scratch root' (:330) checks spawnSync call sites only, so its universal name is not proved.",
          failure_scenario: "Run the node:test file with core.hooksPath in the environment (GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=core.hooksPath GIT_CONFIG_VALUE_0=<dir>, the shape `git -c` hands to children as GIT_CONFIG_PARAMETERS). TEST-3988 writes pre-commit, reference-transaction and pre-push into <dir>, outside its own scratch root. The spawn helper refuses the same environment. backed-by: repro docs/ai/reviews/review-pre-commit-installer-on-node-20261121T224259Z-repro-B1.sh (output beside it, .out)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/install-pre-commit-hook.mjs, line: 443,
          issue: "writeSlot's catch calls fs.rmSync(tmp) also when openSync(tmp, 'wx') failed with EEXIST, so it deletes a <slot>.aai-tmp.<pid> that this run did not create. guard-config.mjs:356-359 does the same for <cfg>.aai-tmp.<pid>. D-SAFETY says the module deletes only its own temp files.",
          failure_scenario: "A crashed earlier run left <hooks>/pre-commit.aai-tmp.<N> behind, and a later run gets pid N. That run exits 1 ('internal error: EEXIST') and deletes the file. Probe in this report: writeSlot and writeRefGuardPolicy both throw EEXIST and the pre-existing file is gone." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 35,
          issue: "The note lists 'the behaviour changes you can notice' but leaves out DR-5, DR-3 and DR-2 (ps1), each of which breaks an invocation that used to succeed. D-DOCS asked only for DR-4/6/11/12/15/16/17, so this is spec-compliant, but downstream readers will take the list as complete.",
          failure_scenario: "A downstream script or alias that runs `install-pre-commit-hook.sh --force --uninstall` (exit 0 before; force ignored) now exits 2 ('--force has no effect with --uninstall'). A Windows user running `install-pre-commit-hook.ps1 -F` or `-Verbose` now gets exit 2. Neither change is in the release note." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-git-ref-guard.sh, line: 1176,
          issue: "Re-homed .ps1 tests TEST-608, 631, 637 and 646 (and the .ps1 arm of TEST-309) now return 0 with no assertion when pwsh is absent. They used to carry static pins that always ran. This is the vacuous-pass class of fu-test641-passes-without-pwsh, which the ride closes for TEST-641 only.",
          failure_scenario: "On a host without pwsh, `bash tests/skills/test-aai-git-ref-guard.sh test_608_ps1_hooks_static` prints PASS-equivalent output with zero assertions. Mitigated: TEST-3994 runs them under need_pester, which fails on CI without pwsh, and the module-level properties are covered by TEST-3982 and TEST-3984." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md, line: 1245,
          issue: "The Test Plan Status cells of TEST-3996 to TEST-3999 still read 'pending', while the AC Status table says done and RED/GREEN/mutation records exist for all four.",
          failure_scenario: "A reader or a later audit that reads the Test Plan table sees four rows still pending on a closed spec." }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 marshalling through the .ps1 launcher, and the Pester launcher context on native Windows (H1)", closes_with: "ps1-quality windows-5_1 and windows-wsl1 job results on the PR head" }
    - { claim: "Parity hook scenarios with the node twin on native Windows (H2)", closes_with: "ps1-quality windows-parity job on the PR head" }
    - { claim: "The .sh launcher plus the module under Git Bash, where MSYS converts the module path (H3, Windows CAT-17 step)", closes_with: "ps1-quality Windows CAT-17 step on the PR head" }
    - { claim: "fs.renameSync over an existing hook on Windows, when the hook is held open or read-only", closes_with: "a native Windows run with a locked hook; nothing in the suites does this" }
    - { claim: "The full sweep (141 PASS, 1 environmental SKIP) and mutation-gate exit 0 at 10d779e8", closes_with: "validation report VALIDATION-20261121T223100Z; not re-run here (the review must not overlap a sweep). This review re-ran only node --test of install-pre-commit-hook.test.mjs: 152/152 pass." }
    - { claim: "A real downstream layer upgraded through /aai-update then SKILL_UPDATE step 4", closes_with: "TEST-3996 simulates it with a scratch older layer; a real consumer run on the first release" }
  overall: fail
```

security_relevant: true

## Scope and inputs

- Scope: `git diff bf0148d6..HEAD`, HEAD `10d779e8` on `feat/pre-commit-installer-on-node`, worktree `/Users/ales/Projects/aai-worktrees/pre-commit-installer-on-node`. That is 39 files, the same as STATE `code_review.scope`. The working tree had one unrelated modification, the append-only `docs/ai/EVENTS.jsonl`, which is outside the reviewed code.
- Spec: the frozen `docs/specs/SPEC-DRAFT-pre-commit-installer-on-node.md`, ceremony L3. It carries 15 contract amendment records of ref `pre-commit-installer-on-node`. Three of them amend this spec itself: the scope addition, DR-23 and the DR-23 extension. All 15 are unsigned (`--signoff none`), so the owner signs them by the merge direction. `spec-lint` passes and `spec-amend list --strict` exits 0.
- Intake: `docs/issues/CHANGE-DRAFT-pre-commit-installer-on-node.md`. Plan: `docs/analysis/node-first-remaining-plan.md`, ride 11.
- Dispatch note: the dispatch listed focus areas. It did not pre-rate any finding or exclude any area, so it is not recorded as coaching. The full scope was reviewed.
- Prior validation reports (rounds 1 to 3, final PASS) were read as context only. Their open R3-N1 to R3-N4 are not repeated below except where noted.

## Evidence run in this review

- `env -u AAI_ROLE node --test tests/skills/lib/install-pre-commit-hook.test.mjs`: 152 tests, 152 pass, 0 skipped (pwsh 7.6.3 present, so the PowerShell corpus ran).
- B1 repro: `docs/ai/reviews/review-pre-commit-installer-on-node-20261121T224259Z-repro-B1.sh` exits 1, output in `.out`. The in-process helper wrote 3 hooks outside the scratch root. The spawn helper wrote 0 under the same environment.
- The `.ps1` launcher's marshalling under `-File` was checked with a stub module (pwsh 7.6.3):
  - `-Hooks:close-gate` arrives as `-Hooks`, `close-gate`.
  - `-Force:$false` arrives as no argument at all.
  - `-Force:$true` arrives as `-Force`.
  - In session, `-Hooks:close-gate -Force:$true -Hooks "a b"` arrives as `-Hooks close-gate -Force -Hooks "a b"`.
  - The exit code 7 passed through in every case.
- N1 probe (scratchpad script). For both `writeSlot` and `writeRefGuardPolicy`, a pre-existing `<target>.aai-tmp.<pid>` makes the call throw EEXIST, and the file is gone afterwards.
- No scratch was left behind under `$TMPDIR` by these runs (`aai-hk-*` and the repro victim directory were both checked).

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| 01 | non-compliant | The SHALL is that "every installer invocation helper ... SHALL ... assert that the resolved hooks path lies under the run's own scratch root". `runMod` (test.mjs:1563) and the direct `run()` calls (:1397, :1408, :1410, :1413, :1510) do not assert it. The rest holds: the removal helpers refuse each unsafe path, the reference copies are hash-pinned, and the forbidden-call scan is clean. |
| 02 | compliant | Anchors are at mjs:17-31. There is one spawnSync call (:30), no `process.stdout`/`process.stderr`, the D4 comment appears once (:612) and the file is ASCII. TEST-3981. |
| 03 | compliant | parseArgs/resolveMode (:131-198) follow the D-CLI order. resolveBase (:210-221) checks identity on the returned path. TEST-3982. |
| 04 | compliant | The reader ignores one leading BOM (guard-config:178-179). The writer (:269-368) follows the link, keeps mode, per-line EOL and BOM, collapses doubled or value-less keys, refuses an unwritable target before creating a temp, and does a read-back. TEST-3983 includes the CAT-17 DECLINED seam. |
| 05 | compliant | Plain skip via SKIP_DECLINED (:671). Decline refuses a foreign hook and writes before the unlink (:594-610). Arm attests and then records (:614-629). DR-18 is at :640-645, the DR-17 warning at :654-664. TEST-3984. |
| 06 | compliant | Templates are read from scriptDir with CR stripped. Missing or malformed templates are named, and composePreCommit adds the final LF (:234-269). TEST-3985. |
| 07 | compliant | git `--git-path` per slot, with relative answers joined to the base (:306-331). Not-a-repo and git-missing lines. TEST-3986. |
| 08 | compliant | Every planned slot is classified before ensureHooksDir. A declined unforced slot is not planned (:671-672). bad-type is refused in all slots, and refusals print in slot order (:666-685). TEST-3987. |
| 09 | compliant | Temp plus `io.rename`, a landing check on every write, upgrade by insertion or refresh, the marked-differs NOTE, 0777 minus umask, post-run attestation, and the win32 skip (:432-501, :528-553). TEST-3988. |
| 10 | compliant | TEST-3989 corpus, green here. |
| 11 | compliant | TEST-3990 corpus under pwsh 7.6.3, green here. |
| 12 | compliant | The launcher is 9 lines, `#!/bin/sh`, 100755, ASCII and holds no policy token. TEST-3991. |
| 13 | compliant | The helper copy lines appear once each. The SPEC-0156/0011/0013/0184 records exist. TEST-3992. |
| 14 | compliant (pwsh 7) | The launcher is 18 lines with no param block. The five Pester launcher cases pass. Windows PowerShell 5.1 is H1 (cannot verify). TEST-3993. |
| 15 | compliant | The thirteen re-homed functions hold no `.ps1` text reads. The SPEC-0184/0156/0201/0278 records exist. TEST-3994. |
| 16 | compliant | hkref is materialized once. sh and ps1 run the frozen references, node runs the vendored module, and the allowlist row is widened. Native Windows is H2 (cannot verify). TEST-3995. |
| 17 | compliant | Core sync, three launchers with byte-equal hooks, the refusal without node, and the update order from a committed scratch source. TEST-3996. |
| 18 | compliant | The suite-map rows (aai-git-hook-templates is covered by its `install-pre-commit-hook.*` glob), weights 196 with the fallback lines, test_090 at 142, the baseline at 1, and identical ps1-quality lists. TEST-3997. |
| 19 | compliant | The heading appears once with Node.js 22 and DR-4/6/11/12/15/16/17 (plus DR-23). SKILL_UPDATE step 4, USER_GUIDE and the RFC sentence are present. TEST-3998. |
| 20 | compliant | All 18 D-FU ids are `done` with resolved_by this ref. The four suggested ids are open with this ref, and fu-seterr-suspended-left-of-or is open. TEST-3999. |

Deviations from the frozen spec, including reasonable ones:
1. The spec was amended three times by its own ride: scope, DR-23 and the DR-23 extension. All are unsigned and additive with disclosure.
2. The Test Plan Status column still shows TEST-3996 to TEST-3999 as `pending` (N4).
3. There are three SPEC-0184 records where D-REHOME named two. The extra one is "TEST-632 key pin on the sh half re-homed early". There is also one SPEC-0307 record (test-aai-update-node.sh) that the spec did not name. The scope amendment covers both.

## Findings

### B1 (BLOCKING): the in-process installer runs skip the hooks-path assertion, and TEST-3980's universal name does not hold

- **Where:**
  - `tests/skills/lib/install-pre-commit-hook.test.mjs:1563-1571` (`runMod`).
  - The direct `run()` calls at :1397, :1408, :1410, :1413 (TEST-3985 missing templates) and :1510 (TEST-3985 bytes).
  - `prepareEnv` at :56-64.
  - The checker `invocationProblems` at :148-165 and the test at :330.
- **What:** `runInstaller` (the spawn path) calls `assertHooksUnderRoot` before every run. The in-process path runs the same module against real git with only `prepareEnv`, and `prepareEnv` removes only `AAI_*`, `GIT_DIR` and `GIT_WORK_TREE`. Git still honours `GIT_CONFIG_COUNT/KEY_n/VALUE_n`, `GIT_CONFIG_PARAMETERS` (exported by `git -c ... <cmd>` to its children, hooks included) and `GIT_COMMON_DIR`. Through any of them, `core.hooksPath` or the common dir can point the module's writes outside the scratch root. The self-check that is supposed to stop this scans only `spawnSync` call sites, so in-process runs are invisible to it. The test still claims "every installer invocation ... asserts the hooks path under the scratch root". Canon makes a universal test name over a subset of paths BLOCKING.
- **Bite (repro):** `bash docs/ai/reviews/review-pre-commit-installer-on-node-20261121T224259Z-repro-B1.sh`
  1. With `core.hooksPath` injected through the environment, TEST-3988 "a hook made non-executable ..." writes `pre-commit`, `reference-transaction` and `pre-push` into a directory outside its scratch root.
  2. Under the same environment, the spawn-based TEST-3986 refuses with "the hooks path ... lies outside the scratch root" and writes nothing.
- **Why it matters here:** the owner's rule for this ride, D-SAFETY and Spec-AC-01, is that hooks are installed only into repositories the test created. The in-process path is the one place where that rule is not enforced.
- **Fix (small):**
  1. Call `assertHooksUnderRoot(cwd, root, env)` inside `runMod`, and route the five direct `run()` calls through `runMod` (or a sibling helper that asserts).
  2. Make `prepareEnv` drop every `GIT_*` variable except the ones it sets, or at least `GIT_CONFIG_PARAMETERS`, `GIT_CONFIG_COUNT`/`KEY_*`/`VALUE_*`, `GIT_COMMON_DIR`, `GIT_INDEX_FILE` and `GIT_OBJECT_DIRECTORY`.
  3. Extend `invocationProblems` to flag an in-process `run(` of the module outside the asserting helper, and add a positive control, so the test name becomes true.
- **Regression test:** the repro as a node:test case. Inject `GIT_CONFIG_COUNT` core.hooksPath and require `runMod` to throw before writing.

### N1 (NON-BLOCKING, P3): a temp file the run did not create is deleted on EEXIST

- **Where:** `.aai/scripts/install-pre-commit-hook.mjs:436-446` (`writeSlot`) and `.aai/scripts/lib/guard-config.mjs:340-359` (`writeRefGuardPolicy`).
- **What:** `catch (e) { fs.rmSync(tmp, { force: true }); throw e; }` also runs when `openSync(tmp, 'wx')` itself failed with EEXIST. The file at `tmp` then belongs to someone else, most likely an earlier crashed run.
- **Scenario:** the stale `<slot>.aai-tmp.<N>` of a crashed run meets a later run with pid N. That run prints `internal error: EEXIST ...`, exits 1 and deletes the file.
- **Recommended disposition:** remediate-in-tree. Remove the temp only after this call created it, the way `fd !== undefined` is already tracked in guard-config.

### N2 (NON-BLOCKING, P3): the CHANGELOG list of noticeable changes omits three invocation breaks

- **Where:** `CHANGELOG.md:35`.
- **What:** three changes are missing from the list:
  - DR-5: `--force` with `--print`, `--uninstall` or `--decline-ref-guard`, and `--hooks` with `--print`, now exit 2.
  - DR-3: PowerShell abbreviations such as `-F` and common parameters such as `-Verbose` now exit 2.
  - DR-2: an unknown argument to the `.ps1` now exits 2 instead of 1.

  `--force --uninstall` used to exit 0. This is spec-compliant (D-DOCS names seven DRs), but the sentence reads as a complete list.
- **Recommended disposition:** remediate-in-tree. Add one sentence naming DR-2, DR-3 and DR-5. TEST-3998 still passes, because it only requires the listed tokens.

### N3 (NON-BLOCKING, P3): the re-homed .ps1 tests pass with no assertion without pwsh

- **Where:** `tests/skills/test-aai-git-ref-guard.sh` test_608 (:1176), test_631, test_637, test_646, and the `.ps1` arm of test_309.
- **What:** without pwsh they `log_info` and `return 0`. They used to hold static pins that always ran. CI is protected by TEST-3994's `need_pester` (it fails on CI without pwsh), and the module-level properties are covered by TEST-3982 and TEST-3984.
- **Recommended disposition:** (d), accepted residual. This is an assurance-strength gap only: nothing bit, and no false record is left, because each test prints "not exercised this run".

### N4 (NON-BLOCKING, P3): stale Test Plan status cells

- **Where:** spec lines 1245-1248.
- **What:** TEST-3996 to TEST-3999 read `pending`, while their AC rows are `done` and their RED, GREEN and mutation records exist.
- **Recommended disposition:** remediate-in-tree at the close amendment. Flip the four cells to `green`.

### Carried from validation, not re-raised

R3-N1 (the doubled-key warning says "the first one wins" when the first key line has no value, mjs:662), R3-N2, R3-N3 and R3-N4 are still open and need their own dispositions from the orchestrator. This review confirms R3-N1 by reading: `readRefGuardPolicy` skips a value-less line (guard-config:180-181), while the writer counts it as a key line.

### INFO (no failure mode, never gate)

- `tests/skills/test-aai-docs-audit.sh:3256`: the comment says "the .ps1 follows in the next ride". It followed in this ride.
- SKILL_UPDATE step 4 says the installer "checks every slot before writing any". A declined, unforced ref-guard slot is deliberately not checked (DR-11).
- The policy writer replaces the file by rename. That keeps the mode, but a hard link to `docs/ai/docs-audit.yaml` is split, and owner and ACLs follow the writing user. The bash replace branch behaved the same way.
- TEST-633 counts the decline-path sentence once. The same first-line sentence also exists, in other template forms, in `foreignRefusal` (:507, :515). The texts differ, so a recorded mutation cannot collide.
- Suites that existed before this ride (`install_guard` in git-ref-guard, the vendored runs in doctor and pre-commit-checks) still start the installer without `GIT_CONFIG_GLOBAL` isolation. This is not introduced by this diff and is outside the ride's scope. It is noted because those suites now run the module.

## Focus-area notes (dispatch list)

1. **Writes:**
   - A refusal is computed for every planned slot before `ensureHooksDir`.
   - bad-type slots are refused even with `--force`.
   - Links are followed only for no-write states. `--force` replaces the link itself.
   - Decline follows a link to a foreign hook and refuses it, and refuses a bad-type slot (DR-23).
   - The landing check covers every write.
   - core.hooksPath and linked worktrees come from git itself.

   No product-path defect was found beyond N1.
2. **Launchers:**
   - Both are within 20 lines and hold no policy.
   - `exec node` preserves the exit code and `exit $LASTEXITCODE` passes it on.
   - Both refuse when node or the module is missing.
   - The `.ps1` marshalling was verified under `-File` and in session (pwsh 7). 5.1 is H1.
3. **guard-config:**
   - The writer follows the link, keeps the mode, keeps EOL and BOM per line, repairs a doubled key and reads back.
   - The reader's only change is the single leading BOM.
   - Readers: aai-doctor CAT-17 (`readRefGuardPolicy`, the intended DR-16 change) and the module. The hook templates and `pre-commit-checks.sh` read no `ref_guard`.
4. **Test safety:**
   - The bash suite: `run_installer` and `install_env_run` assert the hooks path, `safe_rm_own` refuses unsafe paths, cleanup runs from an EXIT trap keyed by pid, and there is no container or kill call.
   - The node:test file: B1.
5. **Pins:** the re-homed pins now run behaviour (launcher under pwsh, or the module). Every DR row cites a test. N3 is the gap when pwsh is absent.
6. **Parity and wiring:** the third twin, hkref, the allowlist row, the ps1-quality lists, suite-map and weights are correct.
7. **CHANGELOG:** the `## [unreleased] — feat: ...` heading form is right and the Node 22 note is present. N2.
8. **Follow-ups:** the eighteen closures match implemented behaviour, checked by reading DR-4/5, DR-8, DR-10, DR-11, DR-15 to DR-19 and the SKILL_UPDATE text.

## Warning dispositions (H6)

| Finding | Severity | Recommended disposition |
|---|---|---|
| N1 | P3 | remediate-in-tree |
| N2 | P3 | remediate-in-tree |
| N3 | P3 | (d) accepted residual: "accepted residual: re-homed .ps1 tests 608/631/637/646/309 pass without assertions on a host without pwsh; CI requires pwsh through TEST-3994 need_pester and the module properties are covered by TEST-3982/3984" |
| N4 | P3 | remediate-in-tree at the close amendment |

The orchestrator records each disposition. This reviewer files no refs.

## Next steps

1. Fix B1 (helper assertion, GIT_* scrub, checker extension) with a RED-first regression test.
2. Fold N1, N2 and N4 into the same remediation, and record N3's residual.
3. Re-review the delta. Hosted checks H1 to H3 are needed on the PR head before merge.

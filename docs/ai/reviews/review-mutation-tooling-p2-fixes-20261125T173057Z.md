```yaml
review:
  scope: "git diff a83f7b0f -- .aai/scripts/mutation-run.mjs .aai/scripts/mutation-gate.mjs .aai/scripts/lib/mutation-record.mjs .aai/scripts/close-work-item.mjs .aai/scripts/spec-lint.mjs .aai/scripts/spec-freeze.mjs tests/skills/lib/close-work-item-pin.sh tests/skills/test-aai-mutation-gate.sh tests/skills/test-aai-close-work-item.sh tests/skills/test-aai-spec-lint.sh tests/skills/test-aai-session-lock.sh tests/skills/test-aai-test-canon.sh docs/specs/SPEC-0181-spec-mutation-gate-for-tests.md CHANGELOG.md (uncommitted tree, worktree fix/p2-mutation-tooling, round 2)"
  spec: docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "mutation-run.mjs:462-480 assertRegularTarget; :1121-1126 source check; :512 clone check before apply; :534 clone re-check after git apply (round-1 BLOCKING-1 fix); :1532-1536 --check patch arm; TEST-4110 PASS (typechange and outside arms now assert the reason)" }
      - { ac: Spec-AC-02, call: compliant, citation: "mutation-run.mjs:385 new RegExp(parsed.pattern, parsed.flags); TEST-4111 PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "test-aai-session-lock.sh:314; test-aai-test-canon.sh:1189; TEST-4112 and TEST-4113 PASS; session-lock test_409 rc 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "mutation-run.mjs:1135-1145 read once; :1070-1074 storePatchCopy(bytes); :524-525 apply from a copy under tmpBase; TEST-4114 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "mutation-run.mjs:485-494 parseCheck; :539-541 refusal; TEST-4115 PASS" }
      - { ac: Spec-AC-06, call: compliant, citation: "mutation-gate.mjs:328 guard; TEST-4116 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "close-work-item.mjs:783-795 isPostMergeClose, :1228-1230 mutationGateArgs; TEST-4117 PASS; TEST-533 PASS; live sha256 2307a652... equals the new pin entry" }
      - { ac: Spec-AC-08, call: compliant, citation: "mutation-run.mjs:676-700 removeCloneTrackedDelete, :708-716 ENOENT branch; TEST-4118 PASS (arms A/B, the git-apply hardening, are outside the frozen row; see deviation DEV-1)" }
      - { ac: Spec-AC-09, call: compliant, citation: "lib/mutation-record.mjs:150-158 stampForFileName; TEST-4119, TEST-474, TEST-492, TEST-500, TEST-501 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "spec-lint.mjs:604, :622-624; spec-freeze.mjs:93; TEST-4120 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "mutation-run.mjs:1470-1553 checkOne; TEST-4121 PASS; probe r2-check-patch.sh: a valid --patch gives CHECK OK exit 0" }
      - { ac: Spec-AC-12, call: compliant, citation: "CHANGELOG D-WIRE heading present; SPEC-0181 D-AMEND heading present; spec-amend list --strict rc 0; none of the 12 ids open; TEST-4122 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md, line: 177,
          issue: "DEV-1: the git-apply hardening added in remediation (runGitApply: stdin closed, 120 s default timeout, overlay diff passed as a file, a timed-out overlay apply is now fatal) is not in any D-section of the frozen spec, and the TEST-4118 Test Plan row does not describe arms A/B. It is disclosed only in CHANGELOG, --help and a source comment. No spec_amendment record covers it.",
          failure_scenario: "A downstream overlay git apply that runs past 120 s (a large tracked diff on a slow runner) used to be a soft failure the overlay recovered from. It now exits with 'git apply timed out'. Someone reading the closed spec, the durable contract of this ride, finds no rule that explains the new fatal path." }
      - { rank: NON-BLOCKING, file: .aai/scripts/mutation-run.mjs, line: 1531,
          issue: "In --check's patch arm, the scratch-dir runGitApply is the only apply that no try/fail wraps. An apply that passes `git apply --check` in the tree and then fails in the scratch dir surfaces as a generic error, not as a CHECK FAIL <class> line at exit 5.",
          failure_scenario: "Theoretical: the scratch dir is outside the repository, so repo-local apply config (for example apply.whitespace) or attribute-driven differences could make the two applies disagree. Not reproduced; P3 message-class accuracy only. No write happens, and the finally block removes the scratch dir." }
  cannot_verify:
    - { claim: "Windows behaviour of assertRegularTarget (path.sep split), parseCheck's 'bash' lookup, runGitApply's timeout/kill, and the stamped names on NTFS",
        closes_with: "a Windows run of TEST-4110/4115/4118/4119. The hosted skill-suite Windows leg runs Pester only, not these bash tests" }
    - { claim: "The source comment and CHANGELOG cause story: 'a --replay once hung 6.5 h on exactly that' (the stdin form). The pre-change overlay call passed `input: diff`, which closes stdin after writing, so the diff alone does not show that the stdin form was the cause.",
        closes_with: "the original hang's process listing or log; TEST-4118 arm A proves only that the stdin form is no longer used" }
    - { claim: "No existing gated cell outside this ride is a deliberately syntax-breaking sed. D5 now refuses such a cell on re-record and counts it INCONCLUSIVE on replay.",
        closes_with: "a --check sweep over the live Mutation cells whose targets exist" }
    - { claim: "The two live m-flag cells and the 69 g-flag cells replay as the spec states",
        closes_with: "mutation-run.mjs --replay on the specs that hold those cells" }
    - { claim: "The branch is green after taking origin/main 01cd7f78: the ledgers rebuilt base-first and the CHANGELOG heading order kept (validation NB-r4-1)",
        closes_with: "the aai-follow-ups and aai-spec-amend suites and the hosted skill-suite on the PR head" }
    - { claim: "The full sweep and Linux bash 5 / GNU userland behaviour of the new suite code",
        closes_with: "the validator's sweep (round 3 rc 0) and the hosted run on the PR head; this review ran 20 selected tests on macOS bash 3.2 only" }
  overall: pass
```

# Code review (round 2): mutation-tooling-p2-fixes

security_relevant: true

(The marker stays true. Round 1's BLOCKING-1 was a write outside the clone, so every later report of this ref says true.)

- **Scope:** explicit paths (STATE `code_review.scope`), diffed with `git diff a83f7b0f -- <paths>` in `/Users/ales/Projects/aai-worktrees/p2-mutation-tooling` (branch `fix/p2-mutation-tooling`, uncommitted, base a83f7b0f; origin/main has since moved to 01cd7f78).
- **Spec:** `docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md` (frozen).
- **Reviewer:** dispatched Code Review role, rule 13, `AAI_ROLE=subagent`. No STATE write; I did not write this code.
- **Coaching record:** none. The dispatch asked for particular attention to the post-round-1 delta. It did not characterize expected findings, pre-rate severity or exclude any area, and I reviewed the full scope.

## Round-1 findings: how each was resolved

| Round-1 finding | Resolution | Verified by |
|---|---|---|
| BLOCKING-1: a typechange `--patch` writes through a planted symlink outside the clone | Fixed. `assertRegularTarget(cloneDir, targetRel)` runs again after `git apply` (mutation-run.mjs:534). `--check`'s patch arm applies in a scratch dir and re-asserts (:1531-1536, TARGET-REFUSED). | Round-1 repro `probes/p1-patch-symlink.sh` on the current tree: run rc 2, "has a symlink on its path", `RESULT: victim unchanged`. The new TEST-4110 typechange arm checks the victim's sha256 for both the run and `--check`. Validation round 3 has a mutant M1 RED log. |
| NB-1: TEST-4110's outside arm was vacuous | Fixed. The arm asserts `is outside the repository` and checks that the outside file is unchanged (test-aai-mutation-gate.sh:3310-3313). | TEST-4110 PASS. Validation round-3 mutant M2 RED log. |
| NB-2: the post-merge predicate accepts any ancestor | Promoted to follow-up `fu-postmerge-predicate-any-ancestor` (P3, decisions.jsonl 13:47:27Z, open). | Ledger line present. |
| NB-3: the SPEC-0181 amendment omitted TEST-501 and the 509/517/007 rewrites | Fixed. The amendment text names them (SPEC-0181 "Edited test expectations"), and a second `spec_amendment` record exists (13:48:44Z). `spec-amend list --strict` rc 0. | Diff read; strict list rc 0. |
| NB-4: the remedy suffix is unconditional | Promoted to follow-up `fu-close-remedy-suffix-unconditional` (P3, open). close-work-item.mjs is byte-unchanged since round 1 (sha 2307a652 both rounds), so no re-pin was spent. | Ledger line present; pin TEST-533 PASS. |

## Verdict 1: spec_compliance = pass

Every Spec-AC row is walked in the YAML above. Every claimed TEST was run in this round and passed (see Evidence).

Deviations from the frozen spec:
- **DEV-1: the git-apply hardening is not in the frozen spec.**
  - **What was added, and when:** remediation round 2 ("ITEM 4") added `runGitApply`:
    - stdin is `'ignore'`;
    - a `timeout` with a 120000 ms default (`AAI_MUTATION_GIT_TIMEOUT_MS`), killed by SIGKILL;
    - a named `git apply timed out` error.
  - **Other changes in the same round:**
    - the overlay diff is now passed as a file;
    - a timed-out overlay apply is fatal, where a failed one used to be soft;
    - TEST-4118 grew arms A and B.
  - **Why it is a deviation:** none of this is in D1-D9, and the TEST-4118 Test Plan row does not mention it.
  - **Where it is disclosed:** CHANGELOG and `--help` (the round-3 NB-r3-1 fold), the open follow-up `fu-mutation-apply-timeout-replay-untest`, and a source comment.
  - **What is missing:** no `spec_amendment` record covers it. No Spec-AC is violated, so this does not fail the verdict. Disposition is in the H6 table.
- **D9 exempt statuses (INFO, carried over):** `spec-lint.mjs:604` holds a literal copy of the gate's `EXEMPT_STATUSES`. The values are equal today. This is already tracked as `fu-mutation-exempt-set-duplicated` (P3).
- **AC Status table:** every row still reads `planned`. This is expected: SKILL_PR flips the table at close.

## Verdict 2: code_quality = pass (0 BLOCKING, 2 NON-BLOCKING)

### Post-round-1 delta, read closely

- **The re-assert after apply** (mutation-run.mjs:534) sits after both foreign-path guards and before the first read through `targetAbs`.
  - **Variants checked:**
    - Turning the target into a directory needs a foreign path (`lib/greeting.mjs/x`), which the numstat guard refuses.
    - Turning a parent into a symlink needs a foreign path (`lib`), also refused.
    - A symlink pointing inside the clone (the round-1 forged-RED shape) is refused by the same lstat check.
  - **Replay:** replay goes through the same `applyMutation`, so a typechange patch in a record becomes INCONCLUSIVE there.
- **`--check` patch arm:**
  - It applies only into a scratch copy that holds just the target, then re-asserts, and reads only after the assert.
  - The scratch dir is removed in `finally`. `exit()` throws `ExitSignal` (lib/cli-pipe-guard.mjs:55), so the `finally` always runs.
  - Probed with a valid patch: CHECK OK, exit 0. Probed with TMPDIR inside a git work tree: CHECK OK too, and a real run records RED (probe `r2-check-patch.sh`). So git apply's subdirectory path filtering does not bite here.
- **runGitApply:**
  - It is the only `git ... apply` spawn in the file (grep: one `'apply'` literal, line 420). That supports the CHANGELOG's "every git apply" claim.
  - `ETIMEDOUT` is the code spawnSync sets when a timeout fires.
  - The overlay catch rethrows only `/timed out/`.
  - `overlay.patch` and `mutation-apply.patch` live in `tmpBase`, outside `cloneDir`, so they never enter the clone's tree hash. They are removed with `tmpBase` on every exit path, and arm B asserts a private TMPDIR is empty after a timeout.
- **TEST-4118 arms A and B:**
  - Both are bounded: a perl alarm of 45 s, and the shim pids are killed afterwards.
  - The suite runs `set -uo pipefail` without `-e`, so a `kill` of an already-dead pid cannot abort it.
  - Arm A's shim matches only the 3-argument stdin form. It proves the stdin form is gone; it does not prove that form was the historical cause (see cannot_verify).

### NON-BLOCKING

- **NB-r2-1 = DEV-1 (disclosure, P3).**
  - **Where:** the frozen spec (D7, line 177) and the TEST-4118 row.
  - **Failure scenario:** a slow overlay apply now ends the run fatally, and no spec rule says so.
  - **Disposition:** (a) remediate in tree. Add an additive amendment to this ride's own spec under the additive-with-disclosure convention: `spec-amend.mjs add --spec docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md --ref mutation-tooling-p2-fixes --class contract --signoff none ...`, naming runGitApply, the fatal overlay timeout, `AAI_MUTATION_GIT_TIMEOUT_MS` and TEST-4118 arms A/B. Then run `spec-amend list --strict`.
  - **Alternative:** if the orchestrator judges the CHANGELOG disclosure sufficient, (b) promote it to a follow-up. Suggested id: `fu-spec-omits-git-apply-hardening`.
- **NB-r2-2 (message class, P3).**
  - **Where:** mutation-run.mjs:1531.
  - **Gap:** `--check`'s scratch apply has no wrapper, so it can fail with a generic error instead of a `CHECK FAIL` class.
  - **Bite:** not reproduced. There is no write, and the cleanup runs.
  - **Disposition:** (d) `accepted residual: --check's scratch apply is unwrapped; a tree-passes/scratch-fails divergence was not reproduced, and the only effect is a generic error line in place of a CHECK FAIL class, with no write and no false record.`

### INFO (does not gate)

Carried from round 1, unchanged:
- **TEST-4121:** the AMBIGUOUS count needle is the bare `"2"`.
- **Zero-width pattern:** `s/^/x/m` counts the EOF position as a match.
- **`isRotatedFileName`:** the `[^.]+` pattern misses a dotted sanitized stamp. It is not called anywhere.
- **`./` prefix:** a `./`-prefixed `--target` is refused as foreign by the patch guards.
- **TEST-4120 comment:** the comment for control D promises a placeholder control that is not asserted.

New this round:
- **TEST-4118 log line:** its `log_pass` does not mention the item-4 arms.
- **pid reuse:** the shim pid kill loop could in theory signal a reused pid. The window is sub-second, the same class as memory `stress-test-busy-loop-leak`.
- **NB-r3-2 (validation):** the second SPEC-0181 amendment record carries `ref_id: spec-mutation-gate-for-tests`. It stays informational.

### Checked and found sound (this round)

- **Tests:** all 20 scoped and affected tests PASS (Evidence).
- **Pin:** the live `close-work-item.mjs` sha256 is `2307a652...` and matches exactly one pin entry (TEST-533). close-work-item.mjs did not change after round 1.
- **Gate:** `mutation-gate.mjs --spec <this spec> --require-evidence` gives GATE PASS, 13 rows, degraded=0, uncomparable=0.
- **Follow-ups:** none of the 12 ids are open, and the two round-1 follow-ups are filed.
- **Dispatch fixes:** they are one-line and bash-3.2-safe.
- **Corpus guard (TEST-4112):** it is a static corpus sweep with both controls, and its two-shape limit is disclosed in its helper comment. This satisfies the universal-negative-name rule.

## cannot_verify

See the YAML block:
- Windows runtime;
- the 6.5 h hang cause story;
- corpus syntax-breaking cells under D5;
- m/g cell replay;
- the merge with 01cd7f78 (validation NB-r4-1);
- the full sweep and Linux CI.

## Warning dispositions (H6)

| Finding | Recommended disposition |
|---|---|
| NB-r2-1 (DEV-1) | (a) remediate in tree: an additive spec-amend on SPEC-0315-spec-mutation-tooling-p2-fixes (fallback (b) suggested `fu-spec-omits-git-apply-hardening`, P3) |
| NB-r2-2 | (d) accepted residual, quoted above |

The orchestrator records these. The reviewer files none.

## Evidence (commands run, this round)

- **mutation-gate tests:** `env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-mutation-gate.sh <fn>` for test_4110, 4111, 4114, 4115, 4116, 4118, 4119, 4112, 4113, 4121, 4122, 474, 492, 500 and 501. All rc 0, with PASS lines.
- **close-work-item tests:** the same runner on `test-aai-close-work-item.sh` for test_4117 and test_533. Both rc 0.
- **spec-lint test:** the same runner on `test-aai-spec-lint.sh` test_4120. rc 0.
- **session-lock selector:** the same runner on `test-aai-session-lock.sh` test_409. rc 0.
- **Gate:** `node .aai/scripts/mutation-gate.mjs --spec docs/specs/SPEC-0315-spec-mutation-tooling-p2-fixes.md --require-evidence` printed GATE PASS, 13 rows.
- **Amendments:** `node .aai/scripts/spec-amend.mjs list --strict` rc 0.
- **Follow-ups:** `node .aai/scripts/follow-ups.mjs list --status open --json` lists none of the 12 ids.
- **Pin hash:** `shasum -a 256 .aai/scripts/close-work-item.mjs` = 2307a652615121eabc1912000c46897d8c5dfa4fe661316e3bbc6f52de705afc.
- **Probes** (scratch fixtures only, under `/private/tmp/claude-501/-Users-ales-Projects-aai/2071b3a2-d378-409f-946d-cd8edb99948a/scratchpad/probes/`):
  - `p1-patch-symlink.sh`: round-1 BLOCKING-1 no longer reproduces; victim unchanged.
  - `r2-check-patch.sh`: a valid patch gives CHECK OK; TMPDIR inside a git work tree also gives CHECK OK, and a real run records RED.

## Next steps

1. The orchestrator records the NB-r2-1 and NB-r2-2 dispositions.
2. Take origin/main 01cd7f78: rebuild the ledgers base-first and keep the CHANGELOG heading order (validation NB-r4-1). Then re-run the delta checks named there.
3. Proceed to /aai-pr.

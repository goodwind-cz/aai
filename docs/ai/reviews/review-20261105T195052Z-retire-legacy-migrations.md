# Code review re-pass - retire-legacy-migrations (PR #533)

security_relevant: true

```yaml
review:
  scope: origin/main...HEAD (f324b66f...75f7e905), focus on the delta fcf4b026..75f7e905
  spec: docs/specs/SPEC-0273-spec-retire-legacy-migrations.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-3380 PASS (aai-legacy-migrations rc 0); pure functions untouched by a907be5d" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-3381 PASS; parity fcf4b026 vs HEAD: legacy, noGitignore, lfNoFinalNewline, migrated identical" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-3382 PASS; parity: dirty, notGit, noDocsAi, every dry run identical" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-3383, TEST-3384, TEST-3401, TEST-3402 PASS (two new TEST-3402 cases RED on fcf4b026, reproduced); parity: hostile, subdir, indexLock, gitTilde, flags identical" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3385, TEST-3386 PASS; launchers untouched by the delta" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3387 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3388 PASS, Pester 7 of 7; CI ps1-quality Windows legs pass on 75f7e905" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3389, TEST-3390 PASS" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3391 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3392 PASS" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3393, TEST-3394 PASS" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3395 PASS" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3396 PASS" }
      - { ac: Spec-AC-14, call: compliant, citation: "TEST-3397 PASS" }
      - { ac: Spec-AC-15, call: compliant, citation: "TEST-3398 PASS; aai-prompt-diet rc 0" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-3399 PASS; numbered link CHANGE-0245 matches the suffix check" }
      - { ac: Spec-AC-17, call: compliant, citation: "TEST-3400 PASS: module 159 of 160 code lines, 182 of 200 lines, seven-file sum 183" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 121,
          issue: "the post-removal verify ls-files is still unchecked; a failing call reads as no survivors",
          failure_scenario: "git~1 evidence name tracked, update-index exits 0 and skips it, the verify ls-files exits 128: run exits 0, prints Files untracked 5, writes .gitignore and EVENTS.jsonl, git~1 stays tracked (probe P4)" }
      - { rank: NON-BLOCKING, file: tests/skills/lib/migrate-state-to-local.test.mjs, line: 337,
          issue: "the new first ls-files guard has no test; deleting it leaves all 18 node cases green",
          failure_scenario: "a later edit drops `if (failed(ls, 'ls-files')) return 1;`; an ls-files failure after a passing status writes .gitignore and EVENTS.jsonl again, and no suite notices (mutant survived)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/migrate-state-to-local.mjs, line: 122,
          issue: "the restore-failure hint `git -C <target> reset` does not recover a truncated index and drops skip-worktree / assume-unchanged bits",
          failure_scenario: "restore write fails after truncation (ENOSPC): the hint itself fails with 'index file smaller than expected'; restore open fails (EACCES): the hint works but STATE.yaml loses its S bit (probe restore.log)" }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 31,
          issue: "the entry omits what spec D6 requires (M-1, M-3, M-6 to M-9, before/after code lines) and its heading differs from the D6 text; the spec's Constitution section says the 10 extra POSIX ignore entries are named in the CHANGELOG, which is now false",
          failure_scenario: "a POSIX downstream that tracks docs/ai/reports or docs/ai/archive runs the migration; 10 new ignore lines silently stop new files there from being tracked, and the release notes never said so" }
  cannot_verify:
    - { claim: "Windows PowerShell 5.1 parity for the delta", closes_with: "CI ps1-quality native Windows legs on 75f7e905 (green; the delta does not touch the launchers)" }
    - { claim: "CHANGELOG 'safe for leading dashes' wording", closes_with: "a TEST-3383 case with a docs/ai/tdd/x/-n.log name; update-index --stdin takes no options from stdin, so it is expected to hold" }
  overall: pass
```

## Scope and preflight

- Branch `refactor/retire-legacy-migrations`, worktree `/Users/ales/Projects/aai-worktrees/retire-legacy-migrations`, HEAD 75f7e905, base origin/main f324b66f (merge base f324b66f).
- `git status --porcelain` is empty, so the scope is clean. The diff is `origin/main...HEAD`, 47 files.
- The earlier rounds reviewed everything up to fcf4b026. This pass reads the whole delta fcf4b026..75f7e905 line by line:
  - a907be5d: the module and the test file.
  - cb6ed570: close-out. Numbering, CHANGELOG, RFC link, roadmap, ledgers and the residual-risk block of the spec.
  - 75f7e905: the pr_sweep record.
- Coaching note. The dispatch summarised what the delta does, but it did not pre-rate any findings or exclude any area. The review covers the full delta.

## Delta read (a907be5d)

The git calls in `run()`, and what happens when each one fails:

| Line | Call | On failure at HEAD | On failure at fcf4b026 |
|---|---|---|---|
| 83 | `--version` | `ERROR: git not found in PATH.`, rc 1 | same |
| 84 | `rev-parse --git-dir` | not-a-repository refusal, rc 1 | same |
| 88 | `status --porcelain` | `ERROR: git status failed (exit n): ...`, rc 1, before any output or write | treated as a clean tree |
| 99 | `ls-files` (plan) | `ERROR: git ls-files failed ...`, rc 1, header printed, no write | treated as an empty tracked set |
| 114 | `rev-parse --git-path index` | stdout empty, `readFileSync(target)` throws EISDIR, uncaught crash, rc 1, before any write (probe P3) | same |
| 115 | `update-index --force-remove` | D1 error, rc 1 | same |
| 121 | `ls-files` (verify) | **unchecked**: survivors read as none, run continues and reports success (P4) | same |

Single-line merges. I read each merged line for a change in meaning:

- `const st = ...; if (failed(st,'status')) return 1;` and the `ls` line are a guard, then a declaration.
- The `listed/tracked/toRemove`, `missing/headerShown` and `eventsPath/createEvents` lines are plain declarations in the original order.
- Line 122 is `if (left.length > 0) { try { write; err(A); } catch (e) { err(B); } return 1; }`. The `return 1` sits outside the try, so both paths exit 1.
- There is no `&&`/`||` precedence change and no early return moved.
- Parity (fcf4b026 vs HEAD, 14 layouts with and without a dry run, 28 runs) is 26 identical. The 2 that differ are the corrupt-index layout, which is the intended change.

## Findings and dispositions (H6)

- **NB-r5-1** (P3): the verify `ls-files` is unchecked. When it bites, the run reports success while a path is still tracked, which leaves a false record, so (d) is not allowed.
  - Recommended: **(b) follow-up** `fu-migrate-state-verify-ls-files-unchecked` (suggested, not filed).
  - Fix: treat a non-zero verify status like a survivor (restore and exit 1) and add a mocked-git test case. Any extra line has to fit under the 160 code-line cap.
  - (a) in the tree is also acceptable.
- **NB-r5-2** (P3): the plan `ls-files` guard has no test, and the mutant survives.
  - Recommended: fold it into the same follow-up as NB-r5-1, which adds an injected-git case through `M.run` for both `ls-files` calls.
  - (d) is not appropriate: the PR thread reply says the `ls-files` check is covered by a regression test, and only the `status` check is.
- **NB-r5-3** (P3): the recovery hint is incomplete. The message is honest: it never claims the index is unchanged and it names the error code.
  - Recommended: **(a)** change the hint to `rm "<index path>" && git -C "<target>" reset` and say that it resets skip-worktree and assume-unchanged bits. This is a text change on the same line, so the line budget does not move.
  - Otherwise fold it into the NB-r5-1 follow-up.
  - Alternatively **accepted residual** under NB-r4-2 (a guard weaker than ideal, no observed bite, no false record). The NB-r4-2 residual text in the spec says "crashes loudly", which a907be5d made stale. It needs the spec amendment either way.
- **NB-r5-4** (P3, but leaves a false record in the spec's Constitution section): the CHANGELOG under-discloses.
  - Recommended: **(a) remediate in the tree before merge**. Docs only, with no code or test effect.
  - Add a bullet naming the 10 extra POSIX ignore entries (M-1), the stop on a failed `git rm` or `git` (M-3 and the a907be5d refusals), the ASCII "Nothing to do" line and the dry-run lines (M-6 to M-8), CRLF-aware appends (M-9), and the 893 to 183 code lines.

INFO (no gate):

- The P3 crash path (`rev-parse --git-path` failure) is not silent and writes nothing.
- `failed()` prints the whole stderr, which can span several lines, and prints `exit null` on a spawn error. This is cosmetic.
- Line 122 is 388 characters, compressed to fit the code-line cap. That is a readability cost.
- The PR #533 reply to the Codex thread says `git ls-files` is checked. Only the first of the two calls is.

Carried accepted residuals (r4, unchanged):

- accepted residual: NB-r4-2 the index restore is a non-atomic write that ignores index.lock; a failed write is now reported (rc 1, recovery hint) instead of crashing; the concurrent-writer race is unchanged from r3 (P3, no observed bite)
- accepted residual: NB-2 under a sparse index, evidence that is not on disk is untracked (P3)
- accepted residual: NB-4 `-h` after a second positional argument exits 2 (cosmetic, P3)
- accepted residual: a dry run on a `git~1` or non-UTF-8 evidence name exits 0 and predicts the untrack; the real run refuses with rc 1 and changes nothing (P3)
- NB-r4-1 split-index expiry: follow-up `fu-migrate-state-split-index-expire` (open)

## Spec deviations (non-AC)

- D6 CHANGELOG clause: unmet (NB-r5-4).
- D1 refusal list and the Effects steps do not list the two new refusals or the restore-failure line. The TEST-3402 Test Plan row does not describe its two new cases. The NB-r4-2 residual text is stale.
  - All of this needs a contract-class amendment. The exact text is in VALIDATION-retire-legacy-migrations-r5.md.

## Next steps

1. Orchestrator: fix NB-r5-4 in CHANGELOG.md. Pick (a) or the follow-up for NB-r5-1/2/3 and file it with `follow-ups.mjs add`.
2. Orchestrator: file the D1 contract amendment, tracked by the open `fu-amend-spec-retire-legacy-migrations`.
3. Correct the PR thread reply about which `ls-files` call is guarded.
4. Merge stays with the owner.

# Code review: ci-flake-root-causes

```yaml
review:
  scope: "ec9bb00b..f7433abf (branch fix/ci-flake-root-causes, separate read-only clone)"
  spec: docs/specs/SPEC-0322-spec-ci-flake-root-causes.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/lib/append-lock.sh:72-76,83; tests/skills/test-framework.sh:963; TEST-4165, TEST-4166, TEST-006 re-run green" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-release.mjs:173-176,201-203,228,272; TEST-4164 and TEST-3537 re-run green (6 of 6)" }
      - { ac: Spec-AC-03, call: non-compliant,
          citation: ".aai/scripts/close-reconcile.mjs:380-381: D3 says a label that is preceded by or contains `not` claims nothing. For Paired labels only an immediately preceding `not` is checked, so `Paired maintenance half (not taken): ID` still claims ID. TEST-4160 green, but its fixture has no negated Paired label (finding 1)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/lib/release-first.test.mjs:64-74,144,298,653-672; TEST-4163 re-run green (local: Pester absent under empty HOME, so only the skip branch ran)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:936-941; tests/skills/test-framework.sh:1311-1316; TEST-4162 re-run green; inherited-mode refusal reproduced by hand (rc=125, AAI-XDG: REFUSED, command not run, fake HOME empty); TEST-4161 not run, the suite has no selector" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "docs/ai/decisions.jsonl (+4 follow_up_status done, resolved_by ci-flake-root-causes); both amendment headings; TEST-4167 re-run green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/close-reconcile.mjs, line: 381,
          issue: "Negation check for Paired labels is narrower than D3: it does not look for `not` inside the label, and it only sees `not` as the word right before `paired`",
          failure_scenario: "a delivered doc with `- Paired maintenance half (not taken): ISSUE-0001` or `- This is not a paired maintenance half: ISSUE-0001` gets ISSUE-0001 itemed id-mention-unpaired, and --apply refuses" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/append-lock.sh, line: 74,
          issue: "when mkdir succeeds but the O_EXCL create fails for a reason other than EEXIST (ENOSPC/EDQUOT), or the process is killed between the two steps, a lock dir with no stamp is left behind. aai_append_lock_age returns empty for it, so it is never broken as stale",
          failure_scenario: "inode quota is exhausted for a moment during an append: the dir is made, the stamp is not, and every later aai_locked_append on that ledger spins to timeout and returns 1 until someone removes <file>.aai-lock by hand. The old code ignored the stamp-write failure and went ahead" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 938,
          issue: "the exit-125 refusal path runs the tree and residue finishers but not aai_iso_cleanup, and does not remove the two tripwire snapshot temp files",
          failure_scenario: "a suite run whose disposable clone (mktemp -d, line 484) was made, but whose XDG mktemp -d failed later (TMPDIR filled up in between), exits 125 and leaves the whole aai-iso-wrap.* clone in TMPDIR" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-sweep-parallel.sh, line: 1130,
          issue: "TEST-4165 writes $d.o1 and $d.o2 beside the fixture; neither is registered, and cleanup() only removes registered directories. Neither file is printed on failure",
          failure_scenario: "a direct `bash tests/skills/test-aai-sweep-parallel.sh` (no wrapper-owned temp root) leaves two aai-sweep-parallel.*.o1/.o2 files in TMPDIR on every run. A red TEST-4165 does not show the framework output that would explain it" }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-reconcile.mjs, line: 371,
          issue: "how claimSpans cuts items: a nested sub-list value starts a new item, so the label's span is empty (false negative). A span runs to the end of the item, so a later mention in the same paragraph counts as a claim. Fenced code is not skipped",
          failure_scenario: "`- Paired maintenance half:\\n  - `ISSUE-0001`` claims nothing (measured: span ['']). In CHANGE-0188 line 18, `the original half, CHANGE-0181, rode with...` sits in the Paired span and counts as a claim" }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-reconcile.mjs, line: 364,
          issue: "PAIRED_LABEL_RE `(?: [a-z]+)*` is quadratic in the length of one line of space-separated words that follows `paired`",
          failure_scenario: "a 340 KB single line `paired a a a a a ...` repeated takes 8.5 s in claimSpans (measured). Real docs have short lines, so no observed bite" }
  cannot_verify:
    - { claim: "the noclobber create is O_EXCL on the hosted ubuntu-26.04 image (uutils coreutils 0.10.0, dash as sh)",
        closes_with: "hosted run 45913897767 log (spec Notes: 0 of 400 double creates); locally verified only: 4 contenders x 100 races, 0 multi-winner, on macOS /bin/sh, bash, dash, zsh and ksh" }
    - { claim: "the release race on the uutils host: `rm -rf` of a released lock cannot delete a new holder's stamp that appears during the traversal",
        closes_with: "a hosted loop that races aai_append_lock_release against aai_claim_dir with uutils rm, or reading uutils rm's traversal (re-read vs single readdir)" }
    - { claim: "the RED/GREEN logs, idm-before/after.txt and mutation records cited in the AC table (docs/ai/tdd/ci-flake-root-causes/, docs/ai/tdd/spec-ci-flake-root-causes/)",
        closes_with: "they are gitignored local evidence missing from the clone; run `mutation-gate.mjs --spec docs/specs/SPEC-0322-spec-ci-flake-root-causes.md --require-evidence` in the ride worktree" }
    - { claim: "the 150-merge replay names no doc (before: five)",
        closes_with: "idm-after.txt. The reviewer reproduced only the two historical claims (ISSUE-0040 at e6aae10b, CHANGE-0181 at 7270a29c, both still itemed) and this range (no id-mention-unpaired item)" }
    - { claim: "TEST-4161 owned mode and the whole aai-run-tests suite",
        closes_with: "the concurrent full sweep (the suite has no single-test selector)" }
    - { claim: "TEST-4163 pass branch (Pester importable under an empty HOME, as on CI)",
        closes_with: "the PR's hosted skill-suite run" }
    - { claim: "D2 fixes the hosted signal-ordering race (TEST-3537 SIGTERM arm); TEST-4164 is a mocked unit test",
        closes_with: "repeated hosted runs of test-aai-release-cut TEST-3537" }
    - { claim: "no other suite relies on the wrapper or framework running a command with an unusable TMPDIR (that path now refuses or exits 125)",
        closes_with: "the full sweep plus hosted CI" }
  overall: fail
```

security_relevant: false

## Scope and spec

- Scope: `git diff ec9bb00b..f7433abf` in the read-only clone, 21 files. The whole diff was read: code, tests, CHANGELOG, SPEC-0182/SPEC-0319 amendments, decisions.jsonl and EVENTS.jsonl additions.
- Spec: docs/specs/SPEC-0322-spec-ci-flake-root-causes.md (frozen).
- Dispatch note (anti-gaming contract): the dispatch prompt listed seven "focus areas worth scrutiny". It did not pre-rate severity or exclude any area. This is recorded as scope steering, and the full diff was reviewed anyway.
- Clone state after review: `git status --porcelain` clean apart from this report.

## Verification run by the reviewer (targeted selectors only, no sweep)

| Check | Result |
|---|---|
| close-reconcile `test_4160_claim_not_mention` | rc 0 |
| close-reconcile `test_4167_registry_and_amendments` | rc 0 |
| sweep-parallel `test_4165_run_dir_claim_survives_a_racy_mkdir` | rc 0 |
| sweep-parallel `test_4166_append_lock_survives_a_racy_mkdir` | rc 0 |
| sweep-parallel `test_006_two_concurrent_framework_runs_keep_the_ledger_whole` | rc 0 |
| suite-isolation `test_4162_no_tmpdir_cache_is_per_run` | rc 0 |
| `node --test` aai-release.test.mjs TEST-4164, TEST-3537 | 6 pass, 0 fail |
| `node --test` release-first.test.mjs TEST-4163 | 1 pass, 0 fail |
| aai-run-tests.sh with TMPDIR set to a regular file (inherited mode, by hand) | rc 125, `AAI-XDG: REFUSED`, command not run, fake HOME empty |
| noclobber race on 5 local shells, 4 contenders x 100 | 0 multi-winner |
| close-reconcile --check on PR 382 and PR 384 historical trees (scratch clone, new script) | ISSUE-0040 and CHANGE-0181 still itemed |
| close-reconcile --check ec9bb00b..HEAD | no id-mention-unpaired item (only the expected pre-merge pr-number-unknown) |
| claimSpans edge-case harness (scratch copy of the function) | see findings 1, 5 and 6 |

## AC table walk

- Spec-AC-01: compliant. `aai_claim_dir` is mkdir followed by `( set -C; date +%s > "$1/$2" )`; the lock acquire (append-lock.sh:83) and setup_results_dir (test-framework.sh:963) both call it, and the stamp write after the loop is gone. TEST-4165 and TEST-4166 force the losing side with a PATH mkdir shim and a pinned date. Their mutations, `mkdir` in place of the claim and a plain `>` in place of the noclobber create, would each turn a test red.
- Spec-AC-02: compliant. `realDeps().git` returns `signal`. `gitStep` sets `Refusal.signal` only for SIGINT and SIGTERM. `stop(killed)` reports `interrupted() || killed`, and SIGKILL stays exit 20. DB-14 is kept.
- Spec-AC-03: non-compliant (narrow). The AC's positive cases and the cases its fixture covers pass. D3 also says "a label preceded or containing `not` claims nothing". Carried head labels check both. Paired labels only check for `not` as the word right before `paired`, and never look inside the label. Repro from a scratch copy of `claimSpans`:
  - `- Paired maintenance half (not taken): \`ISSUE-0001\`` gives the claim span `` `ISSUE-0001` ``
  - `- Paired maintenance ride, not absorbed: ISSUE-0001` gives ` ISSUE-0001`
  - `- This is not a paired maintenance half: ISSUE-0001` gives ` ISSUE-0001`
  - (`- Not paired maintenance half: ...` correctly gives no span.)

  The code comment at close-reconcile.mjs:362 documents the narrower rule ("not carried:"), not the frozen one.
- Spec-AC-04: compliant. `pesterOr` probes once in the reader's own environment. When Pester is absent it fails on CI and otherwise is a named skip. TEST-006's workflow-gate half runs before the probe, and TEST-4163 drives both arms under an empty HOME, XDG_CACHE_HOME and XDG_CONFIG_HOME, with and without CI.
- Spec-AC-05: compliant. The wrapper refuses with 125 after its tree and residue finishers. The framework falls back to `$RUN_DIR/aai-xdg-cache.<suite>`, removed by the existing `/*/aai-xdg-cache.*` guard glob, and refuses the suite (log line, return 1) only when that also fails. The caller still runs iso_destroy (test-framework.sh:1722, 1785).
- Spec-AC-06: compliant. The four `follow_up_status done` lines carry resolved_by ci-flake-root-causes, both amendment headings are present, there are two `spec_amendment` records with owner-sign-off follow-ups, and `spec-amend list --strict` exits 0 (TEST-4167).

Other deviations from the frozen text, none of which fails the verdict:
- TEST-4167 lists with `--status all` and checks that each item is done with resolved_by, where Spec-AC-06 says `--status open` lists none of them. These are equivalent for the four ids.
- The frozen_sha256 of SPEC-0182 and SPEC-0319 was restamped together with the amendments. This is disclosed, and `spec-amend list --strict` passes.

## Findings

1. NON-BLOCKING (P2), .aai/scripts/close-reconcile.mjs:380-381. The Paired-label negation is narrower than D3; failure scenario above. Fix: `if (/\bnot\b/i.test(m[0]) || /\bnot\b[^.;:\n]{0,40}$/i.test(item.slice(Math.max(0, m.index - 40), m.index))) continue;`, or the simpler rule "`not` anywhere in the label or in the clause before it". Add a negated Paired line to the TEST-4160 fixture, for example `- Paired maintenance half (not taken): \`t4160-...\``. Recommended disposition: remediate in tree. This fix also clears the Spec-AC-03 non-compliance.
2. NON-BLOCKING (P3), .aai/scripts/lib/append-lock.sh:73-75. A lock dir without a stamp cannot be broken. Fix: on a failed create, run `rmdir "$1" 2>/dev/null` before `return 1`. rmdir removes only an empty dir: when the create failed because another process already holds the lock, the stamp is there and rmdir fails harmlessly. When the dir is empty (ENOSPC), the orphan is gone. Optionally, treat a stampless lock older than the timeout, by the dir's mtime, as stale. The kill-between-steps window existed before this change; the error-path wedge is new. Recommended disposition: remediate in tree (a one-line fix), or promote to a follow-up.
3. NON-BLOCKING (P3), .aai/scripts/aai-run-tests.sh:936-941. The refusal path does not run `aai_iso_cleanup` or remove `$AAI_TW_BEFORE` and `$AAI_TW_AFTER`. This needs TMPDIR to go from usable to unusable between line 484 and line 933, so it is rare. Fix: call `aai_iso_cleanup` and `rm -f -- "$AAI_TW_BEFORE" "$AAI_TW_AFTER"` before `exit 125`. Recommended disposition: remediate in tree, or accepted residual (P3, no observed bite, no false record).
4. NON-BLOCKING (P3), tests/skills/test-aai-sweep-parallel.sh:1130-1131. Two unregistered output files leak. Fix: write them under `$d.shim/` (already registered), and `cat` them in the failure log_info. Recommended disposition: remediate in tree.
5. NON-BLOCKING (P3), .aai/scripts/close-reconcile.mjs:368-374. claimSpans false negatives and positives: a nested sub-list value is missed, the rest of an item after a Paired label counts as claimed, and fenced code is not skipped. The current corpus has no nested-value claim; CHANGE-0188:18 shows the over-reach shape on a terminal doc. Recommended disposition: promote to a follow-up (P3), or state it in D3's residual list.
6. NON-BLOCKING (P3), .aai/scripts/close-reconcile.mjs:364. A pathological line makes PAIRED_LABEL_RE quadratic; the input is repository docs, not untrusted text. Fix if wanted: bound the word group, `(?: [a-z]+){0,6}`. Recommended disposition: accepted residual: P3 cost finding on trusted repository input, no observed bite, no false record.

INFO (never gates):
- append-lock.sh:85-87. Pre-existing and unchanged: when two waiters both judge one lock stale, the second waiter's `rm -rf` can remove the lock the first one just claimed. D1 says stale handling is unchanged, so this is not a regression.
- aai-release.mjs:203. As disclosed in Residual risks D2: a git child killed by an outside SIGTERM, for example another run's reaper, is now reported as `interrupted (SIGTERM)` with exit 143 rather than a git-command refusal with exit 20.
- release-first.test.mjs:71. `!process.env.CI` treats `CI=false` as CI. This is harmless on real runners.

## Warning dispositions (H6, recommended; the orchestrator records them)

| # | Recommended |
|---|---|
| 1 | (a) remediate in tree (closes Spec-AC-03) |
| 2 | (a) remediate in tree, else (b) follow-up P3 |
| 3 | (a) remediate in tree, else (d) `accepted residual: refusal-path leak needs TMPDIR to fail between two mktemp calls; P3, no bite` |
| 4 | (a) remediate in tree |
| 5 | (b) follow-up P3 (claim-span granularity) or a D3 residual line |
| 6 | (d) `accepted residual: quadratic regex on trusted repo docs, no observed bite` |

## Next steps

1. Fix finding 1 and add the negated Paired fixture line to TEST-4160, then re-run `test_4160_claim_not_mention` and the TEST-4160 mutation.
2. Optionally fold in findings 2, 3 and 4 (each is one or two lines).
3. Re-review: a single pass over the delta.

state_update_commands:
```bash
node .aai/scripts/state.mjs set-code-review --required true --status fail \
  --scope "ec9bb00b..f7433abf" --base-ref ec9bb00b \
  --report docs/ai/reviews/review-ci-flake-root-causes-20261127T002444Z.md \
  --notes "spec_compliance fail (Spec-AC-03: Paired-label negation narrower than D3, close-reconcile.mjs:381); code_quality pass, 6 NON-BLOCKING: 1 remediate, 2 remediate/follow-up, 3 remediate/accepted residual, 4 remediate, 5 follow-up P3, 6 accepted residual: quadratic regex on trusted repo docs, no observed bite"
```

---
review:
  scope: "RE-REVIEW #2 (delta on top of the prior re-review). Working-tree changes since review-dual-verdict-20260723T121021Z: tests/skills/test-aai-run-tests.sh test_015 sleep-4->sleep-8 remediation (4th audited site); docs/specs/SPEC-0072-*.md amendment table + Spec-AC-01 wording update; docs/issues/ISSUE-0026-*.md + docs/specs/SPEC-0072-*.md frontmatter status: done -> implementing (reopen); docs/ai/EVENTS.jsonl 2 new doc_lifecycle events. Supersedes review-dual-verdict-20260723T121021Z-reaper-epoch-survivor-robustness-rereview.md (kept, not deleted; prior review-dual-verdict-20260723T114559Z also kept)."
  spec: docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:500-510 (test_015) now sleep 8 (was sleep 4), with an arithmetic comment matching the test_006/013/017 precedent PLUS the eedea6d/d45fe4e archaeology, independently verified true via `git show eedea6d` and `git show d45fe4e -- tests/skills/test-aai-run-tests.sh` (both confirm the claimed history exactly: eedea6d widened this exact site 3->8/legacy-MIN_AGE-5 model, d45fe4e's epoch-mode migration narrowed it back to 4 on the same 'comfortably beyond GRACE(2)' reasoning that caused this whole defect family). Windowless re-audit (below) confirms all 4 real-time pre-step sites now clear the band and no 5th exists. Spec-AC-01's row wording now names all four sites explicitly (test_006, test_013 epoch branch, test_015, test_017) instead of the prior 'EVERY' overclaim -- my prior finding is CLOSED (see code_quality INFO note on a trivial residual imprecision, not blocking)." }
      - { ac: Spec-AC-02, call: compliant, citation: "test_021 untouched by this delta; re-ran, still passing" }
      - { ac: Spec-AC-03, call: compliant, citation: "test_017 untouched by this delta" }
      - { ac: Spec-AC-04, call: compliant, citation: "git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh and git diff --stat -- .aai/scripts/aai-reap-tests.sh (working tree): both empty; GRACE=2 intact" }
      - { ac: Spec-AC-05, call: cannot-verify, citation: "unchanged from prior pass -- still deferred, Review-By 2026-08-06, honestly PENDING on repeated CI green; not yet pushed as of this review" }
      - { ac: Spec-AC-06, call: compliant, citation: "diff still touches only tests/skills/test-aai-run-tests.sh + docs/specs/SPEC-0072-*.md + docs/issues/ISSUE-0026-*.md + docs/ai/EVENTS.jsonl + review reports; no .aai/*.prompt.md, no AGENTS.md, no new .aai/** path" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: "docs/issues/ISSUE-0026-reaper-epoch-survivor-robustness.md, docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md", line: 3,
          issue: "The done->implementing reopen leaves BOTH docs flagged `probable-false-open` by `node .aai/scripts/docs-audit.mjs` -- verified by diffing the audit's own output with the reopen stashed out (`False-open: 0`, Verdict: CLEAN) vs applied (`False-open: 2`, listing both ref ids with reasons 'ac_evidence event; work_item_closed event' / 'delivery commit(s) 0456684 ...; ac_evidence event; work_item_closed event; AC Status table fully terminal with evidence'). Root cause: the false-open heuristic (`.aai/scripts/lib/docs-audit-core.mjs:257-341`, `falseOpenEvidence`) keys off historical `ac_evidence`/`work_item_closed` events and the delivering commit, none of which the reopen's two new `doc_lifecycle` events (EVENTS.jsonl:1002-1003) can neutralize -- the heuristic has no code path that treats a later doc_lifecycle event as superseding an earlier work_item_closed/ac_evidence signal for the same ref. This is not a pre-existing repo condition: confirmed via `git stash` that the SAME two docs audit CLEAN (False-open: 0) at the prior commit (0456684), before the reopen. `grep -rn reopen .aai/scripts/lib/docs-audit-core.mjs .aai/workflow/WORKFLOW.md .aai/VALIDATION.prompt.md` returns zero hits and `grep -c '\"from\":\"done\",\"to\":\"implementing\"' docs/ai/EVENTS.jsonl` returns 2 (both from this delta) -- this repo has never exercised a done->implementing transition before, so there is no precedent this collides with a known/tolerated gap.",
          failure_scenario: "`tests/skills/test-aai-docs-audit.sh`'s `test_change0028_real_repo_clean` (TEST-009 / Spec-AC-08, the CI-required real-repo regression guard) runs `node .aai/scripts/docs-audit.mjs --check --strict --no-event` and asserts `assert_contains ... \"False-open: 0\"` plus `grep -qF \"probable-false-open\"` must NOT match. Reproduced directly: `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the current working tree prints `False-open: 2` and lists both this PR's own docs by name -- the assertion WILL fail deterministically (not a flake) if pushed as-is, reproducing the EXACT same failure category ('Expected False-open: 0') this PR's earlier CI run (30002328595/30002216044) already hit once for an unrelated reason (the table pipe-drop bug, since fixed). This is the `aai-docs-audit` skill-suite job, a required branch-protection check per this same issue's own 'Impact' section." }
      - { rank: BLOCKING, file: "docs/INDEX.md", line: 10,
          issue: "docs/INDEX.md was not regenerated after the status:done->implementing flip and is now stale relative to the live doc state. Reproduced: `node .aai/scripts/generate-docs-index.mjs` against the current working tree (then reverted -- no persistent change made) produces a real diff beyond the `Generated:` timestamp -- a new '## Active (implementing) (2)' section appears listing ISSUE-0026 and SPEC-0072 with Status/Progress columns, the '## Done' count drops from 157 to 155, and both docs' rows disappear from the flat Done table they currently still sit in.",
          failure_scenario: "Any skill-suite regression test that asserts INDEX regeneration is a no-op against the committed docs/INDEX.md (the same category of check that failed earlier in this session's own manual full-suite run: 'FAIL: POSIX-path change must be a no-op on POSIX (real INDEX byte-identical modulo Generated)') will fail deterministically, since regenerating now produces a real content diff, not just a timestamp change." }
      - { rank: INFO, file: "docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md", line: 362,
          issue: "Spec-AC-01's Description cell still leads with the generic phrase 'EVERY pre-step gap widened `sleep 3`->`sleep 6`' before parenthetically naming all four sites -- but `test_015` actually moved `sleep 4`->`sleep 8`, not `3`->`6`. The Evidence cell in the same row states the correct per-site value ('test_015 at `sleep 8`'), and the dedicated amendment table further up the doc is fully accurate, so this is a cosmetic residual generalization in the lead phrase only, not a substantive claim error.",
          failure_scenario: "None -- style/precision nit only, does not gate." }
    dispositions:
      - { finding: "docs-audit false-open on ISSUE-0026/SPEC-0072 (BLOCKING)", recommended: "orchestrator to choose: (a) regenerate docs/INDEX.md as part of this commit (mechanical, resolves the INDEX-staleness half on its own) AND (b) for the false-open half, either revert the reopen and instead record the test_015 remediation as a small companion doc/decision (avoids the collision entirely -- a fresh doc carries no stale closure events, which was my original recommendation before the reopen was chosen), OR keep the reopen and treat the heuristic's inability to recognize a legitimate reopen as its own small, real tooling gap worth a short follow-up (teach `falseOpenEvidence` to treat a `doc_lifecycle` event postdating the `work_item_closed` event for the same ref as neutralizing the false-open signal) -- filed explicitly, not silently absorbed into this PR's already-extended scope." }
  cannot_verify:
    - { claim: "Validation's independently-measured '~60ms' real slack for test_015's pre-fix sleep-4 gap", closes_with: "no raw measurement log/artifact cited or found under docs/ai/ for this figure; narrated in the spec's amendment prose only, attributed to Validation's own pass -- same category of unverifiable-from-diff-alone measurement as the test_021 20-sample probe flagged in the first review" }
    - { claim: "Spec-AC-05's repeated-CI-green evidence", closes_with: "unchanged from both prior passes -- requires a push of the now-4-site fix + amendment + INDEX regen, followed by >=2 green skill-suite CI runs" }
  overall: fail
---

# Code Review (RE-REVIEW #2) — reaper-epoch-survivor-robustness (SPEC-0072 / ISSUE-0026)

Supersedes `review-dual-verdict-20260723T121021Z-reaper-epoch-survivor-robustness-rereview.md`
(kept, not deleted, as is `review-dual-verdict-20260723T114559Z-...md`). This
pass reviews the `test_015` remediation, the Spec-AC-01 wording fix, and the
doc-lifecycle reopen.

## 1. Is the `test_015` edit correct and in the right place?

**Yes.** Read the full function (`tests/skills/test-aai-run-tests.sh:492-538`)
end to end. The edit replaces only the `sleep 4` line and its comment
(previously lines 500-501) with `sleep 8` and a longer comment
(lines 500-510); every line before and after is byte-identical to the prior
review's read of this function:

- **Position unchanged**: the sleep still sits immediately after
  `p_pid`/`o_pid` are spawned (lines 498-499) and immediately before the
  `pgrep -P` / `ps -o args=` fixture-discovery calls (lines 511-518) — i.e.
  BEFORE the fixture semantics that depend on it, not interleaved with them.
- **Fixture semantics unchanged**: `pgrep -P "$p_pid"` / `"$o_pid"` (511-512),
  the `track` calls (514), the token-less-child guard (516-518), the
  `step_start` capture (522, still positioned identically relative to the
  pgrep/ps calls as before), and the fresh-sibling spawn (523) are all
  byte-for-byte unchanged. The added 4s only gives the forked child MORE time
  to come up before it's polled — it cannot cause the fixture to observe a
  DIFFERENT state (the child either exists by the time `pgrep` runs or the
  fixture already fails at line 513, which was equally true before).
- **Assertions unchanged**: lines 524-536 (reaper must kill `p_pid`/`p_child`,
  must spare `o_pid`/`o_child`/`fresh_pid`) are byte-identical to the version
  reviewed in both prior passes.
- **Archaeology independently verified**: `git show eedea6d --
  tests/skills/test-aai-run-tests.sh` confirms this exact site (then inside
  the legacy-threshold `test_015`) was widened `sleep 3`->`sleep 8` for
  "CI-load timing race" (commit message: "old-process 3s->8s ... for CI
  jitter headroom"); `git show d45fe4e -- tests/skills/test-aai-run-tests.sh`
  confirms the epoch-mode migration narrowed it `sleep 8`->`sleep 4` with the
  comment `# let the forked child come up; comfortably beyond default
  GRACE(2)` — the EXACT text this PR just removed. The claimed history is
  real, not asserted-and-trusted.
- **Behavioral confirmation**: `bash tests/skills/test-aai-run-tests.sh 006
  013 015 017 021` — PASS, all five, locally.

## 2. Windowless re-audit — any fifth site?

**No.** Re-ran the coordinator's awk with no cutoff, and independently
grepped every `step_start="$(date +%s)"` occurrence by hand:

```
$ awk '/sleep [0-9]+/ {s=$0; gsub(/[^0-9]/,"",s); pend=s; pl=NR}
       /step_start="\$\(date \+%s\)"/ && pend!="" {print pl": sleep "pend" -> step_start at "NR" (gap "NR-pl" lines)"; pend=""}' \
  tests/skills/test-aai-run-tests.sh
236: sleep 6 -> step_start at 239 (gap 3 lines)     # test_006 — fixed
430: sleep 6 -> step_start at 431 (gap 1 lines)     # test_013 — fixed
510: sleep 8 -> step_start at 522 (gap 12 lines)    # test_015 — fixed
528: sleep 1 -> step_start at 555 (gap 27 lines)    # false pairing (test_014's
                                                     #   settle-sleep paired
                                                     #   with test_016's
                                                     #   step_start — test_016
                                                     #   has NO pre-step old_pid;
                                                     #   confirmed in the prior
                                                     #   review, structure
                                                     #   unchanged since)
591: sleep 6 -> step_start at 592 (gap 1 lines)     # test_017 — fixed
```
```
$ grep -n 'step_start=' tests/skills/test-aai-run-tests.sh
239, 431, 522, 555, 592   # all 5 real-time captures accounted for above
741, 748                  # test_021's arithmetic-derived step_start=$((...));
                           # no real-time margin needed, already reviewed
```
Five real-time `step_start` captures total; four are genuine pre-step-gap
sites (all now clear of the boundary band) and one (`test_016`, line 555) is
not a pre-step-gap site at all (it captures `step_start` FIRST, then spawns
`fresh_pid` after, asserting the fresh sibling is SPARED — the opposite
direction). No fifth genuine site exists.

## 3. Reaper unchanged / no protected path / no retry loop

- `.aai/scripts/aai-reap-tests.sh`: both `git diff --stat main...HEAD --
  .aai/scripts/aai-reap-tests.sh` and the working-tree equivalent are empty.
  `GRACE=2` unchanged.
- Full changed-file list intersected against `protected_paths_l3`
  (`.aai/scripts/state.mjs`, `.aai/scripts/lib/state-engine.mjs`,
  `.aai/scripts/lib/state-core.mjs`, `.aai/scripts/allocate-doc-number.mjs`,
  `.aai/scripts/pre-commit-checks.sh`, `.aai/scripts/pre-commit-checks.ps1`,
  `.aai/workflow/WORKFLOW.md`, `docs/CONSTITUTION.md`): no overlap.
- No retry/loop-until-pass in the `test_015` edit — same single-shot
  reaper-invocation shape as before.

## 4. Is Spec-AC-01 now accurately scoped?

**Yes, substantively — one trivial residual nit.** The row now names all four
sites explicitly (`test_006`, `test_013` epoch branch, `test_015`,
`test_017`) instead of the bare "EVERY" this review flagged last pass, and
its Evidence cell correctly distinguishes `test_015`'s actual value
(`sleep 8`, not `sleep 6`) from the other three. The dedicated amendment
table further up the doc (`| test_015 | sleep 4 | sleep 8 (restores the
eedea6d value) |`) is fully accurate. The one remaining imprecision — the
row's Description cell still LEADS with the generic "widened `sleep
3`->`sleep 6`" before the four-site parenthetical, which doesn't literally
hold for `test_015` — is recorded as INFO-only above; it does not mislead a
reader who reads the whole row (the Evidence cell corrects it inline) and
does not gate.

The amendment's second lesson ("An audit with an undisclosed cutoff is worse
than no audit... state the window, or use none") is a good, well-earned
addition — both this review and the coordinator's own account converged on
finding `test_015` independently by dropping the window, which is exactly
the lesson recorded.

## 5. Is the reopen an adequate disposition of the doc-lifecycle objection?

**No — it resolves the surface-level self-contradiction Validation flagged,
but introduces a new, DETERMINISTIC, CI-breaking regression in the same
check category that already blocked this PR once.** See the structured
BLOCKING findings above; summarized:

- **Confirmed causally**: `git stash` the reopen out -> `docs-audit.mjs
  --check --strict --no-event` reports `False-open: 0`, `Verdict: CLEAN`.
  Pop the stash back in -> `False-open: 2`, both this PR's own docs named,
  `Verdict: NEEDS-TRIAGE`. This is not a pre-existing condition the reopen
  merely inherited — it is caused by the reopen.
- **Confirmed as CI-required**: `tests/skills/test-aai-docs-audit.sh`'s
  `test_change0028_real_repo_clean` asserts exactly `"False-open: 0"` against
  this same command's output, and is part of the `aai-docs-audit` job inside
  the required `skill-suite` CI workflow — the SAME job category that failed
  earlier in this PR's history for an unrelated reason (the table pipe-drop
  bug), with the identical failure-message shape
  (`Expected 'False-open: 0' in .../c0028-audit.log`).
- **Root cause is a real tooling gap, not operator error**: `.aai/scripts/
  lib/docs-audit-core.mjs`'s `falseOpenEvidence` (lines 257-341) has no code
  path that lets a NEW `doc_lifecycle` event (the reopen) supersede an
  OLDER `work_item_closed`/`ac_evidence` event for the same ref — it simply
  isn't consulted. Grepping the engine, `WORKFLOW.md`, and
  `VALIDATION.prompt.md` for "reopen" returns nothing; this repo's
  `EVENTS.jsonl` has never carried a `done`->`implementing` transition before
  this PR (`grep -c` confirms exactly 2 occurrences, both from this delta).
  This is genuinely new territory for the tooling, not a known/accepted
  edge case being re-hit.
- **A second, independent regression rides along**: `docs/INDEX.md` was not
  regenerated after the status flip and is now stale (verified by running
  the generator against a copy and diffing — a real content diff appears,
  not just the `Generated:` timestamp — then reverting; no persistent change
  was made to the working tree by this check).

None of this reflects badly on the INTENT of the reopen — it is the more
honest choice compared to leaving `status: done` self-contradicted, and My
own prior review recommended against a brand-new work item partly on
proportionality grounds. But "did not spawn a new work item" and "produced
a state that deterministically breaks a required CI check" are different
axes, and the second one is not yet resolved. Recommend regenerating
`docs/INDEX.md` unconditionally (cheap, mechanical), and for the false-open
half, either (a) reconsider the original recommendation — a same-scope
companion doc for `test_015` rather than reopening the just-closed one,
which structurally sidesteps the collision since a fresh doc has no prior
closure events, or (b) accept the reopen and treat the heuristic gap as its
own small, explicitly-named follow-up rather than something this PR's own
close ceremony can silently absorb. Orchestrator to record the choice.

## Evidence log
```
$ git diff --stat -- .aai/scripts/aai-reap-tests.sh ; git diff --stat main...HEAD -- .aai/scripts/aai-reap-tests.sh
(both empty)

$ bash tests/skills/test-aai-run-tests.sh 006 013 015 017 021
... PASS x5, exit 0

$ git show eedea6d -- tests/skills/test-aai-run-tests.sh | grep -n sleep
-  sleep 3  /  +  sleep 8     (test_006-then-numbered function)
-  sleep 3  /  +  sleep 8     (test_015-then-numbered function, "let both
                                matched trees age well past the 5s threshold")

$ git show d45fe4e -- tests/skills/test-aai-run-tests.sh | grep -n sleep
-  sleep 8  /  +  sleep 3     (test_006)
-  sleep 8  /  +  sleep 4     ("let the forked child come up; comfortably
                                beyond default GRACE(2)" -- test_015)

$ node .aai/scripts/docs-audit.mjs --check --strict --no-event   # WITH reopen
- Scanned: 157 docs | ... | False-open: 2 | ...
### Verdict: NEEDS-TRIAGE (2 items)
  reaper-epoch-survivor-robustness           probable-false-open
  spec-reaper-epoch-survivor-robustness      probable-false-open

$ git stash -u && node .aai/scripts/docs-audit.mjs --check --strict --no-event   # WITHOUT reopen
- Scanned: 157 docs | ... | False-open: 0 | ...
### Verdict: CLEAN
$ git stash pop   # working tree restored

$ node .aai/scripts/generate-docs-index.mjs   # then reverted, no persisted change
diff shows: new "## Active (implementing) (2)" section (ISSUE-0026, SPEC-0072),
Done count 157 -> 155, both docs' rows removed from the flat Done table.

$ node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0072-spec-reaper-epoch-survivor-robustness.md
LINT PASS: no structural findings.

$ node .aai/scripts/docs-audit.mjs --gate spec-reaper-epoch-survivor-robustness
GATE PASS: AC Status table complete (every row terminal, every done row evidenced, every Review-By valid).
   # NOTE: this gate does NOT check false-open -- it is the narrower per-doc
   # AC-table gate, not the repo-wide audit that surfaces the regression above.
```

## Next steps
1. Regenerate `docs/INDEX.md` and commit it alongside the status changes.
2. Resolve the false-open flag on both docs before this reaches CI again —
   either by not reopening (companion doc instead) or by explicitly
   acknowledging the tooling gap and filing it. Orchestrator to record the
   disposition per H6.
3. Once (1)-(2) land, push and collect the Spec-AC-05 repeated-CI-green
   evidence (unchanged blocker from both prior passes).

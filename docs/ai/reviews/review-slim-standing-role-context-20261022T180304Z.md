```yaml
review:
  scope: "git diff origin/main...HEAD (branch change/slim-standing-role-context, HEAD 9fe9e551; merge-base side excludes the 40e7caaf origin/main merge) - 18 files"
  spec: docs/specs/SPEC-0243-spec-slim-standing-role-context.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-canon.sh test_700 (TEST-001) re-run PASS: all 6 roles shrink by exactly 14402 B; measured LEARNED.md 13236 B <= 13819; Validation 45362 B <= 45945; VALIDATION.prompt.md/SUBAGENT_CONTRACT.md/CANON.yaml/canon.mjs/prompt-hash.mjs byte-identical to 01de2119" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "test-aai-canon.sh test_701 (TEST-002) re-run PASS: 5 HAZ lines identical in 6 payloads; 17 base stay entries verbatim in LEARNED.md" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "test-aai-hygiene-pack.sh test_830 (TEST-003) + test_831 (TEST-004) re-run PASS; reviewer diff of base blob vs LEARNED.md shows only deletions of the 18 moved entries + one added pointer paragraph" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "test-aai-canon.sh test_702 (TEST-005) re-run PASS; canon.mjs/prompt-hash.mjs untouched by the diff" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "test-aai-canon.sh test_703 (TEST-006) + test-aai-hygiene-pack.sh test_832 (TEST-007, real aai-sync.sh) re-run PASS; aai-sync.sh:504 and aai-sync.ps1:495 copy top-level files only" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "test-aai-learned-routing.sh TEST-008 (pointer 714 B <= 900) + TEST-009 re-run PASS; .aai/SKILL_REPLAY.prompt.md:33" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "prompt-diet suite rc=0 (TEST-012 57901 + TEST-010 measured 108 B); learned-routing TEST-006/TEST-011 PASS; hygiene test_126 PASS; suite-select TEST-1762 PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/lib/learned-guard-lints.mjs, line: 591,
          issue: "New run-as-main guard compares import.meta.url (Node resolves the main module to its realpath) with pathToFileURL(path.resolve(argv[1])) (not realpath'd). Via any symlinked path the CLI prints nothing, not even TOTAL, and exits 0 - every rule, not only learned-standing. Before this diff main() always ran.",
          failure_scenario: "macOS: `node /tmp/aai-slim-learned/tests/skills/lib/learned-guard-lints.mjs learned-standing /tmp/aai-slim-learned/docs/knowledge` -> no output, rc=0 (reproduced; the same call via /private/tmp prints TOTAL: 0; the origin/main copy run through a symlink prints TOTAL: 0). PROJECT_ROOT comes from `cd .. && pwd` (the logical path), so running a suite from a symlinked checkout path makes lgl_run see an empty LGL_TOTAL. Every current caller compares to a literal or uses -ge 1, so the result is a false RED with an empty TOTAL, never a false GREEN." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/learned-guard-lints.mjs, line: 121,
          issue: "isMovedClass (rule (a)) matches `guard shipped:` / `routed to canon` anywhere in the entry text, not as the entry's own annotation. A pending fu- entry that mentions another entry's shipped guard is classified as history.",
          failure_scenario: "Probe fixture: `- [2099-01-02] [guard → fu-still-pending] pending; note: unlike fu-x (guard shipped: lint y) this one is not built.` -> learned-standing flags it (TOTAL 2 together with a CHANGE-0999 pending id). The hygiene pack then goes red and the forward rule tells the author to move a PENDING-guard lesson out of the always-loaded file. That is exactly the behaviour D2 says must not happen. Every live annotation has the shape `(guard shipped:` or `(routed to canon`, so anchoring on the opening parenthesis would remove the false positive without losing any live match." }
      - { rank: NON-BLOCKING, file: docs/knowledge/LEARNED.md, line: 9,
          issue: "Always-loaded preamble still says 'The entry of 2026-07-03 below said a content check must read the staged blob'. That entry ([guard → check-committed-scope.mjs]) has moved to docs/knowledge/history/LEARNED-HISTORY.md, so 'below' now points nowhere (the same stale pointer is in the .aai/scripts/check-committed-scope.mjs:5 header comment, outside this diff).",
          failure_scenario: "An agent following the preamble searches LEARNED.md for the 2026-07-03 entry and does not find it. The pointer is a small false statement in the file that every role loads." }
  cannot_verify:
    - { claim: "aai-sync.ps1 (Windows) leaves docs/knowledge/history out of downstream projects",
        closes_with: "Pester/Windows run of aai-sync.ps1 into a scratch target; the reviewer only read the code (Get-ChildItem -File, aai-sync.ps1:495), and TEST-007 exercises only aai-sync.sh" }
    - { claim: "Unloading the advice that the moved entries carry but no guard enforces has no behavioural cost: 'serialize concurrent audit-touching suites' (haz-restore entry), 'hand-close those' (close-work-item-self-verify), and the Framework-owns-HOW invariant marked 'routed to canon' (no canon text by that name was found; SKILL_BOOTSTRAP/SKILL_LOOP cover only the reaping part)",
        closes_with: "Owner judgement at merge (spec R1 discloses it and offers the owner the choice); or later rides showing replay surfaces these entries when they are relevant" }
    - { claim: "R4 token benefit (bytes, not measured task tokens)",
        closes_with: "METRICS comparison of Validation dispatch token usage before and after merge" }
    - { claim: "test_830, test_701, test_831 and TEST-011 SKIP in a shallow CI clone that lacks 01de2119 / 9296160c (named skip line, not a pass)",
        closes_with: "Confirm the CI checkout depth (fetch-depth 0) on the PR run, so the base-blob arms really run in CI" }
  overall: pass
```

# Code Review — slim-standing-role-context

- **Scope:** `git diff origin/main...HEAD` in `/private/tmp/aai-slim-learned`. That is 18 files on branch `change/slim-standing-role-context` at HEAD `9fe9e551`. Only the branch's own commits are reviewed: ea9f4987, 16aa28dc and 9fe9e551. The 40e7caaf merge of origin/main is excluded.
- **Spec:** `docs/specs/SPEC-0243-spec-slim-standing-role-context.md`. It was amended after freeze in 9fe9e551. That amendment is in the measurement class and has `owner_signoff: false`. The owner signs at merge.
- **Intake:** `docs/issues/CHANGE-0218-slim-standing-role-context.md`.
- **Owner target decision:** Option A, about 24% smaller Validation payload, recorded in `docs/ai/decisions.jsonl` hitl_decision 2026-10-22T16:29:55Z.
- **Coaching check:** the dispatch named focus areas but did not pre-rate severity or exclude anything. The full scope was reviewed.

## AC table walk (spec_compliance: pass)

| Spec-AC | Call | Evidence (reviewer re-run unless stated) |
|---|---|---|
| 01 | compliant | TEST-001: delta 14402 B in all 6 roles. LEARNED.md is 13236 B against a 13819 B ceiling. Validation is 45362 B against a 45945 B ceiling. Code Review is 32615 B, down from 47017 B. All five pinned surfaces are byte-identical to 01de2119. |
| 02 | compliant | TEST-002: 5 HAZ lines are identical, and all 17 stay entries are verbatim in LEARNED.md. |
| 03 | compliant | TEST-003/004 PASS. My own `diff` of the base blob against LEARNED.md shows deletions only, plus the pointer paragraph. The history file holds the 18 entries verbatim (read in full). |
| 04 | compliant | TEST-005 PASS. The digest code is untouched. |
| 05 | compliant | TEST-006 and TEST-007 PASS. TEST-007 runs the real `aai-sync.sh` against an owned target and a fresh target. |
| 06 | compliant | TEST-008: pointer 714 B, replay step 3a at `.aai/SKILL_REPLAY.prompt.md:33`. TEST-009: a real append lands in LEARNED.md and the history file stays byte-identical. |
| 07 | compliant | prompt-diet rc=0 (TEST-012 = 57901, and the TEST-010 measured growth is 108 B). TEST-006/011 and test_126 PASS. TEST-1762 PASS. pr-preflight rc=0. |

Deviations from the frozen spec. Each is reasonable, and each is listed here:
- **pr-preflight edit outside the scope list.** `tests/skills/test-aai-pr-preflight.sh` is edited (the `+108` want_growth term), but it is not in the spec's inline review scope. The edit is required because that test re-derives the TEST-012 pin.
- **CHANGELOG.md not in the diff.** It is listed in the inline review scope but not changed. This matches the "product docs after LOOP COMPLETE" practice, but someone still needs to write it.
- **Spec amended after freeze (9fe9e551).** The 11 Mutation cells were rewritten into the sed grammar. The amendment is in the measurement class and has no owner sign-off yet.
- **Base-blob tests skip in a shallow clone.** TEST-002/003/004/006/011 skip, with a named skip line, when the pinned base commit is missing. This applies the spec's immutable-pin rule. It is not a silent pass.

## Focus answers

1. **Always-needed hazards moved out?** No HAZ line moved. All five live in the contract section, which TEST-002 proves. Each moved entry's enforceable part has a guard: the reaper, the external-runner lint, `session-lock` plus the `merge-cleanup.mjs` untracked-collision refusal, `spec-lint`, `close-work-item`, the prompt-diet ledger, `ledger-merge`, and the four lint rules. Three pieces of advice have no guard and now leave standing context: serialize audit-touching suites, hand-close a NEEDS-TRIAGE scope, and the Framework-owns-HOW invariant marked "routed to canon". No canon text with that name exists. Spec R1 discloses this and gives the owner the choice, so it is listed under cannot_verify, not as a defect. Every `[local]` entry stays, including the git-clean and EVENTS-restore corrections.
2. **Classification rule soundness.** It is deterministic and matches D2 exactly. The live split is 18 moved and 17 kept, and the rule is consistent with routing TEST-006's marker grammar: dated entries carry an `fu-` id or a script name. It has two weak spots:
   - **NB-2: false positive (sometimes moves a pending lesson).** The `guard shipped:` and `routed to canon` text is matched anywhere in the entry, not only as the entry's own annotation.
   - **INFO: false negative (only costs bytes).** A `**RESOLVED:**` form, with no space after the word, is not caught.
3. **Downstream impact.** Both sync scripts copy only top-level files from `docs/knowledge`, so `history/` is never seeded. TEST-007 proves this for the `.sh` script; the `.ps1` script is unverified on Windows (cannot_verify). A project's own unsplit LEARNED.md stays byte-identical, and the code path is unchanged (TEST-006/007). A fresh install receives the slim file with its "when present" pointer, which is spec R2 (pre-existing seeding).
4. **Test quality.** The tests can catch real regressions. They read real manifests and real digests, run the real sync, use a pinned immutable base blob, and include positive controls (the 18-entry base count, history-only bodies > 0, a planted deletion, a planted manifest rewrite, and checks that each edit really changed a file's sha). The mutation cells target production files, not fixtures. Two caveats:
   - **INFO: TEST-002 breaks on purpose when the forward rule is applied.** TEST-002 requires every *base* stay entry to be verbatim in LEARNED.md. The first future scope that ships a stay entry's guard and moves it must re-pin `SLIM_BASE_SHA` in two suites. The spec discloses this. It is a known maintenance cost, not a defect.
   - **NB-1: the lint CLI goes silent under a symlinked path.** It fails loud, so it cannot produce a false green.

## Findings and dispositions (H6)

| # | Rank | File:line | Recommended disposition |
|---|---|---|---|
| NB-1 | NON-BLOCKING (P3) | tests/skills/lib/learned-guard-lints.mjs:591 | (a) Remediate in tree. Compare `fs.realpathSync(process.argv[1])`, or run `main()` unless the module is imported, and add one symlink-invocation assertion. Otherwise (b) promote to a follow-up. |
| NB-2 | NON-BLOCKING (P3) | tests/skills/lib/learned-guard-lints.mjs:121 | (b) Promote to a follow-up (suggested id `fu-learned-standing-annotation-anchor`). Anchor on `(guard shipped:` / `(routed to canon` and add a fixture with a pending entry that cross-references another entry. Not observed live. |
| NB-3 | NON-BLOCKING (P3) | docs/knowledge/LEARNED.md:9 | (a) Remediate in tree. A minimal edit such as "below" → "(now in docs/knowledge/history/LEARNED-HISTORY.md)". This is a false pointer, so disposition (d) "accepted residual" is not allowed. |

INFO (never gates):
- **TEST-002 re-pin cost.** Covered under focus answer 4.
- **`**RESOLVED:` false negative.** Covered under focus answer 2.
- **test_830 prints a non-failing diagnostic line.** When the history file holds extra move-class appends, the script prints a line and continues.

## Next steps

- The orchestrator records a disposition for NB-1, NB-2 and NB-3 as the table above recommends.
- The owner rules on the R1 unloaded-advice residual and signs the 9fe9e551 measurement amendment at merge.
- Write CHANGELOG.md after LOOP COMPLETE.
- Confirm that CI fetch depth lets the base-blob arms run in CI.

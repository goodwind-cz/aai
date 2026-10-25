```yaml
review:
  scope: "origin/main...HEAD (ff32ec2e..b0f8b4ab) in /private/tmp/aai-adapter-slice, branch change/provider-adapter-registry-slice"
  spec: docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "harness-shims.mjs:112-149, HARNESS_SKILLS.yaml shims rows; TEST-3001 PASS (reviewer rerun)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".github/copilot-instructions.md:23-27; TEST-3002 PASS (but see BLOCKING finding 1 on the test's claim)" }
      - { ac: Spec-AC-03, call: compliant, citation: "sync-harness-skills.mjs:381-388,532-555; harness-shims.mjs:180-209; TEST-3003, TEST-3004 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-map.yaml aai-harness-shims row + hygiene-pack globs; lib path selects FULL_RUN reason=shared-lib (superset); hygiene test_111 extension; TEST-3005 PASS, green-TEST-3006.log" }
      - { ac: Spec-AC-05, call: compliant, citation: "COPILOT_SHIM_SHIPPED.list 9 rows; aai-sync.sh:208-234,601-622; aai-sync.ps1:121-151,609-624; TEST-3007, TEST-3008, TEST-3009 PASS (pwsh present)" }
      - { ac: Spec-AC-06, call: compliant, citation: "aai-sync.sh:275,579; aai-sync.ps1:245,578; TEST-3010, TEST-3011 PASS" }
      - { ac: Spec-AC-07, call: non-compliant, citation: "behaviour holds (TEST-3012, TEST-3013 PASS; spec-amend list --strict exit 0) but mutation-gate.mjs --spec exits 5: TEST-3013 record STALE since b0f8b4ab edited AUTONOMOUS_LOOP.md; spec Verification requires exit 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "PROFILES.yaml:184,244-245; wc -l 209 and 563; both follow-ups open; TEST-3014 PASS" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-harness-shims.sh, line: 219,
          issue: "test_3002_copilot_lists_no_skills names a universal negative but asserts only the absence of lines starting two spaces + '- `/aai-'",
          failure_scenario: "a later fragment edit re-adds a skill list in another shape (flush-left '- `/aai-loop` ...', a table, or prose) - --check accepts it because it renders from the fragment, and TEST-3002 stays green while saying the shim lists no skills: the exact 9446fb87 drift this scope exists to close" }
      - { rank: NON-BLOCKING, file: .aai/system/AUTONOMOUS_LOOP.md, line: 97,
          issue: "b0f8b4ab text 'The merge itself signs nothing' contradicts the SPEC-0226 implied-signature fold (spec-amend.mjs:583-601), ROLE_COMMON.md:96 and SKILL_SHIP.prompt.md:108-110; it also went past D6 step 4 without an amendment record",
          failure_scenario: "an orchestrator reading AUTONOMOUS_LOOP after a merge that the fold already signs runs the manual hitl_decision + classify procedure again (duplicate overlays), or tells the owner at the merge checkpoint that the merge signs nothing while SKILL_SHIP prints 'signs on merge:' lines" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.sh, line: 191,
          issue: "awk extraction matches the START/END marker lines exactly, so a CRLF target yields empty override text; the new rule then treats empty text as shipped and replaces the shim. The PowerShell twin (IndexOf) extracts the same block and merges",
          failure_scenario: "a git-bash/Windows target with core.autocrlf=true holds the source shim plus a block '- Our project uses pnpm', and no override file: aai-sync.sh replaces the shim and logs 'unmodified shipped shim replaced, no project overrides' (reproduced in scratch). Base code also lost the text (empty block), so the loss is not new; the false log line and the twin split are" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/harness-shims.mjs, line: 172,
          issue: "a malformed COPILOT_SHIM_SHIPPED.list row raises ShimError inside applyShims, which runs after the tree and shim writes and outside the try that maps ShimError to a clean exit 2",
          failure_scenario: "a hand-typed uppercase or truncated row, then --write: mirror trees and shims are written, then the run dies with an 'unexpected error' stack trace (exit 2) - reproduced in scratch with --check" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-sync.ps1, line: 135,
          issue: "the PowerShell normalisation is wider than D4's N and wider than its own comment: Get-CopilotProjectOverridesContent already .Trim()s (leading whitespace, trailing spaces) and ReadAllText strips a UTF-8 BOM; bash and Node hash the bytes as they are",
          failure_scenario: "a target whose unmodified historical shim carries a BOM: pwsh replaces it, bash merges it into an overrides block (9/9 BOM variants split in the scratch parity run; plain, CRLF, extra-LF and block variants agree 36/36)" }
  cannot_verify:
    - { claim: "the owner's menu answer was literally 'Mergni #501 (Recommended)' (the hitl_decision line is agent-written with by=human)",
        closes_with: "the owner's confirmation or the session transcript; PR #501 head/merge commit/mergedAt do match gh pr view" }
    - { claim: "Copilot, Cursor, Codex and Gemini read the generated files as before",
        closes_with: "a manual check in each harness (spec Seams residual)" }
    - { claim: "aai-sync.ps1 behaviour on Windows PowerShell 5.1 (only pwsh 7 on macOS ran here)",
        closes_with: "the CI Windows Pester leg green on the PR head" }
    - { claim: "the full sweep and the neighbour suites in the Verification list are green",
        closes_with: "the parallel validator's sweep log (the reviewer re-ran only test-aai-harness-shims.sh, mutation-gate, spec-lint, check-test-registration)" }
  overall: fail
```

# Code Review — provider-adapter-registry-slice (round 1)

security_relevant: false

- Scope: `git diff origin/main...HEAD` in `/private/tmp/aai-adapter-slice` (ff32ec2e..b0f8b4ab, 11 commits, 22 files, +1867/-69).
- Spec: `docs/specs/SPEC-0253-spec-provider-adapter-registry-slice.md` (frozen, L2, tdd).
- Reviewer: claude-opus-5-5 (the implementer was claude-sonnet-5-5). I read the tree only. Commands ran in a scratch clone at `.../scratchpad/pa-cr-r1/repo`.
- Dispatch note (anti-gaming): the dispatch had a "Focus" list naming areas to check, and a "known pre-existing failures" note. It did not rate any severity or exclude any area. I reviewed the full diff anyway.

## Spec compliance: FAIL (one row, evidence only)

| AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | lib renderer + six registry rows; TEST-3001 PASS on rerun. `sync-harness-skills.mjs --check` prints both OK lines and exits 0 |
| Spec-AC-02 | compliant | Copilot section replaced by the shared fragment; TEST-3002 PASS (see B1) |
| Spec-AC-03 | compliant | DIVERGE/OK/exit codes; eight D1 errors exit 2; TEST-3003/3004 PASS |
| Spec-AC-04 | compliant | the six shims, HARNESS_SHIMS.md and the list each select both suites. `lib/harness-shims.mjs` gives `FULL_RUN reason=shared-lib`, a superset of both (TEST-3005 accepts this explicitly). test_111 green log present |
| Spec-AC-05 | compliant | 9 list rows (amended measurement); both twins; TEST-3007/3008/3009 PASS with pwsh 7.x |
| Spec-AC-06 | compliant | AGENTS.md moved out of the legacy-delete loop into the shim loop in both twins; TEST-3010/3011 PASS |
| Spec-AC-07 | **non-compliant (evidence)** | Behaviour holds. `node .aai/scripts/mutation-gate.mjs --spec <spec>` exits **5**: `OFFENDING TEST-3013: STALE ... target .aai/system/AUTONOMOUS_LOOP.md changed since the record`. Commit b0f8b4ab edited the target after the record was taken. I re-ran the mutation by hand in the scratch clone and it still reddens (`found 0`), so a `mutation-run.mjs --replay` for TEST-3013 should re-stamp it |
| Spec-AC-08 | compliant | PROFILES rows; 209 ≤ 260 and 563 ≤ 590; both follow-ups open with the measured text |

Ledger checks (focus item, verified with the CLIs as well as grep):
- There is one `hitl_decision` (ts 2026-10-25T13:16:02Z, answer `Mergni #501 (Recommended)`). Its head `897008e3…`, merge commit `ff32ec2e…` and merge time `11:45:39Z` match `gh pr view 501`.
- There are six `spec_amendment_classification` overlays (`classifies_record` = the six D6 keys, `owner_signoff:true`). Each source names PR #501 and the hitl ts. All six fold to `bucket: signed`.
- The two `routing-tables-have-an-owner-and-a-seam` records stay `unsigned-tracked` under `fu-amend-update-installs-ref-guar-f8caa1` (open).
- `spec-amend list --strict` exits 0.
- The five D6 trackers read `done` in `follow-ups list --status all`.
- Three measurement amendments for this ride are recorded, and each edit exists in the spec text: line 168 has "8 distinct / 9 rows", line 387 has the separate "Filed by" paragraph, and the Test Plan has the escaped mutation cells with no caret on TEST-3008.

Deviations from the frozen spec. All were disclosed except the last one.
1. D6 step 3 (`follow-ups.mjs close` ×5) appended nothing. `close` answers "already done … nothing appended", which I reproduced. The trackers read done through the fold, so no close record or `resolved_by` exists. Separately, `spec-amend list --json` still shows `tracked_status: "open"` for the six signed records (spec-amend.mjs:632). That disagreement between the two tools predates this scope. INFO.
2. Edits outside the scope list to `test-aai-sync-seed.sh` (TEST-795) and to the hygiene-pack 113→114 pins. Both were named in the hand-off.
3. **Undisclosed:** b0f8b4ab rewrote the sentence before the `sign-merged` sentence in AUTONOMOUS_LOOP.md, which goes beyond D6 step 4. No amendment record covers it, and its wording is the subject of N1.

## Code quality: FAIL (1 BLOCKING, 4 NON-BLOCKING)

**B1 — BLOCKING — tests/skills/test-aai-harness-shims.sh:219 (`test_3002_copilot_lists_no_skills`).**
- The test name claims a universal negative ("lists no skills"). The assertion only proves that no line starts with two spaces followed by ``- `/aai-``.
- Failure scenario: the Copilot shim is now rendered from a fragment, so `--check` accepts any list that is added to the fragment. A flush-left ``- `/aai-loop` -> …`` list, a table, or prose would pass TEST-3002. That is the 9446fb87 drift class this scope exists to close.
- Fix: prove the negative. The committed shim has zero `/aai-` occurrences (`grep -c '/aai-'` = 0), so assert that count over the whole file. Alternatively, rename the test to what it checks. The canon review rule ranks this BLOCKING.

**N1 — NON-BLOCKING (P2) — .aai/system/AUTONOMOUS_LOOP.md:97-102.**
- The new text says "The merge itself signs nothing: `merge-cleanup.mjs` has no signing step".
- The second half is true; I grepped merge-cleanup.mjs and it has had no signing step since #460.
- The first half contradicts three other sources:
  - the SPEC-0226 implied-signature fold: `spec-amend.mjs:583-601` signs an unsigned contract record at read time once its ride is done and merged with `links.pr`;
  - `ROLE_COMMON.md:96`: "The owner's merge direction signs the ride's contract amendments";
  - `SKILL_SHIP.prompt.md:108-110`: the `signs on merge:` lines.
- Failure scenario: after an ordinary merge, an orchestrator either re-signs records the fold already signs (duplicate overlays plus an unneeded hitl_decision), or gives the owner contradictory statements at the merge checkpoint.
- Disposition: **remediate-in-tree.** Reword to say what each mechanism does: merge-cleanup has no signing step; a merged ride's contract records read signed through the SPEC-0226 fold; a backlog the fold does not reach is signed from a recorded owner decision by the classify/close procedure. Then re-run the TEST-3013 mutation replay (this also clears the AC-07 evidence gap).

**N2 — NON-BLOCKING (P2) — .aai/scripts/aai-sync.sh:191-195 together with the new empty-means-shipped rule at :220.**
- The awk extractor matches `$0==start` exactly, so on a CRLF file it yields empty text. `copilot_shim_is_shipped ""` then returns 0 and the shim is replaced.
- Reproduced in scratch: a CRLF target holding the source shim plus a block `- Our project uses pnpm, never npm.`, with no override file, gives extracted=`[]` and REPLACE. The log line says "unmodified shipped shim replaced, no project overrides".
- The PowerShell twin uses `IndexOf`, extracts the block, and merges it.
- The base bash code also lost this text (it wrote an empty block), so this is not new data loss. What is new is a false log record and a deeper split between the twins.
- Disposition: **promote-to-follow-up** (suggested id `fu-sync-sh-crlf-override-block`). The fix is to strip `\r` in the awk comparison, or to treat "markers present but extraction empty" as not shipped.

**N3 — NON-BLOCKING (P3) — .aai/scripts/lib/harness-shims.mjs:172 / sync-harness-skills.mjs:533.**
- The shipped list is parsed inside `applyShims`, after the tree and shim writes and outside the `ShimError`→exit-2 mapping.
- Reproduced: a list row `ZZZ-not-a-hash` makes `--check` print `unexpected error: Error: malformed row…` with a stack trace, exit 2. Under `--write`, the trees and shims are already written by then.
- Disposition: **remediate-in-tree** (read the list in `loadShims`) or record as an `accepted residual:` (P3, an assurance-strength issue with no observed bite).

**N4 — NON-BLOCKING (P3) — .aai/scripts/aai-sync.ps1:121-151 (and 114-117).**
- The PowerShell hash input is wider than D4's N, and wider than the twin's own comment ("delete every CR, drop the trailing LFs"). The extractor `.Trim()`s, and `ReadAllText` strips a BOM.
- Scratch parity run over the 9 historical blobs × 5 variants: plain, CRLF, extra-LF, block and CRLF-block agree in bash and pwsh, 36/36. BOM variants split 9/9: pwsh replaces, bash merges. Both outcomes are safe, because the bash side keeps the text.
- Disposition: **accepted residual** candidate (P3, an unexercised edge with no false record). Alternatively, fix the comment so it states what the twin compares.

INFO:
- The AGENTS.md install (D5) replaces a target's own AGENTS.md and names it in the sync-conflict advisory (TEST-3010/3011). This is not silent. The advisory's suggested home, `docs/ai/project-overrides/AGENTS.md`, is read by nothing, which is the same as the existing CLAUDE.md policy.
- Bash `copilot_shim_is_shipped` checks the hash tool correctly: sha256sum, then shasum, with output that is not 64 hex counting as a failure, and `|| hash=""` keeps it safe under `set -e`. TEST-3008(d) stubs both tools.
- `String.prototype.matchAll` exists.
- `check-test-registration` exits 0 and `spec-lint` passes.

## cannot_verify
1. The owner's literal menu answer for #501. The hitl line is agent-written; the PR facts do match.
2. That each harness reads the regenerated shims as before (Seams residual).
3. Windows PowerShell 5.1 behaviour of the new PowerShell function (only pwsh 7 ran here).
4. The neighbour suites and the full sweep. I ran only the new suite (13/13 PASS, rc=0), mutation-gate, spec-lint and check-test-registration.

## Warning dispositions (H6)
- N1: remediate-in-tree.
- N2: promote-to-follow-up (`suggested: fu-sync-sh-crlf-override-block`, P2).
- N3: remediate-in-tree, or `accepted residual: P3 list-validation ordering, no observed bite`.
- N4: `accepted residual: P3 PowerShell normalisation wider than N (BOM/Trim), conservative on the bash side, no false record`, or fix the comment.

## Next steps
1. Fix B1: assert zero `/aai-` occurrences in the Copilot shim, or rename the test.
2. Fix N1's wording, then run `mutation-run.mjs --replay` for TEST-3013 (and for any other row whose target changes). Then `mutation-gate.mjs --spec` must exit 0.
3. Have the orchestrator record the N2 to N4 dispositions, then run a re-review on the delta.

# Code Review r1: implied-signing-without-links-pr

```yaml
review:
  scope: origin/main...HEAD (72a8c2ea...785e2247), worktree /private/tmp/aai-implied-sign, branch change/implied-signing-without-links-pr
  spec: docs/specs/SPEC-0254-spec-implied-signing-without-links-pr.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/spec-amend.mjs:390-395,462-473; TEST-3017 + TEST-3023 green (local run rc=0)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/spec-amend.mjs:467-472, SQUASH_PR_SUFFIX :387; TEST-3018/3019/3020/3021 green" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-3022 green: 10 keys signed, totals 400/142/2/0/0 against 72a8c2ea" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "docs/ai/decisions.jsonl +1 hitl_decision, +4 owner classifications after it, +1 follow_up_status done; TEST-3024 green (list --strict rc 0)" }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/system/AUTONOMOUS_LOOP.md:99-102; TEST-3025 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 390,
          issue: "squashPrFromBase trusts `git log -1 --first-parent -- <rel>` in a shallow clone, where the shallow boundary commit is reported as touching every file in the tree. The subject of an unrelated tip commit is then read as the commit that merged the ride.",
          failure_scenario: "Fixture: a done doc with empty links.pr added by a direct push (subject `direct push no suffix`), then an unrelated commit `feat: unrelated (#30)`. A full clone reads `unsigned-tracked` (correct). `git clone --depth 1` reads `signed`. On a push build of main with the default actions/checkout depth 1, refs/remotes/origin/main exists and its tip is a squash commit ending in (#N). Every done ride with empty links.pr then reads signed, including the 26 direct-push or merge-commit docs measured in the spec, and list --strict passes for amendments no owner signed. This is a false signature on the signature gate, introduced by this diff. The links.pr rule never depended on history depth." }
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 462,
          issue: "The implied signature does not order the record against the merge. A contract amendment recorded under a ref_id whose ride doc is already done on base reads signed at once.",
          failure_scenario: "Fixture: ride squash-merged as `feat: ride (#77)` (doc done, links.pr []). A later branch appends a new contract spec_amendment on the same ref_id. `list --base-ref main` reads it `signed` before any merge checkpoint shows it. SPEC-0226 already has this gap for links.pr docs (fixture A2 reads signed too); this diff extends it to the 61 empty-links.pr done docs." }
  cannot_verify:
    - { claim: "The owner actually answered 'Mergni #502 (Recommended)' for PR #502. The hitl_decision line says by: human, actor tdd-implementation.",
        closes_with: "the orchestrator transcript or session journal entry showing the owner's menu answer" }
    - { claim: "Mutation rows reddened their tests (mutation-TEST-30xx.txt records exist, base_commit 68a57e66). The reviewer did not re-run mutation-run.mjs against HEAD 785e2247.",
        closes_with: "Validation's mutation-gate run on the reviewed head" }
    - { claim: "Downstream installs and CI checkouts with shallow history hit finding 1 in practice. This repo's workflows use fetch-depth: 0.",
        closes_with: "a survey of downstream CI checkout depth, or the fix plus a shallow-clone fixture test, which makes the question moot" }
  overall: fail
```

security_relevant: true

## Scope and spec

- Range `origin/main...HEAD` (7 commits, 9 files). The worktree was clean at review time (`git status --porcelain` empty).
- Spec: `docs/specs/SPEC-0254-spec-implied-signing-without-links-pr.md` (frozen, ceremony 2, strategy tdd).
- Dispatch coaching check: the dispatch set a focus question (can the check imply a false signature?) and listed probe ideas. It did not pre-rate severity, predict findings or exclude any area. The full scope was reviewed.

## AC table walk

| Spec-AC | Call | Citation |
|---|---|---|
| Spec-AC-01 | compliant | `checkRideMerged` returns true for done + empty links.pr + strict suffix (spec-amend.mjs:462-473). TEST-3017 and TEST-3023 pass in a scratch clone (`env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh`, rc=0, all 80 PASS lines). |
| Spec-AC-02 | compliant | Not-done, malformed subject, side branch, checkout-only suffix and unresolved base all read unsigned. TEST-3018 to TEST-3021 pass. My own probes agree: a suffix only in the body reads unsigned, and a later direct push reads unsigned. The shallow clone case is outside the AC's enumerated arms but violates D1 in spirit (finding 1). |
| Spec-AC-03 | compliant | TEST-3022 passes on the real history at 72a8c2ea with totals 400/142/2/0/0. |
| Spec-AC-04 | compliant | One hitl_decision, four owner classifications after it, and the tracker reads done. TEST-3024 passes. Ledger and EVENTS keep origin/main as a byte-exact prefix (cmp verified). |
| Spec-AC-05 | compliant | AUTONOMOUS_LOOP.md 6a contains both literals and the old fragment is gone. TEST-3025 passes. |

Deviations from the frozen spec. All are disclosed by the implementer; none is non-compliant:
- The TEST-3023 Mutation cell was re-anchored through a `measurement` spec_amendment (decisions.jsonl, ts 2026-10-25T19:58:23Z). The spec row now shows the `if (st && st.s > 0 && st.u === 0)` cell.
- D4 step 2: `classify` also needed `--ts/--ref`.
- D4 step 3: the tracker close used `--correct` to append an explicit done record. The spec named a plain `close --resolved-by`.
- TEST-3024 skips the ledger's `#` header line (`startsWith("{")` filter).
- Observation: the four hand overlays for #502 are now redundant with the seam itself. TEST-3022 shows the records read signed without them. This is harmless and serves as belt and braces.

## False-signature probes (real git fixtures, scratch only)

| Probe | Result | Verdict |
|---|---|---|
| C: direct-push done doc, then an unrelated `(#30)` tip; full clone vs `--depth 1` | full: unsigned; depth 1: **signed**; depth 2: unsigned | **finding 1, BLOCKING** |
| A: new contract record on an already-merged ride's ref_id (empty links.pr) | signed | finding 2 (pre-existing class, widened) |
| A2: same with links.pr [77] (old rule) | signed | shows the gap predates this diff |
| B: ride doc flipped to done by an unrelated PR `(#41)` | signed | by design: D1 trusts the base branch |
| D: squash-merged, then a direct push touching the doc | unsigned | fail-closed, matches the declared residual |
| F: revert-shaped subject `Revert "..." (#80)` on a done doc | signed | matches D1 (a real revert restores a non-done status) |
| G2: suffix only in the commit body | unsigned | correct, `%s` is the subject only |
| H: explicit `--base-ref HEAD` on the ride branch | signed | the operator chose that base; default callers do not pass one |
| I: no origin/main, local main has an unpushed `(#9)` commit | signed | pre-existing default base fallback (refs/heads/main); INFO |
| J: doc path containing `[x]` | signed (resolved) | the pathspec glob is harmless here; INFO |

## Findings

### BLOCKING 1: shallow history fabricates "the newest commit that touched the doc"
`.aai/scripts/spec-amend.mjs:390-395` (`squashPrFromBase`). In a shallow repository, git presents the boundary commit as having added every file. `git log -1 --first-parent -- <rel>` then returns the tip's subject for any doc whose real last-touching commit lies beyond the depth. On a squash-merge repository that tip almost always ends in ` (#N)`. The result is that every done ride with empty `links.pr` reads merged and its contract amendments read owner-signed. This is the false positive the spec's own strategy section calls worse than a missing signature. The failure scenario (fixture C) is reproduced above.

Recommended fix (remediate in-tree; small): in `squashPrFromBase`, return `null` when `git rev-parse --is-shallow-repository` prints `true`. Alternatively, return `null` when the commit found is listed in `$(git rev-parse --git-path shallow)`. Add a fixture test (`git clone --depth 1 file://...` of the C repo) that reads `unsigned-tracked`, plus a mutation row that removes the guard. The spec's D1 enumeration ("every other case reads unmerged") then gains the shallow arm. That change takes a contract-class amendment or a measurement disclosure, per the HITL scope-change convention.

### NON-BLOCKING 2: no ordering between the amendment record and the merge
`.aai/scripts/spec-amend.mjs:462-473` with the fold at :615-623. A contract amendment appended after the ride merged, on the same ref_id, reads signed immediately. The PR #502 body never disclosed it, and no merge checkpoint shows it. This was already true for docs with `links.pr` under SPEC-0226 (probe A2). This diff widens it to the 61 done docs with empty `links.pr`.
Recommended disposition: promote to a follow-up (P2), e.g. `suggested: fu-implied-sign-ignores-record-order`. Possible fix: imply a signature only for records whose ts precedes the committer date of the merging commit, or whose ledger line is present in the merging commit's blob.

### INFO
- Fallback base `refs/heads/main` (probe I) can read a local, unpushed `(#N)` commit as a merge. This predates the diff; the old links.pr rule behaved the same way.
- `isDone` in the index entry is now unused by `checkRideMerged`. It is harmless and still documented in the cache comment.

## Warning dispositions (H6)
- NON-BLOCKING 2: recommended disposition (b), promote to a typed follow-up. The orchestrator records it; this reviewer files nothing.

## Next steps
1. Implementation remediates BLOCKING 1: a shallow guard plus a fixture test and a mutation row. It discloses the D1 arm through the amendment convention.
2. The orchestrator files the follow-up for NON-BLOCKING 2.
3. Run a re-review on the delta.

## Evidence run by the reviewer
- `git clone --no-local /private/tmp/aai-implied-sign <scratch>/clone && env -u AAI_ROLE bash tests/skills/test-aai-spec-amend.sh`: rc=0, all tests passed, TEST-3017 to TEST-3025 PASS.
- Probe script `/private/tmp/claude-501/-Users-ales-Projects-aai/84834df3-26b2-4169-98af-6a142178eee5/scratchpad/is-cr-r1/probe.sh`: results in the table above.
- `cmp` prefix checks: `docs/ai/decisions.jsonl` and `docs/ai/EVENTS.jsonl` keep origin/main as a byte-exact prefix.

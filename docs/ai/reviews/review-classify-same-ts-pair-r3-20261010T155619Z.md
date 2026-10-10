# Code Review — classify-same-ts-pair, round 3 (PR #449 bot-sweep remediation)

```yaml
review:
  scope: "2590c3d2..8a2038e0 (new in this round: 6f80569b..8a2038e0), worktree /Users/ales/Projects/aai-change-classify-same-ts-pair, branch change/classify-same-ts-pair, base origin/main cf39c58f"
  spec: docs/specs/SPEC-0219-spec-classify-same-ts-pair.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "the delta does not touch the record-addressed classify path or the fold; round-1 evidence (TEST-001/002) still applies" }
      - { ac: Spec-AC-02, call: compliant, citation: "spec-amend.mjs:1421-1423: an all-identical pair is refused with exit 2, the reason names 'ambiguous and indistinguishable', and the ledger is untouched (usageError). This is the AC's 'indistinguishable' case reached without --record; TEST-012 arm (b)" }
      - { ac: Spec-AC-03, call: compliant, citation: "foldAmendments untouched; decisions/EVENTS/test-runs are byte-exact prefixes of HEAD from cf39c58f, 2590c3d2 and 6f80569b; live list --strict exit 0" }
      - { ac: Spec-AC-04, call: compliant, citation: "AC row now carries the byte-identical carve-out (SPEC-0219 AC table) and D6 has the matching paragraph; code at spec-amend.mjs:1139-1151 (add) and 1684-1693 (restamp) matches it; disclosed as contract amendment decisions.jsonl 2026-10-10T15:51:22Z, unsigned-tracked by fu-amend-spec-classify-same-ts-pair (open). TEST-010 green, RED accepted product_red. Validation r2 F1 closed" }
      - { ac: Spec-AC-05, call: compliant, citation: "spec-amend.mjs:1986-2023: the trailer branches on noCommand, so the exit-0 promise is printed only when every violation got a command. TEST-011 and TEST-012; red-TEST-010/011/012 all ACCEPTED product_red (r2 NB-2 closed); mutation-TEST-012 RED" }
      - { ac: Spec-AC-06, call: compliant, citation: "live ledger: the only appended lines are two spec_amendment records for this ref; list --strict exit 0" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/spec-amend.mjs, line: 1421,
          issue: "Only an ALL-identical candidate set takes the new honest refusal. A pair that mixes byte-identical duplicates with a distinct record still gets the old refusal. That refusal lists the duplicate key twice and prints the generic '--record <key>' template, and plugging in the duplicate key exits 2 (indistinguishable). This is the same defect class as r2 NB-1, still open for a mixed pair.",
          failure_scenario: "A legacy or hand-appended ledger holds records A, A and B at one (ts, ref). Running classify without --record prints record=2b4c97b105f6 twice, then record=dcd87375696b, then the template. Using 2b4c97b105f6 exits 2. Reproduced on a scratch copy (cr-f3). By contrast, list --strict on the same ledger is honest: two notes, one --record line for B, and the noCommand trailer." }
    info:
      - "TEST-012 mutation row covers only the trailer branch (noCommand). The classify all-identical branch (spec-amend.mjs:1421) has a test arm, TEST-012 (b), which asserts record= once and no '<key>', but it has no mutation row. Disclosed by the dispatch."
      - "The Spec-AC-04 evidence column still cites only TEST-006/007 logs. The carve-out's evidence (TEST-010) is mapped in the Test Plan but not cited in the AC row. docs-audit --gate passes either way."
      - "The 15:35:27Z measurement record still says 'AC rows and contract unchanged'. It is not edited (HAZ-LEDGER), and the 15:51:22Z contract record names it and corrects it explicitly. An appended correction is the right shape."
      - "mutation-TEST-012 base_commit is 6f80569b (pre-commit worktree). target_sha256 matches the committed engine, and mutation-gate PASS (12 rows)."
  cannot_verify:
    - { claim: "restamp of a byte-identical record skips the append and still re-anchors (spec-amend.mjs:1684-1693)",
        closes_with: "a suite test plus a mutation row for the duplicateRecord branch; today only Validation r2's probe P1 covers it" }
    - { claim: "TEST-010/011/012 and the full spec-amend suite are green at 8a2038e0, locally and on Linux CI",
        closes_with: "Validation's concurrent run at this head and the CI run once pushed (this reviewer was told not to run suites)" }
    - { claim: "the owner accepts the AC-04/D6 carve-out",
        closes_with: "owner signature on the 15:51:22Z contract record (classify --record ... --signoff owner) at the merge checkpoint, which closes fu-amend-spec-classify-same-ts-pair" }
  overall: pass
```

## Scope and method

I read delta 2590c3d2..8a2038e0 in full. New code this round is 6f80569b..8a2038e0: spec-amend.mjs +13, test +43, two ledger records, the spec AC-04/D6 text and Test Plan row, and the INDEX timestamp. I also reread the r2 review and Validation r2 to check what they flagged against this commit. No suites and no mutation-run were executed, as instructed.

Read-only gates run on the worktree:
- `spec-amend list --strict`: rc 0
- `tdd-evidence-check --red` on red-TEST-010, 011 and 012: all ACCEPTED (product_red)
- `docs-audit --gate SPEC-0219`: GATE PASS
- `spec-lint` on SPEC-0219: LINT PASS
- `mutation-gate --spec <path>`: GATE PASS, 12 rows
- `node --check`: ok
- Ledger prefix checks against cf39c58f, 2590c3d2 and 6f80569b: all PREFIX-OK

I also ran a scratch probe on a copy of `.aai/` under the session scratchpad (cr-f3).

Coaching check: the dispatch summarises prior findings and names a known mutation-coverage gap. It does not pre-rate findings or exclude any area. I reviewed the full delta.

## Prior findings, closed?

- **Validation r2 F1 (contract change disclosed as measurement): closed.** The AC-04 row and D6 now state the carve-out. The 15:51:22Z contract record discloses it, names the earlier mis-classed record, and is tracked by the open fu-amend-spec-classify-same-ts-pair, so the owner can sign or reverse it.
- **r2 NB-1 / Validation NB-1 (sibling surfaces advertise an unusable key): mostly closed.** The strict trailer is now honest in every case I probed. The classify refusal is honest for an all-identical pair, but not for a mixed pair. That is NB-1 of this round.
- **Validation NB-2 (unclassified RED logs): closed.** All three logs are accepted as product_red.

## Finding NB-1 (NON-BLOCKING, P3)

spec-amend.mjs:1421 tests `new Set(keys).size === 1`. For candidates {A, A, B}, the size is 2, so the old refusal prints A's key twice plus a template. That template cannot be used with A's key. The fix that would close it: dedupe the listed keys and mark the duplicated key as indistinguishable in the listing.

Reachability: writers can no longer mint an identical pair (the add/restamp no-op), and the live ledger holds 0 identical (ts, ref, key) triples. Only a hand-appended or legacy ledger can reach this. Nothing false is recorded anywhere, and the exit-2 refusal is still correct; only the printed hint misleads.

**Recommended disposition: (d) accepted residual.** Reason: a P3 message-quality gap on a shape no writer can produce. There is no observed bite, and the strict gate, which is the surface operators actually follow, is already honest for this shape. The alternative is (a): a two-line remediation in tree plus a TEST-012 control arm. The orchestrator records the choice. This reviewer files nothing.

accepted residual: classify's pair-addressed refusal on a mixed (identical + distinct) pair still lists the duplicate key twice with the generic template. Writers cannot create the shape, and list --strict prints the honest note for it.

## Regression

- The unshared-pair strict trailer is byte-identical. TEST-012's control arm pins this.
- A distinct pair still gets both keys plus the template (TEST-012 control).
- The fold is untouched.
- Ledgers are append-only, verified by byte prefix.

## Next steps

1. Orchestrator: record NB-1's disposition in code_review.notes.
2. Validation: confirm the suite is green at 8a2038e0. CI runs after the push.
3. Owner at merge: sign or reverse the 15:51:22Z contract record. This closes fu-amend-spec-classify-same-ts-pair.

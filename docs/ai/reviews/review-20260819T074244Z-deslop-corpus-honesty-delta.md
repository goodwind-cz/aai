# Code Review — deslop-corpus-honesty (delta re-review)

```yaml
review:
  scope: >-
    working-tree delta since review-20260818T224100Z (R-12..R-17):
    .aai/scripts/deslop-unrequested.mjs, tests/skills/test-aai-deslop.sh,
    docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md, docs/ai/decisions.jsonl,
    CHANGELOG.md, docs/INDEX.md
  spec: docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "unchanged by the delta; TEST-022 green (own run, 28/28). Corpus rule constants deslop-unrequested.mjs:89-93; exact-equality pins test-aai-deslop.sh:1522-1527" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-023 green; delta is the R-14 discriminator at test-aai-deslop.sh:1623-1648. Verified ok=0 (:1646) sits outside the if/elif/else, so no branch can flip the verdict" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "unchanged by the delta; TEST-024 green. docs/analysis/deslop-candidate-adjudication-20260815.md present (untracked, in code_review.scope)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-025 green; deslop-unrequested.mjs:306-310 reason ternary unchanged this delta" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-020 + TEST-026 green; R-12 (deslop-unrequested.mjs:253) and R-13 (:1100) both independently mutation-proven load-bearing by me — see Evidence. Wording caveat in NB-1" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-005/TEST-006 green; withdrawal narrative corrected at spec:516 per the prior review's NB-3, carried by fu-deslop-suite-additivity-guard" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "TEST-028 green; docs-audit --gate spec-deslop-corpus-honesty rc=0 (own run); spec:495-500 carries the cmp correction from the prior review's NB-4" }
      - { ac: Spec-AC-08, call: compliant,
          citation: "unchanged by the delta; check-test-registration.mjs rc=0 (own run); test-aai-prompt-diet.sh untouched since the prior review (mtime 2026-08-18T13:57Z)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/deslop-unrequested.mjs, line: 1099,
          issue: "The ninth check-that-cannot-fail. Under --diff, renderJson derives BOTH sides of D4's balance rule from the same two terms — examined = documents.length + diffUnreadable, and sum(excluded) = diffUnreadable because every other bucket is a hardcoded 0. examined === count + sum(excluded) is therefore unfalsifiable on the --diff path. Measured: the R-12 mutant (drop `unreadable,` from resolveDiffCorpus:253) prints count 0 / examined 0 / unreadable 0 and balance STILL true. The two --diff pins (test-aai-deslop.sh:1352-1356 and :1938-1942) therefore rest entirely on their literal clauses; the balance clause in each is decorative. Spec-AC-05 (spec:466 'The equation holds under --diff too'), the TEST-020 Test Plan row (spec:861 'and balances the equation') and CHANGELOG.md ('The --diff payload balances by the same equation') each publish a property that cannot fail.",
          failure_scenario: "A later change miscounts --diff unreadable paths (dedupe, a path counted once but read twice, a symlink loop counted per hop): examined and sum move together, balance stays true, both arms stay green. Only the hardcoded literals (2/2 in TEST-020(a), 1/1 in TEST-026) object, and only for those exact fixture shapes. Fix: have resolveDiffCorpus return its own `examined` = the number of STATE-named paths considered, and let renderJson pass it through — the equation then compares two independently-sourced numbers, exactly as under --all. The prior review offered this as one of two fixes ('omit examined for --diff'); the branch taken is the one that produced the tautology." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-deslop.sh, line: 1965,
          issue: "R-16's recorded justification overstates its control. Measured against the PRE-B-4 fixture (d3 minus the dangling symlink) with R-13's actual regression restored (`&& !result.corpus.empty`): count 0 / examined 1 / draft 0 / sum 0 / balance FALSE — the earlier fixture already bites on two clauses (excluded.draft === 1 and the balance clause). Validation's 'blind' control used a bespoke narrowed mutation (`if (unreadable.length > 0 && excluded.draft > 0) { examined -= ...; excluded.unreadable = 0; }`), not the guard restoration the pin exists to prevent. The symlink is worthwhile added coverage of the combined path and costs nothing, but the B-4 comment here and the Spec-AC-05 note (spec:692) claim the earlier fixture 'pinned only half of the fix', which my measurement contradicts.",
          failure_scenario: "A reader trusts the recorded control, concludes that a filter-only fixture cannot detect an empty-corpus fall-through, and omits that cheaper shape from the next such pin. This is the same class R-17 corrected for fu-docnumbering-t013-writes-real-tree, and deserves the same treatment: an append-only correcting record, not a silent edit." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-deslop.sh, line: 1532,
          issue: "R-15 fixed the instance, not the class. TEST-022's three human-header assertions are still unanchored `grep -qF` — the exact superstring shape R-15 removed from TEST-026, in the same file, in the arm whose entire job is corpus-rule/header agreement. A header printing `dirs: docs/specs, docs/issues, docs/rfc, docs/other` satisfies :1532; `types: spec, change, issue, techdebt, rfc, research` satisfies :1534. TEST-026:1908-1910 also keeps three unanchored bucket-NAME checks that assert no count.",
          failure_scenario: "A human-render-only bug (renderHuman:1067 appends to the joined lists while CORPUS_DIRS/REQUIREMENT_TYPE_LIST are unchanged) leaves the operator-facing header wrong and every arm green. Mitigated but not closed: the JSON exact-equality assertions at :1522-1527 read the same constants renderHuman renders from, so a rule change is caught — the residue is exactly the render-side superstring R-15 was written to eliminate. Two-character fix (-qF -> -qxF) plus the full expected line." }
      - { rank: NON-BLOCKING, file: docs/ai/validation, line: 0,
          issue: "No round-7 validation report exists on disk. B-3 and B-4 — the findings R-15 and R-16 remediate — are cited as 'validation round 7' at test-aai-deslop.sh:1899 and :1965, in the Spec-AC-05 note (spec:692), in two decisions.jsonl follow-ups (ts 2026-08-19T06:25:07Z) and throughout round 8's report, but docs/ai/validation/ jumps round6 (2026-08-19T000900Z) straight to round8 (2026-08-19T073933Z) and no file anywhere under docs/ai/ carries round 7's evidence. One of round 7's own follow-ups records the cause: fu-mutation-rig-copies-whole-tree, '19523 s wall, standing set never reached'.",
          failure_scenario: "The originating measurements for two of the six delta items are unauditable — a reader who wants to check the B-3 superstring mutation or the B-4 probe-P10 claim has only prose in a spec note. Round 8 reproduced both pins independently and I reproduced R-12/R-13/R-16 myself, so the substance is closed; the trail is not. Recommend the round-7 report be written from its surviving artifacts before close, or its absence recorded as a decisions.jsonl process_finding." }
      - { rank: NON-BLOCKING, file: docs/ai/validation/validation-20260819T073933Z-deslop-corpus-honesty-round8.md, line: 8,
          issue: "Round 8 claims a 05:55Z-07:45Z window and 'Phase 1 - standing set (run first, before any mutation)', but every remediated file's mtime falls inside that window: test-aai-deslop.sh 06:30:36Z, deslop-unrequested.mjs 06:46:04Z, SPEC-DRAFT 06:46:59Z, docs/INDEX.md 06:55:50Z (its own Generated stamp). Its 'tree unchanged' evidence is a file COUNT (git status | wc -l = 17), which cannot detect content changing under the run.",
          failure_scenario: "Phase 1's standing set may have measured a pre-R-12/R-13 engine, which is the same staleness class (fu-validation-staleness-undetected) that invalidated the first code review of this ride. Closed empirically for the figures: I re-ran the full standing set on the final tree and reproduced it exactly (28/28, spec-lint 0, gate PASS, registration clean, 331/334/56/417, balance true). Not closed for the 15 selected suites I did not re-run." }
  cannot_verify:
    - { claim: "The five known-red suites are still exactly five and all clear at commit + close.",
        closes_with: "Re-running the sweep round 8 describes; I took its enumeration as given and did not re-run any of the five, nor the copy-only pair (test-aai-docs-audit.sh, test-aai-doc-numbering.sh), which are forbidden against the real tree." }
    - { claim: "Round 8's Phase 1 measured the post-remediation tree.",
        closes_with: "Content hashes (not a file count) recorded at validation start and end. My own re-run closes the figures it reports but not the ordering claim." }
    - { claim: "The two `ln -s /nonexistent/...` fixtures (TEST-026:1880, :1987) behave on Windows/Git-Bash.",
        closes_with: "A CI run of this bash suite under MSYS. Reasoned mitigation: if `ln -s` cannot create the dangling link the file is simply absent, so examined drops to 1 and unreadable to 0 and the arm fails LOUDLY rather than silently. The main-fixture symlink predates this delta, so the delta adds no new portability class." }
    - { claim: "TEST-023's real-tree arm keeps working after the ride's own SPEC-DRAFT is closed and CHANGE-0125/CHANGE-0096 age.",
        closes_with: "fu-deslop-ac02-single-citation being worked; by construction the arm depends on three single citations that no gate protects." }
  overall: pass
```

## Scope, method, and the dispatch's framing

Delta re-review of the working-tree changes made after
`docs/ai/reviews/review-20260818T224100Z-deslop-corpus-honesty.md` (mtime
2026-08-19T00:41:39+02:00 = 22:41:39Z). Six files carry mtimes after that point:
`CHANGELOG.md` (22:51Z), `docs/ai/decisions.jsonl` (06:29Z),
`tests/skills/test-aai-deslop.sh` (06:30Z), `.aai/scripts/deslop-unrequested.mjs`
(06:46Z), `docs/specs/SPEC-0136-spec-deslop-corpus-honesty.md` (06:47Z),
`docs/INDEX.md` (06:56Z). Nothing else in the 17-file scope moved.

Tree state, start and end, identical: HEAD `83c389945cbf6eba206abd9219e66e612b9e07e9`,
`git status --porcelain=v1 -uno | wc -l` = 17. Four untracked in-scope files
(`docs/analysis/deslop-candidate-adjudication-20260815.md`,
`docs/specs/SPEC-DRAFT-...`, `docs/issues/CHANGE-DRAFT-...`, the prior review
report) — all named in `code_review.scope`, none of them written by me.
No restoring git command was run. Every mutation ran on **copies of the engine
file** in the scratchpad against **scratchpad fixtures**; the real engine's
sha256 is `c7c0770c...` at start and end. I did not run
`test-aai-docs-audit.sh` or `test-aai-doc-numbering.sh` in any form.

Measurement environment: all figures produced under non-interactive `bash`
with `/usr/bin/grep` by absolute path. No ugrep, no zsh history modifiers.

**Coaching record (anti-gaming clause).** The dispatch enumerated the delta as
R-12..R-17 and carried validation's non-blocking pre-rating of two residual
risks into the prompt, and it scope-excluded the substance of the first review.
It also explicitly disclaimed ranking, said it was not naming the main problem,
and invited disagreement — and it disclosed the registry item about dispatches
framing reviewers. Recording it as the contract requires. I reviewed the delta
and the file-level neighbourhood of each change; NB-1, NB-2 and NB-3 were formed
from my own measurements, not from the list.

## Evidence

| Check | Result |
|---|---|
| `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-deslop.sh` | rc=0, **28 PASS, 0 FAIL** |
| `node .aai/scripts/spec-lint.mjs` | rc=0, LINT PASS |
| `node .aai/scripts/docs-audit.mjs --gate spec-deslop-corpus-honesty` | rc=0, GATE PASS |
| `node .aai/scripts/check-test-registration.mjs` | rc=0 |
| `node .aai/scripts/deslop-unrequested.mjs --all --json` | corpus 331 / examined 334 / sum 3 / balance true / candidates 56 / suppressed 417 |

### Mutation probes (scratchpad engine copies, scratchpad fixtures)

**R-12 pin — drop `unreadable,` from `resolveDiffCorpus`'s fully-unreadable return.**
Fixture: TEST-020(a)'s shape (both `current_focus` paths naming absent documents).

| engine | result |
|---|---|
| clean | `count=0 examined=2 unreadable=2 sum=2 balance=true` |
| mutant | `count=0 examined=0 unreadable=0 sum=0 **balance=true**` |

The pin holds — but only through its literal clauses. This is the measurement
behind NB-1: the mutant restores the exact residue-hiding shape D4 exists to
eliminate, and the balance assertion does not notice.

**R-13 pin — restore `&& !result.corpus.empty` in `renderJson`.**
Fixture: d3 (one draft document + one dangling symlink).

| engine | result |
|---|---|
| clean | `count=0 examined=2 draft=1 unreadable=1 sum=2 balance=true` |
| mutant | `count=0 examined=2 draft=0 unreadable=1 sum=1 balance=false` |

Two clauses of TEST-026:1994-1998 bite (`excluded.draft === 1` and the balance).
Pin is load-bearing.

**R-16 control — the same guard restoration against the PRE-B-4 fixture (no symlink).**

| engine | result |
|---|---|
| clean | `count=0 examined=1 draft=1 unreadable=0 sum=1 balance=true` |
| mutant | `count=0 examined=1 draft=0 unreadable=0 sum=0 **balance=false**` |

The pre-B-4 fixture already bites the regression R-13 guards. This is NB-2.

### Static checks on the delta

- `resolveDiffCorpus`'s added `unreadable` does **not** produce a duplicate note:
  the note selection at `deslop-unrequested.mjs:1004-1011` is `if (corpus.empty)
  … else if (corpus.unreadable…)`, so the fully-unreadable branch still emits only
  the EMPTY-corpus sentence.
- `walk()` (`:131-145`) pushes a dangling symlink because `e.isDirectory()` is
  false on an unfollowed symlink dirent, so `readTextSafe` fails and the entry
  lands in `unreadable`. The d3 fixture's mechanism is real, measured above.
- TEST-023's discriminator is diagnostic-only: `ok=0` at `:1646` is outside the
  `if/elif/else`, so no branch can flip a verdict. The pipeline at `:1638`
  (`grep -rlF … | tr`) would be a `set -e`/`pipefail` hazard, but the suite sets
  `set -uo pipefail` **without** `-e` (`:38`), so a no-match grep does not abort.
- R-15's anchors match the renderer: `renderHuman:1069-1070` emits four leading
  spaces, and both `grep -qxF "    examined: N"` assertions carry them.
- R-17 (`decisions.jsonl` last line, ts 06:29:15Z) parses as JSON, is append-only,
  is `type: process_finding` with `relates_to: fu-docnumbering-t013-writes-real-tree`,
  and states plainly that the earlier reproduction note was wrong while keeping the
  item open at P2 on the latent hazard. Honest and correctly scoped.
- `CHANGELOG.md` uses the per-entry `## [unreleased] — <title>` heading form the
  release cutter requires; `docs/INDEX.md` is a clean regeneration.
- The prior review's four NON-BLOCKING findings are all dispositioned: #1 → R-14
  plus `fu-deslop-ac02-single-citation`; #2 → R-12/R-13; #3 → spec:516 correction
  plus `fu-deslop-suite-additivity-guard`; #4 → spec:495-500 correction plus
  `fu-spec0132-cmp-wording`.

## Disposition of the two residual risks named by validation

**1. TEST-023's discriminator reads `requirement_corpus.dirs` only — AGREE, non-blocking.**
Verified independently, not taken on report: the verdict cannot be affected
(`ok=0` unconditional), and TEST-022 pins `dirs`, `types` **and** `statuses` by
exact `JSON.stringify` equality (`:1522-1527`) and runs immediately before
TEST-023 in the dispatch list, so a type or status regression is named as data in
the same run. The mislabel is a diagnostic-quality issue only. One tightening
though: I would **not** defer this. Widening the `widened` predicate at `:1625`
to include `types` and `statuses` is a single expression and is cheaper than
carrying `fu-deslop-ac02-single-citation` for it. Recommended disposition:
remediate-in-tree; the follow-up then covers only the single-citation coupling,
which is its real subject.

**2. `empty_reason` names one cause when there are two — AGREE, wording gap, not a defect.**
I do not think this was dispositioned generously. The degrade-with-NOTE
convention requires the degraded input be *named in output*, and it is, on the
next line, whole-line asserted for exactly this shape at `:2009`. The branch
precedence (unreadable before filter-miss) is principled: an unreadable document
is an operator-fixable defect, a filter miss is normal operation. The honest
criticism — that a one-line headline reads as exhaustive — is real but costs
nothing today and changes no asserted figure.

## Does the delta carry a ninth "check that could not fail"?

**Yes, in the literal sense — NB-1 — but it is a different animal from the first eight.**

The `--diff` balance clause cannot fail, and it lives inside R-12's own new block,
which is the same recursion the ride has now hit eight times. I measured it rather
than reasoned it: the R-12 mutant that reintroduces the exact defect R-12 fixed
leaves `balance=true`.

What makes it different is that it is **decorative, not load-bearing**. The first
eight were checks whose failure was the only thing standing between a defect and a
green suite. This one sits inside a `node_check` expression whose sibling clauses
(`excluded.unreadable === 2 && examined === 2`) do bite, and which I proved bite.
So the delta does not ship an unguarded surface — it ships a published invariant
(`spec:466`, `spec:861`, the CHANGELOG bullet) that reads as verified and is not.
Given this ride's own standard, that gap should be closed by making the equation
falsifiable (source `--diff`'s `examined` from `resolveDiffCorpus` independently),
not by deleting the clause — deleting it would leave the spec's claim standing with
nothing behind it at all.

The two findings I would rank next, and which the dispatch did not name, are NB-2
(R-16's control does not show what it is recorded as showing) and NB-3 (R-15 fixed
one arm; the identical superstring shape survives two arms away, in TEST-022).
NB-3 is the more consequential habit: seven of the nine findings on this ride were
found one instance at a time, and each remediation has fixed the instance in front
of it.

## Recommended dispositions (orchestrator records; a read-only reviewer files nothing)

| # | Finding | Recommendation |
|---|---|---|
| NB-1 | `--diff` balance rule unfalsifiable | remediate-in-tree (source `examined` from `resolveDiffCorpus`; true up spec:466, spec:861, CHANGELOG) |
| NB-2 | R-16 control overstated | remediate-in-tree as an append-only `decisions.jsonl` correcting record, same form as R-17, plus a one-line true-up of spec:692 and the `:1965` comment |
| NB-3 | TEST-022 unanchored header greps | remediate-in-tree (`-qF` -> `-qxF` with the full expected line, both arms) |
| NB-4 | round-7 validation report missing | promote-to-follow-up-ref (P3) or write the report from surviving artifacts before close |
| NB-5 | round-8 window overlaps the remediation writes | fold into the existing `fu-validation-staleness-undetected` (P2) — evidence that a file COUNT is not a staleness check |
| INFO | TEST-026 d3's draft body says `--draft-only-flag` "must still be reported"; nothing asserts it | optional one-line `node_check` |

## Next steps

Overall **pass**. No BLOCKING finding. Merge readiness is gated on the five
known-red suites clearing at commit + close, on the `ci-full` label obligation
round 8 records, and on the NON-BLOCKING dispositions above being recorded per the
H6 warnings policy before closeout.

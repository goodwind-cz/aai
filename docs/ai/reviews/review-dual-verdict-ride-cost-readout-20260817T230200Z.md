# Code Review — ride-cost-readout (dual verdict, adversarial, ROUND 2 / post-remediation)

```yaml
review:
  scope: "working tree (uncommitted): .aai/scripts/generate-factory-report.mjs, tests/skills/test-aai-factory-report.sh, docs/product/factory-performance-report.md, docs/issues/CHANGE-0148-ride-cost-readout.md, docs/specs/SPEC-0134-spec-ride-cost-readout.md, CHANGELOG.md, docs/ai/decisions.jsonl"
  spec: docs/specs/SPEC-0134-spec-ride-cost-readout.md (FROZEN)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:317,354,441,514-533; TEST-031 (fixture + real-ledger + shadow arms). Round-1 BLOCKING closed: the Edge-case note now exists and is mutation-witnessed (M-A: disabling the push -> TEST-031 red on `missing partial-agent-time note`). Real ledger emits `NOTE 4 agent_run(s) carry no duration_seconds`; I independently counted 4 missing runs across 4 rides. New `R-NODUR` fixture ride asserts a partial (50) agent_seconds, not null and not dropped." }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:405-407; TEST-032. Order is CANONICAL_ROLES + Other, exactly the roles that ran, sums to runs_total. NB-6 correctly NOT reordered — the frozen AC mandates CANONICAL_ROLES order; disclosed in the caption instead." }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:35-37 (single import), :353 (single extractUsageTotal call site reused by the new fold at :386); TEST-033 grep contracts (`usage_total_tokens=(` == 0, import == 1) green." }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:772-774; TEST-034 all three coverage shapes. runs_marked>0 implies tokens_total!==null by construction (both keyed on t!==null)." }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:391-394,416-418,506-508; TEST-035 + TEST-031 shadow note-set diff (both directions). Real ledger: 0 disagreement notes over 124 rides, matching the shadow's independent derivation." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-036 green (five declared ledger shapes exit 0, `process.exit([1-9])` grep == 0, no $-digit). Confirmed independently: full real-ledger run exits 0. A SIXTH, undeclared shape crashes — see NB-2; outside the AC's enumerated five, so it does not fail this verdict." }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:879-884; TEST-037 pins 7 <th> by position, 6 caption clauses, cell-by-cell parity, exact <tr> cardinality. NB-4 fix (`no runs recorded`) mutation-witnessed (M-D). NB-5 fix (P-ZERO-TOK) mutation-witnessed (M-B: dropping `&& r.tokens` -> `NaN%` vs expected `n/a`)." }
      - { ac: Spec-AC-08, call: compliant,
          citation: "tests/skills/test-aai-factory-report.sh:873-925 (TEST-026 extended in place). RE-RUN THIS ROUND in a scratch copy: TEST-026 green, whole suite exit 0 with zero FAIL lines. Goldens confirmed unmodified (`git status --porcelain` clean on tests/fixtures/factory-report/). Upgrades round 1's cannot-verify." }
      - { ac: Spec-AC-09, call: compliant,
          citation: "docs/product/factory-performance-report.md:10,12,108-164; docs/issues/CHANGE-0148-ride-cost-readout.md:8; TEST-039. NB-2 fix verified by mutation (M-C: deleting ONLY the frontmatter `- ride-cost-readout` line -> red). NB-3 fix verified in both directions (M-E garbage date -> red; M-G legitimate future bump 2027-01-05 -> still green)." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 258,
          issue: "R2-NB-1 — the BLOCKING-1 note's COUNT is unpinned. The arm can only fail on the note's ABSENCE, never on a wrong number. The fixture holds exactly one missing-duration run, so any aggregation error still renders `NOTE 1`; and the real-ledger shadow arm — which explicitly re-derives the other two (scope_cost) note payloads (the disagreement set, and the strict-> overlap COUNT at :258-261) — deliberately skips this one.",
          failure_scenario: "MUTATION RUN (M-F): move `runsMissingDuration = 0` inside the `for (const m of rides)` loop so it resets per ride. The whole suite stays GREEN (TEST-031 fixture arm, real-ledger arm and shadow arm all pass) while the real report would publish `NOTE 1 agent_run(s)` instead of the true `NOTE 4` — a wrong honesty number on the exact figure round 1 blocked on. Smallest fix: 4 lines in the shadow arm, symmetric with the overlap check already there — accumulate `if (typeof r.duration_seconds !== \"number\") missingDur += 1;` in the existing shadow run loop, parse the note's leading integer, compare." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 523,
          issue: "R2-NB-2 — the new D10 sort comparator calls `a.ref.localeCompare(b.ref)` (lines 523 and 527) on a value the generator otherwise only ever uses as an opaque Map key. `rides` is filtered with a TRUTHY test (`metrics.filter((m) => m && m.ref_id)`, :229), not a string test, so a non-string truthy `ref_id` reaches the comparator and throws an uncaught TypeError. This is a REGRESSION in degrade-and-report: HEAD exits 0 on the identical ledger.",
          failure_scenario: "Reproduced: a METRICS.jsonl with 12 normal rides plus one line carrying `\"ref_id\": 99` -> new generator dies with `TypeError: a.ref.localeCompare is not a function` at :523, exit 1; the committed HEAD generator over the same file exits 0 and renders. Effect: the report silently stops regenerating (close-work-item absorbs the failure per S4/TEST-013, so no close breaks — the page just goes stale). Never seen in 124 machine-written rides, but the generator is vendored downstream where the ledger may not be. Smallest fix: `String(a.ref).localeCompare(String(b.ref))` in both branches." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 500,
          issue: "R2-NB-3 — the two caption clauses that ARE the NB-6 remediation and half the NB-1 remediation are not pinned by anything. TEST-037 asserts six caption substrings; neither new clause is among them, and TEST-039 pins the product doc's older sentences but not its two new Limits bullets.",
          failure_scenario: "MUTATION RUNS: (M-H) delete `Roles are listed in a fixed canonical order, not the order in which they ran.` from the caption -> suite GREEN. (M-I) delete the whole `— on a ride with several remediation rounds ... runs higher than this figure alone` clause -> suite GREEN. Both remediations can be deleted by a later editor with no signal, restoring the exact misreadings round 1 found (Planning always rendered last reads as a chronology; a 45% share read as total rework when the true figure is 74%). Smallest fix: two more `caption.includes(...)` lines beside the six at tests/skills/test-aai-factory-report.sh:500-505." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 881,
          issue: "R2-NB-4 (carried, reduced from round 1's BLOCKING) — the caption's own sentence `Agent time (summed) is the total of each run's own duration` is still unqualified. The qualifier now exists but lives in a different section (Data honesty notes), carries no pointer from the Agent-time column, and names a RUN count, so it cannot tell a reader WHICH scopes are partial. The Tokens column still carries a per-row denominator while Agent time does not — the asymmetry round 1 named is now declared page-globally rather than removed.",
          failure_scenario: "Live on 4 of 124 rows (subagent-protocol-slim, friction-capture-default-on, dev-progress-hub, ci-test-impact-selection). A reader who compares ci-test-impact-selection's `47m` against a fully-timed ride reads a figure ~25% short and the caption tells them it is a complete total. NOT a re-block: round 1's own prescribed smallest fix was the note, and the note shipped. Smallest remaining fix is one clause — `...is the total of each run's own duration, over the runs that record one (see the data honesty notes)`. A per-scope `runs_timed`/`runs_total` denominator mirroring the Tokens cell would close it properly but changes the model shape after freeze, so it belongs in a follow-up." }
  cannot_verify:
    - { claim: "The eight new arms fail on the pre-change tree (failing-first discipline, strategy `direct`).",
        closes_with: "Exit codes recorded in the Implementation return record; the reviewer is read-only on implementation files in the real tree and cannot revert the generator to observe them." }
    - { claim: "TEST-038's sibling suites (test-aai-metrics.sh, test-aai-overview.sh, test-aai-close-work-item.sh) still exit 0.",
        closes_with: "Executed by Validation round 4; not re-run here per dispatch (the whole test-aai-factory-report.sh suite WAS re-run this round, exit 0, zero FAIL lines)." }
    - { claim: "The new TEST-039 awk/grep frontmatter extraction behaves identically on CI (Ubuntu/GNU).",
        closes_with: "A CI run of the skill suite. The constructs used are POSIX (`awk '/^---$/{n++; next} n==1'`, `grep -qE` with `[[:space:]]`), but the LEARNED BSD/GNU rule says local green is not Linux green. Verified on macOS/BSD only." }
    - { claim: "The committed docs/ai/factory-report.{html,json} will carry the new section.",
        closes_with: "Unmodified in this diff by design — close-work-item.mjs regenerates them into a separate chore(autogen) commit (git log 6f6a6df/cb89bb5). Confirm that commit lands." }
  overall: pass
```

## Scope, spec, and preflight

Working-tree diff, explicit path list. `docs/ai/STATE.yaml` `worktree.user_decision` is `inline`, but its `inline_review_scope` (:378-379) still holds the **ci-test-impact-selection** path list from an earlier ride — stale. The dispatch supplied this scope's paths and the spec's own `Inline review scope` line agrees with them, so the scope is unambiguous; recorded as an INFO for the orchestrator, not a finding.

Seven files carry this ride's substance (generator, suite, product doc, spec, intake, CHANGELOG, decisions.jsonl). Five more are modified — `docs/INDEX.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/overview.html`, `docs/ai/overview-data.json`, `docs/ai/decisions.jsonl` — and all five were inspected: the Drafts row for the intake, this ride's own `doc_lifecycle`/`ac_status`/`validation_verdict` events, the in-flight focus flip, and the `fu-scope-cost-no-live-view` follow-up. Expected companions.

No coaching attempt. The dispatch stated the remediation's claims explicitly as *claims to verify rather than accept*, named the two facts it wanted checked, and invited me to overturn its own stale-validation call. That is the opposite of pre-rating. Recorded as clean.

## The disclosed accidental regeneration — CONFIRMED CLEAN

`git status --porcelain` reports no entry for `docs/ai/factory-report.html` or `docs/ai/factory-report-data.json`, and `git diff HEAD -- <both>` is empty, so worktree == index == HEAD byte-for-byte: the `git show HEAD: | cp` restore was exact, not approximate. The only untracked files in the tree are the three expected in-flight docs (round-1 review, intake DRAFT, spec DRAFT) — no `.orig`, no stray backups left behind. `tests/fixtures/factory-report/` goldens are likewise untouched.

Method note for the record: I did all mutation work in an `rsync`ed scratch copy of `.aai/`, `tests/` and `docs/` under the session scratchpad, never in the real tree. That is the cheap way to avoid the same accident — `PROJECT_ROOT` in this suite is derived from the script's own location, so a copied tree is a fully working harness.

## What I re-verified, and how

Nine mutations, each applied to the scratch copy, run, and reverted. Every claim in the dispatch was tested rather than read.

| # | Mutation | Expected | Result |
|---|---|---|---|
| M-A | disable the BLOCKING-1 `scopeCostNotes.push` | TEST-031 red | **killed** — `FAIL:missing partial-agent-time note (BLOCKING-1)` |
| M-B | drop `&& r.tokens` (D7 zero-denominator guard) | TEST-037 red | **killed** — `P-ZERO-TOK: Remediation-share cell "NaN%" != expected "n/a"` |
| M-C | delete ONLY the frontmatter `- ride-cost-readout` line | TEST-039 red | **killed** — `frontmatter delivered_by must include ride-cost-readout` |
| M-D | revert the NB-4 roles fallback to `''` | TEST-037 red | **killed** — `P-ZERO-RUNS: Roles cell "" != expected "no runs recorded"` |
| M-E | `updated: soon` | TEST-039 red | **killed** — `updated must be a well-formed ISO date` |
| M-G | `updated: 2027-01-05` (legitimate future bump) | still green | **green** — NB-3 regression trap genuinely removed |
| M-F | reset `runsMissingDuration` per ride | ? | **SURVIVED** — R2-NB-1 |
| M-H | delete the NB-6 canonical-order caption clause | ? | **SURVIVED** — R2-NB-3 |
| M-I | delete the NB-1 cumulative-exclusion caption clause | ? | **SURVIVED** — R2-NB-3 |

Plus: full `tests/skills/test-aai-factory-report.sh` exit 0, zero FAIL lines; `test_026_role_consumption_backcompat` green on its own (closing round 1's Spec-AC-08 cannot-verify); a real-ledger generator run exit 0 emitting exactly two `(scope_cost)` notes — `NOTE 4 agent_run(s) carry no duration_seconds` and `NOTE 23 scope(s) have Agent time (summed) exceeding Elapsed (wall clock)` — both of which I re-derived independently from `docs/ai/METRICS.jsonl` (4 missing runs across 4 rides; 23 overlapping rides), matching.

Two claims I checked and *withdrew* before writing them down: `delivered_by: - ride-cost-readout` is a slug, not a CHANGE id, which looked like a pin that would break when the number is allocated — but slug entries are established convention here (`deslop-scope-and-unrequested-engine`, `live-status-dashboard`, `doctor-honesty-batch`) and `close-work-item.mjs:460` appends the ride's `ref` deduped, so the append is a no-op and TEST-039 stays green. And the `m.empty` render path returns at :724 before `scopeCostRows` at :767, so an empty ledger cannot reach the new code — TEST-036's `--data-only` runs on three of its five shapes are a real hole in principle, but not one this change opens.

## The one thing the remediation shipped that nothing can prove — R2-NB-1

Round 1 blocked because a partial sum shipped without a denominator. The fix is a note, and the note is correct today. But the *arm that proves it* only proves the note exists.

Look at the two note families side by side in the shadow model:

- the disagreement notes and the overlap count are re-derived from the raw ledger and diffed exactly (`tests/skills/test-aai-factory-report.sh:248-261`) — a wrong count is caught on the real corpus;
- the missing-duration count is not re-derived at all, and the only fixture that exercises it contains exactly one missing-duration run, so `1` is what a correct implementation prints *and* what a per-ride-reset implementation prints.

That is the same asymmetry round 1 blocked on, one level up: two adjacent honesty numbers built on opposite verification principles. It is non-blocking because the shipped number is right and the blast radius is a wrong integer in a note, and because round 1 ranked the structurally identical NB-2 and NB-5 non-blocking. But it is the first thing I would fix, it is four lines, and it sits six lines below code that already does exactly this for a sibling note.

## R2-NB-2 — the sort comparator broke degrade-and-report

`rides = metrics.filter((m) => m && m.ref_id)` at :229 is a truthy filter; every pre-existing consumer treats `ref_id` as an opaque Map key or feeds it through `esc()`, which is `String(s ?? '')`-safe. The new comparator is the first code in the file to call a String method on it directly, and it does so twice (:523 null-null branch, :527 tie-break). A ledger with a non-string truthy `ref_id` therefore takes the generator from exit 0 to an uncaught TypeError.

I confirmed this is a regression and not pre-existing: the same 13-line fixture renders fine under the committed HEAD generator and dies under the working-tree one. The trigger has never occurred in 124 machine-written rides, so I am not blocking on it — but this is a vendored `.aai` script that runs against downstream ledgers, Constitution Article 4 is the governing rule, and the fix is two `String(...)` wrappers.

## R2-NB-3 — two remediations that a later editor can delete for free

NB-6 was answered with a caption clause instead of a reorder, and I agree with that call: frozen Spec-AC-02 mandates `CANONICAL_ROLES` order, TEST-032 hardcodes it, and disclosing a fixed order is the honest move that does not touch a frozen AC. NB-1 was answered with a caption clause plus a product-doc Limits bullet, and the bullet is the better half of that pair.

The problem is that both caption clauses are invisible to the suite. TEST-037 pins six caption substrings by design — "pinned as substrings that do NOT overlap the `<th>` label text, so they cannot be satisfied by the headings surviving while the caption prose is gutted" — and then the two newest clauses were added below that list without joining it. M-H and M-I delete them with the suite green. Two lines beside the existing six closes it.

## Did the remediation answer the round-1 findings honestly?

Yes, including where it said no.

- **BLOCKING-1** — fixed as prescribed, mutation-witnessed, with a new fixture ride. The one gap is R2-NB-1 above.
- **NB-6 rejected, with a reason I checked and accept.** The rejection is right on the merits and the substitute (disclosure) is the correct smaller move.
- **NB-8 not fixed, filed as `fu-scope-cost-no-live-view` (P3) and stated plainly in the product doc's Limits**: "never to decide whether to stop one that is still running". That is the honest disposition — the capability the intake leads with is structurally out of reach for this data source, and the change now says so where a reader will find it instead of leaving the reader to discover it.
- **NB-1's product-doc half** goes further than the caption: "The remediation share is a lower bound on rework ... true rework can run well above the rendered share." That is the sentence I wanted.
- **NB-7** shipped as a nine-line directive comment naming the one legitimate reason to edit the shadow. It is the right shape: it names the repair reflex, not just the rule.

No claim in the dispatch was overstated except one, addressed next.

## The stale-validation call — judged

The orchestrator's reasoning was: the delta is one note plus one empty-cell fallback, both mutation-witnessed, and TEST-031's shadow re-derives every field from the real ledger on every run.

Two of those three are exactly true, and I re-ran the mutations myself rather than take them on faith. The third is overstated in a way that matters: the shadow re-derives every **field**, and the remediation's headline deliverable is a **note**. Notes are covered by the shadow only for the two families someone thought to add there, and the new one was not added. R2-NB-1 sits precisely in that gap — a fresh adversarial round with a mutation battery is the thing most likely to have found it, because that is how rounds 3 and 4 found their findings on this same ride.

So: I am not asking for a re-validation now, because this round executed the delta mutations, re-ran the suite including the byte-stability pin, and re-derived the real-ledger numbers independently — the coverage a validation round would have supplied has been supplied. But the *reasoning* that skipped it had a hole in it, and the hole is the finding. If a future dispatch reuses "the shadow re-derives everything" to skip a round, that sentence should read "every field the shadow enumerates".

## Does this earn its place

Yes, and more clearly than in round 1. Four hand-reads of `METRICS.jsonl` in two days is a real mechanizable cost; the data is already committed; the fold is genuinely one extra accumulator in a loop that already walks it; `per_ride` is still projected to three fields at :660, so the six new accumulator fields do not leak into the pre-existing block. D8 (ship the token share, not the duration share) remains the single best decision in the spec. The honesty posture is now consistent across five surfaces — null over zero, named lines over blank cells, denominators in-cell, computed counts over prose, and a Limits section that says what the section cannot do.

What it is not, and now says it is not, is a live view.

## INFO (never gates)

- `.aai/scripts/generate-factory-report.mjs:760-762` — the pre-existing `remRows` "Deterministic order / `Number('n/a')` is NaN" comment is still stranded above the `scopeCostRows` block it does not describe. Round 1's INFO, unaddressed. Move it back down.
- `docs/ai/STATE.yaml:378-379` — `worktree.inline_review_scope` still holds the ci-test-impact-selection path list. Orchestrator hygiene.
- `feedback-triage-offline` renders `0s` Agent time over 4 runs because all four record `duration_seconds: 0`. A measured zero, honest under the n/a-vs-zero rule, but it sits one column from an `n/a` and reads oddly. Not a finding; noted in case the capture path is worth a look.
- The rendered caption is now a single ~700-character paragraph carrying five distinct rules. It is all true and all load-bearing, but it is at the edge of what a skimmer will read.

## Warning dispositions (SPEC-0013 H6)

Recommended, for the ORCHESTRATOR to record — the reviewer files nothing:

- **R2-NB-1** (missing-duration note count unpinned) — **remediate in-tree**. Four lines in a file this scope already owns, symmetric with code six lines above. This is the one I would not close the ride without.
- **R2-NB-3** (two caption clauses unpinned) — **remediate in-tree**. Two lines beside six that already exist.
- **R2-NB-2** (non-string `ref_id` crash) — **remediate in-tree** (two `String(...)` wrappers) or **promote to a typed follow-up** (`fu-`, P3) if the owner wants the diff frozen; zero live exposure either way.
- **R2-NB-4** (caption sentence still unqualified) — **remediate in-tree** for the one-clause version, or **promote to a typed follow-up** (`fu-`, P3) for the proper per-scope `runs_timed` denominator, which changes the model shape after freeze and should not be smuggled in.

## Next steps

1. Record the four dispositions above (H6 requires the artifact named per WARNING in STATE `code_review.notes`).
2. Optionally sweep R2-NB-1 and R2-NB-3 in-tree — together they are six lines in `tests/skills/test-aai-factory-report.sh` and need no generator change, so a suite re-run is the only re-evidence required and no AC status moves.
3. PR ceremony. Confirm the `chore(autogen)` regeneration commit lands carrying `<section id="scope-cost">` into the committed report artifacts.

Nine ACs compliant, the round-1 BLOCKING closed and witnessed, eight of nine mutations behaving as claimed, goldens untouched, the tree provably clean of the disclosed accident, and a product doc that states the two things this section cannot do. **Ready, conditional on the four dispositions being recorded.**

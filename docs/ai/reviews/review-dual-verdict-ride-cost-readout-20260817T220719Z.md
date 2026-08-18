# Code Review — ride-cost-readout (dual verdict, adversarial)

```yaml
review:
  scope: "working tree (uncommitted): .aai/scripts/generate-factory-report.mjs, tests/skills/test-aai-factory-report.sh, docs/product/factory-performance-report.md, docs/issues/CHANGE-0148-ride-cost-readout.md, docs/specs/SPEC-0134-spec-ride-cost-readout.md, CHANGELOG.md"
  spec: docs/specs/SPEC-0134-spec-ride-cost-readout.md (FROZEN)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:396-401,505-518; TEST-031 fixture + real-ledger + shadow arms (tests/skills/test-aai-factory-report.sh:1073-1265). Elapsed/agent/null-guard/D10 sort/divergence note all present; overlap count verified independently = 23 of 124." }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:402-405; TEST-032. roles built from normalizeRole + CANONICAL_ROLES.concat(['Other']), only roles that ran, sums to runs_total. See NB-6 on the ORDER this yields." }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:353 (single extractUsageTotal call site, reused), :35-37 (single import); TEST-033 asserts grep -c 'usage_total_tokens=(' == 0 and import count == 1." }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:760-762; TEST-034 pins all three coverage shapes in the rendered cell. runs_marked>0 implies tokens_total!==null by construction (both keyed on t!==null at :355/:382)." }
      - { ac: Spec-AC-05, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:391-394,428,485-495; TEST-035 + TEST-031 shadow note-set diff (both directions: missing note AND note-fired-on-agreement)." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-036 (five ledger shapes exit 0, process.exit([1-9]) grep == 0, no $-digit in either output). Confirmed independently: node .aai/scripts/generate-factory-report.mjs over the real repo exits 0." }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:866-870; TEST-037 pins 7 <th> by position, 6 caption clauses, cell-by-cell parity against the same run's JSON, and exact <tr> cardinality. Strongest arm in the set." }
      - { ac: Spec-AC-08, call: cannot-verify,
          citation: "TEST-026 extended in place (tests/skills/test-aai-factory-report.sh:873-919); goldens confirmed untouched by git status. The byte-identity itself was executed by Validation round 4, not re-run here per dispatch." }
      - { ac: Spec-AC-09, call: compliant,
          citation: "docs/product/factory-performance-report.md:10,12,108-131; TEST-039. Every greppable pin present. See NB-2/NB-3 on how weakly two of those pins are asserted." }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 348,
          issue: "Agent time (summed) is a silently partial sum. A run without duration_seconds is dropped from busy with no denominator, no n/a, and no note — while the adjacent Tokens column mandates runs_marked/runs_total for exactly this failure mode (D4). The spec's own Edge cases promised the mitigation ('notes names the count') and it was not implemented.",
          failure_scenario: "Live today on 4 of 124 rides. ci-test-impact-selection renders 47m agent time over 4 runs with 1 run uncounted; if that run were average the true figure is ~25% higher — the same order of error D1 exists to prevent. Also makes the rendered caption's 'Agent time (summed) is the total of each run's own duration' false for those rows." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 868,
          issue: "NB-1 — the caption discloses the rework exclusion per-remediation-run ('the round whose finding it addressed is not included') and never its cumulative size, which is where the number actually misleads.",
          failure_scenario: "deslop-scope-and-unrequested-engine renders Remediation share 45%. Remediation + the repeat Validation/Code Review rounds is 74% of measured tokens. A reader calibrating scope size off 45% is 29 points low on the ride the intake itself cites." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 567,
          issue: "NB-2 — grep -qF 'ride-cost-readout' over the whole product doc claims to assert frontmatter delivered_by, but the doc's Links section (lines 153-154) contains the same substring. The assertion cannot fail on what its message names.",
          failure_scenario: "Delete line 10 (`- ride-cost-readout` under delivered_by) from docs/product/factory-performance-report.md: TEST-039 stays green and still prints 'delivered_by + updated' in its pass line. Round-4's own thesis — an arm that cannot fail on what it asserts — one test over again." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 568,
          issue: "NB-3 — the literal date pin `grep -qF 'updated: 2026-08-17'` turns any future legitimate edit of this product doc into a failure of an unrelated scope's test.",
          failure_scenario: "The next change touching factory-performance-report.md bumps `updated:` (as this scope's own Spec-AC-09 requires it to) and TEST-039 goes red for a scope that never touched scope_cost." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 759,
          issue: "NB-4 — a zero-run ride renders an EMPTY Roles cell. Every other unmeasurable value in this section is a named line or n/a (D5, Article 4); this one is a blank td.",
          failure_scenario: "Live today: the ISSUE-0004 and ISSUE-0005 rows of the real report render `<td></td>`. A blank cell reads as a rendering bug, not as 'no runs recorded'." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 441,
          issue: "NB-5 — the D7 zero-denominator guard is untested, and round 4 recorded it as structurally unclosable. It is not: the mutant is invisible in JSON but visible in HTML.",
          failure_scenario: "Drop `&& r.tokens` from generate-factory-report.mjs:490. A ride whose only markers are `usage_total_tokens=0` yields 0/0 = NaN; JSON.stringify(NaN) is 'null' so every JSON arm passes, but renderHtml holds the in-memory NaN and emits `NaN%`. TEST-037 compares cells against the JSON-parsed expectation ('n/a') and would catch it — it just has no zero-token fixture row." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 403,
          issue: "NB-6 — the Roles cell is comma-joined in CANONICAL_ROLES order, which lib/usage-note.mjs:131 sorts by DESCENDING STRING LENGTH as a longest-prefix matching priority. It is not a semantic order, but inline as `A 1, B 2, C 8` it reads as a sequence.",
          failure_scenario: "Live: `Implementation 1, Code Review 2, Remediation 8, Validation 6, Planning 1`. Planning — the first role of every ride — is rendered last on every row, forever, because 'Planning' is the shortest canonical name. A skimming reader reads a chronology that does not exist." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-factory-report.sh, line: 161,
          issue: "NB-7 — the shadow model is ~55 lines of the generator's fold restated. It earns its place, but nothing in it says which side to change when it fails, and the cheap fix on a red is to edit the shadow.",
          failure_scenario: "A future scope legitimately changes the elapsed rule. TEST-031 fails with a shadow mismatch; the mechanical repair is to paste the new rule into the shadow, which converts the arm into a tautology and silently retires the guard that closed six findings." }
      - { rank: NON-BLOCKING, file: docs/product/factory-performance-report.md, line: 131,
          issue: "NB-8 — the intake's headline motivation is not served and the limitation is not written down anywhere.",
          failure_scenario: "The intake says 'Seen while the ride was running, the decision to stop would have come earlier — the owner asked for exactly that twice.' agent_runs reach METRICS.jsonl only at metrics-flush, and the report regenerates at close-work-item; an in-flight ride has no row. The owner who reads the product doc will expect a capability that does not exist." }
  cannot_verify:
    - { claim: "Spec-AC-08 byte-identity of the two goldens after excision.",
        closes_with: "Validation round 4 (docs/ai/validation/validation-20260817T214700Z-ride-cost-readout-round4.md) executed it; not re-run here per dispatch. Golden files confirmed unmodified in git status." }
    - { claim: "The eight new arms fail on the pre-change tree (failing-first discipline).",
        closes_with: "Exit codes recorded in the Implementation return record; the reviewer context is read-only and cannot revert the generator to observe them." }
    - { claim: "Sibling suites (metrics, overview, close-work-item) still exit 0.",
        closes_with: "TEST-038 regression row, executed by Validation. Not re-run here." }
    - { claim: "The committed docs/ai/factory-report.{html,json} will carry the new section.",
        closes_with: "They are unmodified in this diff by design — close-work-item.mjs regenerates them into a separate chore(autogen) commit (established practice, git log 6f6a6df/cb89bb5). Confirm that commit lands." }
  overall: fail
```

## Scope and spec

Working-tree diff, explicit path list (STATE `worktree.user_decision` is
`undecided`; the dispatch supplied the paths, which is an accepted scope form).
Four unrelated-looking working-tree files — `docs/INDEX.md`,
`docs/ai/EVENTS.jsonl`, `docs/ai/overview-data.json`, `docs/ai/overview.html` —
were inspected and are this ride's own telemetry and regenerated indexes
(`doc_lifecycle`/`ac_status`/`validation_verdict` events for
`spec-ride-cost-readout`, and the Drafts row for the intake). Expected
companions, not scope pollution.

No coaching attempt in the dispatch: the orchestrator named its open questions
without pre-rating severity or excluding areas, and explicitly invited rejection
of round 4's notes. Recorded as clean.

## Does this earn its place

Yes, on the trend/comparison use. Four hand-reads of `METRICS.jsonl` in two days
is a real, recurring, mechanizable cost, the data is already committed, and the
fold is genuinely one extra accumulator inside a loop that already walks it. D9
is the right call — a `lib/scope-cost.mjs` with one consumer would have bought a
PROFILES obligation for no reuse. D8 (ship the token share only, not the
duration share) is the single best decision in the spec: two rework percentages
disagreeing by 2x would have manufactured exactly the confusion D1 exists to
prevent.

Where it does not earn its place is the use the intake leads with — deciding to
stop a ride *while it runs*. That is structurally out of reach here and always
will be, because the rows come from a ledger the ride only writes at flush. The
change is honest about not gating; it is silent about not being live. NB-8.

## The blocking finding

The section ships two adjacent columns built on opposite principles.

`Tokens` carries `runs_marked/runs_total` in the same cell because — D4, and I
agree with every word of it — "Showing a bare partial would understate
silently. The denominator is the whole answer: it is not optional decoration."

`Agent time (summed)` is built by the same kind of partial fold
(`generate-factory-report.mjs:348` accumulates `busy` only
`if (typeof r.duration_seconds === 'number')`) and ships with no denominator, no
`n/a`, and no note. The spec saw this — Implementation plan, Edge cases: "A run
missing `duration_seconds` (4 of 541 today): excluded from `agent_seconds`,
which is then a partial sum; `notes` names the count." No such note exists;
`notes.push` appears eight times in the file (:526-533, :619) and none of them
counts it.

Measured on the live ledger, 4 runs of 541 across 4 rides:

| ref | runs | runs missing duration_seconds | rendered agent_seconds |
|---|---|---|---|
| subagent-protocol-slim | 5 | 1 | 1739 |
| friction-capture-default-on | 5 | 1 | 1713 |
| dev-progress-hub | 4 | 1 | 1292 |
| ci-test-impact-selection | 4 | 1 | 2849 |

One uncounted run in four is not a rounding error; if it were an average run the
figure is ~25% short — the same magnitude D1 cites as the reason not to label
agent time "duration". It also makes the rendered caption false on those rows:
"Agent time (summed) is the total of each run's own duration" is not what those
four cells contain.

Constitution Article 4 (degrade and report, never silently) is the governing
rule, and this is a report whose entire thesis is that unmeasured quantities say
so by name.

Smallest fix — three lines, no AC change, no golden churn (tag it `(scope_cost)`
and TEST-026's existing filter absorbs it; TEST-031's shadow filters notes by
the two specific patterns and is unaffected):

```js
// in the run loop, beside busy/hasBusy:
if (typeof r.duration_seconds !== 'number') runsMissingDuration += 1;
// beside the other scopeCostNotes pushes:
if (runsMissingDuration) scopeCostNotes.push(`NOTE ${runsMissingDuration} agent_run(s) carry no duration_seconds — Agent time (summed) is a partial sum on those scopes (scope_cost)`);
```

A per-scope denominator would be better still, but the note is what the frozen
spec promised and it closes the silence. Either resolve it this way or amend the
frozen spec's Edge case with a recorded decision — but do not ship the gap
undeclared.

## On round 4's three open notes

- **Shared vocabulary.** Correct, and correctly non-blocking. The shadow proves
  attribution given the vocabulary; TEST-033's grep contract and the metrics
  suite's own TEST-003 guard the vocabulary. Two arms, two properties, no gap.
  My concern with the shadow is different and is NB-7: nothing tells the next
  maintainer which side of a mismatch to repair.
- **Zero-denominator "structurally unclosable".** Rejected. It is unclosable
  *through the JSON*, because `JSON.stringify(NaN)` is `'null'` — but round 4
  stopped one step short: `renderHtml` receives the in-memory model, so the
  mutant emits `NaN%` into the HTML, and TEST-037 compares each cell against the
  JSON-parsed expectation (`'n/a'`). One fixture row with
  `usage_total_tokens=0` in TEST-037 closes it. NB-5.
- **Duplicate `ref_id`.** Agreed, non-issue. Verified: 124 rides, 124 distinct
  refs; the spec's Edge cases declare the shape absent and the sort keeps it
  deterministic if it ever appears.

## Answers to the dispatch's questions

**Is a committed HTML artifact the right home?** For the after-the-fact
comparison, yes — it is already regenerated at every close, already the place
the owner looks, and Article 3 is satisfied. Two costs worth accepting
knowingly: the file grows 37.9 KB -> 61.6 KB on the first regeneration (+62%),
and the 124-row `<tbody>` is emitted as one ~23 KB line (consistent with every
other table in the file, so I am not raising it as a finding — but a
`.join('\n')` is free, invisible to the goldens because the section is excised,
and makes the artifact's diffs readable for the next several hundred rides).

**Can the labels mislead a skimmer?** The two time labels themselves are the
most careful thing in this change and I could not break them. Three softer
spots: the Roles cell reads as a chronology it is not (NB-6), the blank Roles
cell on zero-run rides (NB-4), and the absence of any date column — the table
sorts by elapsed, so a July ride sits beside an August one with nothing to say
which era's capture coverage produced it. `date_utc` is already in the model;
the HTML just does not render it. Not a finding, but it is the cheapest
comprehension win available.

**Is "remediation runs" an honest proxy for rework?** The 18-of-32 fact is not
the problem — remediation driven by a review or bot finding is still rework, and
naming the figure for what it measures is the right call. The problem is the
other direction, and it is bigger than the spec's R2 admits. Measured:

| ref | Remediation share (rendered) | + repeat Validation/Code Review rounds | true rework |
|---|---|---|---|
| deslop-scope-and-unrequested-engine | 45% | 29% | 74% |
| role-verification-guards | 35% | 32% | 67% |

The caption's per-run phrasing ("the round whose finding it addressed is not
included") is defensible as written, so I am not calling it false — but on a
five-round ride it excludes five rounds, and the reader has no way to see that
from a 45%. NB-1: one clause naming the cumulative direction, in the caption and
in the product doc's Limits.

**Will the shadow model rot?** Slower than the alternative. Three rounds of
"add one more fixture row" each rescued exactly one column and each missed the
next; the shadow is the first arm whose coverage grows with the corpus instead
of with the author's imagination, and it is explicitly written to stay stable
under ledger growth. The rot risk is not staleness, it is the repair reflex —
NB-7 asks for one directive line, not a redesign.

**Is any sentence now false?** One, and it is the blocking one: the caption's
"Agent time (summed) is the total of each run's own duration", on four live
rows. Everything else checked out. I independently re-derived the numeric claims
in the CHANGELOG and spec against the ledger — 23 of 124 overlap rides, 18 of 32
remediation rides with `validation_fails: 0`, 124 distinct refs, 4 of 541 runs
without `duration_seconds` — all exact. The spec's Verification line says
"elapsed 25.0h"; `fmtDur` renders `25h`. Numerically identical, cosmetically
different; INFO only.

## INFO (never gates)

- `generate-factory-report.mjs:750-756` — the pre-existing "Deterministic
  order / `Number('n/a')` is NaN" comment for `remRows` is now separated from
  `remRows` by the whole `scopeCostRows` block. Move it back down.
- The D6 disagreement note is emitted per-ride into the global `notes` list;
  every sibling note is an aggregate count. Zero fire on today's ledger (98 of
  98 agree), so this is latent only.
- `no usage marker (0/0 runs)` on the two zero-run rides is literal and honest
  but reads oddly; NB-4's fix would naturally cover it.

## Warning dispositions (SPEC-0013 H6)

Recommended, for the ORCHESTRATOR to record — the reviewer files nothing:

- NB-1, NB-2, NB-4, NB-5 — **remediate in-tree** alongside the BLOCKING fix.
  All four are one to three lines and three of them are in files this scope
  already touches.
- NB-3, NB-6, NB-7 — **remediate in-tree** (a date-range grep, a caption clause,
  a comment line) or **promote to a typed follow-up** if the owner wants this
  scope closed now. My preference is in-tree; none exceeds two lines.
- NB-8 — **promote to a typed follow-up** (`fu-`, P3): it is a product-doc
  Limits line plus, if ever wanted, a genuinely separate capability.

## Next steps

1. Fix BLOCKING-1 (the `duration_seconds` partial-sum note).
2. Fix NB-2 and NB-5 — both are arms that cannot currently fail on what they
   claim, which is the exact defect class this scope has already paid for three
   times.
3. Sweep NB-1, NB-3, NB-4, NB-6, NB-7; decide NB-8.
4. Re-run `tests/skills/test-aai-factory-report.sh` and re-review. The re-review
   is the same single pass, not a delta.

Everything else here is ready. Nine ACs, eight new arms, a shadow model that
does what four rounds of fixtures could not, goldens untouched, exit 0 on five
ledger shapes, and numbers that survived independent re-derivation. The gate is
one three-line omission the spec itself had already written down.

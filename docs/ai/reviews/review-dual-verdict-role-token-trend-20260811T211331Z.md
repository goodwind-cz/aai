# Code Review — CHANGE-0130 / spec-role-token-trend (dual verdict)

```yaml
review:
  scope: git diff main...HEAD (feat/role-token-trend, 789698a..c68a9ae, 12 files)
  spec: docs/specs/SPEC-0117-spec-role-token-trend.md (SPEC-FROZEN, ceremony_level 1)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:340-352 (bucket accumulation) + :461-482 (projection); TEST-022 green in my own suite run" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-023 green, both arms (fixture + REAL docs/ai ledger); identities re-summed independently of the generator in tests/skills/test-aai-factory-report.sh:145-172" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:484-492 (by_week maps over the existing `weeks` array, never recomputed); TEST-024 green" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/generate-factory-report.mjs:595-610 + :703-710; TEST-025 green; visually confirmed on the REAL committed docs/ai/factory-report.html" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-026 green; both goldens contain zero occurrences of role-consumption/role_consumption; D7 provenance independently proven in the validation report" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "my own `bash tests/skills/test-aai-factory-report.sh` exit 0 (28 PASS, 0 FAIL, tree clean); `git diff --name-only main...HEAD` names no PROFILES.yaml / prompt-diet-ledger.sh / test-aai-prompt-diet.sh; the four sibling suites are cited from validation, not re-run here (see cannot_verify 1)" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "docs/product/factory-performance-report.md:5-11 frontmatter (delivered_by +CHANGE-0130, updated 2026-08-11) and :56-79 body pins; TEST-027 green but weaker than the AC (INFO-1)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/product/factory-performance-report.md, line: 79,
          issue: "The product doc promises a denominator the weekly view does not render: \"runs_marked ... sits next to every median and total, in both the JSON and the rendered tables\" (:79-83) and \"runs_marked is always shown alongside so the denominator is never hidden\" (:93-95). The weekly table and the sparklines render median_tokens only — the per-(week,role) runs_marked exists in the JSON but appears nowhere in the HTML weekly view or the bar <title>.",
          failure_scenario: "On the REAL committed report the Implementation row of the weekly table reads 151798 / 215852 / 226054 for W29/W30/W31 and its sparkline draws a clean rising staircase. The underlying runs_marked for those weeks is 2 / 2 / 1. An owner reads a 50% per-run context-growth trend off three single-digit samples, and the doc has told them the denominator is always visible." }
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-factory-report.mjs, line: 601,
          issue: "Six sparklines plotting the SAME quantity (median tokens/run) are stacked vertically, but barSeries computes `max` per series, so each chart has its own private y-scale and no axis labels. Nothing on the page signals that the six charts are not comparable. Measured on the real page: the new section is 43.3% of the rendered document (3180px of 7339px), 2250px of it these charts.",
          failure_scenario: "Code Review's W32 bar (median 148601) renders at full chart height, pixel-identical in appearance to TDD Implementation's W32 bar (median 263386). A reader scrolling the six charts concludes the two roles cost the same per run — a 1.8x error — even though the table three screens above has the correct numbers." }
  cannot_verify:
    - { claim: "test-aai-metrics.sh, test-aai-overview.sh, test-aai-close-work-item.sh and test-aai-layer-profiles.sh exit 0 (Spec-AC-06)",
        closes_with: "re-running the four; deliberately NOT re-run here because test-aai-metrics.sh writes docs/ai/overview*.{json,html} into the real tree (validation NB-1), and a read-only reviewer must not dirty the scope. Validation recorded all four green at c68a9ae." }
    - { claim: "the RED transcripts were produced against the pre-change tree rather than reconstructed after the fact",
        closes_with: "docs/ai/tdd/** is gitignored (.gitignore:35), so nothing anchors the transcripts to a commit. mtimes and content are consistent with genuine pre-change runs (see INFO-2); a generator SHA in the transcript header, or committed RED evidence, would close it outright." }
    - { claim: "the TEST-023 real-ledger arm stays green as docs/ai/METRICS.jsonl grows",
        closes_with: "the identities are ledger-independent by construction, but the arm reads the live ledger; only time or a deliberately mutated-ledger CI run substantiates it." }
    - { claim: "the weekly per-role median is a usable context-growth signal at current sample sizes",
        closes_with: "more marked runs per role-week; R2 accepts this explicitly and the diff cannot substantiate it either way." }
  overall: pass
```

## Scope and method

- Branch `feat/role-token-trend` (verified with `git branch --show-current`); never switched, never pushed, nothing implementation-side written.
- Review surface established as `git diff main...HEAD` per the dispatch: 12 files, +1658/-67.
- Read the frozen spec and the recorded-PASS validation report first; both NB findings recorded there are re-affirmed below rather than re-litigated.
- Independent evidence produced by THIS pass: a full `bash tests/skills/test-aai-factory-report.sh` run (exit 0, 28 PASS, 0 FAIL, `git status --porcelain` unchanged before and after), `spec-lint --strategy hybrid` (0 findings), the governance-path diff check, a byte grep over both goldens, mtime forensics over the TDD evidence, and a browser render of the REAL committed `docs/ai/factory-report.html` with DOM measurements.
- No coaching attempt in the dispatch to record: it named probe areas and a ride-economy budget, it did not characterize expected findings, pre-rate severity, or scope-exclude anything.

## Verdict 1 — spec_compliance: PASS

The AC walk is in the YAML block. Every row is compliant; there are no deviations from the frozen spec to list. Notes on the two rows that needed more than a test citation:

- **Spec-AC-01, role ordering.** `roleConsumptionRoleKeys = CANONICAL_ROLES.slice()` correctly copies before pushing `Other` — without the `slice()` this would mutate the array exported by `lib/usage-note.mjs` and corrupt every later consumer in the same process. The order matches `cost.by_role` as required, with one benign asymmetry the spec does not forbid: `roleSplit` *filters out* roles with neither duration nor tokens, while `role_consumption` keeps all six. That is the stated D5 intent (a missing row and a never-ran row are different facts), and TEST-023's per-role comparison handles the missing-`by_role`-entry case explicitly.
- **Spec-AC-05.** The excision arm handles the trailing blank line, and I confirmed neither golden contains the string `role-consumption` or `role_consumption`. The pin is real.

## Verdict 2 — code_quality: PASS (no BLOCKING; two NON-BLOCKING)

### NON-BLOCKING 1 — the weekly view drops the denominator the docs promise

`docs/product/factory-performance-report.md:79` and `:93`; render side `.aai/scripts/generate-factory-report.mjs:604-606`.

The model is honest — `by_week[].roles[].runs_marked` is there. The HTML is not dishonest either; it renders `n/a` correctly and never imputes. The defect is the gap between them plus prose that closes the gap by assertion:

```
2026-W29 Implementation: n=2  median=151798
2026-W30 Implementation: n=2  median=215852
2026-W31 Implementation: n=1  median=226054
```

Rendered, that is three numbers and a rising bar chart with no `n` in the cell, no `n` in the bar `<title>` (`"2026-W29: 151798 tokens"`), and no `n` anywhere in the weekly table. This is the exact place the sparse-era caveat matters most, and it is the one place `runs_marked` is invisible. The lifetime table above it does show Marked, which is presumably where the prose came from.

Two ways to close it, either acceptable:
1. Narrow the prose to what is true (the per-role table shows `runs_marked`; the weekly denominators live in the JSON), or
2. render the denominator — `151798 (n=2)` in the weekly cell, or append `(n=N)` to the bar title.

**Recommended disposition: remediate-in-tree.** Option 1 is a two-line doc edit already covered by TEST-027's existing greps, and leaving a false honesty claim in a document whose whole subject is honesty semantics is the wrong thing to defer. Option 2 (the render change) is the better product answer and can ride as a follow-up ref if the orchestrator wants to keep this ride L1.

### NON-BLOCKING 2 — six same-quantity sparklines with six private y-scales

`.aai/scripts/generate-factory-report.mjs:601-609`.

`barSeries` was written for the four pre-existing charts, each of which plots a *different* quantity in its own section, so per-series scaling was correct there. Here it is applied six times to the same quantity, stacked, with the role name as the only label. The result reads as a comparison and is not one.

Measured on the real page (DOM, 1282px viewport): each `svg.spark` renders 375px tall; six of them plus two tables make the section 3180px of a 7339px document. The new section is now the largest thing on the report, and the least information-dense part of it — the tables directly above already carry every number the charts encode.

**Recommended disposition: promote-to-follow-up-ref.** `barSeries` is shared with four other charts, so adding a shared-max parameter (or dropping the sparks) has blast radius past this scope, and the spec explicitly mandates the current shape (Spec-AC-04: one spark per marked-run role). Changing it here would be a spec deviation, not a fix.

### INFO (never gating)

- **INFO-1 — TEST-027 is weaker than Spec-AC-07 claims.** `tests/skills/test-aai-factory-report.sh:900-912`. Three gaps: (a) `grep -qi 'n/a'` was *already satisfied by the pre-change doc* (`main:docs/product/factory-performance-report.md:45`, "explicit `n/a` bucket"), so that pin is vacuous and can never go red; (b) `grep -qF 'CHANGE-0130'` is doc-wide and is now satisfied by the new `Links` line alone, so it does not pin the `delivered_by` frontmatter despite the failure message reading "product doc frontmatter delivered_by must include CHANGE-0130"; (c) Spec-AC-07's "`updated` is bumped to the delivery date" is not asserted at all. The doc is in fact correct on all three today — this is test strength, not a defect. Not ranked BLOCKING: the test name (`product_doc_pins`) claims no universal negative, only the internal failure message overstates.
- **INFO-2 — RED evidence filenames are hand-written, not clock-captured.** All six `docs/ai/tdd/red-TEST-02*-20260811T210000Z.log` share the identical round timestamp `21:00:00Z`, which no clock produced for six separate runs. The substance holds and I verified it rather than assuming: actual mtimes are all `2026-08-11T20:41:25Z`, i.e. *before* the GREEN full-suite log (`20:43:41Z`), the mutation pair (`20:43:56Z` / `20:44:02Z`) and the commits (`20:49` UTC); and the contents are genuine pre-change failures (`TypeError: Cannot read properties of undefined (reading 'roles')`). RED-first discipline is intact; only the naming is estimated. Worth correcting as a habit, given the contract's "captured from the system clock, never model estimation" rule.
- **INFO-3 — three parallel accumulators now count the same runs.** `roleConsumption` re-derives what `roleTokens`, `runsWithMarker` and `totalRuns` already accumulate two lines above it (`:328-352`). This is deliberate (additive-first, byte-stability of the existing fields) and is exactly what seam S2 and TEST-023 exist to pin, so drift fails loudly rather than silently. Named only as maintenance surface: a future change to marker semantics must land in both, and TEST-023 is the thing that will tell you.
- **INFO-4 — one unguarded `.find()` in the render.** `:606`, `wk.roles.find((x) => x.role === r.role).median_tokens`. Safe today because both arrays are projected from the same `roleConsumptionRoleKeys`; a future filter applied to the top-level `roles` list but not to `by_week[].roles` would throw a TypeError mid-render. No current input reaches it, so it is not a finding — but `?.median_tokens ?? null` costs two characters.
- **INFO-5 — role order reads arbitrarily.** Both tables order roles by `CANONICAL_ROLES` (length-sorted): TDD Implementation, Implementation, Code Review, Remediation, Validation, Planning. Consistency with `cost.by_role` was the right call (D5) and I would not change it; noting for the owner that the section answering "where do the tokens go" does not lead with the biggest consumer.
- **INFO-6 — one loose CHANGELOG clause.** "All six observed RED pre-change (`cost.role_consumption` undefined)" is precise for TEST-022/023/024/025 and TEST-026's new-key arm, but TEST-027 went red because the product doc lacked the pins, and TEST-026's byte-stability arm was proven by the mutation pair — which the same bullet does disclose two lines earlier. Loose, not false.

### Comment honesty (checked line by line, since the diff is comment-heavy)

Every load-bearing claim in the new comments verified true: "one extra pass over data already in hand inside the SAME loop" (yes, same `for (const r of ...)`); "Marker WINS over sentinel" (yes, `if (t !== null) ... else if (hasUsageSentinel)`); "by_week BORROWS the existing `weeks` array verbatim" (yes, `weeks.map(...)`); "barSeries ... already renders a null point as a grey bar with an n/a title" (yes, `bar-null` class + `n/a` title at `:576-578`). No comment describes behavior the code does not have.

### Truthfulness sweep — docs vs actual behavior

| Claim | Source | Holds? |
|---|---|---|
| `cost.role_consumption` built in the existing loop, no second read/parse | CHANGELOG, code comment | yes |
| the new section is the ONLY element carrying an `id` | CHANGELOG, D6 | yes — one `id` in the whole page |
| `n/a` for every null cell, no dollar figure | CHANGELOG, product doc | yes — TEST-025 asserts the exact `n/a` cell count, and the dollar grep re-runs over both outputs |
| goldens captured pre-change, never regenerated | CHANGELOG, D7 | yes — zero `role_consumption` bytes in either golden; provenance independently reproduced by validation |
| `runs_marked` always shown alongside every median | product doc :79, :93 | **no** — NON-BLOCKING 1 |
| all six tests observed RED pre-change for the same reason | CHANGELOG | partly — INFO-6 |

## Validation's two recorded NB findings

Both stand, neither is this scope's to fix:

1. `test-aai-metrics.sh` dirtying the real tree — pre-existing, file untouched by this scope, and it is why I did not re-run the sibling suites (cannot_verify 1).
2. Spec D5's "seven such variant strings" parenthetical — those seven normalize successfully; the live ledger has zero rejected runs, hence no `Other` row and no `unnormalizedRoleRuns` NOTE. The behavior is right; the frozen spec's prose is imprecise. Not worth reopening a frozen spec at L1.

## Merge fitness

**Fit to merge**, conditional in the H6 sense: both NON-BLOCKING findings need a recorded disposition before closeout (recommendations named above — remediate NB-1 in tree, promote NB-2 to a follow-up ref). The change is additive, the additivity is pinned at the byte level against pre-change goldens, the scope suite is green from a clean tree in my own run, no governance path is touched, and the blast radius of a defect is a wrong number on a report page (the close hook swallows generator failures, pinned by the pre-existing TEST-013).

Two housekeeping items for the orchestrator, not review findings: `docs/ai/EVENTS.jsonl` carries one uncommitted appended telemetry line (never `git restore` it), and the spec is still `status: implementing` with `number: null` pending the close ceremony.

## Timing disclosure

`started_utc` in the result block is the first clock reading I captured in this pass (`21:13:31Z`); the review work preceding that reading was not clock-anchored, so the reported duration covers the report-writing phase only rather than the whole review. Recorded honestly rather than estimated backwards.

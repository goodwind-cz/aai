# Code review — CHANGE-0132 validation cost calibration

```yaml
review:
  scope: git diff main...HEAD (edaf8b4..e60ad8c, branch feat/validation-cost-calibration)
  spec: docs/specs/SPEC-0119-spec-validation-cost-calibration.md (SPEC-FROZEN, ceremony_level 2)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/VALIDATION.prompt.md:102-121 (own awk extraction of the CEREMONY LANE block: prohibition at :112, adversarial-seam probes at :110-111, close-before-CI at :112-114, fail-closed/lane.selected/L2-L3 clauses byte-unchanged); own run tests/skills/test-aai-ceremony-levels.sh EXIT=0 (TEST-015 + TEST-019)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/SUBAGENT_PROTOCOL.md:79-97 (four fields at :88-91, runtime resolution/re-resolution/fail-closed/no-harness-equality at :93-97); own run tests/skills/test-aai-validator-isolation.sh EXIT=0 (TEST-001/TEST-002); own grep over .aai/scripts/*.mjs for harness-name gating of spawn/subagent behavior = 0 hits" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SUBAGENT_PROTOCOL.md:119-152 (tiers 1-4 in order at :123-145, verify-the-granted-model at :147-152); own run test-aai-validator-isolation.sh EXIT=0 (TEST-003/TEST-004); own deletion mutation of the tier-3 token -> EXIT=1 (control is live, see CQ-3 for its diagnostics)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/lib/usage-note.mjs:52-105 (REQUESTED_MODEL_RE :69, ACTUAL_MODEL_RE :72, extractors :79/:87, modelOverrideDropped :98) + .aai/SUBAGENT_PROTOCOL.md:180-193; own node probe battery over the real module (plain/bracketed/prefixed/empty/malformed/equal/differ all as specified); own single-source grep over .aai/scripts = 1 file each. Delivered as specified — see CQ-1 for a grammar wart the AC text does not cover and CQ-2 for an under-asserting pin" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "tests/skills/lib/prompt-diet-ledger.sh:154 (466 B entry) + tests/skills/test-aai-prompt-diet.sh:540 (pin -8021); own recompute: git show main:.aai/VALIDATION.prompt.md | wc -c = 17407, HEAD = 17873, delta 466 MATCH; own run test-aai-prompt-diet.sh EXIT=0; KPI + rollback sentences pinned by TEST-019 (own run, green)" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "docs/product/validation-cost-calibration.md (all required sections non-placeholder); own run tests/skills/test-aai-product-docs.sh EXIT=0 (TEST-014 -> missingProductSections empty + close-work-item gate severity none)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/usage-note.mjs, line: 67,
          issue: "MODEL_ID_GROUP admits a trailing `.` even though `.` is a right-boundary delimiter, so a sentence-final marker captures the period into the model id",
          failure_scenario: "note \"...requested_model=claude-opus-4-8 actual_model=claude-opus-4-8.\" -> extractActualModel returns 'claude-opus-4-8.' and modelOverrideDropped returns TRUE: the one signal this scope exists to produce fires falsely on an override that actually took (verified by direct node probe against the real module)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-token-capture.sh, line: 374,
          issue: "test_013's fifth pin (`grep -qiF 'actual_model'`) is subsumed by the earlier `'actual_model='` pin, so spec TEST-010's third clause (independence claims cite actual_model) is not actually pinned, while log_pass claims it is",
          failure_scenario: "mutation-proved: deleting the whole 'Any claim of validator independence ... MUST cite actual_model' sentence from SUBAGENT_PROTOCOL.md leaves every test_013 pin GREEN" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-validator-isolation.sh, line: 505,
          issue: "the four `pos_*=\"$(echo \"$block\" | grep -n ... | head -1 | cut -d: -f1)\"` assignments run under `set -euo pipefail`, so an ABSENT token aborts the script at the assignment and the `[[ -n ... ]] || log_fail \"tier N token not found\"` diagnostics are unreachable",
          failure_scenario: "mutation-proved: removing the tier-3 `codex exec -m` token yields EXIT=1 with NO 'FAIL:' line — the verdict is right, the diagnosis is gone, and a future maintainer sees a silent abort mid-test (the repo's own learned pipefail trap)" }
      - { rank: NON-BLOCKING, file: tests/skills/suite-map.yaml, line: 653,
          issue: "the new suite's globs are only .aai/SUBAGENT_PROTOCOL.md + .aai/VALIDATION.prompt.md, but its two corpus negative controls sweep ALL of .aai/**/*.md — so the 'standing' control is not selected on the paths where the banned assumption would re-enter",
          failure_scenario: "verified with the real selector: `select-suites.mjs --files-from -` on `.aai/AGENTS.md` or `.aai/IMPLEMENTATION.prompt.md` does NOT emit `SELECTED aai-validator-isolation`. A future ride that writes 'Codex cannot spawn subagents' into IMPLEMENTATION.prompt.md passes CI — the exact mutation (A2) validation had to inject into AGENTS.md to prove the control works" }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 123,
          issue: "tier 1 gates only on `spawn_agent_available` and then claims a fresh context 'by construction'; the declared `fork_turns_supported` field (:91) is never consumed by any tier",
          failure_scenario: "on a backend where fork_turns=\"none\" is not honored (the MultiAgentV1/V2 divergence that is the stated reason the field exists), the orchestrator spawns a context-INHERITING child, reports tier 1, and the ride records full validator independence that never happened. Same hole covers a tier-1 hard spawn failure: no lower tier's precondition matches it (tier 2 needs a model rejection, tier 3 needs spawn_agent_available false/unknown)" }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 136,
          issue: "the replaced 'Headless / CLI runner' bullet carried the only Claude-side concrete recipe (`claude -p --prompt-file .aai/VALIDATION.prompt.md`); the new tier 3 names `codex exec -m <model>` as the sole executable example",
          failure_scenario: "a Claude- or Gemini-hosted downstream project syncing this canon reaches tier 3 with no host recipe ('the host-equivalent headless invocation') and falls to tier 4 in-parent execution — a portability regression in the very file that exists to keep isolation harness-neutral (Article 3)" }
      - { rank: NON-BLOCKING, file: .aai/VALIDATION.prompt.md, line: 112,
          issue: "no tie-break reconciles 'scoped to the DECLARED test scope' with 'Do not run a blanket full-suite re-execution' when an L0/L1 spec's own Test Plan declares a full-suite command (validation NB-1; reviewer's call: fix in tree)",
          failure_scenario: "an L0/L1 spec whose Test Plan row names `.aai/scripts/aai-run-tests.sh` (or a shared-lib touch that select-suites resolves to FULL_RUN) leaves a foreign LLM validator with two directly contradictory instructions and no precedence rule; the cheap resolution is to skip a test the spec explicitly declared" }
      - { rank: NON-BLOCKING, file: .aai/SUBAGENT_PROTOCOL.md, line: 95,
          issue: "'fails closed to the NEXT isolation tier below' uses the house term 'fail-closed' in the opposite direction from its sibling use 14 lines of canon away (CEREMONY LANE: fail-closed -> MORE rigor; here: -> LESS isolation) — validation NB-2",
          failure_scenario: "an orchestrator that has internalized 'fail-closed = escalate ceremony' reads an unknown capability as a reason to escalate, or (worse) applies the isolation reading back to the lane rule and takes the lightweight lane on an unreadable ceremony_level" }
  cannot_verify:
    - { claim: "The pre-registered KPI — validation median tokens/run falls while remediation rate does not rise (RR-1)",
        closes_with: "the SPEC-0117 Role consumption row after ~5 post-merge rides; no in-ride evidence can substantiate it and none is claimed" }
    - { claim: "That a foreign LLM orchestrator actually performs the runtime capability detection rather than declaring tier 1 and running in-parent (RR-2)",
        closes_with: "a deterministic capability-probe script, or METRICS evidence of requested/actual pairs across rides on a non-Claude host" }
    - { claim: "That the documented Codex `spawn_agent(...)` signature, fork_turns semantics and MultiAgentV1/V2 divergence match the live CLI",
        closes_with: "an execution log from a current Codex CLI; the diff carries the owner's source-level report, not an observation" }
    - { claim: "The behavior of the two canon files after downstream sync (both ship to foreign projects with different spec-authoring quality)",
        closes_with: "a downstream ride on a synced project exercising an L0/L1 lane and a non-Claude isolation tier" }
    - { claim: "NB-10's fixture-isolation leak and its widened blast radius",
        closes_with: "taken as recorded ground from the validation report; I deliberately did NOT run test-aai-token-capture.sh so as not to dirty tracked docs/ai/overview* files from a read-only review context" }
  overall: pass
```

## Scope and method

- Scope: `git diff main...HEAD` — 17 files, +1169/-29, commits edaf8b4..e60ad8c.
- Spec: `docs/specs/SPEC-0119-spec-validation-cost-calibration.md` (frozen, L2), read in full.
- Prior evidence read: `docs/ai/validation/validation-20260812T082535Z-CHANGE-0132-validation-cost-calibration.md` (PASS, 10 NB findings).
- Read-only on implementation: no file under `.aai/`, `tests/`, `docs/` (other than this report) was modified. Mutation experiments ran against copies in the session scratchpad. `git status --porcelain` was empty after every suite run.
- Own executions (all from this context): `tests/skills/test-aai-validator-isolation.sh` EXIT=0, `test-aai-ceremony-levels.sh` EXIT=0, `test-aai-prompt-diet.sh` EXIT=0, `test-aai-product-docs.sh` EXIT=0; direct node probes of `lib/usage-note.mjs`; `select-suites.mjs --files-from -` on three path sets; `wc -c` byte recompute; two source mutations (independence-clause deletion, tier-3 token deletion) replayed against scratch copies.
- Not re-run: `test-aai-token-capture.sh` and `test-aai-metrics.sh` (validation recorded EXIT=0 for both; token-capture dirties tracked `docs/ai/overview*` per NB-10, and its two AC-04 claims were re-derived here directly — the extractor battery via node probes and the single-source contract via `grep -rlF ... .aai/scripts` = 1 file each).

### Dispatch framing note (anti-gaming contract)

The dispatch named specific validation findings (NB-1, NB-6, NB-10), described the
validation NB list as "settled ground", and asked for a disposition call on NB-1 and
NB-6. Recorded here as required. The full diff was reviewed independently anyway;
four of the eight findings below (CQ-1, CQ-3, CQ-4, CQ-6) are not in the validation
NB list, and CQ-5 re-ranks NB-3 upward with a concrete failure scenario.

Small correction to the upstream artifact: the validation report's verdict line says
"9 non-blocking findings recorded below" but the section lists ten (NB-1..NB-10).
Cosmetic, no bearing on the verdict.

## Verdict 1 — spec_compliance: PASS

All six Spec-AC rows are compliant with independently executed evidence (table above).
Deviations from the frozen spec: none found. Every TEST-xxx claimed in the Test Plan
exists at the claimed path and is wired into its suite's `main()`; the four suites I
executed are green. Two scope notes, neither a deviation:

- Spec-AC-02's clause "no file under `.aai/` gates subagent behavior on a harness-name
  equality test" is pinned only over `*.md` (`--include='*.md'`, scripts excluded).
  The exclusion is documented honestly in the test header, and I verified the script
  side by hand: no `.aai/scripts/*.mjs` branches on harness name to gate spawn/subagent
  behavior (`routine-emit.mjs` branches to render host CLI invocations only).
- The spec invited a reviewer ruling on whether the new prohibition CONFLICTS with
  `.aai/workflow/WORKFLOW.md`'s ceremony table (L3 file, deliberately not edited).
  **My ruling: no conflict, no L3 escalation.** The table's L0/L1 cells read
  "required — suite run" / "required — suite re-run + targeted probe": they assign the
  obligation, they do not define its breadth, and L1's "targeted probe" already points
  the same direction the canon now makes explicit. The canon additionally *adds*
  adversarial seam probes at L0, which is more rigor than the table's cell, never less.
  Nothing in the table needs editing.

## Verdict 2 — code_quality: PASS (no BLOCKING findings; 8 NON-BLOCKING)

No BLOCKING finding. No new gitignored runtime sidecar. No test name asserts a
universal negative it does not prove — the two corpus controls are honestly named and
scoped ("corpus negative control over `.aai/**/*.md`"), and their live-mutation
behavior was re-proved here.

The eight NON-BLOCKING findings with file:line and failure scenarios are in the YAML
block above. Ranked by value:

**CQ-1 — the trailing-period false positive (usage-note.mjs:67).** The highest-value
finding of this review and the one the 22-case validation battery missed, because
every fixture placed the marker mid-note. The grammar lists `.` as a *right-boundary
delimiter* and simultaneously admits `.` inside the id character class; the greedy id
wins, so a sentence-final marker swallows the period. Both markers ending in a period
stay equal (no false positive); the asymmetric case — the natural one, where a note
ends on `actual_model=<id>.` — reports `modelOverrideDropped() === true` for an
override that took. Verified:

```
"...requested_model=claude-opus-4-8 actual_model=claude-opus-4-8."
  -> requested "claude-opus-4-8", actual "claude-opus-4-8.", dropped=true
"requested_model=claude-sonnet-5- actual_model=claude-sonnet-5"
  -> dropped=true  (trailing hyphen, same root cause)
"requested_model=claude-opus-4-8[1m]. actual_model=claude-opus-4-8[1m]"
  -> correct (the bracketed form is immune — the suffix group ends the id)
```

Suggested in-tree fix (one line + one test case): require the id to END on an
alphanumeric or the bracket suffix, e.g.
`([A-Za-z0-9](?:[A-Za-z0-9._:@/+-]*[A-Za-z0-9])?(?:\[[A-Za-z0-9._-]+\])?)`, and add the
sentence-final pair to TEST-011.

**CQ-4 — the standing control does not stand (suite-map.yaml:653).** The spec's own
words are "a standing corpus negative control (TEST-006) so the assumption cannot
re-enter". With the map rows as written, re-entry through any `.aai/*.md` file other
than the two named ones is invisible to CI selection. Fix is one glob line
(`.aai/**/*.md`); I checked that `tests/skills/test-aai-suite-select.sh` pins its
DROPPED counts against fixtures, not the live map, so the edit is safe.

**CQ-2 / CQ-3 — test hygiene.** Both mutation-proved above; both one-line fixes
(a sharper grep; `|| true` on four assignments).

**CQ-5 / CQ-6 / CQ-8 — canon prose, zero ledger cost.** `.aai/SUBAGENT_PROTOCOL.md`
sits outside TEST-010's `.aai/*.prompt.md` glob and outside its three extras, so these
three edits cost nothing on the diet ledger. Suggested wording:

- CQ-5, tier 1: "…when `spawn_agent_available` is true AND `fork_turns_supported` is
  true. If `fork_turns_supported` is false or unknown, a spawned child may inherit the
  parent context — the model separation still holds, the context separation does not:
  drop to tier 3, or record 'validator inherited parent context' as a residual risk.
  A tier-1 spawn that fails for any reason other than a rejected model falls to tier 3."
- CQ-6, tier 3: keep `codex exec -m <model>` and restore the Claude form alongside —
  "e.g. `claude -p --prompt-file .aai/VALIDATION.prompt.md` or `codex exec -m <model>`
  (or the host-equivalent headless invocation)". TEST-003's ordering pin only requires
  `codex exec -m` to appear before "last resort", so the pin is unaffected.
- CQ-8, capability section: replace "an UNKNOWN capability fails closed to the NEXT
  isolation tier below" with "an UNKNOWN capability is treated as ABSENT — never
  assumed present — so the ride falls through to the next tier and records the
  isolation it actually achieved". Removes the term collision without adding a byte to
  an in-glob file.

**CQ-7 — the NB-1 carve-out: my call is remediate in tree.** The dispatch asked for a
ruling rather than an echo, so: add the sentence. Three reasons the recorded-debt route
is the weaker one here. (a) This is production prompt text read by foreign LLMs on
downstream projects, where Test Plans routinely name whole suites and the spec-authoring
discipline that makes the charitable reading obvious in *this* repo is absent. (b) The
two clauses are not merely under-specified, they are directly contradictory in that
case, with no precedence rule — an LLM will resolve it non-deterministically, and the
cheap resolution skips a test the spec explicitly declared, which is a rigor loss in the
same direction as this scope's already-declared Article 5 deviation. (c) The fix is one
sentence. Suggested wording, sized to fit inside the awk boundaries (SEAM-3):

> A full-suite command DECLARED by the spec's own Test Plan is part of the declared
> scope and still runs; the prohibition targets an UNDECLARED blanket sweep.

Cost: `.aai/VALIDATION.prompt.md` is the only in-glob file, so this needs the standard
diet true-up — bump the 466 B ledger entry by the measured delta (~130 B), re-sum the
TEST-012 pin from -8021 by the same amount, re-run `test-aai-prompt-diet.sh` and confirm
headroom stays inside 0..2048 (it is 1150 today, so there is room).

## Truthfulness of the product doc and CHANGELOG (RR-1 check)

Clean. Neither artifact claims a cost reduction was achieved:

- `CHANGELOG.md` describes only what was installed (lane rule, capability contract,
  marker grammar). No token or percentage claim anywhere in the entry.
- `docs/product/validation-cost-calibration.md` "Limits and non-goals" states outright
  that "the token-savings goal is not measured inside this change — it is a post-merge
  measurement … with a defined rollback", and the second bullet honestly concedes there
  is no mechanical checker for the capability-detection steps (RR-2).
- The "What it does" section correctly scopes the change to the two lightest ceremony
  levels and states that heavier rides are unchanged; the fail-closed default is stated
  in "Interfaces and contracts". The requested/actual marker is described as visibility,
  not as a guarantee.

Two INFO nits: the doc's H1 "Validation stops re-running the whole suite twice" drops the
lane qualifier that every sentence of the body carries (a reader who stops at the title
over-reads the scope); and the Links section's "Validation evidence: docs/ai/reports/"
points at a directory that holds no evidence for this scope — the real report is
`docs/ai/validation/validation-20260812T082535Z-CHANGE-0132-validation-cost-calibration.md`.
The bare-directory form is a pre-existing convention shared with one other product doc,
so this is a suggestion, not a finding.

## INFO (never gates)

- `tests/skills/test-aai-ceremony-levels.sh`: the new `test_019_kpi_pin_survives_rename`
  function is inserted between TEST-018's comment header and `test_018_step10_workflow_pointer`,
  so the TEST-018 banner now sits above the TEST-019 body. Cosmetic ordering only.
- `test-aai-validator-isolation.sh:485` — the harness-equality regex admits `is` as an
  operator (`harness[[:space:]]*(==|===|is)`), so descriptive prose such as "when the
  in-session harness is Claude Code" would fail the suite with no defect present.
- `test-aai-validator-isolation.sh:467` — `grep -qiF 'fail'` is a very loose proxy for
  "fails closed to the next tier"; it would survive a rewrite that says "fail open".
- `test-aai-validator-isolation.sh:470` — the pin greps the exact string
  "not on harness name equality"; a reflow that wraps that phrase across two lines breaks
  the pin with the meaning intact.
- `test-aai-token-capture.sh:362` / `:501` — both section extractions are anchored on
  neighbouring `## ` headings; inserting a section between them silently widens the block.

## Warning dispositions (SPEC-0013 H6) — reviewer's recommendation, orchestrator records

| # | Finding | Recommended disposition |
|---|---|---|
| CQ-1 | usage-note.mjs trailing-punctuation false positive | remediate-in-tree (1-line regex + 1 test case) |
| CQ-2 | test_013 under-asserting independence pin | remediate-in-tree (1 grep) |
| CQ-3 | pipefail swallows tier-token diagnostics | remediate-in-tree (tolerate a no-match grep on the four position assignments) |
| CQ-4 | suite-map globs narrower than the corpus sweep | remediate-in-tree (1 glob line) |
| CQ-5 | `fork_turns_supported` declared, never consumed | remediate-in-tree (zero ledger cost) |
| CQ-6 | Claude-side tier-3 recipe lost | remediate-in-tree (zero ledger cost) |
| CQ-7 | NB-1 declared-full-suite carve-out | remediate-in-tree (needs diet-ledger true-up) |
| CQ-8 | "fail-closed" term collision | remediate-in-tree (zero ledger cost) |

If the orchestrator prefers a smaller in-tree footprint: CQ-1 + CQ-2 + CQ-3 + CQ-4 are the
mechanical set (no prompt bytes, no ledger touch) and should land in this ride; CQ-5, CQ-6
and CQ-8 are free in bytes and near-free in risk; only CQ-7 carries ceremony. Anything not
remediated needs a `decisions.jsonl` entry or a tracked follow-up ref named in
`code_review.notes` before closeout. Validation's NB-6 (unpaired-marker convention) and
NB-7 (repeated markers, first-wins) are, in my judgment, genuine debt rather than in-tree
work: both are documented conventions with no observed instance and no consumer that
misreads them today — a follow-up ref is the right home, and CQ-1's fix should be checked
against them so a future `modelOverrideUnpaired()` lands on a clean grammar.

## Merge fitness

Merge-fit as a cumulative diff. The scope is coherent, the L3 boundary is respected
(`git diff main...HEAD` over `state.mjs`, `WORKFLOW.md`, `CONSTITUTION.md` is empty — I
re-checked), the diet ledger arithmetic reproduces exactly, the new suite is registered in
`suite-map.yaml`, and every AC carries executed evidence. Nothing in the eight findings
changes a shipped behavior for the worse relative to `main`; the worst of them (CQ-1)
degrades a signal that does not exist on `main` at all. Recommendation: land CQ-1..CQ-4 in
this ride, then close.

## Next steps

1. Orchestrator records the disposition per warning (decision id or follow-up ref) in the
   review notes and STATE `code_review.notes`.
2. Remediate the accepted set; re-run `test-aai-token-capture.sh`, `test-aai-metrics.sh`,
   `test-aai-validator-isolation.sh`, `test-aai-suite-select.sh` and, if CQ-7 lands,
   `test-aai-prompt-diet.sh` after the ledger true-up.
3. Re-review is the same single pass; no special casing.

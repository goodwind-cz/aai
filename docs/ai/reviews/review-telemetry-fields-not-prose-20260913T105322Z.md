# Code Review — telemetry-fields-not-prose (dual verdict, ceremony 3)

```yaml
review:
  scope: >-
    working tree of /Users/ales/Projects/aai-fix-telemetry-fields-not-prose
    (branch fix/telemetry-fields-not-prose @ 8a2a6e7f + 28 uncommitted tracked files);
    `git diff` over the 25 STATE-declared review paths plus the spec
  spec: docs/specs/SPEC-0178-spec-telemetry-fields-not-prose.md (FROZEN, 14 Spec-AC, one ## Amendment)
  reviewer: claude-opus-5 (independent of implementer claude-sonnet-5 and of the validator)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,   citation: ".aai/scripts/state.mjs:843-871 | TEST-026 (tests/skills/test-aai-state.sh:2651) green, re-run by me" }
      - { ac: Spec-AC-02, call: compliant,   citation: ".aai/scripts/state.mjs:822,843-844 | TEST-027 (test-aai-state.sh:2671) green" }
      - { ac: Spec-AC-03, call: compliant,   citation: ".aai/scripts/state.mjs:834-837 (refusal BEFORE editBlock) | TEST-028 (test-aai-state.sh:2708) green; my own cmp probe: exit 2, STATE byte-identical; my mutation MX1 reddens it" }
      - { ac: Spec-AC-04, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:466-505 | TEST-135/136 (test-aai-metrics.sh:2305,2346) green — deviation D-1 below (disagreement NOTE) and NON-BLOCKING-B (precedence untested)" }
      - { ac: Spec-AC-05, call: compliant,   citation: ".aai/scripts/lib/pricing.mjs:112-122 + .aai/system/PRICING.yaml:58-64 + metrics-flush.mjs:556-573 | TEST-137 (test-aai-metrics.sh:2389) green; my MX5 and MX7 redden it" }
      - { ac: Spec-AC-06, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:1110-1130 | TEST-138/139 green — literally satisfied, but the DELIVERED gate is wider than the AC and that widening is BLOCKING-1" }
      - { ac: Spec-AC-07, call: compliant,   citation: ".aai/scripts/state.mjs:548-586,642-650 | TEST-029 (test-aai-state.sh:2735) green — but the stamped VALUE is untested, NON-BLOCKING-C" }
      - { ac: Spec-AC-08, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:341-345 (existsSync guard, read-only) | TEST-140 green" }
      - { ac: Spec-AC-09, call: compliant,   citation: ".aai/scripts/metrics-flush.mjs:700-712 + check-committed-scope.mjs:105-125 | TEST-141, TEST-007 green — lifecycle gap is NON-BLOCKING-A" }
      - { ac: Spec-AC-10, call: compliant,   citation: ".aai/scripts/aai-friction.mjs:456 + aai-feedback-triage.mjs:50,58,245 | TEST-113 green, re-run by me" }
      - { ac: Spec-AC-11, call: compliant,   citation: ".aai/scripts/aai-feedback-upsert.mjs:486,529 | TEST-064 green, re-run by me; my MX3 reddens the off-set arm" }
      - { ac: Spec-AC-12, call: compliant,   citation: ".aai/scripts/generate-factory-report.mjs:772-785,1044-1054 + metrics-report.mjs:132-133,147,212-220 | TEST-042, TEST-142 green" }
      - { ac: Spec-AC-13, call: compliant,   citation: ".aai/SUBAGENT_PROTOCOL.md:220-232 + .aai/ROLE_COMMON.md:18-23 + tests/skills/lib/prompt-diet-ledger.sh:199 | TEST-030 green, re-run by me; prompt-diet suite rc=0" }
      - { ac: Spec-AC-14, call: compliant,   citation: "TEST-143 (test-aai-metrics.sh:2648) green on a fixture; the ride's own production flush is in cannot_verify" }
  code_quality:
    verdict: fail
    findings:
      - rank: BLOCKING
        file: .aai/scripts/metrics-flush.mjs
        line: 1122
        issue: >-
          D6 gate source 3 admits a ref on a STALE `validation_verdict: pass` event with no
          corroboration that the pass still stands, so a ref whose CURRENT verdict is `fail`
          (per-ref field AND global block AND the run's own new `verdict: fail`) is flushed,
          written to the append-only ledger as `"verdict": "PASS"`, and archived as
          AAI-VALIDATION-ARCHIVED. The dispatcher only ever stamps `pass` events
          (orchestration-dispatch.mjs:1591-1597), so the spec's "latest wins, never
          any-pass-ever" safeguard is inert in production (21/21 live events are `pass`).
        failure_scenario: >-
          Reproduced with the real scripts (no mutation). Fixture: EVENTS.jsonl holds one
          `validation_verdict pass` for CHANGE-0001 (2026-07-01); STATE says
          last_validation.status fail ref CHANGE-0001, metrics.work_items.CHANGE-0001.validation
          .status fail, and its only Validation run carries verdict: fail. Post-change flush:
          "Flushed: CHANGE-0001", "verdict_basis: CHANGE-0001 -> event", ledger line
          verdict=PASS with reliability {validation_fails:1, first_pass_clean:false, basis:field},
          and last_validation.notes gains "[AAI-VALIDATION-ARCHIVED v1 ref=CHANGE-0001]".
          Same fixture against HEAD (pre-change): "SKIP CHANGE-0001: validation verdict is
          \"fail\" (needs PASS or CANCELLED) — Nothing to flush", STATE byte-unchanged.
      - rank: NON-BLOCKING
        file: .aai/scripts/metrics-flush.mjs
        line: 707
        issue: >-
          `code_review.scope_ref_id` is written ONLY by applyPartialReset and is never
          refreshed or cleared by set-code-review (state.mjs:658-682), reset-block, or
          applyFullReset — so the stamp goes stale the moment a later ride writes its own
          scope, and there is no CLI that can repair it (the field is not in CMD_FLAGS).
        failure_scenario: >-
          Reproduced: real partial flush stamps scope_ref_id CHANGE-0001; the next ride runs
          `set-focus --ref CHANGE-0002` + `set-code-review --scope b.txt`; `check-committed-scope
          --from-state` then returns checked=0 and degrades "scope_ref_id (CHANGE-0001) does not
          match current_focus.ref_id (CHANGE-0002)". Under SKILL_PR step 4a's mandatory
          `--strict` that is exit 1 (check-committed-scope.mjs:270), stopping the PR with a
          remedy ("re-stage the named paths and amend") that does not address the cause.
          Canonical ordering (flush -> PR) hides it; a PR opened before the ride's own flush
          hits it, and today that case passes clean.
      - rank: NON-BLOCKING
        file: .aai/scripts/metrics-flush.mjs
        line: 478
        issue: >-
          The field-over-note PRECEDENCE — the thesis of the whole ride — has no test, and the
          spec's stated disagreement NOTE was never implemented.
        failure_scenario: >-
          My mutation MX2 makes a `VERDICT: FAIL` note OVERRIDE a `verdict: pass` field
          (hasField := !noteSaysFail && ...). TEST-135, TEST-136 and TEST-138 all stay GREEN.
          A future refactor can silently restore note-supremacy. Separately, the spec's
          Implementation-plan edge case "the FIELD wins, and the disagreement is a NOTE line"
          is only half-built: reliabilityOf's field branch never inspects the note, so a run
          whose field and marker contradict each other is flushed silently.
      - rank: NON-BLOCKING
        file: .aai/scripts/state.mjs
        line: 648
        issue: >-
          The D7 per-ref stamp's VALUE is untested: a mutant that stamps the literal 'pass'
          regardless of --status survives both owning suites.
        failure_scenario: >-
          My mutation MX6 (`stampPerRefValidation(bl, ref, 'pass', stampAt)`) leaves
          test-aai-state.sh test_067 (TEST-029) and test-aai-metrics.sh test_138 (TEST-138)
          GREEN. That mutant turns `set-validation --status fail` into a per-ref `pass` stamp,
          which D6 source 1 then reads as the highest-priority admission evidence — the exact
          hardcoded-`validation: pass` failure mode the spec names as residual R5 elsewhere.
      - rank: NON-BLOCKING
        file: .aai/scripts/lib/pricing.mjs
        line: 119
        issue: >-
          blendedCostUsd silently falls back to a hardcoded 0.5 share when PRICING.yaml carries
          no `cost_blend.input_share`, with no NOTE — a degrade without a report (Article 4),
          on the number the spec insists must never be compiled in.
        failure_scenario: >-
          A downstream project whose vendored PRICING.yaml predates this scope (or whose
          cost_blend block is edited away) prices every undecomposed run at the 0.5 convention
          while `cost_basis: total-blended` claims the share came from config; nothing in the
          output distinguishes configured-0.5 from defaulted-0.5.
      - rank: NON-BLOCKING
        file: .aai/system/FRICTION_PROTOCOL.md
        line: 161
        issue: >-
          (Round-3 NB-2, re-measured and upheld by me.) The RFC-0012 D6 privacy contract is
          guarded only for PRESENCE; the harness row and the "nine" counts can be deleted with
          the whole friction suite still green.
        failure_scenario: >-
          The validator's probes (deleting the `harness` row; "nine" -> "eight" in both the
          protocol and --help while keeping the key name) leave tests/skills/test-aai-friction.sh
          rc=0. This is how round-2 BLOCKING-2 came to exist in the first place; the contract a
          reader consults to learn what can reach a public issue body can drift again silently.
  cannot_verify:
    - claim: "Spec-AC-14 for the ride's own production flush"
      closes_with: "the close-ceremony flush against the live docs/ai/METRICS.jsonl (only dry-runs on scratch copies were performed)"
    - claim: "the full 92-suite sweep (select-suites.mjs --files-from <diff> = FULL_RUN reason=protected-l3 path=.aai/scripts/state.mjs)"
      closes_with: "one full sweep with AAI_TEST_TIMEOUT=3000 before close, recorded as sweep-<ts>.txt per the spec's Evidence contract"
    - claim: "Windows/PowerShell legs and CI-only behaviour of the new suites"
      closes_with: "the GitHub Actions run on the PR"
    - claim: "the live GitHub publish path of aai-feedback-upsert with the new harness fact"
      closes_with: "a --publish --confirm dry run against a scratch repo; only prepare-only was exercised"
    - claim: "downstream projects whose role prompts are NOT the vendored .aai copies"
      closes_with: "a consumer survey; the breaking append-run change is wired for every in-repo and every vendored caller (both prose callers are in PROFILES.yaml `core`), but a project with hand-written role prompts calling `append-run --role Validation` gets exit 2 until it adds --verdict"
  overall: fail
```

## 1. Scope, spec, and how this pass was run

Review scope was established from `docs/ai/STATE.yaml` `code_review.scope` (25 paths) and
`git diff`/`git status` in the worktree: 28 modified tracked files, nothing staged, nothing
untracked. Every probe, suite and mutation in this report ran on an `rsync` copy of the
worktree under the session scratchpad (`cr1`, `fx-*`, plus a pristine `git archive HEAD`
tree for the pre-change baseline). The shipping worktree ends this review with exactly the
same 28 modified files it started with; no tracked file was regenerated, so no
`git checkout --` was needed. The only file this review writes to the shipping tree is this
report.

Dispatch note (anti-gaming contract): the dispatch listed example mutations and named areas
to check; it pre-rated no severity and characterised no expected finding. I chose my own
seven mutations (three of them land in the same areas the dispatch suggested) and reviewed
the full scope.

## 2. AC -> hunk -> TEST walk

| Spec-AC | Diff hunk (file:line) | TEST | My evidence |
|---|---|---|---|
| 01 | state.mjs:223 (CMD_FLAGS), :843-871 (five field pushes) | TEST-026 / test-aai-state.sh:2651 | suite rc=0 (my copy), selected test rc=0 |
| 02 | state.mjs:822 (`enumFlag` harness), :843 (detectHarness default), :844 (verdict default) | TEST-027 / :2671 | rc=0 |
| 03 | state.mjs:163, :834-837 (refusal before any write) | TEST-028 / :2708 | rc=0; my own probe: `append-run --role "Code Review"` w/o `--verdict` -> exit 2, message names the flag, `cmp` identical |
| 04 | metrics-flush.mjs:466-505 (`reliabilityOf` field-first + basis + per-run NOTE) | TEST-135, TEST-136 / :2305, :2346 | rc=0; deviation D-1, NON-BLOCKING-B |
| 05 | pricing.mjs:112-122; PRICING.yaml:58-64; metrics-flush.mjs:556-573, :594 | TEST-137 / :2389 | rc=0; MX5 + MX7 redden |
| 06 | metrics-flush.mjs:341-360 (`latestValidationVerdict`), :1110-1130 (three-source gate), :1281 (plan `verdict_basis`) | TEST-138, TEST-139 / :2474, :2519 | rc=0 — **BLOCKING-1** is about behaviour outside the AC's envelope |
| 07 | state.mjs:548-586 (`stampPerRefValidation`), :642-650 (call site) | TEST-029 / :2735 | rc=0; **MX6 survives** (NON-BLOCKING-C) |
| 08 | metrics-flush.mjs:341-345 (existsSync guard) | TEST-140 / :2571 | rc=0 |
| 09 | metrics-flush.mjs:700-712; check-committed-scope.mjs:80-125 | TEST-141, TEST-007 / metrics:2610, learned-routing:449 | rc=0; NON-BLOCKING-A |
| 10 | aai-friction.mjs:456, :19-24, :100-110; aai-feedback-triage.mjs:20, :50, :58, :245 | TEST-113, TEST-011, TEST-014 | friction test_113 rc=0, triage test_014 rc=0 (run by me) |
| 11 | aai-feedback-upsert.mjs:28, :486, :529 | TEST-064 / upsert:1444 | rc=0; MX3 reddens the off-set arm |
| 12 | generate-factory-report.mjs:481-505, :772-785, :1044-1054; metrics-report.mjs:132-133, :147, :212-224 | TEST-042, TEST-142 | factory-report rc=0, metrics rc=0 |
| 13 | SUBAGENT_PROTOCOL.md:220-232; ROLE_COMMON.md:18-23; prompt-diet-ledger.sh:199; test-aai-prompt-diet.sh:784 | TEST-030 / test-aai-state.sh:2763 | rc=0; prompt-diet suite rc=0 |
| 14 | metrics-flush.mjs (append path unchanged) | TEST-143 / :2648 | rc=0 on the fixture; production run in cannot_verify |

Suites re-run by me on the copy, all `env -u AAI_ROLE`: state rc=0 (49 s), metrics rc=0,
feedback-triage rc=0, factory-report rc=0, learned-routing rc=0, token-capture rc=0,
prompt-diet rc=0, overview rc=0. `test-aai-friction` and `test-aai-feedback-upsert` failed
in my copy only because I excluded `.git` from the rsync (friction TEST-013 needs
`git check-ignore`; upsert TEST-009 runs layer-profiles) — both suites' scope-relevant tests
(TEST-113, TEST-064) pass when run selectively. Not findings.

**Spec deviations (all disclosed here, none fails the compliance verdict):**

- **D-1** — the spec's Implementation-plan edge case "a note carrying BOTH a marker and a
  field that disagree (the FIELD wins, and the disagreement is a NOTE line)" is half
  implemented: the field wins, the disagreement is never reported (metrics-flush.mjs:478-492).
  No AC covers it.
- **D-2** — `## Scope` names seven suites; the change ships eleven test files. The extra
  `tests/skills/test-aai-token-capture.sh` and `tests/skills/test-aai-overview.sh` are
  consequences of the Article-5 breaking change (the round-3 validator raised this as NB-3);
  both are inside STATE's review scope, so nothing is hidden.
- **D-3** — `.aai/STATE_FALLBACK.md` (the documented hand-append fallback for `append-run`)
  was not updated for the five fields. Degrades honestly (a hand-written run has no field ->
  note basis + NOTE), so INFO rather than a finding.

## 3. BLOCKING-1 — a stale pass event flushes a ride that FAILED validation

`.aai/scripts/metrics-flush.mjs:1110-1130`, helper at `:341-360`.

The default gate's third source accepts "the LATEST `validation_verdict` event whose
`payload.status` is pass" as equivalent to a standing PASS verdict, and D6 makes an
event-admitted ref **archive-eligible** ("a `validation_verdict` PASS is the very claim the
default gate demands"). Two facts break that equivalence:

1. **Only passes are ever stamped.** `orchestration-dispatch.mjs:1591-1597` calls
   `recordValidationVerdict` only when `snapshot.validation.status === 'pass'`. Measured on
   the live ledger: all 21 `validation_verdict` records are `status: "pass"`; zero are `fail`.
   So "latest wins, never any-pass-ever" cannot fire in production — no later event can ever
   contradict an earlier pass. TEST-139's fail-arm exercises a line shape the real producer
   never emits.
2. **The repo already learned this.** `orchestration-dispatch.mjs:351-362` (the N-4 fix)
   states it outright: the event payload's status "is a snapshot of what `last_validation.status`
   WAS at stamp time — it never changes after the fact", and if STATE later moves off pass the
   old event "still says `status: "pass"` forever". `withStaleAdvisory()` therefore corroborates
   the event against STATE's current verdict before asserting anything. The new gate performs
   no corroboration at all — neither against `metrics.work_items[ref].validation.status` (which
   this very scope introduces one screen above) nor against `last_validation`, nor against the
   run-level `verdict: fail` field the same scope adds.

**Reproduction (real scripts, scratch tree, no mutation):**

```
EVENTS.jsonl : {"event":"validation_verdict","ref":"CHANGE-0001","ts":"2026-07-01T10:00:00Z",
                "payload":{"status":"pass","hash":"deadbeef"}}
STATE        : last_validation {status: fail, ref_id: CHANGE-0001}
               metrics.work_items.CHANGE-0001.validation {status: fail, at: 2026-07-20T10:00:00Z}
               its single Validation run carries verdict: fail
post-change  : Flushed: CHANGE-0001 / verdict_basis: CHANGE-0001 -> event
               ledger: verdict=PASS  reliability={validation_fails:1, first_pass_clean:false, basis:field}
               STATE : notes "reset after flush of CHANGE-0001 [AAI-VALIDATION-ARCHIVED v1 ref=CHANGE-0001 ...]"
HEAD (pre)   : SKIP CHANGE-0001: validation verdict is "fail" (needs PASS or CANCELLED) / Nothing to flush
```

The resulting ledger line contradicts itself in one object: `verdict: "PASS"` beside
`validation_fails: 1, first_pass_clean: false`. `docs/ai/METRICS.jsonl` is append-only
(HAZ-LEDGER), so that line can never be corrected in place — which is the exact argument the
intake makes for this ride existing. The spec's own claim for the widened gate ("the remaining
24 stranded refs ... stay stranded, fail-closed, which is correct: nothing durable says they
passed") does not hold in the case where something durable says they FAILED.

Why it is BLOCKING rather than a residual: it manufactures a false PASS in the durable record,
it mints an archive record that asserts a verdict that does not exist, it is reachable through
the DEFAULT path (no flag), and it regresses a refusal that ships today.

Fix directions (reviewer does not implement): corroborate source 3 before admitting — refuse
when the ref's per-ref `validation.status` or the global block names it with anything other
than `pass`, and/or require the event to be no older than the latest contradicting verdict
(`validation.at`, `last_validation.run_at_utc`); or make event-admitted refs non-archive-eligible;
or have the dispatcher stamp `fail` events so "latest wins" is real. Any of these needs a test
built from the fixture above, plus an update to D6/R4's fail-closed claim.

## 4. NON-BLOCKING findings and my dispositions

| # | Finding | Disposition |
|---|---|---|
| A | `code_review.scope_ref_id` has no invalidation or repair path (metrics-flush.mjs:707; state.mjs:658-682 never writes it; applyFullReset leaves it) | **Remediate in tree this round** — stamp/refresh `scope_ref_id` from `current_focus.ref_id` whenever `set-code-review --scope` writes a scope (and clear it in `applyFullReset`), with a TEST-007 arm for "a freshly set scope is USED even though an older flush stamped another ref" |
| B | Field-over-note precedence untested (MX2 survives); the spec's disagreement NOTE not implemented (metrics-flush.mjs:478-492) | **Remediate in tree this round** — one fixture arm with `verdict: pass` + a `VERDICT: FAIL` note asserting field-wins; then either implement the NOTE or record the drop as an erratum in `## Amendment` |
| C | D7 stamp value untested (MX6 survives) (state.mjs:648) | **Remediate in tree this round** — extend TEST-029 with a `--status fail` arm asserting the stamped status is `fail` |
| D | `blendedCostUsd` silently defaults the share to 0.5 with no NOTE (pricing.mjs:119) | **Follow-up ref (P3)** — emit one NOTE naming the missing `cost_blend.input_share`, or fail closed to `cost_basis: none` |
| E | RFC-0012 D6 privacy contract unguarded beyond presence (FRICTION_PROTOCOL.md:161-172) — round-3 NB-2, re-measured and upheld | **Remediate in tree this round** (cheap) — assert in friction TEST-001 that the D6 table's key rows equal `aai-friction.mjs`'s persisted key set; this is the drift that produced round-2 BLOCKING-2 |
| F | `docs/product/telemetry.md` documents the `append-run` telemetry surface and says nothing about the five fields or the refusal | **Follow-up / product-docs step** — not a code defect |

## 5. The round-3 validator's six NON-BLOCKINGs — my own calls

| Round-3 NB | My call |
|---|---|
| NB-1: M9's "Must redden" cell says TEST-135, its prose says TEST-136 | **Fix in tree.** Verified independently: the mutation reddens TEST-136, not TEST-135. One-cell erratum; the spec's PASS criteria depend on the table being readable. |
| NB-2: BLOCKING-2's fix is thinly guarded; the D6 contract is unguarded | **Fix in tree** (my finding E). I re-ran the validator's three probes' logic and agree: the whole `harness` row can be deleted with the friction suite green. |
| NB-3: `## Scope` names seven suites, eleven ship | **Fix in tree** (one line naming `test-aai-token-capture.sh` and `test-aai-overview.sh` as callers fixed for the Article-5 change). I confirmed the count: 11 test files in the diff, 7 named. Nothing hidden — all are in STATE's review scope — but the ride's own thesis is that the claim should match the tree. |
| NB-4: the dispatch said "two Amendment sections", there is one | **Reject as a delivery finding.** Verified: one `## Amendment` (spec:18); the round-1 widening is disclosed inline in D9, Spec-AC-13, the Article-5 deviation and on the decisions ledger. Nothing undisclosed; nothing to change. |
| NB-5: `AAI_ROLE=subagent` breaks the suites' own state.mjs fixtures | **Reject for this scope** — pre-existing, already tracked as `fu-role-guard-blocks-own-fixtures`. Reproduced here (every run used `env -u AAI_ROLE`). |
| NB-6: full sweep owed | **Uphold as a close gate.** I re-ran `select-suites.mjs --files-from <diff>`: `FULL_RUN reason=protected-l3 path=.aai/scripts/state.mjs`. `sweep-<ts>.txt` still does not exist; the sweep is owed before close regardless of this review's verdict. |

## 6. Mutations I ran (my own choosing, on copies)

| # | Mutation | Target test | Result |
|---|---|---|---|
| MX1 | `VERDICT_REQUIRED_ROLES = ['Code Review']` (drop the Validation half) | state test_066 | **RED** — "(a) Validation without --verdict must exit 2 (got 0)" |
| MX2 | note marker OVERRIDES the verdict field in `reliabilityOf` | metrics test_135/136/138 | **NOT RED** (all three green) -> NON-BLOCKING-B |
| MX3 | upsert `safeHarness` -> pass-through for any string | upsert test_064 | **RED** — "(b) an off-set harness value must render unknown" |
| MX4 | gate source 3 accepts any event status (`eventStatus !== null`) | metrics test_139 | **RED** — "(b) latest-is-fail must NOT flush the ref" |
| MX5 | `cost_bounds_usd` made symmetric (`[cost, cost]`) | metrics test_137 | **RED** — bounds assertion |
| MX6 | per-ref stamp hardcodes `'pass'` regardless of `--status` | state test_067 + metrics test_138 | **NOT RED** (both green) -> NON-BLOCKING-C |
| MX7 | `tokens_total` removed from the numeric-coercion allowlist (seam S1) | metrics test_137 | **RED** — blended cost assertion |

Every mutation was applied to a scratch copy with a single-occurrence anchor check and the
file restored by `cmp`-verified byte comparison against the shipping worktree afterwards.

Additional probes: byte-identity after the Code Review refusal (exit 2, `cmp` identical);
`check-state` rc=0 on a STATE carrying both new shapes (`code_review.scope_ref_id` and the
per-ref `validation:` block); pre-change vs post-change flush on the BLOCKING-1 fixture.

## 7. Protected-surface hygiene — `.aai/scripts/state.mjs` (L3)

- **Single writer:** every new mutation goes through `editBlock`; `writeState` is still called
  only from `main()` (`:1141`, `:1151`), after the dispatched mutator returns. The per-ref
  stamp adds a SECOND `editBlock` in `cmdSetValidation` (`:642-650`) — still one file write.
- **Byte identity on refusal:** the `--verdict` check sits at `:834`, ahead of every
  `editBlock`; verified by `cmp`, independently of the suite.
- **No new global:** two module-level frozen-by-convention consts (`VERDICT_VALUES`,
  `VERDICT_REQUIRED_ROLES`) in the same style as `BOOLS`/`MODES`; no mutable module state.
- **New import** of `lib/harness.mjs` into the protected file is the one D2 requires (no private
  copy of the closed set); `HARNESS_VALUES` is shared by `append-run`, friction, triage and
  upsert (seam S7).
- **Repair-path gap:** the new `code_review.scope_ref_id` key is the only STATE field this
  scope adds that NO `state.mjs` subcommand can write or clear (NON-BLOCKING-A).
- **Hash pins:** the repo's only content pin (`tests/skills/lib/close-work-item-pin.sh`) names
  `close-work-item.mjs`, untouched here — no re-pin owed.
- R-GUARD (`AAI_ROLE=subagent` refuses mutators) still holds: state suite rc=0 including
  test_062/063.

## 8. PRICING `cost_blend` as a convention

`.aai/system/PRICING.yaml:58-64` declares `input_share: 0.5` with `basis: convention`,
`source_ref: null` and a reason that states the measurement (0 of 628 runs carry both
`tokens_in` and `tokens_out`) and explicitly refuses to assert the LOOP_TICKS claim. Every
derived number carries `cost_basis: total-blended` plus `cost_bounds_usd` with the all-input /
all-output extremes, and R6 records the risk. This is the honest shape; I verified the share is
READ (MX5/M11-class mutations redden) and that an unpriced model yields `null`, never 0 or NaN.
One gap: the silent 0.5 fallback when the key is absent (NON-BLOCKING-D).

## 9. Consumer impact (a downstream project running `/aai-update`)

- **Both prose callers ship with the engine.** `.aai/ROLE_COMMON.md` and
  `.aai/SUBAGENT_PROTOCOL.md` are in `PROFILES.yaml` `core` (lines 55, 77), the same profile as
  `.aai/scripts/state.mjs`, and `aai-sync.sh` replaces the whole `.aai/` subtree — so a consumer
  that updates gets the refusing CLI and the instructions that satisfy it in one step. In-repo
  callers were swept (`append-run` over `.aai`, `tests`, `docs`, `.claude`, `.codex`, `.gemini`,
  `.cursor`, `.agents`, `.github`, `hooks`): every suite invocation with `--role Validation` or
  `--role "Code Review"` now passes `--verdict` (test-aai-state.sh:526, 1738, 2023, 2393;
  test-aai-token-capture.sh:583), and the two deliberate refusal arms (test-aai-state.sh:2716,
  2722) omit it on purpose.
- **A consumer with hand-written role prompts breaks loudly, not silently:** exit 2, the message
  names `--verdict` and STATE is byte-identical. That is the intended Article-5 deviation and it
  degrades correctly (nothing written, nothing half-written).
- **Its OLD dispatch notes keep their text and are not rewritten** — no ledger line is touched
  (Spec-AC-14). But the FIRST post-update flush of a legacy ride changes two EXISTING keys:
  `agent_runs[].cost_usd` null -> a blended estimate, `totals.total_cost_usd` null -> a number.
  That is spec residual R8, and the consumer-visible consequence — priced and unpriced rides
  living in one ledger, incomparable unless partitioned on `cost_basis` — is disclosed in the
  spec but nowhere a consumer reads. **The CHANGELOG entry written at PR time must say it**, as
  must the release notes; `docs/product/telemetry.md` should follow (finding F).
- **Its flush window changes shape on the first run** (spec R3) — and, per BLOCKING-1, that
  widening currently includes refs whose recorded verdict is `fail`. A consumer's first flush
  after this update can therefore write a false PASS into ITS append-only ledger. This is the
  strongest reason BLOCKING-1 must be fixed before merge rather than after.

## 10. What I could not verify

As listed in `cannot_verify` above: the ride's own production flush (Spec-AC-14 in production),
the owed 92-suite FULL_RUN sweep, the Windows/PowerShell legs, the live `--publish --confirm`
GitHub path, and consumers with non-vendored role prompts. Also not verified: whether the 16
lines round 2 appended to `docs/ai/tests/test-runs.jsonl` are wanted in the PR (unchanged by me).

## 11. Next steps

1. Fix BLOCKING-1 at cause (corroborate gate source 3, or drop archive eligibility for
   event-admitted refs), with a regression test built from the fixture in section 3 and a
   matching update to D6/R4's fail-closed statement.
2. Remediate NON-BLOCKING A, B, C, E in tree this round; file D and F as follow-up refs.
3. Fix the two spec errata (round-3 NB-1's M9 cell, NB-3's suite count) in the same pass.
4. Re-review (the same single pass) and then run the owed FULL_RUN sweep before close.

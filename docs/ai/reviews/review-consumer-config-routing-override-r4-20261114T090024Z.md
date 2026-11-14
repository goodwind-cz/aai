# Code review: consumer-config-routing-override, round 4 (owner extension)

```yaml
review:
  scope: "5f066770..5905b3e9 (owner extension, focus) within STATE code_review.scope path list vs origin/main"
  spec: docs/specs/SPEC-0290-spec-consumer-config-routing-override.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-3680 plants a pricing: section (test-aai-project-config.sh planted bytes); suite rc=0 this round" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-3681/3682 (unchanged since round 3 PASS); suite rc=0" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-3683/3684; suite rc=0" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-3685; suite rc=0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3686; suite rc=0" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3687; parser unchanged for routing rows except isNullId (project-config.mjs:189)" }
      - { ac: Spec-AC-07, call: compliant, citation: "orchestration-dispatch.mjs:1917-1929 NOTEs after suggestModel under applied===suggested_model; TEST-3688 + TEST-3700" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3689; aai-doctor.mjs catProjectConfig absent -> null unchanged" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3690 (accepts any non-VIOLATION verdict)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3691" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3692/3693" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3695" }
      - { ac: Spec-AC-13, call: compliant, citation: "project-config.mjs:143-198 (PRICE_FIELDS line, all-or-nothing return); TEST-3696 19 fixtures" }
      - { ac: Spec-AC-14, call: compliant, citation: "pricing.mjs rateEntry/priceSource/resolveProjectKey; project-config.mjs loadCostPricing; TEST-3697/3698/3699" }
      - { ac: Spec-AC-15, call: compliant, citation: "aai-doctor.mjs priceHorizon + catProjectConfig; TEST-3701 (test-aai-doctor.sh)" }
      - { ac: Spec-AC-16, call: compliant, citation: "HARNESS_VENDOR + overrideVendor (project-config.mjs); dispatch NOTE; TEST-3702" }
      - { ac: Spec-AC-17, call: compliant, citation: "table-freshness.mjs pricedCheck + priced subcommand; PRICING.yaml header comment; TEST-3703 (see CR4-1: the AC text itself pins UNCHANGED)" }
      - { ac: Spec-AC-18, call: compliant, citation: "ROUTING_REFRESH Steps 1-3; TEST-3704" }
      - { ac: Spec-AC-19, call: compliant, citation: "ROUTING_REFRESH Step 0 + D1-D7; TEST-3705; validator val5-e2e-consumer-clone.log" }
      - { ac: Spec-AC-20, call: compliant, citation: "CHANGELOG.md consumer-config entry body; docs/product/*; TEST-3706" }
      - { ac: Spec-AC-21, call: compliant, citation: "suite-map.yaml globs; TEST-3707 (see CR4-2: the AC text itself is ride-scoped)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-pricing.sh, line: 695,
          issue: "TEST-3703 asserts '^UNCHANGED .aai/system/PRICING.yaml$' from stamp-guard against the merge-base on every future run",
          failure_scenario: "the next upstream ROUTING_REFRESH run (Step 2 marks or re-verifies every row and re-stamps) passes stamp-guard (CHANGED-STAMPED, rc 0) and table-freshness priced, then its required aai-pricing suite goes red on TEST-3703; same class as round-2 CR-1 on TEST-3690. backed-by: repro docs/ai/reports/consumer-config-routing-override/repro-r4-cr1-test3703-blocks-pricing-refresh.sh" }
      - { rank: BLOCKING, file: tests/skills/test-aai-project-config.sh, line: 1241,
          issue: "TEST-3707 asserts this ride's distribution fact (no added .aai/ path, no .aai/*.prompt.md change vs merge-base with origin/main) as a permanent regression test",
          failure_scenario: "any later ride that edits a .aai/*.prompt.md or adds a .aai/ file and runs aai-project-config (FULL_RUN for any lib/** change in CI, or the full sweep before close) turns red for a reason unrelated to it. backed-by: repro docs/ai/reports/consumer-config-routing-override/repro-r4-cr2-test3707-blocks-later-aai-changes.sh" }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/pricing.mjs, line: 133,
          issue: "shipped wins through resolveModelKey's longest-prefix rule, so an EXACT project price for an id the shipped table does not list loses to a different shipped row",
          failure_scenario: "routing_override@codex Metrics Flush: gpt-5-nano with a correct project price 0.05/0.40: cost uses gpt-5 (1.25/10) = 11.25 vs 0.45 per 1M+1M, CAT-22 labels the row 'shadowed by shipped PRICING', and the downstream routine D2/D4 deletes the correct entry (also o3-mini -> o3, gemini-2.5-flash-lite -> gemini-2.5-flash); probe docs/ai/reports/consumer-config-routing-override/repro-r4-nb1-shipped-prefix-shadows-exact-project-price.mjs" }
      - { rank: NON-BLOCKING, file: .aai/routines/ROUTING_REFRESH.routine.md, line: 180,
          issue: "Safety rule 'Never edit anything under .aai/' has no carve for the Step 0 install-for-the-run (validation NB-1)",
          failure_scenario: "an agent that reads the safety rules as overriding the step text treats the Step 0 install as forbidden and STOPs, so the downstream mode never runs in a fresh cloud clone" }
  cannot_verify:
    - { claim: "the curl|bash installer from goodwind-cz/aai main behaves in a real cloud-routine clone of an OLDER consumer (tracked shim files untouched or only left dirty, hooks do not refuse branch push)",
        closes_with: "one live downstream run on a real consumer after merge, with git status and the PR file list captured" }
    - { claim: "the routine's vendor pricing pages and the downstream D3 primary-source reading produce correct rates",
        closes_with: "the first live upstream and downstream runs and their PR bodies" }
    - { claim: "TEST-3707 and TEST-3703 behave in CI as locally (fetch-depth 0 is configured in skill-suite.yml; not observed on a PR run this round)",
        closes_with: "the PR's CI run" }
  overall: fail
```

security_relevant: true

Reason for `true`: NB4-2 touches the routine's Safety rules (the write-scope guard of an autonomous agent with push rights), and the cannot_verify list names the run-time remote installer, a sandbox-boundary question.

## Scope and spec

- Scope: the STATE `code_review.scope` path list against `origin/main`. This round focuses on the owner-extension diff `git diff 5f066770..HEAD` (HEAD `5905b3e9`, branch `change/consumer-config-routing-override`). The uncommitted EVENTS.jsonl lines are append-only telemetry, not reviewed code.
- Spec: `docs/specs/SPEC-0290-spec-consumer-config-routing-override.md`, Spec-AC-01..21, including the "Owner extension 2026-11-14" block (D-PSECTION, D-FORMAT-2, D-PREC, D-PWIRE, D-DISPATCH-2, D-FRESH, D-VENDOR, D-FULL, D-DOWN, D-DIST-2).
- Coaching note (anti-gaming contract): the dispatch named "areas to probe", said that Spec-AC-01..12 had passed three earlier rounds, and called one condition "not a finding". I took these as pointers, not limits. I walked every AC row again and reviewed every file in the extension diff. I set the severities myself. I agree that the docs-audit probable-false-open on a reopened ride is close-ceremony state.

## The owner's four asks

| Ask | Delivered by | Call |
|---|---|---|
| Refresh the whole pricing table | D-FULL: ROUTING_REFRESH Steps 1-3 cover every `models:` row and every `sources:` provider, plus `table-freshness.mjs priced` and `unverified_utc` | delivered (but see CR4-1: the first such run goes red on TEST-3703) |
| Price other vendors' models downstream | D-DOWN: Step 0 mode decision, consumer-clone install, D1-D7 | delivered (NB4-2, cannot_verify 1) |
| Project prices | the `pricing:` section, the `lib/pricing.mjs` seam and all four consumers | delivered (NB4-1 limits it for ids that match a shipped row by prefix) |
| Cross-vendor overrides allowed | D-VENDOR: applied, one NOTE, named in CAT-22 | delivered |

## AC walk notes

All 21 rows are compliant with the frozen text. The four extension suites ran this round, one at a time, through `aai-run-tests.sh`: test-aai-project-config rc=0, test-aai-pricing rc=0, test-aai-doctor rc=0 and test-aai-routine rc=0. The AC Status column still reads `planned`/`implementing` for 01, 07 and 13..21. That is the AC-FLIP deferral to close, as in validation round 4, and not a finding.

Spot checks behind the calls:
- Costing seam (Spec-AC-14). `rateEntry` is the only lookup used by `runCostUsd` and `blendedCostUsd`. `priceSource` follows the same order. metrics-flush prefers a recorded `cost_usd`, then decomposed, then blended. metrics-report fills only a null ledger cost. No path adds a shipped cost and a project cost together. Bracket and prefix ids resolve through `resolveProjectKey` (TEST-3697).
- All-or-nothing (Spec-AC-13). Either section's errors return empty `overrides` and empty `prices` together. `loadCostPricing` attaches nothing unless `status === 'ok'`. A probe confirmed it: an invalid rate plus a missing field gives two errors, and `__proto__` is refused by `PRICE_KEY_RE`.
- Prototype safety. A probe with keys `constructor`, `toString` and `hasOwnProperty` priced each at its own row. `valueOf` and `__proto__` (not keys) stayed null with source null. `prices`, `entry.seen` and `sources` are null-prototype, and `pricing.models` is reached only through own-key resolution.
- NOTE ordering (Spec-AC-07, D-DISPATCH-2). Both model NOTEs follow `suggestModel` under `applied !== null && out.suggested_model === applied`. A backstop-swapped Validation override is silent (TEST-3700).
- CAT-22 (Spec-AC-15/16). The absent file still returns null before any new code runs. Only PASS or WARN is produced. `checkTables` sits in a try block, and a null horizon gives the "cannot be judged" WARN.

## Findings

### CR4-1 BLOCKING: TEST-3703 breaks the routine this ride ships
`tests/skills/test-aai-pricing.sh:695-697` runs `live_guard origin/main` and requires `^UNCHANGED .aai/system/PRICING.yaml$`. That is true only for this ride's comment-only edit. Every later legitimate PRICING change fails it, and the first is the monthly ROUTING_REFRESH run, whose Step 2 must mark or re-verify every row and move the stamp. Its Step 3 requires the aai-pricing suite, and its write scope covers only "id and rate pins", so the routine cannot repair this line.
Repro (exit 0 = reproduced): `docs/ai/reports/consumer-config-routing-override/repro-r4-cr1-test3703-blocks-pricing-refresh.sh` works in a scratch clone. It sets origin/main to HEAD, marks `claude-fable-5-2` with `unverified_utc` and re-stamps. Results: stamp-guard rc 0 `CHANGED-STAMPED`, `priced` prints `UNVERIFIED`, TEST-3703 rc 1. Log: `review-r4-repro-cr1.log`.
This is the class round-2 CR-1 fixed for MODEL_ROUTING (TEST-3690 / amended Spec-AC-09). Spec-AC-17's text repeats the old wording ("SHALL print UNCHANGED for PRICING").
Remedy: assert no `VIOLATION` and a `^(UNCHANGED|RESTAMPED|CHANGED-STAMPED) .aai/system/PRICING.yaml$` line, as TEST-3690 does. Amend Spec-AC-17 additively, as Spec-AC-09 was.

### CR4-2 BLOCKING: TEST-3707 turns this ride's distribution fact into a permanent gate
`tests/skills/test-aai-project-config.sh:1241-1249` fails whenever the branch under test adds any `.aai/` path or touches any `.aai/*.prompt.md` relative to its merge-base with origin/main. After merge the check is trivially green on main. On every later ride that edits a prompt or adds a core file, it is red whenever aai-project-config runs: select-suites answers FULL_RUN for any `lib/**` change, and the canon runs a full sweep before close.
Repro (exit 0 = reproduced): `docs/ai/reports/consumer-config-routing-override/repro-r4-cr2-test3707-blocks-later-aai-changes.sh`. The baseline on the merged state gives rc 0. After a one-line comment appended to `.aai/SKILL_CODE_REVIEW.prompt.md` it gives rc 1, `the change touches a .aai/*.prompt.md file`. Log: `review-r4-repro-cr2.log`.
Remedy: keep the select-suites and check-vendored-script-deps parts, which are durable. Move the merge-base diff assertion out of the permanent suite into ride evidence: a one-off validation command, or a check bound to this ride that skips once the merge-base contains the ride. Amend Spec-AC-21 to match.

### NB4-1 NON-BLOCKING (P2): the shipped prefix rule hides an exact project price
`lib/pricing.mjs:132-134` (`rateEntry`) and `projectPriceRows` (`shadowed`) treat "the shipped table can cost the id" as including the shipped longest-prefix guess. Probe `repro-r4-nb1-shipped-prefix-shadows-exact-project-price.mjs` (log `review-r4-repro-nb1.log`): `gpt-5-nano` is not a shipped key and resolves to `gpt-5`, so the cost is 11.25 instead of the project's 0.45 per 1M+1M. The row is labelled `shadowed by shipped PRICING`, and downstream D2/D4 would delete it. `o3-mini` resolves to `o3` and `gemini-2.5-flash-lite` to `gemini-2.5-flash` in the same way. The mis-costing predates this ride, so the ride makes no cost worse. It does fail to let a consumer correct it, and the label and the routine's deletion compound the problem. The behavior follows D-PREC as frozen.
Disposition: promote to follow-up, `suggested: fu-shipped-prefix-shadows-project-price` (P2, owner decision on D-PREC: an exact or bracket-stripped project key could outrank a shipped prefix match, so only a shipped exact or alias match wins).

### NB4-2 NON-BLOCKING (P3): the safety rule has no carve for the Step 0 install
`ROUTING_REFRESH.routine.md`, the last Safety-rules bullet, says "Never edit anything under `.aai/`", while Step 0 installs into `.aai/` for the run. The validator's end-to-end run shows the effect is harmless (clean tree, PR = one file). The literal conflict can still make a cautious agent STOP. This is validation NB-1, and I agree.
Disposition: remediate in tree in the CR4 round. Append "except the Step 0 install for this run, which is never committed" to the bullet; TEST-3705's pinned phrase survives. The alternative is `suggested: fu-routine-install-carve-safety-rule`.

### INFO (no gate)
- `project-config.mjs` timestamp, rate and provider errors quote the raw value inside quotes, which gives `""2026-02-30T00:00:00Z""` for a quoted value. Cosmetic.
- The missing-field error for an entry is emitted when the entry closes, so errors are not sorted by line. Cosmetic.
- A project-priced run is recorded in METRICS.jsonl with `cost_basis: decomposed`, the same as a shipped-priced run. This is by spec (R13: no new field), and the provenance is visible only through CAT-22.

## Validation round 4 NB-1..4, my view
- NB-1: agreed. It is NB4-2 above.
- NB-2 (an exact `.aai/` marker is needed when the consumer had an `.aai/...` line before its first sync): it fails safe with a STOP. Agreed, no change.
- NB-3 (the run installs from main, not the consumer's pinned version): agreed as an accepted residual. It is cannot_verify 1 here.
- NB-4 (`check_binding.spec_path` still names the DRAFT path): orchestrator re-binds at close. Agreed.

## Warning dispositions (H6)
- NB4-1: follow-up `suggested: fu-shipped-prefix-shadows-project-price` (P2). The orchestrator files it.
- NB4-2: remediate in tree in the CR4-1/CR4-2 round, with fallback `suggested: fu-routine-install-carve-safety-rule` (P3).

## Next steps
1. Implementation round: fix CR4-1 (TEST-3703 verdict set) and CR4-2 (remove the merge-base diff assertion from TEST-3707 or bind it to the ride). Add NB4-2's one-line carve.
2. Additive Spec-AC-17 and Spec-AC-21 amendments with disclosure. Per canon these are owner scope changes, so surface them to the owner, since this was the last review round under the cap.
3. Re-run aai-pricing and aai-project-config, plus both repros, which must then print NOT REPRODUCED.
4. File NB4-1's follow-up.

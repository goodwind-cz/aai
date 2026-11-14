# Code review: consumer-config-routing-override, round 5 of 5 (final)

```yaml
review:
  scope: "STATE code_review.scope path list vs origin/main at HEAD 6ab59f0b; focus git diff 11bcfffb..6ab59f0b (r4 remediation + owner decision NB4-1(a))"
  spec: docs/specs/SPEC-0290-spec-consumer-config-routing-override.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-3680; aai-project-config rc=0 this round" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-3681/3682; rc=0" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-3683/3684; rc=0" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-3685; rc=0" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-3686; rc=0; shipped-only lookup equivalent to resolveModelKey over every shipped key, key-x, key[1m] and alias (0 divergences)" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-3687/3694; parser untouched by 6ab59f0b" }
      - { ac: Spec-AC-07, call: compliant, citation: "orchestration-dispatch.mjs:1917-1929 unchanged; isPricedModel -> runCostUsd -> resolvePrice; TEST-3688/3700" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-3689; aai-doctor rc=0" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-3690 (non-VIOLATION verdict)" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3691" }
      - { ac: Spec-AC-11, call: compliant, citation: "TEST-3692/3693" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3695" }
      - { ac: Spec-AC-13, call: compliant, citation: "TEST-3696; project-config.mjs parse unchanged in 6ab59f0b" }
      - { ac: Spec-AC-14, call: compliant, citation: "pricing.mjs:162-179 resolvePrice (shipped exact, project exact, shipped prefix, project prefix); TEST-3697 (amended mutation), TEST-3698/3699, TEST-3708; probe review-r5 edges" }
      - { ac: Spec-AC-15, call: compliant, citation: "project-config.mjs:298 shadowed = shippedExactPriced; TEST-3701 + TEST-3708 shadowed legs" }
      - { ac: Spec-AC-16, call: compliant, citation: "TEST-3702 rc=0; AC text holds (see NB5R-1 for an untested vendor case outside the AC text)" }
      - { ac: Spec-AC-17, call: compliant, citation: "test-aai-pricing.sh:692-700 no VIOLATION + (UNCHANGED|RESTAMPED|CHANGED-STAMPED); r4 CR4-1 repro NOT REPRODUCED this round" }
      - { ac: Spec-AC-18, call: compliant, citation: "TEST-3704; aai-routine rc=0" }
      - { ac: Spec-AC-19, call: compliant, citation: "ROUTING_REFRESH D4 + Safety rules carve-out; TEST-3705 rc=0" }
      - { ac: Spec-AC-20, call: compliant, citation: "TEST-3706; CHANGELOG states the amended lookup order" }
      - { ac: Spec-AC-21, call: compliant, citation: "TEST-3707 without the merge-base check; r4 CR4-2 repro NOT REPRODUCED this round" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/pricing.mjs, line: 205,
          issue: "modelProvider returns the project row's optional provider (null when absent) whenever resolvePrice picks a project row, discarding the vendor the shipped table names for that id (shipped exact unpriced row or shipped prefix row); new in 6ab59f0b",
          failure_scenario: "routing_override@claude Code Review: gpt-5-nano with a project price that has no provider: field. Before 6ab59f0b vendor openai and one cross-vendor NOTE; now vendor null, no NOTE, CAT-22 does not name it cross-vendor. Same for cursor-grok-4.6 (was xai). Probe repro-r5-nb1-project-row-drops-shipped-vendor.mjs exit 0, log review-r5-repro-nb1.log" }
      - { rank: NON-BLOCKING, file: .aai/routines/ROUTING_REFRESH.routine.md, line: 145,
          issue: "D2 selects stale rows 'whose id the shipped table still does not price', which after decision (a) no longer maps onto a doctor JSON field (validation NB5-2)",
          failure_scenario: "a stale exact project row under a shipped prefix (gpt-5-nano) may be read as 'priced by the shipped table' and skipped; fails safe (row kept, CAT-22 freshness WARN keeps firing)" }
      - { rank: NON-BLOCKING, file: docs/product/aai-doctor.md, line: 137,
          issue: "'a project price the shipped table also prices is named shadowed' and the project-config.mjs:6 header 'a cost fallback behind the shipped table' predate decision (a) (validation NB5-1)",
          failure_scenario: "a consumer reading aai-doctor.md expects a gpt-5-nano row to be shadowed and deletes it by hand, losing the exact price that is now used" }
  cannot_verify:
    - { claim: "the curl|bash installer from main behaves in a real cloud-routine clone of an older consumer (Step 0 install leaves tracked files untouched, hooks allow the branch push)",
        closes_with: "one live downstream run on a real consumer after merge, with git status and the PR file list captured" }
    - { claim: "vendor pricing pages read by the upstream Steps 1-3 and downstream D3 give correct rates",
        closes_with: "the first live upstream and downstream runs and their PR bodies" }
    - { claim: "TEST-3703's live stamp-guard against origin/main behaves in CI as locally (needs full history; fetch-depth 0 is configured in skill-suite.yml)",
        closes_with: "the PR's CI run" }
    - { claim: "owner sign-off of the six unsigned contract amendments (fu-amend-consumer-config-routing-48543f), including the R13 narrowing of 'shipped wins' and the TEST-3697 mutation-string change",
        closes_with: "owner sign-off at the merge checkpoint" }
  overall: pass
```

security_relevant: true

Reason for `true`: round 4 marked the ref true (NB4-2 touched the routine's write-scope guard), and the flag is sticky across later reports of the ref.

## Scope and spec

- Scope: the STATE `code_review.scope` path list against `origin/main`, HEAD `6ab59f0b` on `change/consumer-config-routing-override`. The focus is `git diff 11bcfffb..6ab59f0b`: the r4 remediation and the owner's decision NB4-1(a). The uncommitted `docs/ai/EVENTS.jsonl` lines are append-only telemetry and were not reviewed as code.
- Spec: `docs/specs/SPEC-0290-spec-consumer-config-routing-override.md`, Spec-AC-01..21, TEST-3680..3708, including the 2026-11-14 final-round amendment (decisions.jsonl `spec_amendment` 11:21:25Z). `spec-amend list --strict` rc=0.
- Coaching note (anti-gaming contract): the dispatch summarized what the owner decided and listed areas to concentrate on. It did not rate severities or exclude any area. I walked every AC row again and set every severity myself.

## r4 findings at HEAD

| r4 finding | Fix in 6ab59f0b | My check | Call |
|---|---|---|---|
| CR4-1 TEST-3703 pins UNCHANGED | Asserts no `VIOLATION .aai/system/PRICING.yaml` plus one `UNCHANGED/RESTAMPED/CHANGED-STAMPED` line (test-aai-pricing.sh:692-700). Spec-AC-17 amended. | Re-ran `repro-r4-cr1-test3703-blocks-pricing-refresh.sh` in a scratch clone: exit 1, NOT REPRODUCED. stamp-guard prints CHANGED-STAMPED rc 0 and TEST-3703 rc 0. aai-pricing rc=0. | fixed |
| CR4-2 TEST-3707 merge-base invariant | Diff check removed; select-suites and vendored-deps legs kept. Spec-AC-21 amended. | Re-ran `repro-r4-cr2-...sh`: exit 1, NOT REPRODUCED (rc 0 after a later prompt edit). aai-project-config rc=0. | fixed |
| NB4-1 shipped prefix shadows exact project price | Owner option (a): `resolvePrice` with lookup order shipped exact, project exact, shipped prefix, project prefix; `shadowed` = `shippedExactPriced`; D4 keeps such rows; TEST-3708. | Re-ran the r4 probe: NOT REPRODUCED (gpt-5-nano costs 0.45 from the project, not shadowed). Edge probe below. | fixed (one side effect, NB5R-1) |
| NB4-2 safety-rule carve | The D4 bullet and the Downstream write-scope rule both carve the Step 0 install ("allowed for this run and never committed"). | TEST-3705 rc=0. The two carve-out texts agree. Upstream scope is untouched, which is correct because upstream has no install. | fixed |

## Lookup correctness and determinism (probe in scratch, not shipped)

I tested a fixture PRICING with a prefix row, an exact row, a null-rate row, an alias and an alias to a missing target, under project prices:
- An alias or a bracketed alias whose target has rates resolves to the shipped exact row, and its project row is shadowed. Shadowed and used always agree.
- An exact project id, including one with surrounding whitespace or a `[x]` suffix, beats the shipped prefix. Another id under the same prefix stays shipped.
- A shipped exact row without rates skips the shipped prefix step, and a project prefix then prices `nul-1-xy`. This is the documented rule.
- The empty id, `constructor` and `__proto__` resolve to null, with no prototype leak.
- Ties: two distinct keys of equal length cannot both be prefixes of one id, so longest-prefix selection does not depend on key order. The result is deterministic.
- Shipped-only equivalence: over every shipped key, `key-x`, `key[1m]` and every alias, `resolvePrice` matches the pre-change `resolveModelKey` plus `hasRates` with 0 divergences, and no shipped alias targets a missing row. A project without the file therefore sees no cost change.

No double counting:
- All four readers go through the one seam. metrics-flush (`runCostUsd`/`blendedCostUsd`, recorded `cost_usd` first), metrics-report (fills only a null ledger cost), dispatch (`isPricedModel`, `overrideVendor`) and doctor (`priceSource`, `overrideVendor` on costPricing, `projectPriceRows` on shipped-only) are all reached through `resolvePrice`.
- No caller sums shipped and project rates, and none of these four files changed in 6ab59f0b.

Tests not pinned to live table state:
- TEST-3708 uses a fixture PRICING only.
- TEST-3697 derives its real id from the shipped table and asserts only "shipped equals shipped".
- TEST-3703 and TEST-3707 no longer pin this ride's facts.

## Findings

### NB5R-1 NON-BLOCKING (P3): a provider-less project row hides the vendor the shipped table knows
`lib/pricing.mjs:203-216` (`modelProvider`, line 205) now returns `r.entry.provider ?? null` whenever `resolvePrice` picks a project row. Before 6ab59f0b the shipped row's source provider won whenever `resolveModelKey` landed on a non-`unknown` key. Two cases now lose a vendor they used to have:
- A shipped prefix row (gpt-5-nano under gpt-5): this case reaches the project only because of decision (a).
- A shipped exact row without rates (cursor-grok-4.6, `xai-pricing`).

Probe `docs/ai/reports/consumer-config-routing-override/repro-r5-nb1-project-row-drops-shipped-vendor.mjs` exits 0 (log `review-r5-repro-nb1.log`). With a project row lacking `provider:`, gpt-5-nano was `openai` before the change and is `null` now. cursor-grok-4.6 was `xai` and is now `null`. On claude neither override prints the cross-vendor NOTE or gets a CAT-22 cross-vendor label any more.

The override is still applied and its cost is correct. The only loss is an informational NOTE and label, which is why this is P3.

The spec is also self-contradictory here:
- The D-PREC amendment says `modelProvider` goes "through `resolvePrice`".
- The unamended D-PREC seam bullet ("when `resolveModelKey` lands on a key other than `unknown`, `sources[...]`") and D-VENDOR ("shipped row's source provider, else the project row's provider") still describe the old order.

Spec-AC-16's text does not cover this case.

Remedy: one line, `return r.entry.provider ?? <shipped vendor of resolveModelKey(pricing, modelId)>`, plus a TEST-3702 leg and an amendment of the two bullets.
Disposition: follow-up `suggested: fu-model-provider-keeps-shipped-vendor` (P3). It is not an accepted residual, because it is a behavior regression this commit introduced.

### NB5R-2 NON-BLOCKING (P3): routine D2 wording (validation NB5-2), agreed
`ROUTING_REFRESH.routine.md:143-147`: "whose id the shipped table still does not price" no longer maps onto a doctor field after decision (a). It fails safe.
Disposition: follow-up `suggested: fu-routine-d2-stale-exact-under-prefix` (P3). Reword to "every stale row whose `shadowed` is false".

### NB5R-3 NON-BLOCKING (P3): two stale wordings of "shadowed" (validation NB5-1), agreed
`docs/product/aai-doctor.md:137` and the `lib/project-config.mjs:6` header comment still describe the pre-(a) meaning. consumer-config.md, the CHANGELOG and the spec are correct, and no test pins the old wording.
Disposition: follow-up `suggested: fu-doctor-doc-shadowed-exact-wording` (P3). A docs-only fold at close is acceptable only if the owner accepts it without another review round.

### INFO (no gate)
- `resolvePrice` never returns the `unknown` row. Before, `rateEntry` would have used `unknown` if it carried rates. The shipped `unknown` row is null-rated, so there is no observable change. A fixture PRICING with a priced `unknown` would now cost null.
- An alias whose target is missing from `models` skips the project-exact step for the target id. No shipped alias does this today.
- An override id that only a shipped prefix prices, with no project row, keeps the prefix cost (`price_source` shipped), so the downstream routine does not research it. The owner chose this with (a). A consumer corrects it by adding the exact row by hand. The validator noted the same.
- Validation NB5-3 (the TEST-3697 mutation string changed but the 11:21:25Z record does not name it): agreed, disclose at the owner sign-off. NB5-4 (unsigned amendments): carried in cannot_verify.

## Evidence run this round (one at a time, no full sweep)
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-project-config.sh`: rc 0, TEST-3708 PASS
- the same harness with test-aai-pricing.sh: rc 0; test-aai-routine.sh: rc 0; test-aai-doctor.sh: rc 0
- r4 repros CR4-1 and CR4-2 (scratch clones): exit 1, NOT REPRODUCED. The NB4-1 probe prints NOT REPRODUCED.
- `node .aai/scripts/spec-amend.mjs list --strict`: rc 0
- NB5R-1 probe: exit 0, reproduced

## Warning dispositions (H6)
- NB5R-1: follow-up `suggested: fu-model-provider-keeps-shipped-vendor` (P3); the orchestrator files it.
- NB5R-2: follow-up `suggested: fu-routine-d2-stale-exact-under-prefix` (P3).
- NB5R-3: follow-up `suggested: fu-doctor-doc-shadowed-exact-wording` (P3).

## Next steps
1. The orchestrator files the three follow-ups, or the owner folds NB5R-3's two wording lines at close.
2. Owner sign-off on fu-amend-consumer-config-routing-48543f at the merge checkpoint, including the TEST-3697 mutation-string disclosure.
3. Close ceremony as canon. The AC Status column flip (AC-FLIP) is still due at close.

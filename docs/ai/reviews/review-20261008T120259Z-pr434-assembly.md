```yaml
review:
  scope: "bdeb425c040ada918dd97e5b878b71e420bad83a to current working tree at HEAD 8701da75a29e76e5a7897a9e327ad07f9ab38345; 966 pinned paths"
  spec: docs/specs/SPEC-0210-spec-pr-capability-preflight.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:174-232; fresh TEST-001 and probes.log" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:249-262; fresh TEST-002" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:76-113; fresh TEST-003..005" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/SKILL_PR.prompt.md:54; fresh TEST-006; prose obedience gap below" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/pr-preflight.mjs:146-149,221,271; fresh TEST-007 and probes.log" }
      - { ac: Spec-AC-06, call: compliant, citation: ".aai/system/PROFILES.yaml:205; tests/skills/suite-map.yaml:1117; fresh TEST-008" }
      - { ac: "SPEC-0211/Spec-AC-01", call: compliant, citation: ".aai/scripts/pr-preflight.mjs:157-160,210; TEST-001 and malformed explicit probes" }
      - { ac: "SPEC-0211/Spec-AC-02", call: compliant, citation: ".aai/scripts/pr-preflight.mjs:223-227,273; TEST-007 and numeric generic redacted probe" }
      - { ac: "SPEC-0212/Spec-AC-01", call: compliant, citation: ".aai/scripts/pr-preflight.mjs:271; TEST-007 and combined input/name/path probes" }
      - { ac: "SPEC-0212/Spec-AC-02", call: compliant, citation: ".aai/scripts/pr-preflight.mjs:207,221; TEST-001 and byte-exact endpoint probe" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: docs/ai/overview-data.json, line: 3446, issue: "Carried N1: compatibility log attributed as layer-profiles code review", failure_scenario: "Reader follows the delivered layer-profiles review link and receives a PR434 compatibility test log with no dual review verdict for that scope" }
  cannot_verify:
    - { claim: "Current-source native Windows 5.1/pwsh7, Linux/WSL and full CI", closes_with: "New source-bound native matrix and green full CI after authorized metadata closure; old 1691 results are historical" }
    - { claim: "Final independent parent Validation and final external review sweep", closes_with: "Fresh checked parent outcome report and complete paginated thread/review sweep with replies and resolutions by the parent" }
    - { claim: "Live authenticated Azure/downstream incident and future create permission", closes_with: "Authorized live evidence and original downstream pin/logs; future writes require their own authorization and observation" }
    - { claim: "Arbitrary agent obeys the prose ceremony ordering", closes_with: "Observed ceremony execution or executable enforcement; text and scripted fixtures prove only their declared seam" }
    - { claim: "Actual serving-model weight independence", closes_with: "Harness attestation; requested model identities alone are insufficient" }
    - { claim: "Pre-replay binary index or staged-entry hash was unchanged during the earlier proof role", closes_with: "A contemporaneous pre-replay index capture, absent from its manifest; current equality does not reconstruct it" }
  overall: pass
```

# Final parent assembly review

Both verdicts PASS for this assembly gate. No new blocking finding. Existing N1 remains NON-BLOCKING with filed disposition `fu-review-log-attribution` (P3), not a claim that the catalog is fixed. This is not parent Validation PASS, complete delivery, external-thread resolution or merge authorization.

## Scope, authority and independence

One scope: `git diff bdeb425c040ada918dd97e5b878b71e420bad83a` against the actual working tree, plus the explicit evidence companions. HEAD is `8701da75a29e76e5a7897a9e327ad07f9ab38345`. STATE selects worktree mode and null inline scope. A base...HEAD-only review would omit the parent semantic amendment and integrated mutation repairs. There are 933 tracked diff paths and 33 additional pinned companions: all 966 initial hashes match, and every tracked diff path is covered. `pr434-assembly-20261008T120259Z/input-boundary.json` preserves the exact supplied inventory; `diff-summary.json` hashes the independently obtained complete binary diff without duplicating the old evidence corpus.

The full production source, shared Bash/native tests, prompt, profile and suite selection, companion harness repairs, product/technology contracts, three specs, intake/decision/roadmap/generated changes, ledger deltas, historical review and current integration proof were considered. Historical evidence is assessed through immutable references, manifest checks and relevant raw outcomes; this is not a claim to have manually read every line of 122,000 added historical evidence lines or rerun every old experiment.

Explicit authority is `docs/decisions/DECISION-pr434-identity-split.md`. The machine default proposes Validation; its supplied override orders final assembly Review, metadata-only close, source-bound native/full CI, independent parent Validation, then full external sweep. This review does not execute the default tick, invent a Validation verdict, borrow child PASS as parent PASS, reset the cap, or extend authorization to merge. Parent last_validation remains not_run.

Anti-gaming disclosure: the dispatch characterized both remaining issues as source-fixed, described evidence as GREEN/PASS, called metadata accurate and proposed interpretations of the old index claim. Those expected-outcome/coaching statements were treated as assertions to check, not evidence or scope exclusions. Prior 1691 whole-parent FAIL and old raw-SSH-package failures remain historical. This is a fresh reviewer context; requested route/actual model distinction is retained and actual serving weights are unknown. No subagent was spawned.

## Acceptance criteria and executable evidence

Evidence below is under `docs/ai/reviews/pr434-assembly-20261008T120259Z/` unless otherwise named.

| AC | Call and concrete evidence |
|---|---|
| Parent Spec-AC-01 | Compliant. TEST-001 passes real effective fetch/push equality, multiple/rewrite/blank/whitespace and branch/identity controls. Explicit malformed URLs refuse before classification. Literal SSH path and authority checks precede normalization; SCP percent bytes remain literal. Independent malformed public/unknown-host probes both refuse without providers. |
| Parent Spec-AC-02 | Compliant. TEST-002 asserts the full Azure argv vectors, environment, closed stdin, extension prerequisite, Unicode split response and matching identity. Output keeps create_permission unknown. MSI/ZIP parser controls pass locally; native process execution remains a final delivery gap. |
| Parent Spec-AC-03 | Compliant for executable local contract. TEST-003 exercises named refusal classes; TEST-004 returns timeout124 at1488ms, child_alive=false and no later probes; TEST-005 reaches the secret emitter before testing non-disclosure and tests overflow. No shell interpolation, login/install/write command or new runtime sidecar is introduced. |
| Parent Spec-AC-04 | Compliant. Prompt readiness precedes PROCESS writes and fresh STATE initialization. TEST-006 demonstrates alternate/null routes separately, then origin refusal and byte/tree/ref preservation; successful control reaches real STATE initialization. This does not attest arbitrary agent obedience to prose. |
| Parent Spec-AC-05 | Compliant. TEST-007 covers public/enterprise/SSH443, case-equivalent identity, wrong identity/host, generic/local and raw SSH fixes. Independent probes combine input/name/path casing, retain different Unicode identities, reject wrong URL path/protocol/query/userinfo, preserve numeric generic redaction and byte-exact endpoint refusal. |
| Parent Spec-AC-06 | Compliant. TEST-008 verifies core classification, selected suite, measured1287 canonical LF prompt bytes/checkpoint55539, shallow baseline independence, captured benign stderr, genuine clone failure and derived delayed/immediate/hang replay bounds. Inventory104 and companion changes match the new suite. No broad successful hygiene/framework sweep was repeated. Prior full companion checks remain separately attributed to the 1691 review, not called this review's executions. |
| SPEC-0211 Spec-AC-01 | Compliant. Equal malformed explicit URL endpoints refuse with exit2 and zero providers in current TEST-001 and independent port probes. |
| SPEC-0211 Spec-AC-02 | Compliant. TEST-007 generic and null positives reach success with no provider; numeric-port credential/query redaction positive and divergent endpoint negative pass independently. |
| SPEC-0212 Spec-AC-01 | Compliant. ASCII folding applies to both returned name and HTTPS path. TEST-007 field-wise controls and independent combined-field public/enterprise probes pass; genuinely different fields refuse after three probes. |
| SPEC-0212 Spec-AC-02 | Compliant. Input ASCII equality reaches all three exact calls; genuine differences refuse before providers. Case-only fetch/push divergence still refuses at git.push-destination before folding. |

Fresh full suite command from the named scratch checkout: `AAI_ROLE=subagent AAI_TEST_TIMEOUT=240 AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-assembly-review-scratch/fixtures bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh`, exit0, eight PASS rows, full output read (`preflight.log`). All named tests remain registered in both Bash dispatch and native extraction. Native Pester preserves nonzero status and diagnostic output under Stop; its execution on the new source is not attested here.

Independent additional command: `AAI_ROLE=subagent AAI_TEST_ISOLATION=0 AAI_TEST_TIMEOUT=90 TMPDIR=/private/tmp/aai-pr434-assembly-review-scratch AAI_PREFLIGHT_SCRATCH=/private/tmp/aai-pr434-assembly-review-scratch/fixtures bash .aai/scripts/aai-run-tests.sh node probes.cjs /private/tmp/aai-pr434-assembly-review-scratch 007`, exit0, twelve asserted probes (`probes.cjs`, `probes.log`). Initial preparation used a wrong relative evidence directory and produced MODULE_NOT_FOUND before running any probe; `probes-infra.log` preserves that infrastructure failure, not product RED. The corrected script uses absolute destinations.

All three current mutation-gate commands exit0: parent8, generic2, case2, with no degraded/unstamped/uncomparable/offending row. All12 patches independently pass git apply --check against the single scratch copy. `proof-audit.json` independently verifies all41 integration-manifest artifacts and16 preserved record/patch copies against their pre-replay pins AND shipping Git8701 bytes. The retained actual parent replay is8/8RED, zero inconclusive and zero additional restamps; generic replay is2/2RED. The initial parent inconclusive attempt remains preserved. Adapted parent TEST007 removes only nameWithOwner validation, retaining the URL check, and still triggers the intended identity failure. Child2 patch separately restores strict comparisons. No mutation was replayed or restamped in the shipping tree by this reviewer.

No undisclosed behavioral contract deviation found. The parent plan's equality semantics were amended through the ledger, owner_signoff=false. `spec-amend list --strict` exits0 because debts are disclosed and tracked, not because owner signatures exist. `fu-amend-spec-pr-capability-preflight` and both child amendment debts remain open. Child2's literal TEST001 example says org/repo while its suite uses org/Repo; independent combined-case probes exercise org/repo as well, preserving the acceptance promise.

## Evidence truth, lifecycle and warning disposition

All four base ledgers are byte-exact prefixes: EVENTS, METRICS, decisions and tests/test-runs. Initial index comparison mistakenly compared the supplied staged-entry digest with the binary index file; the retained boundary audit explicitly labels that nonmatching comparison. Correct `git ls-files --stage -z` digest matches `81a7e66098f85c68131f133a47331cfd9bee0efadcf3a15cbc1660b2a2de66d4`; cached diff and unmerged entries are empty. STATE matches the dispatch hash. Final pins are rechecked at seal.

Truthful addendum to the earlier integration result: its sentence claiming unchanged pre-replay index hash is not established by its pre-manifest, which contains no index capture. The root audit correctly qualifies this; this review independently confirms only current staged-entry equality and empty staged/conflict content. No historic hash is invented. Its earlier STATE hash is also historical: root subsequently reset/advanced runtime STATE before this dispatch. The dispatch STATE pin is the applicable freeze boundary here.

Truthful timing clarification for child specs' AC notes: statements that independent checks are outstanding describe maker-stage evidence, not current child gate status. The closed child checks are recorded in `VALIDATION-20261008T111030Z-pr-generic-url-validity.md`, `review-20261008T102859Z-pr-generic-url-validity.md`, `VALIDATION-20261008T113526Z-pr-github-case-identity.md` and `review-20261008T114239Z-pr-github-case-identity.md`. Parent gates remain distinct and owed. This addendum corrects interpretation; it does not edit frozen child promises or manufacture parent completion.

N1 is still observed at overview-data.json:3446 (also7147): a layer-profiles code-review link points to a PR434 compatibility log. Disposition: promote-to-follow-up-ref, already filed `fu-review-log-attribution` by the typed registry at2026-10-08T10:38:39Z, P3. Keep that id in parent code_review.notes. It is not accepted residual and not fixed by this review. No new follow-up was filed.

Parent intake remains implementing with an explicitly explained assembly umbrella; child lifecycle is done. Roadmap and generated historical completion surfaces are not a current parent delivery attestation. Diagnostic `docs-audit --no-event` exits0/CLEAN with eight unreadable AC tables explicitly report-only. Authorized metadata-only reconciliation still precedes final CI. Earlier full CI97PASS/6FAIL/1SKIP and1691 native results remain about their original source; neither is called green full CI for8701.

## Remaining gates and handoff

The cannot_verify list above is mandatory and prevents a delivery/merge-readiness claim. Root must perform authorized metadata-only closure/generated reconciliation, publish and obtain current-source native/full CI, commission fresh independent parent Validation, then complete paginated external review sweep/replies/resolutions. No external action was taken here. Historic eight unresolved threads are not claimed resolved by source fixes.

Only this new report and its evidence directory were written in the shipping checkout. Source, tests, specs, ledgers, STATE, lifecycle and index content stayed frozen. Report staging is returned to the parent because it explicitly owns the sole index writer. All deliberate probes used the one named scratch checkout; the first full run's canonical wrapper automatically created its own temporary isolation checkout outside that path, then cleaned it. This procedural limit is disclosed rather than claiming perfect scratch confinement; no probe ran against shipping source. Later probes disabled redundant wrapper isolation and confined TMPDIR to the named scratch root.

The typed result checker verifies handoff structure, not the truth of these verdicts. Manifest covers the report, result and all new evidence except itself; the immutable supplied boundary is included. Return only set-code-review, with the carried warning disposition. Do not set parent Validation PASS or authorize a merge.

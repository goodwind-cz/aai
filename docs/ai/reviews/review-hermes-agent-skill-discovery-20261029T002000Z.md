```yaml
review:
  scope: "main..5af9b950 plus current local remediation including untracked tests/skills/lib/hermes-skills-contract.mjs"
  spec: docs/specs/SPEC-0259-spec-hermes-agent-skill-discovery.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:70; TEST-001/002 GREEN" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:124; TEST-003 GREEN" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:151; TEST-004 GREEN" }
      - { ac: Spec-AC-04, call: compliant, citation: "tests/skills/lib/hermes-skills-smoke.py:145; TEST-005 GREEN" }
      - { ac: Spec-AC-05, call: compliant, citation: "docs/USER_GUIDE.md:165; TEST-006 native and offline GREEN" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Other Hermes revisions, Windows-native Hermes, downstream model completion and every UI presentation", closes_with: "Additional native platform/revision and live execution evidence; outside claimed support" }
    - { claim: "Original freeze-anchor drift cause and owner acceptance of its restamp", closes_with: "Existing tracked fu-amend-hermes-agent-skill-discovery owner disposition; current behavioral contract independently reviewed here" }
  overall: pass
```

security_relevant: false

# Final full-scope review after external remediation

Compliance PASS and code quality PASS. No open blocking or non-blocking findings. Model identity unavailable; no token estimate reported. No implementation or STATE writes. Review dispatch supplied paths and reference evidence without coaching.

## Scope and evidence

Base main `3778b2c83d5f6a685a5e3f1036224ebaa86eb7e1`; committed head `5af9b9500e59f207b423b28ffed43f15f536d061`; all current local changes included. STATE uses inline review; caller explicitly expands it with the new contract helper. Entire final diff reviewed, including 20 tracked changed paths and the untracked helper: SKILLS and USER_GUIDE; index, factory/overview HTML and data, skill catalog timestamp; events, decisions, roadmap; numbered CHANGE-0234 and SPEC-0259; product documentation; first review report; Python smoke; shell suite; new Node documentation contract; suite map/weights and hygiene pins. Generated companions reflect delivery, dates and ledger contents; no production adapter or sync writer introduced. Ledger changes remain appends.

Fresh reviewer command (exit 0): `AAI_ROLE=subagent AAI_HERMES_SOURCE=/Users/ales/.hermes/hermes-agent AAI_HERMES_PYTHON=/Users/ales/.hermes/installs/de9aef5118c0fdd8/environments/3138bc2b34a540d8b91fc3df21e4db8d/venv/bin/python bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-hermes-skills.sh`. Output in `/tmp/hermes-review-native-2.log`: two offline contract checks and all six native tests GREEN; negative controls bite. Runtime remains observed Hermes SHA `bf0203a794a07aac3ff764972ab9087baa4e4f4e` on macOS.

Fresh weight audit (exit 0): `AAI_ROLE=subagent bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-suite-select.sh test_1804_weights_refresh_audit`; log `/tmp/hermes-review-weight-2.log` reports exact coverage and explicit provenance PASS. `git diff --check` and `node .aai/scripts/sync-harness-skills.mjs --check` exit 0. Corroborating durable local evidence is `docs/ai/reports/VALIDATION-hermes-independent-3.md` and its native/offline/weight logs. Public product evidence now targets the tracked first review report, so consumers do not need local ignored logs to follow the verification link.

## Acceptance walk

| AC | Result | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | TEST-001/002 exact native catalog and descriptions, trust/untrust, missing wrapper, nested cwd. |
| Spec-AC-02 | compliant | TEST-003 native invocation expands wrapper; project prompt exists with source bytes; invalid pointer fails. |
| Spec-AC-03 | compliant | TEST-004 repeated real sync and native reload produce changed metadata once; omitted sync fails. |
| Spec-AC-04 | compliant | TEST-005 preserves unrelated project/profile bytes; parity passes; mutation fails. |
| Spec-AC-05 | compliant | TEST-006 checks guide contract and native procedure; new offline checks ensure guide-only selection and durable product evidence. |

All six declared tests exist and pass. The current numbered spec retains the acceptance behavior reviewed in the earlier draft. No functional deviation found. The disclosed restamp follow-up remains open; this report does not certify its unknown historical cause or provide owner sign-off.

## External findings and remediation

- Comment 4407415793: real and fixed by `tests/skills/suite-map.yaml:1417`; guide-only changes now select Hermes. The new contract helper checks the exact selector output.
- Comment 4407415798: real and fixed at `docs/product/hermes-agent-skill-discovery.md:49`; the link names tracked review evidence. The helper checks existence and tracked status in the isolated checkout.
- CI suite weight provenance failure: real and fixed at `tests/skills/suite-weights.tsv:251`; explicit unsampled fallback 212 replaces an unsupported CI measurement claim. Fresh audit passes.

Falling-first external regressions are recorded in `docs/ai/tdd/hermes-external-review-red.log`; CI failure in `docs/ai/tdd/hermes-external-review-ci-red.log`; GREEN logs and independent validation corroborate fixes. Offline assertions run before the native-availability exit, so a missing Hermes runtime cannot hide these regressions. `--docs-only` explicitly disclaims native execution.

## Disposition and limits

No new WARNING disposition is required. Existing `fu-amend-hermes-agent-skill-discovery` remains the tracked owner-signature obligation, not waived by this review. Windows-native Hermes, other revisions and model execution remain outside support proof. Orchestrator should stage this report, apply the returned review command, commit the remediation, and reply to external threads with the fixing SHA and regression evidence. Hosted CI on that fixing SHA remains a separate PR gate.

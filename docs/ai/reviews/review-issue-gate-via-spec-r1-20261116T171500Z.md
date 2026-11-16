# Code Review: issue-gate-via-spec (round 1)

Reviewer: independent subagent (claude-opus-5-5, effort high), dispatched per .aai/SKILL_CODE_REVIEW.prompt.md (prompt_hash 8e6aae0d5197). Report returned inline; saved by the orchestrator.

security_relevant: false

```yaml
review:
  scope: "git diff origin/main (c1034b24) -- .aai/scripts/lib/docs-audit-core.mjs .aai/scripts/docs-audit.mjs .aai/templates/git-hooks/pre-commit-index.sh tests/skills/test-aai-docs-audit.sh tests/skills/suite-map.yaml CHANGELOG.md, plus untracked docs/product/docs-close-gate.md docs/issues/ISSUE-0120-issue-gate-via-spec.md docs/specs/SPEC-0297-spec-issue-gate-via-spec.md"
  spec: docs/specs/SPEC-0297-spec-issue-gate-via-spec.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "docs-audit-core.mjs gateViaLinkedSpecs/gateDoc; docs-audit.mjs emitGate; TEST-3801 green" }
      - { ac: Spec-AC-02, call: compliant, citation: "prefixed spec reasons + Decided by line; TEST-3802 green" }
      - { ac: Spec-AC-03, call: compliant, citation: "no linked spec reason, dangling and non-spec links.spec reasons; TEST-3803 green" }
      - { ac: Spec-AC-04, call: compliant, citation: "delegation requires missingTable and type != spec; corpus diff: 294 specs + 5 own-table docs byte-identical; TEST-3804 green" }
      - { ac: Spec-AC-05, call: compliant, citation: "gateFile identity lookup; TEST-3805 green; absolute temp-path repro rc 0" }
      - { ac: Spec-AC-06, call: compliant, citation: "pre-commit-index.sh filter widened; TEST-3806 green" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-3807 green; live --gate ISSUE-0115/0118 rc 0" }
      - { ac: Spec-AC-08, call: compliant, citation: "CHANGELOG.md heading; docs/product/docs-close-gate.md; TEST-3808 green" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, id: B1, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "gateViaLinkedSpecs passes an RFC/PRD whose own Rollout Status declares unfinished phases once every spec linked so far passes; closeoutCandidatesFor refuses that parent for exactly that reason", failure_scenario: "live tree: --gate RFC-0012 / RFC-0016 / RFC-0017 exit 0 via linked specs while hasUnfinishedRolloutPhases() is true; base c1034b24 exits 1; under close_gate enforce the widened hook (docs/rfc/) accepts a premature umbrella done-flip" }
      - { rank: NON-BLOCKING, id: NB1, file: .aai/templates/git-hooks/pre-commit-index.sh, issue: "docs/releases/ joins the gated set but release plans have no AC table and nothing links a spec to them", failure_scenario: "close_gate enforce: every REL done-flip aborts with no way to satisfy the gate (REL-0001 rc 1, no linked spec)" }
      - { rank: NON-BLOCKING, id: NB2, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "a path-valued links.spec is reported as resolving to 0 scanned docs, then 'no spec is linked to it'", failure_scenario: "CHANGE-0096, CHANGE-0214, CHANGE-0215" }
      - { rank: NON-BLOCKING, id: NB3, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "no test covers the lean ceremony 0/1 missingTable delegation or the rule that the doc's own non-table reasons still count", failure_scenario: "a mutation dropping either survives TEST-3801..3808; real case CHANGE-0127" }
      - { rank: INFO, issue: "product doc Validation evidence link is a placeholder; TEST-3806 abort assertion greps only the id" }
  cannot_verify:
    - { claim: "effect on downstream corpora under close_gate enforce", closes_with: "--gate-file over a downstream docs/ tree" }
    - { claim: "full-sweep regression across other hook-committing suites", closes_with: "the planned full sweep" }
    - { claim: "mutation records reflect current test bodies", closes_with: "mutation-gate.mjs on the branch head" }
  overall: fail
```

## What the reviewer ran

- `--gate-file` on all 715 governed docs with base c1034b24 scripts and with the branch: no doc went pass to fail; all 294 specs and the 5 own-table docs produce byte-identical output; done docs under docs/issues/ passing: 5 of 349 base, 126 of 349 branch.
- Live `--gate ISSUE-0115`, `ISSUE-0118` pass via SPEC-0292, SPEC-0295; a temp copy of ISSUE-0118 at an absolute path outside the repo passes `--gate-file`.
- Dedupe and list-valued links scratch repro: one spec gated once.
- test_3801..test_3808 each rc 0; full test-aai-docs-audit.sh rc 0; test-aai-git-hook-templates.sh rc 0; spec-amend list --strict rc 0; spec-lint PASS.
- B1 hermetic repro: RFC with rollout phase 2 planned and one reconciled spec linking via links.rfc: branch rc 0, base rc 1.

Verdict: FAIL. spec_compliance pass, code_quality fail (1 BLOCKING, 3 NON-BLOCKING).

## Orchestrator dispositions

- B1: remediate in tree (round 2) via an additive spec amendment (D1 rollout carve; new TEST-3809), standing decision (a): hazard introduced by the feature under delivery.
- NB1: remediate in tree: drop docs/releases/ from the hook filter (release plans have no acceptance-table convention); D4 amended.
- NB2: remediate in tree: a links.spec value equal to a scanned doc's repo path resolves to that doc (new TEST-3810 arm).
- NB3: remediate in tree: TEST-3810 covers the lean ceremony delegation and kept own reasons.
- INFO: product doc link fixed; TEST-3806 assertion tightened.

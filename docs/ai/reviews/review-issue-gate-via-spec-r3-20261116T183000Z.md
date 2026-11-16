# Code Review: issue-gate-via-spec (round 3, full recheck)

Reviewer: independent subagent (claude-opus-5-5, effort high), per .aai/SKILL_CODE_REVIEW.prompt.md (prompt_hash 8e6aae0d5197). Report returned inline; saved by the orchestrator.

security_relevant: false

```yaml
review:
  scope: "git diff origin/main (c1034b24)..fix/issue-gate-via-spec (a4678ac7, 394bc533) plus untracked intake and spec"
  spec: docs/specs/SPEC-0297-spec-issue-gate-via-spec.md
  spec_compliance:
    verdict: fail
    ac_walk: "Spec-AC-01..11 compliant on their tests (TEST-3801..3811 rc 0)"
    deviations:
      - "D1 as amended ('a table counts as the doc's own as soon as it declares a Spec-AC-NN row') is implemented only for tables parseAcTable/parseLeanAcTable already recognise"
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, id: B1, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "missingTable keys on ac.declaredIds / lean.declaredIds, filled only after the parser accepted the table heading and header shape; a non-spec doc whose own Spec-AC table the parser does not recognise (no Review-By column at L2; lean table at implicit L2; lean table with a 'State' column at L1) still delegates; its own non-terminal row is ignored", failure_scenario: "three change docs each with own row 'Spec-AC-01 | own row | implementing' and a reconciled linked spec: branch --gate rc 0 'GATE PASS via linked spec(s)'; base c1034b24 rc 1; --gate-file likewise (enforce hook would accept)", backed_by: "scratchpad cr3-igs/repro-b1.sh" }
      - { rank: NON-BLOCKING, id: NB1, file: docs/product/docs-close-gate.md, issue: "evidence link points at the r2 report; Limits line overstates own-table handling while B1 stands" }
  cannot_verify:
    - "full sweep at the head carrying 394bc533"
    - "downstream corpora under close_gate enforce"
    - "mutation records current at 394bc533"
  overall: fail
```

Round-1 and round-2 findings verified fixed; this B1 is the remainder of round-2 B1's class.

Verdict: FAIL (1 BLOCKING, 1 NON-BLOCKING). This is the third finding-bearing round (cap 2 + one standing-a extension): the ride stops for an owner decision.

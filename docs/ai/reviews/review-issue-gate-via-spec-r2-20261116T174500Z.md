# Code Review: issue-gate-via-spec (round 2, full recheck)

Reviewer: independent subagent (claude-opus-5-5, effort high), per .aai/SKILL_CODE_REVIEW.prompt.md (prompt_hash 8e6aae0d5197). Report returned inline; saved by the orchestrator.

security_relevant: false

```yaml
review:
  scope: "git diff origin/main (c1034b24), paths .aai/scripts/lib/docs-audit-core.mjs .aai/scripts/docs-audit.mjs .aai/templates/git-hooks/pre-commit-index.sh tests/skills/test-aai-docs-audit.sh tests/skills/suite-map.yaml CHANGELOG.md docs/ai/decisions.jsonl docs/ai/EVENTS.jsonl, plus untracked docs/product/docs-close-gate.md, the intake, the spec, the r1 review report"
  spec: docs/specs/SPEC-0297-spec-issue-gate-via-spec.md
  spec_compliance:
    verdict: pass
    ac_walk: "Spec-AC-01..10 compliant (TEST-3801..3810 rc 0; live --gate ISSUE-0118 rc 0, RFC-0012 rc 1 with the Rollout reason, CHANGE-0096 rc 0 via SPEC-0103)"
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, id: B1, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "missingTable was set when the doc HAS its own AC table but the parser dropped every declared row (escaped or raw pipe, cell-count mismatch); gateDoc/gateFile then delegated to linked specs and ignored the doc's own non-terminal rows; lean path same", failure_scenario: "change doc with an own table whose only row 'Spec-AC-01 | handles a \\| pipe | implementing' plus a reconciled spec linking it: branch --gate rc 0 'GATE PASS via linked spec(s)'; base c1034b24 rc 1; --gate-file likewise, so the enforce hook would accept the flip" }
      - { rank: NON-BLOCKING, id: NB1, issue: "spec D4 claims a close-work-item gate follow-up is recorded; none existed" }
      - { rank: NON-BLOCKING, id: NB2, issue: "no test pins the docs/releases/ exclusion of the hook filter" }
      - { rank: INFO, issue: "hook header comment still said 'for each staged spec'" }
      - { rank: INFO, issue: "gateFile runs a full scan per staged non-spec doc without a table; fine for close commits" }
  cannot_verify:
    - "downstream corpora under close_gate enforce after hook reinstall"
    - "other hook-committing suites (owed full sweep)"
    - "base-side live counts (reviewer reproduced branch side: 129 of 349 done issue docs pass)"
  overall: fail
```

Round-1 findings B1, NB1, NB2, NB3 and both INFO items verified fixed.

Verdict: FAIL. spec_compliance pass, code_quality fail (1 BLOCKING, 2 NON-BLOCKING).

## Orchestrator dispositions

- B1: remediated in tree (round 3): missingTable only when the doc declares no Spec-AC row (canonical and lean); D1 clarified by additive amendment; Spec-AC-11 / TEST-3811 with mutation record.
- NB1: filed `fu-gate-not-called-by-close-item` (P3); D4 now names it.
- NB2: remediated: TEST-3806 gains a docs/releases/ arm.
- INFO: hook header comment updated; scan cost accepted (close commits flip one or two docs).

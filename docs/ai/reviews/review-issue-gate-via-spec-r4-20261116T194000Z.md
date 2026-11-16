# Code Review: issue-gate-via-spec (final round, full recheck)

Reviewer: independent subagent (claude-opus-5-5, effort high), per .aai/SKILL_CODE_REVIEW.prompt.md (prompt_hash 8e6aae0d5197). Report returned inline; saved by the orchestrator.

security_relevant: false

```yaml
review:
  scope: "git diff origin/main (c1034b24)..fix/issue-gate-via-spec (ff090e6c) plus untracked intake/spec"
  spec: docs/specs/SPEC-0297-spec-issue-gate-via-spec.md
  spec_compliance:
    verdict: pass
    ac_walk: "Spec-AC-01..12 compliant (TEST-3801..3812 rc 0; live ISSUE-0115/0118 rc 0 via SPEC-0292/0295; RFC-0012 rc 1; CHANGE-0096 rc 0 via SPEC-0103; corpus sweep 748 docs pass->fail 0, spec-type diffs 0)"
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, id: NB1, file: .aai/scripts/lib/docs-audit-core.mjs, issue: "an own AC status table whose rows are numbered AC-NNN (not Spec-AC-NN) is not counted as the doc's own; a non-terminal own row is ignored and the doc passes via its spec (repro ISSUE-7001: base rc 1, head rc 0); matches D1; 5 corpus docs use the shape, all rows done" }
      - { rank: NON-BLOCKING, id: NB2, file: docs/product/docs-close-gate.md, issue: "the hook gates an intake flip against the working-tree spec; when the spec is not done-flipped in the same commit no staged gate of it runs; the product doc and spec R2 overstate; not a regression (base never gated issue flips)" }
      - { rank: INFO, issue: "gateFile runs a full scan per staged non-spec doc without a table (acceptable at close-commit sizes)" }
  cannot_verify:
    - "downstream enforce behaviour on an aai-sync'd consumer close commit"
    - "CI green on the PR head"
  overall: pass
```

All prior-round findings (r1 B1/NB1-3, r2 B1/NB1-2, r3 B1/NB1, validation r4 NB-F1/NB-F2) verified fixed.

Verdict: PASS (spec_compliance pass, code_quality pass, 0 BLOCKING, 2 NON-BLOCKING).

## Orchestrator dispositions

- NB1: follow-up `fu-gate-ac-nnn-own-table` (P3).
- NB2: product doc wording corrected in tree; follow-up `fu-hook-gate-reads-worktree-spec` (P3) for reading linked specs from the index.

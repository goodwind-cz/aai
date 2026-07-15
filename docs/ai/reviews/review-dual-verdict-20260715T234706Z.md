# Code Review — single dual-verdict rewrite (spec-single-dual-verdict-review)

**Reviewer:** Code Review role (claude-fable-5), independent, dogfooding the NEW
single dual-verdict prompt (.aai/SKILL_CODE_REVIEW.prompt.md, worktree version)
on its own delivery.

```yaml
review:
  scope: "worktree: dual-verdict diff (main...feat/dual-verdict-review, uncommitted; 12 modified + 1 new file)"
  spec: docs/specs/SPEC-DRAFT-single-dual-verdict-review.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/SKILL_CODE_REVIEW.prompt.md = 213 lines (live re-run of test_040: PASS '213 lines, anchors present, scaffolding gone'); dual-verdict block at prompt lines 62-95 + YAML schema 107-126; negative markers (Stage 1/2, parseDiff, jsChecks, code-review-config.json, CI YAML, Troubleshooting) absent — confirmed by grep and by heading diff vs git HEAD version; RED evidence docs/ai/tdd/red-20260715T232618Z-dual-verdict.log shows all three stanzas failing pre-change" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "preflight prompt:25-52; H6 warnings policy prompt:161-175; H3 External Review Response prompt:177-205; docs/ai/reviews/ + set-code-review prompt:99,137; never-docs/validation prompt:99-103; report staging prompt:154-159; pre-existing anchors test_011/test_012/test_014 re-run live: PASS" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/SUBAGENT_PROTOCOL.md:31-56 carries all three rules (no coaching / read-only reviewer / ref-path handoff) at the MODEL-field tier; test_041 green live; RED log shows pre-change failure" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".claude/.codex/.gemini skills/aai-code-review/SKILL.md:3 all name the dual-verdict pass + cannot_verify; .aai/roles/ROLES.md:71-86 stage wording gone; .aai/AGENTS.md:86 index line updated; test_042 green live. AC as written covers exactly these surfaces — wider prompt-layer drift filed under code_quality NB-1" }
      - { ac: Spec-AC-05, call: compliant,
          citation: "deferred with future Review-By manual:2026-08-31 (terminal for freeze per the spec's gate rules); surfaced in docs/INDEX.md:85-88 deferred-items table; measurement itself is by construction not verifiable now — see cannot_verify" }
      - { ac: Spec-AC-06, call: compliant,
          citation: "docs/ai/tdd/sweep-20260715T233105Z-dual-verdict.log: 7 suites exit 0, strict audit CLEAN, index idempotent modulo Generated stamp, check-state OK; hygiene pack independently re-executed by this reviewer: all tests PASS" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/REMEDIATION.prompt.md, line: 31,
          issue: "F1-class cross-surface drift remains on orchestration-facing prompts: REMEDIATION.prompt.md:31-32,37 still names 'Code Review Stage 1 spec non-compliance' / 'Code Review Stage 2 ERROR findings'; .aai/SKILL_TDD.prompt.md:325 'ERROR findings block merge/PR readiness'; .aai/workflow/WORKFLOW.md:63 stop condition 'Code Review ERROR findings'; .aai/ORCHESTRATION_HITL.prompt.md:22 'Code Review ERROR findings need a fix/waiver decision'; .aai/scripts/orchestration-dispatch.mjs:166 stop_condition '(ERROR findings block readiness)'; .aai/system/AUTONOMOUS_LOOP.md:22 and .aai/system/SUPERPOWERS_INTEGRATION.md:67-73,124-125,238 still describe the two-stage flow. The new prompt emits only BLOCKING/NON-BLOCKING; 'Stage 1/2' and 'ERROR' findings can never appear in a report again.",
          failure_scenario: "review FAILs with a BLOCKING finding -> orchestrator dispatches Remediation -> REMEDIATION.prompt.md's failure taxonomy (step 2) offers only Stage-1/Stage-2/ERROR buckets that match nothing in the report -> the remediation agent mis-buckets the finding or raises an unnecessary HITL. Routing itself survives (dispatch keys on code_review.status, not labels), hence NON-BLOCKING." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_CODE_REVIEW.prompt.md, line: 14,
          issue: "STATE-write authority stated three different ways by three surfaces touched or cited by this change: prompt:14-16 grants the reviewer the STATE code_review write unconditionally ('write ONLY the review report ... and the STATE code_review block via the CLI below'; STATE CONTRACT:134 calls it PRIMARY PATH); the new SUBAGENT_PROTOCOL.md:47-51 permits reviewer set-code-review only 'when it is the sole agent' (single-writer rule, protocol:118-124: a dispatched subagent MUST NOT write STATE.yaml); orchestration-dispatch.mjs:165 expected_outputs meanwhile tells the dispatched reviewer 'verdict via state.mjs set-code-review'.",
          failure_scenario: "parallel mode (K>=2): Code Review dispatched as a subagent follows its own prompt's PRIMARY PATH and runs set-code-review concurrently with the orchestrator's STATE merge — the lost-update race the single-writer rule exists to prevent. Mitigated by the transactional CLI (SPEC-0012), but a fresh reviewer cannot tell which of the three instructions wins." }
  cannot_verify:
    - { claim: "Real-world review quality/efficiency parity of the single-pass prompt vs the two-stage history (the RES-0001 F4 'equal quality at ~50% tokens / ~2x speed' claim is imported, not demonstrated by this diff)",
        closes_with: "the deferred Spec-AC-05 measurement gate: METRICS.jsonl comparison of review tokens, wall-clock, and remediation cycles over the next 5 reviewed scopes; Review-By manual:2026-08-31" }
    - { claim: "That the .codex and .gemini runtimes actually surface the rewritten wrapper descriptions to their users (only the file text is verifiable here)",
        closes_with: "a smoke invocation of /aai-code-review in each third-party tool" }
    - { claim: "That a reviewer under a coaching dispatch will actually detect and record the attempt — anti-gaming rule 1 is behavioral and has no mechanical check (test_041 verifies the rule's text, not its enforcement)",
        closes_with: "observed review dispatches during the Spec-AC-05 measurement window; optionally a dispatch-lint stanza later" }
  overall: pass
```

## Scope and method

- Scope: uncommitted worktree diff on branch feat/dual-verdict-review
  (12 modified files + new docs/specs/SPEC-DRAFT-single-dual-verdict-review.md,
  read in full). Base main, head = working tree.
- Frozen spec: docs/specs/SPEC-DRAFT-single-dual-verdict-review.md
  (SPEC-FROZEN: true); RFC docs/rfc/RFC-DRAFT-single-dual-verdict-review.md
  (accepted) read for intent.
- Independent re-execution: tests/skills/test-aai-hygiene-pack.sh run by this
  reviewer — all tests PASS including test_040/041/042; prompt is 213 lines.
- Validation context: prior independent validation PASS with one finding (F1,
  cross-surface GitHub-post drift). F1 remediation verified in-tree: the
  .codex/.gemini wrapper descriptions no longer advertise posting to GitHub,
  docs/USER_GUIDE.md:493-505 drops --post and carries the dual-verdict contract
  with BLOCKING/NON-BLOCKING labels; dispositions recorded in the SPEC
  (lines 212-222). USER_GUIDE text checked against the new prompt: accurate
  (the omission of INFO from the severity list matches the SPEC's ACCEPTED
  disposition — INFO lives in the report body, never gates).

## Anti-gaming rule 1 disclosure (recorded per the contract)

This review's dispatch prompt directed attention to specific defect classes
and grep targets ("anchor-grep coupling", named anchors, "USER_GUIDE rewrite
accuracy"). That is scope direction bordering on the coaching the new
protocol forbids; recorded here as required, and the full diff was reviewed
regardless of the suggested focus areas. No pre-rating of severity and no
scope exclusions were present. Notably the anchor-coupling hunt it suggested
came back mostly clean (no other test suite greps the review prompt; the
preserved H3/H4/H6 anchors are intact), while the real drift (NB-1) sits in
prompts the dispatch did not name.

## Warning dispositions (H6)

Both findings are NON-BLOCKING WARNINGs and need a disposition before
closeout (remediate, decisions.jsonl entry, or tracked follow-up ref):

- NB-1 (stale Stage/ERROR vocabulary in REMEDIATION / SKILL_TDD / WORKFLOW /
  ORCHESTRATION_HITL / orchestration-dispatch.mjs / system docs):
  recommended disposition = tracked follow-up ref (a small CHANGE aligning
  the remaining orchestration-facing surfaces to BLOCKING/NON-BLOCKING and
  the single-pass shape; grep list is in the finding). Out of the frozen
  SPEC's Spec-AC-04 scope, so remediating in this branch would be scope creep.
- NB-2 (STATE-write authority: prompt unconditional vs protocol
  sole-agent-only vs dispatch template): recommended disposition =
  decisions.jsonl entry choosing one rule (the dispatch-template convention
  "reviewer records via the transactional CLI" appears to be the de facto
  winner) and a one-line alignment edit to whichever surface loses.

## Next steps

1. Operator: record the two dispositions above (follow-up ref for NB-1,
   decision or alignment edit for NB-2) before closeout, then proceed to PR.
2. Spec-AC-05 measurement gate stays open: check at wrap-up once 5 post-change
   reviewed scopes exist in docs/ai/METRICS.jsonl (Review-By 2026-08-31).

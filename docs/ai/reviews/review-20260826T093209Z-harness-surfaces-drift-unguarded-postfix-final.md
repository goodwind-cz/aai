```yaml
review:
  scope: "main...2ec19db102c35686e43f236b1a1ccdbc718b3b1c plus complete working tree at 2026-08-26T09:31Z"
  spec: docs/specs/SPEC-0154-spec-harness-surfaces-drift-unguarded.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "TEST-001 / test_110; fresh hygiene-pack PASS, 39 skills" }
      - { ac: Spec-AC-02, call: compliant, citation: "TEST-002,003 / test_111; generator --check exit 0 and idempotence PASS" }
      - { ac: Spec-AC-03, call: compliant, citation: "TEST-004 / test_112; sync-harness-skills.mjs:120-137,250-268" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-006 / test_110..115 registered in hygiene-pack main; fresh suite PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "TEST-007 / test_113 fresh PASS with control plus three mutations" }
      - { ac: Spec-AC-06, call: compliant, citation: "TEST-005 / test_110 and test_112; shipped exclusions empty" }
      - { ac: Spec-AC-07, call: compliant, citation: "TEST-008 / test_114; .cursor/rules/aai.mdc:1-32 and official Cursor docs" }
      - { ac: Spec-AC-08, call: compliant, citation: "TEST-009 / test_115; AGENTS.md:1 and HARNESS_SKILLS.yaml:35-53" }
      - { ac: Spec-AC-09, call: compliant, citation: "TEST-010 / test-aai-suite-select.sh:test_020; prior fresh scoped PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-011..014; committed 81/81 at 2ec19db plus fresh postfix hygiene-pack PASS; validation R1 named" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/sync-harness-skills.mjs, line: 350, issue: "--write can follow a mirror skill-directory symlink outside the mirror tree.", failure_scenario: "An expected mirror skill path is a symlink to another writable directory; --write creates or overwrites SKILL.md there. Disposition recorded as typed P3 follow-up fu-harness-sync-symlink-containment." }
  cannot_verify:
    - { claim: "A complete post-postfix 81-suite framework run", closes_with: "A current-tree test-framework.sh run completing 81/81; validation timeboxed its attempt after 11 passing suites" }
    - { claim: "Actual discovery, deduplication, and precedence in installed Cursor, Codex, and Gemini clients", closes_with: "End-to-end smoke in each supported client" }
  overall: pass
```

# Final postfix Code Review — harness-surfaces-drift-unguarded

Both verdicts pass. NB-1 is closed; NB-2 remains a NON-BLOCKING code-quality finding with its required H6 artifact recorded.

## Scope preflight and anti-coaching record

The exact scope is `main...2ec19db102c35686e43f236b1a1ccdbc718b3b1c` plus the complete working tree: postfix implementation/test edits, append-only EVENTS and decisions lines, the prior review, and the postfix validation report. Branch and merge base remain `fix/harness-surface-parity` and `17caf5d26e861a9e2d546c39076fab4bf19b29f8`.

The dispatch characterized the expected postfix outcomes (NB-1 fixed, NB-2 recorded). I treated those as claims to disprove, not findings to suppress: read the complete current diff, re-ran all four malformed CLI forms, ran the complete hygiene suite, checked the typed ledger record, and retained NB-2 as an open finding.

`main` remains a byte-exact prefix of EVENTS, decisions, and test-runs. The working changes add two EVENTS verdicts total and the typed NB-2 follow-up without rewriting prior bytes. `git diff --check` is clean.

## Verdict 1 — spec_compliance: PASS

| AC | Call | Evidence |
|---|---|---|
| Spec-AC-01 | compliant | `test_110` fresh PASS; all three mirrors carry the 39-source-skill set. |
| Spec-AC-02 | compliant | Generator `--check` fresh exit 0; `test_111` fresh PASS covers no-op write and README set. |
| Spec-AC-03 | compliant | `test_112` fresh PASS. The postfix `valueAfter()` also makes malformed path-valued flags fail closed at parsing. |
| Spec-AC-04 | compliant | `test_110`..`test_115` remain registered and the full hygiene suite passes. |
| Spec-AC-05 | compliant | Fresh `test_113` PASS supplies the control and three independent bite proofs. |
| Spec-AC-06 | compliant | `test_110`/`test_112` fresh PASS; exclusions remain empty in the shipped manifest. |
| Spec-AC-07 | compliant | `test_114` fresh PASS; the current 32-line Cursor rule remains aligned with the official rules/skills contracts reviewed in the full-scope pass. |
| Spec-AC-08 | compliant | `test_115` fresh PASS; root title and D2/D3 record are unchanged. |
| Spec-AC-09 | compliant | `test_020` passed in the preceding full-scope review and postfix validation; the postfix delta does not touch selector code or map rows. |
| Spec-AC-10 | compliant | The committed final-HEAD framework proof is 81/81; every postfix-touched behavior is covered by a fresh complete hygiene run. R1 below names the missing broad rerun honestly. |

All required TEST-001..014 still exist and have passing evidence. AC/Test table cells remain `planned`/`pending` under the open-doc AC-flip deferral and must be filled by close ceremony.

## NB-1 remediation verification

`.aai/scripts/sync-harness-skills.mjs:252-255` rejects an absent or option-shaped value before either default can activate. Independent direct results:

```text
--check --root       -> exit 2, --root requires a value
--root --check       -> exit 2, --root requires a value
--check --manifest   -> exit 2, --manifest requires a value
--manifest --check   -> exit 2, --manifest requires a value
```

`tests/skills/test-aai-hygiene-pack.sh:1869-1887` covers the same four cases and asserts both exit 2 and the flag-specific message. The fresh whole hygiene suite exits 0. NB-1 is closed with no new parser defect found.

## Verdict 2 — code_quality: PASS

No BLOCKING finding.

NB-2 remains real at `.aai/scripts/sync-harness-skills.mjs:350`: `--write` can follow an expected skill-directory symlink and write `SKILL.md` outside the mirror. Its concrete scenario and rank are unchanged. H6 is now satisfied by the append-only typed record `fu-harness-sync-symlink-containment` (P3) in `docs/ai/decisions.jsonl`, which names the failure, rationale, and originating review. No additional warning was found in the postfix delta.

## Cannot verify / validation R1

- R1: postfix validation began a current-tree full framework run but timeboxed it after 11 completed passing suites. The broad proof therefore remains the committed 81/81 run at `2ec19db`; a new completed 81/81 run would close this assurance gap. This does not block because the only behavioral postfix is parser-local and its owning full hygiene suite passed independently in both Validation and this review.
- Installed-client discovery/dedup/precedence remains externally unexercised. Repository parity and current vendor documentation do not substitute for client smokes.

## Evidence and next step

- Generator `--check`: exit 0.
- Four malformed CLI probes: exit 2 with correct messages.
- Canonical-wrapper hygiene suite: exit 0, including `test_110`..`test_115` and postfix `test_112(d)`.
- Ledger prefix checks: all three pass.
- Postfix validation: PASS with R1, no blocking category.

Overall: **PASS**. NB-2 is durably dispositioned as `fu-harness-sync-symlink-containment`; close ceremony may proceed while retaining R1 in the record.

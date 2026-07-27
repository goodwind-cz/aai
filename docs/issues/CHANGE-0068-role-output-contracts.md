---
id: role-output-contracts
number: 68
type: change
status: draft
links:
  pr: []
  commits: []
---

# Change — Role output contracts: deterministic EXPECT validation of subagent result blocks

## Summary
- Adopt Promptbook's EXPECT mechanism (analysis extension 2026-07-27,
  candidate 1): declare a small set of deterministic postconditions on
  dispatched-role outputs in .aai/SUBAGENT_CONTRACT.md, add
  .aai/scripts/check-role-output.mjs that validates a result block WITHOUT
  any LLM call, and EXAMPLE fixtures per role class run by a CI-suite
  stanza — so format drift is caught for cents before the expensive merge/
  review path.

## Motivation / Business Value
- This session repeatedly lost wall-clock to malformed/incomplete subagent
  returns (stalls, missing blocks) that only a human/LLM read could catch.
  A deterministic pre-merge check converts those into instant cheap
  rejections with a precise reason.
- Promptbook's test-books.yml proves the EXAMPLE-as-CI-fixture pattern for
  natural-language contracts.

## Scope
- In scope:
  - SUBAGENT_CONTRACT.md: an EXPECT block (~6 declarations): parseable
    YAML result block present; required fields (scope, role, status,
    started_utc, ended_utc, duration_seconds, evidence, files_changed,
    blockers); status enum PASS/FAIL/BLOCKED; >= 1 evidence entry with
    integer exit_code; ISO-8601 UTC timestamps; duration == ended-started
    (+/-1s tolerance mirroring the existing timing rule).
  - .aai/scripts/check-role-output.mjs: stdin/file input, extracts the
    LAST ```yaml subagent_result fence from a role's final message text,
    validates per the EXPECT set, exit 0 clean / 1 violations (one line
    per violation, machine-parseable prefix), no dependencies (line-based
    YAML subset parser consistent with repo practice).
  - EXAMPLE fixtures tests/fixtures/role-outputs/: one valid + one
    violating sample per class (implementation, validation, review,
    planning) used by a new suite tests/skills/test-aai-role-output.sh.
  - Orchestration wiring: SUBAGENT_PROTOCOL merge protocol step 1 gains
    the mandatory check invocation (reject-and-re-prompt once before any
    STATE merge); prompt-diet ledger true-up for corpus bytes.
- Out of scope: semantic/quality judgment (stays with validation/review);
  auto-repair of malformed blocks; changes to the result block schema.

## Affected Area
- .aai/SUBAGENT_CONTRACT.md, .aai/SUBAGENT_PROTOCOL.md (merge step),
  new .aai/scripts/check-role-output.mjs, tests/fixtures/role-outputs/,
  new tests/skills/test-aai-role-output.sh, PROFILES, prompt-diet ledger.

## Desired Behavior (To-Be)
- Orchestrator runs the checker on every returned result block; a clean
  block proceeds to merge; a violating block is rejected with precise
  machine-readable reasons and one re-prompt; CI keeps the contract and
  fixtures honest.

## Acceptance Criteria
- AC-001: checker accepts all valid fixtures and rejects each violating
  fixture with the expected violation code (suite-verified, one code per
  fixture class).
- AC-002: checker is deterministic and LLM-free (no network, no model
  deps; suite runs it twice, identical output).
- AC-003: timestamps/duration rule enforced with the documented +/-1s
  tolerance; future-started (>300s) rejected mirroring the existing
  protocol rule.
- AC-004: SUBAGENT_CONTRACT EXPECT block and PROTOCOL merge-step wiring
  present (grep contracts); ledger true-up recorded; PROFILES classifies
  the new script (core) and suite.
- AC-005: no regression — new suite + docs-lock + hygiene-pack green
  locally; full run on PR CI.

## Verification
- bash tests/skills/test-aai-role-output.sh (new)
- bash tests/skills/test-aai-docs-lock.sh; bash tests/skills/test-aai-hygiene-pack.sh
- PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Ceremony L2 expected (contract/protocol/tests not protected — verify).
- The checker must tolerate result blocks with EXTRA extension fields
  (rides add scope-specific fields) — validate the required core only.
- Corpus growth in SUBAGENT_CONTRACT/PROTOCOL must stay pointer-thin;
  ledger true-up mandatory.

## Notes
- Source: Promptbook analysis extension (session journal), adoption
  candidate 1; EXPECT/EXAMPLE precedent examples/pipelines + test-books.yml.
  Autopilot intake: metrics question skipped, human_time_minutes null.

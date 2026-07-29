---
id: contract-headroom
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — SUBAGENT_CONTRACT 60-line headroom

## Summary
- `.aai/SUBAGENT_CONTRACT.md` sat at exactly 60/60 lines against SPEC-0094's
  hard `<=60`-line cap (enforced by `tests/skills/test-aai-role-output.sh`
  TEST-010 and `tests/skills/test-aai-hygiene-pack.sh` TEST-001). Zero headroom
  means the next contract clause addition silently breaches the cap. Trim the
  contract to `<=54` lines (`>=6` lines of headroom) WITHOUT losing any pinned
  or load-bearing clause.

## Motivation / Business Value
- Restores editing headroom on a governance-pinned canon file so the next
  legitimate contract addition does not have to fight the cap or trigger a
  scramble at the boundary. Prose-only compression, zero behavior change.

## Scope
- In scope: prose compression of `.aai/SUBAGENT_CONTRACT.md`; a new headroom
  guard test (`<=54` lines).
- Out of scope: the frozen `subagent_result:` YAML skeleton (byte-identical to
  `.aai/templates/BRIEF_TEMPLATE.md`); the existing `<=60` cap assertions; any
  behavioral clause of the contract; the prompt-diet ledger (the file is not a
  `.aai/*.prompt.md` and is not in TEST-010 extra accounting — no ledger touch).

## Affected Area
- `.aai/SUBAGENT_CONTRACT.md`, `tests/skills/test-aai-role-output.sh`,
  `CHANGELOG.md`.

## Desired Behavior (To-Be)
- Contract at 53 lines with a `<=54` headroom guard, all pinned tokens and
  load-bearing clauses intact, all CONTRACT-pinning suites green.

## Acceptance Criteria
- AC-001: `.aai/SUBAGENT_CONTRACT.md` is `<=54` lines with every pinned token
  (STATE single-writer rule, `duration_seconds` match, `docs/ai/tdd/`,
  `append-event.mjs`, `check-role-output.mjs`, EXPECT pointer, rationalization
  table, byte-identical `subagent_result:` YAML skeleton) and every load-bearing
  clause intact; the CONTRACT-pinning suites (test-aai-role-output.sh,
  test-aai-hygiene-pack.sh) are green.
- AC-002: governance reconciled — no prompt-diet ledger entry or TEST-012 pin
  bump is required (the contract is outside the `.aai/*.prompt.md` byte
  accounting and its extra-accounting set); test-aai-prompt-diet.sh stays green
  and docs-audit `--check --strict --no-event` + spec-lint stay clean.

## Verification
- `bash tests/skills/test-aai-role-output.sh` (TEST-010 `<=60` + new TEST-020
  `<=54`)
- `bash tests/skills/test-aai-hygiene-pack.sh` (TEST-001/002/003 CONTRACT pins)
- `bash tests/skills/test-aai-prompt-diet.sh`
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event`
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0094-spec-role-output-contracts.md`

## Constraints / Risks
- Ceremony L1 (prose-only compression + additive test). The frozen YAML fence
  and every hostile-pinned sentence must survive verbatim; the `<=60` cap tests
  stay untouched. No secrets referenced.

## Notes
- Recorded follow-up "CONTRACT 60-line headroom". TDD evidence:
  `docs/ai/tdd/red-contract-headroom.log` (product_red),
  `docs/ai/tdd/green-contract-headroom.log`.

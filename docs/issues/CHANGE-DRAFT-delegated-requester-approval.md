---
id: delegated-requester-approval
type: change
number: null
capability: configurable-merge-policy-lanes
user_visible: true
status: draft
links:
  pr: []
  commits: []
---

# A lane can accept a chat-relayed requester approval from a delegated bot login

## Summary
- Source: GitHub goodwind-cz/aai#474. The owner's final decision in that
  issue is option B (the second comment replaces the first; option A, a
  gateway-signed ledger record, is not wanted).
- Option B: a chat gateway holds a dedicated GitHub App or bot credential
  that agent tools cannot reach. When a requester without a GitHub account
  answers "OK" in chat to a preview of one exact head, the gateway submits an
  APPROVED review at that `headRefOid`. The review body quotes the chat
  message id and the requester's platform id. P6 of SPEC-0207 already
  accepts such a review when the lane lists the bot login in
  `requester_logins`.
- The owner chose (2026-11-16) to deliver both remaining AAI-side items:
  1. Document option B as a supported pattern for requesters without GitHub,
     naming the trust assumption explicitly.
  2. Let a lane mark a requester login as a delegated approver, so
     `merge-policy.mjs --check` additionally requires that login's APPROVED
     review body to carry a chat message reference and the requester's
     platform id in one strict, documented format.

## Motivation / Business Value
- A non-technical requester who works only through a chat gateway (Hermes,
  Telegram) can approve a preview without creating a GitHub account, and the
  downstream project no longer needs a custom merge exception outside
  `merge-policy.mjs` (the drift #429 set out to remove).
- The delegated flag keeps an Approve pressed by hand from the bot's
  credential distinguishable from one the gateway relayed, because only a
  relayed one carries the reference line.

## Scope
- In scope:
  - A new optional per-lane key in `docs/ai/merge-policy.yaml` that names
    which of the lane's `requester_logins` are delegated approvers.
  - Lane validation for that key: a malformed list is a parse error; an
    empty list, a duplicate entry, or an entry not listed in
    `requester_logins` is a named validation error.
  - `--check`: a delegated login's APPROVED review at `headRefOid` counts
    only when its body carries exactly one well-formed relay reference line;
    otherwise that review does not satisfy the lane and, when no other listed
    login satisfies it, the lane is denied with a named reason that differs
    from `requester_approval_missing`.
  - Product doc and USER_GUIDE: the option B pattern, the trust assumption,
    the config key, the relay line format and the new denial reasons.
- Out of scope:
  - Option A (a gateway-signed approval record) and option C.
  - Binding the relay reference to a lane-listed list of requester platform
    ids (the gateway decides which chat user may approve).
  - Any gateway implementation; it lives downstream.
  - Production promotion.

## Affected Area
- `.aai/scripts/merge-policy.mjs` (parser, canonical emitter, validation,
  P6 requester check, `--check` lane lines).
- `tests/skills/test-aai-merge-policy.sh`.
- `docs/product/configurable-merge-policy-lanes.md`, `docs/USER_GUIDE.md`,
  `CHANGELOG.md`.

## Desired Behavior (To-Be)
- With no new key in a lane, P6 behaves exactly as today, including for a
  bot login listed in `requester_logins` whose review body is empty.
- With the key, a delegated login's latest deciding review must be APPROVED,
  at `headRefOid`, and carry the relay reference line; a non-delegated
  login in the same lane is judged exactly as today.
- Trust assumption, stated in the docs: the approving identity's credential
  must be unreachable from agent tools. On a single host where the agent
  runs as the same OS user, this is a guardrail, not a security boundary
  (the same wording SPEC-0207 uses for markers); server-side branch
  protection remains the real boundary.

## Acceptance Criteria
- AC-001: A lane without the new key judges a bot login's APPROVED review at
  head with an empty body exactly as before (allowed); every existing
  requester-approval test stays green.
- AC-002: A lane that marks a login delegated is allowed when that login's
  latest deciding review is APPROVED at head and its body carries exactly
  one well-formed relay reference line.
- AC-003: The same lane is denied with a named reason, not
  `requester_approval_missing`, when that review has no relay line, a
  malformed one, or more than one.
- AC-004: `--validate` rejects a malformed list, an empty list, a duplicate
  entry, and an entry not in `requester_logins`, each with its own code.
- AC-005: `--canonical` prints the key in a fixed position, and the docs
  name the key, the line format, the denial reasons and the trust
  assumption.

## Verification
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-merge-policy.sh`
  exits 0 with the new tests passing.

## Constraints / Risks
- Strict parser format up front (the merge-policy parser history, four
  validation rounds of misreadings): one canonical relay line, narrow
  fixtures, no catch-all pattern.
- `merge-policy.mjs` is in GUARD_PATHS (a PR editing it is never
  lane-eligible), so the owner merges this PR. It is not listed in
  `protected_paths_l3`.
- Secrets: no local secret is referenced.

## Notes
- Related: #429, #430, SPEC-0207 P6, RFC-0014 D1.
- Autopilot (/aai-ship) recorded human_time_minutes null; no metrics question asked.

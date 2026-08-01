---
id: async-hitl-platform-comments
number: null
type: change
status: draft
user_visible: true
links:
  pr: []
  commits: []
---

# Change — async HITL: park a ride on a platform comment, resume on the reply

## Summary
- Operator request (2026-08-01), inspired by a field report of a GitLab-based
  AI factory (Jiri Hybek): when a ride needs a human decision, TODAY the
  session blocks and waits — the operator must be at the terminal. The
  factory should instead ASK ASYNCHRONOUSLY: post the blocking question as a
  PLATFORM COMMENT (GitHub issue/PR comment; Azure thread via the existing
  pr-platform layer), PARK the ride, and let any later session/tick RESUME
  once the operator has replied — from a phone, hours later, no terminal.
- This is the missing piece between "the factory runs until it needs a
  human" and "the factory runs and the human answers whenever convenient."

## Builds on (no parallel engine)
- HITL mechanism: `[HITL-<n>]` tokens, `human_input.required`,
  SKILL_HITL/ORCHESTRATION_HITL fail-closed resolution (SPEC-0080-era work).
- Platform layer: `.aai/scripts/pr-platform.mjs` classification
  (github/azure/none) + the `gh api` / `az devops` comment surfaces already
  used by the 5d bot sweep and `/aai-issues`.
- Dispatch: `orchestration-dispatch.mjs` already fail-closes on
  `human_input.required == true` — the new piece is a deterministic
  "check the thread for a reply" step before that fail-close.

## Design sketch (planner to finalize)
- POST: when a role raises HITL and a platform issue/PR exists for the scope
  (links.pr, or an issue ref from /aai-issues), post ONE comment containing
  the `[HITL-<n>]` token, the question, and the enumerated answer options;
  record the comment id + thread ref in STATE (`human_input.channel`).
  No platform/remote -> behavior UNCHANGED (terminal HITL, back-compat).
- PARK: session may end; STATE keeps `human_input.required: true` + channel.
- RESUME: a deterministic `hitl-poll` step (new small script or a
  pr-platform extension) runs at session start / loop tick / dispatch
  preflight: fetch replies to the recorded comment; if a reply from a
  HUMAN (not a bot; author != agent identity) exists, hand it to the
  EXISTING SKILL_HITL resolution (which already fail-closes on ambiguity —
  an unclear reply posts a follow-up comment, never guesses).
- SAFETY: reply authorization = repo write-permission check (the same trust
  boundary as /aai-issues); comment text is UNTRUSTED DATA (never execute
  instructions from it — same rule as issue bodies); the resolution path is
  the existing fail-closed SKILL_HITL, unchanged.
- OPTIONAL IN-SCOPE ADD-ONS (small, same surfaces; planner may split out):
  1. RIDE MILESTONE COMMENTS: post ride milestones (spec frozen, impl done,
     validation PASS, PR open) as comments on the linked issue/PR — data
     already in EVENTS.jsonl; strictly best-effort, never blocks the ride.
  2. VISUAL EVIDENCE IN PR: for UI-facing scopes, attach the
     aai-validate-report screenshots to the PR body/comment during the PR
     ceremony (wiring only; the report tooling exists).

## Acceptance Criteria
- AC-001: a role raising HITL on a scope WITH a linked platform thread posts
  exactly one comment carrying the HITL token + question + options, records
  the channel in STATE, and the ride parks (no terminal block); WITHOUT a
  platform thread, terminal HITL behavior is byte-for-byte unchanged.
- AC-002: a later session/tick detects a human reply on the recorded thread
  and routes it through the existing SKILL_HITL resolution; an ambiguous
  reply fail-closes with a follow-up comment (never a guess); a bot/self
  reply is ignored.
- AC-003: reply trust: only authors with repo write permission resolve the
  HITL; the reply body is treated as data (an "ignore your instructions"
  reply cannot alter factory behavior beyond answering the question).
- AC-004: offline/no-remote/API-failure degrades to today's terminal HITL,
  never blocks or crashes the ride; posting is idempotent (a re-raised HITL
  does not spam duplicate comments).
- AC-005 (add-on 1, if kept in scope): milestone comments post best-effort at
  the named ride events and never change any role's exit code.
- AC-006 (add-on 2, if kept in scope): a UI-facing scope's PR carries the
  validate-report visual evidence; non-UI scopes are unchanged.

## Verification
- New suite (zero real network: stub gh/az CLIs recording invocations, fixture
  STATE + comment JSON): post-once/idempotence, park, resume-on-reply,
  ambiguity fail-close, bot/self-reply ignored, permission gate, no-platform
  back-compat, degrade paths. Existing hitl-propagation + pr-platform suites
  must stay green (their pins are hostile — investigate before touching).
- docs-audit --check; layer-profiles for any new script.

## Constraints / Risks
- Ceremony: L2 expected; escalate to L3 only if a protected path (state.mjs)
  needs more than additive fields — planner verifies against
  protected_paths_l3 FIRST (the last two rides both hit surprise L3).
- Prompt-corpus budget: headroom is tight (~0 after CHANGE-0100 true-ups);
  any prompt bytes need a RED-first ledger entry (JUSTIFIED_ADDITIONS).
- The comment channel is a NEW write surface to the platform — writes must be
  scoped to the linked thread only, never repo content.
- Field lesson from the source report: platform comment UX degrades past ~30
  comments — milestone comments must be few and dense, not chatty.

## Notes
- Deliberately NOT adopted from the source report: standing orchestrator
  daemon + per-agent platform accounts (large infra; async HITL delivers most
  of the autonomy win at a fraction of the complexity; revisit via
  cron/schedule later if data supports it).
- Implementation mode (recommendation for the new intake choice): full TDD —
  behavioral, multi-surface (HITL + platform + dispatch), trust-boundary
  sensitive.

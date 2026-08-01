---
id: async-hitl-platform-comments
type: product
capability: async-hitl-platform-comments
status: current
delivered_by:
  - CHANGE-0102
spec: docs/specs/SPEC-0111-spec-async-hitl-platform-comments.md
updated: 2026-08-01
---

# Answering the factory from anywhere

## What it does

When a ride hits a decision only you can make, the factory no longer has to
sit blocked at a terminal waiting for you. If the scope has a linked GitHub
issue or PR, the blocking question — with its `[HITL-<n>]` token and the
enumerated answer options — is posted as **one comment on that thread**, the
ride parks, and whichever session runs next picks up your reply and
continues. You answer from a phone, hours later; the factory resumes on its
own.

## How to use it

- Nothing to configure. When a ride raises a human decision on a scope with a
  linked issue/PR, the question appears as a comment there; reply to it in
  your own words (or with one of the offered options).
- Your reply counts only if your account has **write permission** on the
  repo. Replies from bots or read-only users are ignored.
- If your reply is ambiguous, the factory does not guess — it posts one
  follow-up comment naming the accepted forms and keeps waiting.
- No linked thread, offline, or a posting error? Behavior is exactly the old
  one: the question surfaces at the terminal.

## Data model

- `docs/ai/hitl-channel.json` (gitignored runtime sidecar): one entry per
  posted question — token, ref, platform, thread, comment id, posted-at,
  resolved flag. Owned by `.aai/scripts/hitl-channel.mjs` (post / poll /
  resolve), Node stdlib only.

## Interfaces and contracts

- **Trust boundary:** a reply resolves a decision only when the author holds
  repo write permission (a permission-lookup failure fails CLOSED — nothing
  is surfaced); bot and self authors are filtered; only comments created
  after our post count.
- **Untrusted data:** the reply body is an answer, never instructions —
  control/bidi characters are stripped, the text is never executed or
  shell-interpolated, and an "ignore your instructions" reply is inert.
- **Once only:** posting is idempotent (a re-raised question never spams);
  an applied answer is consumed (`resolve`) so it never re-surfaces; a reply
  carrying a different question's token is stale and ignored.
- **Never blocks:** posting/polling failures degrade loudly to the terminal
  flow; exit codes of the raising role are never changed.

## Limits and non-goals

- GitHub only for now; Azure DevOps threads degrade cleanly to terminal HITL
  (comment channel is a recorded follow-up).
- The factory does not auto-wake when you reply — the next session or loop
  tick picks it up (a session-start nudge is a recorded follow-up).
- Ride milestone comments and PR visual evidence were split into follow-ups.

## Links

- Request: docs/issues/CHANGE-0102-async-hitl-platform-comments.md
- Spec: docs/specs/SPEC-0111-spec-async-hitl-platform-comments.md

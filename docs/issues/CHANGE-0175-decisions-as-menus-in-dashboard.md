---
id: decisions-as-menus-in-dashboard
number: 175
type: change
status: done
capability: live-agent-dashboard
links:
  pr:
    - TBD
  commits:
    - b9c70aca
---

# A pending decision appears in the dashboard as buttons, and one click answers it

## Summary
- Roadmap wave 1, pair 2, capability half (`hitl_decision` `capability-roadmap-wave-1`).
  Paired maintenance ride: `canon-one-line-report-and-downstream-rules`.
- `/aai-live` (CHANGE-0173) already shows *that* something waits on the owner.
  It cannot be answered from there: the owner still has to find the terminal.

## What exists (measured)
- `docs/ai/STATE.yaml` `human_input: {required, question, blocking_reason}`; the
  canonical writer emits `question: >-` block scalars.
- `.aai/SKILL_HITL.prompt.md` STEP 0 already RESUMES from an async channel:
  `hitl-channel.mjs poll` surfaces a reply as **untrusted data**, STEP 3
  validates it, STEP 4 records it, then `hitl-channel.mjs resolve` consumes it.
- `hitl-channel.mjs` today has exactly one transport: a GitHub thread
  (`--thread <n>`, replies fetched through `gh`). A local answer has no thread.

## Change
The dashboard becomes a **second transport for the existing channel**, not a new
resolution path. It writes the owner's answer to a gitignored local sidecar;
`poll` reads that sidecar alongside GitHub and surfaces it in the same shape, so
SKILL_HITL STEP 0/3/4 and `resolve` work unchanged.

## Acceptance Criteria
- **AC-001** The page renders a pending `human_input` as a question plus a
  free-text box. Parsed option buttons are OUT of this scope (Amendment 1: the
  parser is its own ride) — `waiting.options` is empty and the rendered block
  carries no button, which is the no-options fallback this AC always specified.
- **AC-002** `POST /answer` (loopback only, same server) with
  `{token, ref, answer}` appends ONE record to `docs/ai/hitl-answers.jsonl` and
  returns 200 with what it recorded. A malformed body, an empty answer, or an
  answer over 4 KB is rejected 400 and appends nothing.
- **AC-003** `hitl-channel.mjs poll` surfaces an unresolved local answer with
  `status: 'reply'`, `source: 'local'`, the sanitized body and the token/ref —
  the same shape a GitHub reply produces, so STEP 0 needs no change. A GitHub
  reply and a local answer for one token: the EARLIER one wins, and the source
  is named.
- **AC-004** The answer body is untrusted data: control and bidi characters are
  stripped by the same `sanitizeBody` the GitHub path uses, and nothing in the
  answer is ever executed or interpolated into a command.
- **AC-005** `hitl-channel.mjs resolve --token <t>` marks the local answer
  consumed too, so a second `poll` does not re-surface it.
- **AC-006** With no pending `human_input`, `POST /answer` is refused 409 —
  the dashboard cannot invent a decision nobody asked for.
- **AC-007** The server still writes nothing under the repository EXCEPT
  `docs/ai/hitl-answers.jsonl`, which is gitignored; `git status --porcelain`
  is unchanged by a full answer cycle.

## Verification
- Park a real HITL, open the page, click a recommended option, then run
  `hitl-channel.mjs poll --json` and see the answer with `source: local`.

## Constraints / Risks
- **HAZ**: this is the first WRITE surface on the dashboard, and **loopback is
  not a control** — any page the operator has open can POST to 127.0.0.1, and a
  CORS-safelisted `text/plain` body needs no preflight (validation round 1 and
  code review both proved the write). The controls are: content-type must be
  `application/json`, `Origin` and `Sec-Fetch-Site` must be same-origin when
  sent, `Host` must be loopback (DNS rebinding), only POST routes here, the body
  is capped, and nothing pending is a 409.
- `hitl-channel.mjs` carries a 19-case gate (TEST-001..019); the local source
  must not change any existing GitHub-path behaviour.
- STATE.yaml is a protected L3 surface: the dashboard never writes it. Clearing
  `human_input` stays SKILL_HITL's job, exactly as with a GitHub reply.

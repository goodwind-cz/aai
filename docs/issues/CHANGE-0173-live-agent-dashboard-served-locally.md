---
id: live-agent-dashboard-served-locally
number: 173
type: change
status: done
capability: live-agent-dashboard
links:
  pr:
    - TBD
  commits:
    - 129422c6
---

# A locally served live dashboard: what every agent does, what it waits on, for how long

## Summary
- Roadmap wave 1, pair 1, capability half (`hitl_decision`
  `capability-roadmap-wave-1`). Paired maintenance ride:
  `roadmap-driven-ride-selection-with-budget`.
- The owner's own friction observation (`SKILL_LOOP/operator_observability`):
  he wants to see in a browser what agents are doing and whether they are
  waiting on him, instead of asking "stav?" in the CLI and reading prose.

## What exists and what is missing (measured)
- `generate-live-status.mjs` (SPEC-0114) renders a STATIC page from harness
  transcripts, zero tokens. It is regenerated on demand, never served, and it
  does not know that a role is *waiting* on a human.
- `heartbeat.mjs` (SPEC-0164, PR #335) writes `hb-*` slots per running role.
- `docs/ai/STATE.yaml` carries `human_input` (the HITL block).
- Nothing in `.aai/scripts/` listens on a port (`grep -l 'createServer\|listen('`
  → no match).

## Change
A local HTTP server, Node stdlib only, that serves one page and refreshes it
from disk. No LLM tokens, no network beyond `127.0.0.1`.

## Acceptance Criteria
- **AC-001** `node .aai/scripts/aai-live-serve.mjs` binds `127.0.0.1:<port>`
  (default 7331, `--port` overrides), prints the URL once, and serves the page
  at `/`. Binding a non-loopback address is refused.
- **AC-002** The page lists every role with a live `hb-*` heartbeat slot: role,
  ref_id, last message, last heartbeat age in seconds. A slot older than the page's own
  stale threshold (120 s; `heartbeat.mjs` defines none by design) is shown as stale, not hidden.
- **AC-003** When `docs/ai/STATE.yaml` carries a pending `human_input`, the page
  shows it FIRST, above all roles, with the question text and how long it has
  been waiting. When there is none, that section says so in one line.
- **AC-004** The page auto-refreshes (polling `/data.json`) at least every 5 s
  and shows the time of its last successful refresh; a failed refresh keeps the
  last data on screen and marks it as stale.
- **AC-005** The server reads only: `hb-*` slots, `docs/ai/STATE.yaml`, and the
  live-status generator's output (which scans harness transcripts, as it already does). It writes nothing under the repository. A suite
  proves this with the tripwire.
- **AC-006** `/aai-live` (skill wrapper) starts the server; `Ctrl-C` stops it
  cleanly with no orphan process (the ops orphan-sweep from #211 finds none).
- **AC-007** Works in the existing suites' bash 3.2 / Node stdlib contract;
  `tests/skills/test-aai-live-serve.sh` covers AC-001..006 against fixtures.

## Out of scope
- Answering a question from the page (that is pair 2: decisions as menus).
- Any cloud or multi-machine view.

## Verification
- Start the server, open the URL, run a ride in another terminal: the role
  appears within one refresh; block it on HITL: the question appears on top.

## Constraints / Risks
- Loopback only; a bind to `0.0.0.0` is a refusal, not a warning.
- The page must render with no heartbeat slots at all (fresh install).

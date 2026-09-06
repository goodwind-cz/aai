# SKILL: /aai-live — a live page of agents, waits and ages, served locally

Thin wrapper over `.aai/scripts/aai-live-serve.mjs`. Loopback only, Node stdlib
only, zero LLM tokens. The only file it writes is the gitignored answer ledger
`docs/ai/hitl-answers.jsonl`; it never writes STATE or any tracked file.

## Run
```
node .aai/scripts/aai-live-serve.mjs [--port 7331]
```
Prints one URL. Open it; the page refreshes itself every 5 s. Ctrl-C stops it.

## The page, top to bottom
1. What waits on you — a pending `human_input`, its question and age.
2. Every role with a live heartbeat: ride, role, last message, age; stale marked.
3. Live sessions and today's spend, from the existing live-status data.

## Answering
A pending decision renders as buttons (parsed from the question, recommended
marked) plus a free-text box. One click appends the answer to the ledger and
`hitl-channel.mjs poll` hands it to SKILL_HITL like a GitHub reply.

## Refusals
`--host` beyond loopback exits 2. A busy port exits 1 naming the port. `POST
/answer` refuses a non-JSON content-type (415), a cross-site Origin, a
non-loopback Host (403), a body over 4 KB, an empty answer, a token or ref that
does not match the live block (400), and anything at all when nothing is
pending (409).

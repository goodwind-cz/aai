# SKILL: /aai-live — a live page of agents, waits and ages, served locally

Thin wrapper over `.aai/scripts/aai-live-serve.mjs`. Loopback only, Node stdlib
only, zero LLM tokens, writes nothing under the repository.

## Run
```
node .aai/scripts/aai-live-serve.mjs [--port 7331]
```
Prints one URL. Open it; the page refreshes itself every 5 s. Ctrl-C stops it.

## The page, top to bottom
1. What waits on you — a pending `human_input`, its question and age.
2. Every role with a live heartbeat: ride, role, last message, age; stale marked.
3. Live sessions and today's spend, from the existing live-status data.

## Refusals
`--host` beyond loopback exits 2. A busy port exits 1 naming the port.

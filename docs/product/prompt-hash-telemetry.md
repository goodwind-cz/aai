---
id: prompt-hash-telemetry
type: product
status: current
spec: docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md
updated: 2026-07-27
---

# Prompt-hash telemetry (content-addressed identity of effective role instructions)

## What it does

Telemetry knew model, duration, and tokens for a run — but never WHICH
VERSION of the role's instructions produced it. Prompt edits are the most
common change class in this factory, and until now they were invisible in
run history: two runs of the same role, on different days, looked identical
even if the role prompt, `SUBAGENT_CONTRACT.md`, or `docs/knowledge/LEARNED.md`
had changed underneath them in between.

This feature gives every recorded run an optional, content-addressed
fingerprint of the EFFECTIVE instruction stack it ran under: a sha256 hash
over the role prompt file plus `SUBAGENT_CONTRACT.md` plus `LEARNED.md`. The
hash flows end-to-end — `state.mjs append-run` stores it, `metrics-flush`
carries it into the METRICS.jsonl ledger, `metrics-report` groups run counts
by hash per role so a prompt-version change becomes a mechanical query
instead of a guess, and `orchestration-dispatch --human` prints the hash the
about-to-run role is expected to carry as an advisory line.

## How to use it

Nothing is required — the whole pipeline is additive and observability-only:

- Pass `--prompt-hash <12-64 lowercase hex>` to
  `node .aai/scripts/state.mjs append-run` when a caller wants a run's
  instruction version recorded (validated; a malformed value is rejected
  with a usage error and nothing is written).
- Omit it and everything behaves exactly as before — the field never
  appears on the run entry.
- Run `node .aai/scripts/metrics-report.mjs`: any role whose recorded runs
  carry more than one distinct hash gets a "Prompt versions" section
  showing run counts per short (12-hex) hash — a role with only one hash
  across its history renders nothing new.
- Run `node .aai/scripts/orchestration-dispatch.mjs --human`: the dispatch
  block prints an advisory `Prompt hash: <12-hex> (informational — ...)`
  line naming the hash the dispatched role is expected to run under.

## Data model

One new optional scalar field, additive everywhere it appears:

- `docs/ai/STATE.yaml` `metrics.work_items.<ref>.agent_runs[].prompt_hash`
  — a 12-64 lowercase hex string; absent by default.
- `docs/ai/METRICS.jsonl` `agent_runs[].prompt_hash` — the same string,
  copied through unchanged; absent when the STATE run lacked it.
- `orchestration-dispatch.mjs` stdout JSON `prompt_hash` — a full 64-char
  lowercase hex string on a `dispatch` verdict that names a role; absent on
  `no_action` / `needs_llm` verdicts.

## Interfaces and contracts

- `.aai/scripts/lib/prompt-hash.mjs` — `computeEffectivePromptHash(rolePromptPath, root = process.cwd())`:
  sha256 hex over the role prompt file + `.aai/SUBAGENT_CONTRACT.md` +
  `docs/knowledge/LEARNED.md`, each section framed by a stable filename
  separator; a missing input contributes the literal `ABSENT` marker instead
  of throwing. `shortHash(hash)` returns the first 12 hex characters. Node
  stdlib only — zero new dependencies.
- `state.mjs append-run --prompt-hash <hex>` (PROTECTED L3 surface): optional,
  validated 12-64 lowercase hex; a bad value exits 2 with a usage error and
  writes nothing; the field is pushed onto the run entry AFTER the existing
  conditional `tdd_tests` line, so an absent flag leaves every existing
  append-run golden byte-identical.
- `metrics-flush.mjs buildEntry`: `if (typeof r.prompt_hash === 'string') out.prompt_hash = r.prompt_hash;`
  — a pure, additive copy; no re-validation at flush time.
- `metrics-report.mjs`: a "Prompt versions" section (`| role | prompt_hash | runs |`)
  emitted only for roles whose recorded runs carry more than one distinct
  hash; absent entirely when no role qualifies (report output otherwise
  unchanged).
- `orchestration-dispatch.mjs`: `prompt_hash` on the dispatch-verdict JSON
  object (additive; absent on `no_action`/`needs_llm`) plus one advisory
  `--human` stderr line.
- `.aai/system/PROFILES.yaml`: `.aai/scripts/lib/prompt-hash.mjs` classified
  under `core:` (import closure of the core state/dispatch engines).

## Limits and non-goals

- The hash covers ONLY the durable instruction layer (role prompt +
  `SUBAGENT_CONTRACT.md` + `LEARNED.md`) — dispatch-time extra context
  (brief, scope inputs, per-run injected text) is deliberately excluded.
- Observability only: nothing enforces a hash match anywhere, and there is
  no historical backfill for runs recorded before this change.
- The loop/orchestrator call site that actually PASSES `--prompt-hash` to a
  live `append-run` invocation at runtime is a follow-on wiring concern —
  this change proves the pipeline end-to-end from the `append-run` boundary
  onward (state -> ledger -> report; lib -> dispatch advisory), not the
  producer wiring itself.

## Links

- Request: docs/issues/CHANGE-0070-prompt-hash-telemetry.md
- Spec: docs/specs/SPEC-0096-spec-prompt-hash-telemetry.md

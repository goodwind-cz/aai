---
id: harness-universal-routing
type: change
number: null
status: draft
capability: harness-universal-routing
links:
  pr: []
  commits: []
---

# The dispatcher knows which harness it is running in, and routes models for that harness

## Summary
- Roadmap wave 2, pair 1, capability half (`docs/project-sessions/2026-09-12-wave-2-roadmap.md`).
  Paired maintenance ride: `telemetry-fields-not-prose`.
- `.aai/system/MODEL_ROUTING.yaml` binds `tiers`, `roles` and
  `validation_alternate` to Claude model ids only. `orchestration-dispatch.mjs`
  never detects the harness it runs under; `suggestModel()` resolves
  role@lane, role, tier from that single table.
- On Codex or Gemini every dispatch therefore carries a foreign
  `suggested_model` (for example `claude-opus-4-8`) that the loop must ignore
  and fall back to `suggested_tier`. Validator independence, which compares
  the routed model to the implementer's recorded model, is likewise judged
  against Claude ids on a harness that has none.
- The ledger shows the consequence: of 620 recorded runs, 98% are Claude; 4
  are GPT, 5 DeepSeek, 0 Gemini. Universality is asserted by the mirrors under
  `.codex/`, `.gemini/`, `.cursor/`, `.agents/` and by `CODEX.md`/`GEMINI.md`;
  it has never been routed or measured.

## Motivation / Business Value
- AAI is meant to run on Claude, Codex and Gemini alike. A routing table that
  can only name one vendor makes the tier contract (mechanical, standard,
  premium) real on one harness and decorative on the others.
- The cheap-implementer / strong-verifier split is a tier statement and is
  therefore already harness-universal in intent. Only the binding is not.
- `SUBAGENT_PROTOCOL.md` already anticipates single-model environments
  ("record the reuse as a residual risk") and resolves isolation tiers from
  detected capabilities. Routing is the piece that never caught up.

## Scope
- In scope: harness detection in the dispatcher; per-harness tier and role
  bindings in `MODEL_ROUTING.yaml`; `suggested_model` and validator
  independence resolved per detected harness; `harness` carried on every
  dispatch verdict; Claude defaults moved to the current family; Codex and
  Gemini maps whose ids resolve in `PRICING.yaml`; tests for every resolution
  path; documentation of the new keys.
- Out of scope: proving that a full ride works on Codex or Gemini (wave 2
  list item `cross-harness-universality-proof`); recording the harness on
  runs and friction observations (the paired maintenance ride); any change to
  which roles are delegable (RES-0002 stands).

## Affected Area
- `.aai/scripts/orchestration-dispatch.mjs` (`suggestModel`, the routing
  loader, the verdict JSON), `.aai/system/MODEL_ROUTING.yaml` and its
  line-based parser, `.aai/system/PRICING.yaml` (ids must resolve), the
  MODEL row of `.aai/SUBAGENT_PROTOCOL.md`, `tests/skills/test-aai-orchestration-dispatch.sh`
  or a sibling suite. Harness identity may reuse the environment probes in
  `.aai/scripts/generate-live-status.mjs` (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`,
  `GEMINI_HOME`), which today serve display only.

## Desired Behavior (To-Be)
- Every dispatch verdict carries `harness: claude | codex | gemini | cursor | unknown`,
  detected deterministically from the environment, never inferred from a model
  name (`aai-doctor.mjs` already states that rule).
- `MODEL_ROUTING.yaml` can bind tiers and role overrides per harness. A harness
  with a map gets ids from its own vendor; a harness without a map gets
  `suggested_model: null` and `suggested_tier` stands, exactly as today when the
  file is absent.
- Validator independence resolves within the harness: a different model at or
  above the tier when the map has one; else `validation_alternate` for that
  harness; else null with the residual recorded, per the protocol. Never a
  foreign vendor's id.
- Claude defaults move to the current family so a fresh install routes to
  shipping models; Codex and Gemini maps ship with ids that resolve in
  `PRICING.yaml` under its existing lookup rules.
- A `MODEL_ROUTING.yaml` with no per-harness keys resolves byte-identically to
  before, on every harness (additive, back-compatible), and the file's own
  contract — every routed id resolves in PRICING — holds for every map.
- The no-mid-session-flip rule is preserved: the harness is detected once per
  tick and recorded with the verdict.

## Acceptance Criteria
- AC-001: `orchestration-dispatch.mjs --human` emits a `harness` field on every
  verdict; with `CODEX_HOME` set and no Claude marker it reads `codex`, with
  neither it reads `unknown`, and `unknown` never changes the exit code.
- AC-002: with a per-harness map present, a dispatch under `codex` resolves
  `suggested_model` to an id from the codex map and never to a Claude id; under
  a harness with no map, `suggested_model` is null and `suggested_tier` is
  unchanged.
- AC-003: validator independence never proposes an id outside the detected
  harness's map; when the map cannot supply a different model, the verdict
  carries the residual note the protocol names instead of a foreign id.
- AC-004: a `MODEL_ROUTING.yaml` without per-harness keys produces verdicts
  byte-identical to the pre-change dispatcher on the same STATE fixture.
- AC-005: a test walks every id in every harness map through the PRICING
  lookup rules and fails on any that resolves to `unknown`.
- AC-006: the shipped Claude map names the current family (mechanical, standard,
  premium) and no id older than that family remains in `tiers` or `roles`.
- AC-007: the parser change, if any, keeps the closed one-level shape or extends
  it with a documented key form, and `MODEL_ROUTING.yaml`'s header states the
  new keys and their resolution order.

## Verification
- `node .aai/scripts/orchestration-dispatch.mjs --human` under `CODEX_HOME=/tmp/x`
  and under a clean environment; compare the `harness` and `suggested_model`
  fields.
- The dispatch suite green, including a fixture pair proving AC-004's
  byte-identity and a PRICING resolution sweep proving AC-005.
- `docs-audit --check --strict`, `spec-lint`, and the prompt-diet suite if any
  prompt byte grows.

## Constraints / Risks
- The `MODEL_ROUTING.yaml` parser reads exactly one level of nesting. Either
  extend it under test or use a flattened key form; Planning chooses and
  documents the choice.
- Harness detection must be cheap and deterministic; it runs on every tick.
- Ids for Codex and Gemini must already exist in `PRICING.yaml` or be added
  there in the same scope, with a source line, or flush cannot cost them.
- This ride makes routing honest on non-Claude harnesses; it does not make
  those harnesses proven. The proof is a separate research ride.
- No secret is referenced by this scope; secrets preflight skipped.

## Notes
- Measured on 2026-09-12 during the wave 2 assessment. Routing ids appear in
  six files only (`MODEL_ROUTING.yaml`, `PRICING.yaml`, `usage-note.mjs`,
  `SUBAGENT_PROTOCOL.md`, `state.mjs`, `STATE_FALLBACK.md`), so the surface is
  contained.
- Implementation mode (user choice): tdd — behavioral, multi-surface, and the
  resolution order is exactly the kind of logic where a test that cannot fail
  would pass a wrong routing silently.

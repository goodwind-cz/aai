# Independent audit & autonomy pack (2026-07-26)

Session type: external-auditor deep audit of the AAI factory, benchmarked
against current agent-engineering practice (Anthropic agent guidance, Karpathy
autonomy-slider/verifier framing, Devin/Copilot/Kiro/spec-kit/OpenHands
lifecycles, Ralph-loop/ACE-FCA context economics). Delivered directly on
branch `feat/auditor-autonomy-pack`.

## Audit verdict (short)

The factory's process core is unusually strong: deterministic dispatch,
transactional STATE, evidence-gated verdicts, ceremony levels, byte-budgeted
prompt corpus. The gaps are at the edges: the autonomy chain dead-ends after a
close, cheap-model routing was advisory rather than bound, telemetry captures
no token/cost data, and the factory produces process evidence but no product
artifacts (user docs, data models, interface contracts) and no stakeholder
view of what was delivered.

## Delivered in this session

1. Dispatch rule 4b (`orchestration-dispatch.mjs`): a closed-but-unflushed
   focus (committed `work_item_closed` event, no METRICS entry) now dispatches
   Metrics Flush mechanically instead of falling through to a phantom
   Planning re-offer of the finished scope. Guards: fail-verdict precedence,
   unsatisfied required review, legacy snapshots. Tests: TEST-019.
2. Deterministic model routing: `.aai/system/MODEL_ROUTING.yaml` binds
   dispatch tiers to model ids (per-role overrides + validator-independence
   alternate); dispatch emits `suggested_model`; orchestration prompts honor
   it. Absent file = pre-binding behavior.
3. Stakeholder overview: `.aai/scripts/generate-overview.mjs` renders
   `docs/ai/overview.html` + `overview-data.json` (delivered / in-progress /
   waiting-on-you, with spec + evidence links). Wrapper: `/aai-overview`.
4. End-to-end autopilot: `.aai/SKILL_SHIP.prompt.md` (`/aai-ship`) chains
   intake -> loop -> product docs -> ONE ship checkpoint -> PR. Autopilot
   defaults recorded, never silent; L3/`required` worktree and HITL questions
   stay human; never merges.
5. Product artifact layer: `.aai/templates/PRODUCT_TEMPLATE.md` — per-feature
   functional description, data model, interface contract, limits — written
   by the ship flow at `docs/product/<ref>.md` for user-visible scopes.
6. Bookkeeping: PROFILES.yaml classification, prompt-diet ledger true-up
   (+3451 B in-glob, +148 B AGENTS.md; headroom 636/2048), TEST-012 expected
   total bumped to 29005, USER_GUIDE + SKILLS.md documentation.

## Roadmap (recommended next intakes, highest leverage first)

1. Token/cost capture is 100% null in METRICS.jsonl despite SPEC-0043 being
   done — the tiering economics are unmeasurable. Root-cause the harness
   handoff (Agent-tool usage totals -> append-run/log-tick) and add a
   validation-time canary that fails the flush when a run recorded usage
   upstream but nulls landed in the ledger.
2. Prompt dedup pass: ceremony-level rules exist in 4 places; VALIDATION's
   prose AC STATUS GATE duplicates `docs-audit.mjs --gate` (45 lines of LLM
   date math); the metrics/append-run boilerplate is repeated across 4 role
   prompts. Single canonical includes would cut per-tick context and remove a
   divergence risk for unattended runs.
3. Slim `SUBAGENT_PROTOCOL.md` for per-unit dispatches (result block + writer
   rules only); rely on briefs (already designed) as the sole handoff.
4. Friction loop has infrastructure but zero data (`docs/ai/friction/` empty).
   Enable shadow capture by default for AAI-owned failures and feed triage
   output into wrap-up as proposed intakes.
5. EARS-notation acceptance criteria in SPEC_TEMPLATE (WHEN X, the system
   SHALL Y) to make AC tables machine-walkable end-to-end (Kiro pattern).
6. Legacy prune: `autonomous-loop.*`, `triage.*`, one-time migrations, the
   inert `claude-hook-gate`, and the deprecated consumer-less `triggers.json`
   mechanism — archive or remove.
7. Overview enrichment: group delivered items by release, add per-item cost
   once (1) lands, and auto-regenerate overview.html in the close ceremony.
8. Phase-boundary compaction (ACE-FCA): each role already emits artifacts;
   audit role dispatches to ensure NO transcript context crosses a phase
   boundary, only artifact paths.

## Evidence

- Dispatch suite: 43 PASS incl. new TEST-019 (pure + CLI + routing binding).
- prompt-diet TEST-010 floor holds (net reduction 29308 >= 28672).
- layer-profiles, verify-gate, friction-wiring, feedback, release suites all
  green post-change; full-suite re-run recorded in the PR.

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

## Skill-sweep results (2026-07-27, three parallel hands-on auditors)

All ~20 previously-untouched skills audited hands-on (read-only smoke runs,
promise-vs-behavior checks, token economics, staleness, consumer evidence).
Verdicts: 12 KEEP-AS-IS (share, replay, debug, verify, update,
feedback-triage/upsert, auto-trigger, deslop, meta, scout, interrogate-watch,
profile), 3 QUICK-WINs fixed in this ride (canonicalize bash-3.2 unbound
arrays — reproduced live; test-canon --help/unknown-flag footgun that
performed a real write during the audit itself, TEST-020 pin;
generate-dashboard positional-arg collision silently overwriting
docs/ai/dashboard.html — reproduced twice), 5 INTAKEs (doctor-determinize,
dashboard-refit incl. test-skills trim, docs-hub-generator — catalog is
8/35 skills stale, session-journal-contract, validate-report-contract) and
1 LEGACY-PRUNE (decapod-prune: external CLI never built, ~55 KB dead
weight, zero consumers since March). The roadmap's broader legacy-prune
item RESOLVED with evidence: autonomous-loop.*, triage.*, claude-hook-gate
and the migration scripts are all actively wired — only decapod is dead.

## Final run status (2026-07-28, release v2026.07.28)

Twenty-nine PRs merged across the run (#157-#185), released as
v2026.07.28. Beyond the #157-#170 core (documented below), the second
phase delivered: CI test-impact selection incl. the factory-doc-paths map
(#171/#173 — typical PR 2.4 min instead of ~25), prompt-hash runtime
wiring with the first live non-null METRICS hash (#172), the universality
proof on a virgin non-AAI project (#174, findings CHANGE-0074/0075), the
hands-on skill-sweep (#175 — 3 fixed footguns, 6 intakes, decapod = the
only true dead code), the STATE bootstrap template (#176), decapod prune
(#177), doctor determinization (#178), dashboard/test-skills refit
(#179), the deterministic skills catalog (#180), rollup exclusion
visibility (#181), the journal/validate-report contract reconciliations
per operator decisions (#182), both follow-up batches (#183/#184) and the
platform-portable PR ceremony with the internal-review fallback (#185).
Fourteen PRs merged in the first phase (#157-#170). Everything from the original
audit roadmap AND the extended original-assignment gap list AND the three
Promptbook adoptions is delivered except the recorded follow-ups below.
Follow-ups as of v2026.07.28 — SHIPPED since this list was written:
prompt-hash runtime wiring (#172), stall-hook friction class (#184,
`stalled_progress`), EARS AC guidance (#184), legacy prune (#177, decapod
— the only true dead code), universality proof (#174), skill-sweep
(#175), hash display resolved-as-designed (#184 disposition). STILL OPEN:
allocator rewrite of script/test headers (manual sweep each ride),
CONTRACT 60-line headroom, R1 GitHub-no-bots hardening, Azure live round
trip (SPEC-0103 AC-06, Review-By 2026-08-15), reaper TEST-018 root-cause
data (trap armed via `reaped raw:`, waits for the next CI flake).

## Roadmap execution status (updated 2026-07-26 evening)

Delivered same-day via /aai-ship rides: item 1 (token-capture canary,
PR #158, CHANGE-0058), item 2 (prompt dedup, PR #159, CHANGE-0059,
corpus −4687 B), item 3 (subagent contract split, PR #161, CHANGE-0061)
plus the operator-directed SKILL_PR step 5d bot-review sweep (PR #160,
CHANGE-0060). Process upgrades en route: local full-framework duplication
cut to CI-only (operator direction — was 3x per ride); two stale
L3 zero-diff test landmines reframed; 5d sweep canonized after catching
7+3+3+3 real bot findings across four PRs. Remaining items renumber to:
(1) friction capture default-on, (2) overview v2 (cost/feature once token
telemetry accrues, auto-regen at close), (3) EARS ACs, legacy prune,
allocator-rewrite-all-trees, token-capture canary follow-through in
metrics-report. Next ride: /aai-ship "friction capture default-on".

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

## Extension: Promptbook (Book language) analysis (added 2026-07-27, operator request)

Source: github.com/webgptorg/promptbook (+ specs/book-language.md, examples/
pipelines, ptbk.io). Maturity check: real but pre-1.0 single-maintainer
project (167 stars, 0 tagged releases, npm 0.113.0-11 prerelease, explicit
not-production warning), mid-pivot from a pipeline DSL with testable output
contracts toward a hosted persistent-agent SaaS ("Agents Server"). Notably,
its most relevant feature (EXPECT output validation) is fully working only
in the older generation and sits "reserved, not implemented" in the new one.
Verdict: adopt the ideas, not the dependency.

Adoption candidates for AAI (ranked):
1. EXPECT-style declarative output contracts on role outputs, checked
   deterministically (no LLM) before the expensive review, plus
   EXAMPLE-as-test-fixture run in CI (their test-books.yml precedent) —
   candidate ride: "role output contracts".
2. Append-only self-learning with a structural gate: persist a LEARNED/
   knowledge append ONLY if after == before + append (their self-learning
   spec's hard guarantee) + a Teacher/critic reviewer before any automated
   append — direct upgrade for the friction->LEARNED promotion path.
3. Content-addressed prompt identity: hash each effective role prompt
   (role + AGENTS + LEARNED snapshot) into telemetry per run — answers
   "did this role's instructions change between run A and B" and correlates
   metric regressions with prompt edits (their computeAgentHash).
4. Inheritance provenance markers: stamp dispatched prompts with the
   resolved canon/LEARNED versions they inherited (their visible
   NOTE-inherited-FROM pattern), instead of implicit convention.
5. Graceful degrade-with-provenance on unresolved cross-references (never
   silent, always a visible structured NOTE in the artifact).
6. Named composable POSTPROCESSING declared next to the prompt whose output
   it cleans (contract visible in one place). DISPOSITION 2026-07-28:
   WONTFIX (operator-approved) — no real use-case materialized across 31
   PRs; adopting it would add speculative structure. Items 1-5 delivered
   (1 #166, 2 #167, 3 #170+#172, 4 session-loose-ends ride, 5 promoted to
   an AGENTS.md convention in the same ride).
7. Deliberately NOT adopting: the single-flat-file everything-is-a-keyword
   design (their own repo shows the cost: two incompatible language
   generations, stale blueprint, EXPECT stranded); AAI's separation of
   prompts / dispatch scripts / state / telemetry stays.

## Evidence

- Dispatch suite: 43 PASS incl. new TEST-019 (pure + CLI + routing binding).
- prompt-diet TEST-010 floor holds (net reduction 29308 >= 28672).
- layer-profiles, verify-gate, friction-wiring, feedback, release suites all
  green post-change; full-suite re-run recorded in the PR.

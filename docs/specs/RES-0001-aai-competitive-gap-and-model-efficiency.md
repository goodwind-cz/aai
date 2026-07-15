---
id: aai-competitive-gap-and-model-efficiency
type: research
number: 1
status: done
links:
  pr:
    - 49
  commits:
    - 0f9960e
---

# Research — AAI Competitive Gap Analysis and Model-Efficiency Audit

## Research Question

What should AAI add or improve, based on (a) a self-audit of the repository's
current capabilities and prompt architecture, and (b) deep comparative research
against similar agentic-workflow repositories and processes? Three sub-questions:

1. **Missing capabilities** — what do comparable frameworks have that AAI lacks
   and would benefit from (features, guardrails, workflows, integrations)?
2. **Better execution of existing capabilities** — where do comparable systems do
   the same job (intake, planning, TDD, validation, review, state, docs hygiene,
   multi-agent orchestration) in a measurably better way?
3. **Model-efficiency in prompts** — how can AAI use models more efficiently
   across its ~40 prompt files: model tiering per role (mechanical vs standard vs
   premium), token footprint of the prompts themselves (several exceed 500
   lines), context loaded per tick, caching-friendly prompt structure, and
   right-sizing subagent dispatches?

## Scope

- In scope:
  - Self-audit of this repository: `.aai/*.prompt.md` (~40 prompts),
    `.aai/scripts/` tooling, workflow/state/locking model (RFC-0001/0004/0005),
    docs governance (RFC-0002/0003, SPEC-0015), skill catalog, metrics/telemetry.
  - Comparative research (web) against similar public frameworks and processes,
    at minimum: Superpowers and pro-workflow (both already partially adopted —
    see AGENTS.md), claude-flow, BMAD-method, GitHub spec-kit / OpenSpec-style
    spec-driven development, Aider conventions, OpenHands/SWE-agent process
    patterns, Claude Code native features (skills, hooks, subagents, MCP) that
    could replace bespoke AAI machinery.
  - Model-usage analysis: which AAI roles/prompts could run on cheaper/faster
    tiers, where premium models are wasted on mechanical work, and where the
    orchestrator's MODEL SELECTION guidance is not actually wired into dispatch.
  - Prioritized recommendations, each sized (S/M/L) with expected impact.
- Out of scope:
  - Implementing any change (research only; follow-ups become RFCs/CHANGEs).
  - Benchmarking with paid runs at scale; rely on repo evidence + public sources.
  - Rewriting the workflow model itself (evaluate, do not redesign here).

## Success Criteria

- A findings report saved into this document's Findings/Recommendations
  sections (this doc is the deliverable; done == findings captured).
- Concrete comparison table: AAI vs at least 5 comparable frameworks across
  the core dimensions (intake, planning, implementation strategy, validation
  independence, review, state/concurrency, docs governance, metrics, model
  tiering, token hygiene).
- Model-efficiency audit table: per prompt/role — current effective tier,
  recommended tier, estimated token footprint, top reduction opportunities.
- Prioritized recommendation list (P1/P2/P3) with size (S/M/L) and rationale,
  each phrased so it can be converted directly into an RFC or CHANGE intake.
- Explicit "do NOT adopt" list — patterns seen elsewhere that AAI should
  consciously reject, with reasons (avoids cargo-culting).

## Constraints

- Timebox: one deep-research session (≈ half a day of agent time); if the
  comparative sweep exceeds it, cut breadth (fewer frameworks), not depth on
  model-efficiency (the highest-leverage sub-question).
- Access/data/tools: read-only repo access; public web research; no paid
  benchmark runs; subagent parallelism allowed for the comparative sweep.

## Method

- Approach, experiments, sources:
  1. Repo self-audit: inventory prompts (line counts, per-role token estimates,
     duplication), scripts, and telemetry (`docs/ai/METRICS.jsonl`,
     `LOOP_TICKS.jsonl`) for real usage evidence.
  2. Parallel comparative sweep (one researcher per framework), each answering
     the same structured questionnaire for comparability.
  3. Model-efficiency pass: map each AAI role prompt to the cheapest tier that
     preserves quality, using the orchestrator's own MODEL SELECTION rubric;
     identify prompt-structure changes that improve cache hit rates.
  4. Synthesis: comparison table, gap list, recommendation list, reject list.

## Findings

Run 2026-07-15: 5 parallel researchers (repo self-audit, model-efficiency audit,
3 comparative sweeps over 6 frameworks), synthesized below. Full raw reports in
the session transcript; every claim below carried file or URL evidence in the
underlying report.

### F1 — Enforcement is bimodal; failures happen on the soft side

AAI's mechanical layer is genuinely hardened (transactional `state.mjs`, atomic
`docs-lock.mjs` CAS, docs-index/audit/allocator scripts). The behavioral layer —
validator independence, evidence honesty, model tiering, metrics completeness —
is prompt-only convention, and telemetry shows that is where real failures
occurred (RFC-0006 ran all roles on one model, noted only post-hoc; internal
reviews missed Linux/dash bugs an external reviewer caught). Both mature
competitors attack exactly this gap by different means: Superpowers with an
anti-gaming review protocol (read-only reviewer, controller banned from
coaching, "can't verify from diff" verdict), pro-workflow with PreToolUse hooks
that block the tool call mechanically. Nothing in `state.mjs set-validation`
even compares validator model to implementer model — a ~5-line check.

### F2 — The cost/tiering subsystem has never worked

MODEL SELECTION tiering exists in one prompt (ORCHESTRATION) and is enforced
nowhere: no MODEL field in SUBAGENT_PROTOCOL's dispatch contract, no `model:`
frontmatter in the 27 skill wrappers, zero mention in ORCHESTRATION_PARALLEL.
PRICING.yaml is stale (opus-4-6 at $15/$75 vs actual $5/$25), lacks every model
actually used, and has never priced a run because `tokens_in/out` are null in
100% of METRICS.jsonl history. The framework cannot answer its own "which model
per role" question. Meanwhile observed practice runs premium models on intake
form-filling and on the orchestrator tick — a deterministic 14-rule first-match
table over STATE enums that `orchestration-mode.mjs` already proved can be a
script.

### F3 — Token structure: ~115k-token prompt corpus, ~17–20k fixed tax per tick

59 prompt files, 9,571 lines. Top-10 files = 54% of corpus; SKILL_PROFILE is
~85% fiction (mock transcripts + JS for a script that does not exist). The 8
INTAKE_* files are ~67% identical boilerplate (4 blocks repeated verbatim ×8).
The "PRIMARY PATH / FALLBACK if state.mjs absent" pattern + STATE-WRITE SAFETY
footer repeat in ≥6 prompts. A minimal loop tick re-reads ~17–20k tokens before
any work. Worst: SKILL_LOOP's own caching guidance is inverted — it puts
STATE.yaml (27.6KB, mutates every tick) in the "stable prefix", guaranteeing a
cache break at the earliest byte. Realistic corpus reduction: ~30% (~120–150KB).
Competitors' mechanisms: BMAD step-files + doc sharding (~74–82% reported),
OpenSpec profiles (core = 4 workflows), SKILL.md progressive disclosure (now an
open standard read natively by Codex and Gemini CLIs — AAI's dual prompt+wrapper
layer may be pure overhead).

### F4 — AAI's two-stage review is the pattern Superpowers measured out of existence

Superpowers v6.0 replaced two per-task reviewers with one dual-verdict reviewer
after 25 evals showed equal quality at ~50% tokens and 2× speed. AAI's own
telemetry: review+remediation wall-clock ≈ 88% of implementation time. The
review pipeline is AAI's costliest stage and has never been measured for its
token cost/benefit.

### F5 — Docs lifecycle: AAI remediates sprawl after the fact; OpenSpec prevents it

OpenSpec's delta-spec lifecycle (ADDED/MODIFIED/REMOVED deltas per change,
auto-merged into canonical specs at archive time, change folder archived as
audit trail) solves by construction the exact problem docs-canon/docs-audit
(RFC-0002/0003) were built to clean up afterward. AAI already has
`docs/canonical/` + `docs/_archive/`, so this is an evolution path, not a
rewrite.

### F6 — Live integration bug found during this intake (first SPEC-0015 use)

`state.mjs` `REF_RE = /^[A-Z]+-\d+$/` (state.mjs:102) rejects slug refs, so
DRAFT-era docs (slug-first until merge per SPEC-0015 D2) cannot be focused,
phased, or metered in STATE until a number exists. Intake human-time for this
doc could not be recorded. Confirmed by the self-audit as gap #1. Second
instance found at closeout of this very doc: `docs-audit.mjs --gate <slug>`
returns "no scanned doc resolves to id" for a slug id that the same tool's
`--check` accepts — the slug-ref gap spans the tooling family, not just
state.mjs. P1 recommendation 1 should therefore cover state.mjs AND
docs-audit --gate (and any other consumer of the `TYPE-000N` id shape).

### F7 — Confirmed differentiators (defend, do not regress)

No surveyed framework has AAI's combination: transactional STATE + invariant
checker, typed 8-way intake, docs-audit/canon close gates, persistent metrics
ledger with pricing intent, HITL gating, operator-only merge, and tri-platform
(Claude/Codex/Gemini) portability. Superpowers has no state or telemetry;
BMAD has zero metrics; spec-kit/OpenSpec validate in the implementer's own
session; claude-flow's headline features failed an independent source audit
(~97% of MCP tools are stubs; fabricated benchmark counters).

### F8 — Comparison snapshot (10 dimensions)

| Dimension | AAI | Superpowers | pro-workflow | claude-flow | BMAD | spec-kit | OpenSpec |
|---|---|---|---|---|---|---|---|
| Intake taxonomy | **8 typed** | brainstorm gate | scout score | none | forge-idea/PRD | 1 template | explore/propose |
| Spec discipline | frozen ACs | plan format | thoroughness | SPARC (fading) | levels 0–4 + gate | constitution | SHALL+validator CLI |
| TDD | enforced skill | enforced skill | none | persona only | ATDD module | rhetorical | none |
| Validation independence | separate role+model (convention) | **read-only reviewer, anti-gaming** | hook gates | truth-score concept | fresh-chat structural | same-session | same-session |
| Review | two-stage | single dual-verdict (**eval-backed**) | reviewer+deslop | persona | per-story fresh chat | external PR | external PR |
| State/concurrency | **transactional+locks** | none | SQLite memory | theater | sequential files | git branches | git dirs |
| Docs governance | audit/canon (remediation) | minimal | wikis | none | doc-chain | evolving spec | **delta+archive (prevention)** |
| Metrics/cost | ledger (never fed) | eval-driven releases | **budgets+alerts** | fabricated | none | none | product-only |
| Model tiering | 1 paragraph, unenforced | **mandatory per dispatch** | Haiku gate routing | router (unaudited) | none (community) | none | none |
| Token hygiene | duplicated corpus | bootstrap compression | tool-call budgets | inflation (audited) | **step-files+sharding** | templates | **profiles+deltas** |

## Recommendations

Each item is phrased for direct conversion to a CHANGE/RFC intake. Sizes S/M/L.

### P1 — do first (broken or bleeding money now)

1. **CHANGE: accept slug refs in state.mjs** (S) — widen REF_RE (or map
   slug→number at allocation); unblocks STATE tracking for all DRAFT-era docs.
   Fixes F6.
2. **CHANGE: model tiering with teeth** (S–M) — add MODEL field to the
   SUBAGENT_PROTOCOL dispatch contract; add `model:` frontmatter to skill
   wrappers (harmlessly ignored off-Claude); add the validator≠implementer
   mechanical check to `state.mjs set-validation`; refresh PRICING.yaml to the
   current Claude family and require `--tokens-in/--tokens-out` on append-run
   (warn when null). Fixes the enforcement half of F2. Steal: Superpowers
   "always specify the model when dispatching".
3. **CHANGE: prompt-layer diet, phase 1** (M) — extract the 4 duplicated intake
   blocks into one shared include; delete SKILL_PROFILE fiction (or make the
   script real); drop hand-edit fallback blocks where state.mjs is guaranteed;
   fix SKILL_LOOP's inverted caching order (canon first, STATE last); inject a
   ~1KB STATE digest (loop-digest.mjs exists) instead of the whole 27.6KB file.
   Fixes ~30% of F3 at low risk.
4. **CHANGE: mechanize deterministic ticks** (M) — `orchestration-dispatch.mjs`
   implementing the 14-rule table (LLM only for auto-repair edges); metrics
   flush/report as scripts. Fixes the "premium model as switch statement" half
   of F2.

### P2 — high leverage, needs design

5. **RFC: single dual-verdict review** (M) — replace two-stage review with one
   read-only reviewer returning spec-compliance + quality verdicts, adopting
   the anti-gaming rules (no coaching, no pre-rating, "can't verify" verdict,
   file-based diff handoff). Measure before/after on METRICS. Addresses F4.
6. **RFC: scale-adaptive ceremony levels** (M) — planning declares level 0–4;
   low levels legitimately prune gates (tech-spec-only, compressed review);
   codifies the exception policy instead of operator improvisation. (BMAD.)
7. **CHANGE: verification-before-completion + systematic-debugging skills**
   (S+M) — operationalize "no PASS without evidence" against its actual failure
   modes; give Remediation a root-cause-first protocol. (Superpowers.)
8. **RFC: hook-enforced gates on Claude** (M) — PreToolUse hooks hard-blocking
   secrets/commit-format/merge-outside-ceremony as an additive layer; portable
   script gates remain the cross-platform floor. (pro-workflow; native.)
9. **CHANGE: work-item brief as subagent handoff** (S–M) — Planning emits a
   self-contained 500–1,000-word brief (AC↔task links, canon excerpts, return
   Record section) instead of "go read the spec". (BMAD story files.)
10. **CHANGE: constitution + complexity tracking** (S) — one ratified
    principles doc; gate exceptions must be documented and justified in the
    plan. (spec-kit.)

### P3 — strategic, larger or watch-first

11. **RFC: delta-spec lifecycle** (L) — evolve docs-canon into OpenSpec-style
    ADDED/MODIFIED/REMOVED deltas with archive-time merge. Highest doc-hygiene
    leverage. Addresses F5.
12. **CHANGE: spec-lint.mjs** (M) — deterministic structural validation of
    spec docs (AC format, Test Plan mapping), beside docs-audit. (OpenSpec.)
13. **CHANGE: profiles for the vendored layer** (M) — core/extended prompt sets
    in aai-sync/bootstrap; stop installing all ~40 prompts everywhere.
14. **CHANGE: truth-scoring on METRICS** (S) — record claimed-PASS vs
    verified-PASS and remediation counts per strategy; surface reliability in
    the dashboard. (claude-flow concept — the one good idea there.)
15. **CHANGE: scout readiness score / deslop pass / plan-interrogate** (S each)
    — optional pre-implementation confidence gate; diff-scoped slop removal
    before review; decision-ledger interrogation at spec freeze. (pro-workflow.)

### Do NOT adopt (with reasons)

- **SQLite/binary stores for state or knowledge** (pro-workflow, claude-flow) —
  breaks file-based, git-diffable, tri-platform portability.
- **Simulated multi-agent consensus vocabulary** (claude-flow) — audited as
  cosmetic; single orchestrator + evidence gates is strictly more auditable.
- **Tool/agent-count maximalism** (claude-flow: 314 tools, ~97% stubs) — every
  skill must have a runtime consumer (AAI already learned this via SPEC-0014).
- **README-first, methodology-free benchmarks** (claude-flow "84.8% SWE-bench",
  BMAD "90% savings") — AAI numbers must come from METRICS.jsonl, reproducibly.
- **Always-on context injection hooks** (claude-flow: +15–25k tokens/session) —
  keep pull-based replay, never push-based memory.
- **Same-session self-validation** (spec-kit, OpenSpec) — do not weaken
  independent validation to match simpler competitors.
- **Branch auto-creation at intake** (spec-kit) — collides with the worktree
  decision gate and operator-only ceremony.
- **Persona theater** (BMAD's named personas; coercive all-caps rhetoric) —
  costs tokens, adds nothing enforceable.
- **Claude-only enforcement as the sole gate layer** — hooks/subagent
  frontmatter are additive hardening; portable scripts remain the floor.
- **Regeneration maximalism** ("code as disposable output of specs") — unproven
  at scale; incompatible with brownfield evidence-based remediation.

## Open Questions

- Should recommendations that touch the vendored AAI template layer be filed
  upstream (template repo) or here (this repo is self-hosting)?
- Found during intake (2026-07-15, first SPEC-0015 DRAFT-flow use): `state.mjs`
  rejects slug refs (`^[A-Z]+-\d+$`), so DRAFT-era docs cannot be focused or
  metered in STATE until merge assigns a number. Human intake time for this doc
  (5 min) is recorded here because STATE cannot hold it yet. Candidate follow-up
  CHANGE: accept slug refs in state.mjs (or map slug→number at allocation).
- Whether Claude Code native subagent/skill features can replace bespoke
  dispatch machinery without losing the Codex/Gemini portability AAI targets.

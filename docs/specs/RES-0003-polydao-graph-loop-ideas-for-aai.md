---
id: polydao-graph-loop-ideas-for-aai
type: research
number: 3
status: done
links:
  pr: []
  commits: []
---

# Research — Polydao loop/graph playbook vs AAI

## Research Question

Which ideas in Mr. Buzzoni (@polydao)'s X article **"300 AGENTS, ONE GRAPH,
AND A LOOP THAT EDITS THE LOOP"** (2026-09-05,
`https://x.com/polydao/status/2096128417108287566`, article id
`2096101165515653121`) are worth adopting into AAI — as a gap AAI does not
have, as a sharper version of something AAI already does, or not at all?

Sub-questions:

1. For each of the fourteen build-order steps, is the idea **already covered**
   by an AAI artifact, **partially covered**, or **absent**?
2. Where coverage is partial or absent, is the gap **worth a follow-up
   change/RFC**, or is it out of AAI's product shape (research-swarm /
   knowledge-graph product vs software-factory)?
3. Which of the author's load-bearing rules (stop condition as counts, gate
   outside the writer, corrections in a durable file, meta-loop proposes but
   never writes) are already AAI canon, and which are only prose?
4. Does the article's "graph under the loop" idea (launch as a query over
   node state, not a fixed list) map onto AAI's `STATE.yaml` / roadmap /
   ride-select model, or would adopting it mean a different memory shape?

## Scope

- In scope:
  - Primary source: the X article linked above, read via its article payload
    (the tweet itself is only the article URL). Secondary recaps are not
    evidence.
  - A mapping of all fourteen steps onto existing AAI surfaces (skills,
    prompts, `STATE.yaml`, validation independence, LEARNED / friction /
    wrap-up, routines, ride-select, orchestration dispatch).
  - A per-step verdict: **adopt** (named follow-up), **defer**, or **reject**,
    with one-line rationale and the AAI path that already covers it when
    coverage exists.
  - Explicit call-out of ideas that look new but collapse onto something AAI
    already shipped (false gaps).
- Out of scope:
  - Implementing any adopted idea in this spike.
  - Standing up a 300-agent swarm, Kimi K3, or a market-map knowledge graph.
  - Buying or packaging the author's workspace as a product.
  - Re-litigating AAI's sequential/small-k orchestration (RFC-0005) into a
    hundreds-of-agents dispatcher solely because the article uses that
    capacity.

## Success Criteria

- A findings section in this document (status remains `draft` until the spike
  lands) that:
  - scores all fourteen steps as adopt / defer / reject / already-have;
  - names at most a handful of follow-up intake slugs for any **adopt** rows;
  - records which AAI files were actually read for the "already-have" claims
    (paths, not paraphrases of memory).
- The spike is done when those verdicts are written here and a human can
  decide whether to open a follow-up change/RFC. No code. No spec freeze.

## Constraints

- Timebox: one research pass in a single agent session (read source + read
  named AAI counterparts + write verdicts). Do not open a multi-week study.
- Access/data/tools: repository on disk; the article text captured at intake
  (X.com itself returns 403 to automated fetch — do not block the spike on a
  live re-fetch). No secrets referenced.
- Language: this document in English; operator conversation in Czech.
- Assumption (stated): the author's domain is entity-research / market-mapping
  with a mergeable graph. AAI's domain is a software factory. A "yes, adopt"
  verdict must name the factory analogue, not copy the graph product.

## Method

1. Treat the fourteen steps as the evaluation units (table below). Do not
   score the article as one blob.
2. For each step, open the named AAI counterpart (if any) and record
   covered / partial / absent before writing a verdict.
3. Prefer **reject** when the idea is load-bearing only for a knowledge-graph
   product (node types, alias tables, edge evidence lines) and has no honest
   factory analogue.
4. Prefer **adopt** only when the idea would change AAI behaviour (a file, a
   gate, a stop condition) and is not already canon.
5. The meta-loop (step 14) is the one most likely to look like AAI's
   wrap-up / LEARNED / friction channel — score it last, after the others,
   so it is not a vibe match.

### Source digest (intake-time; not findings)

Title: *300 AGENTS, ONE GRAPH, AND A LOOP THAT EDITS THE LOOP*.
Thesis: a system improves between runs when something carries forward and
something rejects work before it carries forward. Loop engineering gives
carry-forward; a graph gives queryable shape; routines run it unattended;
a large swarm makes the structure worth building.

Build order the author names:

| Phase | Steps | Claimed product |
| --- | --- | --- |
| I Spine | 1–4 | A loop that finishes and refuses bad work |
| II Graph | 5–8 | Memory with a shape, not a transcript |
| III Dynamic workflows | 9–11 | A run that picks its own scope from graph state |
| IV Routines and review | 12–14 | Schedule plus a meta-loop that edits instructions |

Step list (verbatim intent, condensed):

1. Pick the task by frequency times reversibility (weekly, verifies in under
   a minute, cheap to undo; no send/pay/publish in month one).
2. Write the stop condition before the prompt, as counts not adjectives,
   plus hard caps (agents, wall clock, retries) and an on-cap-hit exit.
3. Move the work step out of the prompt into `SKILL.md` with an in-agent
   self-check so N agents return one format.
4. Add a gate the writer does not control: cheap deterministic script first,
   then a fresh-context verifier, then a threshold, then a human queue.
5. Decide the node type in `SCHEMA.md` (one primary type per graph).
6. Write `aliases.csv` before the first launch (identity merge lives above
   the graph).
7. Fix the return schema so merges are deterministic (no prose returns).
8. Land every node before drawing edges; every edge carries an evidence line.
9. Make the launch block a query over graph state, not a fixed list.
10. Route by node state (verified-fresh skip, stale delta, thin, contradicted,
    new) so the second run costs a fraction of the first.
11. Branch on the verdict and cap retries; pass the failure reason into the
    retry; second fail goes to a human file and is not touched again.
12. Schedule a floor, then add an event trigger; match interval to how fast
    the data actually moves.
13. Give corrections a permanent home in `CONSTRAINTS.md`, loaded at every
    launch (dated one-liners, not chat).
14. Weekly meta-loop: one fresh-context agent reads run history, proposes
    diffs to the owned files; **it never writes those files itself**.

Files the author treats as the whole system: `SKILL.md`, `SCHEMA.md`,
`CONSTRAINTS.md`, `aliases.csv`, `00-launches/`, `10-returns/`, `20-graph/`,
`30-queries/` (includes `needs-human.md`), `40-runs/` (append-only).

Load-bearing quotes to score against, not paraphrase away:

- "A stop condition made of counts rather than adjectives is the difference
  between a loop and a runaway process."
- "An agent rereading its own output sees every reason it wrote things that
  way, so it approves."
- "This file is the reason the system improves rather than merely repeats."
  (`CONSTRAINTS.md`)
- "Keep the approval step. An agent that can edit its own constraints without
  review will eventually edit away the constraint that was inconvenient."

### Comparison targets (read these; do not score from memory)

| Article idea | First AAI surfaces to open |
| --- | --- |
| Stop condition as counts + caps | `.aai/SKILL_LOOP.prompt.md`, loop tick log, TDD cycle fields in `STATE.yaml` |
| Skill file + self-check | `.aai/*.prompt.md`, `.claude/skills/`, `.aai/system/DYNAMIC_SKILLS.md` |
| Gate outside the writer | `.aai/VALIDATION.prompt.md`, validator independence, `check-state.mjs`, tests |
| Durable corrections | `docs/knowledge/LEARNED.md`, `.aai/system/FRICTION_PROTOCOL.md`, wrap-up |
| Meta-loop proposes, does not write | `/aai-wrap-up`, `/aai-feedback-triage` + upsert, memory review |
| Schedule + event trigger | `/aai-routine`, roadmap `wave_2` (`cloud-morning-digest`) |
| Route by state / skip settled work | `docs/ai/STATE.yaml` phases, `ride-select.mjs`, orchestration dispatch |
| Retry with reason, cap, then human file | remediation, review-round cap in `.aai/AGENTS.md`, HITL |
| Structured returns | `orchestration-dispatch.mjs` JSON contract, `.aai/SUBAGENT_PROTOCOL.md` |
| Graph / schema / aliases / evidence edges | likely absent as a product — confirm by search, then reject or reframe |
| Launch as a query | `ride-select.mjs`, `docs/ai/roadmap.yaml` — list vs query |

## Findings

The spike ran on 2026-09-28 against `origin/main` at `afc73985` (release
v2026.09.28). Every "already-have" claim below was checked by opening the named
file, not from memory; the paths are cited inline.

### Per-step verdicts

| # | Article step | AAI coverage | Verdict |
| --- | --- | --- | --- |
| 1 | Pick the task by frequency x reversibility | **Partial.** Irreversibility is first-class, but as a HITL/park trigger (`.aai/ORCHESTRATION_HITL.prompt.md` HITL-4, `.aai/SKILL_LOOP.prompt.md:193`, `.aai/SKILL_SHIP.prompt.md:58`), never as a ranking over candidate work. Ride order comes from `docs/ai/roadmap.yaml` pairs and owner direction (`roadmap-propose.mjs harvest --direction`). | **Already-have, different axis.** The article ranks tasks to survive month one of an unattended swarm; AAI ranks by owner direction and gates the dangerous ones at the boundary. No ride. |
| 2 | Stop condition as counts, plus hard caps and an on-cap-hit exit | **Covered.** `.aai/SKILL_LOOP.prompt.md:57-67` declares `max_ticks: 20`, `stagnation_limit: 3`, `max_run_tokens`, `max_run_cost_usd`, `max_prs` (1-5, preflight-enforced), and names the stop conditions explicitly. | **Already-have.** AAI's caps are counts, not adjectives, and predate this article. |
| 3 | Move the work step into a skill file with an in-agent self-check | **Covered.** The whole `.aai/*.prompt.md` corpus is that move; the self-check is `.aai/SUBAGENT_CONTRACT.md` plus the mechanical `check-role-output.mjs`, which is a gate the agent does not control rather than a self-check it grades. | **Already-have, stronger.** The article's self-check is in-agent; AAI's is external and mechanical. |
| 4 | A gate the writer does not control: cheap script, then fresh-context verifier, then threshold, then human queue | **Covered, four layers deep.** Deterministic scripts (`docs-audit.mjs`, `spec-lint.mjs`, `check-role-output.mjs`, `mutation-gate.mjs`), then an independent Validation in fresh context with a mechanical maker != checker check, then the AC STATUS GATE, then HITL. | **Already-have.** This is the article's central rule and AAI's central rule; the orderings match. |
| 5 | Decide the node type in `SCHEMA.md` (one primary type per graph) | **Absent, and rightly.** AAI has document types with a closed vocabulary, not graph nodes. | **Reject.** Load-bearing only for a knowledge-graph product. |
| 6 | Write `aliases.csv` before the first launch | **Absent as such.** Identity in AAI is the slug/doc-number allocation (`allocate-doc-number.mjs`), which is assignment, not post-hoc alias merging. | **Reject.** AAI never mints two identities for one thing, so it has no merge problem to solve above the store. |
| 7 | Fix the return schema so merges are deterministic (no prose returns) | **Covered.** `.aai/SUBAGENT_PROTOCOL.md` fixes the `subagent_result` block and `check-role-output.mjs` refuses a non-conforming one by code (E-NO-BLOCK, E-BAD-ROLE and the rest). | **Already-have.** |
| 8 | Land every node before drawing edges; every edge carries an evidence line | **Covered in the factory form.** A link between a requirement and a claim is an `ac_evidence` record in `docs/ai/EVENTS.jsonl` (589 of them on this main) and, since SPEC-0183, an outcome/evidence pair the checker refuses without hashed bytes. | **Already-have, reframed.** The "edge carries evidence" rule is the outcome backcheck shipped in v2026.09.28. |
| 9 | Make the launch block a query over graph state, not a fixed list | **Partial.** `ride-select.mjs nextRide` walks an ORDERED LIST of roadmap pairs and filters by `status`, so it is a query over a list rather than a query over work-item state. | **Defer, with the sharpest honest gap of the article.** See "The one real gap" below. |
| 10 | Route by node state so the second run costs a fraction of the first | **Covered.** `orchestration-dispatch.mjs` is a 14-rule table over STATE, and it routes on exactly the staleness classes the article names: `validation_staleness_unknown`, `review_staleness_unknown`, closed-focus-stale-state. A settled ride is not re-run. | **Already-have.** |
| 11 | Branch on the verdict, cap retries, pass the failure reason into the retry, second fail goes to a human file | **Covered.** `.aai/AGENTS.md:311` caps review at two rounds ("a third finding-bearing round means the ride was cut wrong: split it, do not re-verify it"); the failure reason travels in the remediation brief; the durable pile is the follow-up ledger (139 open) plus `human_input` in STATE. | **Already-have.** AAI's cap is stricter: it re-cuts the work instead of retrying it. |
| 12 | Schedule a floor, then add an event trigger | **Covered.** `.aai/SKILL_ROUTINE.prompt.md` emits cron/launchd/Task Scheduler lines and never writes the scheduler itself. | **Already-have.** |
| 13 | Give corrections a permanent home loaded at every launch | **Covered, and answered harder.** `docs/knowledge/LEARNED.md` is loaded every session (`.aai/AGENTS.md:283`). But Operator contract rule 5 goes further than the article: a lesson that must hold **downstream** is a GUARD, not a note. The evidence is in the file itself — LEARNED said since 2026-07-03 that a content check must read the staged blob, and the same mistake shipped twice on 2026-09-06 (PR #346, #347). | **Already-have, stronger.** A durable note is the article's answer; AAI measured that a note fails and demoted it. |
| 14 | Weekly meta-loop proposes diffs but never writes the owned files | **Covered.** `.aai/SKILL_WRAP_UP.prompt.md:194-195` forbids committing and forbids adding LEARNED rules without explicit approval; feedback triage prints drafts for the operator. | **Already-have.** The article's "keep the approval step" is AAI canon. |

### The one real gap (step 9)

Ten of fourteen steps are already AAI canon, two are graph-product mechanics
with no factory analogue, one is covered more strongly than the article states,
and one is a genuine difference worth naming.

`ride-select.mjs` answers "what is next" by walking `roadmap.yaml`'s ordered
pairs and skipping `status: done`. The article's step 9 answers the same
question by querying node state: *give me everything stale, thin or
contradicted*. AAI already HAS that state — 139 open follow-ups, docs with
lifecycle status, specs carrying mutation-record drift, `ac_evidence` gaps —
but no selector reads it. The backlog is a pile the operator drains by hand,
not a queryable source of the next ride.

That is why the roadmap felt like extra questions rather than a benefit: the
factory knows what needs doing and cannot say it. Concretely, the open piles a
query would have surfaced today without anyone asking: ~52 mutation records
that declare something other than what ran, 8 unsigned `fu-amend-*` items, and
five research follow-ups (`fu-context-window-telemetry`,
`fu-vocabulary-independence-chaos-test`, `fu-corpus-navigability-measure`,
`fu-go-clarify-kill-gate`, `fu-shell-twin-parity-tax`) that have sat open since
the studies that produced them.

### False gaps (ideas that collapse onto shipped AAI)

- "A gate outside the writer" reads as new, but it is the reason AAI's
  Validation is a separate dispatch with a maker != checker check.
- "Evidence line on every edge" reads as new, but it shipped in v2026.09.28 as
  the outcome backcheck.
- "Agents rereading their own output approve it" is the argument AAI already
  won in SPEC-0021 (single dual-verdict review) and SPEC-0025.
- "Routines run it unattended" is `/aai-routine` plus the loop's unattended
  branch with `max_prs`.

### What the 300-agent framing does not transfer

The article's structure earns its cost because ~300 agents write into one
merged graph; the schema, alias table and deterministic return format exist to
survive that merge. AAI dispatches a small number of roles sequentially against
one focus (RFC-0005), so the merge problem the graph solves does not arise.
Adopting the graph shape to get the loop discipline would be paying the
product's cost for a benefit AAI already has.

## Recommendations

**Adopt — one follow-up, not a ride from this document.**

1. `fu-backlog-is-not-queryable` (P2) — the selector cannot ask the backlog what
   needs doing. Step 9's idea, in the factory form: a read-only query over
   existing state (follow-up ledger, doc lifecycle, mutation-record drift,
   `ac_evidence` gaps) that RANKS candidates, feeding the slate
   `roadmap-propose.mjs harvest` already prints. No new store, no graph, no
   schema file — every input already exists and is already written.

**Reject — named, with reasons.**

- `SCHEMA.md` node types and `aliases.csv` identity merge: load-bearing only for
  a knowledge-graph product. AAI assigns identity at allocation and never mints
  two for one thing.
- The 300-agent swarm shape: AAI is sequential small-k by decision (RFC-0005).
  The graph mechanics exist to survive a many-writer merge AAI does not have.
- `CONSTRAINTS.md` as a separate file: AAI already loads `LEARNED.md` every
  session AND has demoted the "durable note" pattern by measurement (Operator
  contract rule 5). Adding a second correction file would re-introduce exactly
  what rule 5 removed.
- A separate `needs-human.md` pile: the follow-up ledger plus `human_input` in
  STATE is the same job with telemetry attached.

**Already-have — no action, recorded so the next reader does not re-litigate.**

Steps 2, 3, 4, 7, 8, 10, 11, 12, 13, 14 (ten of fourteen). Where AAI differs it
is stricter, not weaker: the self-check is external and mechanical (step 3), the
retry cap re-cuts the work instead of retrying it (step 11), and a downstream
lesson becomes a guard rather than a note (step 13).

## Open Questions

All four are answered by the findings above; kept with their answers so the
next reader inherits the reasoning rather than the question.

- **Is `STATE.yaml` the graph?** Half of it. It is a single-FOCUS machine, but
  skipping settled work does not depend on the focus: `orchestration-dispatch.mjs`
  is a rule table over state and already declines to re-run a settled phase,
  including on the staleness classes step 10 names. What AAI lacks is not
  node-state routing (it has that) but node-state SELECTION — see step 9.
- **Is `CONSTRAINTS.md` a better shape?** No, and the gap is not injection
  either: `LEARNED.md` is loaded every session and is already a dated
  one-liner list. AAI went past the article here — Operator contract rule 5
  demotes the durable note for anything that must hold downstream, on the
  evidence that a note failed twice in this very repository. A second
  correction file would restore what rule 5 removed.
- **Does AAI lose the "failed twice, stop touching it" pile?** No. The
  follow-up ledger is that pile, with telemetry the article's flat file does
  not have, and `.aai/AGENTS.md:311` stops at two rounds by re-cutting the ride
  rather than retrying it. If anything AAI's problem is the opposite: the pile
  is durable but unqueryable, which is the one adopt row.
- **Source snapshot.** Unchanged and still the rule: the digest is the
  `2026-09-05T06:48:53Z` capture; re-fetch only if a human says the source
  moved. Nothing in these verdicts depends on a passage that a later edit could
  soften — the ten already-have rows are decided by AAI files, not by the
  article's wording.

## Notes

- Prompted by operator request 2026-09-14: evaluate the linked post for
  ideas worth taking into AAI.
- Intake type: research (spike with a deliverable matrix, not a feature
  and not an RFC — options are the per-step verdicts, not a design fork).
- Assumption: one session timebox; no secrets; no implementation in this
  ref.
- Staleness preflight: `intake-staleness-check.mjs` stdout empty
  (2026-09-14).
- Secrets preflight: skipped — no secret referenced.

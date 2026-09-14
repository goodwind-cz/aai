---
id: polydao-graph-loop-ideas-for-aai
type: research
number: null
status: draft
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

Spike not yet run. Do not treat the comparison-target table as a verdict.

## Recommendations

Pending findings. Expected shape:

- Zero or more **adopt** rows, each a follow-up intake slug (change or RFC),
  never implemented in this document.
- **Reject** the 300-agent swarm and the market-graph product shape unless a
  factory analogue survives the mapping.
- If the only surviving adopt is "write stop conditions as counts" or "keep
  the human on constraint edits", say so plainly — those may already be
  AAI rules, in which case the recommendation is **already-have**, not a
  new ride.

## Open Questions

- Does AAI's `STATE.yaml` already function as the "graph" (work items as
  nodes, phase as state, launch as a query), or is it a single-focus
  machine that cannot skip settled work the way step 10 describes?
- Is `CONSTRAINTS.md` a better shape than `LEARNED.md` + friction spool for
  corrections that must load at every launch, or is the gap only that
  LEARNED is not injected as a short dated list?
- The article's human queue (`30-queries/needs-human.md`) vs AAI HITL
  (`human_input` in STATE): same job, or does AAI lose the durable "failed
  twice, stop touching it" pile?
- Intake captured the article text because live X fetch is 403. If the
  author edits the article later, this digest is a snapshot of
  `2026-09-05T06:48:53Z` (`modified_at` same). Re-fetch only if a human
  says the source moved.

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

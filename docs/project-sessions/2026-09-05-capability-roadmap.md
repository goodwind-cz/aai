# Capability roadmap — wave 1, owner-ranked (2026-09-05)

Why this exists: since 2026-08-01 the factory merged 132 PRs, of which about
10 were capabilities an operator would notice; ~31 of the 81 feat+fix rides sat
in fix-of-fix chains around six concerns. The owner ranked the candidates below
from three menus. Ledger: `hitl_decision` `capability-roadmap-wave-1` and the
four policy decisions of the same date (`internal-work-without-asking`,
`review-round-cap`, `capability-roadmap-drives-rides`,
`maintenance-budget-one-to-one`).

## Rules that govern this list

- Rides are taken from here, top pair first.
- **1:1 budget:** every maintenance/canon ride is paired with a capability ride
  and the pair ships together. A fix outside a pair goes to the backlog.
- **Two review rounds max** per ride; a third finding-bearing round splits the ride.
- Internal work is done and merged without asking; the owner is asked only via a
  menu, only for new capabilities or public side effects.

## Wave 1 — three pairs (capability ↔ maintenance)

| # | Capability (owner-visible) | Paired maintenance / canon | Why this pairing |
|---|---|---|---|
| 1 | **Live agent dashboard** in the browser: what each agent does, what it waits on, for how long. Replaces "stav?" in the CLI. | **Ride selection from this roadmap with the 1:1 budget enforced** in the orchestrator. | The selector is what keeps every later pair honest; the dashboard is the biggest visible win. |
| 2 | **Decisions as menus in the dashboard**: a pending question appears as buttons with a recommended default; one click resolves it. | **Canon: one-line ride report + vendoring the conciseness/menu/no-ask rules into AGENTS.md** so `/aai-update` carries them downstream. | Both are the same theme: the owner sees less text and clicks more. One canon ride, not two. |
| 3 | **Standardized backlog drain**: one command takes every draft to a PR without intervention and reports at the end. | **Windows + Codex test dispatch without friction** (gitbash dispatch, `.pytest` cleanup). | The drain is the autonomy the owner asked for; the Windows fix is his most repeated environment complaint. |

## Wave 2 (selected as valuable, deferred by the owner)

- CHANGE-0172 — a hand-authored friction observation can carry a score and prose.
- Review-round cap written into VALIDATION canon.
- CHANGE-0166 — the 32-minute sequential sweep is no longer needed after suite isolation.
- Cloud morning digest across projects (extend the morning-scryer routine).

## Not selected

- 1 fix : 2 capabilities (owner chose 1:1); time-based budget.

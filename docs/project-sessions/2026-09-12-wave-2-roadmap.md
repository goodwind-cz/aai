# Capability roadmap — wave 2, owner-ranked (2026-09-12)

Why this exists: wave 1 shipped three of its four pairs (live dashboard,
decisions-as-menus, simple-and-friendly-to-use) and the day of 2026-09-12 put
two more scopes into main (`close-ceremony-fires-only-via-aai-pr`,
`friction-publish-hides-required-followup`). The same day produced the evidence
this wave is ranked on. Ledger: `hitl_decision` records of 2026-09-12 with
`ref_id: wave-2-roadmap` (standing merge authorization, standing decisions a
and b) plus the per-scope decisions of the two rides.

## What the day measured

- 137 rides in `docs/ai/METRICS.jsonl`, 620 role runs, 59.7 M tokens
  (RES-0002). Verification and remediation together are about 56% of tokens.
- `total_cost_usd` is null on all 137 entries. `model_id` is unknown on
  27 of 620 runs. `reliability.validation_fails` sums to 1 across the ledger
  while `remediation_runs` sums to 67: fails are derived from a free-text
  marker (`VERDICT: FAIL`) and remediations from the role name, so the
  factory report's 76% first-pass-clean cannot be right.
- 98% of runs are Claude models. Codex/GPT 4 runs, DeepSeek 5, Gemini 0.
  The universality proof of 2026-07-27 ran Claude models on a virgin project.
  Harness universality is asserted by mirrors and entry files; it has not been
  measured on Codex or Gemini.
- `MODEL_ROUTING.yaml` binds tiers to Claude ids only and the dispatcher never
  detects the harness. A Codex loop is handed `suggested_model: claude-opus-4-8`
  and must ignore it.
- One scope needed three validation rounds and four remediation rounds. Five
  of its controls claimed a property they did not test, and none would have
  been caught by a green run; four were found by mutation, one by an external
  bot. Three false statements were shipped in spec text, one by the
  orchestrator.
- 21 full sweeps on one day, about ten hours of wall-clock.
- 165 open follow-ups (median age 11 days, one P1), and 25 of the 45 draft
  issues are machine-clustered re-packagings of that same backlog. The 1:1
  budget admits one maintenance ride per capability, so at roughly forty refs
  the backlog cannot drain by pairing alone.

## Rules that govern this list

Rules 1 to 5 of the operator contract in `.aai/AGENTS.md` stand unchanged. The
owner added three standing decisions on 2026-09-12:

- Standing merge authorization for INTERNAL rides (fix, chore, guard, harness,
  test; ceremony 2 or below): the orchestrator may squash-merge when validation
  and review are both pass, CI is fully green on the final head, every bot
  thread is answered and resolved, and residuals are disclosed. New
  capabilities, public or external side effects and ceremony 3 stay
  owner-merged.
- Standing decision (a): a hazard introduced by the feature under delivery that
  cannot be split out gets ONE extra finding-bearing round without asking; a
  second extension on the same scope stops and asks.
- Standing decision (b): a remediation that changed executable behaviour after
  a recorded pass is re-validated with `--force` without asking; a text-only
  remediation keeps the verdict and discloses the staleness.

## Wave 2 — pairs in priority order (capability ↔ maintenance)

| # | Capability (owner-visible) | Paired maintenance | Why this pairing, and why here |
|---|---|---|---|
| 1 | **Harness-universal routing**: the dispatcher detects the harness and `MODEL_ROUTING` binds tiers per harness, so Codex and Gemini get their own vendor's ids and validator independence resolves within the harness. | **Telemetry fields, not prose**: `append-run` records harness, total tokens, verdict and model as fields; flush derives cost and reliability from fields; friction observations carry the harness. | Both are the ledger saying truthfully which harness and model did what. Without them the question "does it work on Codex" cannot be answered, forwards or backwards. First because every later pair is judged on these numbers. |
| 2 | **Ref-guard disclosed and optional**: `/aai-update` names the reference-transaction guard before installing it, the installer takes a per-hook switch, and doctor CAT-17 distinguishes declined from accidental. | `agents-tree-not-synced` | Already admitted; confirmed live twice on 2026-09-12 (a downstream friction issue and a `git fetch` refused in this repository). Changes consumer git behaviour, so the merge stays with the owner. |
| 3 | **Mutation gate for tests**: `spec-lint` requires a Mutation checks section at ceremony 2 and above, and the TDD role records one mutation run per test. | **CHANGE-0166**: the 32-minute sequential sweep is no longer needed after suite isolation. | Both are the economics of verification. The gate turns the day's lesson into a guard instead of a note; the sweep change removes the largest wall-clock cost the gate will otherwise multiply. |
| 4 | **Canon is a build artifact**: the dispatch payload is assembled and asserted, so rules bind by construction (DEBT-0005). | **CHANGE-0181**: an amendment nobody recorded is invisible to the gate that exists to catch it. | Reconfirmed three times on 2026-09-12: amendments written without a record, and the sweep-backgrounding rule living only in dispatch prose. One mechanism, two halves. |
| 5 | **Standardized backlog drain**: one command takes every draft to a PR without intervention (wave 1 pair 3, carried). | `windows-codex-test-dispatch` (wave 1 pairing, kept) | The drain is what makes 165 follow-ups tractable. CHANGE-0180 (the only P1: HEAD moves between commands in a shared worktree) rides ahead of it via `blocks: standardized-backlog-drain`, because the drain cannot run unattended while that holds. |
| 6 | `friction-publish-hides-required-followup` (done) | **CHANGE-0172**: a hand-authored friction observation can carry a score and prose. | Capability shipped in PR #373; the maintenance half is now rideable under the 1:1 rule. |

Rides run sequentially through `/aai-ship unattended=true --intake <path>` with
a declared run budget. Under the standing authorization the orchestrator merges
pairs 1, 3, 4 and 5 itself; the owner merges pair 2.

## Wave 2 list (deferred by the owner, not gated)

- `canon-one-line-report-and-downstream-rules`
- `decision-menu-options-parser` (CHANGE-0176)
- `review-round-cap-in-validation-canon` — standing decision (a) is the text to
  write into `VALIDATION.prompt.md` when this rides
- `cloud-morning-digest`
- `cross-harness-universality-proof` — repeat the 2026-07-27 proof on Codex and
  Gemini once pair 1 has shipped; needs those environments available

## Not selected, with reasons

- The 25 machine-clustered `ISSUE-00xx` drafts (`P2 backlog cluster: ...`) are
  an index of the follow-up registry, not work. They are drained by pair 5, not
  ridden individually.
- Pruning dormant skills (about 14 untouched since July, times five harness
  mirrors) waits for skill-invocation telemetry; a git date is a proxy, not a
  measurement.
- Splitting `close-work-item.mjs` (1870 lines, hash-pinned by four suites)
  is real debt but carries no owner-visible outcome; it goes to the backlog.
- CHANGE-0179 (prose-free friction issue) is half-settled by the reporter's own
  words in upstream #371 and is folded rather than ridden.

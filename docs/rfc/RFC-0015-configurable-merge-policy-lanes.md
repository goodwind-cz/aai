---
id: configurable-merge-policy-lanes
type: rfc
number: 15
status: done
links:
  spec: null
  pr:
    - 430
  commits:
    - bcdc1077e45683416b097945ab6e11cd1fd557f0
---

# RFC (Decision Proposal): Configurable merge policy — owner-defined merge lanes

Source: GitHub issue #429 (goodwind-cz/aai).

Frontmatter status values: draft | proposed | accepted | implementing | done | deferred | rejected | superseded

## Context
- Problem or opportunity:
  - The merge boundary in `.aai/SKILL_PR.prompt.md` step 6 is hard-coded:
    `gh pr merge` is forbidden; merging is operator-only.
  - The single sanctioned exception, STANDING AUTHORIZATION, is prose that
    points at one owner-signed `hitl_decision` in `docs/ai/decisions.jsonl`, and
    it states that a capability ride, any public or external side effect, and
    ceremony 3 are NEVER covered.
  - A downstream fleet (Hermes gateway, several requester-facing profiles, one
    operator) has an owner who wants to be consulted only on architecture (new
    container, database or schema change, new external service dependency,
    credentials). Content and design belong to a non-technical requester.
    - Repo A: merge to `main` rebuilds a persistent, publicly reachable
      preview; production moves by a separate promote the requester triggers.
    - Repo B: no preview; merge to `main` deploys production; the requester
      approves screenshots before the merge.
  - The owner's decision in both repos is: content/design PR, CI green,
    requester approved, then the agent merges. AAI cannot express it: the hard
    rule forbids it, and the exception excludes it twice (public side effect;
    a health-adjacent site is ceremony 3).
  - `.aai/` is vendored and rewritten by every sync, so the downstream project
    cannot fix this locally. The agent correctly refuses a merge its owner has
    delegated, and the requester keeps hearing that the owner must approve her
    wording.
- Drivers/constraints:
  - Default behavior must not change for any project that does not opt in.
  - RFC-0014 D1 reserves scope, cost and irreversibility for a human. A lane
    must keep a human at the merge (the requester), not remove the human; it
    only changes WHICH human, by the owner's signed delegation.
  - RFC-0014 also rejected self-declared severity: a role's self-assessment is
    the thing observed failing. Lane eligibility must therefore be decided by
    deterministic, machine-checkable signals, not by the agent's own
    classification of its change.
  - The hook-overlay merge guard (`.aai/scripts/claude-hook-gate.sh`, marker
    `AAI_OPERATOR_MERGE`) is dispatched through `CLAUDE_PLUGIN_ROOT` and guards
    Claude Code sessions only. Other harnesses (Hermes) are governed by prose
    alone, and when the boundary lives in several prose layers the most
    absolute one silently wins.

## Proposal
- Recommended option:
  A project-owned, declarative merge policy plus one deterministic evaluator
  that every harness and the hook consult.

  1. Policy file `docs/ai/merge-policy.yaml`, same family as
     `docs/ai/pr-config.yaml` and `docs/ai/docs-audit.yaml` (never touched by
     sync). Absent file = today's behavior exactly.
  2. Each lane declares: `id`; `decision_ref` to an owner-signed
     `hitl_decision`; `applies_to` (eligibility); `merge_reaches`
     (`preview`, `production` or `nothing`); `requires` (CI green, recorded bot
     sweep via `lane-gate.mjs --sweep-check`, requester approval); a lane-unique
     `marker`; explicit `allow_public_side_effect` and `max_ceremony` opt-ins.
  3. A closed `architecture` list defined by the project. Any PR touching an
     architecture item is ineligible for every lane and goes to the operator.
  4. Evaluator `node .aai/scripts/merge-policy.mjs --check --pr <n>` returns
     `allowed lane=<id> decision_ref=<ref>` or `denied reason=<code>`, exit
     code distinct per outcome. `SKILL_PR` step 6, the hook gate, and any other
     harness call the same evaluator; the prose rule becomes "merge only when
     the evaluator says allowed, with that lane's marker, citing decision_ref".
  5. `--validate` mode: a lane that cannot be satisfied (e.g.
     `merge_reaches: preview` on a repo with no preview declared, a missing or
     unsigned `decision_ref`, a lane covering ceremony 3 without the explicit
     opt-in) fails loudly instead of silently never applying.

  Design points this RFC adds to the issue's proposal:
  - The evaluator reads `merge-policy.yaml` and `decisions.jsonl` from the
    BASE branch (merge target), never from the PR head. Otherwise a PR could
    grant itself a lane by editing the policy file in the same diff.
  - A PR that modifies `merge-policy.yaml` itself is never lane-eligible.
  - `change_kinds` resolve through path globs declared in the policy
    (e.g. `content: ["src/content/**", "**/*.md"]`), and `architecture` items
    likewise map to globs (Dockerfile, compose files, migrations, dependency
    manifests, env/credential files). A file matching no declared kind makes
    the PR ineligible (closed world: unknown means operator).
  - Requester approval is evidence produced by the requester's identity, not
    by the agent: a GitHub PR review approval (or label event) by a login
    named in the lane, read via the platform API. The agent writing a record
    that the requester approved does not count.
  - The existing STANDING AUTHORIZATION becomes one lane in this repository's
    own policy file, so there is a single mechanism instead of a prose
    exception plus a new file.
- Rationale:
  - One machine-readable source of truth removes the prose-layer conflict class
    and gives non-Claude harnesses the same boundary the hook enforces.
  - Everything the owner already decided is preserved: default off, owner
    signature, explicit opt-in for public effect and ceremony 3, distinct audit
    marker per lane, sweep-check and CI still mandatory.
  - It generalizes a mechanism that already exists and works (the 2026-09-12
    standing authorization) rather than inventing a new autonomy concept.

## Alternatives Considered
- Option A — keep the hard rule; downstream owners merge by hand.
  Pros: zero change, zero new risk. Cons: the owner stays a bottleneck on
  content wording, which is exactly what they delegated; the requester flow
  stays broken; agents in other harnesses keep re-encoding the rule in prose.
- Option B — widen STANDING AUTHORIZATION prose to allow public effect and
  ceremony 3 when the record says so.
  Pros: smallest diff. Cons: still prose, still Claude-hook-only enforcement,
  no machine-checkable eligibility, and the agent self-classifies its change
  (the failure mode RFC-0014 D1 rejected).
- Option C — let downstream projects overlay their own `SKILL_PR` text.
  Pros: total flexibility. Cons: forks the canonical prompt; every sync
  conflicts; the safety properties become per-project and unauditable.
- Option D (recommended) — declarative policy plus one evaluator, as above.

## Consequences
- Technical impact:
  - New: `docs/ai/merge-policy.yaml` schema, `.aai/scripts/merge-policy.mjs`
    (`--check`, `--validate`), test suite with fixtures for every deny reason.
  - Changed: `SKILL_PR` step 6 text (defers to the evaluator),
    `claude-hook-gate.sh` (accepts a lane marker only when the evaluator
    allows), `aai-doctor` (runs `--validate` when the file exists).
  - Prompt-corpus governance applies to the `SKILL_PR` edit (diet ledger,
    TEST-012, PROFILES classification).
- Operational impact:
  - Merge reports cite the lane id and `decision_ref`; the audit trail shows
    who decided each merge (operator marker vs lane marker).
  - Owners must author and sign lanes; nothing activates implicitly.
- Migration/compatibility notes:
  - No file = unchanged behavior; existing downstream projects see nothing.
  - This repository's 2026-09-12 standing authorization is migrated into a lane
    with identical conditions; the prose exception is then removed so there is
    one path.
  - Constitution article 7 (the ceremony ends at `gh pr create`) needs an
    owner-approved amendment naming lane merges as the sanctioned exception.

## Risks
- Primary risks and mitigations:
  - Self-granted lane via the PR diff. Mitigation: policy and decisions read
    from the base branch; policy-editing PRs never lane-eligible.
  - Misclassification of a structural change as content (e.g. a `.astro`
    restyle that adds a script tag calling a new external service).
    Mitigation: closed-world globs, architecture globs override kind globs,
    unknown files deny; residual risk disclosed — globs classify paths, not
    semantics.
  - Forged requester approval. Mitigation: approval read from the platform by
    actor login, never from an agent-written record.
  - Irreversible production deploy in Repo B. Mitigation: requires explicit
    `merge_reaches: production` plus `allow_public_side_effect: true`; the
    requester approval is the human gate RFC-0014 D1 requires.
  - Non-Claude harness ignores the evaluator. Mitigation: none mechanical in
    AAI; the gain is a single source of truth to wire into each harness.
    Server-side branch protection remains the only true boundary.
  - Honest framing carries over: markers are guardrails against habit, not a
    security boundary.

## Open Questions
- None open; resolved by the owner decisions below.

## Decisions (owner, 2026-10-03)
- D1 — requester approval source: a GitHub pull request review with state
  APPROVED by a login named in the lane, read from the platform API. Labels
  and agent-written records do not count.
- D2 — v1 scope: both `merge_reaches: preview` and `merge_reaches:
  production`. Production requires the explicit `allow_public_side_effect:
  true` opt-in; otherwise Repo B in issue #429 stays blocked.
- D3 — classification: path globs only, closed world, architecture globs
  override kind globs, an unmatched file denies. A diff-content tripwire
  (e.g. a new `<script src>` in a content file) is a follow-up, not v1.
- D4 — roadmap: admitted as the next capability (position 12); implementation
  mode full TDD.

## Approvals
- Required approvers (roles/names): repository owner (AlesH) — this changes
  the merge boundary and constitution article 7, which only the owner can sign.
- Timeline: no hard date; it blocks the downstream Hermes fleet rollout
  described in issue #429.

## Notes
- Related: RFC-0010 (hook-enforced gates), RFC-0014 (human gate at merge,
  decisions D1 and D2), the 2026-09-12 standing authorization record in
  `docs/ai/decisions.jsonl`.

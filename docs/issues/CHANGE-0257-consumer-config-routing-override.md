---
id: consumer-config-routing-override
type: change
number: 257
capability: consumer-config
user_visible: true
status: done
links:
  pr: []
  commits: []
---

# A consumer's routing exception lives in a project-owned config the update never touches

## Summary
- The deferred "seam" half of CHANGE-0192
  (`routing-tables-have-an-owner-and-a-seam`, keeper half shipped in PR #553 /
  SPEC-0289, released v2026.11.13). Tracked as follow-up
  `fu-consumer-routing-seam` (P2); this intake resolves it.
- `.aai/system/MODEL_ROUTING.yaml` is core-vendored and `/aai-update` replaces
  it on every update. That stays correct (owner decision 2026-09-24). What is
  missing is a place a consumer can put an exception that the update never
  overwrites or deletes.
- Add one consumer-owned config file, outside `.aai/` (downstream projects
  gitignore `.aai/`, so a file there is neither committed nor shared), whose
  first and only tenant is a narrow routing override: role -> model, per
  harness.

## Motivation / Business Value
- Trust: a consumer who customizes routing and loses it on update learns that
  our update is unsafe for their configuration.
- The current MODEL_ROUTING.yaml UPGRADING note tells the consumer to re-apply
  customizations after every update — the defect handed to the user as a
  procedure (CHANGE-0192 AC-004).
- Owner framing, 2026-09-24: "přepisování uživatelem může být spíš nějaký
  výjimečný proces někam do centrálního jeho konfigu, který by stejně měl
  vzniknout." — an exceptional override in the consumer's central config.

## Scope
- In scope:
  - A consumer-owned config file (location and name decided in Planning,
    measured against a scratch `aai-sync` install, not this repo) that
    `aai-sync.sh`, `aai-sync.ps1`, `aai-update.sh` and `aai-update.ps1` never
    write, overwrite or delete.
  - A routing override section in it: role -> model id, scoped to one named
    harness (from the closed harness set). Tier overrides only if trivial.
  - `orchestration-dispatch.mjs` applies a matching override on top of the
    shipped table's resolution, for that harness only.
  - `aai-doctor` reports an active override in one line; a malformed file is
    reported, never silently half-applied.
  - The MODEL_ROUTING.yaml UPGRADING note points to the consumer file instead
    of telling the reader to re-apply edits.
  - Product doc for the capability.
- Out of scope:
  - A second full routing table (validation_alternate, lane keys, effort,
    effort_params stay shipped-table-only unless Planning decides otherwise —
    default: the override does NOT set effort).
  - Changing the shipped tables' overwrite behaviour, the freshness stamp
    (SPEC-0289) or the effort tiers (SPEC-0288).
  - Seeding the file on install (absence is the default and must change
    nothing).

## Affected Area
- `.aai/scripts/orchestration-dispatch.mjs` (model resolution),
  `.aai/scripts/aai-doctor.mjs` (visibility), `.aai/system/MODEL_ROUTING.yaml`
  (UPGRADING note), `.aai/scripts/aai-sync.sh` / `.aai/scripts/aai-sync.ps1` /
  `.aai/scripts/aai-update.sh` / `.aai/scripts/aai-update.ps1` (must provably
  not touch the file), `tests/skills/lib/install-parity.mjs` (twin parity
  proof), `docs/product/`.

## Desired Behavior (To-Be)
- A consumer writes, e.g., "on claude, Code Review uses claude-sonnet-5-5" in
  the consumer config; every Code Review dispatch on the claude harness then
  carries that model as `suggested_model`; Codex/Gemini dispatches and every
  other role are unchanged.
- After `/aai-update` (bash or PowerShell), the shipped routing table is the
  new shipped one and the consumer config is byte-identical to before.
- No consumer config, or no entry for the dispatched role and harness: the
  dispatch output is byte-identical to today.
- An override that does not name a harness, or names one outside the closed
  set, is refused with a visible NOTE and has no effect.
- A malformed consumer config is reported (NOTE on dispatch, a doctor finding)
  and no part of it is applied.
- An override model id that does not resolve in PRICING.yaml is reported as
  unpriced (so metrics cost is not silently lost).

## Acceptance Criteria
- AC-001: a consumer config file exists at a path outside `.aai/` that both
  sync twins and both update twins provably never overwrite or delete,
  demonstrated by an update run (bash and PowerShell) over a scratch target
  carrying a customized shipped MODEL_ROUTING.yaml AND the consumer config: the
  shipped table is replaced, the consumer config is byte-identical
  (CHANGE-0192 AC-002).
- AC-002: a routing override there changes `suggested_model` for the role it
  names ONLY on the harness it names; every other role and harness resolves
  exactly as without it (CHANGE-0192 AC-003).
- AC-003: an override with no harness, or a harness outside the closed set, is
  ignored with a stderr NOTE naming it, and changes nothing (CHANGE-0192 AC-003
  rationale: a role-only override carrying a vendor model id would follow a
  project switching harnesses).
- AC-004: absence of the file, or of a matching entry, yields byte-identical
  dispatch JSON to the same tick without the feature.
- AC-005: a malformed consumer config fails visibly — a NOTE on dispatch and a
  doctor finding — and no override from it is applied (no half-apply).
- AC-006: an override model id not resolvable in PRICING.yaml is reported as
  unpriced (dispatch NOTE and doctor), not silently accepted.
- AC-007: `aai-doctor` prints one line naming each active override (harness,
  role, model) when the file carries any.
- AC-008: MODEL_ROUTING.yaml's UPGRADING note no longer instructs the reader to
  re-apply customizations after each update; it names the consumer config
  instead (CHANGE-0192 AC-004).
- AC-009: suggested_effort, harness_effort and the routing freshness stamp
  are unaffected by an override.

## Verification
- `tests/skills/lib/install-parity.mjs` scenario (both twins): customized
  shipped table + consumer config in the scratch target, run update, assert
  table replaced and consumer config unchanged, twins agree.
- Dispatch tests over fixture STATE: override hit on the named harness,
  miss on another harness, miss on another role, absent file byte-identity,
  harness-less row NOTE, malformed file NOTE with no half-apply, unpriced id
  NOTE.
- Doctor test: active-override line and malformed-file finding.

## Constraints / Risks
- Narrow on purpose: an override that can express anything the shipped file
  can drifts into a fork, and the consumer is back to maintaining it.
- The consumer file must be committed by the consumer, so it cannot live
  under a gitignored path (`.aai/`, `docs/ai/reports/` and the other
  RUNTIME_IGNORE entries).
- Both sync twins already preserve `docs/ai/` runtime data; Planning must
  verify (not assume) that no prune, seed or migrate step touches the chosen
  path.
- No secret is referenced.

## Notes
- Source: CHANGE-0192 AC-002, AC-003, AC-004
  (`docs/issues/CHANGE-0192-routing-tables-have-an-owner-and-a-seam.md`).
- Closes follow-up `fu-consumer-routing-seam` at ride end.
- Autopilot defaults (/aai-ship): human_time_minutes null; implementation mode
  left to Planning.

## Owner extension 2026-11-14

Before PR #555 merged, the owner extended the scope (round_extension, authority
owner, recorded in docs/ai/EVENTS.jsonl 2026-11-14T06:16:45Z): "K tomu pr 555
... Musí to aktualizovat pricing ale i cizí modely" (it must also keep pricing
up to date, including for third-party models). He chose all four additions:

1. The monthly `.aai/routines/ROUTING_REFRESH.routine.md` refreshes the whole
   `.aai/system/PRICING.yaml`, not just the routed ids. A row it cannot verify
   is marked unverified with the date, never silently kept.
2. In a consumer checkout the routine runs a downstream mode: it researches
   prices only for the project's override model ids that the shipped PRICING
   lacks, writes them into the consumer-owned project config and opens a PR in
   that project. Upstream mode is otherwise unchanged.
3. The project config carries its own prices, which metrics costing, the
   dispatch's unpriced NOTE and the doctor use when the shipped PRICING lacks
   the id.
4. An override naming a model from another vendor than the section's harness
   is applied, never blocked, and made visible.

### Additional acceptance criteria

- AC-010: the monthly routine's upstream mode covers every `models:` row of
  PRICING.yaml except `unknown`: each ends a run either re-verified from a
  primary source or marked unverified with the run date (rates kept); a
  deterministic check refuses a refreshed table that leaves a row neither
  verified nor marked since the run date.
- AC-011: in a consumer checkout (the tables are not tracked there) the routine
  does not stop: it prices only the override model ids that no shipped PRICING
  row prices, writes the verified rates into the project config's pricing
  section, opens one pull request in that project, and never edits `.aai/`.
- AC-012: `docs/ai/project-config.yaml` may carry a pricing section with, per
  model id, input and output USD per 1M tokens, a source URL and a
  last-verified timestamp. metrics-flush, metrics-report, the dispatch's
  unpriced NOTE and doctor CAT-22 cost an id from it when the shipped
  PRICING.yaml cannot; when both can, the shipped table wins. A malformed
  pricing section makes the whole file malformed (no override, no project
  price applied).
- AC-013: doctor CAT-22 warns when a project price is older than the shipped
  PRICING cadence (`update_policy.cadence_days`).
- AC-014: an override whose model belongs to a different vendor than the
  section's harness is applied, never blocked, with one dispatch stderr NOTE
  and a mention on the CAT-22 line.
- AC-015: the product doc shows the pricing section and codex and gemini
  override examples; the update-ownership proof (both sync and both update
  twins) runs over a consumer file that carries a pricing section; the
  CHANGELOG entry describes the extension.

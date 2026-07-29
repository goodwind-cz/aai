---
id: auto-update-config
number: 91
type: change
status: done
user_visible: true
links:
  pr:
    - 194
  commits:
    - 9c4d17156d9548427e2c5bb3fced854dcea9df27
---

# Change — auto-update: local config for new-release notification + opt-in automatic update

## Summary
- Operator request (2026-07-28, /aai-intake, clarified): the check must fire
  as a SIDE EFFECT OF NORMAL USE — not a command anyone has to remember. Just
  starting a session / using the project surfaces a newer-release
  notification (or, in auto mode, performs the update). Controlled by a LOCAL
  per-project config. Two modes:
  1. `notify` (default, safe) — surfaces "a newer AAI release <version> is
     available" during normal use; applies nothing; the operator updates when
     ready.
  2. `auto` (opt-in) — the same trigger performs the `aai-update` layer sync
     automatically, no manual step.
- TRIGGER (the point of this change): reuse the existing SessionStart hook
  (hooks/session-start.{sh,ps1} + hooks.json, which already runs SKILL_META)
  as the primary usage-moment hook — the notify/auto check runs there, so the
  operator gets it just by opening a session. Optionally also a loop-tick
  boundary. NOT a standalone command you must invoke (a manual
  `aai-update-check` may exist too, but it is not the primary path).
- Builds on what already exists: `.aai/system/AAI_PIN.md` records the synced
  template version/commit; `layer-drift.mjs` already compares that pin
  against the source's canonical HEAD/ref; `aai-update.sh/.ps1` performs the
  sync (and refuses on the canonical repo itself). This change adds the
  config-driven notify/auto behavior on top — it does NOT reinvent detection
  or sync.

## Design sketch (planner to finalize)
- A LOCAL config (e.g. `docs/ai/update-config.yaml`, sibling of the
  committed `docs/ai/docs-audit.yaml`; planner decides committed vs
  per-dev/gitignored — likely committed so the team shares the policy, with
  the notify/auto choice being the shared setting): keys `mode: notify |
  auto` (default `notify`), optional `channel`/verbosity, and a
  `check_on: <manual|loop-tick|session-start>` hint for WHEN the check runs.
- A check entrypoint (extend `aai-doctor` and/or a small
  `aai-update-check.mjs`): runs the existing drift/pin-vs-source comparison,
  and either prints a loud NOTIFY line (mode notify) or invokes the
  aai-update sync (mode auto). Never auto-updates on the canonical repo
  (same guard aai-update already has). Offline-safe: if the source ref is
  unreachable, degrade to a clear "could not check" note, never block.
- Wiring: notify surfaces where the operator already looks (e.g. a
  session-start hook line and/or aai-doctor CAT). Auto mode is opt-in only —
  never the default — because an unattended sync mutates the vendored layer.

## Acceptance Criteria
- AC-001: with `mode: notify` (default) and a newer source release than the
  local pin, the check prints a clear "newer AAI release <version>
  available" line and changes NO files; exit code non-failing
  (suite-verified with a fixture pin behind the source).
- AC-002: with `mode: auto`, the same condition triggers the aai-update
  sync automatically; on the canonical repo it still REFUSES (never
  auto-syncs the source of truth); a source-unreachable check degrades to a
  loud "could not check" note, never a hard failure (suite-verified).
- AC-003: config is validated (unknown mode rejected with a clear error,
  falls back to notify); absent config == notify default (back-compat, no
  behavior change for projects that never adopt it).

## Verification
- new suite tests/skills/test-aai-update-check.sh (fixtures: pin-behind ->
  notify; pin-behind + auto -> sync invoked; canonical-repo -> refuse;
  unreachable -> degrade; bad-config -> notify fallback).
- docs-audit --check; layer-profiles (if a new .aai script is added).

## Constraints / Risks
- Ceremony L2. Auto mode mutates the vendored layer unattended — must stay
  opt-in, canonical-repo-guarded, and offline-degrading; that safety
  envelope is the main review focus. Live cross-repo release detection is
  only fully provable against a real second checkout — defer that AC to
  first target-project adoption if not fixture-coverable.

## Notes
- Queued behind the in-flight core-prompt-diet ride; intake is offline and
  sets no focus. Reuses AAI_PIN + layer-drift + aai-update; no parallel
  detection/sync engine (same discipline as the platform-portable-pr and
  product-docs rides).

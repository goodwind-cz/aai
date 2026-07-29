---
id: auto-update-config
type: product
capability: auto-update-config
status: current
delivered_by:
  - CHANGE-0091
spec: docs/specs/SPEC-0106-spec-auto-update-config.md
updated: 2026-07-29
---

# Staying current with AAI releases

## What it does

A project built on AAI finds out that a newer AAI release exists **as a side
effect of normal use** — nobody has to remember to run an update command. The
existing SessionStart hook runs a best-effort, non-blocking check every time a
session opens (throttled so it is not a network hit every time). A local
config decides what happens:

- **notify** (the default, safe) — a session surfaces a short "a newer AAI
  release is available" line and changes nothing; you update when you are
  ready.
- **auto** (opt-in) — the same moment applies the update for you, in the
  background, and tells you the result the next time you open a session.

Detection and the actual sync are the same machinery `/aai-update` already
uses — this feature only adds the config-driven, usage-triggered behaviour on
top.

## How to use it

- Do nothing to get **notify**: with no config (or `mode: notify`) a session
  quietly tells you when a newer release is out. This is safe on every
  project.
- Opt into **auto** by setting `mode: auto` in `docs/ai/update-config.yaml`.
  From then on, when a session detects a newer release it applies the
  `aai-update` sync in the background and reports the outcome
  ("auto-update applied <the new version> — review the diff", or a
  failure/refused note) on your **next** session start.
- Tune how often it checks with `throttle_hours` (default `24`) — checks
  within that window are skipped.
- Run it by hand any time with `node .aai/scripts/update-check.mjs`
  (add `--force` to bypass the throttle); this is the same check the hook
  runs.

Example `docs/ai/update-config.yaml`:

    mode: notify        # notify (default) | auto
    throttle_hours: 24  # skip re-checking within this many hours

## Data model

- `docs/ai/update-config.yaml` — committed local policy (so a team shares one
  setting). Keys: `mode` (notify | auto, default notify) and `throttle_hours`
  (non-negative integer, default 24). The file being absent is exactly the
  same as `mode: notify`.
- Runtime state lives under gitignored `.aai/cache/`: `update-check.json`
  (throttle timestamp) and, for auto mode, `update-sync-outcome.json` (the
  result of the last background sync, surfaced once) plus `update-sync.log`.
  None of this is synced into a target project's vendored layer.

## Interfaces and contracts

- `.aai/scripts/update-check.mjs` — the orchestrator and manual entrypoint.
  Reuses `layer-drift.mjs` for the verdict and `aai-update.{sh,ps1}` for the
  sync; it never reimplements detection or the canonical-repo guard. Runtime
  outcomes always exit 0; only a CLI usage error exits 2.
- `hooks/session-start.{sh,ps1}` — invoke the check best-effort. A check that
  fails, times out, or hangs can **never** block or break session start (a
  bounded watchdog on the detection; the auto-mode sync runs fully detached).
- auto mode applies a sync **only** on a `behind` verdict, **never** on the
  canonical repo (relies on `aai-update`'s own refusal), and **never** when
  the source is unreachable. An unknown `mode` value is rejected on stderr and
  falls back to notify — a typo can never silently enable auto-sync.

## Limits and non-goals

- notify vs auto is the only behavioural switch; auto is deliberately opt-in
  because it mutates the vendored layer.
- Live cross-repo detection is proven here against local fixtures; the first
  real target-project adoption is its real-world confirmation.
- Under two truly-simultaneous session starts in the same repo, the
  concurrent-sync guard can be raced (bounded, converges, no corruption) — an
  atomic-lock hardening is a tracked fast-follow (`docs/ai/decisions.jsonl`).

## Links

- Request: docs/issues/CHANGE-0091-auto-update-config.md
- Spec: docs/specs/SPEC-0106-spec-auto-update-config.md

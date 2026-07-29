---
id: spec-auto-update-config
type: spec
number: null
status: implementing
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-auto-update-config.md
  rfc: null
  pr: []
  commits: []
---

# Implementation Spec — auto-update: config-driven new-release notify + opt-in auto-sync

SPEC-FROZEN: true
<!-- Re-affirmed 2026-07-29 after the owner-authoritative amendment (Design
     decisions D1 detached+report-next-session, D2 future-dated-cache guard,
     D3 ps1 nits; Spec-AC-02 refined, Spec-AC-06 extended, Spec-AC-09 added). -->

## Links
- Requirement: docs/issues/CHANGE-DRAFT-auto-update-config.md
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md
- Builds on: SPEC-0020 (spec-doctor-vendored-layer-drift, `.aai/scripts/layer-drift.mjs`), SPEC-0052 (aai-update TOCTOU, `.aai/scripts/aai-update.sh`/`.ps1`), `.aai/system/AAI_PIN.md`, `hooks/session-start.sh`/`.ps1` + `hooks/hooks.json`

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: see template

## Problem and intent

A target AAI project must learn a newer AAI release exists as a SIDE EFFECT OF
NORMAL USE — not a command anyone must remember. The existing SessionStart hook
(`hooks/session-start.{sh,ps1}`, wired in `hooks/hooks.json`, matcher
`startup|resume|clear|compact`) already runs at every session start to inject
`.aai/SKILL_META.prompt.md`. This change slots a best-effort, non-blocking
new-release check into that same usage-moment, controlled by a LOCAL per-project
config with two modes:
- `notify` (default, safe): surfaces "a newer AAI release is available" during
  normal use; applies nothing.
- `auto` (opt-in): the same trigger performs the `aai-update` layer sync.

Detection and sync ALREADY exist and are REUSED verbatim — no parallel engine:
- `.aai/scripts/layer-drift.mjs` (`decide`/`--json`) compares the pin
  (`.aai/system/AAI_PIN.md`) against the canonical HEAD with honest distance
  tiers and strict degrade-and-report (exit 0 up-to-date, 3 drift, 4
  unverifiable). See SPEC-0020.
- `.aai/scripts/aai-update.{sh,ps1}` performs the sync and REFUSES on the
  canonical repo (origin-slug guard, `aai-update.sh:66-73`,
  `aai-update.ps1:57-61`).

## Implementation strategy
- Strategy: tdd
- Rationale: the safety envelope is the whole point of the change and is
  security/data-integrity shaped — auto mode mutates the vendored layer
  unattended, must stay opt-in, canonical-repo-guarded, and offline-degrading,
  and the trigger must never block or slow session start. Every guard (auto vs
  notify branch, canonical refuse, offline degrade, bad-config fallback,
  throttle) needs a RED-proven test before its GREEN can count. Hook wiring is
  the only glue-shaped slice; it is still asserted behaviorally (hook stays
  non-blocking) so tdd across the board keeps the evidence uniform.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: multi-surface, PR-bound change that edits the runtime
  SessionStart hooks (`hooks/session-start.sh` + `.ps1`) — a regression there
  breaks EVERY session on every target project, so isolating the work from the
  live tree is prudent. Not `required`: no `protected_paths_l3` surface is
  touched (state engine, allocator, guards, WORKFLOW.md, CONSTITUTION.md are
  all untouched).
- User decision: undecided
- Base ref: feat/auto-update-config
- Worktree branch/path: to be decided at Implementation Preparation
- Inline review scope: .aai/scripts/update-check.mjs, docs/ai/update-config.yaml, hooks/session-start.sh, hooks/session-start.ps1, .aai/system/PROFILES.yaml, tests/skills/test-aai-update-check.sh

Allowed worktree recommendation values: not_needed | optional | recommended | required
Allowed user decision values: undecided | worktree | inline | waived

## Acceptance Criteria Mapping

- Maps to: CHANGE AC-001
  - Spec-AC-01: WHEN config `mode` is `notify` (or the config file is absent)
    and the pin is behind the canonical source, the check SHALL print a clear
    "newer AAI release available" line and SHALL change NO repository files
    (the runtime throttle cache under `.aai/cache/` is the only permitted
    write), exiting non-failing.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-001, TEST-002.

- Maps to: CHANGE AC-002 (auto sync — DETACHED, owner-authoritative model)
  - Spec-AC-02: WHEN config `mode` is `auto` and the pin is behind, the check
    SHALL apply the existing `aai-update` sync as a side effect of normal use
    WITHOUT blocking session start and WITHOUT losing the outcome: it SHALL
    spawn the sync FULLY DETACHED (its own session/process group, own stdio),
    return immediately, and the detached child SHALL record the outcome
    (`applied` / `failed` / `refused` with started/finished timestamps + target
    version) in a persistent outcome log under `.aai/cache/`. The availability
    line SHALL still surface. Exiting non-failing.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-003 (detached
    outcome eventually applied) and TEST-014 (REAL hook exits fast, sync
    detached, outcome eventually written).

- Maps to: CHANGE AC-002 (canonical guard)
  - Spec-AC-03: WHEN `mode` is `auto` and the current project is the canonical
    AAI repo (origin slug equals the update source), the check SHALL NOT mutate
    the vendored layer — the reused `aai-update` origin-slug guard refuses — and
    SHALL surface a "refused (canonical repo)" note, exiting non-failing.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-004.

- Maps to: CHANGE AC-002 (offline degrade)
  - Spec-AC-04: WHEN the canonical source is unreachable (layer-drift verdict
    `unverifiable`), the check SHALL emit a clear "could not check for AAI
    updates" note and exit non-failing in BOTH modes, performing NO sync.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-005, TEST-006.

- Maps to: CHANGE AC-003 (config validation + default)
  - Spec-AC-05: WHEN the config file is absent the effective mode SHALL default
    to `notify` (back-compat), AND WHEN `mode` holds an unknown value the check
    SHALL reject it with a clear stderr error and fall back to `notify` (never
    auto-sync on a typo), exiting non-failing.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-007, TEST-008.

- Maps to: CHANGE (throttle, Design sketch + Constraints)
  - Spec-AC-06: WHEN a check completed within the throttle window (default 24h,
    key `throttle_hours`, stored in `.aai/cache/update-check.json`) the next
    invocation SHALL skip the network probe and emit no notify (fast path); WHEN
    outside the window or invoked with `--force` it SHALL probe; AND a
    FUTURE-DATED or unparseable cache timestamp SHALL be treated as
    never-checked (force a probe) so a bad timestamp never throttles notify AND
    updates forever (self-heals by re-stamping the cache on the next probe).
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-009, TEST-010,
    TEST-017.

- Maps to: CHANGE (TRIGGER — primary usage-moment)
  - Spec-AC-07: The SessionStart hook (`hooks/session-start.sh` and `.ps1`,
    wired in `hooks/hooks.json`) SHALL invoke the check best-effort so its
    output is surfaced in the injected session context, AND a check failure,
    timeout, or slow network SHALL never break, block, or delay session start —
    the meta-skill context SHALL still be emitted and the hook SHALL still exit
    0.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-011, TEST-012.

- Maps to: governance (new `.aai/**` file)
  - Spec-AC-08: The new `.aai/scripts/update-check.mjs` SHALL be classified in
    `.aai/system/PROFILES.yaml` so the profile union still equals the vendored
    `.aai` tree exactly.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-013 and the
    existing `tests/skills/test-aai-layer-profiles.sh` TEST-001.

- Maps to: CHANGE AC-002 (detached model — outcome durability + no orphan surprise)
  - Spec-AC-09: WHEN a completed-but-unreported detached-sync outcome exists in
    the outcome log, the NEXT check run SHALL surface it exactly once (`applied`
    with a review-the-diff hint, `failed` with detail, or `refused (canonical
    repo)`) and then mark it reported so it shows once; AND WHILE a detached
    sync is in flight (a non-stale `running` marker), a subsequent run SHALL NOT
    launch a duplicate sync (concurrent-sync guard). Exiting non-failing.
  - Verification: `tests/skills/test-aai-update-check.sh` TEST-015
    (report-next-session, shown once) and TEST-016 (concurrent-sync guard).

## Design decisions

- D1 (owner-authoritative, 2026-07-29): AUTO-SYNC ON SESSION-START =
  DETACHED + REPORT-NEXT-SESSION. Code review found the original synchronous
  auto path unsafe: the SessionStart hook's ~15s watchdog is shorter than
  update-check's ~40s aai-update budget, so a slow sync's node parent is
  SIGKILLed while `kill -9` reaches only node's PID (not the process group) —
  orphaning the child aai-update, which finishes the layer mutation in the
  background AFTER session start with the "review the diff" outcome LOST. The
  owner directed that auto mode apply as a side effect of normal use but MUST
  NOT block session start and MUST NOT lose the outcome. Resolution: the hook
  runs only FAST detection; on `behind` + auto it spawns the sync FULLY
  DETACHED (node `spawn` with `detached:true` + `unref()` + its own stdio — one
  portable mechanism that yields a new session/process group on POSIX and a new
  process group on Windows, so the ps1 hook needs no separate detached
  Start-Process), writes a synchronous `running` marker as the concurrent-sync
  guard, and returns at once. The detached child records a structured OUTCOME
  LOG at `.aai/cache/update-sync-outcome.json` (gitignored; excluded from the
  PROFILES union); the next run surfaces it exactly once. Guarantees: session
  start is never blocked; the outcome is never lost; the detach is deliberate,
  reaped (unref'd, own stdio so it never holds the hook's pipe), and logged —
  no orphan surprise; a stale (>30 min) `running` marker never wedges future
  syncs.
- D2 (from code review MINOR): a future-dated or unparseable throttle-cache
  timestamp is treated as never-checked (force a probe). A negative
  `(now - last)` would otherwise satisfy `< window` and throttle notify AND
  updates forever, and a throttled run never refreshes so it never self-heals.
- D3 (from code review NITs): the ps1 detection child drains BOTH stdout and
  stderr async (a full stderr pipe stalls the child just as a full stdout one
  does) and is reaped in a `finally` (`Kill()` then `WaitForExit()`, then
  `Dispose()`).

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                  | Status | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN mode notify (or config absent) and pin behind THEN print newer-release line and mutate no repo files    | done   | TEST-001, TEST-002 green (green-update-check-detached-20260728T234923Z.log) | —         | throttle cache is the only permitted write; notify branch asserts no repo mutation |
| Spec-AC-02 | WHEN mode auto and pin behind THEN spawn aai-update DETACHED (non-blocking), record outcome in .aai/cache log | done   | TEST-003, TEST-014 green (green-update-check-detached-20260728T234923Z.log) | —         | detached node spawn (own session or process group); real hook exits fast, outcome eventually applied; no parallel engine |
| Spec-AC-03 | WHEN mode auto and project is canonical repo THEN no layer mutation and a refused outcome (surfaced next run) | done   | TEST-004 green (green-update-check-detached-20260728T234923Z.log) | —         | reuses aai-update origin-slug guard (exit 2 / REFUSED); detached child records result refused; no mutation asserted |
| Spec-AC-04 | WHEN canonical source unreachable THEN could-not-check note and non-failing exit in both modes, no sync      | done   | TEST-005, TEST-006 green (green-update-check-detached-20260728T234923Z.log) | —         | maps layer-drift unverifiable verdict; auto never spawns unless behind |
| Spec-AC-05 | WHEN config absent THEN default notify AND WHEN mode unknown THEN stderr error and notify fallback           | done   | TEST-007, TEST-008 green (green-update-check-detached-20260728T234923Z.log) | —         | fail-safe: typo never auto-syncs; column-0 line parser |
| Spec-AC-06 | WHEN checked within throttle window THEN skip probe ELSE probe (24h or --force); future-dated cache re-probes | done   | TEST-009, TEST-010, TEST-017 green (green-update-check-detached-20260728T234923Z.log) | —         | throttle state in .aai/cache/update-check.json; future-dated or NaN treated as never-checked (self-heal); --now injects clock |
| Spec-AC-07 | SessionStart hook invokes check best-effort AND a failure or slow network never breaks or blocks the session | done   | TEST-011 (fail+hang, marker-proven), TEST-012 (static parity) green; sh + ps1 non-blocking verified live (rc 0 fast) | — | meta-skill context still emitted; hook exit 0; self-contained watchdog (no `timeout` binary); ps1 drains both pipes and reaps |
| Spec-AC-08 | New .aai/scripts/update-check.mjs classified in PROFILES.yaml so profile union equals the vendored tree       | done   | TEST-013 green + test-aai-layer-profiles.sh TEST-001 green (union == live tree) | —         | companion obligation (new .aai file) satisfied; outcome log lives under excluded .aai/cache |
| Spec-AC-09 | WHEN a completed detached-sync outcome exists THEN surface it once AND no duplicate sync while one in flight  | done   | TEST-015 (surfaced once, marked reported), TEST-016 (concurrent guard, one invocation) green (green-update-check-detached-20260728T234923Z.log) | — | report-next-session; synchronous running marker guards concurrency; stale 30 min marker never wedges |

Status values: planned | implementing | done | deferred | blocked | rejected

Gate behavior (enforced by .aai/VALIDATION.prompt.md): any planned/implementing
AC blocks PASS; any done AC with empty Evidence blocks PASS.

## Implementation plan

### Components affected
- NEW `.aai/scripts/update-check.mjs` — the notify/auto orchestrator. Node
  stdlib only (docs/TECHNOLOGY.md: zero deps, plain `node`). Responsibilities:
  1. Resolve config (default path `docs/ai/update-config.yaml`, overridable via
     `--config`). Parse with a COLUMN-0 line scan in the same discipline as
     `.aai/scripts/lib/guard-config.mjs` (no YAML lib). Keys: `mode`
     (notify|auto, default notify), `throttle_hours` (int, default 24). Absent
     file -> notify default. Unknown `mode` -> stderr error + notify fallback.
  2. Throttle: read `.aai/cache/update-check.json` (gitignored — `.gitignore`
     already ignores `.aai/cache/`; PROFILES excludes `.aai/cache/**`). If the
     last successful check is within `throttle_hours` and `--force` is absent,
     exit 0 quietly (no probe). A `--now <iso>` flag injects a deterministic
     clock for tests.
  3. Detect: run the existing drift check (import `decide`/`parsePin` from
     `layer-drift.mjs`, or spawn it with `--json`) with a bounded timeout;
     honor `--pin` and `--remote` overrides (pass-through to layer-drift for
     tests/CI). Never re-implement pin parsing or distance tiers.
  4. Decide + act:
     - verdict up_to_date / ahead (exit 0) -> quiet; refresh throttle cache.
     - verdict behind (exit 3): mode notify -> print the notify line; mode auto
       -> spawn `aai-update.{sh,ps1}` once (respecting the platform), surface
       its result; the canonical-repo guard lives inside aai-update and is NOT
       duplicated here.
     - verdict unverifiable (exit 4) -> "could not check" degrade note; refresh
       throttle cache is SKIPPED (so a transient outage retries next session).
  5. Always exit 0 for runtime outcomes (best-effort, non-blocking); exit 2
     only for CLI usage errors (unknown flag / missing value) when run manually.
     `--json` emits a single machine-readable object for tests.
  This script is ALSO the manual entrypoint (`node .aai/scripts/update-check.mjs`);
  no new slash-skill / prompt wrapper is added (keeps the prompt corpus flat).
- NEW `docs/ai/update-config.yaml` — COMMITTED (sibling of the committed
  `docs/ai/docs-audit.yaml`). Committed so the team shares one notify/auto
  policy; the file ships with `mode: notify` and a documented `throttle_hours`.
  Absent file == notify default preserves back-compat for projects that never
  adopt it.
- EDIT `hooks/session-start.sh` and `hooks/session-start.ps1` — after building
  the meta-skill CONTENT and BEFORE emitting, append the check output
  best-effort: run `update-check.mjs` under a short timeout, capture stdout,
  and swallow any error/timeout (`|| true` in bash; try/catch with a bounded
  wait in ps1) so `set -euo pipefail` / `$ErrorActionPreference = Stop` can
  never abort the hook. The notify text is concatenated onto CONTENT so it
  rides the existing platform-specific emit path (Claude/Cursor/Gemini/Codex).
  Empty check output changes the hook output byte-for-byte vs today (no notify
  line). hooks/ is a profile-independent surface (always synced) — no PROFILES
  entry needed for the hook edits.
- EDIT `.aai/system/PROFILES.yaml` — add `.aai/scripts/update-check.mjs` to the
  `core:` list (distribution & health family, alongside `aai-update.*` and
  `layer-drift.mjs`), keeping the union == live tree invariant.

### Data flows
session start -> hooks.json (SessionStart) -> session-start.sh/.ps1 ->
(best-effort, timeout-bounded) update-check.mjs -> reads update-config.yaml +
throttle cache -> layer-drift.mjs (--json / decide) -> [notify line] OR [auto:
aai-update.sh/.ps1 with its canonical guard] -> stdout note appended to
meta-skill CONTENT -> emitted to the agent.

### Edge cases
- Config present but empty / only comments -> notify default.
- `throttle_hours: 0` -> probe every session (documented escape hatch).
- Corrupt / unparseable throttle cache -> treat as "never checked" (probe),
  never crash.
- Canonical repo in notify mode -> layer-drift returns equal/ahead vs its own
  pin, so no notify line ever appears (guard-consistent by construction).
- Slow / hanging network -> the bounded timeout in both update-check AND the
  hook wrapper caps the delay; timeout is treated as unverifiable.
- Auto mode + unverifiable -> NEVER call aai-update (only `behind` triggers a
  sync).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                                          | Status  |
|----------|------------|-------------|--------------------------------------------|-----------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-update-check.sh      | notify mode + pin behind local fixture canonical THEN newer-release line printed and no repo file mutated | green   |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-update-check.sh      | notify mode + pin equal canonical THEN quiet, no notify line, exit 0                                 | green   |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-update-check.sh      | auto mode + pin behind local fixture source THEN aai-update sync spawned DETACHED, outcome eventually applied, exit 0 | green   |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-update-check.sh      | auto mode + project origin equals source slug THEN aai-update refuses (detached), refused outcome, surfaced next run, no mutation | green   |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-update-check.sh      | notify mode + unreachable source (file:// nonexistent) THEN could-not-check note, exit 0, no sync    | green   |
| TEST-006 | Spec-AC-04 | integration | tests/skills/test-aai-update-check.sh      | auto mode + unreachable source THEN could-not-check note, NO aai-update invoked, exit 0              | green   |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-update-check.sh      | config file absent + pin behind THEN behaves as notify default (line printed, no sync)              | green   |
| TEST-008 | Spec-AC-05 | integration | tests/skills/test-aai-update-check.sh      | mode set to unknown value + pin behind THEN stderr error, notify fallback, NO auto-sync             | green   |
| TEST-009 | Spec-AC-06 | integration | tests/skills/test-aai-update-check.sh      | throttle cache timestamp within window THEN probe skipped, no notify, exit 0 (no layer-drift call)   | green   |
| TEST-010 | Spec-AC-06 | integration | tests/skills/test-aai-update-check.sh      | cache outside window OR --force THEN probe runs and notify decision produced                        | green   |
| TEST-011 | Spec-AC-07 | integration | tests/skills/test-aai-update-check.sh      | run hooks/session-start.sh with update-check forced to fail/hang THEN hook exits 0 and still emits meta-skill content | green   |
| TEST-012 | Spec-AC-07 | unit        | tests/skills/test-aai-update-check.sh      | static parity: hooks.json wires SessionStart AND both session-start.sh/.ps1 invoke update-check.mjs guarded | green   |
| TEST-013 | Spec-AC-08 | unit        | tests/skills/test-aai-update-check.sh      | .aai/scripts/update-check.mjs is listed in .aai/system/PROFILES.yaml core list                       | green   |
| TEST-014 | Spec-AC-02 | integration | tests/skills/test-aai-update-check.sh      | REAL session-start.sh auto+behind THEN hook exits 0 fast (well under sync), sync detached, outcome eventually written | green   |
| TEST-015 | Spec-AC-09 | integration | tests/skills/test-aai-update-check.sh      | a completed-but-unreported outcome is surfaced once on the next run then marked reported             | green   |
| TEST-016 | Spec-AC-09 | integration | tests/skills/test-aai-update-check.sh      | a second run while a detached sync is in flight does not launch a duplicate (one invocation)         | green   |
| TEST-017 | Spec-AC-06 | integration | tests/skills/test-aai-update-check.sh      | future-dated throttle cache treated as never-checked THEN probe runs (throttled false), self-heals   | green   |

Test status values: pending -> red -> green
Notes: every Spec-AC has at least one TEST-xxx. Test IDs are stable after freeze.

## Seam analysis

- SEAM 1 (update-check -> layer-drift.mjs): update-check consumes layer-drift's
  verdict to decide notify/sync/degrade. Crossed end-to-end (real layer-drift
  against a real fixture pin, NOT mocked) by TEST-001/002/005.
- SEAM 2 (update-check auto -> aai-update.{sh,ps1}): the auto branch invokes the
  real sync AND relies on its canonical-repo guard. Crossed by TEST-003 (real
  local-fixture sync, no network) and TEST-004 (real origin-slug guard refuses).
- SEAM 3 (SessionStart hook -> update-check): the hook surfaces the notify text
  and must stay non-blocking. Crossed by running the actual hook script in
  TEST-011.
- SEAM 4 (update-check -> throttle cache file): read/write of
  `.aai/cache/update-check.json`. Crossed by TEST-009/010.
- SEAM 5 (new `.aai` file -> profile union): a new vendored file must be
  classified. Crossed by TEST-013 and the existing test-aai-layer-profiles
  suite; recorded as a companion obligation below (no residual risk).

Residual risk: live cross-repo release detection against a REAL second checkout
over the network is not fixture-provable in CI (ZERO-network policy). It is
proven only against local git fixtures + file:// remotes here; first
target-project adoption is the real-world confirmation. Recorded as RR-1.

## Verification

- Command: `bash tests/skills/test-aai-update-check.sh` (exit 0 = all pass; 42 =
  skipped deps). ZERO real network — reuse the layer-drift fixture pattern
  (local `git init` canonical repo, `file://` remotes, `file://` nonexistent
  path for the offline tier; see `tests/skills/test-aai-layer-drift.sh:80-97`).
- Command: `bash tests/skills/test-aai-layer-profiles.sh` (TEST-001 confirms the
  PROFILES union still equals the live tree after the new script is added).
- Advisory: `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-auto-update-config.md`.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  non-empty Evidence.

## Evidence contract
For each implementation / validation / TDD / code-review artifact record:
ref_id; Spec-AC and TEST-xxx links; command or review scope; exit code or
verdict; evidence path; commit SHA or diff range when available.

## Companion obligations (Planning step 3a)
- NEW `.aai/**` file (`.aai/scripts/update-check.mjs`) -> classification entry
  in `.aai/system/PROFILES.yaml` (Spec-AC-08 / TEST-013). IN SCOPE.
- Prompt-corpus bytes (`.aai/*.prompt.md`, `.aai/AGENTS.md`) -> NOT triggered:
  this change adds no prompt-corpus bytes (the engine is a script, the trigger
  is the hooks/ surface, and no new slash-skill prompt is created). If
  Implementation later adds a prompt (e.g. an aai-doctor CAT line or a manual
  skill wrapper), fold in a prompt-diet ledger true-up + TEST-012 checkpoint
  (tests/skills/lib/prompt-diet-ledger.sh) at that point.

Notes: This document defines HOW, not WHAT/WHY. Plain Markdown; no emoji.

---
id: runtime-state-consolidation
number: null
type: change
status: draft
user_visible: false
links:
  pr: []
  commits: []
---

# Change — consolidate runtime-sidecar lifecycles onto a shared primitive library

## Summary
- Every recent feature that needed local runtime state invented its own
  gitignored SIDECAR file with a hand-rolled lifecycle (staleness, atomic write,
  corruption handling, orphan cleanup). Five sidecar families now exist, and
  external review (Codex + Copilot 5d sweeps) keeps re-finding the SAME small set
  of bug classes in each new one: cross-process read-modify-write races,
  future-dated-timestamp wedges, silent-empty-on-corrupt reads, missing GC of
  aside/orphan files, and torn (non-atomic) writes.
- This is a DRY-of-proven-code change, not a speculative abstraction: four
  sidecars independently re-derived overlapping primitives, and the re-derivation
  is where the defects entered. The proposal is a shared, zero-dependency
  `runtime-file.mjs` library plus a CONVENTION pin so the NEXT sidecar is born
  correct instead of re-shipping the same five bug classes to every target
  project that vendors the `.aai` tree.
- Deliberately staged to AVOID churning code hardened this week: build the lib +
  negative-control tests, migrate exactly ONE sidecar (hitl-channel — newest,
  simplest, and currently missing atomic write) as a byte-identical proof, pin
  the convention, and leave the hardened update-check lock and the SPEC-0004
  docs-lock lease alone until a real reason touches them.

## Motivation / Business Value
- Quantified cost of bespoke lifecycles (see Bug-class analysis): ~23 substantive
  lifecycle defects across 4 sidecar families in ~2 weeks; ~17 of them (about
  74%) were caught by EXTERNAL bots in post-implementation review sweeps, not by
  internal validation — i.e. they shipped through planning + implementation +
  internal review and were only stopped at the bot gate. Each was root-caused,
  fixed, and re-tested per sidecar, paying the same debugging tax five times.
- Universality: target projects vendor the identical `.aai` scripts, so they
  inherit both the sidecars and their bug surface. One hardened implementation
  shipped once beats five near-identical implementations each carrying its own
  residuals.

## Scope
- In scope:
  - New `.aai/scripts/lib/runtime-file.mjs` (Node stdlib only) exposing the
    proven primitives distilled from the existing sidecars.
  - A negative-control test suite for each primitive (corrupt / absent / race /
    future-dated / orphan / torn-write).
  - Migrate ONE sidecar (hitl-channel.mjs) to the lib as a byte-identical proof.
  - A CONVENTION pin (new runtime sidecars MUST use the lib) + a review/docs-audit
    checklist reference.
  - Governance companions: PROFILES.yaml core classification for the new lib;
    consolidate the scattered `.gitignore` runtime-sidecar lines into one
    documented block (cheap, zero-behavior add-on).
- Out of scope (deferred / opportunistic — see Staged plan):
  - Migrating update-check.mjs (hardened this week; RR-1/RR-2 just closed).
  - Migrating docs-lock.mjs (SPEC-0004 O_EXCL lease, its own battle-tested suite).
  - A unified single-ledger design (rejected — see Design).
  - Force-migrating the append-ledgers (friction / EVENTS / LOOP_TICKS) — they
    use a different atomicity model (O_APPEND under PIPE_BUF), documented as a
    separate primitive, not converted.

## Affected Area
- `.aai/scripts/lib/runtime-file.mjs` (new), `.aai/scripts/hitl-channel.mjs`
  (migrated), `.aai/system/PROFILES.yaml`, root `.gitignore`, a convention doc
  (`.aai/AGENTS.md` pointer or a `lib/` README), and the test suites under
  `tests/skills/`.

## Inventory — every gitignored runtime sidecar

| Sidecar (path) | Owner script | Staleness rule | Atomic write | Corruption behavior | Known past bugs (evidence) |
|---|---|---|---|---|---|
| .aai/cache/update-check.json (throttle) | update-check.mjs | throttle_hours (24h default); future-dated -> treated as never-checked (self-heal) | best-effort writeFileSync (idempotent single field) | corrupt/absent -> null -> probe (never crash) | future-dated cache throttled forever (Copilot, #194); throttle_hours "24h"/"0x10" coerced (Copilot, #194) |
| .aai/cache/update-sync-outcome.json | update-check.mjs | `running` marker aged by SYNC_STALE_MS (30min), symmetric | writeOutcome best-effort; surfacing via atomic rename claim | corrupt/absent -> null (nothing to report) | RR-2 dup surfacing (internal code review, #194); orphaned .surfacing.* not recovered (Codex P2 Finding C, #196); false "No changes were forced" message (Copilot, #194) |
| .aai/cache/update-sync.lock (+ .reclaim, .rec.*, .surfacing.* asides) | update-check.mjs | lockIsStale symmetric SYNC_STALE_MS; parseable aged by started_utc, torn aged by mtime | claimLockFile: temp+linkSync (O_EXCL), wx fallback | torn/empty lock aged by mtime; NaN ts -> reclaimable | RR-1 concurrent-sync TOCTOU (internal review, #194); concurrent stale-reclaim double-spawn + torn-empty-window mtime mis-age (internal validation, #196); linkSync-unsupported silent never-run (Codex P2 Finding A, #196); release deletes reclaimer's lock (Codex P2 Finding B, #196) |
| docs/ai/hitl-channel.json | hitl-channel.mjs | none (entries carry posted_utc/resolved flags; poll compares reply created_at > posted_utc) | saveSidecar = plain writeFileSync (NOT atomic — latent) | absent -> empty; corrupt -> {corrupt:true} loud degrade | resolved never set true -> poll re-surfaces forever + stale answer bleeds to new token (internal validation, #205); token-reuse across rides (Codex P1 :281, #205); followup didn't retire question (P2, #205); comments not paginated (P2, #205); corrupt read-as-empty (P2 :121, #205) |
| docs/ai/friction/observations.jsonl | aai-friction.mjs | none (append-only spool; pruned by METRICS_FLUSH after 7d) | O_APPEND, per-line < PIPE_BUF (atomic by construction) | n/a (append-only; rejected input never writes) | concurrency race then PIPE_BUF atomicity gap (2 internal remediation rounds, #202/SPEC-0078); privacy leaks impact:critical + unlisted-TLD FQDN (bot, RFC-0013 v2) |
| docs/ai/briefs/{ref-id}.md | Planning (BRIEF_TEMPLATE) + prune-stale-briefs.mjs | pruned when owning doc reaches a TERMINAL status or is orphaned | template write | parse-fail -> id 'unknown' -> KEEP (safe) | over-prune on unknown/future status; unwrapped FS error crashes caller (Codex+Copilot P2, #153) |
| docs/ai/locks/<scope>.lock (+ .reclaim sentinel) | docs-lock.mjs | TTL lease (1800s) + sentinel SENTINEL_STALE_MS (30s) | fs.openSync 'wx' (O_EXCL) single-syscall CAS | corrupt/unparseable -> fail-closed (never clobber) | review-E1 double-claim reclaim race (fixed at design); the mature O_EXCL reference impl |
| docs/ai/STATE.yaml + LOOP_TICKS.jsonl | state-engine.mjs / state.mjs | per-dev; reaper ages LOOP_TICKS | tmp-<pid> + rename + optimistic-concurrency recheck | protected-path; validated by check-state | the mature atomic-write reference impl (SPEC-0012 D3) |
| docs/ai/reports/**, docs/ai/tdd/**, docs/ai/loop/** | validate-report / TDD evidence / loop | pruned by METRICS_FLUSH (7d) | file writes | ephemeral evidence | (evidence spools; low lifecycle complexity) |

Two implementations are already MATURE and correct — state-engine (atomic
tmp+rename + optimistic recheck) and docs-lock (O_EXCL lease + serialized
reclaim). They are the reference for the lib's write and claim primitives. Every
NEWER sidecar re-derived a subset of what those two already solved, and that
re-derivation is where the defects entered.

## Bug-class analysis (quantified)

Recurring classes and which sidecars hit them (a class x sidecar matrix):

| Bug class | update-check | hitl-channel | friction | prune-briefs | docs-lock | Found by |
|---|---|---|---|---|---|---|
| A. Cross-process read-modify-write / TOCTOU race | RR-1, RR-2, concurrent-reclaim | (idempotence only) | concurrency race | — | E1 (fixed at design) | bot + internal |
| B. Silent-empty on corrupt read | (avoided: null->probe) | corrupt-as-empty (shipped) | n/a | parse-fail handling | fail-closed | bot (:121, #205) |
| C. Future-dated / clock-skew timestamp wedge | cache throttle-forever; started_utc guard wedge | — | — | over-prune future status | — | bot (#194, #153) |
| D. No GC of aside / orphan files | .surfacing orphan; .reclaim/.rec | — | — | — | stale sentinels (handled) | bot (Finding C, #196) |
| E. Non-atomic / torn write window | openSync-wx empty window (fixed via linkSync) | saveSidecar plain write (latent) | O_APPEND (correct) | — | O_EXCL (correct) | internal validation (#196) |
| F. Staleness helper re-implemented (no shared symmetric window / injectable clock) | SYNC_STALE_MS | — | — | — | SENTINEL_STALE_MS | (each reinvents) |

Counting substantive lifecycle defects (excludes pure cosmetic/doc-drift and
test-only findings):

- update-check.mjs: ~12 (RR-1, RR-2, future-date cache, future started_utc,
  throttle coercion, false failure message, source-agreement, detached-to-
  completion SIGKILL, pwsh ENOENT, linkSync fallback, owner-token release,
  orphan-surfacing recovery, concurrent-reclaim torn-window). Bot-found post-
  implementation: 9. Internal (code review / validation): 3.
- hitl-channel.mjs: 5 (resolve-lifecycle, token-reuse, followup-retire,
  pagination, corrupt-as-empty). Bot-found: 4. Internal: 1.
- aai-friction.mjs: 4 (concurrency race, PIPE_BUF gap, impact:critical leak,
  FQDN leak). Bot-found: 2. Internal: 2.
- prune-stale-briefs.mjs: 2 (over-prune unknown status, unwrapped FS crash).
  Bot-found: 2. Internal: 0.

TOTALS: ~23 lifecycle defects across 4 sidecar families. ~17 (about 74%)
surfaced by EXTERNAL bots (Codex/Copilot) in post-implementation 5d review
sweeps; ~6 by internal validation/code review. The signal is unambiguous: the
bespoke-per-sidecar approach lets the same handful of classes reach the bot gate
repeatedly. A shared, negative-control-tested primitive moves that discovery
LEFT (once, in the lib's tests) instead of re-paying it per sidecar per target
project.

## Design

Three options were considered.

### (a) Shared runtime-state library — RECOMMENDED (with (c))
`.aai/scripts/lib/runtime-file.mjs`, Node stdlib only, exposing the primitives
distilled from the mature implementations (state-engine, docs-lock) and the
hard-won update-check fixes:

- `loadOrDegrade(path, {isShape})` -> `{status:'absent'|'ok'|'corrupt', data}`.
  The hitl-channel absent-vs-corrupt distinction, generalized: a DAMAGED ledger
  is never read as empty; an absent one is a normal empty. (Closes class B.)
- `atomicWrite(path, string)` -> temp `.tmp.<pid>.<seq>` + `renameSync`, `mkdir -p`
  parent. The state-engine discipline, so no sidecar ever ships a torn write
  again. (Closes class E; fixes hitl-channel's current plain-write gap.)
- `claimExclusive(path, body)` -> the update-check `claimLockFile` pattern:
  temp+linkSync (full content the instant the lock appears — no torn window),
  with the O_EXCL `wx` fallback for hard-link-hostile filesystems; returns
  `claimed | held | error` (a genuine error is loud, never masqueraded as held).
  (Closes class A for cold-start claims.)
- `isStale(tsOrMtimeMs, nowMs, windowMs)` -> SYMMETRIC `|now - ts| > window`
  with an injectable clock; future-dated / NaN -> stale (never wedge). The
  update-check symmetric-window insight, made reusable. (Closes classes C + F.)
- `reapAsides(dir, prefix, nowMs, windowMs)` -> GC orphan/aside files older than
  the window; never touches a fresh one. The .surfacing / .reclaim / sentinel
  sweep, generalized. (Closes class D.)
- (documented, separate) `appendLine(path, line)` -> O_APPEND with the PIPE_BUF
  guard — the friction append-ledger discipline, kept DISTINCT from whole-file
  state so nobody force-fits append semantics onto rewrite semantics.

Each sidecar migrates to it opportunistically; new sidecars use it from day one.

### (b) Single unified runtime ledger — REJECTED
One JSON/JSONL with namespaced sections for throttle + outcome + hitl + friction
+ locks. Rejected honestly:
- COUPLES unrelated lifecycles: throttle is best-effort single-field; the sync
  lock needs O_EXCL exclusivity; hitl is a mutable entry list; friction is
  append-only; locks are per-scope leases. One file cannot be simultaneously
  best-effort AND exclusive AND append-only.
- One corruption kills ALL of them — the exact class-B failure, amplified from
  one feature to every feature at once.
- Breaks the per-dev vs committed and protected-path boundaries: STATE is
  per-developer gitignored; EVENTS is committed append-only; the sync lock lives
  under PROFILES-excluded `.aai/cache/`. A single file cannot satisfy those
  distinct governance rules.
- Multiplies write contention: unrelated flows (a session-start throttle probe
  and a mid-loop hitl post) would serialize on one file.
The library gives the DRY benefit (one hardened implementation of each primitive)
WITHOUT the coupling cost. It is stateless helpers over many files, not shared
state in one file.

### (c) Library + CONVENTION doc (no forced migration) — ADOPTED alongside (a)
Ship the lib AND a convention pin: new gitignored runtime sidecars MUST use
`runtime-file.mjs`; existing ones migrate opportunistically (next time a bug or a
feature touches them). This is what makes the change safe — it does not demand a
big-bang rewrite of code that is currently green.

Recommended = (a) + (c): build the lib, migrate ONE sidecar as proof, pin the
convention, defer the rest.

Zero-deps constraint is honored (Node stdlib only, matching every existing
sidecar and docs/TECHNOLOGY.md). The universality story: because target projects
vendor these scripts verbatim, shipping ONE hardened lib fixes the bug surface
for every downstream project at once and makes their next inherited feature's
sidecar correct by construction.

## Staged plan
1. Stage 1 — build `runtime-file.mjs` + a negative-control test suite (each
   primitive: corrupt / absent / race / future-dated / orphan / torn). No
   sidecar touched. Add the lib to PROFILES core (companion obligation). Do the
   `.gitignore` runtime-sidecar comment-block consolidation here (documentation,
   zero behavior change).
2. Stage 2 — migrate hitl-channel.mjs (`loadSidecar` -> `loadOrDegrade`,
   `saveSidecar` -> `atomicWrite`). Chosen because it is the NEWEST, the SIMPLEST
   lifecycle (no locks/asides), and the migration ADDS a currently-missing
   guarantee (atomic write) rather than merely reshuffling. The existing 19
   hitl-channel tests are the byte-identical regression gate.
3. Stage 3 — pin the convention (a short rule in `.aai/AGENTS.md` or a `lib/`
   README + a docs-audit / code-review checklist item): any new gitignored
   runtime sidecar uses `runtime-file.mjs`.
4. Stage 4 (deferred / opportunistic) — migrate update-check.mjs and add the
   friction append helper ONLY when a real reason next touches them. Leave
   docs-lock's SPEC-0004 O_EXCL lease alone (its own suite, no shared benefit
   worth the churn).

## Acceptance Criteria
- AC-001: `loadOrDegrade` distinguishes absent (empty, status:absent) from
  corrupt (status:corrupt) from valid (status:ok). Negative controls: absent
  file, truncated JSON, wrong-shape JSON, valid JSON — a damaged ledger is NEVER
  returned as empty.
- AC-002: `atomicWrite` is crash-safe. Negative control: a simulated crash
  between temp-write and rename leaves the target either its prior content or
  absent — never torn/partial; two concurrent writers each land a whole file.
- AC-003: `claimExclusive` is a true exclusive claim. Negative controls: two
  simultaneous claimants -> exactly one `claimed`, the other `held`; a
  hard-link-hostile filesystem (linkSync throws EPERM/ENOSYS/EOPNOTSUPP/EMLINK)
  falls back to `wx` and stays exclusive; a genuine error (e.g. EACCES) returns
  `error` (loud), never `held`.
- AC-004: `isStale` is symmetric and clock-injectable. Negative controls: a
  future-dated timestamp -> stale; a NaN/unparseable timestamp -> stale; a fresh
  timestamp -> not stale; an injected clock makes the verdict deterministic (no
  wall-clock dependence). A future-dated value NEVER wedges.
- AC-005: `reapAsides` GCs only aged orphans. Negative controls: an aside older
  than the window is removed; a fresh aside is kept; a missing directory is a
  no-op (never throws).
- AC-006: `appendLine` (append-ledger primitive) appends only lines strictly
  under PIPE_BUF and refuses an over-length line. Negative controls: concurrent
  appenders lose no line; an over-length line is rejected, not truncated.
- AC-007: hitl-channel.mjs migrated to `loadOrDegrade` + `atomicWrite` behaves
  BYTE-IDENTICALLY: all 19 existing test-aai-hitl-channel tests stay green with
  no fixture changes (read behavior identical; written bytes identical), and a
  crash mid-save now leaves the prior ledger intact (new guarantee, asserted).
- AC-008: the convention is pinned in a discoverable location and referenced by
  the code-review / docs-audit checklist so a new bespoke sidecar is flagged.
- AC-009: the new lib is classified in PROFILES.yaml core; layer-profiles
  TEST-001 stays green (profile union == live `.aai` tree).
- AC-010: the `.gitignore` runtime-sidecar lines are consolidated into one
  documented block with NO path added or removed (the ignore set is byte-
  equivalent in effect; verified by `git check-ignore` on each sidecar path).
- AC-011: no regression in untouched sidecars — update-check (31 tests),
  docs-lock, and friction suites stay green.
- AC-012: zero new runtime dependencies (Node stdlib only); the lib imports
  nothing outside `node:*`.

## Implementation status (close-ready)
Per-AC reconcile recorded as a BULLET list (not a terminal AC-Status table): the
doc stays `status: draft` until the close ceremony flips it, so an all-DONE
terminal table would trip the docs-audit false-open heuristic (delivered-but-
draft) before close. Left close-ready per the C-ride precedent. This ride
delivers intake Stages 1-3; Stage 4 (update-check / docs-lock migration + the
append helper) is deliberately FROZEN.

- AC-001 loadOrDegrade absent/corrupt/wrong-shape/ok — DONE (runtime-file.mjs
  loadOrDegrade; test-aai-runtime-file.sh TEST-001..004; RED control confirmed a
  corrupt-as-empty variant fails TEST-002/003).
- AC-002 atomicWrite crash-safety + concurrent whole-file — DONE (atomicWrite
  temp+rename; TEST-005..007, incl. a true-parallel two-writer case).
- AC-003 claimExclusive exclusive + wx fallback + loud error — DONE
  (claimExclusive; TEST-008 8-way true-parallel single-winner, TEST-009
  hard-link-hostile fallback, TEST-010 genuine error returns error not held).
- AC-004 isStale symmetric + injectable clock — DONE (isStale abs(now-ts) over
  window, NaN/future -> stale; TEST-011, TEST-012 determinism).
- AC-005 reapAsides GCs only aged orphans; missing dir no-op — DONE (reapAsides;
  TEST-013, TEST-014).
- AC-006 appendLine (append-ledger primitive) — DEFERRED to Stage 4. The intake
  Design (a) marks appendLine "(documented, separate)" and Staged plan point 4
  defers the friction append helper to "only when a real reason next touches
  them"; append vs rewrite are different atomicity models and no sidecar in this
  ride's scope needs it. Not built; documented as the separate append primitive
  in the runtime-file.mjs header.
- AC-007 hitl-channel migrated byte-identically — DONE. loadSidecar ->
  loadOrDegrade, saveSidecar -> atomicWrite; serialized bytes unchanged; the 19
  test-aai-hitl-channel tests stay green with NO fixture/assertion edits; the
  crash-safe write guarantee is newly added (asserted generically by
  runtime-file.mjs TEST-006).
- AC-008 convention pinned + review checklist — DONE (runtime-file.mjs header
  CONVENTION PIN + .aai/SKILL_CODE_REVIEW.prompt.md Verdict 2 BLOCKING-finding
  line; prompt-diet ledger true-up +196 B, TEST-012 bumped 682 -> 878).
- AC-009 PROFILES core classification; layer-profiles green — DONE
  (.aai/scripts/lib/runtime-file.mjs added to PROFILES core; test-aai-layer-
  profiles green; suite-map row aai-runtime-file added, hygiene-pack green;
  SPEC-0097 shared-lib FULL_RUN trigger applies — heavy CI lane expected).
- AC-010 .gitignore runtime-sidecar consolidation — PARTIAL / DEFERRED. The
  safety half is MET and verified: `git check-ignore` confirms every sidecar
  path (hitl-channel.json, STATE.yaml, briefs, update-sync.lock, friction
  observations) is correctly ignored, and no path was added or removed. The
  purely-cosmetic reordering of the scattered blocks into one header is deferred:
  it is outside this ride's five deliverables and risks the interleaved
  glob+negation ordering semantics — contrary to the change's own don't-churn-
  working-code discipline. No behavior change either way.
- AC-011 no regression in untouched sidecars — DONE (update-check 31, docs-lock,
  friction suites all green).
- AC-012 zero runtime deps (node:* only) — DONE (TEST-016; imports node:fs +
  node:path only).

## Verification
- New: `tests/skills/test-aai-runtime-file.sh` — the negative-control suite for
  AC-001..006, RED-before-GREEN, zero real network.
- `tests/skills/test-aai-hitl-channel.sh` (19) green post-migration (AC-007).
- `tests/skills/test-aai-update-check.sh` (31), docs-lock suite, friction suite
  green (AC-011).
- `tests/skills/test-aai-layer-profiles.sh` TEST-001 green (AC-009).
- `git check-ignore` on each sidecar path before/after (AC-010).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path <this-file>`
  CLEAN; spec-lint PASS.

## Constraints / Risks
- Ceremony L2 (behavioral, multi-surface, but no protected-path/security/data-
  integrity write). Not user_visible.
- CHURN ON PROVEN CODE is the principal risk — update-check (31 tests), docs-lock,
  friction, and hitl (19 tests) are all green and were hardened within the last
  two weeks. The STAGING is the mitigation: Stage 1 touches no sidecar; Stage 2
  touches only hitl-channel, where the lib ADDS a missing guarantee (atomic
  write) and the existing 19 tests are the exact-behavior gate; update-check and
  docs-lock are explicitly left frozen until a real reason touches them.
- PREMATURE-ABSTRACTION risk is low and evidence-bounded: four sidecars already
  independently re-derived overlapping primitives and shipped ~23 defects doing
  so — this is DRY of proven code, not speculation. The unified-ledger over-reach
  is explicitly rejected above.
- APPEND vs REWRITE atomicity are different models — the lib keeps them as
  separate primitives so nobody force-fits O_APPEND onto whole-file state (or
  vice-versa). EVENTS.jsonl / LOOP_TICKS / friction stay on the append path.
- No secrets referenced (no secrets preflight required).

## Notes
- Evidence base: update-check lifecycle in `.aai/scripts/update-check.mjs`
  (RR-1/RR-2 + Findings A/B/C, CHANGE-0091 #194 + CHANGE-0093 #196); hitl-channel
  in `.aai/scripts/hitl-channel.mjs` (CHANGE-0102 / SPEC-0111 #205, 8-finding 5d
  sweep); friction in `.aai/scripts/aai-friction.mjs` (CHANGE-0045 / SPEC-0078
  #202, 2 remediation rounds + RFC-0013 v2 bot findings); prune-stale-briefs in
  `.aai/scripts/prune-stale-briefs.mjs` (CHANGE-0054 #153). Reference
  implementations: `.aai/scripts/lib/state-engine.mjs` (atomic tmp+rename, SPEC-
  0012 D3) and `.aai/scripts/docs-lock.mjs` (O_EXCL lease + serialized reclaim,
  SPEC-0004).
- Related open item: ISSUE-0012 (aai-update mktemp TOCTOU) is the same class-A
  family in the sync path, out of scope here but reinforces the pattern.
- Implementation mode (user choice): let Planning decide (default). This intake
  is analysis + parking only; no strategy recorded.

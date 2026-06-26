---
id: SPEC-0005
type: spec
status: done
links:
  requirement: null
  rfc: RFC-0005
  pr: []
  commits: []
---

# SPEC-0005 — Automatic Parallel-Mode Detection for the Loop (independence selector + SKILL_LOOP wiring)

SPEC-FROZEN: true

## Links
- Parent RFC (WHAT/WHY + chosen Option B): docs/rfc/RFC-0005-automatic-parallel-mode-detection.md
- Enforcement floor reused (atomic scope locks + single-writer): docs/specs/SPEC-0004-enforced-multi-agent-state-locking.md
- Lock primitive consumed (degrade signal): .aai/scripts/docs-lock.mjs
- Parallel scheduler routed to (unchanged mechanics): .aai/ORCHESTRATION_PARALLEL.prompt.md
- Single scheduler routed to: .aai/ORCHESTRATION.prompt.md
- Wiring point made mode-aware: .aai/SKILL_LOOP.prompt.md ("RUN ORCHESTRATION" step)
- Single-writer merge protocol (unchanged): .aai/SUBAGENT_PROTOCOL.md
- Style reference for the new helper: .aai/scripts/docs-lock.mjs (ESM CLI conventions)
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in RFC-0005)
RFC-0004 shipped the parallel-safety primitives (atomic scope locks, hard
single-writer rule) and a parallel scheduler (`ORCHESTRATION_PARALLEL.prompt.md`)
already exists, but the capability is operationally unreachable: `SKILL_LOOP`'s
"RUN ORCHESTRATION" step hard-dispatches the single-agent
`ORCHESTRATION.prompt.md` every tick. This spec adds the missing piece —
**automatic, fail-closed detection** of when a tick may safely run parallel, and
the **wiring** that routes the loop to the single or parallel orchestrator
accordingly — reusing the existing scheduler, locks, and merge protocol. It does
NOT add new orchestration mechanics, a new lock, or a new merge path.

The honest split (per RFC-0005 open question): the MECHANICAL, frozen, unit-
testable core is a deterministic selector script
(`.aai/scripts/orchestration-mode.mjs`) with a strict input/output JSON contract.
The prompt/process half (the LLM loop actually invoking the selector and honoring
its decision) is partly process, asserted by grep/text assertions exactly as
SPEC-0004's Spec-AC-08 does — not over-claimed as runtime-enforced.

## Design decisions (load-bearing — read before implementing)

### D1 — A deterministic selector script is the frozen core (not prose rules)
Independence is computed by `.aai/scripts/orchestration-mode.mjs`, an ESM node
CLI matching `docs-lock.mjs` conventions (`#!/usr/bin/env node`, `node:fs`/
`node:path` only, header usage block, `parseArgs`, `fail(msg, code)`). It is a
PURE decision function over a normalized JSON input — no STATE/spec parsing, no
clock, no concurrency — so it is fully unit-testable and deterministic. Reading
STATE.yaml + specs to BUILD that input is the orchestrator's responsibility
(prose, grep-asserted in D7/Spec-AC-10), kept OUT of the frozen core on purpose;
the helper trusts its caller and fails closed on anything it cannot prove safe.

### D2 — Input contract (stdin or `--input <file>`)
A single JSON object:

```json
{
  "orchestration_mode": "auto",        // auto | single | parallel  (default auto)
  "k_max": 2,                           // integer >= 1 (default 2)
  "max_k_budget": null,                 // optional int budget-derived ceiling; null = unbounded
  "locks_available": true,              // false when .aai/scripts/docs-lock.mjs is absent
  "scopes": [
    {
      "id": "SPEC-A",
      "role_kind": "write",            // read = validation|code_review ; write = implementation|tdd|remediation
      "review_scope_paths": ["apps/web/dashboard/"],
      "isolation": "inline",           // inline | worktree (relevant for write scopes)
      "parent": null,                   // links parent id, or null
      "children": []                    // links child ids
    }
  ]
}
```

`scopes` is the orchestrator's list of ACTIONABLE scopes for this tick (a scope
with a next role ready to dispatch), already in PRIORITY order
(ORCHESTRATION_PARALLEL priority). Unknown extra keys are ignored.

### D3 — Output contract (stdout JSON, exit 0)
```json
{
  "mode": "parallel",                  // single | parallel
  "k": 2,                               // chosen fan-out (1 when single)
  "groups": [
    { "kind": "parallel",   "scopes": ["SPEC-A", "SPEC-B"] },
    { "kind": "sequential", "scopes": ["SPEC-C"] }
  ],
  "reasons": { "SPEC-C": "deferred: k_cap reached (k_max=2)" }
}
```
- Exactly one `parallel` group MAY exist (the scopes co-scheduled THIS tick);
  every other actionable scope is its own `sequential` singleton group (runs a
  later tick). When `mode == single`, there is no `parallel` group — the
  highest-priority scope is the single `sequential` group that runs.
- `reasons` records, per excluded/deferred scope, WHY it was not parallelized
  (uncertain / conflicts-with-X / k_cap / budget / locks_unavailable / override),
  so a human reading STATE/tick log sees why a tick went the way it did.

### D4 — Independence (the safety core): path-overlap + fail-closed
For each scope compute `effective_paths`:
- A scope is **uncertain** if it has zero `review_scope_paths`, OR any path is
  empty/whitespace, OR any path is a bare/leading glob that reduces to an empty
  literal prefix (e.g. `*`, `**`, `*.md`). `normalizePath(p)`: trim; strip a
  single trailing `/`; drop a trailing `/**` or `/*` segment; if an interior `*`
  remains, keep the literal prefix up to the first glob segment; if that prefix
  is empty -> uncertain.
- A **write scope with `isolation == "worktree"`** has guaranteed-disjoint writes
  (isolated working tree); its `effective_paths` are treated as empty for
  collision purposes and it is NOT uncertain on the path axis.

`conflict(S1, S2)` is true iff ANY of:
1. `uncertain(S1)` OR `uncertain(S2)` — fail-closed; cannot prove disjoint.
2. `S1` is `S2`'s parent or child in the links graph (`parent`/`children`).
3. `effective_paths(S1)` overlaps `effective_paths(S2)`, where two normalized
   paths overlap iff equal OR one is a path-boundary prefix of the other
   (`b === a` or `b.startsWith(a + "/")`).

Conservatism note: path overlap is a conflict for ANY `role_kind`. Reads on
overlapping paths never corrupt anything, so treating them as a conflict only
costs throughput, never safety — and it keeps the rule one line. The `role_kind`
/ `isolation` axis governs the ISOLATION REQUIREMENT for WRITES (D5), not whether
overlap is a conflict.

### D5 — Read vs write isolation requirement
- Read-only roles (validation, code review) across non-conflicting (disjoint)
  scopes are always safe to parallelize — no worktree needed.
- A write role (implementation/tdd/remediation) may parallelize only when it is
  provably disjoint: `isolation == "inline"` with declared, non-overlapping,
  non-uncertain paths, OR `isolation == "worktree"` (isolated writes). An inline
  write scope that cannot prove disjoint paths is uncertain (D4.1) -> sequential.
  The selector NEVER creates a worktree; it only consumes the declared
  `isolation` value (the worktree decision remains the user/orchestrator gate).

### D6 — Mode selection, K cap, degrade, budget, overrides
Let `effective_cap = min(k_max, max_k_budget ?? +inf, locks_available ? +inf : 1)`.
Greedily build the parallel group in input (priority) order: add a scope iff it
is not uncertain AND conflicts with no scope already in the group AND the group
size `< effective_cap`. Then:
- `orchestration_mode == "single"` -> ALWAYS `mode=single`, `k=1` (override wins
  over everything; the single highest-priority scope runs).
- Otherwise if the built group size `>= 2` -> `mode=parallel`,
  `k = group size = min(k_max, count_of_mutually_independent_scopes, budget cap)`;
  the group is the parallel group, all other scopes are sequential singletons.
- Otherwise -> `mode=single`, `k=1` (single scope, all-conflicting scopes, or any
  cap forcing `< 2`). Zero added overhead in the single case.
- `orchestration_mode == "parallel"` uses the SAME safety-gated selection as
  `auto` (it is an opt-in signal, never a safety override): parallel iff `>= 2`
  mutually independent scopes exist, single otherwise.

Consequences of the cap formula (all frozen-tested):
- `locks_available == false` (docs-lock.mjs absent) -> `effective_cap = 1` ->
  `mode=single`, `k=1` (degrade-and-report; never parallel without enforceable
  locks).
- `max_k_budget` reduces K: `=1` -> single; `=2` with 3 independent and `k_max=3`
  -> `k=2`. Respects the loop run-budget stop (reduce K or go single).
- `k_max` default `= 2` (justification D8); `>k_max` independent scopes -> `k=k_max`.

### D7 — SKILL_LOOP wiring (partly process; grep-asserted core)
`.aai/SKILL_LOOP.prompt.md`'s "RUN ORCHESTRATION" step (currently a hard dispatch
of `ORCHESTRATION.prompt.md`) becomes MODE-AWARE: before dispatch it (a) discovers
actionable scopes, (b) gathers each scope's declared review-scope paths from the
spec's `code_review.scope` / `worktree.inline_review_scope` / STATE affected paths
and whether `docs-lock.mjs` is present, (c) invokes the selector
`orchestration-mode.mjs`, (d) dispatches `ORCHESTRATION.prompt.md` when
`mode=single` or `ORCHESTRATION_PARALLEL.prompt.md` when `mode=parallel`, and (e)
records `orchestration.mode` / `orchestration.k` / `orchestration.groups` in
`docs/ai/STATE.yaml` and the tick log line (LOOP_TICKS.jsonl). Be honest: that a
live LLM loop actually performs (a)-(e) is process, not mechanically enforced;
the testable core is (1) the selector + its JSON contract (D2/D3, Spec-AC-01..09)
and (2) the presence of this wiring text + the STATE/doc fields, asserted by grep
(Spec-AC-10..12), exactly as SPEC-0004 Spec-AC-08 handled its prompt wiring.
`ORCHESTRATION_PARALLEL.prompt.md` and `ORCHESTRATION.prompt.md` each gain a
one-line cross-reference to the selector so a maintainer can follow the routing.

### D8 — K_max default = 2; budget-aware
`k_max` default is 2, matching `ORCHESTRATION_PARALLEL.prompt.md`'s existing
conservative fan-out default. Rationale: parallel fan-out multiplies token/compute
spend; a conservative default keeps unattended cost bounded while still halving
wall-clock for the common two-independent-scope case. Larger K is opt-in via
`k_max` and is additionally bounded by `max_k_budget` derived from the loop's
run-budget. The operator override (`orchestration_mode`) and the budget ceiling
let a human cap or disable parallelism without code changes.

### D9 — STATE schema: optional, non-breaking `orchestration` block
`docs/ai/STATE.yaml` gains an optional `orchestration:` block
(`mode: auto|single|parallel` default `auto`, `k`, `groups`) documented in the
schema-comment header. ABSENT block == `auto` (back-compat): existing single-scope
projects behave exactly as before. `orchestration.mode` is also the override input
(STATE field, overridable by a loop arg per RFC-0005 open question — STATE field
is the durable default).

## Implementation strategy
- Strategy: hybrid
- Rationale: the selector (`orchestration-mode.mjs`) is safety-critical decision
  logic whose core property is a fail-closed independence invariant ("scopes with
  overlapping or unprovable paths are NEVER co-scheduled"). That demands TDD with
  a real RED — the overlap/fail-closed tests must be observed FAILING against a
  deliberately naive overlap-BLIND selector (one that parallelizes any >=2
  actionable scopes, ignoring path overlap — the Option C failure the RFC
  rejected) before the real selector turns them GREEN; a safety test never seen
  failing proves nothing (mirrors SPEC-0004 TEST-003's non-O_EXCL stub). So
  Spec-AC-01..09 (TEST-001..014) are TDD against `DOCS_SELECTOR_SCRIPT`-style
  stub substitution. The SKILL_LOOP / orchestrator / STATE-schema / USER_GUIDE /
  CHANGELOG edits (Spec-AC-10..12, TEST-015..017) are low-risk prose wiring where
  RED-GREEN adds little beyond a grep assertion, so they run as a loop segment.
  Hybrid = TDD for the selector, loop for the wiring/docs.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: additive change — one new script
  (`orchestration-mode.mjs`), one new test file, and edits to two workflow prompts
  (`SKILL_LOOP`, the two orchestrators), the STATE schema comment, `USER_GUIDE.md`
  and `CHANGELOG.md`. No STATE migration, no schema-breaking change (the
  `orchestration` block is optional/back-compat), no cross-cutting refactor, no
  change to the lock primitive or merge protocol. The work already sits on the
  dedicated feature branch `feat/auto-parallel-detection`, which isolates from
  `main`; a separate git worktree would add ceremony without added safety, and
  every edit is trivially reversible. It touches protected workflow prompts but
  only by addition.
- User decision: inline (already recorded in STATE.yaml worktree.user_decision; no
  further user decision required because recommendation is not_needed)
- Base ref: main
- Worktree branch/path: n/a (inline on feat/auto-parallel-detection)
- Inline review scope:
  - `.aai/scripts/orchestration-mode.mjs`
  - `tests/skills/test-aai-orchestration-mode.sh`
  - `.aai/SKILL_LOOP.prompt.md`
  - `.aai/ORCHESTRATION_PARALLEL.prompt.md`
  - `.aai/ORCHESTRATION.prompt.md`
  - `docs/ai/STATE.yaml` (schema-comment header only)
  - `docs/USER_GUIDE.md`
  - `CHANGELOG.md`
  - `docs/specs/SPEC-0005-automatic-parallel-mode-detection.md`

## Acceptance Criteria Mapping

- Maps to: RFC-0005 Proposal part 1 + Open Question "helper, unit-testable"
  - Spec-AC-01: `.aai/scripts/orchestration-mode.mjs` exists as an ESM node CLI
    that reads the D2 input JSON (stdin or `--input <file>`) and prints the D3
    output JSON `{mode,k,groups,reasons}` with exit `0`; missing/empty input,
    malformed JSON, or an unknown flag prints usage and exits `2`.
  - Verification: TEST-001.

- Maps to: RFC-0005 Proposal part 2 (independence test — the safety core)
  - Spec-AC-02: two actionable scopes with DISJOINT declared review-scope paths
    are co-scheduled — `mode=parallel`, `k=2`, ONE `parallel` group containing
    BOTH; two scopes with OVERLAPPING declared paths are NEVER co-scheduled
    (`mode=single` / not in one parallel group), with a conflict reason recorded.
  - Verification: TEST-002 (disjoint -> parallel), TEST-003 (overlap -> sequential;
    RED-proofed vs an overlap-blind selector).

- Maps to: RFC-0005 Proposal part 2 (fail-closed) + Risks (undeclared scopes)
  - Spec-AC-03: a scope whose review-scope path is MISSING/empty or UNPARSEABLE
    (bare/leading glob reducing to empty prefix) is treated as NOT independent
    (uncertain) and is never placed in a parallel group; alongside a second
    disjoint scope it is the sequential singleton.
  - Verification: TEST-004 (missing/empty path), TEST-005 (unparseable glob).

- Maps to: RFC-0005 Proposal parts 1+6 (mode selection, no overhead, default auto)
  - Spec-AC-04: a single actionable scope -> `mode=single`, `k=1`, no parallel
    group (zero overhead); two mutually independent actionable scopes under default
    `orchestration_mode=auto`, `k_max=2` -> `mode=parallel`, `k=min(k_max,count)=2`.
  - Verification: TEST-006 (single scope), TEST-007 (two independent -> parallel).

- Maps to: RFC-0005 Controls (K_max cap) + D8
  - Spec-AC-05: with more mutually independent scopes than `k_max`, `k = k_max`,
    the parallel group has exactly `k_max` scopes, and the remainder are sequential
    singletons (deferred).
  - Verification: TEST-008.

- Maps to: RFC-0005 Proposal part 4 + Risks (read vs write isolation)
  - Spec-AC-06: read-only roles (validation/code_review) across disjoint scopes
    parallelize; a write role parallelizes only when provably disjoint — inline
    with non-overlapping declared paths OR `isolation=worktree`; an inline write
    scope that cannot prove disjoint paths is sequential.
  - Verification: TEST-009 (read disjoint -> parallel), TEST-010 (write inline
    unprovable -> sequential; write worktree -> independent).

- Maps to: RFC-0005 Controls (degrade-and-report; docs-lock absent => K=1)
  - Spec-AC-07: when `locks_available=false` (docs-lock.mjs absent), even >=2
    independent scopes yield `mode=single`, `k=1` (never parallel without locks),
    with a `locks_unavailable` reason.
  - Verification: TEST-011.

- Maps to: RFC-0005 Controls (respect run-budget; reduce K or go single)
  - Spec-AC-08: `max_k_budget` caps fan-out — `=1` forces `mode=single`; `=2` with
    3 independent scopes and `k_max=3` yields `k=2`.
  - Verification: TEST-012.

- Maps to: RFC-0005 Controls (override auto|single|parallel; Alternative A retained)
  - Spec-AC-09: `orchestration_mode=single` forces `mode=single`/`k=1` even with
    >=2 independent scopes; `orchestration_mode=parallel` respects independence as
    an opt-in — parallel when scopes are independent, single when they overlap
    (never an unsafe override).
  - Verification: TEST-013 (single override), TEST-014 (parallel override
    respects independence both ways).

- Maps to: RFC-0005 Proposal part 5 (SKILL_LOOP wiring) + D7
  - Spec-AC-10: `.aai/SKILL_LOOP.prompt.md`'s "RUN ORCHESTRATION" step is
    mode-aware: it references the selector (`orchestration-mode.mjs`), dispatches
    `ORCHESTRATION.prompt.md` for single and `ORCHESTRATION_PARALLEL.prompt.md` for
    parallel, and records `orchestration.mode`/`k`/`groups` in STATE + the tick
    log; `ORCHESTRATION_PARALLEL.prompt.md` and `ORCHESTRATION.prompt.md` each
    cross-reference the selector.
  - Verification: TEST-015 (grep assertions across the prompts).

- Maps to: RFC-0005 Consequences (STATE schema additions; non-breaking)
  - Spec-AC-11: `docs/ai/STATE.yaml`'s schema-comment header documents the optional
    `orchestration.mode` (auto|single|parallel), `orchestration.k`, and
    `orchestration.groups` fields, and states that an absent block == `auto`
    (back-compat).
  - Verification: TEST-016 (grep the schema header).

- Maps to: RFC-0005 Consequences (user docs + CHANGELOG; retroactive docs-lock line)
  - Spec-AC-12: `docs/USER_GUIDE.md` has a "Parallel multi-agent orchestration"
    section documenting `auto`/`single`/`parallel`, the `k_max=2` default, the
    docs-lock degrade-to-single behavior, and how to override; `CHANGELOG.md` has
    an entry for RFC-0005 that also retroactively records the RFC-0004 `docs-lock`
    primitive.
  - Verification: TEST-017 (grep USER_GUIDE + CHANGELOG).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | orchestration-mode.mjs CLI exists; reads D2 input, prints D3 {mode,k,groups,reasons}; bad input/flag exits 2 | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-02 | disjoint paths -> parallel (both in one group); overlapping paths -> never co-scheduled (SAFETY) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD; RED-proof vs overlap-blind stub |
| Spec-AC-03 | missing/unparseable review-scope path -> uncertain -> sequential (fail-closed) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD; safety |
| Spec-AC-04 | single scope -> single/k=1 (no overhead); two independent (auto,k_max=2) -> parallel k=2 | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-05 | >k_max independent scopes -> k=k_max; remainder sequential | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-06 | read-only disjoint -> parallel; write parallel only if inline-disjoint or worktree; else sequential | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-07 | docs-lock absent (locks_available=false) -> single/k=1 (degrade) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-08 | max_k_budget caps K (=1 single; =2 with 3 indep -> k=2) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-09 | override single forces single; override parallel respects independence (opt-in, never unsafe) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | TDD |
| Spec-AC-10 | SKILL_LOOP RUN ORCHESTRATION mode-aware: selector + both orch prompts + STATE/tick orchestration.mode/k/groups | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | loop; partly process (D7) |
| Spec-AC-11 | STATE.yaml schema header documents optional orchestration.mode/k/groups; absent == auto | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | loop; non-breaking |
| Spec-AC-12 | USER_GUIDE parallel-orchestration section + CHANGELOG RFC-0005 entry (retroactive docs-lock) | done | TEST-001..017 green (bash tests/skills/test-aai-orchestration-mode.sh exit 0 2026-06-26T19:26Z commit 51c5c73); docs/ai/tdd/green-mode-suite-20260626T192042Z.log; RED-proof confirmed (red-mode-overlap-blind-20260626T191843Z.log); independent Validation claude-sonnet-4-6 RUN_ID:val-SPEC-0005-2026-06-26T192600Z | — | loop |

## Implementation plan
- Components/modules affected:
  - NEW `.aai/scripts/orchestration-mode.mjs`: ESM CLI. `parseArgs` (`--input
    <file>`, default stdin; unknown flag -> usage exit 2). `readInput()` ->
    parse JSON (malformed -> exit 2). Pure helpers: `normalizePath(p)`,
    `isUncertain(scope)`, `effectivePaths(scope)`, `pathsOverlap(a,b)`,
    `conflict(s1,s2)`, `selectGroups(input)` returning `{mode,k,groups,reasons}`.
    `main()` prints the output JSON, exit 0. Keep the decision functions exported
    (or import-friendly) so a unit test can call them directly, mirroring
    `lib/docs-canon-core.mjs` import-style tests.
  - EDIT `.aai/SKILL_LOOP.prompt.md`: make "RUN ORCHESTRATION" (step 3, ~lines
    158-165) mode-aware per D7 — discover actionable scopes, gather declared paths
    + docs-lock presence, invoke the selector, dispatch single vs parallel
    orchestrator on `mode`, record `orchestration.mode/k/groups` in STATE +
    LOOP_TICKS tick line.
  - EDIT `.aai/ORCHESTRATION_PARALLEL.prompt.md` and `.aai/ORCHESTRATION.prompt.md`:
    add a one-line cross-reference to the selector as the upstream mode decision.
  - EDIT `docs/ai/STATE.yaml`: add the optional `orchestration` fields to the
    schema-comment header (mode|k|groups; absent == auto). (Implementation edits
    the header; Planning does not.)
  - EDIT `docs/USER_GUIDE.md`: add "Parallel multi-agent orchestration" section.
  - EDIT `CHANGELOG.md`: RFC-0005 entry + retroactive docs-lock/RFC-0004 line.
  - NEW `tests/skills/test-aai-orchestration-mode.sh`: bash harness mirroring
    `tests/skills/test-aai-docs-lock.sh` (`set -euo pipefail`, isolated tmp,
    `log_pass`/`log_fail`/`log_skip`, exit 0/1/42), feeding JSON fixtures to the
    CLI on stdin and asserting output fields via `node -e`/`node --input-type=
    module -e`; `DOCS_SELECTOR_SCRIPT` overridable so TEST-003 can RED-proof
    against an overlap-blind stub.
- Data flows: selector input is built by the orchestrator from STATE + spec
  fields; selector output drives the dispatch branch and is mirrored into STATE
  `orchestration.*` + the tick log. No STATE writes from the selector; no lock
  writes (it only reads the `locks_available` boolean its caller computed).
- Edge cases:
  - empty `scopes` array -> `mode=single`, `k=1`, empty groups (loop has nothing
    actionable; orchestrator handles the no-op).
  - duplicate scope ids / a scope listing itself as parent -> treat as conflict
    (fail-closed); document, do not crash.
  - `k_max < 1` or non-integer -> coerce to 1 (single) rather than crash.
  - all scopes mutually conflicting -> `mode=single`, highest-priority scope runs.
  - `orchestration_mode` absent -> `auto`.

## Seam analysis
A SEAM is any place this change shares state with, or is consumed by, a feature
it does not own.

- SEAM-1 (selector `orchestration-mode.mjs` <-> SKILL_LOOP RUN ORCHESTRATION
  dispatch): the loop branches on the selector's `mode`/`k`/`groups` JSON to pick
  the single vs parallel orchestrator. The mechanically automatable half is the
  output contract itself, crossed end-to-end by the selector tests (produce a real
  decision on one side) + TEST-015 (assert SKILL_LOOP text consumes it on the
  other). RESIDUAL RISK R-WIRE: that a live LLM loop actually invokes the selector
  and honors its decision is process, grep-asserted not runtime-enforced (same
  honesty as SPEC-0004 R-WIRE).
- SEAM-2 (selector output <-> STATE `orchestration.mode/k/groups`, read by humans
  and the next tick): produce-side is the selector; consume/record-side is
  asserted by TEST-016 (schema) and the D7 wiring text (TEST-015).
- SEAM-3 (selector `locks_available` input <-> docs-lock.mjs presence): the degrade
  path depends on the orchestrator correctly detecting docs-lock.mjs. The
  selector's HALF (locks_available=false -> single) is crossed by TEST-011.
  RESIDUAL RISK R-LOCKDETECT: the orchestrator computing `locks_available` from the
  filesystem is prose, not in the frozen helper.
- SEAM-4 (independence inputs <-> spec `code_review.scope` /
  `worktree.inline_review_scope`): the selector trusts the orchestrator to supply
  declared paths; a spec that declares no scope yields uncertain -> sequential.
  TEST-004/005 cross the selector's fail-closed half. RESIDUAL RISK R-SCOPE-SOURCE:
  gathering paths from STATE/specs is prose, not in the frozen helper — but it is
  fail-SAFE (missing data can only REDUCE parallelism, never create a conflict).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                         | Description | Status |
|----------|------------|-------------|----------------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-orchestration-mode.sh  | CLI exists; no input / malformed JSON / unknown flag -> exit 2 with usage; a valid input -> exit 0 and stdout JSON with keys mode,k,groups,reasons | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-mode.sh  | two scopes with DISJOINT paths (apps/web/dashboard/ vs apps/api/export/) -> mode=parallel, k=2, one parallel group containing BOTH ids | green |
| TEST-003 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-mode.sh  | two scopes with OVERLAPPING paths (apps/api/ vs apps/api/export/) -> NOT co-scheduled (mode=single / not one parallel group), conflict reason recorded. RED-proofed against an overlap-BLIND stub that parallelizes any >=2 scopes | green |
| TEST-004 | Spec-AC-03 | unit        | tests/skills/test-aai-orchestration-mode.sh  | a scope with MISSING/empty review_scope_paths is uncertain -> never in the parallel group; with a second disjoint scope it is the sequential singleton (fail-closed) | green |
| TEST-005 | Spec-AC-03 | unit        | tests/skills/test-aai-orchestration-mode.sh  | a scope whose only path is an unparseable bare glob (`*` / `**`) reduces to empty prefix -> uncertain -> sequential | green |
| TEST-006 | Spec-AC-04 | unit        | tests/skills/test-aai-orchestration-mode.sh  | single actionable scope -> mode=single, k=1, no parallel group (no overhead) | green |
| TEST-007 | Spec-AC-04 | unit        | tests/skills/test-aai-orchestration-mode.sh  | two mutually independent scopes, default orchestration_mode=auto + k_max=2 -> mode=parallel, k=2 | green |
| TEST-008 | Spec-AC-05 | unit        | tests/skills/test-aai-orchestration-mode.sh  | three mutually independent scopes, k_max=2 -> k=2, parallel group has exactly 2, the third is a sequential singleton with a k_cap reason | green |
| TEST-009 | Spec-AC-06 | unit        | tests/skills/test-aai-orchestration-mode.sh  | two read-only scopes (role_kind=read) on disjoint paths -> mode=parallel, k=2 (read roles need no worktree) | green |
| TEST-010 | Spec-AC-06 | unit        | tests/skills/test-aai-orchestration-mode.sh  | a write scope inline with NO/unprovable paths -> sequential; a write scope with isolation=worktree -> treated independent (can join the parallel group) | green |
| TEST-011 | Spec-AC-07 | unit        | tests/skills/test-aai-orchestration-mode.sh  | locks_available=false with two independent scopes -> mode=single, k=1, locks_unavailable reason (degrade) | green |
| TEST-012 | Spec-AC-08 | unit        | tests/skills/test-aai-orchestration-mode.sh  | max_k_budget=1 with 3 independent -> mode=single; max_k_budget=2 with 3 independent and k_max=3 -> k=2 | green |
| TEST-013 | Spec-AC-09 | unit        | tests/skills/test-aai-orchestration-mode.sh  | orchestration_mode=single with two independent scopes -> mode=single, k=1 (override forces single) | green |
| TEST-014 | Spec-AC-09 | unit        | tests/skills/test-aai-orchestration-mode.sh  | orchestration_mode=parallel: two disjoint scopes -> parallel; two OVERLAPPING scopes -> single (opt-in respects independence, never overrides safety) | green |
| TEST-015 | Spec-AC-10 | integration | tests/skills/test-aai-orchestration-mode.sh  | grep: SKILL_LOOP RUN ORCHESTRATION references orchestration-mode.mjs + dispatches ORCHESTRATION.prompt.md (single) AND ORCHESTRATION_PARALLEL.prompt.md (parallel) + records orchestration.mode/k/groups; both orchestrators cross-reference the selector | green |
| TEST-016 | Spec-AC-11 | integration | tests/skills/test-aai-orchestration-mode.sh  | grep: STATE.yaml schema header documents orchestration.mode (auto|single|parallel) / k / groups and "absent == auto" back-compat note | green |
| TEST-017 | Spec-AC-12 | integration | tests/skills/test-aai-orchestration-mode.sh  | grep: USER_GUIDE.md has a "Parallel multi-agent orchestration" section (auto/single/parallel, k_max=2, docs-lock degrade, override); CHANGELOG.md has an RFC-0005 entry referencing docs-lock | green |
| TEST-018 | Spec-AC-02 | unit        | tests/skills/test-aai-orchestration-mode.sh  | post-review E1 canonicalization safety: non-literal spellings of an overlapping/whole-repo path (`.`, `./`, `//`, `..`, case variants) must NEVER co-schedule with the path they overlap (fail-closed -> mode=single), incl. under override=parallel. RED-proofed: pre-fix normalizePath skips canonicalization and co-schedules `.` vs apps/api/ as parallel | green |

RED-proof obligation (all AC-gating tests, regardless of strategy):
- TEST-001 fails before `orchestration-mode.mjs` exists (no script / no contract).
- TEST-002/003 are the SAFETY pair. TEST-003 is RED-proofed by first standing up a
  deliberately OVERLAP-BLIND selector (parallelizes any >=2 actionable scopes,
  ignoring path overlap — the rejected Option C): it co-schedules the overlapping
  scopes, so "not co-scheduled" fails RED; the real overlap test turns it GREEN. A
  safety test never seen failing proves nothing — this stub step is mandatory.
- TEST-004/005 fail RED before the fail-closed `isUncertain`/`normalizePath` logic
  (the naive selector treats the missing/glob scope as independent).
- TEST-006..014 fail RED before mode selection / k-cap / role-isolation / degrade /
  budget / override logic exist (the stub returns a fixed mode and ignores them).
  TEST-008 doubles as a positive control against an over-eager selector that
  ignores k_max; TEST-014's overlap half is a positive control that `parallel`
  does not bypass the overlap test.
- TEST-015..017 fail RED before the SKILL_LOOP / orchestrator / STATE-schema /
  USER_GUIDE / CHANGELOG edits land (grep finds none of the required strings).

## Verification
- `bash tests/skills/test-aai-orchestration-mode.sh` — TEST-001..017 green
  (exit 0; 42 if node missing).
- `printf '%s' '{"orchestration_mode":"auto","k_max":2,"locks_available":true,
  "scopes":[{"id":"A","role_kind":"write","review_scope_paths":["apps/web/"],
  "isolation":"inline"},{"id":"B","role_kind":"write","review_scope_paths":
  ["apps/api/"],"isolation":"inline"}]}' | node .aai/scripts/orchestration-mode.mjs`
  prints `mode":"parallel","k":2` with both ids in the parallel group.
- Same input with B's path changed to `apps/web/dashboard/` (overlaps `apps/web/`)
  prints `mode":"single"` and a conflict reason for B.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path
  docs/specs/SPEC-0005-automatic-parallel-mode-detection.md` reports CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  non-empty Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (RFC-0005 / SPEC-0005)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (e.g. docs/ai/tdd/red-*.log, green-*.log)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (RFC-0005 owns WHAT/WHY).
This document does not define workflow.

Post-review remediation (code review E1, 2026-06-26):
- Code review FAILED the first implementation: Spec-AC-02's absolute invariant
  ("overlapping declared paths are NEVER co-scheduled") was breakable because
  `normalizePath` did not canonicalize. Non-literal spellings of an overlapping
  or whole-repo path defeated the overlap test and came back parallel — e.g.
  `.` vs `apps/api/`, `./apps/api/`, `apps//api/`, `apps/web/../api/`, and
  case variants (`Apps/Api` on macOS) all yielded mode=parallel with both write
  scopes co-scheduled. The segment-boundary prefix case (`a/b` vs `a/bc`) was
  already SAFE. The validator's 9 overlap shapes and the 17 tests never
  exercised `.`/`./`/`//`/`..`/case, so the hole survived to the review gate.
- Fix: `normalizePath` now canonicalizes before overlap — case-folds, strips
  `.` segments, collapses `//`, resolves `..` (a path escaping its declared
  root => null/uncertain), rejects absolute paths, and reduces `.`/whole-repo/
  bare-glob to null (fail-closed). null => uncertain => never parallelized.
- New TEST-018 covers all five breaking spellings + the override=parallel case;
  RED on pre-fix (`.` co-scheduled), GREEN after. Disjoint scopes still
  parallelize and `a/b` vs `a/bc` stays independent (no over-sequentialization).
  Evidence: docs/ai/tdd/red-mode-canon-*, green-mode-canon-*.

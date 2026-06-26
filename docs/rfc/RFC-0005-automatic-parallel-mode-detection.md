---
id: RFC-0005
type: rfc
status: done
links:
  rfc: RFC-0004
  spec: SPEC-0005
  pr:
    - 14
  commits:
    - 648f0b0
---

# RFC-0005 — Automatic Parallel-Mode Detection for the Loop

## Context

### Problem or opportunity

RFC-0004 shipped the enforcement primitives for safe parallel multi-agent work:
an atomic scope-lock CLI (`.aai/scripts/docs-lock.mjs`) and a hard single-writer
rule (`SUBAGENT_PROTOCOL.md`). A parallel scheduler already exists
(`.aai/ORCHESTRATION_PARALLEL.prompt.md`). But the capability is **operationally
unreachable**: the autonomous loop (`.aai/SKILL_LOOP.prompt.md`) hard-dispatches
the single-agent `.aai/ORCHESTRATION.prompt.md` every tick, and nothing routes to
the parallel orchestrator. There is no `orchestration_mode`, no skill, no flag,
and no documentation. The lock enforcement therefore only engages if a human
manually types "Follow .aai/ORCHESTRATION_PARALLEL.prompt.md".

Concrete cost of staying single-only: a backlog of N independent frozen specs
(e.g. SPEC-A over `apps/web/dashboard/*`, SPEC-B over `apps/api/export/*`,
SPEC-C over `apps/api/auth/*`) is implemented and validated strictly
sequentially. Wall-clock is the sum of all scopes; with parallel scheduling it
would be the slowest single scope.

### Drivers/constraints

- **Minimize operator burden** (explicit user preference, 2026-06-26): the
  operator should keep running `/aai-loop` exactly as today; the loop should
  decide single vs parallel by itself. No new flag to remember for the common case.
- Parallelize ONLY genuinely independent scopes — wrong independence detection
  risks two agents mutating the same files. Safety beats throughput.
- Reuse, do not duplicate: the parallel scheduling logic
  (`ORCHESTRATION_PARALLEL.prompt.md`), the locks (`docs-lock.mjs`), and the
  single-writer merge protocol (`SUBAGENT_PROTOCOL.md`) already exist. This RFC
  is about DETECTION + WIRING + DOCS, not new orchestration mechanics.
- Bounded resource use: parallel fan-out multiplies token/compute spend; default
  must be conservative and respect the loop's existing run-budget stop.
- Degrade-and-report: if `docs-lock.mjs` is absent (older layer), fall back to
  K=1 (single) — never run parallel without enforceable locks.

### Prior art / current mechanisms studied

- RFC-0004 — atomic scope locks + single-writer rule (the enforcement floor).
- `ORCHESTRATION_PARALLEL.prompt.md` — already classifies scopes
  (NEEDS_PLANNING / READY_FOR_IMPLEMENTATION / READY_FOR_VALIDATION / ...),
  caps fan-out at K=2, and states "inline scopes can be parallelized only when
  their file/path review scopes do not overlap" — the independence rule we
  formalize.
- `ORCHESTRATION.prompt.md` — single-scope decision logic (first-match-wins).
- `SKILL_LOOP.prompt.md` step "RUN ORCHESTRATION" — the single dispatch point
  (currently hard-coded to the single orchestrator).
- RFC-0001 — per-agent-local STATE; the merge of parallel result blocks must
  remain a single-writer STATE update by the orchestrator.

## Proposal

### Recommended option

**Option B — Automatic detection with a conservative cap and an explicit
override.** Each loop tick, the orchestrator decides mode from observable STATE,
defaulting to parallel only when it is provably safe and useful:

1. **Detection (per tick):** after STATE discovery, compute the set of
   *actionable* scopes (a scope with a next role ready to dispatch:
   needs-planning, ready-for-implementation, ready-for-validation,
   ready-for-code-review, failed-* needing remediation). Partition them into
   **independent groups** by review-scope overlap (below). If >= 2 actionable
   scopes are mutually independent, run **parallel** with
   `K = min(K_max, count)`; otherwise run **single** (zero added overhead).
2. **Independence test (the safety core):** two scopes are independent iff their
   declared file/path review scopes (from each spec's `code_review.scope` /
   `worktree.inline_review_scope` / the spec's affected paths) do **not** overlap
   AND neither is the other's parent/child in the links graph. Any uncertainty
   (missing/unparseable scope paths) => treat as NOT independent (fail-closed to
   sequential). Shared-file scopes are never parallelized.
3. **Scheduling = the existing parallel orchestrator:** for each selected scope,
   `docs-lock acquire <scope> <orch-id>` -> spawn one subagent (canonical role
   prompt) that returns a **result block and does NOT write STATE** -> collect
   all -> orchestrator MERGE -> single STATE write -> `docs-lock release`. This
   is exactly `ORCHESTRATION_PARALLEL.prompt.md`; this RFC routes to it.
4. **Isolation for parallel writes:** independent inline scopes that only touch
   disjoint files may run inline. If two otherwise-independent scopes are in the
   Implementation phase and the platform cannot guarantee disjoint writes, the
   detector requires worktree isolation (per scope) before parallelizing, or
   drops them to sequential. (Read-only roles — validation, code review — are
   always safe to parallelize across disjoint scopes.)
5. **Wiring:** `SKILL_LOOP.prompt.md` "RUN ORCHESTRATION" step gains a mode
   selector: it reads the tick's detection result and dispatches either
   `ORCHESTRATION.prompt.md` (single) or `ORCHESTRATION_PARALLEL.prompt.md`
   (parallel). The decision + chosen K + the independent groups are recorded in
   STATE (`orchestration.mode`, `orchestration.k`, `orchestration.groups`) and in
   the tick log, so a human can see why a tick went parallel.
6. **Controls / safety rails:**
   - `K_max` default = 2 (conservative; matches the parallel prompt's default).
   - Respect the loop's run-budget stop: never start a parallel fan-out that
     would blow the remaining budget; reduce K or stay single.
   - Override: a STATE field / loop arg `orchestration_mode: auto|single|parallel`
     (default `auto`) lets a human force single (debugging) or force-cap. `auto`
     is the documented default so the operator does nothing.
   - `docs-lock.mjs` absent => K=1 (degrade-and-report).
   - Never two roles on one scope; validator independence (RFC pattern) preserved
     per scope; a FAIL in one group triggers Remediation for that scope only.

### Rationale

- **Zero operator burden in the common case** — `/aai-loop` is unchanged; the
  loop opportunistically parallelizes only when it is safe and useful, and stays
  single otherwise. Matches the stated preference.
- **Safety is structural, not advisory** — independence is fail-closed; locks are
  atomic (RFC-0004); STATE stays single-writer. The detector can only ever
  *reduce* parallelism when unsure, never create a conflict.
- **Almost no new mechanism** — reuses the existing parallel orchestrator, locks,
  and merge protocol; the new code is the detection + the SKILL_LOOP mode
  selector + docs. Small, testable surface.
- **Bounded cost** — K_max=2 default + run-budget awareness keep token blow-up in
  check; the operator can cap or disable.

### Worked example (K=3 cap raised; 3 independent frozen specs)

```
tick: STATE discovery -> SPEC-A (apps/web/dashboard/*), SPEC-B (apps/api/export/*),
      SPEC-C (apps/api/auth/*) all READY_FOR_IMPLEMENTATION
detect: pairwise review-scope overlap = none -> 3 independent -> PARALLEL, K=min(3,Kmax)
for each: docs-lock acquire SPEC-X orch -> spawn Implementation subagent (returns block)
collect 3 result blocks -> orchestrator merges -> single STATE write -> release locks
wall-clock ~= slowest of the three, not the sum
```

## Alternatives Considered

- **Option A — Explicit opt-in only** (`/aai-loop parallel` or
  `orchestration_mode: parallel`). Pros: simplest, most predictable, no
  independence-detection risk. Cons: the capability stays undiscovered (the very
  problem RFC-0005 exists to fix); operator must know it exists and opt in every
  time. Rejected as primary per the "minimize burden" driver, but RETAINED as the
  `single`/`parallel` override on top of `auto`.
- **Option C — Always parallel when >=2 actionable scopes** (no independence
  test, rely on locks alone). Pros: maximal throughput. Cons: locks prevent two
  agents on the SAME scope but NOT two agents writing the same files from
  DIFFERENT scopes; without the overlap test this corrupts shared files.
  Rejected — unsafe.
- **Option D — Worktree-per-scope always for parallel.** Strong isolation via
  `aai-worktree`. Pros: disjoint writes guaranteed. Cons: heavyweight for short
  read-only roles (validation/review) and small scopes; setup cost per scope.
  Folded into Option B as the conditional isolation step only when inline disjoint
  writes can't be guaranteed.
- **Option E — External job queue / scheduler.** Overkill for repo-local,
  within-orchestrator parallelism; adds a dependency. Rejected for scope.

## Consequences

### Technical impact

- `SKILL_LOOP.prompt.md`: the "RUN ORCHESTRATION" step becomes mode-aware
  (single vs parallel dispatch) driven by the per-tick detection.
- New detection logic: either a small helper the orchestrator calls (e.g.
  `.aai/scripts/orchestration-mode.mjs` computing independent groups from STATE +
  spec review scopes) or detection rules added to the orchestration prompts.
- STATE schema: add `orchestration.mode` (auto|single|parallel),
  `orchestration.k`, and a derived `orchestration.groups` record (non-breaking,
  optional fields).
- `ORCHESTRATION.prompt.md` / `ORCHESTRATION_PARALLEL.prompt.md`: cross-reference
  the selector; the parallel one already consumes the locks.
- Docs: a "Parallel multi-agent orchestration" section in `docs/USER_GUIDE.md`,
  a `docs-lock` usage note, and a CHANGELOG entry (also retroactively covering
  RFC-0004's docs-lock, which never got a CHANGELOG line).

### Operational impact

- `/aai-loop` transparently parallelizes safe, independent work; single-scope and
  shared-file work is unchanged. Operators can force `single` for debugging.
- Tick logs/STATE show the mode decision for transparency.

### Migration/compatibility notes

- Additive and default-safe: `orchestration_mode: auto` with K_max=2 and
  fail-closed independence means existing single-scope projects behave exactly as
  before. Absent `docs-lock.mjs` => single.

## Risks

- **Independence false-positive (parallelize scopes that actually share files).**
  Mitigation: fail-closed overlap test; any unparseable/missing scope path =>
  sequential; read-only roles parallelized freely, write roles require disjoint
  paths or worktrees. Covered by tests (overlapping scopes must NOT parallelize).
- **Token/compute blow-up.** Mitigation: K_max=2 default; run-budget stop reduces
  K or forces single; operator override.
- **Detection complexity drifts from reality** (spec scopes not declared).
  Mitigation: when a scope lacks a declared review/path scope, treat as
  non-independent (sequential) and report it.
- **Partial-failure semantics.** A FAIL in one parallel group must not block the
  others' merge; Remediation is per-scope. Covered by the merge protocol
  (already in SUBAGENT_PROTOCOL) and tested.

## Open Questions

- Where should independence be computed — a small deterministic helper script
  (testable in isolation, preferred) vs. prose rules in the orchestrator prompt?
  Lean: a helper (`orchestration-mode.mjs`) so it is unit-testable.
- `K_max` default (2 vs 3) and whether it should scale with the run budget.
- For parallel Implementation with inline writes: require worktrees always, or
  only when declared review scopes can't prove disjointness? Lean: inline if
  provably disjoint, else worktree, else sequential.
- Should `orchestration.mode` live in STATE, as a `/aai-loop` arg, or both?
  Lean: STATE field defaulting to `auto`, overridable by a loop arg.

## Approvals

- Required approvers (roles/names): Project owner (ales@holubec.net); AAI
  maintainer.

## Notes

- Decision captured during intake (2026-06-26): operator prefers AUTOMATIC
  detection to minimize burden; keep an explicit override for force-single /
  force-parallel. Build = detection + SKILL_LOOP wiring + user docs; reuse the
  existing parallel orchestrator, RFC-0004 locks, and the single-writer merge
  protocol.
- Follow-on: a SPEC must define the independence algorithm precisely (inputs:
  which STATE/spec fields; overlap semantics), the SKILL_LOOP selector contract,
  the STATE fields, the degrade rules, and the test plan (independent scopes ->
  parallel; overlapping scopes -> sequential; missing locks -> single;
  budget-bound -> reduced K; single scope -> no overhead).

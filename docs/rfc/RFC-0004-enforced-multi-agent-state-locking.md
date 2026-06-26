---
id: RFC-0004
type: rfc
status: proposed
links:
  rfc: RFC-0001
  spec: null
  pr: []
  commits: []
---

# RFC-0004 — Enforced Multi-Agent STATE Locking (single-writer + atomic scope locks)

## Context

### Problem or opportunity

The user asked: can multiple agents work over one STATE at the same time? The
chosen shape is **parallel agents on different work items** (horizontal scaling),
not concurrent writers to one shared file.

AAI already has most of the design for this:

- `.aai/ORCHESTRATION_PARALLEL.prompt.md` schedules up to K independent
  workstreams across non-overlapping scopes, with the rules "never run two roles
  on the same scope concurrently" and "respect `.aai/system/LOCKS.md`".
- `.aai/SUBAGENT_PROTOCOL.md` defines a **single-writer merge protocol**:
  subagents return structured result blocks; only the orchestrator merges them
  and writes `docs/ai/STATE.yaml`. Concurrent writes never happen by design.
- RFC-0001 already made `docs/ai/STATE.yaml` and `LOOP_TICKS.jsonl` per-agent
  local (gitignored) and put the cross-agent audit trail in a shared
  append-only `docs/ai/EVENTS.jsonl` (JSONL append tolerates concurrent commits;
  "accept both lines").

So the intended model is sound: **parallelize the work, serialize the state
write through one orchestrator.** What is missing is *enforcement* — today the
model holds only by convention and by accident of sequential execution.

Three concrete gaps between "written in the prompt" and "actually enforced":

1. **Scope locks are advisory text.** `.aai/system/LOCKS.md` is a human-readable
   list with the instruction "Agents MUST respect these locks." Nothing makes
   lock acquisition atomic, so two orchestrator instances (e.g. two developers,
   or two terminals) can each select the same scope and dispatch conflicting
   roles. There is no `acquire`/`release` mechanism, only a convention.
2. **Subagents write STATE directly.** In practice the role prompts ask each
   dispatched subagent to update `docs/ai/STATE.yaml` itself (Planning,
   Implementation, Validation, Code Review all do). This is fine when they run
   sequentially (one at a time), but it **violates the single-writer guarantee
   the moment K >= 2**: two subagents writing the same gitignored STATE race and
   the last writer wins (lost update). Observed indirectly this session — five
   subagents wrote STATE and it only stayed consistent because they ran
   strictly sequentially.
3. **No lock script, no stale handling.** There is no `acquire`/`release`
   primitive and no way to reclaim a lock whose owner died mid-run, so any
   locking scheme would deadlock on a crashed orchestrator.

### Drivers/constraints

- Must NOT reintroduce a shared, concurrently-written `STATE.yaml`. RFC-0001
  deliberately rejected that because deeply-nested mutable YAML produces
  unmergeable conflicts for a 4-10 developer team. Keep per-agent-local STATE.
- Reuse the existing parallel-orchestration + merge-protocol architecture;
  this RFC closes the enforcement gap, it does not redesign the model.
- Lock acquisition must be atomic and crash-safe (a dead owner must not deadlock
  the scope forever).
- Must work cross-platform (macOS + Linux; bash/node), consistent with the rest
  of `.aai/scripts/`.
- Must stay degrade-and-report friendly: absence of the lock tooling (older AAI
  layer) must not hard-break single-agent operation.

### Prior art / current mechanisms studied

- RFC-0001 — per-agent local STATE + shared append-only EVENTS. Foundation we
  build on, not replace.
- `ORCHESTRATION_PARALLEL.prompt.md` — K-way scheduling across independent
  scopes (the consumer of the lock primitive).
- `SUBAGENT_PROTOCOL.md` merge protocol — orchestrator-as-sole-writer (the rule
  we must make hard).
- Common atomic-lock primitives: `mkdir` atomicity, `flock(1)`, O_EXCL file
  creation, and git-tracked CAS lock files. Lease/TTL with stale reclaim is the
  standard answer to dead-owner deadlock.

## Proposal

### Recommended option

**Option B — Atomic local lock registry + hard single-writer rule.** Two parts:

1. **Atomic scope-lock primitive** — a new `.aai/scripts/docs-lock.mjs` exposing
   `acquire <scope> <owner> [--ttl <seconds>]`, `release <scope> <owner>`,
   `list`, and `reap` (release expired locks). Locks live as individual files
   under a lock directory (e.g. `docs/ai/locks/<scope>.lock`) created with
   atomic O_EXCL semantics so acquisition is a genuine compare-and-set: if the
   file already exists and is not expired, acquisition fails. Each lock file
   records `{ scope, owner, acquired_utc, ttl_seconds, pid? }`. `reap` (and a
   self-heal step inside `acquire`) deletes locks whose `acquired_utc + ttl` is
   in the past, so a crashed orchestrator's lock is reclaimable without manual
   intervention. The lock directory is **per-agent-local (gitignored)** like
   STATE — locks coordinate *within one machine/orchestrator process tree*,
   which is exactly the scope of "K parallel subagents under one orchestrator".

2. **Hard single-writer rule** — amend `SUBAGENT_PROTOCOL.md` and the role
   prompts so that **subagents never write `docs/ai/STATE.yaml`**. A dispatched
   subagent returns its result block (already the protocol's contract) and the
   orchestrator performs the only STATE write, via the merge protocol, after
   collecting all result blocks. `ORCHESTRATION_PARALLEL.prompt.md` calls
   `docs-lock.mjs acquire` before dispatching a scope and `release` after
   merging that scope's result.

`.aai/system/LOCKS.md` is demoted from "the lock mechanism" to a
human-readable *view* (optionally regenerated from `docs-lock.mjs list`), so the
authoritative lock state is the atomic registry, not editable prose.

### Rationale

- **Closes the real gap with mechanism, not discipline** — the same philosophy
  as RFC-0001/RFC-0002 (turn a "MUST remember" convention into an enforced
  check). Atomic acquire makes double-claim impossible; the single-writer rule
  makes lost-update impossible.
- **Minimal blast radius** — reuses the existing parallel orchestrator + merge
  protocol; adds one script and one rule, plus prompt edits. No change to the
  STATE schema or to single-agent flow.
- **Crash-safe by construction** — TTL + reap means a dead owner self-heals; no
  deadlock, no manual lock surgery.
- **Honors RFC-0001** — STATE stays per-agent-local; nothing becomes a
  concurrently-written shared file. Cross-agent visibility remains EVENTS.jsonl.

### Worked flow (K=2)

```
orchestrator: docs-lock acquire SPEC-0005 orch-A   -> OK
orchestrator: docs-lock acquire SPEC-0006 orch-A   -> OK   (independent scope)
  spawn subagent A (SPEC-0005)   spawn subagent B (SPEC-0006)   # concurrent
  A returns result block         B returns result block         # NO STATE write
orchestrator: merge A + B  -> single STATE.yaml write
orchestrator: docs-lock release SPEC-0005 orch-A; release SPEC-0006 orch-A
```

## Alternatives Considered

- **Option A — Keep advisory `LOCKS.md`, just document discipline harder.**
  Pros: zero code. Cons: does not actually prevent double-claim or lost-update;
  the problem is precisely that conventions are not enforced. Rejected.
- **Option C — Shared, concurrently-written `STATE.yaml` with a global file
  lock (`flock`).** A single shared STATE that every agent locks before writing.
  Pros: one source of truth. Cons: reintroduces the exact YAML-merge / coupling
  pain RFC-0001 removed; `flock` serializes ALL state writes into a global
  bottleneck and is brittle over some network filesystems; a crashed holder
  needs the same TTL machinery anyway. Rejected as a regression of RFC-0001.
- **Option D — git-branch / worktree isolation per agent (no shared lock).**
  Each agent works in its own worktree/branch; merge via PRs. Pros: strong
  isolation, already supported by `aai-worktree`. Cons: solves *file* isolation
  but not *scope* deduplication (two agents can still pick the same work item),
  and heavyweight for short tasks. Complementary, not a substitute — worktrees
  can layer on top of Option B for file-level isolation.
- **Option E — External coordination service (Redis/DB lease).** Pros: robust
  distributed locking. Cons: adds an external dependency and a running service
  to a repo-local, file-based toolchain; overkill for within-orchestrator
  parallelism. Rejected for scope.

## Consequences

### Technical impact

- New `.aai/scripts/docs-lock.mjs` (acquire/release/list/reap) + a gitignored
  `docs/ai/locks/` directory.
- `SUBAGENT_PROTOCOL.md`: add the hard "subagents never write STATE" rule and a
  rationalization-table row.
- `ORCHESTRATION_PARALLEL.prompt.md`: wire acquire-before-dispatch /
  release-after-merge; reference the lock script as authoritative over
  `LOCKS.md`.
- Role prompts (Planning/Implementation/Validation/Code Review): change "update
  STATE.yaml" to "return result block; the orchestrator updates STATE" for the
  parallel path. (The single-orchestrator sequential path may still write STATE
  directly — it IS the writer.)
- `.gitignore`: add `docs/ai/locks/`.

### Operational impact

- Parallel runs (K>=2) become safe to actually use; single-agent flow unchanged.
- A crashed orchestrator's locks auto-expire (TTL), no manual cleanup.

### Migration/compatibility notes

- Additive. If `docs-lock.mjs` is absent (older layer), the orchestrator falls
  back to the current advisory `LOCKS.md` behavior (degrade-and-report); K should
  default to 1 in that case.
- No STATE schema change; existing single-agent loops are unaffected.

## Risks

- **Lock dir on a network filesystem with weak O_EXCL atomicity.** Mitigation:
  prefer `mkdir`-based atomicity (widely atomic) or document the local-FS
  assumption; locks are per-agent-local anyway.
- **TTL too short reaps a live owner's lock.** Mitigation: conservative default
  TTL (e.g. 30-60 min) plus an optional heartbeat/refresh; `reap` only removes
  locks past `acquired + ttl`.
- **Subagents that still write STATE out of habit.** Mitigation: make the rule a
  hard protocol line + add a guard the orchestrator can run (detect unexpected
  STATE mutation from a subagent context). Covered by the spec's tests.
- **Two orchestrators on the same machine** sharing the lock dir is the intended
  coordination; **two orchestrators on different machines** do NOT share the
  gitignored lock dir — out of scope here (that is the EVENTS/PR layer's job and
  a possible future RFC).

## Open Questions

- Atomicity primitive: `mkdir` vs O_EXCL file vs `flock` wrapper — pick one in
  the SPEC after a quick portability check on macOS + Linux.
- Default TTL value and whether to add a heartbeat/refresh in v1 or defer it.
- Should `.aai/system/LOCKS.md` be auto-regenerated from `docs-lock.mjs list`
  (a committed human view) or dropped entirely in favor of `list`?
- Should the lock dir be strictly local (within-orchestrator, this RFC) or is a
  committed/shared cross-developer lock a separate follow-up RFC? Lean: local
  now, cross-developer later if demand appears.

## Approvals

- Required approvers (roles/names): Project owner (ales@holubec.net); AAI
  maintainer.

## Notes

- Decisions captured during intake (2026-06-26): direction = parallel agents on
  DIFFERENT work items (horizontal scaling); keep RFC-0001's per-agent-local
  STATE (do NOT build a shared concurrently-written STATE); close the gap by
  enforcing the existing single-writer model — atomic scope locks
  (`docs-lock.mjs`) + a hard "subagents never write STATE" rule — rather than by
  redesigning state ownership.
- Follow-on: a SPEC must pick the atomicity primitive, define the lock-file
  schema and TTL/reap semantics, the `docs-lock.mjs` CLI contract, and the
  orchestrator wiring + tests (including a concurrency test that two acquires of
  the same scope cannot both succeed, and a stale-reap test).

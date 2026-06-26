---
id: SPEC-0004
type: spec
status: done
links:
  requirement: null
  rfc: RFC-0004
  pr: []
  commits: []
---

# SPEC-0004 — Enforced Multi-Agent STATE Locking (atomic scope locks + single-writer)

SPEC-FROZEN: true

## Links
- Parent RFC (WHAT/WHY + chosen Option B): docs/rfc/RFC-0004-enforced-multi-agent-state-locking.md
- Foundation (per-agent-local STATE, shared EVENTS): docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md
- Consumer of the lock primitive (K-way scheduler): .aai/ORCHESTRATION_PARALLEL.prompt.md
- Single-writer merge protocol being hardened: .aai/SUBAGENT_PROTOCOL.md
- Advisory lock file being demoted to a view: .aai/system/LOCKS.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (SPEC-FROZEN: true)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in RFC-0004)
AAI already intends "parallelize the work, serialize the STATE write through one
orchestrator," but that model holds only by convention and by accident of
sequential execution. Two enforcement gaps remain: (1) scope locks are advisory
prose in `.aai/system/LOCKS.md` with no atomic `acquire`/`release`, so two
orchestrators can claim the same scope; (2) dispatched subagents write
`docs/ai/STATE.yaml` directly, which races and loses updates the moment K >= 2.
This spec closes both gaps with mechanism: an atomic scope-lock CLI and a hard
"subagents never write STATE" protocol rule wired into the parallel orchestrator.
It does NOT redesign state ownership and does NOT reintroduce a shared,
concurrently-written STATE (RFC-0001 deliberately rejected that).

## Design decisions (load-bearing — read before implementing)

### D1 — Atomicity primitive: O_EXCL single-file create (`fs.openSync(path, 'wx')`)
The acquire CAS is a single atomic syscall: `fs.openSync(lockPath, 'wx')`
(flags `O_WRONLY|O_CREAT|O_EXCL`) which creates the lock file iff it does not
already exist and throws `EEXIST` otherwise. The same returned fd is then used to
write the lock payload, so there is no "container exists but metadata not yet
written" window that a two-step `mkdir <dir>` + write-metadata-file approach
would expose. Chosen over `mkdir`-atomicity because O_EXCL is equally atomic on
local macOS (APFS/HFS+) and Linux (ext4/xfs) filesystems AND lets the test-and-
claim-and-payload happen as one open+write on one inode. The weak-O_EXCL-on-NFS
caveat (RFC-0004 Risks) is out of scope: the lock directory is per-agent-local
and gitignored, i.e. always on a local filesystem within one orchestrator
process tree. `flock(1)` was rejected — it serializes through an external lock
held only for the lifetime of a process, which does not match a lease that must
outlive individual `acquire`/`release` CLI invocations.

### D2 — Lock-file schema and location
Each lock is one JSON file at `docs/ai/locks/<safe-scope>.lock` where
`<safe-scope>` is the scope id sanitized to a filesystem-safe token
(`[^A-Za-z0-9._-]` -> `_`). Payload:

```json
{ "scope": "<original scope id>", "owner": "<agent id>",
  "acquired_utc": "<ISO 8601 UTC>", "ttl_seconds": 1800, "pid": 12345 }
```

`pid` is best-effort (`process.pid`) and informational only — reclaim is driven
by TTL, never by liveness-probing a pid (a pid can be reused; cross-process pid
checks are not portable). The script creates `docs/ai/locks/` on demand
(`mkdirSync(..., { recursive: true })`).

### D3 — Default TTL = 1800 seconds (30 minutes); no heartbeat in v1
A lock is expired iff `now > acquired_utc + ttl_seconds`. Default TTL is 30 min.
Justification against measured role runtimes in this repo (STATE.yaml agent_runs:
Planning ~80-190s, Validation ~170-320s, Implementation 729s, longest Remediation
951s ~= 16 min): 1800s gives roughly 2x headroom over the longest observed
single-role run, so a LIVE owner is never reaped mid-run, while a CRASHED
orchestrator's scope self-heals within half an hour with no manual lock surgery.
Callers MAY pass `--ttl <seconds>` higher for known-long jobs. A heartbeat/refresh
is deferred to a follow-up (keep v1 minimal); recorded as residual risk R-TTL.

### D4 — Reap and acquire self-heal are TTL-driven; the CAS stays the only gate
`reap` scans every `*.lock`, deletes those past `acquired_utc + ttl_seconds`,
and prints what it reclaimed; it never removes a fresh (non-expired) lock.
`acquire` self-heals: on `EEXIST` it reads the existing lock; if that lock is
expired it `rmSync`s it and retries the `wx` open. Even if two acquirers race the
reclaim delete, only one wins the subsequent O_EXCL create — the reap/self-heal
is opportunistic cleanup; the atomic create is the sole arbiter of ownership, so
double-claim remains impossible. A fresh lock encountered on `EEXIST` is NOT
reclaimed; acquire fails with the contention exit code.

### D5 — CLI contract and exit codes
ESM `.mjs`, `#!/usr/bin/env node`, `node:fs`/`node:path`/`node:child_process`
only, matching `.aai/scripts/docs-canon.mjs` / `append-event.mjs` conventions
(header usage block, `parseArgs`, `fail(msg, code)`). Subcommands:
- `acquire <scope> <owner> [--ttl <seconds>]` — atomic claim (D1/D4).
- `release <scope> <owner>` — remove the lock iff `owner` matches.
- `list [--json]` — report all current locks (scope, owner, acquired_utc,
  ttl_seconds, expired?), with an explicit "no locks" marker when empty.
- `reap` — delete expired locks (D4).

Exit codes (so the orchestrator can branch deterministically):
- `0` success (acquired / released / listed / reaped)
- `2` usage error (missing args / unknown subcommand)
- `3` acquire contention (scope held by a live, non-expired lock)
- `4` release ownership violation (lock held by a different owner)
- release of an unheld scope is idempotent success (`0`).

### D6 — Lock directory is per-agent-local (gitignored)
`docs/ai/locks/` is added to `.gitignore` (whole-directory ignore, like
`docs/ai/loop/`), consistent with RFC-0001's treatment of `STATE.yaml` /
`LOOP_TICKS.jsonl`. Locks coordinate within one machine / orchestrator process
tree — exactly the scope of "K parallel subagents under one orchestrator." No
`.gitkeep` is committed (the script creates the dir on demand). Cross-machine /
cross-developer locking is explicitly out of scope (future RFC).

### D7 — Hard single-writer rule (documentation/protocol; partly process)
`.aai/SUBAGENT_PROTOCOL.md` gains an explicit hard rule: a dispatched subagent
MUST NOT write `docs/ai/STATE.yaml` — it returns its result block and the
orchestrator is the SOLE STATE writer via the merge protocol — plus a
rationalization-table row. `.aai/ORCHESTRATION_PARALLEL.prompt.md` is wired to
call `docs-lock acquire <scope> <owner>` before dispatching a scope and
`docs-lock release <scope> <owner>` after merging that scope's result, and to
treat the lock registry as authoritative over `.aai/system/LOCKS.md`.
`LOCKS.md` is demoted to a human-readable view. Be honest: a prose rule binding
an LLM subagent is partly process, not fully mechanical. The MECHANICAL,
testable core is (a) the lock CLI + exit-code contract the orchestrator branches
on (D5) and (b) the presence of the rule + wiring text, asserted by grep
(TEST-010). A runtime STATE-mutation guard is recorded as residual risk R-GUARD,
not a frozen AC, to avoid over-claiming enforcement we do not build in v1.

### D8 — Degrade-and-report fallback
If `.aai/scripts/docs-lock.mjs` is absent (older AAI layer), the orchestrator
falls back to advisory `LOCKS.md` and defaults K=1 (single-agent safe). This is
stated in the orchestrator prompt; it is NOT mechanically tested here because the
script IS the primary deliverable of this spec (its presence is asserted by
TEST-001).

## Implementation strategy
- Strategy: hybrid
- Rationale: the lock primitive (`docs-lock.mjs`: acquire/release/reap/list) is
  data-integrity-critical concurrency code whose core property is a race-class
  invariant ("two acquires of one scope cannot both succeed"). That demands TDD
  with a real RED — the concurrency test must be observed FAILING against a
  deliberately naive non-atomic stub (read-existence-then-create, which
  double-claims under parallel load) before the O_EXCL CAS turns it GREEN; a
  test never seen failing here would be worthless. So Spec-AC-01..07 (TEST-001..
  009) are TDD. The protocol/orchestrator/gitignore documentation edits
  (Spec-AC-08, TEST-010) are low-risk prose wiring where RED-GREEN adds little
  signal beyond a grep assertion, so they run as a loop segment. Hybrid =
  TDD for the script, loop for the docs wiring.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: additive change — one new script (`docs-lock.mjs`), one new
  test file, and edits to three workflow docs + `.gitignore`. No STATE schema
  change, no migration, no cross-cutting refactor. The work already sits on a
  dedicated feature branch `feat/multi-agent-state-locking`, which itself isolates
  from `main`; a separate git worktree would add ceremony without added safety,
  and every edit is trivially reversible. (It does touch protected workflow
  prompts, but only by addition, on an already-isolated branch — so not `required`.)
- User decision: inline (already recorded in STATE.yaml worktree.user_decision;
  no further user decision required because recommendation is not_needed)
- Base ref: main
- Worktree branch/path: n/a (inline on feat/multi-agent-state-locking)
- Inline review scope:
  - `.aai/scripts/docs-lock.mjs`
  - `tests/skills/test-aai-docs-lock.sh`
  - `.aai/ORCHESTRATION_PARALLEL.prompt.md`
  - `.aai/SUBAGENT_PROTOCOL.md`
  - `.aai/system/LOCKS.md`
  - `.gitignore`
  - `docs/specs/SPEC-0004-enforced-multi-agent-state-locking.md`

## Acceptance Criteria Mapping

- Maps to: RFC-0004 Proposal part 1 (CLI surface)
  - Spec-AC-01: `.aai/scripts/docs-lock.mjs` exists as an ESM node CLI exposing
    `acquire`/`release`/`list`/`reap`; an unknown or missing subcommand prints
    usage and exits `2`.
  - Verification: TEST-001 — `node .aai/scripts/docs-lock.mjs` (no args) and a
    bogus subcommand exit 2; each of the four subcommands is recognized.

- Maps to: RFC-0004 Proposal part 1 (atomic acquire + schema; D1/D2)
  - Spec-AC-02: `acquire <scope> <owner> [--ttl N]` on a free scope exits `0` and
    creates `docs/ai/locks/<safe-scope>.lock` containing `{scope, owner,
    acquired_utc, ttl_seconds, pid}` (ttl defaulting to 1800).
  - Verification: TEST-002 — acquire a free scope; assert exit 0, file present,
    JSON keys + values correct.

- Maps to: RFC-0004 follow-on "two acquires of the same scope cannot both
  succeed" (CORE SAFETY; D1/D4)
  - Spec-AC-03: N concurrent `acquire` calls for the SAME scope yield EXACTLY ONE
    exit `0`; every other call exits `3`; exactly one lock file remains, naming
    exactly one owner.
  - Verification: TEST-003 (concurrency).

- Maps to: RFC-0004 worked flow `release` (D5)
  - Spec-AC-04: `release <scope> <owner>` (owner match) exits `0` and frees the
    scope so a subsequent `acquire` by a different owner exits `0`. `release` by a
    non-owner exits `4` and leaves the lock intact. `release` of an unheld scope
    is idempotent (`0`).
  - Verification: TEST-004 (release frees), TEST-005 (ownership guard + idempotent).

- Maps to: RFC-0004 "TTL + reap so a dead owner never deadlocks" (D3/D4)
  - Spec-AC-05: an EXPIRED lock is reclaimable — `reap` deletes it AND `acquire`
    self-heals (a later acquire of the same scope by a different owner succeeds
    without an explicit reap); a FRESH (non-expired) lock is NEVER reaped or
    reclaimed (a competing acquire still exits `3`).
  - Verification: TEST-006 (reap reclaims expired), TEST-007 (acquire self-heal +
    fresh-not-reaped).

- Maps to: RFC-0004 Proposal part 1 (`list` view; D5)
  - Spec-AC-06: `list` reports every current lock (scope + owner + acquired_utc +
    ttl_seconds, expired flag) and an explicit "no locks" marker when none are held.
  - Verification: TEST-008.

- Maps to: RFC-0004 Consequences `.gitignore` (D6)
  - Spec-AC-07: `docs/ai/locks/` is git-ignored; a created lock file never appears
    in `git status --porcelain`.
  - Verification: TEST-009 — `git check-ignore docs/ai/locks/<x>.lock` exits 0 and
    porcelain shows nothing after an acquire.

- Maps to: RFC-0004 Proposal part 2 (hard single-writer rule + wiring; D7/D8)
  - Spec-AC-08: `.aai/SUBAGENT_PROTOCOL.md` contains an explicit hard rule that a
    subagent MUST NOT write `docs/ai/STATE.yaml` (orchestrator is sole writer)
    plus a rationalization-table row; `.aai/ORCHESTRATION_PARALLEL.prompt.md`
    references `docs-lock` with acquire-before-dispatch / release-after-merge, the
    lock registry as authoritative over `LOCKS.md`, and the degrade-and-report
    fallback (absent script -> advisory LOCKS.md + K=1); `.aai/system/LOCKS.md`
    states it is a human-readable view, not the authoritative mechanism.
  - Verification: TEST-010 (grep assertions across the three docs).

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | docs-lock.mjs CLI exists (acquire/release/list/reap); unknown/missing subcommand exits 2 | done | TEST-001 green (docs/ai/tdd/green-lock-20260626T175113Z.log); validated independently RUN_ID:val-2026-06-26T175503Z | — | TDD; Validation PASS |
| Spec-AC-02 | acquire free scope -> exit 0 + lock file with {scope,owner,acquired_utc,ttl_seconds,pid} | done | TEST-002 green (docs/ai/tdd/green-lock-20260626T175113Z.log); validated independently RUN_ID:val-2026-06-26T175503Z | — | TDD; Validation PASS |
| Spec-AC-03 | CONCURRENCY: N concurrent acquires of one scope -> exactly one exit 0, rest exit 3, one lock/one owner | done | TEST-003 green; RED-proofed vs naive stub (docs/ai/tdd/red-lock-concurrency-fixedharness-20260626T175108Z.log: 14 winners); validator stress 10 iterations (5xN=40, 5xN=50): all 1 winner RUN_ID:val-2026-06-26T175503Z | — | TDD; core safety property; Validation PASS |
| Spec-AC-04 | release (owner match) frees scope; non-owner release exits 4 + intact; unheld release idempotent 0 | done | TEST-004/005 green (docs/ai/tdd/green-lock-20260626T175113Z.log); independently verified ownership guard + idempotent release RUN_ID:val-2026-06-26T175503Z | — | TDD; Validation PASS |
| Spec-AC-05 | expired lock reclaimable via reap AND acquire self-heal; fresh lock never reaped (competing acquire still 3) | done | TEST-006/007 green (docs/ai/tdd/green-lock-20260626T175113Z.log); independently verified reap/self-heal/fresh-guard RUN_ID:val-2026-06-26T175503Z | — | TDD; dead-owner no-deadlock; Validation PASS |
| Spec-AC-06 | list reports held locks (scope/owner/acquired/ttl/expired) + no-locks marker when empty | done | TEST-008 green (docs/ai/tdd/green-lock-20260626T175113Z.log); validated independently RUN_ID:val-2026-06-26T175503Z | — | TDD; Validation PASS |
| Spec-AC-07 | docs/ai/locks/ is gitignored; lock files never in git status --porcelain | done | TEST-009 green; git check-ignore exit 0 in real repo; porcelain clean verified RUN_ID:val-2026-06-26T175503Z | — | TDD; Validation PASS |
| Spec-AC-08 | SUBAGENT_PROTOCOL hard no-STATE-write rule + ORCHESTRATION_PARALLEL acquire/release wiring + LOCKS.md demotion | done | TEST-010 green (docs/ai/tdd/green-lock-20260626T175113Z.log); grep assertions independently confirmed RUN_ID:val-2026-06-26T175503Z | — | loop; partly process (D7); Validation PASS |

## Implementation plan
- Components/modules affected:
  - NEW `.aai/scripts/docs-lock.mjs`: ESM CLI. `parseArgs` (positional
    subcommand + scope + owner, `--ttl`, `--json` flags). `LOCKS_DIR =
    docs/ai/locks`. `safeScope(scope)` sanitizer. `lockPath(scope)`. `acquire`:
    `mkdirSync(recursive)`, build payload, `openSync(lockPath,'wx')` then
    `writeFileSync`/`writeSync` the JSON; on `EEXIST` read + check expiry ->
    reclaim (rmSync + retry wx) if expired else exit 3. `release`: read lock; if
    absent exit 0; if owner mismatch exit 4; else rmSync + exit 0. `list`: read
    all `*.lock`, print table/JSON, "no locks" marker when empty. `reap`: read
    all, delete expired, print reclaimed. `isExpired(lock, now)` =
    `now > Date.parse(acquired_utc) + ttl_seconds*1000`. `fail(msg, code)`.
  - EDIT `.aai/SUBAGENT_PROTOCOL.md`: add the hard "subagents never write STATE"
    rule near the merge protocol + a rationalization-table row.
  - EDIT `.aai/ORCHESTRATION_PARALLEL.prompt.md`: wire acquire-before-dispatch /
    release-after-merge; reference docs-lock as authoritative over LOCKS.md;
    state the degrade-and-report fallback (absent script -> LOCKS.md + K=1).
  - EDIT `.aai/system/LOCKS.md`: header note demoting it to a human-readable view.
  - EDIT `.gitignore`: add `docs/ai/locks/` block (with an RFC-0004 comment,
    mirroring the existing STATE/LOOP_TICKS block).
  - NEW `tests/skills/test-aai-docs-lock.sh`: bash harness mirroring
    `tests/skills/test-aai-docs-audit.sh` conventions (`set -euo pipefail`,
    isolated `TEST_DIR`, `log_pass`/`log_fail`, exit 0/1/42), TEST-001..010.
- Data flows: lock payload JSON is the only persisted state; no STATE.yaml or
  git writes from the script. `list`/`reap` read the lock dir; `acquire`/`release`
  mutate one lock file atomically.
- Edge cases:
  - scope ids containing `/` or spaces -> `safeScope` token; original scope kept
    inside the JSON for `list`.
  - corrupt/non-JSON lock file on `EEXIST` -> treat as a held lock that cannot be
    parsed; do NOT silently reclaim (fail closed, exit 3) to avoid clobbering an
    unknown holder. (Recorded; reap may surface it.)
  - clock skew: expiry compares against the local system clock only (locks are
    single-machine), consistent with D6.
  - empty lock dir / missing lock dir for `list`/`reap` -> "no locks", exit 0.

## Seam analysis
A SEAM is any place this change shares state with, or is consumed by, a feature
it does not own.

- SEAM-1 (docs-lock CLI <-> ORCHESTRATION_PARALLEL scheduler): the orchestrator
  branches on docs-lock's exit codes (0 acquired vs 3 contended) to decide
  whether to dispatch a scope. The mechanically automatable half of this seam is
  the exit-code contract itself, crossed end-to-end by TEST-003/004 (produce a
  real held lock on one side, assert the exact exit code a scheduler would read
  on the other). The prose wiring that an LLM orchestrator follows is asserted by
  TEST-010. RESIDUAL RISK R-WIRE: that a live LLM orchestrator actually calls
  acquire/release in order is process, not automatable in v1.
- SEAM-2 (lock dir <-> git): a produced lock file must be invisible to git.
  TEST-009 crosses it directly — create a lock, assert git ignores it.
- SEAM-3 (single-writer rule <-> subagent STATE writes): the rule constrains
  what dispatched subagents do to `docs/ai/STATE.yaml`. The testable core is the
  protocol text + wiring (TEST-010). RESIDUAL RISK R-GUARD: no runtime guard
  detects a rogue subagent STATE write in v1; a `git diff`-based mutation guard
  the orchestrator could run is a recommended follow-up, not a frozen AC.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)               | Description | Status |
|----------|------------|-------------|------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-lock.sh | no-arg and bogus-subcommand invocations exit 2 with usage; acquire/release/list/reap are recognized subcommands | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-lock.sh | acquire of a free scope exits 0 and writes docs/ai/locks/<scope>.lock with scope/owner/acquired_utc/ttl_seconds(=1800)/pid | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-lock.sh | CONCURRENCY: N=20 background acquires of ONE scope -> exactly 1 exit 0, 19 exit 3; exactly one lock file naming one owner. RED-proofed against a naive non-O_EXCL stub that double-claims | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-lock.sh | acquire(ownerA)=0; competing acquire(ownerB)=3; release(scope,ownerA)=0; re-acquire(ownerB)=0 (release frees the scope) | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-docs-lock.sh | release(scope,ownerB) on a lock held by ownerA exits 4 and lock intact; release of an unheld scope exits 0 (idempotent) | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-docs-lock.sh | acquire --ttl 1, sleep 2, reap deletes the expired lock (exit 0, reports reclaimed); a fresh acquire by another owner then exits 0 | green |
| TEST-007 | Spec-AC-05 | integration | tests/skills/test-aai-docs-lock.sh | (a) acquire --ttl 1, sleep 2, acquire SAME scope/other owner exits 0 via self-heal (no explicit reap); (b) acquire --ttl 1800 then reap leaves it AND a competing acquire still exits 3 (fresh NOT reaped) | green |
| TEST-008 | Spec-AC-06 | integration | tests/skills/test-aai-docs-lock.sh | list on empty dir prints a no-locks marker (exit 0); after two acquires of distinct scopes, list shows both scopes + owners | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-docs-lock.sh | git check-ignore docs/ai/locks/<x>.lock exits 0; after an acquire, git status --porcelain shows no lock file | green |
| TEST-010 | Spec-AC-08 | integration | tests/skills/test-aai-docs-lock.sh | grep: SUBAGENT_PROTOCOL.md has the hard "MUST NOT write ... STATE.yaml" rule + rationalization row; ORCHESTRATION_PARALLEL.prompt.md references docs-lock acquire+release + degrade fallback (K=1); LOCKS.md states it is a view | green |
| TEST-011 | Spec-AC-03 | integration | tests/skills/test-aai-docs-lock.sh | post-review E1 regression: N concurrent acquires over a PRE-EXPIRED lock (forcing the self-heal/reclaim path that TEST-003 never enters) -> exactly one exit 0, one lock file. RED-proofed: the pre-fix rename-steal double-claims (~10-20%/run; 2 winners observed); GREEN with the O_EXCL `.reclaim` sentinel: 30/30 runs exactly one winner | green |

RED-proof obligation (all AC-gating tests, regardless of strategy):
- TEST-001/002 fail before `docs-lock.mjs` exists (no script / no subcommands).
- TEST-003 (concurrency) is RED-proofed by first standing up a deliberately
  NAIVE acquire (read-existence-then-create, no O_EXCL): with N=20 parallel
  acquirers it reliably lets >=2 succeed, so the "exactly one exit 0" assertion
  fails RED; switching to the O_EXCL CAS turns it GREEN. A concurrency test never
  seen failing proves nothing — this stub step is mandatory.
- TEST-004/005 fail RED because release/ownership/idempotent exit codes do not
  exist before implementation.
- TEST-006/007 fail RED because reap/self-heal do not exist; TEST-007(b) also
  asserts a fresh lock IS still contended, a positive control against an
  over-eager reaper.
- TEST-008/009 fail RED (no list output / no lock files to ignore) before impl.
- TEST-010 fails RED before the protocol/orchestrator/LOCKS.md edits land (grep
  finds none of the required strings).

## Verification
- `bash tests/skills/test-aai-docs-lock.sh` — TEST-001..010 green (exit 0; 42 if
  node/git missing).
- `node .aai/scripts/docs-lock.mjs acquire DEMO-1 orch-A` exits 0 and creates
  `docs/ai/locks/DEMO-1.lock`; a second `acquire DEMO-1 orch-B` exits 3;
  `release DEMO-1 orch-A` exits 0; `list` then shows no DEMO-1 lock.
- `git check-ignore docs/ai/locks/DEMO-1.lock` exits 0.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event --path docs/specs/SPEC-0004-enforced-multi-agent-state-locking.md` reports CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  non-empty Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (RFC-0004 / SPEC-0004)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path (e.g. docs/ai/tdd/red-*.log, green-*.log)
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (RFC-0004 owns WHAT/WHY).
This document does not define workflow.

Post-review remediation (code review E1, 2026-06-26):
- Code review FAILED the first implementation: Spec-AC-03 was violated on the
  EXPIRED-RECLAIM path. The original self-heal did an unconditional unlink/rename
  of the lock by path; between observing "expired" and unlinking, a competitor
  could create a FRESH lock that the unlink then destroyed -> two winners. The
  free-scope concurrency stress (TEST-003 and the validator's 450-attempt run)
  never entered the reclaim branch, so it missed this.
- Fix: the expired-reclaim is now serialized through a short-lived O_EXCL
  sentinel (`<lock>.reclaim`). The sentinel holder re-verifies expiry under
  mutual exclusion (so a fresh lock is never removed) and the O_EXCL create
  remains the sole ownership arbiter for the briefly-empty slot. A leaked
  sentinel (dead acquirer) is detected as stale after 30s and swept by `reap`.
- New TEST-011 reproduces the race (pre-expired lock + N concurrent acquirers):
  RED on the pre-fix code (2 winners, ~10-20%/run), GREEN after the fix
  (30/30 runs exactly one winner). Evidence: docs/ai/tdd/red-lock-e1-reclaim-*,
  green-lock-e1-reclaim-*.

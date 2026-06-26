# Active Work Locks (human-readable view)

> NOTE (RFC-0004 / SPEC-0004): This file is a **human-readable view**, NOT the
> authoritative locking mechanism. The authoritative scope-lock registry is the
> atomic CLI **`.aai/scripts/docs-lock.mjs`** (`acquire` / `release` / `list` /
> `reap`), backed by per-agent-local lease files under `docs/ai/locks/`. When this
> prose and `docs-lock` disagree, **`docs-lock` wins**. Run
> `node .aai/scripts/docs-lock.mjs list` for the live, machine-checked state.
>
> Orchestrators acquire a scope lock before dispatch and release it after the
> merge (see `.aai/ORCHESTRATION_PARALLEL.prompt.md`). Only if `docs-lock.mjs` is
> absent (older AAI layer) does this advisory file become the fallback, with K=1.

This optional table is for humans skimming what is in flight; it is not read by
the lock CAS and may lag the registry.

## Locks
(If empty, no active locks.)

Format:
- Scope: <REQ/PRD/SPEC/Page>
  Role: <Planning|Implementation|Validation|Remediation>
  Owner: <agent identifier>
  Started: <YYYY-MM-DD>

---
id: orphan-sweep
type: product
capability: orphan-sweep
status: current
delivered_by:
  - CHANGE-0108
updated: 2026-08-02
---

# Leaked runaway shells die at the next session start

## What it does

Agent sessions can leak detached processes: a load test or background job
whose cleanup lived AFTER the workload dies with its timed-out parent shell,
and the leftover process spins on CPU unowned, invisibly, for days (the
motivating incident: 37 busy-loops, ~15 cores, ~4 days).

Every session start now runs a bounded, best-effort **orphan sweep**. It
kills processes that are ALL of: orphaned (adopted by launchd/init),
agent-shell wrappers, older than 2 hours, and burning at least 20 % CPU —
by process group, so children die with their wrappers. When it reaps
something, one summary line appears in the session's opening context;
when there is nothing to reap it is completely silent.

## How to use it

Nothing to invoke. Runs from `hooks/session-start.sh` with a watchdog —
it can never block or delay a session. Manual run / inspection:

    node .aai/scripts/orphan-sweep.mjs --dry-run --json

Tunables (flags): `--min-age-s` (default 7200), `--min-cpu` (default 20),
`--pattern` (default the agent shell-snapshot marker).

## Interfaces and contracts

- Selection is conservative by construction: any process still parented to
  a live session, idling below the CPU floor, or younger than the age floor
  is never touched; a process group shared with live foreign work is
  dropped whole; unparseable `ps` output fails SAFE (no kill).
- The sweep's own process group is always excluded. Never kill these leaks
  by `pkill -f <snapshot-id>` by hand — a live session's own tool calls
  contain the same string.
- Windows: silent no-op (no `ps`); the leak class is macOS/Linux-specific.

## Limits and non-goals

- Fires only when a session starts in this project on that machine.
- A leaked process idling below 20 % CPU is deliberately not reaped — the
  harm class this exists for is CPU burn.
- Prevention stays with the author: load generators must self-terminate
  (`while ((SECONDS<t))`), never rely on a trailing kill.

## Links

- Request: docs/issues/CHANGE-0108-orphan-sweep-session-hook.md

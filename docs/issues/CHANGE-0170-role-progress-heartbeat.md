---
id: role-progress-heartbeat
number: 170
type: change
status: draft
links:
  pr: []
  commits: []
---

# Long-running dispatched roles should emit a live progress heartbeat

## Summary
- Long-running dispatched roles (Validation full sweeps, multi-round Code
  Review, large Implementation subagents) currently give the operator no
  live signal of progress while they run — the only observable evidence is
  the process existing (`ps aux`) or STATE.yaml/EVENTS.jsonl changing at the
  END of a role's execution.
- This forces an operator who is monitoring an autonomous ride to either poll
  blind (repeated "how's it going?" checks that get no more information than
  "still running") or wait for full completion before knowing whether the
  role is on round 1 of 3 or already near done.

## Motivation / Business Value
- This session's single most repeated point of user friction was exactly
  this blind wait: multiple long Validation/Code Review rounds each ran for
  extended periods with zero intermediate signal, during which the operator
  repeatedly asked for status and the honest answer was "still running, no
  more detail available."
- A lightweight, low-cost heartbeat closes that gap without requiring a
  fundamentally different dispatch architecture: it lets an operator (or a
  monitoring script) distinguish "making progress" from "stuck" without
  interrupting the role.

## Scope
- In scope: a mechanism for a dispatched role (Validation, Code Review,
  Implementation, Remediation) to periodically record a short, structured
  progress marker (e.g. "sweep round 2/3 in progress", "reviewing file 4 of
  9") that is readable from outside the role's own process, plus the minimal
  prompt changes needed for the relevant role instructions to actually emit
  it at natural checkpoints (start of each full-sweep round, start of each
  review pass, etc.).
- STORAGE DECIDED (owner-approved 2026-09-03): a DEDICATED FILE, not a
  `docs/ai/STATE.yaml` field. See "Why not STATE.yaml" below — this is
  settled on the merits and Planning should not re-open it, though Planning
  still chooses the file's path, shape and write discipline.
- Out of scope: real-time streaming of a role's internal token-by-token
  output; a UI/dashboard for visualizing heartbeats (an operator/orchestrator
  reading the field directly is sufficient for this change); redesigning the
  SKILL_LOOP tick/dispatch architecture itself.

## Why not STATE.yaml (decided, with evidence)
Two independent facts make `docs/ai/STATE.yaml` the wrong home, and either
one alone is disqualifying:

1. **The roles that most need to emit a heartbeat are forbidden from writing
   it.** `.aai/SUBAGENT_CONTRACT.md:72` — "A dispatched subagent MUST NOT
   write `docs/ai/STATE.yaml`; the orchestrator is the SOLE STATE writer" —
   and its hazard table repeats the rule against exactly the "my update is
   tiny" rationalisation. The long-running subagents are the subject of this
   change, so a STATE.yaml heartbeat would need either a carve-out in that
   contract or an orchestrator that cannot see inside the role, which is the
   very gap being closed.
2. **STATE.yaml is per-worktree, not shared.** It is gitignored
   (`.gitignore:79`), so every worktree carries its own copy; the
   orchestrator hand-syncs it, and `close-work-item.mjs` says so out loud
   ("state-reconcile wrote <worktree>/docs/ai/STATE.yaml (this worktree's own
   STATE); the main checkout's STATE ... is untouched"). A heartbeat written
   by a role inside its worktree would land in a file the observer never
   reads — missing the entire point.

There is also a semantic mismatch: STATE.yaml is low-frequency, authoritative
and read by gates (`branch-guard`, `validation-waiver`, `close-work-item`);
a heartbeat is high-frequency, advisory and must never gate anything (see
Constraints). Putting an advisory signal inside a gate-bearing file invites
exactly the coupling the Constraints section forbids.

Consequence worth stating plainly: this keeps the change off the
`protected_paths_l3` surface (`.aai/scripts/state.mjs`), so it needs no owner
sign-off. That is a RESULT of the decision, not its reason — if the merits
had pointed at STATE.yaml, the right move would have been to ask the owner,
not to route around the guard.

Design consequence Planning must honour: the file must live in a single
well-known location the OBSERVER can read regardless of which worktree a role
is running in — a per-worktree heartbeat reproduces defect 2 above.

## Affected Area
- A new small script for writing/reading the heartbeat file (NOT
  `.aai/scripts/state.mjs`, which is a protected L3 path and is ruled out
  above on the merits).
- The role prompts that run long (`.aai/VALIDATION.prompt.md`,
  `.aai/CODE_REVIEW.prompt.md`, `.aai/IMPLEMENTATION.prompt.md`,
  `.aai/REMEDIATION.prompt.md` or equivalents) — each needs a small, optional
  instruction to update the heartbeat at natural checkpoints.
- Optionally, orchestrator-facing reporting (SKILL_LOOP status output) to
  surface the latest heartbeat value when asked for a status report.

## Desired Behavior (To-Be)
- While a dispatched role is running, an external observer can read a
  single, cheap, well-known location (e.g. `docs/ai/STATE.yaml`'s
  `heartbeat:` block, or a small gitignored `docs/ai/HEARTBEAT.json`) and see
  the role's own most recent self-reported progress marker plus a timestamp,
  without needing to interrupt or query the running subagent itself.
- A stale heartbeat (last update older than some threshold relative to the
  role's own typical cadence) is itself a useful signal — "likely stuck or
  hung" — though this change only needs to make the raw signal available; a
  stuck-detection heuristic can be built on top of it later if wanted.
- The heartbeat is best-effort: a role that fails to update it must not be
  treated as failed for that reason alone; absence of a heartbeat degrades to
  today's behavior (silence), not a new failure mode.

## Acceptance Criteria
- AC-001: A documented, single well-known location exists for a role to
  record `{ref_id, role, message, updated_at}`-shaped progress, writable via
  a single script invocation (not raw file editing) so the shape stays
  consistent.
- AC-002: At least one long-running role prompt (recommend Validation, since
  its full-sweep rounds are the most reproducibly long operation observed
  this session) is updated to emit a heartbeat at the start of each
  full-sweep round, with a fixture/manual test demonstrating the value
  updates as the role progresses through multiple rounds.
- AC-003: Reading the heartbeat requires no more than one script invocation
  or file read, and works correctly (returns "no heartbeat" cleanly, not an
  error) when no role has ever run or the field/file does not exist yet.
- AC-004: The heartbeat mechanism does not introduce a new git-tracked file
  that needs committing per-update (it belongs alongside the other
  per-developer runtime state such as STATE.yaml's ride-local fields, or is
  explicitly gitignored) and does not participate in any append-only ledger
  invariant.

## Verification
- Command(s) and expected results:
  - Dispatch a Validation role on a scope with a full sweep spanning
    multiple rounds; while it runs, read the heartbeat location from a
    separate shell and confirm the message/timestamp advances between
    rounds.
  - Read the heartbeat location before any role has ever run on a fresh
    checkout: confirm a clean "none recorded" result, not an error or crash.
  - Confirm the heartbeat write path does not affect the role's own
    pass/fail outcome if the write itself is skipped (e.g. simulate a
    read-only STATE.yaml momentarily) — the role's substantive work must not
    depend on the heartbeat write succeeding.

## Constraints / Risks
- Must not become a new source of merge conflicts or noisy diffs on shared
  files — if implemented as a STATE.yaml field, confirm STATE.yaml's existing
  gitignore/local-only status (per this session's established understanding
  that STATE.yaml is per-developer runtime state) actually holds, otherwise
  prefer a separate gitignored file.
- Must not become a new precondition that PR/ship gating reads and can be
  left stale/misleading the way the Metrics Flush interaction did (see
  [[metrics-flush-invalidates-pr-precondition]]) — the heartbeat is
  observational only and must never gate anything.
- No secret is referenced by this scope (SECRETS PREFLIGHT skipped).

## Notes
- Filed per operator request after a retrospective review of session
  friction points; motivated most directly by the ISSUE-0046 ride, whose
  three Validation/Code Review rounds each ran long with no intermediate
  signal available to the operator.

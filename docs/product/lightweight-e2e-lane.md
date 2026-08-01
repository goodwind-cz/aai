---
id: lightweight-e2e-lane
type: product
capability: lightweight-e2e-lane
status: current
delivered_by:
  - CHANGE-0103
spec: docs/specs/SPEC-0112-spec-lightweight-e2e-lane.md
updated: 2026-08-01
---

# Small changes stop paying the full ceremony price

## What it does

Every ride used to pay a flat ~42-minute pipeline floor (two full CI rounds
plus a 10-minute external-review window) no matter how small the change. Now
a **deterministic gate** (`lane-gate.mjs`) checks four machine-readable
predicates and, when ALL hold, the ride takes a **fast lane**:

- external bot sweep becomes optional-on-demand (the mandatory internal
  dual-verdict review still runs and still gates the merge),
- the docs-only close commit runs core suites instead of a second full
  CI round.

Anything outside the gate — bigger diffs, higher ceremony, protected or core
surfaces — takes the heavy lane, byte-for-byte identical to before.

## How to use it

Nothing to invoke. The PR ceremony runs the gate itself and prints the lane
with its predicate values into the PR body (`## Lane`). To qualify, a ride
must have: ceremony level 0 or 1, implementation mode `direct`, `untested`
or `loop`, a diff under 5 files within safe classes (docs, at most one
prompt file, one test, one non-core script), and no protected/shared-lib
surface. Any reviewer or bot can re-arm the full sweep by commenting;
a review may reclassify the ride upward at any time.

## Data model

- No new state. The gate reads the spec frontmatter (ceremony level), the
  recorded implementation strategy, and the diff file list; it emits
  `LANE fast` / `LANE heavy reason=<first-failing-predicate>` plus one
  auditable line per predicate (also `--json`).

## Interfaces and contracts

- The lane is **never agent judgment**: every predicate is script-computed
  and every degenerate input (missing spec, garbage frontmatter, unreadable
  STATE, failed diff, absent protected-path config) fails closed to heavy.
- Renamed files are read with rename-detection disabled, so a protected file
  renamed to a benign path still surfaces its original path.
- Core workflow engines and multi-prompt diffs never qualify.
- Post-merge pushes to main and the nightly run always execute the FULL
  suite — the backstop behind every fast-lane merge.

## Limits and non-goals

- The fast lane trims process, never review: the internal dual-verdict code
  review remains mandatory on the exact final diff.
- Live wall-clock savings are measured on the first real fast-lane ride
  (deferred evidence, recorded in the spec).

## Links

- Request: docs/issues/CHANGE-0103-lightweight-e2e-lane.md
- Spec: docs/specs/SPEC-0112-spec-lightweight-e2e-lane.md

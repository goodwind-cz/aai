---
id: routing-table-freshness
type: product
capability: routing-table-freshness
status: current
delivered_by:
  - routing-tables-have-an-owner-and-a-seam
spec: docs/specs/SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md
updated: 2026-11-13
---

# Routing and pricing tables that say how old they are

## What it does

The two tables that decide which model each factory role runs on
(`.aai/system/MODEL_ROUTING.yaml`) and what that run costs
(`.aai/system/PRICING.yaml`) now carry a machine-readable freshness stamp, and
the doctor reports when either table has gone past its refresh cadence, when a
stamp is missing or malformed, or when a table cannot be read. A change to a
routed model id or a price without a newer stamp fails the pricing test suite,
so stamping is part of changing the table. Keeping the tables current is a
central, monthly job in the upstream repository (the ROUTING_REFRESH routine),
delivered to projects by `/aai-update`; projects do not maintain the tables
themselves. The first refresh (2026-11-13) moved every harness section to the
vendors' current model ids and corrected stale prices.

## How to use it

- See the state of both tables: `/aai-doctor` shows a `CAT-21 Routing Tables`
  line (PASS when fresh, WARN naming the file, its date and the remedy
  otherwise). It never fails a non-strict doctor run.
- Directly: `node .aai/scripts/table-freshness.mjs check` prints one
  FRESH / LAPSED / INVALID / ABSENT line per table. The horizon defaults to the
  table's own `cadence_days` (30); override with `--horizon-days <n>` or the
  `AAI_TABLES_HORIZON_DAYS` environment variable.
- Upstream maintainers: `node .aai/scripts/table-freshness.mjs stamp-guard
  --base <rev>` and `node .aai/scripts/table-freshness.mjs routed --since
  <date>` are the checks the pricing suite runs; the monthly routine is
  instantiated once by the owner (command in `docs/product/universal-routines.md`).

## Data model

- `MODEL_ROUTING.yaml` gains a `routing_meta:` block with
  `last_updated_utc` and `cadence_days`, mirroring PRICING.yaml's existing
  `pricing_meta.last_updated_utc` and `update_policy.cadence_days`. Model
  resolution ignores the block.
- PRICING.yaml rows carry `source_ref` and `last_verified_utc` as before; the
  refresh adds sources for the vendors' model and deprecation pages.

## Interfaces and contracts

- `table-freshness.mjs check [--root <dir>] [--now <ISO>] [--horizon-days <n>]`:
  exit 0 when every present table is FRESH, 1 on LAPSED or INVALID, 2 on a
  usage error or an invalid horizon override.
- `table-freshness.mjs stamp-guard --base <rev> [--root <dir>] [--now <ISO>]`:
  compares only routed id lines and priced model/alias lines; exit 1 when they
  changed without a strictly later stamp, when the stamp was lowered, or when
  the head marker is invalid (including more than one day in the future);
  exit 2 on an unresolvable base or any git read failure.
- `table-freshness.mjs routed --since <date> [--allow-stale <ids>]`: every
  routed id must be an exact, priced PRICING key verified on or after the date;
  exit 0 only when every line is OK or ALLOWED.
- Doctor category `CAT-21 Routing Tables` (WARN-only; `--strict` exits 1 on a
  WARN; `--json` carries per-table detail); absent when neither table exists.
- Routine `.aai/routines/ROUTING_REFRESH.routine.md` (extended profile):
  opens a pull request, never merges, and stops in any checkout where the
  tables are not tracked (every normal downstream install).

## Limits and non-goals

- The stamp makes a lapse visible; it cannot make prices or model ids correct.
  Values come from a monthly read of vendor pages.
- A refresh moves a bound id only to the vendor's named successor; binding a
  model of a different price class (for example a more expensive premium tier)
  is an owner decision.
- A consumer-owned override file that `/aai-update` never overwrites is not
  part of this capability yet; it is a planned follow-up.
- The scheduled trigger for the routine is not created automatically.

## Links

- Request: docs/issues/CHANGE-0192-routing-tables-have-an-owner-and-a-seam.md
- Spec: docs/specs/SPEC-0289-spec-routing-tables-have-an-owner-and-a-seam.md
- Validation evidence: docs/ai/reports/VALIDATION-20261113T1512Z-routing-tables-have-an-owner-and-a-seam.md

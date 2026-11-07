---
id: singleton-reservation-portability
type: product
capability: singleton-reservation-portability
status: current
delivered_by:
  - singleton-reservation-portability
spec: docs/specs/SPEC-0275-spec-singleton-reservation-portability.md
updated: 2026-11-06
---

# Portable document-number reservations

## What it does

Document-number allocation can reserve one number on a Git server without atomic multi-ref push support. Coupled families still reserve all their refs atomically. Network operations have finite deadlines and report the operation, failure category and recovery action when they fail.

## How to use it

Run the existing allocator for an explicit draft:

```sh
node .aai/scripts/allocate-doc-number.mjs --path docs/issues/CHANGE-DRAFT-example.md --base-ref origin/main
```

The default deadline is 30000 ms per network call. Set `AAI_DOCNUM_NETWORK_TIMEOUT_MS` to an integer from 1 through 300000 to change it. Invalid values produce a warning and retain the finite default. This deadline applies to reservation pushes, fetches and remote reservation-ref reads; a batch may make several calls.

## Data model

Reservation refs remain under `refs/aai/docnums/`. Each reservation attempt uses a unique commit object and an empty expected-value lease to require an absent ref. Existing refs remain protected. Provisional allocations retain `number_reserved: false` when a reservation cannot be confirmed.

## Interfaces and contracts

The allocator commands and exit-code contracts remain unchanged. A single-ref push omits `--atomic`; a multi-ref push requires it and has no sequential fallback. Only confirmed create-only collisions retry another candidate number. Timeout, unsupported atomic capability, permission, connectivity and unknown failures are diagnosed separately.

A timed-out push can have reached the server. Inspect the named remote reservation refs before reconciliation; a timeout establishes neither rollback nor remote absence. Use the existing `--reserve` completion flow only after checking the remote state and following its collision diagnostics.

## Limits and non-goals

The deadline bounds each network subprocess, not the entire allocation batch or every credential-helper descendant. This change adds no capability cache or automatic reservation-ownership reconciliation. Hermetic Git fixtures establish the tested transport behavior; they do not establish a live Azure round trip or native Windows runtime behavior.

## Links

- Request: docs/issues/CHANGE-0247-singleton-reservation-portability.md
- Spec: docs/specs/SPEC-0275-spec-singleton-reservation-portability.md
- Parent proposal: docs/rfc/RFC-0016-downstream-pr-ceremony-reliability.md
- Validation evidence: recorded in the pull request and linked specification.

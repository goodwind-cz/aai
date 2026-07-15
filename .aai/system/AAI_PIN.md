# AAI Pin

- Source path: <set by sync script>
- Template version: <set by sync script>
- Template commit: <set by sync script>
- Canonical repo: <set by sync script>
- Synced at (UTC): <set by sync script>

Notes:
- This file is overwritten by .aai/scripts/aai-sync.* during each sync run.
- Field contract (spec-doctor-vendored-layer-drift D1/D2):
  - `Template commit` — HEAD sha of the sync source at sync time.
  - `Canonical repo` — origin remote URL of the sync source (UNKNOWN when the
    source has no origin). Consumed by `.aai/scripts/layer-drift.mjs`
    (doctor CAT-13) to detect vendored-layer drift vs canonical main.
  - Backward tolerance: pins written before this contract lack the
    `Canonical repo` line — the drift check falls back to `Source path` when
    that directory is locally reachable, else reports "unverifiable" (info,
    never a failure). Re-run /aai-update to restamp with the full contract.

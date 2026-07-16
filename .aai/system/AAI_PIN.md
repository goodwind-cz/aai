# AAI Pin

- Source path: <set by sync script>
- Template version: <set by sync script>
- Template commit: <set by sync script>
- Canonical repo: <set by sync script>
- Profile: <set by sync script>
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
- Profile field contract (CHANGE layer-profiles / spec-layer-profiles):
  - `Profile` — which vendored-layer profile the last sync installed
    (`core` = the workflow engine per .aai/system/PROFILES.yaml, or
    `extended` = the whole layer). Stamped by both sync scripts.
  - Sticky: a sync run WITHOUT --profile honors this line, so /aai-update
    keeps the installed profile instead of reinstalling the full layer.
  - Backward tolerance: pins written before this contract lack the line —
    treated as `extended` (implicit); layer-drift.mjs ignores the line by
    construction (key-anchored parser; regression-pinned by its TEST-015).
    Doctor CAT-13 displays the profile, absent line -> "extended (implicit)".

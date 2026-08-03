---
id: release-roll-scaffold
number: 116
type: change
status: done
user_visible: false
ceremony_level: 1
links:
  pr:
    - 221
  commits:
    - 12dc8c9f448f4c4e1e1b11b74813ac64aa7cc9b2
---

# Change — release roll consumes the pre-existing scaffold (root cause of the duplicate class)

## Summary
- Root cause found, 4th occurrence: the duplicate bare `## [unreleased]`
  heading was planted by the RELEASE ENGINE itself — the roll inserts a
  fresh scaffold above the rolled section AND copied the pre-existing
  scaffold through into the versioned region (both v2026.08.02 and
  v2026.08.03 cuts did it on the real repo). TEST-022 (CHANGE-0111) guards
  PR-time, but the engine writes directly to main, so it kept planting the
  bomb the next CHANGELOG PR would trip on.
- Why tests never saw it: the `two_entries` cut fixture had NO pre-existing
  scaffold — the real CHANGELOG always has scaffold+entries.
- Fix: the roll now CONSUMES pre-existing bare scaffolds (skips copying
  them); exactly one fresh scaffold remains. New fixture kind
  `scaffold_plus_entries` + TEST-023, RED-proven against the pre-fix engine
  (found 2). The live duplicate planted by the v2026.08.03 cut is cleaned
  in the same diff.

## Acceptance Criteria
- AC-001: cut over scaffold+entries leaves exactly one bare scaffold
  (TEST-023; RED=2 on pre-fix engine).
- AC-002: existing roll semantics untouched (TEST-003 bodies byte-preserved,
  full release suite green).
- AC-003: live CHANGELOG passes TEST-022 after the cleanup.

## Verification
- test-aai-release.sh full suite incl. new TEST-023; docs-audit strict CLEAN.

## Constraints / Risks
- Ceremony L1, direct. aai-release.sh is a core ceremony script — heavy
  lane, correctly.

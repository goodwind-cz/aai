---
id: aai-version-file
number: 117
type: change
status: done
user_visible: true
ceremony_level: 1
links:
  pr:
    - 222
  commits:
    - c0a4cbd66c7fd9cd2ed87631bfaf14bc74c19636
---

# Change — downstream pins stop saying UNKNOWN: releases stamp AAI_VERSION.md

## Summary
- Operator-found after the v2026.08.03 deployment check: every downstream
  `.aai/system/AAI_PIN.md` said `Template version: UNKNOWN`. Root cause:
  `aai-sync.*` reads `docs/ai/AAI_VERSION.md` from the sync SOURCE — a file
  that never existed in the AAI repo and that no release cut ever wrote.
- Fix, three layers: (1) `aai-release.sh` + `.ps1` write/refresh
  `docs/ai/AAI_VERSION.md` in the release commit (E2E-proven: fixture cut
  stamps `- Version: v7.7.7`); (2) the file is seeded NOW at v2026.08.03 so
  deployments from current main stamp correctly without waiting for the
  next cut; (3) `aai-sync.sh` gains a fallback — source without the file
  derives `vX (tag)` from the newest reachable release tag instead of
  UNKNOWN.

## Acceptance Criteria
- AC-001: a cut writes the version file with the exact version (TEST-003
  extended pin).
- AC-002: sync from a source WITH the file stamps its version; without it,
  the tag fallback fires; both-absent still degrades to UNKNOWN honestly.
- AC-003: ps1 engine parity (parse-checked; Windows CI validates behavior).

## Verification
- Release suite green incl. extended TEST-003; fixture E2E cut; docs-audit
  strict CLEAN.

## Constraints / Risks
- Ceremony L1, direct. Release/sync are core ceremony scripts — heavy lane.
- AC-002 sync arms verified by inspection + fallback logic; a dedicated
  sync-suite arm is left to the sync suite's next touch (noted honestly).

---
id: layer-profiles
type: change
number: 23
status: draft
links:
  research: RES-0001
  pr: []
  commits: []
---

# Change — Core/Extended Profiles for the Vendored Layer

## Summary
- aai-sync gains profiles (OpenSpec pattern, RES-0001 P3): core (the
  workflow engine: orchestration, roles, intake, state/docs scripts, gates)
  vs extended (everything: dashboards, share, decapod, session tooling).
  Target projects choose; default remains extended (zero behavior change for
  existing consumers).

## Scope
- In scope: a manifest (.aai/system/PROFILES.yaml listing prompt/skill/script
  membership; every existing file must be classified — a conformance test
  fails on unclassified additions); aai-sync.sh/.ps1 --profile core|extended
  (default extended); AAI_PIN records the profile; layer-drift unaffected
  (pin commit comparison is profile-agnostic); doctor line shows the profile.
- Out of scope: changing any prompt content; per-file cherry-picking.

## Acceptance Criteria
- AC-001: PROFILES.yaml classifies 100% of vendored files (conformance test
  enumerates the tree and fails on unlisted).
- AC-002: sync --profile core copies exactly the core set (fixture test, sh;
  ps1 parity asserted); default run byte-identical to today.
- AC-003: pin records profile; doctor displays it; suites + audit green.

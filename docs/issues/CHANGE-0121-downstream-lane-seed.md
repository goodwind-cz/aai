---
id: downstream-lane-seed
number: 121
type: change
status: draft
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — fast lane stops being structurally dead downstream: seed the guard config

## Summary
- Live cost forensics (InfluxDriver log): the exact target ride of the
  lightweight lane — 1-line fix, direct strategy — computed `LANE heavy`
  downstream because `docs/ai/docs-audit.yaml` DOES NOT EXIST in target
  projects: `protected_config_missing` fails closed (correct per SPEC-0112)
  but means NO downstream project can EVER ride fast until someone
  hand-writes the config. The lane's biggest value is exactly there.
- Fix: seed a minimal `docs/ai/docs-audit.yaml` when missing at
  install/update (aai-sync seed-when-missing, mirroring the CHANGE-0094
  update-config precedent): protected_paths_l3 with the vendored defaults +
  report-only dials + docs_ai_canon_extra: []. Fail-closed semantics stay
  untouched — the config simply exists now.
- Second finding recorded for a SEPARATE decision (not implemented here):
  the ride's PR counted 9-10 files, most of them CEREMONY docs (intake,
  spec, reviews, INDEX, CHANGELOG) — the diff-surface predicate spends its
  5-file budget on the process's own artifacts. Options (pick later, with
  data): exclude ceremony-generated paths from the count, or raise the cap
  for docs-class files. Needs its own measured intake.

## Acceptance Criteria
- AC-001: sync into a target without the config seeds the minimal file
  (fixture-proven); an existing config is NEVER overwritten.
- AC-002: after seeding, lane-gate in the fixture target resolves
  protected_config=present (fast becomes reachable).
- AC-003: ps1 sync parity.

## Constraints / Risks
- Ceremony L1. Touches aai-sync.sh/.ps1 + a seed template file.
- Seeded protected_paths_l3 must match the VENDORED layer's real protected
  set — source it from the canonical template, not a copy.

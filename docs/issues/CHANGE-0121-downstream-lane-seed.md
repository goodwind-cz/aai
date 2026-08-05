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

## Acceptance Criteria Status

Reconciled at implementation hand-off. Ceremony L1 — no separate spec; this
intake is the authoritative scope.

| AC | Description | Status | Evidence | Review-By | Notes |
|----|-------------|--------|----------|-----------|-------|
| AC-001 | Sync into a target without docs/ai/docs-audit.yaml seeds the minimal file; an existing config is NEVER overwritten | done | test-aai-sync-seed TEST-004 (fresh target seeded, equals the template) and TEST-005 (operator config byte-identical after re-sync); both RED before the engine change | — | seed prints one operator-facing SEED note naming the enforced-mode consequence |
| AC-002 | After seeding, lane-gate in the fixture target resolves protected_config=present (fast becomes reachable) | done | test-aai-sync-seed TEST-004 lane-gate arm — `protected_config=present ok` plus `LANE fast`; negative control removes the seed and gets `LANE heavy reason=protected_config_missing` | — | fail-closed semantics untouched; only the config's existence changed |
| AC-003 | ps1 sync parity | done | aai-sync.ps1 seed block added; pwsh ParseFile clean; test-aai-sync-seed TEST-006 pins both engines; ps1-quality and layer-profiles TEST-008 (ps1 end-to-end set equality) green | — | Windows CI validates runtime behavior |
| AC-004 | Seeded protected_paths_l3 is single-sourced from the canonical vendored set, not a drifting hand copy | done | test-aai-sync-seed TEST-006 diffs the template's list against this repo's docs/ai/docs-audit.yaml; drift-sanity run (one entry mutated) fails the suite | — | constraint promoted to a checked AC |

## Verification
- test-aai-sync-seed (TEST-004..006 RED before implementation, green after),
  test-aai-lightweight-lane, test-aai-layer-profiles, test-aai-suite-select,
  test-aai-update, test-aai-release (TEST-022 scaffold invariant),
  test-aai-hygiene-pack, test-ps1-quality — all green.
- docs-audit --check --strict --no-event: CLEAN.

## Constraints / Risks
- Ceremony L1. Touches aai-sync.sh/.ps1 + a seed template file.
- Seeded protected_paths_l3 must match the VENDORED layer's real protected
  set — source it from the canonical template, not a copy.
- Known consequence, documented in the template header and the SEED note:
  docs-audit runs report-only while the config is ABSENT and enforced once it
  EXISTS, so `docs-audit.mjs --check` starts hard-failing on new orphans and
  violations in an adopting project. The dials that gate commits and closes
  are all seeded report-only, so nothing that previously passed starts
  blocking; a project with pre-existing docs sets `legacy_until_date`.

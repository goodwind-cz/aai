---
id: seed-update-config
number: 94
type: change
status: done
user_visible: false
links:
  pr:
    - 197
  commits:
    - 5546b7954ae654df6928a8fb1dea6b0e61a7dfba
---

# Change — install/sync seeds docs/ai/update-config.yaml when missing

## Summary
- The auto-update feature (CHANGE-0091) ships update-check.mjs (core profile)
  and the SessionStart hook (hooks/ synced), but its LOCAL policy file
  `docs/ai/update-config.yaml` is NOT installed by aai-sync.{sh,ps1} — the
  docs/ai/ handling only PRESERVES runtime data, and no step seeds the config.
- Consequence: a target project works (absent == notify default) but the
  `auto` opt-in knob is effectively HIDDEN — the operator never sees the file
  or its documented options unless they read the docs. This is the same
  seed-when-missing gap TECHNOLOGY.md already solves.

## Fix
- Add `.aai/templates/update-config.template.yaml` (the documented default
  policy: `mode: notify`, `throttle_hours: 24`, with the full key comments —
  mirror the current docs/ai/update-config.yaml content).
- In aai-sync.sh AND aai-sync.ps1, SEED `docs/ai/update-config.yaml` from that
  template ONLY when the target's copy is MISSING (mirror the TECHNOLOGY.md
  seed-when-missing: never overwrite an existing project-owned config).
- Classify the new template in PROFILES.yaml core so the profile union == the
  vendored tree.

## Acceptance Criteria
- AC-001: a fresh target sync (no docs/ai/update-config.yaml) SEEDS the file
  from the template with `mode: notify` + `throttle_hours: 24` + comments;
  bash and PowerShell parity (both sync scripts).
- AC-002: an EXISTING docs/ai/update-config.yaml in the target is PRESERVED
  byte-for-byte (never overwritten by a re-sync) — it is project-owned policy.
- AC-003: the template is in PROFILES core (layer-profiles union intact); no
  prompt-corpus bytes.

## Verification
- extend tests/skills for aai-sync seed behavior (fresh -> seeded; existing ->
  preserved), bash; the ps1-quality windows-5.1 functional smoke asserts the
  seeded file appears on a fresh target.
- docs-audit --check; layer-profiles.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------|--------|----------|-----------|-------|
| Spec-AC-01 | AC-001 — a fresh target sync seeds docs/ai/update-config.yaml from the template (mode notify + throttle_hours 24 + comments); bash and PowerShell parity | done | docs/ai/tdd/green-20260729T183017Z-sync-seed.log (TEST-001); test-aai-layer-profiles.sh TEST-008 (ps1 end-to-end parity) | 2026-10-29 | RED docs/ai/tdd/red-20260729T182823Z-sync-seed.log; ps1 Windows-5.1 smoke in ps1-quality.yml |
| Spec-AC-02 | AC-002 — an existing target docs/ai/update-config.yaml is preserved byte-for-byte (never overwritten by a re-sync) | done | docs/ai/tdd/green-20260729T183017Z-sync-seed.log (TEST-002 byte-for-byte preserve) | 2026-10-29 | negative control; seed is strictly when-missing |
| Spec-AC-03 | AC-003 — the template is in PROFILES core (layer-profiles union intact); no prompt-corpus bytes | done | test-aai-layer-profiles.sh TEST-001 (core=136, 100% classification); test-aai-sync-seed.sh TEST-003 | 2026-10-29 | suite-map row aai-sync-seed added (hygiene-pack) |

## Constraints / Risks
- Ceremony L2. Windows parity matters (the sync just had a 5.1 copy bug);
  the windows-5.1 functional smoke is the authoritative check. Seed must be
  strictly when-missing (never clobber an operator's policy).

## Notes
- Completes the auto-update feature's discoverability. Follows CHANGE-0091
  (auto-update) + CHANGE-0092 (the 5.1 sync fix).

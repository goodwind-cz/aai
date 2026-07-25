---
id: feedback-triage-offline
number: 48
type: change
status: done
links:
  rfc: RFC-0012
  spec: null
  pr:
    - 147
  commits:
    - 82ca9e3f2225af92a38e09dfba8128c18fbd2e78
---

# RFC-0012 Phase 2 / RFC-0013 Slice B — offline triage over schema-v2 records (local mode)

## Summary
- The offline triage core, now that schema v2 (Slice A) gives it real signal.
  Delivers `/aai-feedback-triage` + `.aai/scripts/aai-feedback-triage.mjs`: reads
  the local spool, applies hard gates, SCORES clusters using the v2 structured
  fields (impact/confidence/reproducible + recurrence), clusters by fingerprint,
  and emits a **LOCAL triage report** — no network, no GitHub token, no writes.
- `review`/`auto` upsert (network) and the auto-gate (D8) are LATER slices. Default
  mode is `local` (summarize only).

## Type
- change (feature — RFC-0012 Phase 2, offline slice; consumes RFC-0013 schema v2)

## Motivation / Business Value
- Slice A made capture persist structured signal; nothing reads it yet. This turns
  the raw spool into a triaged, scored, de-duplicated LOCAL summary an operator can
  review — the exact input the later review-mode upsert consumes — built and proven
  entirely OFFLINE first (the safe order: establish scoring/gating before any
  network surface exists).

## Scope
- In scope:
  - `.aai/scripts/aai-feedback-triage.mjs` — dependency-free OFFLINE engine:
    reads `docs/ai/friction/observations.jsonl`; HARD GATES per observation
    (schema_version in {1,2}; failure_class in the FRICTION_PROTOCOL taxonomy;
    sanitization — only the persisted allowlist keys present); SCORES each kept
    observation with a deterministic composite of the v2 signals (impact,
    confidence, reproducible) with a v1 fallback (recurrence-only when v2 fields
    are absent); CLUSTERS by `fingerprint`; assigns a per-cluster DECISION
    (below-threshold: retain/aggregate; at/above: review_candidate) with
    `auto_publishable` ALWAYS false in this slice (auto is locked until Slice D).
    Writes a LOCAL report to `docs/ai/friction/triage-report.json` + a human
    stdout summary. No network, no token, no gh. Flags: `--spool` `--config`
    `--out` `--help`.
  - `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md` — thin portable wrapper documenting
    `/aai-feedback-triage` (explicit invocation; may also run from /aai-wrap-up or
    after a failed skill; NO resident daemon), mirroring SKILL_UPDATE's shape.
  - `.aai/feedback.yaml` — add a `triage` section: `mode` (local default),
    `thresholds.review_candidate` (score cutoff). Fail-closed to local.
  - Companion: classify the 2 new `.aai/**` files in PROFILES.yaml; the wrapper
    prompt grows corpus -> prompt-diet ledger true-up.
  - Tests: `tests/skills/test-aai-feedback-triage.sh` — gates, deterministic
    scoring, v2-signal vs v1-fallback scoring, clustering, fail-closed config,
    offline (static + runtime), local-only (no sendable payload), auto locked.
- Out of scope (later slices):
  - Any network / GitHub upsert / upstream issue search / the
    `<!-- aai-friction:v1:<fp> -->` marker WRITE / review-mode approval flow (Slice C).
  - The auto-gate (D8 acceptance ledger + unlock) — Slice D. Fix-PRs — Slice E.

## Affected Area
- `.aai/scripts/aai-feedback-triage.mjs` (new), `.aai/SKILL_FEEDBACK_TRIAGE.prompt.md`
  (new), `.aai/feedback.yaml` (triage section), `.aai/system/PROFILES.yaml`,
  `tests/skills/`, prompt-diet ledger (companion).

## Desired Behavior (To-Be)
- Running the engine over a spool produces a deterministic, scored,
  fingerprint-clustered LOCAL report; honors the hard gates (a non-AAI-owned,
  schema-invalid, or unsanitized observation is dropped with a reason); scoring
  uses the v2 signals when present and falls back to recurrence for v1 records;
  performs NO network I/O; in `local` mode only summarizes; no cluster is ever
  `auto_publishable` in this slice.
- Missing/invalid `feedback.yaml` degrades to local-only, never errors the caller.

## Acceptance Criteria
- AC-001: the engine reads the spool and applies all hard gates; a fixture failing
  each gate (bad schema_version, non-taxonomy failure_class, an extra
  non-allowlist key) is dropped with a named reason; a valid one is kept.
- AC-002: scoring is DETERMINISTIC (same spool bytes -> byte-identical report).
- AC-003: scoring uses the v2 signals — two observations identical except
  impact high vs low produce a higher score for the high-impact one; a v1 record
  (no v2 fields) scores via the recurrence fallback without error.
- AC-004: clustering groups observations by `fingerprint` (two same-fp rows -> one
  cluster with recurrence 2).
- AC-005: per-cluster decision honors `thresholds.review_candidate`; NO cluster is
  `auto_publishable` in this slice (grep-assertable + asserted in the report).
- AC-006: the engine performs NO network I/O and holds no token (static grep +
  runtime under an unroutable proxy still writes the report, exit 0).
- AC-007: `local` mode emits the local report only, NO sendable issue payload;
  `review`/`auto` are parsed but have no network side effect here (grep-assertable).
- AC-008: fail-closed config — a malformed feedback.yaml runs in local mode.
- AC-009: companion — 2 new `.aai/**` files classified in PROFILES.yaml; prompt-diet
  ledger trued up; layer-profiles + prompt-diet green.

## Verification
- `bash tests/skills/test-aai-feedback-triage.sh` (new; RED first).
- `node .aai/scripts/aai-feedback-triage.mjs --help` documents the offline contract.
- `bash tests/skills/test-aai-layer-profiles.sh` + `test-aai-prompt-diet.sh` green.
- `node .aai/scripts/docs-audit.mjs` CLEAN.

## Constraints / Risks
- OFFLINE-ONLY is the safety invariant of this slice (same discipline as Slice A) —
  enforce with static grep + runtime-under-blocked-network tests.
- Fail-closed config: any ambiguity degrades to `local`, never `review`/`auto`.
- No protected_paths_l3 surface (keep L2).

## Notes
- Scoring reads only the persisted structured fields (leak-free by construction);
  it never dereferences `evidence_ref` (path safety is Slice A's concern; deref is
  a later-slice decision).
- The eventual issue TITLE is templated from structured fields (RFC-0013 D2); the
  optional summary, when present, is already redaction-certified at capture.

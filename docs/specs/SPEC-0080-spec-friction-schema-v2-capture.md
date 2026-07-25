---
id: spec-friction-schema-v2-capture
type: spec
number: 80
status: done
ceremony_level: 2
links:
  requirement: CHANGE-0047-friction-schema-v2-capture
  rfc: RFC-0013
  pr:
    - 146
  commits:
    - 49bb6fcc74080c1501c9609d85d0d38b87ad1eb2
---

# SPEC — RFC-0013 Slice A: schema-v2 capture + hard redactor (capture pass)

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-0047-friction-schema-v2-capture.md
- RFC: docs/rfc/RFC-0013-friction-record-v2-redaction.md (D1-D5)
- Foundation: .aai/scripts/aai-friction.mjs, .aai/system/FRICTION_PROTOCOL.md
- Technology contract: docs/TECHNOLOGY.md

## Implementation strategy
- Strategy: tdd
- Rationale: Privacy-critical trust-boundary code (the redactor decides what
  sensitive text may persist) with deterministic, adversarially-testable behavior
  (deny-by-default detectors, fail-closed drop, enum/shape validation, byte-exact
  v1 backward compatibility). Every property is a clean RED/GREEN over a concrete
  fixture; the security surface mandates TDD per the strategy rule.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: Extends one existing script + one new module + config + doc
  + tests; reversible; dedicated branch. No protected_paths_l3 surface.
- User decision: inline
- Base ref: main
- Inline review scope: .aai/scripts/aai-friction.mjs, .aai/scripts/lib/aai-redact.mjs, .aai/feedback.yaml, .aai/system/FRICTION_PROTOCOL.md (schema section), .aai/system/PROFILES.yaml (new entries), tests/skills/test-aai-friction.sh

## Acceptance Criteria Mapping
- Spec-AC-01 (AC-001): `schema_version` ∈ {1,2}; a v1 record persists EXACTLY the
  8 legacy keys BYTE-IDENTICAL to today; a v2 record persists the 8 plus the valid
  structured fields present; any input key outside the expanded allowlist is
  dropped (deny-by-default). Verification: v1 golden-line diff + v2 key-set assert + forged-key drop.
- Spec-AC-02 (AC-002): `reproducible` (bool), `impact` (low|medium|high|critical —
  the existing IMPACT_VALUES domain, a superset of RFC-0013 D1's initial
  low|medium|high; still a leak-free enum), `confidence` (low|medium|high),
  `workaround` (none|manual|automatic) are type/enum-validated; an invalid value →
  named-field ValidationError, nothing persisted. Verification: per-field bad fixtures.
- Spec-AC-03 (AC-003): `evidence_ref` accepts ONLY a repo-relative doc path
  (`docs/...`) or an AAI doc id (`^(SPEC|CHANGE|ISSUE|RFC|PRD|RES|DEBT)-\d{4}`);
  a URL / absolute path / arbitrary string → rejected. Verification: accept + reject fixtures.
- Spec-AC-04 (AC-004): with `capture.summary_enabled` false (default) a `summary`
  in input is NEVER persisted; with it true, a clean summary persists and
  `redaction_status: capture_clean`. Verification: default-off fixture (no summary key) + enabled-clean fixture.
- Spec-AC-05 (AC-005): with summary enabled, a summary containing ANY detector
  token is DROPPED (summary key absent from the persisted line — not kept
  class-redacted in the capture pass) and `redaction_status: capture_dropped_fields`;
  the structured record still persists. Verification: per-detector poisoned fixtures.
- Spec-AC-06 (AC-006): structured/enum/bool/evidence_ref values never flow through
  the redactor (only `summary` does) — the redactor is invoked on the summary path
  only. Verification: structural grep + a fixture whose structured field contains
  a detector-like string still persists that field verbatim (not redacted).
- Spec-AC-07 (AC-007): capture performs NO network I/O and holds no token — static
  grep + runtime under an unroutable proxy still exits 0 and writes the line. Verification: static + runtime.
- Spec-AC-08 (AC-008): companion — the 2 new `.aai/**` files (aai-redact.mjs,
  feedback.yaml) classified once in PROFILES.yaml; layer-profiles green; prompt-diet
  green (no corpus growth expected — .aai/system/*.md and .aai/scripts are not corpus). Verification: both suites green.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC    | Description                                                    | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | v1 byte-identical; v2 persists structured; forged keys dropped | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-02 | reproducible/impact/confidence/workaround type+enum validated  | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-03 | evidence_ref safe-pointer shape (doc path / AAI id only)        | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-04 | summary opt-in default-off; clean summary → capture_clean       | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-05 | poisoned summary DROPPED, capture_dropped_fields, record kept   | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-06 | only summary is redacted; structured fields bypass verbatim     | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-07 | no network / no token (static + runtime)                       | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |
| Spec-AC-08 | companion PROFILES classification; suites green                | done    | docs/ai/tdd/green-20260725T091050Z-schema-v2.log | —         | GREEN |

## Implementation plan
- `.aai/scripts/lib/aai-redact.mjs` (new, node stdlib only): `redactSummary(str)`
  → `{ ok: true, value }` when certified clean, or `{ ok: false, reason }` when a
  detector fires (→ caller DROPS). Deny-by-default detector set (RFC-0013 §3):
  secret shapes (long base64/hex/high-entropy, `AKIA`, `-----BEGIN`), absolute
  paths (`/…`, `C:\…`), URLs, emails, hostnames/FQDNs, IPv4/IPv6, `@user`/
  `user:pass`, git remotes, long digit runs. Pure, no I/O.
- `.aai/scripts/aai-friction.mjs`: accept schema_version 1|2; for v2 add the
  structured fields to the persisted fresh-object (still deny-by-default);
  validate enums/bool/evidence_ref shape; route `summary` through the redactor
  ONLY when `capture.summary_enabled`; set `redaction_status`. v1 path untouched.
- `.aai/feedback.yaml` (new): `capture: { summary_enabled: false }` + a comment
  that triage/upsert config lands in later slices.
- `.aai/system/FRICTION_PROTOCOL.md`: schema section → v2 (fields + redaction).
- `.aai/system/PROFILES.yaml`: classify aai-redact.mjs (core, shares state-lib
  neighborhood? → extended, alongside aai-friction.mjs) + feedback.yaml (extended).

## Seam analysis (6a)
- SEAM 1 (config → capture behavior): `feedback.yaml summary_enabled` gates whether
  the redactor path can ever run. INTEGRATION TEST: default (no config / false) →
  summary never persisted even when clean; true → clean summary persists. Crosses
  config→capture end-to-end (real config file, real record run).
- SEAM 2 (redactor ↔ capture): the capture pass calls the shared redactor; the
  transmit pass (later slice) calls the SAME module. Assert the module is a pure
  reusable unit (no capture-specific coupling) so Slice C can reuse it.
- Residual risk: detector completeness is bounded (RFC-0013 Risks) — fail-closed
  drop + structured-by-default bound the blast radius; recorded, not automatable.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                   | Description                                                             | Status  |
|----------|------------|-------------|----------------------------------------|-------------------------------------------------------------------------|---------|
| TEST-101 | Spec-AC-01 | unit        | tests/skills/test-aai-friction.sh      | v1 record persists exactly 8 keys, byte-identical to the golden line     | green |
| TEST-102 | Spec-AC-01 | unit        | tests/skills/test-aai-friction.sh      | v2 record persists the 8 + valid structured fields; forged key dropped   | green |
| TEST-103 | Spec-AC-02 | unit        | tests/skills/test-aai-friction.sh      | invalid reproducible/impact/confidence/workaround → named-field reject    | green |
| TEST-104 | Spec-AC-03 | unit        | tests/skills/test-aai-friction.sh      | evidence_ref: doc path / AAI id accepted; URL / abs path / free → reject  | green |
| TEST-105 | Spec-AC-04 | integration | tests/skills/test-aai-friction.sh      | summary_enabled false → summary never persisted; true+clean → capture_clean | green |
| TEST-106 | Spec-AC-05 | unit        | tests/skills/test-aai-friction.sh      | each detector token in summary → dropped, capture_dropped_fields, record kept | green |
| TEST-107 | Spec-AC-06 | unit        | tests/skills/test-aai-friction.sh      | a structured field containing a detector-like string persists verbatim   | green |
| TEST-108 | Spec-AC-07 | unit        | tests/skills/test-aai-friction.sh      | static: no network/gh/token in aai-friction.mjs or aai-redact.mjs        | green |
| TEST-109 | Spec-AC-07 | integration | tests/skills/test-aai-friction.sh      | runtime under unroutable proxy → exit 0, line written                     | green |
| TEST-110 | Spec-AC-06 | unit        | tests/skills/test-aai-redact.sh (or friction) | redactor is a pure module: clean→ok, each poisoned class→!ok            | green |
| TEST-111 | Spec-AC-08 | integration | tests/skills/test-aai-layer-profiles.sh | 2 new .aai files classified once; layer-profiles green                   | green |

RED-proof: TEST-102..110 written first, observed FAILING against the v1-only
engine / absent redactor before GREEN. TEST-101 guards v1 backward-compat (must
stay green throughout — a regression there is a hard failure).

## Verification
- `bash tests/skills/test-aai-friction.sh` (extended; green; RED first for v2)
- `bash tests/skills/test-aai-layer-profiles.sh` green
- `node .aai/scripts/aai-friction.mjs --help` documents v2 + redaction
- `node .aai/scripts/docs-audit.mjs` CLEAN
- PASS: all TEST-xxx green AND all Spec-AC terminal (done + evidence)

## Evidence contract
Per artifact: ref_id friction-schema-v2-capture; Spec-AC + TEST links; command/scope;
exit code/verdict; evidence path (docs/ai/tdd/*.log); commit SHA when available.

Notes: This document defines HOW, not WHAT/WHY. It does not define workflow.

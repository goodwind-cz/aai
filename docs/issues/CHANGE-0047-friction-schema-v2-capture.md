---
id: friction-schema-v2-capture
number: 47
type: change
status: done
links:
  rfc: RFC-0013
  spec: null
  pr:
    - 146
  commits:
    - 49bb6fcc74080c1501c9609d85d0d38b87ad1eb2
---

# RFC-0013 Slice A — schema-v2 capture + hard redactor (capture pass)

## Summary
- First code slice of RFC-0013: extend the Phase-0 offline capture CLI to persist
  the **schema v2 structured signal fields** (D1) and add the **hard, fail-closed
  redactor** (D3 capture pass, D4) for the opt-in `summary` (D2), with the
  `evidence_ref` shape restriction (D5). Backward compatible: schema_version 1
  records behave exactly as today.
- This is the capture half of the double redaction; the transmit pass lives in the
  later upsert slice and REUSES the same single-sourced redactor module.

## Type
- change (feature — RFC-0013 capture implementation, privacy-critical)

## Motivation / Business Value
- Turns the minimal 8-field spool into a triage-capable record WITHOUT opening a
  free-text leak channel: the new fields are structured/enum/bool (leak-free by
  construction), and the only free-text (`summary`) is opt-in, default OFF, and
  hard-redacted with a fail-closed drop. This is the data foundation every later
  triage/upsert slice consumes.

## Scope
- In scope:
  - Extend `.aai/scripts/aai-friction.mjs`:
    - Accept `schema_version` ∈ {1, 2} (v1 unchanged; v2 enables the new persisted
      fields). Persist, for v2, the structured fields into the D6 allowlist:
      `reproducible` (bool), `impact` (low|medium|high), `confidence`
      (low|medium|high), `workaround` (none|manual|automatic), `evidence_ref`
      (shape-validated safe pointer: repo-relative doc path or AAI doc id only).
    - Expand the deny-by-default allowlist to exactly the v1 eight PLUS these
      structured v2 keys (still a fresh-object copy — no unlisted key persists).
    - `summary` (opt-in free-text, <=200 chars): persisted ONLY when
      `feedback.yaml` `capture.summary_enabled: true` (default false) AND the
      redactor certifies it clean; otherwise DROPPED (record persists without it).
    - Persist `redaction_status` enum: `none | capture_clean | capture_dropped_fields`.
    - Structured/enum/bool/`evidence_ref` fields BYPASS the redactor by
      construction (validated by type/enum/shape); only `summary` is redacted.
    - Fingerprint v1 unchanged (v2 fields do not alter clustering).
  - New shared module `.aai/scripts/lib/aai-redact.mjs` — the hard redactor
    (deny-by-default detectors: secret shapes, absolute paths, URLs, emails,
    hostnames, IPs, usernames, repo remotes, long digit runs → class tokens;
    fail-closed: if it cannot certify clean, signal DROP). Single-sourced for
    reuse by the later transmit pass.
  - `.aai/feedback.yaml` — minimal config carrying `capture.summary_enabled: false`
    (default). (Triage/upsert config comes in later slices.)
  - Update `.aai/system/FRICTION_PROTOCOL.md` schema section to v2 (fields,
    redaction status, the redactor contract), referencing RFC-0013 decisions.
  - Companion: classify the 2 new `.aai/**` files (aai-redact.mjs, feedback.yaml)
    in PROFILES.yaml; `.aai/system/*.md` growth is not corpus.
  - Tests: extend `tests/skills/test-aai-friction.sh` (or a new v2 suite) — v2
    persist, backward-compat v1, redactor fail-closed drop, structured bypass,
    summary opt-in default-off, evidence_ref shape rejection, still offline.
- Out of scope (later slices):
  - Triage over v2 records (Slice B), review-mode upsert + the transmit redaction
    pass (Slice C), auto-gate (Slice D), fix-PRs (Slice E).
  - Any network / GitHub / token (capture stays offline).

## Affected Area
- `.aai/scripts/aai-friction.mjs`, `.aai/scripts/lib/aai-redact.mjs` (new),
  `.aai/feedback.yaml` (new), `.aai/system/FRICTION_PROTOCOL.md`,
  `.aai/system/PROFILES.yaml`, `tests/skills/`.

## Desired Behavior (To-Be)
- A schema_version 2 record with valid structured fields persists them alongside
  the v1 eight; a v1 record is byte-unchanged from today.
- With `summary_enabled` false (default), a `summary` in the input is NEVER
  persisted. With it true, `summary` is persisted only if the redactor certifies
  it clean; a summary containing a secret/path/identity token is dropped (its
  class-redacted form is NOT persisted in the capture pass — drop, not keep) and
  `redaction_status` = capture_dropped_fields.
- `evidence_ref` failing the safe-pointer shape is rejected (validation error),
  never persisted as free text.
- Capture performs NO network I/O and holds no token (unchanged).

## Acceptance Criteria
- AC-001: schema_version ∈ {1,2}; a v1 record persists exactly the 8 fields
  (byte-identical to today); a v2 record additionally persists the valid
  structured fields; any input key outside the expanded allowlist is dropped.
- AC-002: `reproducible`/`impact`/`confidence`/`workaround` are type/enum-validated;
  an invalid value is rejected with a named field error.
- AC-003: `evidence_ref` accepts only a repo-relative doc path or AAI doc id
  (strict shape); a URL/absolute-path/free string is rejected.
- AC-004: with `summary_enabled` false (default), `summary` is never persisted;
  with it true, a clean summary persists (`redaction_status: capture_clean`).
- AC-005: a summary containing any detector token (secret/abs-path/url/email/
  host/ip/user/repo-remote/long-digit-run) is DROPPED (not persisted, not kept
  class-redacted in capture) and `redaction_status: capture_dropped_fields`; the
  structured record still persists.
- AC-006: structured/enum/bool/evidence_ref fields never pass through the redactor
  (they cannot carry free content) — asserted structurally.
- AC-007: capture still performs no network I/O / holds no token (static + runtime).
- AC-008: companion — 2 new `.aai/**` files classified in PROFILES.yaml;
  layer-profiles + (if corpus grew) prompt-diet green.

## Verification
- `bash tests/skills/test-aai-friction.sh` (extended; RED first for v2/redactor).
- `node .aai/scripts/aai-friction.mjs --help` documents v2 + redaction.
- `bash tests/skills/test-aai-layer-profiles.sh` green.
- `node .aai/scripts/docs-audit.mjs` CLEAN.

## Constraints / Risks
- PRIVACY-CRITICAL: the redactor is the trust boundary. Deny-by-default +
  fail-closed drop + structured-by-default (tiny free-text surface). RFC-0013 is
  the governing design; implementation-time security review applies (this slice).
- Backward compatibility with v1 is a hard invariant (a v1 record must be
  byte-identical to today) — assert it.
- No protected_paths_l3 surface (keep L2).

## Notes
- Redactor detector completeness is inherently bounded; the fail-closed drop +
  structured-by-default design keeps residual risk low (RFC-0013 Risks). Recorded.
- `evidence_ref` (single, shape-validated) supersedes Phase-0's tolerated
  `evidence_refs` array for persisted v2 records; v1 input handling is unchanged.

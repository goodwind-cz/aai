---
id: friction-record-v2-redaction
type: rfc
number: 13
status: implementing
links:
  spec: null
  rfc: RFC-0012
  pr: []
  commits: []
---

# RFC — Friction observation schema v2 + redaction policy (unblocks RFC-0012 Phase 2)

## Context

RFC-0012 Phase 0/1 ship an OFFLINE friction capture: a skill records an observation
to a local spool `docs/ai/friction/observations.jsonl`. Per decision D6, the
persisted record contains EXACTLY eight structural fields and NOTHING else:
`schema_version, os_family, aai_pin, node_major, skill_id, skill_phase,
failure_class, fingerprint`. No free-text prose (`expected_behavior`,
`observed_behavior`, `reproduction`, `workaround`, `impact`, ...) is persisted —
Phase 0 explicitly deferred that: *"Later phases that persist or transmit richer
records must apply the redaction status and the hard/double-redaction rules
(RFC-0012 D5) before any external write."*

RFC-0012 Phase 2 triage is meant to gate on **actionability**, **reproducibility**,
and score by **impact/confidence/recurrence**, then (Phase 2c+) prepare an upstream
issue. NONE of those signals — except recurrence (derivable from fingerprint
counts) — exist in the v1 minimal spool. So Phase 2's triage intelligence, the
review-mode upsert, the auto-gate (D8), and fix-PR scaffolding are ALL blocked on
a richer record. This RFC specifies that richer record (schema v2) and the D5
redaction policy that makes persisting/transmitting it privacy-safe.

### The reframing insight

You do NOT need to persist free-text prose to triage well. Almost all triage
signal is **structured**: reproducibility is a boolean, impact and confidence are
small enums, recurrence is a count. Structured/enum fields leak nothing by
construction — there is no free-text channel for a secret, a path, a hostname, or
proprietary code to ride out on. This RFC therefore proposes a schema v2 that is
still **prose-free by default**, adding only enum/boolean/int signal fields, and
treats any free-text as an opt-in, hard-redacted, double-checked exception.

## Proposal

### 1. Schema v2 — structured signal, no free-text by default

Add to the persisted record (all OPTIONAL, absent → treated as unknown; the v1
eight fields are unchanged, `schema_version` becomes `2`):

- `reproducible` — boolean. Did the reporter reproduce it deterministically?
- `impact` — enum `low | medium | high`. Blast radius of the friction.
- `confidence` — enum `low | medium | high`. Reporter's confidence it is AAI-owned.
- `workaround` — enum `none | manual | automatic`. Cost of the current workaround.
- `evidence_ref` — a SAFE pointer only: a repo-relative doc path or an AAI doc id
  (e.g. `SPEC-0079`, `docs/ai/tdd/...`), validated against a strict shape; never
  a URL, absolute path, or free string.

These carry the RFC-0012 triage gates (`reproducible` OR recurrence) and scoring
(`impact`, `confidence`, `workaround`, recurrence) with ZERO free-text.

### 2. Optional short summary (opt-in, hard-redacted)

For the eventual human-readable issue title, ONE optional field:

- `summary` — a short (<= 200 char) one-line human summary, PERSISTED ONLY when
  redaction can prove it carries no forbidden token; otherwise dropped (fail
  closed, the record persists WITHOUT it). Off unless `feedback.yaml` opts in.

If `summary` is omitted (the default), the eventual issue title is TEMPLATED from
structured fields: `[<failure_class>] <skill_id>/<skill_phase> (<impact> impact)`
plus the fingerprint — no free-text at all.

### 3. Redaction policy (D5 elaboration) — hard + double

- **Hard redaction (fail-closed).** Redaction is deny-by-default: a fixed
  detector set (high-entropy/secret shapes, absolute paths, URLs, emails,
  hostnames, IPs, usernames, repo remotes, long digit runs) scans any free-text
  (`summary`). A match is REPLACED with a class token (`<redacted:secret>`,
  `<redacted:path>`, ...). If, after replacement, the detector cannot certify the
  string clean (e.g. residual high-entropy), the field is DROPPED, not persisted
  — the record still lands without it. There is no "redact best-effort and keep".
- **Double redaction.** Redaction runs (a) at CAPTURE, before the local spool
  write, and (b) again at TRANSMIT, before any external write (Phase 2c). The
  second pass is not trust in the first — schema, tooling, or policy may have
  changed between capture and transmit.
- **`redaction_status`** — a persisted enum recording which passes ran and
  whether any field was dropped: `capture_clean | capture_dropped_fields |
  none`. Transmit adds `transmit_clean | transmit_blocked` at send time.
- **Structured fields need no redaction** — enums/booleans/ints/`evidence_ref`
  (shape-validated) cannot carry free content, so they bypass the detector by
  construction. Redaction applies ONLY to `summary`.

### 4. Scope guards

- Schema v2 is BACKWARD COMPATIBLE: `schema_version` 1 records remain valid;
  triage treats missing v2 fields as unknown (recurrence-only signal).
- Capture stays OFFLINE and best-effort; adding v2 fields never makes capture
  fail a skill.
- This RFC is DESIGN ONLY — it specifies the record + redaction contract that a
  later implementation slice (schema-v2 capture + triage over it) will build.

## Alternatives considered

- **Persist full free-text prose + redact.** Rejected as default: a free-text
  channel is the exact exfiltration surface Phase 0 closed; even redacted, it is
  the highest-risk path. Kept only as the opt-in `summary` exception with
  fail-closed hard redaction.
- **Stay prose-free forever (v1 only).** Rejected: recurrence alone cannot score
  impact/confidence/actionability; triage would be near-blind. The enum fields are
  the minimal addition that restores triage signal without a free-text channel.
- **Redact only at transmit.** Rejected: a plaintext secret sitting in the local
  spool is already a leak (backups, shared machines). Capture-time redaction is
  the first of the double pass.

## Consequences

- Unblocks RFC-0012 Phase 2 (triage over structured signal), 2c (upsert of a
  templated, redaction-certified issue), 4 (auto-gate over real acceptance), 5.
- Privacy posture stays "structural exclusion first": the default record is still
  prose-free; the only free-text is opt-in and fail-closed.
- Adds a small redaction module + detector set that both capture and transmit
  share (single-sourced, skill-suite-enforced).

## Rollout Status

Human-maintained delivery roadmap. The AUTOMATIC per-child-doc rollup (done/total
of docs linking `rfc: RFC-0013`) is surfaced by `node .aai/scripts/docs-audit.mjs`
(`- Rollout:` / `### Rollout progress`). Note: only the schema-v2-capture pair
links back to this RFC; the redactor it introduced is REUSED (not re-linked) by the
triage/upsert slices, which link RFC-0012.

| Proposal | Status | Delivered by |
|----------|--------|--------------|
| Schema v2 (structured signal, prose-free default) | done | CHANGE-0047/SPEC-0080 (schema-v2 capture) |
| Hard redactor (allow-list charset + deny-list detectors) | done | `.aai/scripts/lib/aai-redact.mjs` (Slice A) |
| Double redaction (capture + transmit reuse) | done | capture in `aai-friction.mjs`; transmit in `aai-feedback-upsert.mjs` (CHANGE-0049) |
| Opt-in short summary (fail-closed, default off) | done | CHANGE-0047 (`feedback.yaml capture.summary_enabled`) |

## Risks

- Detector completeness: a hard redactor can only catch known shapes. Mitigation:
  fail-closed (drop on uncertainty) + structured-by-default (tiny free-text
  surface) + double pass. Residual risk explicitly accepted and documented.
- Enum gaming: a reporter could mis-set `impact: high`. Mitigation: `confidence`
  + recurrence corroboration; auto-gate (D8) still requires human acceptance rate.

## Open Questions (decide before freeze)

- OQ1 — Richer fields: adopt the structured/enum set (`reproducible`, `impact`,
  `confidence`, `workaround`, `evidence_ref`)? [recommend: yes]
- OQ2 — Free-text `summary`: (A) NO free-text ever, issue title templated from
  structured fields; (B) opt-in short `summary` with fail-closed hard redaction,
  default OFF. [recommend: B — capability exists but off by default]
- OQ3 — Redaction timing: double (capture + transmit)? [recommend: yes]
- OQ4 — Fail mode on uncertain redaction: DROP the field and persist the rest
  (fail-closed), vs DROP the whole record? [recommend: drop the field, keep the
  structured record — the signal is still useful]
- OQ5 — `evidence_ref`: restrict to repo-relative doc paths + AAI doc ids only
  (no URLs/abs paths)? [recommend: yes]

## Decisions (resolved 2026-07-25, project owner)

- **D1 (OQ1) — Adopt the full structured signal set.** Schema v2 adds
  `reproducible` (bool), `impact` (low|medium|high), `confidence` (low|medium|high),
  `workaround` (none|manual|automatic), and `evidence_ref` (safe pointer) to the
  persisted record. All optional; `schema_version` becomes `2`; v1 records stay
  valid. These are the triage gates + scoring inputs, all leak-free by construction.
- **D2 (OQ2) — Free-text `summary` is an opt-in, default-OFF capability.** The
  default record is prose-free; the eventual issue title is templated from
  structured fields (`[<failure_class>] <skill_id>/<skill_phase> (<impact> impact)`
  + fingerprint). A short (<=200 char) `summary` may be enabled via
  `feedback.yaml`; when enabled it passes hard redaction before persist.
- **D3 (OQ3) — Double redaction.** Redaction runs at CAPTURE (before local spool
  write) AND again at TRANSMIT (before any external write). The transmit pass does
  not trust the capture pass. `redaction_status` records which passes ran.
- **D4 (OQ4) — Fail closed by DROPPING THE FIELD, keeping the record.** If
  redaction cannot certify a free-text field clean, that field is dropped and the
  structured record persists without it (`redaction_status: capture_dropped_fields`).
  The structured signal remains useful; no uncertain free-text is ever stored.
- **D5 (OQ5) — `evidence_ref` is a shape-restricted safe pointer only.** Allowed:
  a repo-relative doc path or an AAI doc id (e.g. `SPEC-0079`, `docs/ai/tdd/...`)
  matching a strict pattern. Rejected: URLs, absolute paths, any free string.
  Structured/enum/bool fields bypass the redactor by construction — redaction
  applies ONLY to `summary`.

These decisions are binding inputs to the RFC-0012 Phase 2 implementation specs
(schema-v2 capture, then triage over it, then review-mode upsert). This RFC is
DESIGN ONLY — no code is written under this RFC; the security/privacy posture it
defines is the owner's approval of the redaction contract.

## Approvals

- Project owner: **approved 2026-07-25** (ales@holubec.net) — decisions D1-D5 above.
- Security/privacy: satisfied by owner sign-off — this RFC IS the privacy design;
  implementation-time review still applies when the schema-v2 capture + redactor
  land (a code slice, not this design).

## Notes

- Parent: RFC-0012 (this RFC elaborates its D5 and unblocks Phase 2+). On accept,
  RFC-0012 Phase 2 specs consume schema v2 as a binding input.
- A parked offline-triage slice (dedup + fingerprint clustering + recurrence
  ranking over the v1 spool) can proceed independently and be upgraded to v2
  signal once this lands.

---
id: docs-ai-canon
number: null
type: change
status: implementing
user_visible: true
ceremony_level: 1
links:
  pr: []
  commits: []
---

# Change — docs/ai gets a canon registry: invented dirs are detected, not found by hand

Ceremony justification: L1 — one report-only WARN class in an existing audit
engine plus a vendored list file. No new gate, no exit-code change, no
protected-surface edit; a single suite covers it.

## Summary
- Downstream agents invented TWO ad-hoc directories under `docs/ai/` in two
  days: `docs/ai/validation/` (a Validation role's run output — since
  canonicalized as CHANGE-0118) and `docs/ai/hitl/` (NOT canonical: HITL
  decisions belong in `docs/decisions/DECISION-*.md` per SKILL_HITL step 4a,
  and channel state is `docs/ai/hitl-channel.json`).
- Both leaked as untracked noise / mislocated evidence, and both were found
  only by the operator, by hand. Prose in prompts did not prevent either.
- Fix: a vendored canon registry `.aai/system/DOCS_AI_CANON.list` naming the
  allowed DIRECT children of `docs/ai/`, a project-owned extension key
  `docs_ai_canon_extra:` in `docs/ai/docs-audit.yaml`, and a report-only
  docs-audit class `docs_ai_noncanon` that enumerates the real directory and
  names anything unregistered with a deterministic remediation hint.

## Motivation / Business Value
- Owner directive: (1) it stops happening, (2) docs-audit surfaces the strays
  so they can be straightened. Deterministic detection is the prevention —
  prose does not fire.

## Scope
- In scope: `.aai/system/DOCS_AI_CANON.list` (new, core profile);
  `docs_ai_canon_extra` in the docs-audit config reader; the
  `docs_ai_noncanon` detection + report shape in
  `.aai/scripts/lib/docs-audit-core.mjs` and `.aai/scripts/docs-audit.mjs`;
  TEST-U02 in `tests/skills/test-aai-docs-audit.sh`; USER_GUIDE +
  live-config documentation; PROFILES/suite-map classification.
- Out of scope: an enforcement dial that escalates the class beyond WARN (see
  Notes); moving any existing stray file; changing the runtime-ignore set.

## Desired Behavior (To-Be)
- Every direct child of `docs/ai/` is either in the vendored canon, in the
  project's `docs_ai_canon_extra`, or reported.
- The report is a summary line `- docs/ai non-canonical: N (<names>)` plus a
  detail table with one shape-derived hint per entry. Both appear ONLY when
  N > 0, so a clean repo's digest is byte-identical to before.
- Detection is pure `fs` — it works under `--quick` (no git, no EVENTS).
- The class is WARN: it never feeds `hardFail` or the NEEDS-TRIAGE tally and
  never changes an exit code.

## Acceptance Criteria
- AC-001: `.aai/system/DOCS_AI_CANON.list` exists, is line-based with `#`
  comments, and covers the AAI repo's real `docs/ai` inventory (including
  `tests`); it is classified in `.aai/system/PROFILES.yaml` (core).
- AC-002: a rogue `hitl` dir and a rogue `scratch.md` are both named in the
  summary line, listed in the detail section, and the `hitl` entry carries the
  HITL-specific hint; the canonical `tdd/` sibling is not flagged.
- AC-003: `docs_ai_canon_extra: [scratch.md]` in `docs/ai/docs-audit.yaml`
  removes exactly that entry from the finding set; a malformed or absent value
  yields the empty list (fail-safe = stricter).
- AC-004: the verdict stays CLEAN and `--check` still exits 0 with findings
  present (report-only pinned).
- AC-005: a canonical-only `docs/ai` (and a repo with no canon list at all)
  emits no new line anywhere in the digest.
- AC-006: `--quick` detects the same findings as a full run.
- AC-007: the real AAI repo audits clean under the new class.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` (TEST-U02 added; RED first).
- `bash tests/skills/test-aai-layer-profiles.sh` (new .aai file classified).
- `bash tests/skills/test-aai-hygiene-pack.sh`, release TEST-022.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` — CLEAN.

## Constraints / Risks
- Ceremony L1, strategy direct (no separate spec).
- An absent canon list disables the class entirely: judging a repo that never
  synced the inventory would flag every child of `docs/ai/` at once. Silence
  is the only safe reading of "no canon".
- Exact names only — no glob/dot-tempfile escape hatch. A temp or aside file
  has no canonical home under `docs/ai/`; it belongs outside the governed tree.

## Notes
- FUTURE DIAL (deliberately NOT built here): the class could be escalated from
  WARN to a `--check` failure via a `docs_ai_canon_gate: enforce` key mirroring
  `close_gate`/`body_lint`. Landing detection first lets the signal prove
  itself clean across downstreams before anything blocks on it.
- Incidents cited: CHANGE-0118 (`docs/ai/validation/`, 2026-08-03) and the
  operator-found `docs/ai/hitl/` (2026-08-03).

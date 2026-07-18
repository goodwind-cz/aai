---
id: spec-lint-enforce-spec-id-prefix
type: issue
number: 16
status: done
links:
  pr:
    - 111
  commits:
    - 0940309
---

# Issue: spec-lint should flag a spec whose id is a collision-prone bare slug

## Summary
- spec-lint does not check the shape of a spec's frontmatter `id`. A spec
  created with a bare-slug id (neither the numbered `SPEC-NNNN` form nor a
  `spec-`-prefixed slug) collides with its change doc's id — the root cause of
  the 4 spec-id collisions found this session (SPEC-0056 + SPEC-0048/0049/0051).
  Add a spec-lint finding so this is caught at spec-freeze, the earliest point.

## Root Cause
- Planning names a spec DRAFT slug; nothing enforces that a spec's id is
  disambiguated from its change's id. The SPEC-0057 detector catches the
  collision at audit time and close-work-item.mjs fail-closes at close time —
  both LATE. spec-lint runs per-spec at freeze, so it can prevent it.

## Current Cost / Risk
- A collision-prone id ships and only surfaces later (NEEDS-TRIAGE, or a
  fail-closed close). Preventing it at freeze is defence-in-depth at the source.

## Steps to Reproduce
- A spec with frontmatter `id: <bare-slug>` (e.g. `secrets-preflight-env-multiline`);
  `node .aai/scripts/spec-lint.mjs --path <that spec>` → currently no finding.

## Expected vs Actual
- Expected: spec-lint emits a `spec-id-shape` finding when a spec's `id` is a
  bare slug — i.e. it is NOT the numbered `SPEC-NNNN` form AND does NOT start
  with `spec-`. Guidance: use `spec-<change-slug>`.
- Actual: no id-shape check; a bare-slug spec id lints clean.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: spec-lint flags a spec whose `id` is a bare slug (not `/^SPEC-\d+$/i` and not `spec-`-prefixed) with a `spec-id-shape` finding naming the id + the `spec-<slug>` guidance; exit 1. (Spec: SPEC-0058-spec-spec-lint-enforce-spec-id-prefix Spec-AC-01) | pending | |
| AC-002: no false positives — a `spec-`-prefixed id and the legacy numbered `SPEC-NNNN` id both lint clean; running spec-lint over EVERY current `docs/specs/SPEC-*.md` yields zero `spec-id-shape` findings (the corpus is clean post-remediation); only `type: spec` docs are checked; existing spec-lint suite green. (Spec: Spec-AC-02 + Spec-AC-03) | pending | |

Ceremony justification: additive per-spec lint check in one script (spec-lint.mjs)
+ regression stanzas; no engine/protected-path change (L1).

## Verification
- New stanzas in `tests/skills/test-aai-spec-lint.sh`: bare-slug fixture (flagged,
  exit 1) + `spec-`-prefixed and numbered `SPEC-NNNN` negative controls (clean);
  a loop over all real `docs/specs/SPEC-*.md` asserts zero `spec-id-shape`.

## Constraints / Risks
- Deterministic; the numbered-`SPEC-NNNN` legacy convention MUST be excluded
  (those never collide with change ids). Advisory-consistent with spec-lint's
  existing findings.

## Notes
- Source: the spec-id collision cascade (ISSUE-0015 remediation + SPEC-0057
  detector + close-work-item fail-closed); decisions.jsonl process_findings
  (2026-07-18). Earliest-point prevention completing the duplicate-id
  defence-in-depth (detect at audit + fail-closed at close + lint at freeze).

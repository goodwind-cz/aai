---
id: secrets-preflight-env-multiline
type: issue
number: 10
status: draft
links:
  pr: []
  commits: []
---

# Issue: secrets-preflight `.env` first-match line-scan misreads multiline values

## Summary
- `.aai/scripts/secrets-preflight.mjs` classifies `.env` keys with a naive
  first-match line scan. A `KEY=`-shaped tail line inside a quoted multiline
  value is misread as a fresh assignment, so an actually-empty secret is
  reported `exists` (false confidence, the dangerous direction).

## Root Cause
- The `.env` reader matches the first `^<KEY>=` line rather than parsing the
  file's quoting: a value like `CERT="-----BEGIN...\nSOMEKEY=...\n-----END..."`
  spanning lines lets an inner `SOMEKEY=`/`KEY=` fragment satisfy a later
  lookup, and a quoted-but-empty value's continuation is not tracked.

## Current Cost / Risk
- Report-only preflight, but the failure mode is precision-losing in the unsafe
  direction: a missing/empty credential can read as present, defeating the
  point of the check. Found in CHANGE-0034 code review (review-20260717T152035Z
  NB-1), dispositioned as a follow-up; the never-echo guarantee is unaffected.

## Steps to Reproduce
- A `.env` with a quoted multiline value whose interior contains a `KEY=`-shaped
  line, then `secrets-preflight.mjs --file <that>.env --key <interior-key>` (or a
  key whose real value is empty but whose multiline neighbour looks assigned).

## Expected vs Actual
- Expected: quoting-aware parse — empty/quoted-empty → `empty`; interior lines
  of a multiline value are never treated as assignments.
- Actual: interior `KEY=` fragment satisfies the lookup → `exists`.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: `.env` parse is quoting-aware — a quoted multiline value's interior lines are not read as assignments; a genuinely empty (incl. quoted-empty `""`) value classifies `empty`, never `exists`. | pending | |
| AC-002: never-echo property preserved on every new path (interior/malformed lines never emit value bytes); existing secrets-preflight suite stays green. | pending | |

Ceremony justification: single-surface correctness fix to one helper's `.env`
parser + regression stanzas; no engine/protected-path change (L1).

## Verification
- New stanzas in `tests/skills/test-aai-secrets-preflight.sh` covering the
  multiline-interior and quoted-empty cases; `bash` suite exit 0; never-echo
  sentinel grep clean.

## Notes
- Source: docs/ai/reviews/review-20260717T152035Z.md NB-1; decisions.jsonl
  disposition (CHANGE-0034, 2026-07-17).

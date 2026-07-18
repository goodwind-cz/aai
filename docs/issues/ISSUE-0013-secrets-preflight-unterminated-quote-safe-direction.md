---
id: secrets-preflight-unterminated-quote-safe-direction
type: issue
number: 13
status: done
links:
  pr:
    - 108
  commits:
    - 2d9a40f
---

# Issue: secrets-preflight unterminated-quote value should classify toward missing, not exists

## Summary
- In `.aai/scripts/secrets-preflight.mjs`, a `.env` value that opens a quote
  never properly closed (consumed to EOF, or "closed" by a stray/escaped quote
  on a later line) is currently classified from whatever interior text was
  accumulated — which can report `exists` for a genuinely malformed/ambiguous
  value. The safe direction for a secrets existence check is to classify an
  ambiguously-unterminated value toward `missing` (or `empty`), never a false
  `exists`.

## Root Cause
- `consumeQuotedValue` returns the accumulated value up to the matching close
  or EOF-if-never-closed (SPEC-0049 RR-2, explicitly accepted as a limitation
  at the time). The caller then classifies that value by length, so an
  unterminated quote whose interior happens to be non-empty reads `exists`.
  There is no signal that the value was never legitimately terminated.

## Current Cost / Risk
- Report-only preflight, and never a value LEAK — but the failure direction is
  the unsafe one: a malformed multiline value can read as a present secret
  (`exists`) when its termination is ambiguous, giving false confidence that a
  credential is set. The reviewer (CHANGE-0034 review NB / ISSUE-0010 RR-2)
  flagged this as the follow-up hardening: prefer `missing` on ambiguity.

## Steps to Reproduce
- A `.env` where a target key opens a quote that is never closed before EOF (or
  is only "closed" by an unrelated later quote), with non-empty interior text;
  `secrets-preflight.mjs --file <that>.env --key <that-key>` currently → `exists`.

## Expected vs Actual
- Expected: an unterminated / ambiguously-closed quoted value classifies
  `missing` (ambiguity resolves to the safe direction — do not claim a present
  secret). A well-formed quoted value (properly closed, incl. quoted-empty) is
  unchanged.
- Actual: it can classify `exists` from the accumulated interior.

## Acceptance Criteria
| AC | Status | Evidence |
|---|---|---|
| AC-001: a target key whose quoted value is never properly terminated (consumed to EOF without a real matching close) classifies `missing`, never `exists` — the ambiguity resolves to the safe direction. `consumeQuotedValue` reports the unterminated condition so the classifier can act on it. | pending | |
| AC-002: no regression — properly-closed quoted values (single-line, multiline, quoted-empty `""`/`''`) and the interior-masking of OTHER keys (SPEC-0049) are unchanged; never-echo invariant preserved; existing secrets-preflight suite green with zero assertion edits. | pending | |

Ceremony justification: single-surface safe-direction correctness fix to one
helper's quote handling + regression stanzas; no engine/protected-path change (L1).

## Verification
- New stanzas in `tests/skills/test-aai-secrets-preflight.sh`: an
  unterminated-quote fixture (interior non-empty → `missing`) + a stray-later-quote
  fixture + negative controls (properly-closed multiline, quoted-empty) unchanged;
  never-echo sentinel grep clean; `bash` suite exit 0.

## Notes
- Source: docs/ai/reviews/review-20260717T201256Z.md NB (RR-2); decisions.jsonl
  disposition (ISSUE-0010, 2026-07-17). Completes the ISSUE-0010 `.env` parser
  hardening (multiline-interior masking shipped in SPEC-0049; this is the
  unterminated-quote safe-direction follow-up).

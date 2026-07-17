---
id: secrets-preflight-env-multiline
type: spec
number: 49
status: done
ceremony_level: 1
links:
  requirement: ISSUE-0010
  rfc: null
  pr:
    - 101
  commits:
    - 3449c57
---

# Spec: secrets-preflight `.env` parser becomes quoting-aware (multiline fidelity)

SPEC-FROZEN: true

Ceremony justification: single-surface correctness fix to one helper's `.env`
parser (`classifyEnvFileKey` in `.aai/scripts/secrets-preflight.mjs`) plus
regression stanzas in its own test suite. No engine, allocator, guard, or
workflow-canon change; `.aai/scripts/secrets-preflight.mjs` is NOT in
`protected_paths_l3`. Reversible, single reviewable surface -> Level 1. The
helper is security-class, so the L1 lane's Validation MUST adversarially
re-check the never-echo invariant on the new parser paths (dispatch mandate).

Reserved display number (cross-branch collision check, CHANGE-0035/SPEC-0047):
SPEC-0049. Verified 2026-07-17 free across `origin/*` trees and
`refs/aai/docnums/*` (highest reserved anywhere is SPEC-0048). The number is
minted/reserved at merge by `allocate-doc-number.mjs`; this file stays
`SPEC-DRAFT-<slug>.md` with `number: null` in-branch.

## Links
- Requirement: docs/issues/ISSUE-0010-secrets-preflight-env-multiline.md
- Origin finding: docs/ai/reviews/review-20260717T152035Z.md (NB-1)
- Shipped-by: docs/issues/CHANGE-0034-intake-secrets-preflight.md / docs/specs/SPEC-0045-spec-intake-secrets-preflight.md
- Decision record: docs/ai/decisions.jsonl (CHANGE-0034 NB-1 promote-to-follow-up, 2026-07-17)
- Technology contract: docs/TECHNOLOGY.md

## Problem

`classifyEnvFileKey` (`.aai/scripts/secrets-preflight.mjs:200-220`) scans the
`.env` text line-by-line and returns the first line matching `^KEY=` or
`^export KEY=` (first match wins). It has no notion of quoting, so a `KEY=`-
shaped line that is actually INTERIOR to a quoted multiline value (e.g. a
`SOMEKEY=` fragment inside a `CERT="-----BEGIN...-----END"` PEM block) is
misread as a fresh top-level assignment. Consequences:

1. An interior `KEY=`-shaped fragment satisfies a lookup for that key even
   though no such top-level assignment exists -> false `exists` for a key that
   is genuinely `missing`.
2. When a real, empty assignment appears AFTER a multiline block whose interior
   shadows the same key name, the interior fragment wins (first match) ->
   false `exists` for a key that is genuinely `empty`.

Both fail in the DANGEROUS direction (a missing/empty credential reads as
present, defeating the preflight). The never-echo guarantee is NOT implicated
by the current bug (misclassification only, no value bytes emitted) and MUST
remain intact across the fix.

## Scope
- In scope: the `.env` parsing path of `.aai/scripts/secrets-preflight.mjs`
  (`classifyEnvFileKey`, and any small helper it needs) and new regression
  stanzas in `tests/skills/test-aai-secrets-preflight.sh`.
- Out of scope: the CLI grammar, argument parsing, JSON path, env-var path,
  exit contract, stderr note strings, the intake wiring/canon blocks, and the
  leading-whitespace-rejects behavior (` KEY=` -> `missing`, accepted safe
  direction per the origin review). YAML support remains out of scope.
- Protected paths touched: none.

## Parsing contract (the fix — quoting-aware `.env` scan)

The `.env` scan MUST become quoting-aware while preserving every currently-
passing classification. Contract:

1. Lines are scanned top to bottom. A candidate top-level assignment matches
   `^KEY=(rest)` or `^export\s+KEY=(rest)` for the requested KEY (anchored at
   column 0 exactly as today — leading-whitespace lines are NOT assignments).
2. When a genuine top-level assignment's value (`rest`) BEGINS with a quote
   char (`"` or `'`) that is not closed by a matching quote later on the SAME
   physical line, the value is quoted-multiline: subsequent physical lines are
   CONSUMED as value continuation up to and including the line bearing the
   matching closing quote char (or EOF if never closed). Consumed continuation
   lines are NEVER treated as new top-level assignments — their `KEY=`-shaped
   interior fragments do not satisfy any lookup.
3. First genuine top-level assignment of the requested KEY wins (top to
   bottom), unchanged.
4. One pair of matching surrounding quotes is stripped before the length test
   (unchanged rule), now applied to the full — possibly multiline — value.
5. Classification: no genuine assignment found -> `missing`; stripped value of
   length 0 -> `empty`; else `exists`. Quoted-empty (`KEY=""` / `KEY=''`) ->
   `empty`.
6. NEVER-ECHO INVARIANT (unchanged, D4): no value byte is interpolated into
   stdout, stderr, a note, or an exception on ANY path — including interior,
   continuation, unterminated-quote, and malformed lines. Values are only ever
   tested for presence and `.length`.

Backward compatibility (Constitution Art. 5, additive): a single-line quoted
value closes its quote on the same line, so no continuation is consumed and
every existing TEST-001..006 classification is byte-identical. The output
contract (`env:`/`file:` lines, three-status closed set) is unchanged — this
is a fidelity fix, not a boundary change.

## Implementation strategy
- Strategy: tdd
- Rationale: a correctness bug fix in a security-class helper that needs
  regression proof, failing in the dangerous direction. TDD RED-GREEN-REFACTOR
  is required so the multiline-interior misclassification is observed FAILING
  against the current first-match parser before the fix counts as evidence
  (RED-proof), and the never-echo invariant is re-asserted on the new paths.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single helper + its own test suite, small, reversible,
  no protected path. STATE already records `worktree.user_decision: inline`,
  `base_ref: main`, on the current branch `fix/secrets-preflight-env-multiline`
  (operator-approved wave). No user decision required.
- User decision: inline (already recorded)
- Base ref: main
- Worktree branch/path: fix/secrets-preflight-env-multiline (inline)
- Inline review scope: `.aai/scripts/secrets-preflight.mjs`,
  `tests/skills/test-aai-secrets-preflight.sh`,
  `docs/specs/SPEC-0049-secrets-preflight-env-multiline.md`

## Acceptance Criteria Mapping

- Requirement ISSUE-0010 AC-001 (quoting-aware parse; interior lines are not
  assignments; empty incl. quoted-empty -> `empty`, never `exists`)
  -> Spec-AC-01 + Spec-AC-02.
- Requirement ISSUE-0010 AC-002 (never-echo preserved on every new path;
  existing suite stays green) -> Spec-AC-03.

- Maps to: ISSUE-0010 AC-001
- Spec-AC-01: A quoted multiline value's interior `KEY=`-shaped lines are never
  read as top-level assignments. A key that appears ONLY as an interior
  fragment classifies `missing`; a real assignment appearing after the
  multiline block is still found; the multiline key itself (non-empty content)
  classifies `exists`. Both `"..."` and `'...'` multiline forms are handled.
  - Verification: `bash tests/skills/test-aai-secrets-preflight.sh test_007_multiline_quoting_aware`
    -> exit 0. RED-proof: same test observed FAILING (interior/shadowed key
    reports `exists`) against current `.aai/scripts/secrets-preflight.mjs`
    before the fix; RED log under `docs/ai/tdd/`.

- Maps to: ISSUE-0010 AC-001
- Spec-AC-02: A genuinely empty value classifies `empty`, never `exists`:
  `KEY=`, quoted-empty `KEY=""` and `KEY=''`, and a real empty assignment that
  is shadowed by an earlier multiline block's interior `KEY=`-shaped fragment
  all classify `empty`.
  - Verification: `bash tests/skills/test-aai-secrets-preflight.sh test_008_empty_and_quoted_empty`
    -> exit 0. RED-proof: the `KEY=''` and multiline-shadowed-empty arms
    observed FAILING (report `exists`) against current parser before the fix.

- Maps to: ISSUE-0010 AC-002
- Spec-AC-03: The never-echo invariant holds on every NEW parser path — a
  sentinel planted inside a quoted multiline value's interior line and inside
  an unterminated-quote value never appears in combined stdout+stderr for any
  invocation shape (query the multiline key, the interior key, a later key, the
  malformed/unterminated fixture); every such run exits 0. The pre-existing
  suite (TEST-001..006) stays green.
  - Verification: `bash tests/skills/test-aai-secrets-preflight.sh test_009_never_echo_multiline`
    -> exit 0, sentinel grep clean; AND full-suite
    `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-secrets-preflight.sh`
    -> exit 0 (TEST-001..006 unchanged and green).

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable AC + TEST-xxx, no PASS claim in
  planning. Art.2 KISS/YAGNI: minimal parser change, CLI untouched. Art.3
  portability: plain .mjs, git-diffable. Art.4 degrade-and-report: unreadable
  -> missing + fixed note, preserved. Art.5 additive: output contract and all
  existing classifications unchanged (fidelity fix). Art.6 single-writer:
  STATE via state.mjs only. Art.7 operator-only merge: planning does not
  merge. -->

## Seam analysis

No cross-feature seam requiring an integration test. `classifyEnvFileKey` is a
private helper consumed only by this CLI; its output contract (`file:<path>#
<key> <status>`, three-status closed set) is unchanged, so the intake wiring
that reads a status token is unaffected by the fidelity change. No shared DB
row, no multi-writer, no downstream projection of `.env` interior structure.
- Residual risk RR-1 (pre-existing, unaffected): whether a live intake agent
  invokes the helper vs echoing a value is LLM behavior (SPEC-0045 R1 /
  cannot_verify), out of code scope and not changed here.
- Residual risk RR-2 (accepted, minimal scope): a value that legitimately
  contains the SAME quote char as an ESCAPED interior character (`\"`) is
  outside the motivating PEM/token case (PEM interiors contain no quote chars);
  the closing quote is the next occurrence of the opening quote char. Recorded
  as a known limitation, not covered by an automated test; never a leak
  (never-echo invariant holds regardless).

## Acceptance Criteria Status

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Quoting-aware: interior `KEY=` lines are not top-level assignments          | done    | TEST-007 green; RED docs/ai/tdd/red-20260717T195518Z-secrets-preflight-env-multiline-test007-008.log; GREEN docs/ai/tdd/green-20260717T200002Z-secrets-preflight-env-multiline-test007-010.log | — | — |
| Spec-AC-02 | Empty & quoted-empty (`""`/`''`) & multiline-shadowed-empty classify `empty`| done    | TEST-008 green; RED docs/ai/tdd/red-20260717T195518Z-secrets-preflight-env-multiline-test007-008.log; GREEN docs/ai/tdd/green-20260717T200002Z-secrets-preflight-env-multiline-test007-010.log | — | — |
| Spec-AC-03 | Never-echo invariant holds on all new paths; existing suite stays green     | done    | TEST-009/TEST-010 green; full-suite (TEST-001..010) exit 0 + adversarial isolated-fixture sentinel grep = 0; docs/ai/tdd/green-20260717T200002Z-secrets-preflight-env-multiline-test007-010.log | — | — |

## Implementation plan
- Components/modules affected: `.aai/scripts/secrets-preflight.mjs` —
  `classifyEnvFileKey` only (plus a small line-consuming helper if useful). No
  other function, no CLI/grammar/exit change.
- Data flow: `loadFile` already returns `{ ok, format:'env', raw }`;
  `classifyFileCheck` calls `classifyEnvFileKey(raw, key)`. Only the internal
  scan of `raw` changes.
- Edge cases: single-line quoted value (no continuation — must stay identical);
  unterminated quote to EOF (consume to EOF, classify by length, never echo);
  interior fragment with no real later assignment (-> missing); real assignment
  after a multiline block (-> found); `'`-quoted multiline; `KEY=''` (-> empty);
  CRLF (existing `\r?\n` split preserved); regex-special key names (existing
  `escapeRegExp` preserved).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                          | Description                                                                                                   | Status  |
|----------|------------|------|-----------------------------------------------|---------------------------------------------------------------------------------------------------------------|---------|
| TEST-007 | Spec-AC-01 | unit | tests/skills/test-aai-secrets-preflight.sh    | Quoted multiline value's interior `KEY=` lines are not assignments: interior-only key -> `missing`, shadowed key -> real later value, key-after-block found, `"..."` and `'...'` forms, multiline key itself -> `exists`. RED-gating. | green |
| TEST-008 | Spec-AC-02 | unit | tests/skills/test-aai-secrets-preflight.sh    | Empty classification: `KEY=`, `KEY=""`, `KEY=''`, and multiline-shadowed real-empty all -> `empty`, never `exists`. `''` and shadowed-empty arms RED-gating. | green |
| TEST-009 | Spec-AC-03 | unit | tests/skills/test-aai-secrets-preflight.sh    | Adversarial never-echo on new paths: sentinel inside a multiline interior line and inside an unterminated-quote value never appears in combined stdout+stderr for any invocation shape; each run exits 0. (Guard/invariant — may be green pre-fix since the bug is misclassification, not leakage; recorded so its pre-fix green is not read as AC-proof.) | green |
| TEST-010 | Spec-AC-03 | unit | tests/skills/test-aai-secrets-preflight.sh    | Full-suite regression: TEST-001..006 re-run unchanged and green via `.aai/scripts/aai-run-tests.sh` wrapper -> exit 0. | green |

Notes:
- Test IDs continue the existing suite's stable numbering (TEST-001..006 ship
  with SPEC-0045); do not renumber.
- RED-proof obligation: TEST-007 and the `''`/multiline-shadowed-empty arms of
  TEST-008 MUST be observed FAILING against the current parser before the fix,
  with RED logs under `docs/ai/tdd/`. TEST-009 is an invariant guard whose
  pre-fix state may already be green (the current bug does not leak) — that is
  expected and must not be counted as AC-01/02 evidence.

## Verification
- `bash tests/skills/test-aai-secrets-preflight.sh test_007_multiline_quoting_aware` -> exit 0
- `bash tests/skills/test-aai-secrets-preflight.sh test_008_empty_and_quoted_empty` -> exit 0
- `bash tests/skills/test-aai-secrets-preflight.sh test_009_never_echo_multiline` -> exit 0, sentinel grep clean
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-secrets-preflight.sh` -> exit 0 (whole suite)
- Adversarial (Validation, security-class): independent probe re-running the
  new fixtures asserting no value byte on stdout/stderr on interior/multiline/
  unterminated paths.
- PASS criteria: all TEST-007..010 green; TEST-001..006 still green; all
  Spec-AC in a terminal (`done`) status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: secrets-preflight-env-multiline (SPEC-0049 at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-007, Spec-AC-02/TEST-008,
  Spec-AC-03/TEST-009+TEST-010)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under docs/ai/tdd/; review under docs/ai/reviews/)
- commit SHA or diff range when available

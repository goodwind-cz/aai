---
id: spec-secrets-preflight-unterminated-quote-safe-direction
type: spec
number: 56
status: done
ceremony_level: 1
links:
  requirement: ISSUE-0013
  rfc: null
  pr:
    - 108
  commits:
    - 2d9a40f
---

# Spec: secrets-preflight unterminated-quote value classifies toward `missing` (safe direction)

SPEC-FROZEN: true

Ceremony justification: single-surface safe-direction correctness fix to one
helper's quote handling in `.aai/scripts/secrets-preflight.mjs` —
`consumeQuotedValue` gains an `unterminated` signal and its target-key caller
`classifyEnvFileKey` acts on it; plus regression stanzas in the helper's own
test suite. No engine, allocator, guard, CLI/grammar/exit, or workflow-canon
change; `.aai/scripts/secrets-preflight.mjs` is NOT in `protected_paths_l3`
(verified against docs/ai/docs-audit.yaml). Reversible, single reviewable
surface -> Level 1. The helper is security-class, so the L1 lane's Validation
MUST adversarially re-check the never-echo invariant AND the safe-direction on
the new unterminated path (dispatch mandate).

Reserved display number (cross-branch collision check, RFC-0007): SPEC-0056.
Verified 2026-07-18 free across local `docs/specs/` + every `refs/heads`/
`refs/remotes` tree (highest SPEC allocated anywhere is SPEC-0055; no
`refs/aai/docnums/*` reservation refs present). The sequential integer is
minted/reserved at merge by `allocate-doc-number.mjs`; this file stays
`SPEC-DRAFT-<slug>.md` with `number: null` in-branch.

## Links
- Requirement: docs/issues/ISSUE-0013-secrets-preflight-unterminated-quote-safe-direction.md
- Extends (do NOT reopen): docs/specs/SPEC-0049-secrets-preflight-env-multiline.md
  (the quoting-aware `.env` multiline-masking contract; RR-2 was its recorded residual)
- Origin finding: docs/ai/reviews/review-20260717T201256Z.md (NON-BLOCKING, RR-2)
- Decision lineage: docs/ai/decisions.jsonl (ISSUE-0010 review_disposition
  2026-07-17T20:15:13Z — "accepted-limitation (spec RR-2). Optional follow-up:
  make the ambiguous unterminated-close case classify toward missing/empty")
- Shipped-by (predecessor helper): docs/specs/SPEC-0045-spec-intake-secrets-preflight.md
- Technology contract: docs/TECHNOLOGY.md

## Problem

`consumeQuotedValue` (`.aai/scripts/secrets-preflight.mjs:222-240`) consumes a
quoted value that opened on a `KEY=` line but did not close on the same physical
line by appending subsequent lines up to (and including) the line bearing the
matching close quote char, OR to EOF if never closed (SPEC-0049). It returns
`{ value, nextIndex }` with NO signal distinguishing "closed by a real matching
quote" from "ran to EOF, never closed."

The target-key classifier `classifyEnvFileKey` (`:279-294`) then classifies that
returned `value` purely by length after stripping one surrounding quote pair. So
a target key whose quoted value is never terminated (e.g. `KEY="secret…<EOF>`)
accumulates a non-empty interior and reads `exists` — a FALSE claim that a
present secret was found, when the value's extent is actually ambiguous.

This fails in the DANGEROUS direction for a secrets EXISTENCE preflight: a
malformed/ambiguous value gives false confidence a credential is set. The
never-echo guarantee is NOT implicated (misclassification only, no value bytes
emitted) and MUST remain intact across the fix.

## Design: the frozen unterminated rule + the target-vs-masking separation

### What "unterminated" means (exact)
A value is **unterminated** iff, on the target `KEY=` line, the value text opens
with a quote char (`"` or `'`) that is NOT closed on the same physical line
(`closedSameLine` is false), AND the continuation scan reaches EOF
(`j >= lines.length`) WITHOUT any later line containing the matching close quote
char. Equivalently: a quote was opened and no matching close char appears before
EOF. A value that is closed by its matching quote — same-line `KEY="v"`, a
properly-closed multiline value whose END line bears the close char, or
quoted-empty `""`/`''` — is NOT unterminated. An unquoted value (no opening
quote char) is NOT unterminated.

### The classification (frozen): unterminated -> `missing`
An unterminated target value classifies **`missing`**, never `exists`, never
`empty`. Justification for `missing` over `empty`:
- `empty` asserts a specific fact — "the key is assigned and its value has
  length 0." An unterminated quote means the value cannot even be delimited (the
  motivating interior is non-empty), so `empty` would be a different false claim.
- `missing` is the "could-not-establish a trustworthy present value" bucket. The
  grammar already degrades unreadable files and parse failures to `missing`
  (Constitution Art.4 degrade-and-report); an unterminated quote is another
  "cannot establish" condition, so `missing` is the consistent, safest direction
  ("do not claim a secret is present").

### The target-vs-masking separation (frozen)
The SAME `consumeQuotedValue` is used by TWO callers. The `unterminated` signal
MUST change ONLY the target-key classification, NEVER the masking:
- **Masking of OTHER keys' interiors** — `computeConsumedLineMask` (`:258-272`,
  caller at `:267`) destructures ONLY `nextIndex` and marks interior line indices
  consumed. It MUST continue to ignore `unterminated` entirely; masking is
  driven by `nextIndex` (unchanged), so every SPEC-0049 interior-masking result
  is byte-identical. An unterminated value still masks its consumed span to EOF
  exactly as today.
- **Target-key classification** — `classifyEnvFileKey` (caller at `:289`) is the
  ONLY site that reads `unterminated`; when the requested key's first genuine
  top-level assignment is unterminated, it returns `missing` before the
  length test.

Adding a third field to the returned object is backward-compatible: the mask
caller's `{ nextIndex }` destructuring silently ignores it (verified — only two
callers exist, `:267` and `:289`).

## Scope
- In scope: `.aai/scripts/secrets-preflight.mjs` — `consumeQuotedValue` (report
  `unterminated`) and `classifyEnvFileKey` (act on it for the target key); new
  regression stanzas in `tests/skills/test-aai-secrets-preflight.sh`; the ONE
  stale UNTERMINATED status assertion in TEST-009 (see Test Plan note).
- Out of scope: the CLI grammar, argument parsing, JSON path, env-var path, exit
  contract, stderr note strings, intake wiring/canon, `computeConsumedLineMask`
  masking behavior (byte-identical), and `stripSurroundingQuotes`. YAML remains
  out of scope.
- Explicitly NOT fixed (residual RR-2, carried forward — see Seam analysis): the
  stray/escaped-quote UNDER-mask, where a value's close is found on a later line
  that bears the quote char but is not a legitimate close (`\"` escape). That
  case leaves `unterminated` FALSE (the parser believes it closed), so this
  single-surface signal does not address it; fixing it requires escape-aware
  parsing (a different, larger surface). Never a leak.
- Protected paths touched: none.

## Implementation strategy
- Strategy: tdd
- Rationale: a safe-direction correctness fix in a security-class helper needing
  regression proof, failing in the dangerous direction (unterminated -> false
  `exists`). TDD RED-GREEN-REFACTOR is required so the misclassification is
  observed FAILING against the current parser before the fix counts as evidence
  (RED-proof), and never-echo is re-asserted on the new `missing` path.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single helper + its own test suite; small, reversible; no
  protected path. STATE already records `worktree.user_decision: inline`,
  `base_ref: main` (operator-approved wave). No user decision required.
- User decision: inline (already recorded)
- Base ref: main
- Worktree branch/path: inline (operator wave; STATE rationale names
  fix/secrets-preflight-unterminated-quote)
- Inline review scope: `.aai/scripts/secrets-preflight.mjs`,
  `tests/skills/test-aai-secrets-preflight.sh`,
  `docs/specs/SPEC-0056-secrets-preflight-unterminated-quote-safe-direction.md`,
  `docs/issues/ISSUE-0013-secrets-preflight-unterminated-quote-safe-direction.md`

## Acceptance Criteria Mapping

- Requirement ISSUE-0013 AC-001 (unterminated-to-EOF value classifies `missing`,
  never `exists`; `consumeQuotedValue` reports the unterminated condition)
  -> Spec-AC-01.
- Requirement ISSUE-0013 AC-002 (no regression: properly-closed single-line,
  multiline, quoted-empty unchanged; OTHER-key interior masking byte-identical;
  never-echo preserved; existing suite green) -> Spec-AC-02 + Spec-AC-03.

- Maps to: ISSUE-0013 AC-001
- Spec-AC-01: A target key whose quoted value opens a quote never closed before
  EOF classifies `missing` (never `exists`, never `empty`). Covered forms: bare
  `KEY="` at EOF, `KEY="non-empty interior…<EOF>` (double-quoted), the `'...`
  single-quoted equivalent. `consumeQuotedValue` returns `unterminated: true` on
  exactly these paths and `false` on every closed path.
  - Verification: `bash tests/skills/test-aai-secrets-preflight.sh test_011_unterminated_quote_safe_direction`
    -> exit 0. RED-proof: same test (and the edited TEST-009 UNTERMINATED arm)
    observed FAILING (unterminated reports `exists`) against the current
    `.aai/scripts/secrets-preflight.mjs` before the fix; RED log under `docs/ai/tdd/`.

- Maps to: ISSUE-0013 AC-002
- Spec-AC-02: No classification regression. Properly-closed values are unchanged:
  single-line quoted (`KEY="v"` -> `exists`), quoted-empty (`KEY=""`/`KEY=''` ->
  `empty`), properly-closed multiline (END line bears the close char -> `exists`),
  and the interior-masking of OTHER keys (SPEC-0049 — interior-only key ->
  `missing`, shadowed key -> real later assignment, key-after-block found) is
  byte-identical. The pre-existing suite TEST-001..008 and TEST-010 stay green
  with zero assertion edits.
  - Verification: `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-secrets-preflight.sh`
    -> exit 0 (whole suite); TEST-011 negative-control arms (properly-closed
    multiline still `exists`; quoted-empty still `empty`) green.

- Maps to: ISSUE-0013 AC-002
- Spec-AC-03: The never-echo invariant holds on the new unterminated path — a
  sentinel planted inside an unterminated-quote value never appears in combined
  stdout+stderr for any invocation shape (query the unterminated key, an
  interior key, a later key); every such run exits 0. Values are only ever
  tested for presence and `.length`; the added `unterminated` boolean carries no
  value bytes.
  - Verification: `bash tests/skills/test-aai-secrets-preflight.sh test_011_unterminated_quote_safe_direction`
    -> exit 0, sentinel grep clean; AND the edited TEST-009 stays green (sentinel
    grep clean on the unterminated path) post-fix.

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable AC + TEST-xxx, no PASS in planning.
  Art.2 KISS/YAGNI: minimal signal (one boolean) + one caller branch; masking and
  CLI untouched. Art.3 portability: plain .mjs, git-diffable. Art.4
  degrade-and-report: unterminated -> missing joins the existing "cannot
  establish" -> missing convention. Art.5 additive: output contract (three-status
  closed set, ref lines) unchanged; only a dangerous-direction misclassification
  is corrected toward the safe bucket. Art.6 single-writer: STATE via state.mjs
  only. Art.7 operator-only merge: planning does not merge. -->

## Seam analysis

No cross-feature seam requiring an integration test. `classifyEnvFileKey` /
`consumeQuotedValue` are private helpers consumed only by this CLI; the output
contract (`file:<path>#<key> <status>`, three-status closed set) is unchanged, so
the intake wiring that reads a status token is unaffected. No shared DB row, no
multi-writer, no downstream projection of `.env` interior structure. The two
internal callers of `consumeQuotedValue` (mask vs classify) ARE a shared-helper
seam within the file — covered by keeping masking byte-identical (Spec-AC-02
regression + TEST-007 unchanged) while only the classifier reads the new signal.
- Residual risk RR-1 (pre-existing, unchanged): whether a live intake LLM agent
  invokes the helper vs echoing a value (SPEC-0045 R1 / cannot_verify), out of
  code scope, unchanged here.
- Residual risk RR-2 (NARROWED, not fully closed): the stray/escaped-quote
  UNDER-mask (a value "closed" by a `\"`-style stray quote on a later line, which
  the parser reads as a real close) is NOT detected by the unterminated signal
  (that path leaves `unterminated` FALSE). This fix closes the true
  unterminated-to-EOF sub-case; the escaped-quote sub-case remains an accepted
  limitation requiring escape-aware parsing (larger surface, separate follow-up).
  Never a leak (never-echo holds regardless). Characterized, not asserted-fixed,
  in TEST-011.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                     | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Unterminated-to-EOF target value classifies `missing`; `consumeQuotedValue` reports `unterminated` | done | RED docs/ai/tdd/red-20260718T111551Z-test_011_unterminated_quote_safe_direction.log; GREEN docs/ai/tdd/green-20260718T111638Z-test_011_unterminated_quote_safe_direction.log; TEST-011 exit 0 | — | — |
| Spec-AC-02 | No regression: closed single-line/multiline/quoted-empty unchanged; OTHER-key masking byte-identical; TEST-001..008/010 green | done | docs/ai/tdd/green-20260718T111647Z-full-suite-secrets-preflight-unterminated-quote-safe-direction.log (TEST-001..011 all green, exit 0) | — | — |
| Spec-AC-03 | Never-echo holds on the new unterminated path; `unterminated` boolean carries no value bytes | done | RED docs/ai/tdd/red-20260718T111556Z-test_009_never_echo_multiline.log; GREEN docs/ai/tdd/green-20260718T111642Z-test_009_never_echo_multiline.log; TEST-009+TEST-011 sentinel-absence assertions exit 0; independent manual adversarial probe confirmed no leak | — | — |

## Implementation plan
- Components/modules affected: `.aai/scripts/secrets-preflight.mjs` —
  `consumeQuotedValue` (track whether the continuation loop broke on a real close
  vs ran to EOF; return `{ value, nextIndex, unterminated }`; `unterminated:
  false` on the same-line-closed and unquoted early-return path) and
  `classifyEnvFileKey` (read `unterminated`; return `missing` before the length
  test when the target key's first genuine assignment is unterminated). No change
  to `computeConsumedLineMask`, `stripSurroundingQuotes`, the CLI, grammar, or
  exit contract.
- Data flow: `classifyFileCheck` -> `classifyEnvFileKey(raw, key)` scans lines,
  skips masked indices, matches the requested key, calls `consumeQuotedValue`,
  and now short-circuits to `missing` on `unterminated`. `computeConsumedLineMask`
  keeps consuming `nextIndex` only.
- Edge cases: bare `KEY="` at EOF (-> unterminated -> missing); `KEY="v"` same
  line (-> closed -> exists, unchanged); properly-closed multiline (END line has
  close char -> closed -> exists, unchanged); `KEY=""`/`KEY=''` (-> closed empty
  -> empty, unchanged); single-quoted unterminated `KEY='…<EOF>` (-> missing);
  trailing-newline `split(/\r?\n/)` empty last element does not count as a close
  (empty string contains no quote char); OTHER-key interior masking unchanged;
  CRLF preserved; stray/escaped-quote under-mask NOT changed (RR-2).

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                       | Description                                                                                                                                                                   | Status  |
|----------|------------|------|--------------------------------------------|-----------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-011 | Spec-AC-01, Spec-AC-02, Spec-AC-03 | unit | tests/skills/test-aai-secrets-preflight.sh | Unterminated-quote safe direction: bare `KEY="`@EOF, non-empty `"`-interior@EOF, and `'`-interior@EOF each -> `missing`; negative controls (properly-closed multiline -> `exists`, `KEY=""`/`KEY=''` -> `empty`, unquoted `KEY=v` -> `exists`) prove no over-correction; sentinel inside an unterminated value never appears in combined stdout+stderr; each run exits 0. RED-gating (unterminated arms report `exists` pre-fix). | green |
| TEST-009 | Spec-AC-01, Spec-AC-03 | unit | tests/skills/test-aai-secrets-preflight.sh | EDITED (single assertion): the existing `UNTERMINATED` status assertion flips `exists` -> `missing` (ISSUE-0013 safe direction) and its description string updates; the sentinel-absence core and all MULTILINE/INTERIOR/AFTER_MULTILINE assertions are UNCHANGED. RED-gating for the flipped assertion. | green |

Notes:
- Test IDs continue the existing suite's stable numbering (TEST-001..010 ship
  with SPEC-0045/SPEC-0049); do not renumber. TEST-011 is new.
- TEST-009 assertion edit — DELIBERATE, JUSTIFIED, single line (see Blocking /
  decisions): SPEC-0049's TEST-009 pinned the RR-2 accepted-limitation
  (`UNTERMINATED -> exists`) as the then-current behavior. ISSUE-0013 corrects
  exactly that behavior, so this one status assertion MUST flip to `missing` or
  the suite cannot be green post-fix. This is the RED-proof surface, NOT a
  regression edit; ISSUE-0013 AC-002's "zero assertion edits" is scoped to the
  behavior-unchanged tests (TEST-001..008, TEST-010, and the rest of TEST-009).
- RED-proof obligation: TEST-011's unterminated arms AND the flipped TEST-009
  assertion MUST be observed FAILING (report `exists`) against the current parser
  before the fix, with RED logs under `docs/ai/tdd/`. TEST-011's never-echo arm
  may be green pre-fix (the current bug misclassifies, does not leak) — that is
  expected and must not be counted as AC-01 evidence.

## Verification
- `bash tests/skills/test-aai-secrets-preflight.sh test_011_unterminated_quote_safe_direction` -> exit 0, sentinel grep clean
- `bash tests/skills/test-aai-secrets-preflight.sh test_009_never_echo_multiline` -> exit 0 (post-edit, post-fix)
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-secrets-preflight.sh` -> exit 0 (whole suite; TEST-001..008/010 byte-identical and green)
- Adversarial (Validation, security-class): independent probe re-running the new
  unterminated fixtures asserting (a) no value byte on stdout/stderr on the
  unterminated path AND (b) the safe direction (unterminated target -> `missing`).
- PASS criteria: TEST-011 green; edited TEST-009 green; TEST-001..008/010 still
  green; all Spec-AC in a terminal (`done`) status with non-empty evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: secrets-preflight-unterminated-quote-safe-direction (SPEC-0056 at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-011+TEST-009, Spec-AC-02/TEST-011+full-suite,
  Spec-AC-03/TEST-011+TEST-009)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under docs/ai/tdd/; review under docs/ai/reviews/)
- commit SHA or diff range when available

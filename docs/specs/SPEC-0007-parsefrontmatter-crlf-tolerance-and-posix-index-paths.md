---
id: SPEC-0007
type: spec
status: done
links:
  requirement: null
  issue: ISSUE-0001
  rfc: RFC-0001
  pr: []
  commits: []
---

# SPEC-0007 — CRLF/lone-CR-tolerant `parseFrontmatter` + OS-independent POSIX index paths (ISSUE-0001)

SPEC-FROZEN: true

## Links
- Issue (WHAT/WHY, proven root cause + reproduction): docs/issues/ISSUE-0001-parsefrontmatter-crlf-drops-index-sections.md
- AC-tracking authority: docs/rfc/RFC-0001-ac-tracking-and-multi-dev-state.md
- Sibling docs-index integrity / coverage invariant (merged): docs/specs/SPEC-0006-index-deferred-coverage-and-done-close-policy.md
- Docs hygiene / drift authority: docs/rfc/RFC-0002-docs-hygiene-and-drift-audit.md
- Technology contract: docs/TECHNOLOGY.md

## Frontmatter status values
- draft: spec frozen for implementation, work not yet started (this doc)
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred / rejected / superseded: standard meanings per template

## Problem (WHAT/WHY lives in ISSUE-0001)
Confirmed against the live code on this branch:

1. **Parser gap — `parseFrontmatter` is LF-only.**
   `.aai/scripts/lib/docs-model.mjs:146`:
   `if (!content.startsWith('---\n')) return null;` hard-codes LF. On a CRLF
   checkout (Windows, or any `core.autocrlf=true` / `*text=auto` repo) every doc
   begins with `'---\r\n'`, so `startsWith('---\n')` is false → returns `null`
   for **every** doc. The frontmatter block is also split on `'\n'`
   (`block.split('\n')`, line 154), so even partial parses would carry a trailing
   `\r` on every value. `parseAcTable` (line 198) has the same `.split('\n')`
   assumption: AC-table rows, `Review-By`, and `Notes`/references derived from
   those cells would all carry a trailing `\r` on a CRLF doc.

2. **Generator gap — OS-dependent paths and silent all-Legacy fallout.**
   `.aai/scripts/generate-docs-index.mjs:102`: `rel = path.relative(ROOT, filePath)`
   with no POSIX normalization → backslash paths on win32. Line 106-108: a `null`
   frontmatter routes the doc to the Legacy bucket
   (`status:'legacy', legacy:true`). On a CRLF checkout the combination yields a
   `docs/INDEX.md` with every real section `(0)` / `_None._`, the whole corpus
   (operator reported 464 docs) under "## Legacy (no frontmatter)", OS-specific
   backslash paths, exit 0, and no error — a silent corruption of a committed,
   shared artifact.

   **Why SPEC-0006's coverage invariant does NOT catch this:** the SPEC-0006
   zero-section invariant treats the Legacy section as a valid placement and
   exempts legacy docs. An all-Legacy CRLF index therefore has **zero** coverage
   violations and passes `--strict`. There is currently no automated tripwire for
   a parser failure that collapses the whole corpus into Legacy. This spec closes
   the root cause (FIX 1) and adds a complementary, report-only legacy-ratio
   tripwire (Spec-AC-06) that the SPEC-0006 invariant structurally cannot provide.

## Design decisions (load-bearing — read before implementing)
1. **Normalize line endings once, at parser entry — never mutate files on disk.**
   The required fix is `content = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n')`
   applied at the top of `parseFrontmatter` (CRLF first, then lone-CR). The same
   normalization MUST be applied consistently wherever a raw-content parser splits
   on `\n` — at minimum `parseFrontmatter` and `parseAcTable`. `parseReviewBy`
   and `extractReferences` receive cell-level strings produced downstream of
   `parseAcTable`; once `parseAcTable` normalizes, those are clean, but the
   implementation MUST guarantee (by normalization or by trimming) that no parsed
   value returned to a consumer carries a trailing `\r` for any of LF / CRLF /
   lone-CR input. Implementation MAY centralize the normalization in one helper
   so the three+ parsers cannot drift.
2. **POSIX paths everywhere a path enters a record/row.** In
   `generate-docs-index.mjs`, every place a filesystem path is pushed into a
   `docs[]` record or an index table row MUST use
   `path.relative(ROOT, filePath).split(path.sep).join('/')`. On POSIX
   `path.sep === '/'`, so this is a strict no-op for the current LF/macOS output
   (Spec-AC-03 negative requirement: the real-repo index must be byte-identical
   modulo the `Generated:` line before vs after the path change). Diagnostic
   `console.*` lines that print `path.relative(...)` for human messages are out of
   scope; only paths that land in the committed `docs/INDEX.md` (or the `docs[]`
   record consumed to build it) are in scope.
3. **The CRLF fix is a true bug fix → RED-proof is mandatory and central.** The
   parser unit assertions (Spec-AC-01/02) and the end-to-end CRLF-corpus
   assertion (Spec-AC-04) MUST be observed FAILING on the pre-fix code
   (`parseFrontmatter(crlf) === null`; CRLF corpus → all-Legacy INDEX) and GREEN
   after. A test that never reproduced the bug proves nothing.
4. **Legacy-ratio guard is report-only and false-positive-hardened.** Mirror the
   SPEC-0006 / SPEC-0003 "report-only first, escalate only when the signal is
   proven clean" precedent: `generate-docs-index.mjs` emits a LOUD `stderr`
   warning when the Legacy bucket exceeds 50% of scanned docs **AND** the legacy
   count is greater than 1 (the `>1` floor prevents a tiny corpus — e.g. 1 legacy
   doc out of 1 — from tripping it). It does **not** change any exit code in this
   spec (no `--strict` fatal): a fatal escalation is explicitly DEFERRED to a
   follow-up once the threshold is field-validated. Rationale for inclusion (not
   deferral): SPEC-0006's coverage invariant cannot detect an all-Legacy corpus
   (Legacy is a valid/exempt placement), so without this guard there is no
   automated detector for a future parser regression that all-Legacies the
   corpus; a report-only stderr warning closes that gap at near-zero risk and
   touches no gate exit code.
5. **`.gitattributes` is defense-in-depth at the source.** The repo's
   `.gitattributes` covers `*.sh/*.bash/*.ps1` (eol=lf) and `*.bat/*.cmd`
   (eol=crlf) but neither the docs corpus nor the `.mjs` scripts. Add
   `docs/**/*.md text eol=lf` and `*.mjs text eol=lf` so the corpus and the
   scripts that read it stay LF regardless of `autocrlf`. This is the durable
   prevention; FIX 1 is the runtime tolerance that protects already-checked-out
   CRLF trees and target repos that lack the attribute.
6. **Reuse the existing test harness; do not invent a parallel runner.** All
   tests live in `tests/skills/test-aai-docs-audit.sh` (the established AAI
   convention used by SPEC-0003/0004/0005/0006 and run by the Validation /
   aai-test-skills path). Pure-parser assertions (Spec-AC-01/02) run as `node`
   inline assertions against `.aai/scripts/lib/docs-model.mjs`; the CRLF-corpus
   and POSIX-path assertions (Spec-AC-03/04/06) write CRLF fixtures and invoke the
   real `generate-docs-index.mjs`. New `test_*` functions register in `main()`
   BEFORE `test_index_continue_on_error` (the suite is `set -e` and
   `test_index_continue_on_error` is the known pre-existing last-failing test).

## Implementation strategy
- Strategy: hybrid
- Rationale: TDD (RED-GREEN-REFACTOR) for the three code surfaces — the
  `parseFrontmatter` / `parseAcTable` CRLF+lone-CR normalization, the
  POSIX-path normalization in the generator, and the legacy-ratio report-only
  guard — because this is a confirmed High-severity bug in a parser shared by the
  index generator, docs-audit, and docs-canon (consumed by CI, pre-commit, and
  intake gating), it demands regression proof, and the assertions include
  self-evaluation-trap negatives (POSIX path change must be a *no-op* on macOS;
  legacy guard must NOT fire on a normal corpus) that only a real RED state proves
  non-tautological. Loop for the `.gitattributes` two-line addition, which is
  configuration glue verified by `grep`. This matches the dispatch suggestion and
  the sibling SPEC-0006 hybrid posture.
- RED-proof obligation (all AC-gating tests, any strategy): every gating test
  must be observed FAILING without the change. The negative assertions
  (Spec-AC-03 macOS no-op, Spec-AC-06 normal-corpus-not-flagged) embed a positive
  control in the same fixture so the RED is genuine.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: additive, low-risk change to a single shared parser module
  plus one generator and one config file. No schema change, no migration, no
  protected-workflow rewrite; the normalization is purely additive at parser
  entry and the POSIX-path change is a no-op on the current (POSIX) CI/dev host.
  Work is already on a dedicated branch (`fix/issue-0001-crlf-frontmatter`) off
  `main`, independent of other in-flight PRs. Same inline posture used for the
  sibling SPEC-0003/0004/0005/0006 docs-index/parser work.
- User decision: inline
- Base ref: main
- Worktree branch/path: n/a (inline on branch `fix/issue-0001-crlf-frontmatter`)
- Inline review scope:
  - `.aai/scripts/lib/docs-model.mjs`
  - `.aai/scripts/generate-docs-index.mjs`
  - `.gitattributes`
  - `tests/skills/test-aai-docs-audit.sh`
  - `docs/specs/SPEC-0007-parsefrontmatter-crlf-tolerance-and-posix-index-paths.md`
  - `docs/issues/ISSUE-0001-parsefrontmatter-crlf-drops-index-sections.md` (links)

## Acceptance Criteria Mapping

- Maps to: ISSUE-0001 FIX 1 (primary) / Verification "Unit"
  - Spec-AC-01: `parseFrontmatter` returns an identical parsed object for the LF,
    CRLF (`\r\n`), and lone-CR (`\r`) variants of the same document — same keys,
    same scalar/list/nested values, with no trailing `\r` on any value. (LF result
    is the reference.) Normalization happens once at parser entry; files on disk
    are not mutated.
  - Verification: TEST-001.

- Maps to: ISSUE-0001 Constraints/Risks (apply normalization consistently across
  the other parsers)
  - Spec-AC-02: `parseAcTable` returns identical rows (cell-for-cell) for LF,
    CRLF, and lone-CR variants of the same document, and no value returned by
    `parseAcTable` / `parseReviewBy` / `extractReferences` carries a trailing
    `\r` for any of the three line-ending variants. (Concretely: a `Review-By`
    cell that is a valid date for LF is still parsed as that same date — not
    `kind:'invalid'` — for CRLF, and a `→ REF-0001` note still yields `REF-0001`
    not `REF-0001\r`.)
  - Verification: TEST-002.

- Maps to: ISSUE-0001 FIX 2 (secondary) / Expected Behavior (POSIX paths only)
  - Spec-AC-03: Every path written into `docs/INDEX.md` (and into the `docs[]`
    record used to build it) uses forward slashes only — no backslash separators —
    via `path.relative(ROOT, filePath).split(path.sep).join('/')`. Negative
    requirement: on POSIX the change is a no-op — the real-repo `docs/INDEX.md` is
    byte-identical (modulo the `Generated:` line) before and after the change.
  - Verification: TEST-003.

- Maps to: ISSUE-0001 Verification "Generator" / Steps to Reproduce 2 (end-to-end)
  - Spec-AC-04: A fixture corpus written with CRLF line endings, run through the
    real `generate-docs-index.mjs`, produces an INDEX in which docs are bucketed
    by their real frontmatter status (correct non-Legacy section counts, ≤1
    Legacy) and all paths are POSIX — NOT the all-Legacy / zero-real-section
    corruption. RED-proof: on pre-fix code the same CRLF corpus yields every real
    section empty and the corpus under "## Legacy (no frontmatter)".
  - Verification: TEST-004.

- Maps to: ISSUE-0001 Guardrail 2 (.gitattributes)
  - Spec-AC-05: `.gitattributes` contains both `docs/**/*.md text eol=lf` and
    `*.mjs text eol=lf` (in addition to the existing executable-script rules,
    which are unchanged).
  - Verification: TEST-005.

- Maps to: ISSUE-0001 Guardrail 3 (optional defense-in-depth, scoped as
  report-only per Design decision 4)
  - Spec-AC-06: `generate-docs-index.mjs` writes a loud `stderr` warning when the
    Legacy bucket exceeds 50% of scanned docs AND the legacy count is greater than
    1; it does NOT alter any exit code (no fatal in this spec). Negative control:
    a normal corpus (≤1 legacy, or legacy ≤50%) produces no such warning. The
    warning text names the legacy count and the scanned-doc total.
  - Verification: TEST-006.

- Maps to: ISSUE-0001 Verification line 3 + Constraints (no regression)
  - Spec-AC-07: No regression — `bash tests/skills/test-aai-docs-audit.sh` passes
    except the known pre-existing `test_index_continue_on_error`; on the real repo
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` exits 0 CLEAN
    and `node .aai/scripts/generate-docs-index.mjs` is idempotent (two runs
    byte-identical modulo the `Generated:` line).
  - Verification: TEST-007.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | parseFrontmatter identical parsed object for LF/CRLF/lone-CR; no trailing CR; no disk mutation | done | TEST-001 GREEN (docs/ai/tdd/green-spec0007-suite-20260630T154419Z.log); RED docs/ai/tdd/red-spec0007-test001-20260630T153841Z.log; independently reproduced by Validation (sonnet-4-6 node inline, 2026-06-30T15:50Z) | — | RED-proof confirmed independent: parseFrontmatter(crlf)===null pre-fix; normalizeNewlines at parser entry |
| Spec-AC-02 | parseAcTable identical rows for LF/CRLF/CR; no trailing CR via parseReviewBy/extractReferences | done | TEST-002 GREEN (suite log); RED docs/ai/tdd/red-spec0007-test002-20260630T153854Z.log; independently reproduced by Validation (parseAcTable node inline, parseReviewBy kind=date, refs=[REF-0001] all PASS) | — | lone-CR genuine RED (rows empty pre-fix); normalization routed through normalizeNewlines |
| Spec-AC-03 | Index paths POSIX-only (split(path.sep).join('/')); no-op on macOS (byte-identical real index) | done | TEST-003 GREEN (suite log): real INDEX byte-identical modulo Generated, 0 backslashes; independently verified (generate-docs-index twice, diff clean, 2026-06-30T15:51Z) | — | No-op on POSIX by design; positive path-fix RED carried by TEST-004 |
| Spec-AC-04 | CRLF fixture corpus → real-status buckets, ≤1 Legacy, POSIX paths; NOT all-Legacy | done | TEST-004 GREEN (suite log); RED docs/ai/tdd/red-spec0007-test004-20260630T153910Z.log (pre-fix all-Legacy) | — | End-to-end seam; RED-proof confirmed independent |
| Spec-AC-05 | .gitattributes adds `docs/**/*.md text eol=lf` and `*.mjs text eol=lf` | done | TEST-005 GREEN (suite log); RED docs/ai/tdd/red-spec0007-test005-20260630T153931Z.log; independently grep-verified by Validation (2026-06-30T15:50Z) | — | grep-verified; existing *.sh/*.bat rules unchanged |
| Spec-AC-06 | Report-only legacy-ratio stderr warning (>50% AND >1); exit code unchanged; not fired on normal corpus | done | TEST-006 GREEN (suite log); RED docs/ai/tdd/red-spec0007-test006-20260630T153931Z.log; independently verified positive+negative control (exit 0 both, 2026-06-30T15:51Z) | — | Defense-in-depth SPEC-0006 cannot provide; negative control (1 legacy/3 docs) silent; fatal deferred |
| Spec-AC-07 | No regression: suite green (except known pre-existing); repo docs-audit CLEAN; index idempotent | done | TEST-007 GREEN (suite log): repo docs-audit --check --strict --no-event CLEAN exit 0; index idempotent; independently verified by Validation suite run (2026-06-30T15:49Z) | — | suite fails only known pre-existing test_index_continue_on_error |

Status values: planned | implementing | done | deferred | blocked | rejected.
Gate (per .aai/VALIDATION.prompt.md): any planned/implementing row blocks PASS;
any done row needs non-empty Evidence; deferred/blocked need a future Review-By.

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/lib/docs-model.mjs`:
    - `parseFrontmatter(content)`: normalize at entry —
      `content = content.replace(/\r\n/g, '\n').replace(/\r/g, '\n');` before the
      `startsWith('---\n')` test and the `block.split('\n')` loop.
    - `parseAcTable(content)`: apply the same normalization at entry (it
      `section.split('\n')`-es). Optionally extract a small
      `normalizeNewlines(s)` helper reused by both so the two cannot drift.
    - Guarantee `parseReviewBy` / `extractReferences` outputs carry no trailing
      `\r`: with `parseAcTable` normalized, the cells are clean; add a defensive
      trim only if a direct caller can pass un-normalized content.
  - `.aai/scripts/generate-docs-index.mjs`:
    - Line ~102: `const rel = path.relative(ROOT, filePath).split(path.sep).join('/');`
      Audit the other `d.path` push sites (lines ~108, 130 and the table
      renderers at ~272/285/292/298/306/330/336/364) — they consume the already
      normalized `rel`, so normalizing once at the source (102/108) suffices;
      verify no other site re-derives a raw `path.relative`.
    - Add the legacy-ratio report-only guard after the scan loop (where `docs[]`
      and the legacy count are known), before/independent of the exit-code path:
      `if (legacyCount > 1 && legacyCount / docs.length > 0.5) console.warn(...)`.
  - `.gitattributes`: append the two `text eol=lf` lines.
  - `tests/skills/test-aai-docs-audit.sh`: add `test_issue0001_*` functions
    (TEST-001..006 as below) + reuse `test_index*` style for TEST-007, registered
    in `main()` BEFORE `test_index_continue_on_error`.
- Data flows: frontmatter / AC-table / Review-By / references already read by the
  generator and docs-audit; normalization is interposed at parser entry only. No
  new filesystem walk, no new git probe.
- Edge cases:
  - Lone-CR (old-Mac) input: `\r` not followed by `\n` — the second replace
    handles it; assert it explicitly (TEST-001/002).
  - A doc whose body legitimately contains `\r\n` inside fenced code: only the
    parser's working copy is normalized; the on-disk file is untouched.
  - Mixed line endings within one file (CRLF frontmatter, LF body): normalization
    is global on the in-memory copy, so the parse is consistent.
  - POSIX no-op: `split('/').join('/')` must not alter any existing path — assert
    byte-identical real-repo index (TEST-003).
  - Tiny corpus (1 legacy of 1): the `>1` floor keeps the legacy guard silent
    (TEST-006 negative control).

## Seam analysis
- SEAM-1 (`docs-model.mjs` parsers → `generate-docs-index.mjs` AND
  `docs-audit-core.mjs` AND `docs-canon-core.mjs`): the CRLF normalization changes
  a parser consumed by three engines that back CI, pre-commit, and intake gating.
  Risk: a normalization that subtly changes LF parsing breaks the real index or
  docs-audit. TEST-004 crosses it end-to-end (CRLF corpus → real generator →
  correct buckets); TEST-007 crosses it for docs-audit (real-repo
  `--check --strict` exit 0 CLEAN) and for index idempotence. Not two mocked unit
  checks — the real generator/audit run over real content.
- SEAM-2 (generated `docs/INDEX.md` → committed shared artifact / git across
  OSes): the POSIX-path change makes the artifact OS-independent. Risk: it alters
  the current macOS output (it must not). TEST-003 crosses it: the real-repo index
  is byte-identical (modulo `Generated:`) before vs after, AND a CRLF/backslash
  fixture yields forward-slash-only paths (TEST-004).
- SEAM-3 (legacy-ratio guard ↔ shared generator exit-code gate used by CI /
  pre-commit `--strict`): report-only must not change exit codes. TEST-006 crosses
  it: a high-legacy fixture emits the stderr warning AND the process exit code is
  unchanged vs the same run without the trip; a normal corpus emits nothing.
- Residual risk (recorded): the legacy-ratio threshold (50% / `>1`) is a
  heuristic; a legitimately legacy-heavy migrating corpus could emit a benign
  warning. Mitigated by report-only (no exit-code effect) and the `>1` floor;
  escalation to a `--strict` fatal is explicitly deferred until the threshold is
  field-validated, per Design decision 4.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description | Status |
|----------|------------|-------------|-------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | unit        | tests/skills/test-aai-docs-audit.sh | `node` assertion: build one doc string, derive CRLF and lone-CR variants; assert `parseFrontmatter` returns deep-equal objects for all three and no value contains `\r`. RED-proof: pre-fix `parseFrontmatter(crlf) === null`. | green |
| TEST-002 | Spec-AC-02 | unit        | tests/skills/test-aai-docs-audit.sh | `node` assertion: a doc with an AC-Status table (incl. a dated `Review-By` and a `→ REF-0001` note); assert `parseAcTable` rows are cell-equal across LF/CRLF/CR, `parseReviewBy` of the CRLF cell yields the same date (not `invalid`), and `extractReferences` yields `REF-0001` (no `\r`). RED-proof: pre-fix CRLF rows carry trailing `\r` / Review-By parses invalid. | green |
| TEST-003 | Spec-AC-03 | integration | tests/skills/test-aai-docs-audit.sh | Run the real `generate-docs-index.mjs` on the real repo twice around the change context; assert `docs/INDEX.md` has zero backslash paths and is byte-identical modulo `Generated:` (POSIX no-op). RED-proof control: a fixture path containing a backslash-sep would render `/` post-fix. | green |
| TEST-004 | Spec-AC-04 | integration | tests/skills/test-aai-docs-audit.sh | Write a small CRLF fixture corpus (docs with `status: done/draft/...`), run the real generator; assert each doc lands in its real-status section, ≤1 Legacy, POSIX paths only. RED-proof: pre-fix the same CRLF corpus is all-Legacy with every real section empty. | green |
| TEST-005 | Spec-AC-05 | integration | tests/skills/test-aai-docs-audit.sh | grep asserts `.gitattributes` contains both `docs/**/*.md text eol=lf` and `*.mjs text eol=lf`; existing `*.sh/*.bat` rules still present. | green |
| TEST-006 | Spec-AC-06 | integration | tests/skills/test-aai-docs-audit.sh | High-legacy fixture (>50% legacy AND >1) → generator prints the legacy-ratio warning to stderr AND exit code is unchanged vs a normal run; negative control: a ≤1-legacy / ≤50% corpus prints no such warning. RED-proof via the negative control. | green |
| TEST-007 | Spec-AC-07 | integration | tests/skills/test-aai-docs-audit.sh | Regression: full suite green except known `test_index_continue_on_error`; real-repo `docs-audit --check --strict --no-event` exit 0 CLEAN; `generate-docs-index.mjs` idempotent (two real runs byte-identical modulo `Generated:`). | green |

Test status values: pending → red → green. Every Spec-AC has ≥1 TEST-xxx. Test
IDs are stable; do not renumber after freeze.

Note on CI: the GitHub Actions `ps1-quality` workflow currently runs only
`test-ps1-quality.sh` + the Pester `aai-update.Tests.ps1`; the `tests/skills/*.sh`
suite is the gate the AAI Validation / aai-test-skills path runs (as for
SPEC-0003/0004/0005/0006). Wiring the skills suite into GitHub Actions is a
non-blocking follow-up, out of scope for this spec.

## Verification
- `bash tests/skills/test-aai-docs-audit.sh` — TEST-001..007 green; pre-existing
  pass set preserved (only `test_index_continue_on_error` known-fails).
- `node -e` over `.aai/scripts/lib/docs-model.mjs`: `parseFrontmatter` and
  `parseAcTable` return identical results for LF/CRLF/lone-CR inputs.
- `node .aai/scripts/generate-docs-index.mjs` on the real repo: zero backslash
  paths in `docs/INDEX.md`; two runs byte-identical modulo `Generated:`.
- `node .aai/scripts/generate-docs-index.mjs` on a CRLF fixture corpus: real
  status buckets populated, ≤1 Legacy.
- `grep -F 'docs/**/*.md text eol=lf' .gitattributes` and
  `grep -F '*.mjs text eol=lf' .gitattributes` both match.
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real repo
  exits 0 CLEAN.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal with evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id (ISSUE-0001 / SPEC-0007)
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY (ISSUE-0001 owns WHAT/WHY).
This document does not define workflow.
Use plain Markdown headings and body text. Do not add emoji or decorative icons
unless there is a strong domain-specific reason.

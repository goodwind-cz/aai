---
id: spec-gate-checks-declared-mutation
number: null
type: spec
status: implementing
mutation_gate: v1
frozen_sha256: cc21078fde6022051081d63239f1c8cb3b0acd26a7ad3f091d2195cd61702199
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-DRAFT-gate-checks-declared-mutation.md
  rfc: null
  pr: []
  commits: []
---

# Spec — the mutation gate compares the declared mutation to the one that ran

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/CHANGE-DRAFT-gate-checks-declared-mutation.md
- Registry item drained: `fu-gate-ignores-declared-mutation` (P2)
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, no dependencies)

## Implementation strategy
- Strategy: tdd
- Rationale: the artifact under repair is the gate that enforces this project's
  RED-first discipline. Every criterion below must be observable FAILING on the
  pre-change tree, because a gate that cannot detect its own sabotage is the
  defect being closed. The intake's own Notes record the same choice.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: the change edits `mutation-gate.mjs`, which every other
  ride's close ceremony runs; a half-applied edit in the shared checkout would
  break unrelated closes.
- User decision: worktree (already recorded in STATE before planning)
- Base ref: main (753a269d)
- Worktree branch/path: fix/gate-checks-declared-mutation / ../aai-fix-gate
- Inline review scope: n/a (worktree; review scope is the branch diff)

## Ceremony level

ceremony_level: 2. No path in scope is listed in `protected_paths_l3`
(docs/ai/docs-audit.yaml): `state.mjs`, `state-engine.mjs`, `state-core.mjs`,
`allocate-doc-number.mjs`, `pre-commit-checks.sh/.ps1`, `WORKFLOW.md` and
`CONSTITUTION.md` are all untouched. `close-work-item.mjs` is in scope but is
NOT an L3 path; it carries its own content-hash pin instead (see Implementation
plan, step 6).

## What is established before this scope starts

Measured on 2026-09-26 against main 753a269d. Every number below was taken by
running `lib/docs-model.mjs`'s own `parseTestPlanTable` / `resolveStrategy` and
`lib/mutation-record.mjs`'s own `parseRecord` over the live corpus, never by
hand-reading.

- The gate governs 5 specs (frontmatter `mutation_gate: v1` AND a tdd/hybrid
  strategy): SPEC-0181, SPEC-0182, SPEC-0184, SPEC-0185, SPEC-0186. They carry
  229 non-empty Mutation cells. Corpus-wide there are 2133 Test Plan rows, of
  which 1904 carry an empty cell and are not gated at all.
- `mutation-gate.mjs:273-279` checks that a cell is non-empty and not a
  placeholder, and nothing else. The stored record carries `target` and
  `mutation` (`lib/mutation-record.mjs:17-18`), so the comparison is possible
  today with no record-format change.
- The gate's only production caller is `close-work-item.mjs`
  `evaluateMutationGate()`, which runs it for the docs of the ride being closed
  (frontmatter `type: spec`). Nothing sweeps the whole corpus, and the
  `mutation_gate` dial in docs/ai/docs-audit.yaml is `enforce` in this repo, so
  a non-zero gate exit REFUSES a close (exit 8).
- Mutation records are gitignored (`.gitignore:35`, `docs/ai/tdd/**`), so they
  exist only on the machine that produced them. In this worktree no
  `docs/ai/tdd/<spec-id>/` exists for any of the 5 specs, and all 5 take the
  existing `evidence tree absent` DEGRADE at exit 0.

### Corrections to the intake's measurement

The intake's corpus numbers are close but two of its three classes do not
survive being defined as code:

- "124 already carry a machine-readable `sed:`/`patch:` token" — 124 is the
  count of cells CONTAINING the substring `sed:` or `patch:` (confirmed). Only
  **95** of them yield a token under the sed grammar the runner actually
  applies (`mutation-run.mjs` `applySedExpr`). The other 29 are prose mentions
  of the words (for example a cell quoting `startsWith('patch:')`) or spans
  whose boundary cannot be closed by that grammar.
- "15 name a file path but no token" — a path-shaped regex finds 17 such cells,
  but the class is worthless and is DROPPED from this design: of those rows,
  **0** have a named path equal to the record's `target` and 1 actively
  contradicts it. The orchestrator's hypothesis that a named path can stand in
  for a declaration is not supported by the corpus.
- "90 are pure prose" — under the grammar above the uncomparable class is
  **134**, not 90.
- Not in the intake, and the most important number here: of the 95 comparable
  rows, 86 have a record on the owner's main checkout, and only **34** of those
  match it. **52 declare something other than what ran.** TEST-694 is not a
  one-off; 60% of the comparable corpus is already drifted.

| spec | rows | comparable | uncomparable | match | mismatch | record absent |
|------|------|------------|--------------|-------|----------|---------------|
| spec-mutation-gate-for-tests (SPEC-0181) | 50 | 1 | 49 | 0 | 1 | 0 |
| spec-close-ceremony-sweep (SPEC-0182) | 84 | 74 | 10 | 30 | 44 | 0 |
| spec-update-installs-ref-guard-undisclosed (SPEC-0184) | 43 | 12 | 31 | 4 | 7 | 1 |
| spec-friction-channel-sweep (SPEC-0185) | 25 | 8 | 17 | 0 | 0 | 8 |
| spec-canon-is-a-build-artifact (SPEC-0186) | 27 | 0 | 27 | 0 | 0 | 0 |

SPEC-0185 and SPEC-0186 have no evidence directory on any machine reachable
from here (their rides ran in worktrees), so they degrade before any row is
read.

## Decisions

**D1 — one grammar, in one module.** The sed-expression grammar currently
inlined in `mutation-run.mjs` `applySedExpr` moves into
`lib/mutation-record.mjs` (the module that already exists so a producer and a
consumer cannot each invent their own idea of the record) and is imported by
both the applier and the gate's extractor. A declaration the gate is willing to
compare is by construction an expression the runner is able to apply.

**D2 — extraction is grammar-anchored, and ambiguity fails to UNCOMPARABLE.**
`extractDeclaredMutations(cell)` scans the cell (after unescaping markdown
`\``) for:
- `sed:s/<pat>/<repl>/<flags>` using the applier's own character classes, with
  flags restricted to `[gimsuy]*` and a `(?![A-Za-z])` boundary;
- `patch:<path>.patch`.
An expression whose boundary cannot be closed yields NO token, so the row lands
in the counted UNCOMPARABLE class rather than being accused of a mismatch. The
fail-safe direction is deliberate: the gate may say "I did not look", never
"you lied" on its own parsing ambiguity.

**D3 — comparison is exact after whitespace canonicalization only.**
`canonicalizeMutation(s)` collapses internal whitespace runs to one space and
trims. Nothing else — in particular backslashes are significant. An
escape-insensitive compare would accept `sed:s/split(X)/.../` for a record that
ran `sed:s/split\(X\)/.../`, which is a DIFFERENT regex that would not have
matched the source: accepting it would re-open the same hole one notch lower.
28 of the 52 mismatching legacy rows differ only by dropped backslashes, and
that is exactly the sloppiness that must stop counting as evidence.

**D4 — a cell may declare more than one token; the record must match one.**
Rows exist whose cell preserves a rotated round-4 mutation beside the live
round-5 one (TEST-497). Matching ANY declared token satisfies the row.

**D5 — UNCOMPARABLE is its own visible class, never satisfied.** Uncomparable
rows still owe every existing check (record parses, `test_id`, `suite`,
`verdict: RED`, ancestry, `target_sha256`). They are simply never counted in
`satisfied`, are each NAMED on stdout, and carry their own summary token.

**D6 — the ratchet lives in the spec's own frontmatter.**
`mutation_uncomparable: <int>` (absent means 0) is the per-spec baseline.
Actual above baseline refuses; equal passes; below passes and prints a NOTE
naming the lower number. It lives in the spec because that is the document a
reviewer is already reading when the rows are written, it travels with the
spec, and it needs no new file (so neither companion obligation — the prompt
diet ledger, the PROFILES classification — is triggered).

**D7 — the ratchet reads committed text only, so it applies even under the
evidence-tree-absent degrade.** Row text is committed; records are not. Making
the ratchet evidence-independent is what makes it trustworthy on a fresh clone
or in CI. This is the one place a `DEGRADED` run can now exit 5.

**D8 — mismatch is never baselineable.** There is no grandfather list for the
52 drifted rows. See "Day one".

## Day one — what happens to the 5 existing specs' 229 rows

- **On any checkout without the gitignored evidence tree** (CI, a fresh clone,
  this worktree): unchanged for the RED-record half — all 5 specs still take
  `DEGRADED: evidence tree absent` at exit 0. The ratchet (D7) additionally
  runs; with the baselines this ride stamps (49 / 10 / 31 / 17 / 27) all 5
  pass.
- **On the owner's main checkout**, which holds evidence for SPEC-0181,
  SPEC-0182 and SPEC-0184: 34 rows match, 134 are counted UNCOMPARABLE at
  baseline, and **52 rows would newly be OFFENDING** (exit 5). Those 3 specs
  are already closed and nothing re-runs the gate over a closed spec, so no
  scheduled ride is blocked; but a ride that RE-closes one of them (an
  amendment ride on the same capability) will be refused until each named row
  is either re-run through `mutation-run.mjs` or its cell amended to the
  expression that actually ran. That is the defect surfacing, and this spec
  deliberately does not offer a way to silence it.
- **For the next NEW spec**: a gated spec whose Test Plan carries prose-only
  Mutation cells now fails its own close unless the author either writes
  machine-readable cells or declares `mutation_uncomparable: N` in the
  frontmatter, where N is visible in the spec under review. This is the
  intended friction and it is the one behaviour change a future ride will feel.
- **For this ride**: every Mutation cell in the Test Plan below is
  machine-readable, so this spec's own baseline is 0. Because D3 compares
  exactly, the implementer must reconcile each cell with the expression
  `mutation-run.mjs` actually recorded, through the existing amendment
  convention (`spec-amend.mjs add` + restamp) — a planning-time guess that
  drifts by one character is a self-inflicted GATE FAIL.

## Constitution deviations

None.

## Acceptance Criteria Mapping

- Spec-AC-01: WHEN a row's cell declares a mutation and the record's `mutation`
  does not canonically equal any declared token THEN the gate reports the row
  as OFFENDING, names both the declared and the recorded value, and exits 5.
  - Verification: `bash tests/skills/test-aai-mutation-gate.sh
    test_701_gate_compares_declared_mutation`; the fixture's stdout carries
    `OFFENDING TEST-9001:` with both values and the run exits 5.
- Spec-AC-02: WHEN the record's `mutation` canonically equals one of the cell's
  declared tokens (including a cell that declares two) THEN the row is counted
  in `satisfied` and the gate exits 0.
  - Verification: same suite, `test_702_gate_accepts_matching_declaration`;
    `GATE PASS: 2 row(s) satisfied` and exit 0.
- Spec-AC-03: WHEN two spellings of a declaration differ only by whitespace or
  surrounding backticks THEN they compare equal, AND WHEN they differ by a
  backslash escape THEN they do not.
  - Verification: same suite, `test_703_canonicalization_boundaries`; the
    whitespace arm exits 0, the backslash arm exits 5.
- Spec-AC-04: WHEN a row's cell declares no machine-readable mutation THEN the
  gate prints `UNCOMPARABLE <TEST-id>:` for it, carries `uncomparable=<n>` in
  the summary line, and EXCLUDES the row from the `satisfied` count.
  - Verification: same suite, `test_704_uncomparable_class_is_named`; a
    2-row fixture with one prose cell prints
    `GATE PASS: 1 row(s) satisfied degraded=0 unstamped=0 uncomparable=1` and
    one `UNCOMPARABLE` line.
- Spec-AC-05: WHEN the uncomparable count exceeds the spec's
  `mutation_uncomparable` frontmatter value (absent equals 0) THEN the gate
  exits 5 with an `OFFENDING <spec-id>:` line naming actual, baseline and the
  remedy; WHEN it equals the value the gate exits 0; WHEN it is below the value
  the gate exits 0 and prints `NOTE: mutation_uncomparable ... can be lowered
  to <n>`.
  - Verification: same suite, `test_705_uncomparable_ratchet`; three arms, exit
    5 / 0 / 0, and `node .aai/scripts/spec-lint.mjs --path <fixture>` reports no
    finding naming `mutation_uncomparable`.
- Spec-AC-06: WHEN an applicable spec's evidence directory is absent THEN the
  gate still evaluates the ratchet — exit 5 naming the spec when the count
  exceeds the baseline, and the unchanged `DEGRADED: evidence tree absent`
  at exit 0 when it does not.
  - Verification: same suite, `test_706_ratchet_without_evidence_tree`; two
    arms, exit 5 and exit 0, the exit-0 arm's summary line still starting
    `DEGRADED: evidence tree absent`.
- Spec-AC-07: The sed-expression grammar has exactly one definition: an
  expression `extractDeclaredMutations` yields is accepted by the runner's
  applier, and an expression the applier refuses is never yielded as a
  declaration.
  - Verification: same suite, `test_707_one_sed_grammar`; the arm feeds the
    same three expressions to the exported grammar and to a real
    `mutation-run.mjs` run in a fixture repo and asserts the two agree;
    `/usr/bin/grep -c 'want s/pattern/replacement/' .aai/scripts/mutation-run.mjs`
    is 0 (the inline copy is gone).
- Spec-AC-08: WHEN a closing ride's spec reports `uncomparable=<n>` with n
  greater than 0 THEN `close-work-item.mjs` names that count in its mutation
  gate notice rather than closing silently.
  - Verification: `bash tests/skills/test-aai-close-work-item.sh
    test_708_close_surfaces_uncomparable`; the close's stderr WARNING carries
    `uncomparable=1`.
- Spec-AC-09: The 5 gated specs each carry a `mutation_uncomparable` value
  equal to the count the shipped classifier measures for them.
  - Verification: same mutation-gate suite,
    `test_709_live_corpus_baselines_are_measured`; the arm recomputes each
    spec's uncomparable count with the exported classifier and asserts equality
    with the frontmatter value for all 5.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                  | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | WHEN a declared mutation does not match the record THEN the row is OFFENDING naming both values, exit 5        | planned | —        | —         | —     |
| Spec-AC-02 | WHEN the record matches any declared token THEN the row counts as satisfied                                    | planned | —        | —         | —     |
| Spec-AC-03 | Canonicalization equates whitespace and backticks and keeps backslashes significant                            | planned | —        | —         | —     |
| Spec-AC-04 | An undeclarable cell is NAMED and counted as uncomparable and never counted as satisfied                       | planned | —        | —         | —     |
| Spec-AC-05 | The uncomparable count is ratcheted against the spec's own frontmatter baseline                                | planned | —        | —         | —     |
| Spec-AC-06 | The ratchet holds on a checkout with no evidence tree                                                          | planned | —        | —         | —     |
| Spec-AC-07 | One sed grammar shared by the runner's applier and the gate's extractor                                        | planned | —        | —         | —     |
| Spec-AC-08 | The close ceremony names a non-zero uncomparable count instead of closing silently                             | planned | —        | —         | —     |
| Spec-AC-09 | The 5 live gated specs carry measured baselines                                                                | planned | —        | —         | —     |

## Implementation plan

Components and order:

1. `.aai/scripts/lib/mutation-record.mjs` — add `SED_EXPR_RE`,
   `parseSedExpr(expr)`, `SED_DECL_RE`, `PATCH_DECL_RE`,
   `extractDeclaredMutations(cellText)` and `canonicalizeMutation(s)`. No
   change to `formatRecord`/`parseRecord` and no new record field.
2. `.aai/scripts/mutation-run.mjs` — `applySedExpr` uses `parseSedExpr` instead
   of its inline regex; behaviour and error text otherwise unchanged.
3. `.aai/scripts/mutation-gate.mjs` — inside the per-row loop, AFTER the
   existing test_id / suite / verdict / ancestry checks and BEFORE the
   `target_sha256` staleness checks: classify the row as comparable or
   uncomparable and, when comparable, compare. Uncomparable rows are collected
   like `exempt` rows; `satisfied` becomes `rows - exempt - uncomparable`;
   `uncomparable=<n>` is appended to the summary line immediately after
   `unstamped=<n>` (before the optional ` exempt=<n>`, so the existing
   `exempt=` / `degraded=` / `unstamped=` regexes in close-work-item.mjs keep
   matching); `UNCOMPARABLE <id>: ...` lines print unconditionally alongside the
   `EXEMPT` lines; the JSON payload gains `uncomparable`, `uncomparable_rows`
   and `uncomparable_baseline`.
4. `.aai/scripts/mutation-gate.mjs` — the ratchet, evaluated for every
   applicable spec including on the evidence-absent degrade path (D7), emitting
   an `OFFENDING <spec-id>: ...` line so close-work-item's existing
   `OFFENDING ` filter reports it unchanged.
5. `docs/specs/SPEC-0181/0182/0184/0185/0186` — add
   `mutation_uncomparable: 49 / 10 / 31 / 17 / 27` to the frontmatter
   (re-measured by the shipped classifier at implementation time; if a number
   differs from this spec's, the shipped measurement wins and the difference is
   disclosed).
6. `.aai/scripts/close-work-item.mjs` — read `uncomparable=(\d+)` from the
   summary line, add it to the notice trigger and to `formatMutationNotice`.
   **This file is content-hash pinned**: `tests/skills/lib/close-work-item-pin.sh`
   needs a new `CLOSE_WORK_ITEM_ALLOWED_HASHES` entry re-affirming both frozen
   invariants (exit contract unchanged at 0..8; the D6 snapshot/rollback
   transaction and its four regen calls untouched). Do this step LAST and in
   one commit — a stale pin reddens four suites.
7. `tests/skills/test-aai-mutation-gate.sh` and
   `tests/skills/test-aai-close-work-item.sh` — the arms below, registered in
   each suite's `main()`.

Edge cases:
- A row that is EXEMPT (`deferred`/`dropped`/`rejected`) is still exempted
  first and is never classified, counted or compared.
- A row that already fails an existing check (missing record, wrong `suite`,
  not RED, non-ancestor base) keeps its existing reason; the comparison never
  replaces an existing diagnosis.
- `mutation_uncomparable` with a non-integer or negative value is a gate error
  (exit 3) naming the spec, never a silent 0.
- A `patch:` declaration compares by path only; the patch file's CONTENT is not
  hashed (see Residual risks).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                       | Description                                                                                                                                                              | Mutation                                                                                                                       | Status  |
|----------|------------|-------------|--------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------------------------------------------------|--------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-701 | Spec-AC-01 | integration | tests/skills/test-aai-mutation-gate.sh     | A fixture row declaring `sed:s/A/B/` whose record carries `sed:s/C/D/` is OFFENDING, the reason names declared and recorded, and the gate exits 5                          | sed:s/if \(!declaredTokens\.includes\(recordedCanon\)\)/if (false)/                                                            | green |
| TEST-702 | Spec-AC-02 | integration | tests/skills/test-aai-mutation-gate.sh     | A row whose record equals its single declared token, and a row whose record equals the second of two declared tokens, are both satisfied and the gate exits 0              | sed:s/if \(!declaredTokens\.includes\(recordedCanon\)\)/if (declaredTokens[0] !== recordedCanon)/                              | green |
| TEST-703 | Spec-AC-03 | integration | tests/skills/test-aai-mutation-gate.sh     | A declaration differing from the record only by whitespace and wrapping backticks matches; one differing by a backslash escape does not                                    | sed:s/replace\(\/\\s\+\/g, ' '\)\.trim\(\)/replace(\/\s+\/g, ' ')/                                                             | green |
| TEST-704 | Spec-AC-04 | integration | tests/skills/test-aai-mutation-gate.sh     | A two-row fixture with one prose cell prints one UNCOMPARABLE line, carries uncomparable=1 in the summary and counts only 1 satisfied                                      | sed:s/if \(uncomparableIdSet\.has\(row\.testId\)\)/if (false)/                                                                 | green |
| TEST-705 | Spec-AC-05 | integration | tests/skills/test-aai-mutation-gate.sh     | Ratchet arms above, at and below the frontmatter baseline give exit 5 with the OFFENDING spec line, exit 0, and exit 0 with the lower-the-baseline NOTE; spec-lint is quiet | sed:s/ratchetActual > uncomparableBaseline/false/                                                                              | green |
| TEST-706 | Spec-AC-06 | integration | tests/skills/test-aai-mutation-gate.sh     | With the evidence directory absent, a grown uncomparable count exits 5 while a count at baseline keeps the DEGRADED evidence-tree-absent line at exit 0                    | sed:s/ratchetActual > uncomparableBaseline/false/                                                                              | green |
| TEST-707 | Spec-AC-07 | integration | tests/skills/test-aai-mutation-gate.sh     | The same three expressions are accepted or refused identically by the exported grammar and by a real mutation-run.mjs run, and mutation-run carries no second copy         | sed:s/\[gimsuy\]\*/[a-z]*/                                                                                                     | green |
| TEST-708 | Spec-AC-08 | integration | tests/skills/test-aai-close-work-item.sh   | A close whose spec reports uncomparable=1 prints that count in the mutation gate WARNING instead of closing silently                                                       | sed:s/uncomparableN > 0/false/                                                                                                 | green |
| TEST-709 | Spec-AC-09 | integration | tests/skills/test-aai-mutation-gate.sh     | Each of the 5 live gated specs carries a mutation_uncomparable equal to the count the shipped classifier measures over its committed rows                                  | sed:s/mutation_uncomparable: 10/mutation_uncomparable: 11/                                                                     | green |

Notes on the Mutation column: each expression above targets the code the row
proves and was written against the implementation plan, not against code that
exists yet. Per D3 the gate compares these cells EXACTLY, so the implementer
reconciles each cell with the expression `mutation-run.mjs` records, disclosing
the change through `spec-amend.mjs add`. TEST-709's mutation targets
docs/specs/SPEC-0182-spec-close-ceremony-sweep.md (a committed baseline value),
which is the only way to redden a corpus-consistency assertion.

## Seams

- **S1 — the gate's extractor and the runner's applier share one grammar.**
  Produced on one side (an expression the extractor yields from a cell),
  asserted on the other (a real `mutation-run.mjs` run in a fixture repo
  applies it). TEST-707. Two unit tests over two regexes would test the two
  regexes, which is the drift being prevented.
- **S2 — the gate's summary line is parsed by `close-work-item.mjs`.**
  `evaluateMutationGate` matches `exempt=`, `degraded=` and `unstamped=` with
  its own regexes and only raises a notice when exempt or unstamped is
  non-zero. A new token nobody reads is the hole moved, not closed. TEST-708
  produces on the gate side and asserts on the close's printed WARNING, through
  the real shell-out, never a stub.
- **S3 — a new frontmatter key crosses spec-lint, spec-freeze and docs-audit.**
  No frontmatter key allowlist exists (only `status` values are validated), so
  the risk is a lint finding rather than a refusal. TEST-705 runs the real
  `spec-lint.mjs --path` over a fixture carrying the key and asserts no finding
  names it.
- **S4 — the ratchet crosses the degrade short-circuit.** The evidence-absent
  path previously returned before any row was read; it now evaluates the
  ratchet. TEST-706 asserts both that the grown count refuses there and that
  the unchanged degrade line and exit 0 survive when it does not.

## Residual risks

- **R1 — order of evidence is still not proved.** An author can paste the
  record's `mutation` into the cell after the run. Only `mutation-run.mjs
  --replay` re-applies a recorded mutation, and the close ceremony does not run
  it (NB8-r2). This change proves declared equals recorded, never that declared
  came first.
- **R2 — 52 drifted legacy rows stay drifted.** They are named the moment their
  spec is re-closed, and are not silenced. Draining them is a separate ride.
- **R3 — escape-sensitivity produces loud false alarms on equivalent-looking
  declarations.** Accepted by D3; the OFFENDING line prints both values, which
  is the remedy.
- **R4 — a `patch:` declaration is compared by path, not content.** A patch
  file edited after the run still matches its cell. `target_sha256` covers the
  target, not the patch.
- **R5 — records are gitignored** (`fu-mutation-evidence-is-gitignored`), so
  the comparison half only ever runs where the evidence was produced. Only the
  ratchet is machine-independent. NOT closed by this scope.
- **R6 — a mutation containing a pipe character cannot be declared at all**: the
  Test Plan table parser splits the row on it. Such a row is permanently
  uncomparable and must be carried in the baseline.

## Verification

- `bash tests/skills/test-aai-mutation-gate.sh` — exit 0.
- `bash tests/skills/test-aai-close-work-item.sh` — exit 0.
- `bash tests/skills/test-aai-doc-numbering.sh` and
  `bash tests/skills/test-aai-follow-ups.sh` — exit 0 (both pin
  close-work-item.mjs; they prove step 6's re-pin).
- `bash tests/skills/test-aai-layer-profiles.sh` — exit 0 (no new `.aai/**`
  file, so the classification set is unchanged).
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-gate-checks-declared-mutation.md`
  — exit 0.
- `node .aai/scripts/mutation-gate.mjs --spec <each of the 5 gated specs>` —
  exit 0 in this worktree (no evidence tree), with `uncomparable=` present in
  every summary line.
- PASS criteria: all TEST-xxx green AND all Spec-AC terminal AND a RED record
  under docs/ai/tdd/spec-gate-checks-declared-mutation/ for each of the 9 rows.

## Evidence contract

- ref_id: gate-checks-declared-mutation
- Per TEST-xxx: the `mutation-run.mjs` record at
  docs/ai/tdd/spec-gate-checks-declared-mutation/mutation-TEST-70N.txt, carrying
  `verdict: RED` and the expression the Mutation cell declares.
- Per Spec-AC: the suite command above, its exit code, and the assertion text
  that names the observable.
- Review scope: the branch diff fix/gate-checks-declared-mutation..main over
  `.aai/scripts/mutation-gate.mjs`, `.aai/scripts/mutation-run.mjs`,
  `.aai/scripts/lib/mutation-record.mjs`, `.aai/scripts/close-work-item.mjs`,
  `tests/skills/lib/close-work-item-pin.sh`,
  `tests/skills/test-aai-mutation-gate.sh`,
  `tests/skills/test-aai-close-work-item.sh` and the 5 gated specs' frontmatter.

### Evidence by strategy

Strategy `tdd`: a stored RED artifact per AC-gating test plus the full
verification matrix.

## Registry items closed by this scope

- `fu-gate-ignores-declared-mutation` (P2) — closed by Spec-AC-01..05.

Open items in the same neighbourhood, explicitly NOT closed:
- `fu-mutation-evidence-is-gitignored` (P3) — whether mutation evidence stops
  being gitignored is an owner policy decision, out of scope (intake).
- `fu-mutation-gate-absent-tree-passes` (P2) — the RED-record requirement still
  degrades vacuously without an evidence tree. Spec-AC-06 makes only the
  ratchet evidence-independent; it does not make the gate meaningful on a
  fresh clone.
- `fu-mutation-sed-drops-multiline-flag` (P2) — the applier still honours only
  `g`. D1 moves the grammar without changing which flags it applies.
- `fu-sed-replacement-dollar-trap` (P3) — `applySedExpr` keeps the string form
  of `String.replace`; this scope moves the expression PARSER, not the applier's
  replacement call.

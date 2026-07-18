---
id: spec-spec-lint-enforce-spec-id-prefix
type: spec
number: 58
status: implementing
ceremony_level: 1
links:
  requirement: ISSUE-0016
  rfc: null
  pr: []
  commits: []
---

# Spec: spec-lint flags a collision-prone bare-slug spec id (`spec-id-shape`)

SPEC-FROZEN: true

Reserved display number (cross-branch collision check, RFC-0007): SPEC-0058.
Verified 2026-07-18 free across local `docs/specs/` (highest is SPEC-0057), every
`refs/aai/docnums/SPEC-*` reservation ref (highest reserved SPEC-0057), and every
remote branch tree (`git ls-tree` scan found no `SPEC-0058*`). The sequential
integer is minted/reserved at merge by `allocate-doc-number.mjs`; this file stays
`SPEC-DRAFT-<slug>.md` with `number: null` in-branch. The slug id is
`spec-`-prefixed (`spec-spec-lint-enforce-spec-id-prefix`) so it can NEVER collide
with the intake's id (`spec-lint-enforce-spec-id-prefix`) — this spec is itself
compliant with the very rule it adds, and it lints CLEAN under its own new check.

Ceremony justification: additive per-spec lint check in one script
(`spec-lint.mjs`) + regression stanzas; no engine/protected-path change.
`spec-lint.mjs` is verified NOT in `protected_paths_l3` (docs/ai/docs-audit.yaml:
state engine, allocator, guards, WORKFLOW.md, CONSTITUTION.md). Report-only tool
(never a hard gate, RFC-0002 posture), single surface, reversible → L1 lean lane.

## Links
- Requirement: docs/issues/ISSUE-0016-spec-lint-enforce-spec-id-prefix.md
- Origin: the spec-id collision cascade (ISSUE-0015 remediation + SPEC-0057
  duplicate-doc-id detector + close-work-item.mjs fail-closed); decisions.jsonl
  process_findings (2026-07-18). This is the earliest-point prevention completing
  the duplicate-id defence-in-depth: detect at audit (SPEC-0057) + fail-closed at
  close (close-work-item.mjs) + LINT at freeze (this spec).
- Technology contract: docs/TECHNOLOGY.md

## Problem
`spec-lint.mjs` checks intra-spec STRUCTURE but never the SHAPE of a spec's
frontmatter `id`. A spec authored with a bare-slug id — neither the legacy
numbered `SPEC-NNNN` form nor a `spec-`-prefixed slug — shares its originating
change/issue's id, the root cause of the 4 spec-id collisions found this session
(SPEC-0056 + SPEC-0048/0049/0051). The collision surfaces only LATE (docs-audit
NEEDS-TRIAGE, or a fail-closed close). `spec-lint` runs per-spec at freeze — the
earliest point — so a `spec-id-shape` finding there prevents the id from ever
shipping.

## Design: the frozen predicate (freeze exactly)

### The check (frozen)
Added inside the pure `lintContent(content)` function (the same finding set as
`ceremony-level-invalid`, `ac-id-*`, `test-ac-*`, `delta-*`), immediately after
`const fm = parseFrontmatter(norm) ?? {}`. It emits at most one finding per doc:

- Type guard (frozen): the check runs ONLY when
  `String(fm.type ?? '').toLowerCase() === 'spec'`. This matters in `--path` mode,
  where `lintContent` is invoked on a doc of ANY type; a non-spec doc (rfc,
  research, issue) with a bare-slug id is NEVER flagged. (In the default scan,
  `main()` already restricts to `type: spec` docs; the internal guard makes the
  restriction hold under `--path` too.)
- `id = String(fm.id ?? '')`.
- `numbered = /^SPEC-\d+$/i.test(id)` — the legacy numbered `SPEC-NNNN` form,
  case-insensitive (matches `SPEC-0001`), which never collides with a change id.
- `prefixed = id.startsWith('spec-')` — the disambiguated lowercase `spec-<slug>`
  form (case-sensitive lowercase: this is the convention, and it makes the two
  predicate arms genuinely independent — the numbered form is uppercase `SPEC-`
  and is exempted only by `numbered`, not by `prefixed`).
- Emit `add('spec-id-shape', <detail>)` when `id !== '' && !numbered && !prefixed`.
  The detail NAMES the id and gives the `spec-<change-slug>` guidance, e.g.:
  `spec id "<id>" is a bare slug (neither the numbered SPEC-NNNN form nor a
  spec-<slug> id) — rename it to spec-<change-slug> so it cannot collide with its
  change/issue id`.
- Empty/missing id is NOT flagged (frozen boundary): a missing frontmatter `id` is
  a lifecycle/schema concern owned by docs-audit, not intra-spec structure. Guard
  on `id !== ''` so spec-lint and docs-audit do not double-report.

### Emission / exit shape (frozen)
`spec-id-shape` is an ordinary member of the returned findings array. It therefore
contributes to the report-only exit contract UNCHANGED: exit 1 when the aggregate
findings set is non-empty, exit 0 when clean; never a hard gate; `--json` includes
it in `findings`. No new flag, no new mode (contrast `--slug-handles`, which IS a
separate opt-in mode — this check is NOT).

### Self-consistency (frozen note)
This spec's own id (`spec-spec-lint-enforce-spec-id-prefix`) is `spec-`-prefixed,
so it passes the new check; once merged as SPEC-0058 it is part of the real corpus
that Spec-AC-03's loop asserts clean.

## Scope
- In scope: `.aai/scripts/spec-lint.mjs` (ADD the `spec-id-shape` check to
  `lintContent`; nothing else changed), `tests/skills/test-aai-spec-lint.sh` (new
  stanzas + the mechanical fixture-id alignment below), and this spec + the
  ISSUE-0016 AC table.
- Out of scope: every existing spec-lint rule (unchanged); the `--slug-handles`
  mode; docs-audit's duplicate-doc-id detection (SPEC-0057) and close-work-item's
  fail-closed check (both remain — this is the third, earliest layer); the
  advisory wiring in PLANNING/VALIDATION (already invoke `spec-lint.mjs`; the new
  finding rides the existing invocation, no prompt edit); renaming any real doc.
- Protected paths touched: none (`spec-lint.mjs` verified NOT in
  `protected_paths_l3`).

### Fixture-id alignment (frozen implementation constraint — resolves a real
### tension with "existing stanzas unchanged")
The existing suite's `type: spec` fixtures all use BARE-SLUG ids (`fixture-clean`
in the shared `clean_spec_body` helper; `fixture-lean`, `fixture-escpipe`,
`fixture-compact`, `fixture-dupac-*` in inline heredocs). Empirically (verified
2026-07-18) ALL 9 would be flagged by the new check, breaking ~10 expect-clean
control stanzas. Because a test fixture is structurally identical to a real
bare-slug spec (that is WHY it is a good fixture), NO production-code-only design
can exempt them. Resolution (frozen): mechanically `spec-`-PREFIX every fixture
`type: spec` id (helper + heredocs) and the two `sed` id-rewrite expressions
(`id: fixture-clean` → `id: spec-fixture-clean`, `id: fixture-b` →
`id: spec-fixture-b`). This is behavior-preserving: every existing assertion (exit
codes, target-finding greps, `--json` scanned/findings counts) stays satisfied —
only the fixture id STRING values change, dogfooding the very rule. The literal
"existing stanzas unchanged" is thus relaxed to "existing stanza ASSERTIONS and
COVERAGE unchanged; fixture `id:` values receive a mechanical `spec-` prefix." See
Blocking / decisions for the operator heads-up.

## Implementation strategy
- Strategy: tdd
- Rationale: a NEW governance-integrity detection rule whose value depends on it
  actually FIRING — a never-failed test could be tautological (self-evaluation
  trap). RED-proof is natural and required: a bare-slug fixture yields NO
  `spec-id-shape` finding (exit 0) against the pre-change lint (RED); the same
  fixture is flagged with exit 1 (GREEN). Sibling detector SPEC-0057 set the tdd
  precedent for exactly this shape.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: small, additive, single-script change; no migration, no
  protected path, reversible. STATE already records `worktree.user_decision:
  inline`, `base_ref: main` (operator-approved wave). No user decision required.
- User decision: inline (already recorded)
- Base ref: main
- Worktree branch/path: inline (operator wave)
- Inline review scope: `.aai/scripts/spec-lint.mjs`,
  `tests/skills/test-aai-spec-lint.sh`,
  `docs/specs/SPEC-0058-spec-spec-lint-enforce-spec-id-prefix.md`,
  `docs/issues/ISSUE-0016-spec-lint-enforce-spec-id-prefix.md`

## Acceptance Criteria Mapping
- Maps to: ISSUE-0016 AC-001
- Spec-AC-01: For a `type: spec` doc whose `id` is a bare slug (not `/^SPEC-\d+$/i`
  and not `spec-`-prefixed), `spec-lint` emits exactly one `spec-id-shape` finding
  whose detail NAMES the id and gives the `spec-<change-slug>` guidance, and the
  process exits 1.
  - Verification: `bash tests/skills/test-aai-spec-lint.sh` (new bare-slug stanza)
    -> exit 0. RED-proof: the same bare-slug fixture observed producing NO
    `spec-id-shape` finding and exit 0 against the pre-change `spec-lint.mjs`.

- Maps to: ISSUE-0016 AC-002 (no false positives; only type:spec checked)
- Spec-AC-02: No false positives. (a) A `spec-`-prefixed id and a legacy numbered
  `SPEC-NNNN` id each lint CLEAN (no `spec-id-shape`). (b) The check applies ONLY
  to `type: spec` docs: a non-spec doc (e.g. `type: research`) carrying a bare-slug
  id, linted via `--path`, is NOT flagged.
  - Verification: `bash tests/skills/test-aai-spec-lint.sh` (new negative-control
    stanzas) -> exit 0; the `spec-`-prefixed and numbered fixtures show no
    `spec-id-shape`; the non-spec `--path` fixture shows no `spec-id-shape`.

- Maps to: ISSUE-0016 AC-002 (clean corpus; existing suite green)
- Spec-AC-03: Running `spec-lint` over EVERY real `docs/specs/SPEC-*.md` yields
  ZERO `spec-id-shape` findings (the corpus is clean post ISSUE-0015 remediation —
  verified 2026-07-18: all 57 spec ids are numbered or `spec-`-prefixed), and the
  full existing `test-aai-spec-lint.sh` suite stays green after the mechanical
  fixture-id alignment (all prior assertions/coverage intact).
  - Verification: `bash tests/skills/test-aai-spec-lint.sh` (new real-corpus loop
    stanza) -> exit 0; `.aai/scripts/aai-run-tests.sh bash
    tests/skills/test-aai-spec-lint.sh` -> exit 0 (whole suite).

## Constitution deviations

None.

<!-- Art.1 evidence-before-claims: measurable AC + TEST-xxx with mandatory
  RED-proof; no PASS in planning. Art.2 KISS/YAGNI: one predicate (two regex/prefix
  arms) added to lintContent; no new mode, no new flag. Art.3 portability: plain
  .mjs + bash fixture, git-diffable. Art.4 degrade-and-report: report-only advisory
  finding (exit 1 on findings), never a hard gate. Art.5 additive: purely additive
  finding rule; every existing rule, exit contract, and --json shape unchanged.
  Art.6 single-writer: STATE via state.mjs only. Art.7 operator-only merge: planning
  does not merge. -->

## Seam analysis
- Real-corpus seam: the new rule runs over the whole `docs/specs/` corpus in the
  default scan and via the existing TEST-009 real-corpus arm (`runlint
  "$PROJECT_ROOT"` -> exit 0). A regression here would flip the live repo to
  findings. Covered end-to-end by TEST-004 (an explicit loop over every real
  `docs/specs/SPEC-*.md` asserting zero `spec-id-shape`, over REAL docs, not a
  mock) and by the pre-existing TEST-009 staying green — the mandated integration
  coverage across the tool↔corpus boundary.
- Self-referential seam: this spec becomes SPEC-0058 in that same corpus; its
  `spec-`-prefixed id keeps TEST-004 green after merge (verified: predicate flags 0
  of the current 57 + this one).
- No automatable-gap residual risk: the check is a pure function over frontmatter;
  both the positive and every negative face are covered by TEST-001..004.

## Acceptance Criteria Status

| Spec-AC    | Description                                                                                                   | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Bare-slug `type: spec` id -> one `spec-id-shape` finding naming the id + `spec-<change-slug>` guidance; exit 1 | done | docs/ai/tdd/red-20260718T153835Z.log, docs/ai/tdd/green-20260718T153949Z.log (TEST-001) | — | RED-proofed |
| Spec-AC-02 | No false positives: `spec-`-prefixed and numbered `SPEC-NNNN` ids lint clean; only `type: spec` docs checked (non-spec `--path` doc not flagged) | done | docs/ai/tdd/green-20260718T153949Z.log (TEST-002, TEST-003) | — | — |
| Spec-AC-03 | Every real `docs/specs/SPEC-*.md` -> zero `spec-id-shape`; full existing suite green after fixture-id alignment | done | docs/ai/tdd/green-20260718T153949Z.log (TEST-004, TEST-005) | — | — |

## Implementation plan
- Components/modules affected:
  - `.aai/scripts/spec-lint.mjs`: inside `lintContent`, after the `fm` parse, add
    the type-guarded `spec-id-shape` check (numbered-form regex + lowercase
    `spec-` prefix; skip empty id). No other function touched; `main()`, the
    default scan, `--path`, `--json`, and `--slug-handles` are all unchanged.
  - `tests/skills/test-aai-spec-lint.sh`: mechanical `spec-`-prefix of all fixture
    `type: spec` ids (helper `clean_spec_body` + inline heredocs) and the two `sed`
    id rewrites; then ADD the new stanzas below.
- Data flow: `parseFrontmatter(norm)` -> `{ type, id }` -> guarded predicate ->
  `findings[]` -> exit code / `--json` (all existing plumbing).
- Edge cases: empty/missing id (skipped — docs-audit's boundary); mixed-case
  `Spec-foo` (flagged — not the lowercase convention, guidance points to
  `spec-<slug>`); numbered `SPEC-0001` (exempt via `numbered`, even though it is
  not lowercase-`spec-`-prefixed); a non-spec doc via `--path` (type guard skips
  it); a `spec-`-prefixed id that also happens to be long/odd (passes — prefix is
  the only requirement).

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                                                                                                              | Status  |
|----------|------------|-------------|-------------------------------------|------------------------------------------------------------------------------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-spec-lint.sh  | Bare-slug fixture (`id: secrets-preflight-env-multiline`, otherwise clean) -> exactly one `spec-id-shape` finding naming the id + `spec-<slug>` guidance; exit 1. RED-gating: pre-change lint yields no `spec-id-shape` and exit 0. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh  | Negative controls: a `spec-`-prefixed id fixture AND a numbered `SPEC-NNNN` id fixture each lint CLEAN (no `spec-id-shape`, exit 0).                                       | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-spec-lint.sh  | Type guard: a `type: research` doc with a bare-slug id, linted via `--path`, emits NO `spec-id-shape` finding (only `type: spec` docs are checked).                        | green |
| TEST-004 | Spec-AC-03 | integration | tests/skills/test-aai-spec-lint.sh  | Real-corpus loop: for every real `docs/specs/SPEC-*.md`, running spec-lint asserts ZERO `spec-id-shape` findings (corpus clean post-remediation; includes this spec once merged). | green |
| TEST-005 | Spec-AC-03 | integration | tests/skills/test-aai-spec-lint.sh  | Full-suite regression: the entire `test-aai-spec-lint.sh` suite stays green after the mechanical fixture-id alignment (every prior assertion/coverage intact).             | green |

Notes:
- Every Spec-AC has >=1 TEST-xxx. TEST-001/002/003/005 are hermetic-fixture
  stanzas (own mktemp root, like the existing suite); TEST-004 probes the real
  `docs/specs/` read-only.
- RED-proof obligation (Art.1 / step-6 RED-proof): TEST-001 MUST be observed
  FAILING against the pre-change `spec-lint.mjs` (bare-slug fixture NOT flagged,
  exit 0) before its GREEN counts as evidence. TEST-002/003's clean arms are green
  pre-change (the rule flags nothing yet) — that alone is NOT AC evidence; they
  gate once the rule exists (proving no over-flagging). TEST-004 is green
  pre-change (corpus already clean) and guards against future regression.
- Test IDs are stable — do not renumber after freeze.

## Verification
- `bash tests/skills/test-aai-spec-lint.sh` -> exit 0 (incl. new TEST-001..005).
- `.aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-spec-lint.sh` -> exit 0
  (whole suite; every pre-existing assertion green).
- `node .aai/scripts/spec-lint.mjs` (repo root) -> exit 0 with no `spec-id-shape`
  finding (real corpus clean).
- PASS criteria: all TEST-001..005 green; all Spec-AC in a terminal (`done`) status
  with non-empty Evidence; RED log captured for TEST-001.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: spec-lint-enforce-spec-id-prefix (SPEC-0058 at merge)
- Spec-AC and TEST-xxx links (Spec-AC-01/TEST-001, Spec-AC-02/TEST-002+003,
  Spec-AC-03/TEST-004+005)
- command or review scope
- exit code or review verdict
- evidence path (RED/GREEN logs under docs/ai/tdd/; review under docs/ai/reviews/)
- commit SHA or diff range when available

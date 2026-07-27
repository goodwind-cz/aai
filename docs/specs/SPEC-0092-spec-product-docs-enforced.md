---
id: spec-product-docs-enforced
type: spec
number: 92
status: implementing
ceremony_level: 2
links:
  requirement: product-docs-enforced
  rfc: null
  pr: []
  commits: []
---

# Spec — Product docs enforced at close + USER_GUIDE rollup generated from them

## Links
- Requirement: docs/issues/CHANGE-0066-product-docs-enforced.md (id: product-docs-enforced)
- Decision records: none
- Technology contract: docs/TECHNOLOGY.md
- Related mechanism: docs/specs/SPEC-0053-spec-deterministic-close-ceremony.md (the close ceremony this spec extends)

## Frontmatter status values
- draft: spec being written, not yet ready for implementation
- implementing: spec frozen, work in flight
- done: all Spec-AC reached terminal status; validation PASS recorded
- deferred: entire spec postponed; explain reason in this section
- rejected: spec was abandoned; explain rationale
- superseded: replaced by a newer spec; set links to the replacement

## Implementation strategy
- Strategy: tdd
- Rationale: The dominant risk is a pre-write refusal gate (a refusal is NOT a
  rollback path — it must fire BEFORE the close ceremony's first byte is
  written) plus byte-exact invariants (rollup idempotence + marker
  containment) and negative controls (a best-effort hook that must never change
  the close exit code). These are self-authored acceptance criteria over
  integrity-sensitive behavior, so every AC-gating test must be observed RED
  before it can count (self-evaluation trap). The few mechanical rows (PROFILES
  classification, template note, USER_GUIDE marker seeding) still admit natural
  RED proof (the layer-profiles conformance suite fails on an unclassified new
  file), so a single tdd strategy keeps the whole scope under one discipline.

## Isolation and review
- Worktree recommendation: recommended
- Worktree rationale: PR-bound work touching 3+ independent modules
  (close-work-item.mjs, a new generator, the shared guard-config reader, a
  template, PROFILES, USER_GUIDE, the dial doc, two test suites) INCLUDING an
  edit to a shared library (guard-config.mjs) imported by state.mjs and the
  allocator. A feature branch (feat/product-docs-enforced) already isolates the
  work, which satisfies the recommendation inline; the operator confirms in
  Implementation Preparation.
- User decision: undecided
- Base ref: main
- Worktree branch/path: feat/product-docs-enforced (branch already exists; inline-on-branch)
- Inline review scope: .aai/scripts/close-work-item.mjs, .aai/scripts/generate-userguide-rollup.mjs, .aai/scripts/lib/guard-config.mjs, .aai/templates/PRODUCT_TEMPLATE.md, .aai/system/PROFILES.yaml, docs/USER_GUIDE.md, docs/ai/docs-audit.yaml, tests/skills/test-aai-close-work-item.sh, tests/skills/test-aai-userguide-rollup.sh, docs/specs/SPEC-0092-spec-product-docs-enforced.md, docs/issues/CHANGE-0066-product-docs-enforced.md, CHANGELOG.md

Allowed worktree recommendation values:
- not_needed / optional / recommended / required (see SPEC_TEMPLATE)

## Key design decisions

### D1 — where `user_visible` lives (single authoritative source)
The `user_visible` trigger key lives on the PRIMARY work-item doc (the intake
change/issue/prd doc resolved by close-work-item.mjs `--ref`), as an optional
top-level frontmatter scalar `user_visible: true`. This is the single
authoritative source.

Justification:
- close-work-item.mjs ALWAYS resolves the `--ref` doc; `--spec` is OPTIONAL.
  Reading the trigger from the spec would silently fail-open on every close
  that omits `--spec`, producing an inconsistent gate. The primary doc is the
  only always-present anchor.
- The product doc convention already keys on the same slug
  (docs/product/<slug>.md, where slug == the primary doc's frontmatter `id` —
  confirmed against the three existing product docs). One slug therefore drives
  BOTH the trigger key and the product-doc lookup — no second identity.
- "Is this scope user-facing?" is a request-level product attribute decided at
  intake, which is exactly the primary doc.
- ABSENT key = ungated (fail-open, legacy-safe): the ~106 pre-convention items
  and any doc that never opts in are silently unaffected. Truthy test is narrow:
  the value lower-cased equals `true` (a parsed boolean or the string "true");
  anything else (false, absent, garbage) is NOT gated.

Rejected: spec frontmatter (optional `--spec` -> silent fail-open); "both
docs" (the dispatch requires exactly one authoritative source).

### D2 — the product-doc predicate (existence + non-placeholder)
A user_visible scope's product doc is docs/product/<slug>.md. It counts as a
REAL product doc only when it exists AND each REQUIRED section is present and
non-placeholder. Required sections (the original operator assignment's trio —
functional description, data model, interfaces): `What it does`, `Data model`,
`Interfaces and contracts` (exact level-2 heading text, matching
PRODUCT_TEMPLATE).

Non-placeholder predicate for a section: take the body between the section
heading and the next level-2 heading (or EOF); strip HTML comments and blank
lines; it is a placeholder (== missing) when the remaining body is empty OR
consists solely of unfilled template angle-bracket tokens (a line matching
`^<.*>$`). The literal `None.` counts as REAL content (the template explicitly
uses "None." to positively assert an empty section) — it must PASS.

### D3 — gate placement + dial (report-only default, enforce refuses pre-write)
The gate runs inside close-work-item.mjs's existing PRE-WRITE resolution region
(after each doc is resolved and status-validated, BEFORE the snapshot/apply
block), so a refusal writes nothing. It is evaluated only for the primary
`--ref` doc (D1). Behavior:
- Not user_visible (D1 truthy false/absent): gate is silent, close proceeds.
- user_visible AND real product doc present (D2): close proceeds, no warning.
- user_visible AND product doc missing/placeholder, dial `report-only`
  (DEFAULT): print a loud WARNING to stderr naming the missing doc/section,
  close PROCEEDS (exit unchanged).
- user_visible AND product doc missing/placeholder, dial `enforce`: REFUSE with
  a non-zero exit and a named reason; nothing is written (doc bytes + EVENTS
  length unchanged).
- `--dry-run`: the gate verdict is reported in the JSON plan (informational);
  dry-run still writes nothing and exits 0 (its contract is unchanged).

The dial is a NEW enforce|report-only key `product_doc_gate` in
docs/ai/docs-audit.yaml, read through the canonical reader
.aai/scripts/lib/guard-config.mjs (extend GUARD_DIALS + the line regex + the
`out` defaults to include `product_doc_gate`, mirroring `close_gate`). Default
(key or file absent, or an invalid value) = report-only, fail-open. AAI core
ships the key documented as report-only.

### D4 — USER_GUIDE rollup (new generator, marker-delimited, idempotent)
New .aai/scripts/generate-userguide-rollup.mjs renders one marker-delimited
section into docs/USER_GUIDE.md from docs/product/*.md:
- Markers (HTML comments): `<!-- AAI:USERGUIDE-ROLLUP:BEGIN ... -->` /
  `<!-- AAI:USERGUIDE-ROLLUP:END -->`. Only the region BETWEEN the markers is
  ever written; every byte outside is preserved verbatim (containment). When
  the markers are absent (first run) the block is appended at EOF; subsequent
  runs replace in place.
- Per product doc: the H1 title, a link to the product doc + its `spec`, and the
  "What it does" first paragraph; sorted by frontmatter `updated` descending.
- Placeholder-rejecting: a product doc that fails the D2 predicate is EXCLUDED
  (a half-written product doc never leaks into the guide).
- Byte-idempotent: NO volatile content (no generation timestamp) inside the
  marked region, so a second run with unchanged inputs is byte-identical.

### D5 — best-effort close hook (never changes the close exit code)
close-work-item.mjs invokes the rollup generator best-effort as the strictly
last step of a successful close, immediately AFTER regenerateOverviewBestEffort()
— reusing that exact pattern: `fs.existsSync` guard (the generator is an
`extended`-profile file and may be absent in a core-only sync), swallow every
failure to an INFO stderr line, never reach rollback, never change the exit
code. This is a negative-control-backed property (Spec-AC-04).

### D6 — new-.aai-file classification (companion obligation)
generate-userguide-rollup.mjs is a NEW .aai/** file, so per PLANNING step 3a it
is classified in .aai/system/PROFILES.yaml. Classification: `extended` — it is
documentation generation (reporting/publishing family), and it follows the
direct precedent of generate-overview.mjs (also invoked best-effort from the
core close ceremony yet classified `extended`). The core close path
`existsSync`-guards it, so a core-only sync degrades cleanly (D5).

## Acceptance Criteria Mapping
For each requirement AC:
- Maps to: AC-001 (intake) -> Spec-AC-01
- Maps to: AC-002 -> Spec-AC-02
- Maps to: AC-003 -> Spec-AC-03
- Maps to: AC-004 -> Spec-AC-04
- Maps to: AC-005 -> Spec-AC-05
- Companion obligation (PLANNING step 3a, new .aai file) -> Spec-AC-06

- Spec-AC-01: The product-doc gate fires ONLY when the primary `--ref` doc's
  frontmatter carries a truthy `user_visible`; missing/placeholder product doc
  warns under report-only (close proceeds) and REFUSES pre-write under enforce
  (nothing written); an absent key leaves the close byte-for-byte unchanged from
  today. Verification: bash tests/skills/test-aai-close-work-item.sh gate stanzas (TEST-001..004).
- Spec-AC-02: A product doc whose `Data model` or `Interfaces and contracts`
  section still holds template placeholder text counts as MISSING; a section
  reading `None.` counts as REAL and passes. Verification: bash tests/skills/test-aai-close-work-item.sh (TEST-005, TEST-006).
- Spec-AC-03: The rollup writes only between its markers (bytes outside
  untouched), is byte-identical on a second run, sorts by `updated` descending,
  and excludes placeholder product docs. Verification: bash tests/skills/test-aai-userguide-rollup.sh (TEST-007..010).
- Spec-AC-04: A successful close invokes the rollup best-effort after the
  overview regen; a rigged rollup failure leaves the close exit 0 with the doc
  done and close events intact (no rollback). Verification: bash tests/skills/test-aai-close-work-item.sh (TEST-011, TEST-012).
- Spec-AC-05: No regression — the full close-work-item suite stays green and the
  guard-config reader returns the new dial correctly (enforce, report-only,
  invalid-value fail-open). Verification: bash tests/skills/test-aai-close-work-item.sh (TEST-013, TEST-014); PR CI full framework.
- Spec-AC-06: generate-userguide-rollup.mjs is classified in PROFILES.yaml and
  the layer-profiles conformance suite stays green. Verification: bash tests/skills/test-aai-layer-profiles.sh (TEST-015).

## Constitution deviations

None.

<!-- Checked each article of docs/CONSTITUTION.md against the planned scope:
  1 Evidence before claims: honored (tdd RED-proof + suite evidence).
  2 Simplicity: additive gate + generator reusing the overview-hook and
    guard-config patterns; INTERFACES automation explicitly out of scope (no
    speculative build).
  3 Portability: plain files, Node stdlib only, bash-3.2 test suites.
  4 Degrade and report: report-only default warns; enforce refuses with a named
    reason; rollup best-effort swallows failures to an INFO line; absent
    generator no-ops.
  5 Additive first: user_visible optional (absent = ungated), product_doc_gate a
    new dial defaulting report-only, rollup markers + guard-config extension all
    additive and backward-compatible.
  6 Single-writer state: no STATE writes introduced.
  7 Operator-only merge: unchanged.
  No canonical requirement (REQ id) is added/modified/removed, so no
  `## Deltas` section is included. -->

## Acceptance Criteria Status

Tracks per-Spec-AC delivery state. Separate from per-test lifecycle below.

| Spec-AC    | Description                                                                 | Status  | Evidence | Review-By | Notes |
|------------|-----------------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | user_visible-only gate; report-only warns, enforce refuses pre-write        | done | TEST-001..004 green; docs/ai/tdd/red-20260727T073622Z-close-work-item-gate.log then docs/ai/tdd/green-20260727T073736Z-close-work-item.log | — | — |
| Spec-AC-02 | placeholder Data model / Interfaces counts as missing; None. passes         | done | TEST-005/006 green; same red/green close-work-item logs as Spec-AC-01 | — | — |
| Spec-AC-03 | rollup marker-contained, byte-idempotent, sorted desc, placeholder-rejecting | done | TEST-007..010 green; docs/ai/tdd/red-20260727T073025Z-userguide-rollup.log then docs/ai/tdd/green-20260727T073142Z-userguide-rollup.log | — | — |
| Spec-AC-04 | best-effort close hook; rigged failure never changes close exit code        | done | TEST-011/012 green; same red/green close-work-item logs as Spec-AC-01 (SEAM test_022 + negative control test_023) | — | — |
| Spec-AC-05 | no regression; guard-config reads product_doc_gate dial                     | done | TEST-013/014 green (test_024 legacy-suite regression + test_025 guard-config unit); docs/ai/tdd/green-20260727T073736Z-close-work-item.log; docs-audit --check --strict --no-event exit 0; hygiene-pack test_031 green (unchanged) | — | — |
| Spec-AC-06 | new generator classified in PROFILES; layer-profiles suite green            | done | TEST-015 green; docs/ai/tdd/red-20260727T073811Z-layer-profiles.log then docs/ai/tdd/green-20260727T073824Z-layer-profiles.log | — | — |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- Components/modules affected:
  - .aai/scripts/lib/guard-config.mjs — add `product_doc_gate` to GUARD_DIALS,
    the line regex, and the `out` defaults (mirror close_gate). Additive.
  - .aai/scripts/close-work-item.mjs — add the pre-write product-doc gate (D1,
    D2, D3) inside the existing resolution loop / before the snapshot; add the
    best-effort rollup hook after regenerateOverviewBestEffort() (D5); surface
    the gate verdict in the --dry-run JSON.
  - .aai/scripts/generate-userguide-rollup.mjs — NEW generator (D4).
  - docs/USER_GUIDE.md — seed the marker block (or let the first generator run
    append it); the marked region is machine-owned.
  - docs/ai/docs-audit.yaml — document + set `product_doc_gate: report-only`.
  - .aai/templates/PRODUCT_TEMPLATE.md — add the `user_visible` convention note
    (how the key on the work-item doc triggers this product doc's requirement).
  - .aai/system/PROFILES.yaml — classify the new generator under `extended` (D6).
  - tests/skills/test-aai-close-work-item.sh — gate + best-effort-hook stanzas.
  - tests/skills/test-aai-userguide-rollup.sh — NEW rollup suite.
- Data flows: primary doc frontmatter (user_visible) + docs/product/<slug>.md ->
  gate verdict -> warn/refuse; docs/product/*.md -> rollup -> USER_GUIDE marked
  region.
- Edge cases: absent user_visible; user_visible with no product doc; product doc
  with a placeholder required section vs an explicit `None.`; markers absent on
  first rollup run; a product doc with no `updated` field (sort tie-break stable
  by slug); rollup generator absent in a core-only sync; --dry-run.

## Seam analysis
- SEAM 1 (guard-config dial -> close gate consumer): the new
  `product_doc_gate` dial is produced by guard-config.mjs and consumed by
  close-work-item.mjs. Crossed end-to-end by TEST-002 (enforce fixture in a real
  docs-audit.yaml -> real close refuses) and TEST-001 (report-only fixture ->
  real close warns and proceeds) — a real config file drives the real script, no
  mocked boundary.
- SEAM 2 (close producer -> rollup consumer): close-work-item.mjs invokes
  generate-userguide-rollup.mjs. Crossed by TEST-011 (a real close of a
  user_visible item with a real product doc -> assert the USER_GUIDE marked
  region updated) and the negative control TEST-012.
- SEAM 3 (product-doc slug identity): docs/product/<slug>.md keyed on the
  primary `--ref` fm.id is read by BOTH the gate (lookup) and the rollup
  (render). Covered by TEST-004 (gate finds the doc by slug) + TEST-011 (rollup
  renders the same doc).
- SEAM 4 (new file -> live .aai tree classification): TEST-015 (layer-profiles
  conformance against the live tree).
- Residual risk RR-1: product docs are intentionally OUTSIDE the docs-audit scan
  (type `product` is not scanned), so the gate's existence/placeholder check has
  no audit oracle to cross-verify against; it is close-work-item-local. Accepted
  — the fixture triad (TEST-001..006) is the verification.

## Test Plan
For each Spec-AC, enumerate concrete tests:

| Test ID  | Spec-AC    | Type        | File path (expected)                          | Description                                                                                     | Status  |
|----------|------------|-------------|-----------------------------------------------|-------------------------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | user_visible + missing product doc + report-only dial: WARNING on stderr, close exit 0, doc flipped | green |
| TEST-002 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | user_visible + missing product doc + enforce dial: refuse exit non-zero, doc bytes + EVENTS length unchanged (pre-write) | green |
| TEST-003 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | user_visible absent (legacy): gate silent, close proceeds regardless of product doc (negative control) | green |
| TEST-004 | Spec-AC-01 | integration | tests/skills/test-aai-close-work-item.sh      | user_visible + real product doc present under enforce: close proceeds, no warning               | green |
| TEST-005 | Spec-AC-02 | integration | tests/skills/test-aai-close-work-item.sh      | product doc with a placeholder Data model section counts as missing (enforce refuses)           | green |
| TEST-006 | Spec-AC-02 | integration | tests/skills/test-aai-close-work-item.sh      | placeholder Interfaces section counts as missing; a section reading None. counts as real and passes | green |
| TEST-007 | Spec-AC-03 | unit        | tests/skills/test-aai-userguide-rollup.sh     | rollup writes only between markers; bytes outside the markers are byte-identical (containment)   | green |
| TEST-008 | Spec-AC-03 | unit        | tests/skills/test-aai-userguide-rollup.sh     | rollup is byte-identical on a second run with unchanged inputs (idempotence)                     | green |
| TEST-009 | Spec-AC-03 | unit        | tests/skills/test-aai-userguide-rollup.sh     | rollup lists product docs sorted by updated descending                                           | green |
| TEST-010 | Spec-AC-03 | unit        | tests/skills/test-aai-userguide-rollup.sh     | a placeholder-failing product doc is excluded from the rendered section                          | green |
| TEST-011 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | SEAM: real close of a user_visible item with a real product doc updates the USER_GUIDE marked region | green |
| TEST-012 | Spec-AC-04 | integration | tests/skills/test-aai-close-work-item.sh      | NEGATIVE CONTROL: a rigged rollup failure leaves close exit 0, doc done, close events intact (no rollback) | green |
| TEST-013 | Spec-AC-05 | integration | tests/skills/test-aai-close-work-item.sh      | full existing close-work-item suite (TEST-001..015 legacy) stays green (no regression)           | green |
| TEST-014 | Spec-AC-05 | unit        | tests/skills/test-aai-close-work-item.sh      | guard-config readGuardConfig returns product_doc_gate for enforce, report-only, and invalid-value fail-open | green |
| TEST-015 | Spec-AC-06 | integration | tests/skills/test-aai-layer-profiles.sh       | generate-userguide-rollup.mjs is classified (extended); union-equals-live-tree conformance stays green | green |

Test status values: pending | red | green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- Test IDs are stable — do not renumber after freeze.
- RED-proof obligation: every AC-gating test above must be observed FAILING
  without the change before its passing counts as evidence (strategy is tdd).
- Test file paths are suggestions; implementation may adjust with justification.

## Verification
- Commands to run:
  - bash tests/skills/test-aai-close-work-item.sh
  - bash tests/skills/test-aai-userguide-rollup.sh
  - bash tests/skills/test-aai-layer-profiles.sh
  - node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0092-spec-product-docs-enforced.md
  - node .aai/scripts/docs-audit.mjs --check --strict --no-event
  - (all suites via the .aai/scripts/aai-run-tests.sh wrapper per the LEARNED rule)
  - PR CI: full framework.
- Evidence artifacts: TDD red/green logs under docs/ai/tdd/; suite outputs;
  docs-audit --check exit code.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: product-docs-enforced
- Spec-AC and TEST-xxx links where applicable
- command or review scope
- exit code or review verdict
- evidence path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

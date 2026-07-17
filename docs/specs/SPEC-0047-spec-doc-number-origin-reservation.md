---
id: spec-doc-number-origin-reservation
type: spec
number: 47
status: done
ceremony_level: 3
links:
  requirement: CHANGE-0035
  rfc: null
  pr:
    - 99
  commits:
    - ff55d1e
---

# SPEC — Atomic Doc-Number Reservation in Origin (CHANGE-0035)

## Links
- Requirement: docs/issues/CHANGE-0035-doc-number-origin-reservation.md
- Prior art: docs/specs/SPEC-0015-parallel-safe-doc-numbering.md (RFC-0007 —
  the allocator this spec extends), docs/specs/SPEC-0033-spec-spec-lint.md
  (the lint this spec extends)
- Technology contract: docs/TECHNOLOGY.md

## Ceremony decision (L3)

`ceremony_level: 3` is MANDATORY: the scope modifies
`.aai/scripts/allocate-doc-number.mjs`, which is listed in
`protected_paths_l3` (docs/ai/docs-audit.yaml line 34; canonical defaults in
.aai/workflow/WORKFLOW.md "Ceremony levels" — "allocator"). Verified directly
in this planning pass. Consequences applied per the WORKFLOW.md L3 column:
- Full SPEC artifact (this document), full freeze proxy.
- Worktree gate: REQUIRED semantics — an explicit operator `user_decision`
  must be RECORDED before implementation (operator may still record an inline
  override with rationale; the recorded decision is what rule 8 mandates).
- Validation: full independent validation.
- Code review: MANDATORY on the most capable tier; a waiver is flagged to the
  operator (needs_llm), never auto-accepted. Non-waivable in this plan.
- PR ceremony: + operator checkpoint before merge (explicit final-diff
  sign-off).

## Implementation strategy
- Strategy: hybrid
- Rationale: `tdd` for all reservation/guard/lint/coupled-family behavior
  (TEST-001..TEST-010, TEST-014, TEST-015) — new, risky, data-integrity
  behavior on an L3-protected surface where a silent regression corrupts doc
  identity across every vendored project; `loop` for mechanical wiring and
  docs rows (TEST-011 back-compat suite run, TEST-012 CI-workflow wiring
  greps, TEST-013 docs rows) where RED-GREEN-REFACTOR adds no signal.

## Isolation and review
- Worktree recommendation: required
- Worktree rationale: L3-protected surface (`allocate-doc-number.mjs` is on
  `protected_paths_l3`) plus a cross-cutting scope (allocator + guard-config
  lib + spec-lint + CI workflow + tests + docs). WORKFLOW.md L3 row makes an
  explicit recorded operator decision mandatory for ANY recommendation; this
  plan recommends physical isolation in a worktree off `main`.
- User decision: undecided — the operator decides at the implementation-
  preparation gate; Planning does not fabricate this decision.
- Base ref: main
- Worktree branch/path: to be recorded at the gate (suggested branch:
  `feat/doc-number-origin-reservation`)
- Inline review scope (applies if the operator overrides to inline):
  `.aai/scripts/allocate-doc-number.mjs`, `.aai/scripts/spec-lint.mjs`,
  `.aai/scripts/lib/guard-config.mjs`, `.github/workflows/docs-numbering.yml`,
  `tests/skills/test-aai-doc-number-reservation.sh`,
  `tests/skills/test-aai-doc-numbering.sh` (only if touched),
  `docs/TECHNOLOGY.md`, `docs/USER_GUIDE.md`,
  `docs/specs/SPEC-0047-spec-doc-number-origin-reservation.md`,
  `docs/issues/CHANGE-0035-doc-number-origin-reservation.md`, `docs/INDEX.md`

## Design decisions (operator-approved constraints, frozen)

- D1 — Reservation medium: one ref per reserved number,
  `refs/aai/docnums/<TYPE>-<NNNN>` in `origin`, where `<TYPE>-<NNNN>` is the
  zero-padded DISPLAY id exactly as it appears in the filename token (width
  from the allocator's existing `deriveWidth` cascade). The ref points at the
  current local HEAD commit (content is irrelevant; ref EXISTENCE is the
  semaphore). Holes (abandoned reservations) are acceptable and are never
  cleaned up.
- D2 — Create-only atomic primitive: the reservation push is
  `git push --atomic --force-with-lease=<ref>: origin HEAD:<ref>` (one push,
  all refs). The expect-absent lease (`--force-with-lease=<ref>:` with empty
  expected value) makes creation strictly create-only: an existing ref at ANY
  sha — including the same sha or an ancestor that a plain push would
  fast-forward — rejects the push. `--atomic` makes multi-ref (coupled
  family) reservation all-or-nothing. GitHub (this project's remote) supports
  both.
- D3 — Candidate scan (union): taken numbers for a prefix =
  (a) local governed-dir filenames (as today) ∪ (b) trees of ALL fetched
  `origin/*` refs (`git for-each-ref refs/remotes/origin` + `ls-tree`, after
  the existing best-effort fetch widened to `git fetch origin` default
  refspec) ∪ (c) reservation refs from `git ls-remote origin
  "refs/aai/docnums/<PREFIX>-*"` (numeric parse of the ref tail; on ls-remote
  failure, degrade to any locally-known `refs/aai/docnums/*` and report).
  Next-free = max(union) + 1.
- D4 — Provisional marker semantics: frontmatter key `number_reserved` —
  ABSENT = confirmed/legacy (no claim; all historical docs stay valid);
  `number_reserved: false` = provisional (merge guard BLOCKS). Stamped only
  when the reservation push fails for a non-collision reason. Completion:
  `allocate-doc-number.mjs --reserve --path <numbered-doc>` re-attempts the
  create-only push for the doc's display id (plus coupled refs) and removes
  the marker line on success; if the ref already exists at completion time,
  exit 4 with a report naming the potential collision (operator renumbers via
  re-allocation). Never silent.
- D5 — Merge guard home: two NEW predicates added to the existing `--guard`
  mode (single wiring point: pre-commit host + `docs-numbering.yml` CI
  mirror; enforcement rides the existing `doc_number_guard` dial):
  (a) cross-branch collision — a governed doc in the staged tree whose
  `TYPE-NNNN` display id exists on the guard base ref (`--base-ref`, default
  `origin/main`; CI passes the PR target branch) under a DIFFERENT slug `id`
  → exit 4; (b) unreserved marker — any governed doc with
  `number_reserved: false` → exit 4. `--guard` therefore now honors
  `--base-ref` (previously ignored in guard mode); base-ref unreachable in
  guard mode degrades to predicate (b) + today's predicates with a printed
  WARNING (degrade-and-report, exit unchanged by the skipped predicate).
- D6 — Slug-handle lint home: a new OPT-IN `--slug-handles` scan mode in
  `.aai/scripts/spec-lint.mjs` (report-only charter preserved: exit 0 clean /
  1 findings; never blocks). Scope: FILENAMES under session-artifact dirs
  (`docs/ai/reviews/`, `docs/ai/reports/`, `docs/ai/briefs/`, `tests/`)
  embedding a `TYPE-NNN(N)` token (governed prefixes only) that has no
  corresponding numbered governed doc in the local tree → WARN (slug-only
  handle discipline). The spec-lint boundary comment is updated to name this
  additive advisory scope.
- D7 — Coupled-families config: new OPTIONAL key `coupled_families` in
  `docs/ai/docs-audit.yaml`, parsed ONLY by the shared
  `.aai/scripts/lib/guard-config.mjs` reader (single-parser discipline,
  CHANGE-0009 D8). Line-parser-friendly syntax — one group per list item,
  prefixes joined by `+`:
  `coupled_families:` / `  - CHANGE+SPEC-CHANGE`.
  Semantics: all prefixes in a group share one counter — next-free is
  computed over the UNION of taken numbers across every member (D3 scan per
  member); the reservation push covers ALL member refs in the one D2 atomic
  push. AAI core ships the key ABSENT (links-based pairing stays
  authoritative; this repo does NOT enable coupling).
- D8 — Exit-code surface unchanged (0/2/3/4, SPEC-0015 D3): base-ref
  unreachable in allocate mode still exits 3 byte-identical; provisional
  fallback (D4) exits 0 WITH a prominent WARNING; ref-exists rejection
  retries the next free number with a hard cap of 50 attempts, then exit 4
  with a report.
- D9 — Back-compat: no `coupled_families` key + no reachable/no configured
  `origin` ⇒ behavior identical to today except the provisional-marker
  discipline (D4 stamp + warning where a reservation could not be made). The
  existing suite `tests/skills/test-aai-doc-numbering.sh` must pass
  UNMODIFIED except for stanzas whose fixtures lack an origin remote and now
  observe the D4 marker/warning — any such edit must be limited to asserting
  the new marker/warning, never to weakening an existing assertion.
- D10 — Testability without network: all reservation tests use a local bare
  repo as origin (`git init --bare` + one or two clones with
  `git remote add origin <bare-path>`); the race is simulated by pre-creating
  a reservation ref in the bare repo from "the other clone".

## Acceptance Criteria Mapping

- Maps to: CHANGE-0035 AC-001
  - Spec-AC-01: reservation-before-rename — with a reachable origin, the
    allocator creates `refs/aai/docnums/<TYPE>-<NNNN>` in origin via the D2
    create-only atomic push BEFORE stamping/renaming the local DRAFT; after a
    successful run the ref exists in the bare origin AND the file is renamed.
  - Verification: TEST-001 (fixture: bare origin + clone; assert
    `git --git-dir <bare> show-ref refs/aai/docnums/<ID>` exit 0 and renamed
    file present).
- Maps to: CHANGE-0035 AC-001
  - Spec-AC-02: candidate union scan — next-free is computed over local tree
    ∪ all fetched `origin/*` trees ∪ existing reservation refs (D3), so a
    number taken on an unmerged origin branch, or held only by a naked
    reservation ref, is never granted.
  - Verification: TEST-003 (origin side branch holds N; clone allocates N+1),
    TEST-004 (naked reservation ref for N; clone allocates N+1).
- Maps to: CHANGE-0035 AC-001
  - Spec-AC-03: rejection→retry — a create-only push rejected because the ref
    exists causes retry with the next free number (cap 50, then exit 4); the
    winning and losing clones end with distinct numbers and both refs exist.
  - Verification: TEST-002 (pre-created ref from "other clone"; allocation
    lands on next free; both refs present; no duplicate filename).
- Maps to: CHANGE-0035 AC-002
  - Spec-AC-04: offline/no-permission fallback — when the reservation push
    fails for a non-collision reason, allocation still completes, stamps
    `number_reserved: false` (D4), prints a WARNING naming the incomplete
    reservation, exits 0; `--reserve --path` completes the reservation and
    removes the marker (or exits 4 if the ref now exists).
  - Verification: TEST-005 (unreachable push URL → marker + warning + exit
    0), TEST-007 (completion path clears marker; ref-exists completion exits
    4).
- Maps to: CHANGE-0035 AC-002 + AC-003 (guard half)
  - Spec-AC-05: merge guard — `--guard` fails (exit 4) when (a) a staged
    governed doc's `TYPE-NNNN` exists on the guard base ref under a different
    slug id, or (b) any governed doc carries `number_reserved: false`; both
    predicates ride the existing `doc_number_guard` dial and existing
    pre-commit/CI wiring (D5).
  - Verification: TEST-006 (cross-branch collision → exit 4 naming both
    paths), TEST-007 (marker blocks; clean after completion).
- Maps to: CHANGE-0035 AC-003 (lint half)
  - Spec-AC-06: slug-handle lint — `spec-lint --slug-handles` warns
    (report-only, exit 1 with findings / 0 clean) on session-artifact
    FILENAMES embedding a governed `TYPE-NNN(N)` token with no corresponding
    numbered governed doc (D6); silent for tokens whose doc exists.
  - Verification: TEST-008 (fixture artifact `review-CHANGE-036.md` with no
    CHANGE-036 doc → finding; with the doc present → clean).
- Maps to: CHANGE-0035 AC-004
  - Spec-AC-07: coupled families union — with `coupled_families` declaring a
    group, next-free is max over the UNION of all members' taken numbers + 1,
    and ONE `git push --atomic` creates every member ref; any member ref
    already existing rejects the WHOLE set and retries the next union-free
    number (all-or-nothing).
  - Verification: TEST-009 (family A max 5, family B max 3 → both allocate
    6; both refs created), TEST-010 (one member ref pre-exists → neither ref
    created for that number; pair lands on next free).
- Maps to: CHANGE-0035 Constraints (back-compat)
  - Spec-AC-08: back-compat — without the `coupled_families` key and without
    a usable origin, allocator/guard behavior is unchanged except the D4
    marker discipline; the existing `tests/skills/test-aai-doc-numbering.sh`
    suite passes per D9; exit-code surface unchanged (D8).
  - Verification: TEST-011 (run the existing suite through the AAI test
    wrapper → PASS).
- Maps to: CHANGE-0035 Scope (CI wiring)
  - Spec-AC-09: CI wiring — `.github/workflows/docs-numbering.yml` passes the
    PR target branch as `--base-ref` to the guard on pull_request events,
    runs the `--slug-handles` lint as an always-report-only step, and the
    enforce gate covers the new guard predicates under the existing
    `doc_number_guard` dial.
  - Verification: TEST-012 (deterministic grep assertions on the workflow
    file — ps1-quality precedent style).
- Maps to: CHANGE-0035 Scope (docs)
  - Spec-AC-10: docs — `docs/TECHNOLOGY.md` and `docs/USER_GUIDE.md` document
    the reservation protocol, the `number_reserved` marker, the
    `coupled_families` config, and the new guard predicates + lint mode.
  - Verification: TEST-013 (grep for the documented tokens in both files).

## Seam analysis (cross-feature integration)

- Seam S1 — `--guard` ↔ pre-commit host (`pre-commit-checks.sh`/`.ps1`) and
  CI mirror: the new predicates ride an invocation owned by other surfaces.
  Covered by TEST-014 (run the pre-commit host script in a fixture where only
  the NEW predicate fails → the host surfaces the failure under
  `doc_number_guard: enforce`).
- Seam S2 — `guard-config.mjs` shared reader ↔ its other consumers
  (`state.mjs`, docs-audit callers): adding `coupled_families` must not
  disturb the existing dials. Covered by TEST-009 (new key parsed) plus
  TEST-011 (existing doc-numbering suite green) — full-suite validation
  re-checks the remaining consumers.
- Seam S3 — `number_reserved` frontmatter key ↔ docs-audit frontmatter
  checks: the marker must not trip `docs-audit --check --strict`. Covered by
  TEST-015 (fixture doc with `number_reserved: false` → docs-audit reports no
  frontmatter violation for that key).
- Seam S4 — reservation ref namespace shared across clones: that IS the
  feature; the race crossing is TEST-002 (real bare-origin fixture, no
  mocks).
- Residual risk (accepted, recorded): true concurrent push-race timing (two
  pushes in flight simultaneously) is serialized by the git server and cannot
  be deterministically forced in a local fixture; TEST-002 exercises the
  observable outcome (ref-exists rejection → retry). No automated test forces
  the in-flight interleaving itself.

## Constitution deviations

None.

Constitution walk (L3, all articles checked): (1) evidence-before-claims —
Test Plan + evidence contract below; (2) simplicity — coupled families is an
intake-required behavior (downstream incident), not speculative; AAI core
ships it disabled/absent; (3) portability — reservation uses plain git refs,
no service-bound store; offline path preserved; (4) degrade-and-report —
D4/D5/D8 make every degraded path print an explicit warning, never silent;
(5) additive-first — new flags, new optional config key, absent-key = legacy
behavior, exit-code surface unchanged; (6) single-writer state — STATE.yaml
touched only via state.mjs; (7) operator-only merge — unchanged; L3 adds an
operator pre-merge checkpoint.

## Acceptance Criteria Status

| Spec-AC    | Description                                            | Status  | Evidence | Review-By | Notes |
|------------|--------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | Reservation ref created in origin before local rename  | done | TEST-001/TEST-016/TEST-017 green (remediation of validation F1 — same-sha `--force-with-lease` no-op, fixed via per-attempt nonce-commit push), docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log | — | Remediated 2026-07-17 post-validation FAIL (validation-20260717T174229Z-SPEC-0047.md F1) |
| Spec-AC-02 | Next-free over local ∪ origin/* ∪ reservation refs     | done | TEST-003/TEST-004 green, docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log | — | — |
| Spec-AC-03 | Ref-exists rejection retries next free (cap 50)        | done | TEST-002/TEST-016/TEST-017 green (direct unit test of reserveAtomic + remediation of validation F1 same-sha false-success, uncoupled and coupled), docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log | — | Remediated 2026-07-17 post-validation FAIL (validation-20260717T174229Z-SPEC-0047.md F1) |
| Spec-AC-04 | Offline/no-permission fallback marker + completion     | done | TEST-005/TEST-007/TEST-015/TEST-018 green (remediation of validation F2 — permission-denied push over-matched the collision predicate, narrowed to the lease-rejection signal "stale info"), docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log | — | Remediated 2026-07-17 post-validation FAIL (validation-20260717T174229Z-SPEC-0047.md F2) |
| Spec-AC-05 | Merge guard: cross-branch collision + unreserved block | done | TEST-006/TEST-007/TEST-014 green, docs/ai/tdd/green-20260717T173500Z-final-new-suite.log | — | — |
| Spec-AC-06 | spec-lint --slug-handles artifact-filename warning     | done | TEST-008 green, docs/ai/tdd/green-20260717T173500Z-final-new-suite.log | — | — |
| Spec-AC-07 | Coupled families: union counter + atomic multi-ref     | done | TEST-009/TEST-010/TEST-017 green (TEST-017 remediates validation F1's coupled same-sha variant — one member's no-op previously let the whole atomic push false-succeed), docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log | — | Remediated 2026-07-17 post-validation FAIL (validation-20260717T174229Z-SPEC-0047.md F1) |
| Spec-AC-08 | Back-compat: no config/no origin behaves as today      | done | TEST-011 green (D9 invariant, unmodified suite semantics via setup_iso_repo origin addition), docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log (TEST-011 embedded) | — | — |
| Spec-AC-09 | CI wiring: base-ref guard + lint step + enforce gate   | done | TEST-012 green, docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log; .github/workflows/docs-numbering.yml | — | — |
| Spec-AC-10 | TECHNOLOGY.md + USER_GUIDE.md rows                     | done | TEST-013 green, docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log; docs/TECHNOLOGY.md, docs/USER_GUIDE.md | — | — |

## Implementation plan
- Components: `.aai/scripts/allocate-doc-number.mjs` (reserve step in
  `runAllocate` before the write loop; `--reserve` completion mode; `--guard`
  predicates; D3 scan helpers), `.aai/scripts/lib/guard-config.mjs`
  (`coupled_families` parsing), `.aai/scripts/spec-lint.mjs`
  (`--slug-handles` mode), `.github/workflows/docs-numbering.yml` (base-ref +
  lint step), `tests/skills/test-aai-doc-number-reservation.sh` (new suite,
  bash-3.2, bare-origin fixture per D10), docs rows.
- Data flow: plan numbers (per-prefix or per-family union) → one atomic
  create-only push → on success stamp/rename locally → on ref-exists retry →
  on network/permission failure stamp `number_reserved: false` + warn.
- Edge cases: width variance in ref names (numeric parse per D3); multiple
  drafts in one `--all` batch (per-draft reservation, sequential); guard base
  ref unreachable (degrade per D5); ls-remote unavailable offline (degrade
  per D3); completion when ref exists (exit 4 per D4); retry cap (D8).
- Constraints: Node stdlib only, plain `node` invocation; bash-3.2 test
  suite; suites run through `.aai/scripts/aai-run-tests.sh`; STATE.yaml only
  via state.mjs; JSONL ledgers append-only.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                              | Description                                                                 | Status  |
|----------|------------|-------------|---------------------------------------------------|-----------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Allocation creates refs/aai/docnums/<ID> in bare origin before rename; ref + renamed file both present | green |
| TEST-002 | Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Pre-existing reservation ref (racing clone) → create-only push rejected → allocator retries and lands next free; both refs exist | green |
| TEST-003 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Number taken only on an unmerged origin side branch is skipped (SPEC-0042-incident regression) | green |
| TEST-004 | Spec-AC-02 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Naked reservation ref (no doc anywhere) is treated as taken                 | green |
| TEST-005 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Unreachable push target → allocation proceeds, stamps number_reserved: false, prints WARNING, exit 0 | green |
| TEST-006 | Spec-AC-05 | integration | tests/skills/test-aai-doc-number-reservation.sh   | --guard exit 4 when staged TYPE-NNNN exists on base ref under different id  | green |
| TEST-007 | Spec-AC-04, Spec-AC-05 | integration | tests/skills/test-aai-doc-number-reservation.sh | --guard blocks number_reserved: false; --reserve completes (marker removed, guard clean) or exits 4 when ref exists | green |
| TEST-008 | Spec-AC-06 | unit        | tests/skills/test-aai-doc-number-reservation.sh   | spec-lint --slug-handles flags artifact filename embedding TYPE-NNN with no merged doc; clean when doc exists | green |
| TEST-009 | Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh   | coupled_families group: next-free over union (5,3 → 6 for both); one atomic push creates both refs | green |
| TEST-010 | Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Atomic all-or-nothing: one member ref pre-exists → neither ref created at that number; pair retries together | green |
| TEST-011 | Spec-AC-08 | integration | tests/skills/test-aai-doc-numbering.sh            | Existing SPEC-0015 suite passes per D9 (back-compat invariant — see RED-proof note) | green |
| TEST-012 | Spec-AC-09 | unit        | tests/skills/test-aai-doc-number-reservation.sh   | Grep assertions: workflow passes PR base as --base-ref, has slug-handles lint step, enforce gate covers new predicates | green |
| TEST-013 | Spec-AC-10 | unit        | tests/skills/test-aai-doc-number-reservation.sh   | TECHNOLOGY.md + USER_GUIDE.md contain reservation/marker/coupled_families/guard rows | green |
| TEST-014 | Spec-AC-05 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Seam S1: pre-commit host surfaces a NEW-predicate-only failure under doc_number_guard: enforce | green |
| TEST-015 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh   | Seam S3: docs-audit --check --strict raises no frontmatter finding for number_reserved: false | green |
| TEST-016 | Spec-AC-01, Spec-AC-03 | integration | tests/skills/test-aai-doc-number-reservation.sh | Remediation of validation F1: two reserveAtomic attempts from the SAME HEAD (no intervening commit) must not both "win" the number — a same-sha `--force-with-lease` push is a silent no-op unless the pushed object is per-attempt unique | green |
| TEST-017 | Spec-AC-01, Spec-AC-03, Spec-AC-07 | integration | tests/skills/test-aai-doc-number-reservation.sh | Remediation of validation F1 (coupled variant): a same-HEAD coupled-family retry must reject the PAIR, not false-succeed because one member's ref happened to already be at the same sha | green |
| TEST-018 | Spec-AC-04 | integration | tests/skills/test-aai-doc-number-reservation.sh | Remediation of validation F2: a permission-denied/unpacker-error push (read-only bare origin, distinct from TEST-005's unreachable-path case) must fall through to the D4 provisional path (number_reserved: false + WARNING + exit 0), never the 50-attempt retry storm ending in die(4) | green |

Evidence: docs/ai/tdd/red-20260717T171247Z-per-test.log (RED, TEST-001..010/
012..014, product_red-accepted by tdd-evidence-check.mjs);
docs/ai/tdd/pre-existing-green-TEST-011-TEST-015.log (TEST-011/TEST-015 pass
today by design, per the RED-proof exception below); docs/ai/tdd/green-
20260717T173500Z-final-new-suite.log + green-20260717T173500Z-final-old-suite.log
(GREEN, all 15 + the existing SPEC-0015 suite, both exit 0).

REMEDIATION (2026-07-17, post-validation FAIL — validation-20260717T174229Z-
SPEC-0047.md): F1 (same-sha `--force-with-lease` silent no-op false-success,
uncoupled and coupled) and F2 (permission-denied push over-matched by the
`/rejected/i` collision predicate, causing a 50-attempt retry storm instead
of the D4 provisional fallback) fixed at cause in `pushReservation` —
(F1) push a per-attempt globally-unique dangling commit (`git commit-tree
<empty-tree> -m <nonce>`) instead of `HEAD`, so a pre-existing ref can never
coincidentally share the pushed sha and the create-only lease always
evaluates; (F2) narrow the collision predicate from
`/rejected|stale info|already exists/i` to `/stale info/i` (the exact
create-only lease-rejection signal), routing every other push failure to the
provisional-marker path. TEST-016/017/018 added, each RED-proofed against
the unfixed code (docs/ai/tdd/red-20260717T174800Z-remediation-per-test.log,
product_red-accepted by tdd-evidence-check.mjs) before the fix, then GREEN
(docs/ai/tdd/green-20260717T174800Z-remediation-new-suite.log, all 18/18,
TEST-011 back-compat embedded). Re-validation of this reset is pending on the
next orchestration tick.

RED-proof obligation: every AC-gating test above must be observed FAILING
without the change before its pass counts as evidence — including the `loop`
rows TEST-012/TEST-013 (grep targets absent today → deterministic RED).
EXCEPTION, recorded per PLANNING step 6: TEST-011 is a back-compat
INVARIANT — it passes today BY DESIGN and cannot RED; its evidentiary value
is that it STAYS green after the change (regression guard, not new-behavior
proof). It gates Spec-AC-08 together with the D8/D9 assertions embedded in
TEST-005 (exit codes) which are RED-provable.

## Verification
- Commands:
  - `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-doc-number-reservation.sh`
  - `bash .aai/scripts/aai-run-tests.sh tests/skills/test-aai-doc-numbering.sh`
  - `node .aai/scripts/docs-audit.mjs --check --strict --no-event` → CLEAN
  - `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-0047-spec-doc-number-origin-reservation.md` → advisory
- Evidence artifacts: suite output logs (RED and GREEN captures per TDD
  cycle), guard/lint output snippets, commit SHAs.
- PASS criteria: all TEST-xxx green AND all Spec-AC in a terminal status with
  non-empty Evidence.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: doc-number-origin-reservation (CHANGE-0035)
- Spec-AC and TEST-xxx links
- command (from Verification above) + exit code
- evidence path (tests/skills/results/ or docs/ai/reports/)
- commit SHA or diff range

SPEC-FROZEN: true

Frozen 2026-07-17 by Planning (dispatch tick 2 rule 5). All Spec-AC
measurable with mapped TEST-xxx rows; strategy declared (hybrid); ceremony
level 3 declared with the L3 consequences recorded above.

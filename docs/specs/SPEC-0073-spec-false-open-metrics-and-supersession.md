---
id: spec-false-open-metrics-and-supersession
type: spec
number: 73
status: done
ceremony_level: 1
links:
  issue: false-open-metrics-and-supersession
  github_issues: [133, 134]
  rfc: null
  pr:
    - 136
  commits:
    - 8eb7d9baab34cff3b3d79cc6c1f0ecda8efaddd5
---

<!-- SPEC-0015 / RFC-0007 — Parallel-safe doc identity: `id` is the durable
  slug primary key; `number` is assigned at merge by allocate-doc-number.mjs,
  which renames this file from SPEC-DRAFT-<slug>.md to SPEC-000N-<slug>.md. -->

# SPEC — `falseOpenEvidence()` METRICS.jsonl Arm + doc_lifecycle Supersession

SPEC-FROZEN: true

Ceremony justification: single non-protected source file
(`.aai/scripts/lib/docs-audit-core.mjs`, confirmed absent from
`protected_paths_l3` in `docs/ai/docs-audit.yaml`) plus one extension of the
already-existing test file `tests/skills/test-aai-docs-audit.sh`; the change
is two additive evidence-arm edits inside one existing function
(`falseOpenEvidence`), read-only and fail-closed, with no schema/state/prompt
surface touched.

## Links
- Issue: false-open-metrics-and-supersession
  (docs/issues/ISSUE-0027-false-open-metrics-and-supersession.md)
- GitHub issues to close in this ceremony: #133, #134 — the PR body and the
  close step MUST reference both (`Closes #133`, `Closes #134`); they are one
  work item on purpose (same function, same handful of lines, same fixture
  family — see intake "Notes").
- Mirrors/extends: `probable-false-open` heuristic
  (docs/specs/SPEC-0039-spec-false-open-drift-heuristic.md, CHANGE-0027) and
  its D2 hardening (docs/specs/SPEC-0040-spec-docs-audit-d2-evidence-hardening.md)
- Technology contract: docs/TECHNOLOGY.md

## Problem
`falseOpenEvidence()` (`.aai/scripts/lib/docs-audit-core.mjs:257`) decides
whether an open-status doc is `probable-false-open` from four evidence arms,
all pure `events.some(...)` existence checks with no time ordering. Two
defects in the same function, opposite directions:
- **#133** — no arm reads `docs/ai/METRICS.jsonl`, the one artifact that
  proves delivery (a work item is flushed only after validation PASS + a
  satisfied review gate). Intake docs (`ISSUE`/`CHANGE`/`PRD`) keep their AC
  table in their spec and emit no `ac_evidence` of their own, so a flushed
  intake can sit at `status: draft` forever, invisible to the audit.
- **#134** — because the arms are existence-only, delivery evidence is
  permanent. A later `doc_lifecycle: done -> implementing` reopen cannot
  revoke it, so a legitimately reopened doc is reported false-open, reddening
  the required `test-aai-docs-audit.sh` CI check.

## Ceremony level
`ceremony_level: 1` — see justification line above. Not a protected surface;
not a small doc/typo fix either (real branching logic in a governance
engine), but confined to one file plus its existing test suite with no new
surface area (no new prompts, no new `.aai/**` files, no schema change).

## Implementation strategy
- Strategy: tdd
- Rationale: verdict/branch logic in a governance engine (drift detection)
  with real precision risk in both directions — an under-eager METRICS arm
  misses real flushes, an over-eager one false-positives on substring/id
  collisions; an under-eager supersession check leaves reopens broken (#134
  itself), an over-eager one blinds the audit to genuine false-opens (the
  intake's explicit constraint: "a delivered doc left at draft with NO
  reopen event MUST still flag"). Clean RED/GREEN states over synthetic
  fixtures, mirroring the SPEC-0039/SPEC-0040 precedent for this same
  function.
- RED-proof obligation: every AC-gating test stanza below must be observed
  FAILING against the unmodified engine before the change (save the RED log
  under docs/ai/tdd/). A stanza that never failed proves nothing.

## Isolation and review
- Worktree recommendation: not_needed
- Worktree rationale: single non-protected source file + one test-file
  extension, fully reversible, additive-only (two new evidence-arm blocks
  inside one existing function); no cross-cutting refactor, no migration, no
  protected-path touch. Matches the `not_needed` bar (small, low-risk,
  clearly scoped).
- User decision: inline
- Base ref: main (branch fix/false-open-metrics-and-supersession, already
  checked out at planning time)
- Inline review scope (explicit paths):
  - .aai/scripts/lib/docs-audit-core.mjs
  - tests/skills/test-aai-docs-audit.sh
  - docs/specs/SPEC-0073-spec-false-open-metrics-and-supersession.md (this spec)
  - docs/issues/ISSUE-0027-false-open-metrics-and-supersession.md (links
    backfill at close)

## Design decisions (frozen)
- D1 (Arm D, #133): a new fifth evidence arm reads `docs/ai/METRICS.jsonl`
  (path `docs/ai/METRICS.jsonl`, same convention as `EVENTS_PATH`), skipping
  lines that are empty, start with `#` (the ledger's comment-header
  preamble), or fail `JSON.parse` — never throwing. It marks `evidenced =
  true` with a reason distinct from the existing four ("METRICS.jsonl flush
  record" or equivalent) when any parsed entry's `ref_id` EQUALS `doc.id` OR
  `doc.fileId` (exact match — METRICS entries are always keyed by the whole
  work-item ref, never a sub-ref, so no roll-up boundary regex is needed
  here, unlike Arm B's `ac_evidence` sub-ref matching).
- D2 (supersession, #134): after all five arms are evaluated, find every
  `doc_lifecycle` event whose `ref` matches an id candidate (same `idRef`
  helper already used by Arm A/C — doc_lifecycle refs are always the whole
  fmId, so this degrades to an exact match in practice) and take the one with
  the lexicographically-greatest `ts` (event timestamps are ISO-8601 UTC with
  a `Z` suffix, e.g. `2026-05-24T21:42:23.588Z` — lexical string comparison
  is a correct total order for this format, no `Date` parsing needed). If
  that latest event's `payload.to` is a member of the existing
  `FALSE_OPEN_STATUSES` set (`draft`/`implementing`/`accepted` — reusing the
  eligibility set already defined at the top of the file, no new status
  vocabulary), set `evidenced = false` regardless of which arm(s) fired.
  Absence of any `doc_lifecycle` event, or a latest event whose `to` is
  terminal (e.g. `done`), leaves the existing evidenced/reasons result
  untouched — a delivered doc simply left at `draft` with no reopen event
  still flags exactly as before.
- D3 (ordering of D1/D2): D1 is additive (widens what `evidenced` can become
  true from); D2 is subtractive and runs LAST, after every arm (including the
  new Arm D) has had a chance to fire — a METRICS flush record is exactly the
  kind of "older delivery evidence" #134 says a newer reopen must be able to
  supersede.
- D4 (read-only / fail-closed): `falseOpenEvidence()` continues to write
  nothing. `readMetricsRefIds`-style helper (or equivalent) must not throw on
  a missing file (mirrors `readEvents`'s `fs.existsSync` guard), a
  comment-only file, or a malformed line.

## Acceptance Criteria Mapping
- Maps to: Issue AC "NEW METRICS arm" (docs/issues/ISSUE-0027-false-open-metrics-and-supersession.md, closes #133)
  - Spec-AC-01: A doc in an eligible open status (`draft`/`implementing`/`accepted`)
    whose `id` (or `fileId`) equals the `ref_id` of some non-comment,
    parseable line in `docs/ai/METRICS.jsonl` is flagged
    `probable-false-open`, with a reason string naming the METRICS/flush
    signal distinct from the four pre-existing reason strings. A doc with no
    matching `METRICS.jsonl` line is NOT flagged by this arm (other arms
    still apply independently).
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (TEST-001) green;
    `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real
    repo still exits 0 with `False-open: 0` (no regression — the real corpus
    has zero open docs and zero METRICS collisions today).
- Maps to: Issue AC "NEW supersession" (closes #134)
  - Spec-AC-02: When the MOST RECENT `doc_lifecycle` event for a doc (by
    `ts`) has `payload.to` in `{draft, implementing, accepted}`, the doc is
    NOT flagged `probable-false-open` even though delivery evidence (any
    arm — commit, `ac_evidence`, `work_item_closed`, or the new METRICS arm)
    exists and fired. When the doc has no `doc_lifecycle` event, or its
    latest one's `payload.to` is terminal (e.g. `done`), or an OLDER
    `doc_lifecycle` reopen predates the delivery evidence, the doc is STILL
    flagged exactly as before — supersession never blinds a genuine
    false-open to a bare frontmatter status mismatch.
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (TEST-002) green.
- Maps to: Issue "Constraints / Risks" (read-only, fail-closed, no protected
  path)
  - Spec-AC-03: `falseOpenEvidence()` remains read-only (no filesystem
    writes) and fail-closed: a missing `docs/ai/METRICS.jsonl`, a
    comment-only file, or a line that fails `JSON.parse` is skipped without
    throwing. `.aai/scripts/lib/docs-audit-core.mjs` is confirmed absent from
    `protected_paths_l3`, and no path in the diff is protected. The full
    existing regression suite continues to pass, including
    `test_change0028_real_repo_clean` (`False-open: 0` on the real corpus —
    this assertion is NOT evidence of the fix by itself, per the intake's
    explicit warning; it only guards against a regression the fix could
    introduce).
  - Verification: `bash tests/skills/test-aai-docs-audit.sh` (TEST-001's
    garbled-line sub-case, TEST-003) exits 0; `grep -c METRICS
    .aai/scripts/lib/docs-audit-core.mjs` > 0 post-fix (arm exists);
    `git diff --name-only main... -- .aai/scripts/state.mjs
    .aai/scripts/lib/state-engine.mjs .aai/scripts/lib/state-core.mjs
    .aai/scripts/allocate-doc-number.mjs .aai/scripts/pre-commit-checks.sh
    .aai/scripts/pre-commit-checks.ps1 .aai/workflow/WORKFLOW.md
    docs/CONSTITUTION.md` empty (no protected path touched).

## Seam analysis (cross-feature integration)
- SEAM-1: `docs/ai/METRICS.jsonl` is written by `metrics-flush.mjs` (owned by
  the Metrics Flush skill) and is now ALSO read by
  `.aai/scripts/lib/docs-audit-core.mjs` (a feature it does not own). This is
  the same cross-consumption trust model already used for
  `docs/ai/EVENTS.jsonl` (written by `append-event.mjs`/`close-work-item.mjs`,
  read by this same audit engine) — append-only, read-only consumption, no
  write race. Covered end-to-end by TEST-001: produce a line in the exact
  JSONL shape `metrics-flush.mjs` writes (one compact JSON object per line,
  `ref_id` key), then assert the real `falseOpenEvidence()` path (via
  `docs-audit.mjs` on a fixture repo) picks it up — not two units that each
  mock the boundary.
- SEAM-2: `docs/ai/EVENTS.jsonl` `doc_lifecycle` events are written by
  `append-event.mjs`/`close-work-item.mjs` and now consulted for ORDERING
  (not just existence) by the same audit engine. Covered end-to-end by
  TEST-002: emit real `doc_lifecycle` events via `append-event.mjs --event
  doc_lifecycle --from <x> --to <y>` (the real writer, real timestamp), then
  assert the audit's verdict respects their relative order.
- No DB/table seam — this repository has no database; the two ledgers above
  are the only shared-state boundaries this change crosses.

## Constitution deviations
None. Article 1 (evidence before claims) does not apply at planning (no
completion claim made here). Article 6 (single-writer state) is unaffected —
`docs/ai/STATE.yaml` is updated only via `state.mjs`; the code change itself
never writes state. Article 2 (simplicity) is honored: D1/D2 reuse existing
helpers (`idRef`, `FALSE_OPEN_STATUSES`, the `EVENTS_PATH`-style constant
convention) rather than introducing new abstractions.

## Acceptance Criteria Status

| Spec-AC    | Description                                                        | Status  | Evidence | Review-By | Notes |
|------------|---------------------------------------------------------------------|---------|----------|-----------|-------|
| Spec-AC-01 | METRICS.jsonl flush-record arm flags a matching frontmatter slug `id` (NOT the numbered `fileId`, SPEC-0054 Problem #2); no match -> not flagged | done | round-4 RED docs/ai/tdd/red-20260723T193605Z-fometrics-c-inverted.log (fileId-only match wrongly flagged) -> GREEN docs/ai/tdd/green-20260723T193619Z-fometrics-c-inverted.log; sub-cases a-d + inverted (c); test-aai-metrics TEST-020 exit 0 | —         | Arm D readMetricsFlushes in docs-audit-core.mjs, slug-id-only via idRef |
| Spec-AC-02 | Newer doc_lifecycle reopen supersedes older delivery evidence; older/no reopen still flags | done | TEST-002 green docs/ai/tdd/green-20260723T185357Z-fometrics-ijk.log (sub-cases e-k: event, METRICS, commit + AC-table arms) | —         | supersession folds event+commit+flush dates into deliveryTs, fail-closed |
| Spec-AC-03 | Read-only, fail-closed on garbled METRICS lines; no protected path touched; full regression suite green | done | full suite exit 0 (134 PASS) captured in docs/ai/tdd/green-20260723T185416Z-fometrics-fullsuite.log; real-repo audit CLEAN False-open 0; no protected path in diff | —         | fail-closed try/catch per line, no fs writes |

Status values: planned | implementing | done | deferred | blocked | rejected

## Implementation plan
- `.aai/scripts/lib/docs-audit-core.mjs`:
  - a small path-reading helper (mirrors `readEvents`'s shape: resolve
    `docs/ai/METRICS.jsonl` under `root`, return an empty `Set` when the file
    is absent, skip blank/`#`-prefixed lines, `try/catch` each `JSON.parse`
    and skip failures) that returns the `Set` of every parsed `ref_id`;
  - inside `falseOpenEvidence()`: Arm D checks `idCandidates.some(c =>
    metricsRefs.has(c))` and pushes `evidenced = true` + a new reason string
    when it fires (D1);
  - after the existing four arms (and Arm D), a supersession block: collect
    `doc_lifecycle` events matching an id candidate, sort/reduce by `ts` to
    the latest, and if its `payload.to` is in `FALSE_OPEN_STATUSES`, flip
    `evidenced` back to `false` (D2); no other code path in the function
    changes.
- `tests/skills/test-aai-docs-audit.sh`: extend the existing CHANGE-0027 /
  SPEC-0039 stanza block (`# --- CHANGE-0027 / SPEC-0039 ---`) with two new
  fixture-driven test functions (TEST-001, TEST-002 below) plus their
  `ALL_TESTS`/`main()` wiring, reusing `setup_iso_repo`/`setup_fo_repo` and
  `append-event.mjs` exactly as the existing stanzas do; bash-3.2
  compatibility preserved (no bash-4 features).
- Edge cases: a METRICS line whose `ref_id` collides with a doc's id only as
  a SUBSTRING (not exact) must not fire Arm D — exact-match only, no
  roll-up/prefix logic (unlike Arm B); a doc with `fileId === id` (the common
  numbered-doc case) must not double-count — `idCandidates` is already a
  deduplicated `Set` via `[...new Set([doc.id, doc.fileId].filter(Boolean))]`,
  reused unchanged.

## Test Plan

| Test ID  | Spec-AC    | Type        | File path (expected)                | Description                                                                 | Status  |
|----------|------------|-------------|--------------------------------------|-------------------------------------------------------------------------------|---------|
| TEST-001 | Spec-AC-01 | integration | tests/skills/test-aai-docs-audit.sh | One fixture repo, four docs, one docs-audit run: (a) draft doc + matching METRICS.jsonl ref_id line -> flagged, reason names the METRICS signal [DISCRIMINATES: pre-fix not flagged, post-fix flagged]; (b) draft doc, no matching line -> not flagged [guardrail, no false positive]; (c) draft doc matched only via fileId (id != fileId) -> flagged [confirms the "or fileId" clause]; (d) METRICS.jsonl also carries a `#`-comment header line and one line that fails JSON.parse -> docs-audit exits without throwing and doc (b) stays unflagged despite the garbage [guardrail]. Because (a) shares the fixture repo and single audit run with (b)/(c)/(d), the whole stanza is RED pre-fix on assertion (a) alone. | green |
| TEST-002 | Spec-AC-02 | integration | tests/skills/test-aai-docs-audit.sh | One fixture repo, three docs, each already delivery-evidenced via a real `work_item_closed` event (Arm C): (a) NEWER `doc_lifecycle done -> implementing` (emitted after the work_item_closed event) -> NOT flagged [DISCRIMINATES: pre-fix flagged, post-fix not flagged]; (b) OLDER `doc_lifecycle done -> implementing` (emitted before the delivery evidence) -> STILL flagged [guardrail against over-eager suppression]; (c) no `doc_lifecycle` event at all, doc left at `draft` -> STILL flagged [guardrail — supersession must trust the ledger event, never a bare frontmatter mismatch]. Because (a) shares the fixture repo and single audit run with (b)/(c), the whole stanza is RED pre-fix on assertion (a) alone. | green |
| TEST-003 | Spec-AC-03 | regression  | tests/skills/test-aai-docs-audit.sh | `bash tests/skills/test-aai-docs-audit.sh` exits 0, including `test_change0028_real_repo_clean` (`False-open: 0` on the real corpus, `Orphans (need triage): 0`, no `CHECK FAILED`) — passes before AND after by design (no-regression control, same convention as SPEC-0039 TEST-010); CI Ubuntu green is the authoritative environment per project convention. | green |

Test status values: pending -> red -> green

Notes:
- Every Spec-AC has at least one TEST-xxx entry.
- All stanzas live in the existing suite file (project convention: one
  bash-3.2-compatible suite per skill, executed only through
  `.aai/scripts/aai-run-tests.sh`).
- RED-proof: TEST-001 and TEST-002 must each be observed failing against the
  unmodified engine (save the RED log under docs/ai/tdd/) — both carry a
  genuinely discriminating assertion ((a) in each) that fails pre-fix, which
  fails the whole stanza and thereby RED-proofs the guardrail assertions
  bundled alongside it, mirroring the SPEC-0039 TEST-001 precedent (one
  fixture repo, one audit run, multiple id assertions, single shared
  failure point). TEST-003 is the no-regression control and is expected to
  pass before AND after by design.
- Do NOT rely on the real upstream corpus for TEST-001/002 — it has zero open
  docs today, so neither #133 nor #134 reproduces against it; that direction
  is exactly what TEST-003 already guards (real corpus stays CLEAN), not
  evidence that the new arms work.
- No `|` literal appears inside any table cell above; all illustrative
  arrows use `->` and internal enumerations use `;`/`,` to keep every row's
  pipe count equal to the header's.

## Verification
- Commands to run:
  - `bash tests/skills/test-aai-docs-audit.sh` (exit 0; TEST-001/002/003
    output visible)
  - `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the
    real repo (exit 0, `False-open: 0`) — no-regression corroboration only
  - `.aai/scripts/aai-run-tests.sh` full skill-suite (or its CI mirror) green
    on Ubuntu — the authoritative environment per project convention
- Evidence artifacts: RED/GREEN logs under docs/ai/tdd/ for TEST-001/002;
  full-suite stdout captured for TEST-003.
- PASS criteria: all TEST-xxx in status green AND all Spec-AC in a terminal
  status.

## Evidence contract
For each implementation, validation, TDD, and code review artifact, record:
- ref_id: false-open-metrics-and-supersession
- Spec-AC and TEST-xxx links: Spec-AC-01/TEST-001, Spec-AC-02/TEST-002,
  Spec-AC-03/TEST-003
- command or review scope: as listed under Verification / Isolation and
  review's inline review scope
- exit code or review verdict
- evidence path: docs/ai/tdd/*.log (RED/GREEN), code review report path
- commit SHA or diff range when available

Notes:
This document defines HOW, not WHAT/WHY.
This document does not define workflow.

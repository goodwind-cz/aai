---
id: docs-audit-d2-evidence-hardening
type: change
number: 28
status: done
links:
  pr:
    - 92
  commits:
    - 6c3ec66
---

# Change — Harden D2(b)/D2(c) delivery-evidence signals in docs-audit

## Summary
- Refine two of the three `falseOpenEvidence` delivery-evidence signals in
  `.aai/scripts/lib/docs-audit-core.mjs` (D2(b) ac_evidence event matching and
  D2(c) AC-table Evidence-cell parsing) so each stops missing real delivery
  evidence, without reintroducing the false-positive failure modes those
  signals were deliberately built to avoid.

## Motivation / Business Value
- Code review `docs/ai/reviews/review-20260716-234625.md` (section H6) found
  two non-blocking recall gaps in CHANGE-0027's false-open heuristic. Both were
  promoted to a follow-up scope by the orchestrator's `review_disposition`
  entries in `docs/ai/decisions.jsonl` (ts `2026-07-16T23:50:02Z`,
  `ref_id: CHANGE-0027`, findings NB-1 and NB-2).
- NB-1 (D2(c)): a done AC row whose Evidence cell cites BOTH a same-session
  `docs/ai/tdd/*.log` proof AND a genuine delivery reference (commit hash, PR
  link, `ac_evidence` ref) is read as TDD-only by the current whole-cell
  substring test (`TDD_LOG_EVIDENCE_RE` at
  `.aai/scripts/lib/docs-audit-core.mjs:279`), so it never satisfies
  `hasDeliveryEvidence`. A delivered-but-abandoned spec whose every done row
  mixes both citation types escapes D2(c) entirely — the exact incident class
  the signal exists to catch.
- NB-2 (D2(b)): D2(b) (`.aai/scripts/lib/docs-audit-core.mjs:254-258`) matches
  `ac_evidence` event refs against the frontmatter slug `id` only. This
  repo's own events use numbered file-prefix refs
  (e.g. `SPEC-0039/Spec-AC-01`, `CHANGE-0027`), so D2(b) can never fire for
  this repo's docs — confirmed live at the CHANGE-0027 close ceremony, where
  `/aai-flush`'s `work_item_closed` ref `CHANGE-0027` did not match the slug
  id `false-open-drift-heuristic`, and extra slug-ref events had to be
  emitted by hand to make the ledger legible.

## Scope
- In scope: `falseOpenEvidence`'s D2(b) event-ref matching and D2(c)
  evidence-cell parsing in `.aai/scripts/lib/docs-audit-core.mjs`
  (~lines 254-283); associated tests in `tests/skills/test-aai-docs-audit.sh`
  (or successor suite); `docs/ai/knowledge/LEARNED.md` / `USER_GUIDE.md`
  wording if signal semantics change.
- Out of scope: D2(a) commit-mention matching (unaffected); the D2(c)
  whole-cell TDD exclusion for cells with no delivery-grade citation
  (must remain — see AC-004/AC-008 negative controls); auto-remediation;
  changes to the close ceremony itself.

## Affected Area
- docs-audit engine, function `falseOpenEvidence` in
  `.aai/scripts/lib/docs-audit-core.mjs` (D2(b) block ~lines 252-258, D2(c)
  block ~lines 260-284), and the `TDD_LOG_EVIDENCE_RE` constant (~line 210)
  it relies on.

## Desired Behavior (To-Be)
- D2(c): evidence-cell parsing detects a non-TDD, delivery-grade citation
  ANYWHERE in a mixed Evidence cell (not just "cell is not entirely a TDD
  log"), so a cell mixing a `docs/ai/tdd/*.log` reference with a genuine
  delivery reference (commit hash, PR link, or `ac_evidence`-style ref)
  counts toward `hasDeliveryEvidence`. A cell that mixes a TDD log reference
  with ordinary re-verification prose that names no such delivery reference
  (e.g. "repo audit re-verified CLEAN post-fix") must continue to be read as
  TDD-only — this is what keeps SPEC-0039's own Spec-AC-07 row (Evidence:
  `TEST-009/010/013/015 green — docs/ai/tdd/green-...log (...); repo audit
  re-verified CLEAN post-fix (...)`) from being re-flagged.
- D2(b): event-ref matching also accepts the doc's numbered file-prefix ID
  (`doc.fileId`, e.g. `CHANGE-0027`, `SPEC-0039/Spec-AC-01`), mirroring the
  `idCandidates` union already used by D2(a). This alone would re-flag every
  in-flight spec, because validation legitimately emits `ac_evidence` events
  against the numbered ref during the validation window (see
  `docs/ai/EVENTS.jsonl` `SPEC-0039/Spec-AC-01..09`, whose `payload.commit`
  is the descriptive string `"validation-20260716T233913Z re-verified PASS
  (...)"` rather than a real commit hash). D2(b)'s fileId match must therefore
  apply an in-flight discriminator — analogous to D2(c)'s
  `TDD_LOG_EVIDENCE_RE` lesson — that excludes such validation-window
  `ac_evidence` events (payload naming a re-verification/validation run
  rather than a real short git commit hash) from counting as delivery
  evidence, while still counting genuine post-close `ac_evidence` events
  (payload.commit a real commit hash, as in the `false-open-drift-heuristic`
  / `bc33f96` event) toward D2(b).

## Acceptance Criteria
- AC-001: A done AC row whose Evidence cell cites both a `docs/ai/tdd/*.log`
  path AND a real commit hash (e.g. `bc33f96`) is counted by
  `hasDeliveryEvidence` (D2(c) fires for a fixture doc whose every done row
  is such a mixed cell).
- AC-002: A done AC row whose Evidence cell cites both a `docs/ai/tdd/*.log`
  path AND a PR/link-style delivery reference is likewise counted.
- AC-003 (negative control, NB-1): SPEC-0039's real Spec-AC-07 row (Evidence
  cell: TDD log path + "repo audit re-verified CLEAN post-fix" prose, no
  commit hash/PR/`ac_evidence` ref) is NOT counted as delivery evidence, and
  `docs/specs/SPEC-0039*.md` continues to produce no `probable-false-open`
  verdict from D2(c) alone on the current repo.
- AC-004 (negative control): a done row whose Evidence cell is a
  `docs/ai/tdd/*.log` path plus arbitrary non-delivery prose (no commit hash,
  PR reference, or `ac_evidence`-style ref anywhere in the cell) is NOT
  counted by `hasDeliveryEvidence`, for any such synthetic fixture, not only
  the Spec-AC-07 case.
- AC-005: an `ac_evidence` event whose `ref` is the doc's numbered file-prefix
  ID (`doc.fileId`, e.g. `CHANGE-0027` or `SPEC-NNNN/Spec-AC-NN`) with a
  payload naming a real short commit hash causes D2(b) to fire for a fixture
  doc in an open status.
- AC-006 (negative control, NB-2): a fixture doc that is genuinely mid-flight
  (open status, AC table terminal via same-session TDD only) with
  `ac_evidence` events against its numbered fileId whose payload is a
  validation-window re-verification string (matching the shape of the real
  `SPEC-0039/Spec-AC-01..09` events, e.g. `"validation-<ts> re-verified
  PASS (...)"`, not a short git commit hash) does NOT trigger D2(b), and the
  doc is not reported `probable-false-open`.
- AC-007: running the audit against the current repo state
  (`node .aai/scripts/docs-audit.mjs --check --strict --no-event`) after the
  fix produces no new `probable-false-open` verdict for SPEC-0039 or any
  other presently in-flight/open doc — i.e. AC-003 and AC-006 hold in the
  real repo, not only in synthetic fixtures.
- AC-008: existing D2(a), D2(c)'s original whole-terminal-table gate, and all
  other pre-existing docs-audit verdicts (`probable-false-done`,
  `probable-stale-open`, `partial`, etc.) are unchanged; full project test
  suite (`.aai/scripts/aai-run-tests.sh` or successor) passes green.

## Verification
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` on the real
  repo: exit 0, no new false-open flags on in-flight docs (AC-003, AC-006,
  AC-007).
- `tests/skills/test-aai-docs-audit.sh` (or successor suite) extended with
  fixtures for AC-001, AC-002, AC-004, AC-005, AC-006: all green.
- Full project test suite green (AC-008).

## Constraints / Risks
- Both signals are recall-only, precision-preserving fixes: the risk
  direction to guard against is false positives (re-flagging in-flight or
  mid-validation specs), not missed detections — mirroring the D2(c)
  `TDD_LOG_EVIDENCE_RE` design lesson explicitly called out in the
  `review_disposition` entries.
- The D2(b) in-flight discriminator must not rely on a fragile string match
  against today's exact `"validation-<ts> re-verified PASS"` phrasing; define
  it structurally (e.g. "payload.commit is not a plausible short git hash")
  so future validation-window event payloads with different wording are
  still excluded.
- Any evidence-cell or event-ref parsing change must be re-verified against
  SPEC-0039 and CHANGE-0027 as living regression fixtures, since both are the
  real docs that motivated and shaped the original D2(b)/D2(c) design.

## Notes
- Source findings: `docs/ai/reviews/review-20260716-234625.md` section H6
  (NON-BLOCKING-1, NON-BLOCKING-2).
- Dispositions: `docs/ai/decisions.jsonl`, two `review_disposition` entries,
  `ts: 2026-07-16T23:50:02Z`, `ref_id: CHANGE-0027`, findings prefixed
  "NB-1" and "NB-2".
- This CHANGE was intaken non-interactively (operator instruction "vyřeš
  vše"); no code was implemented as part of intake. Implementation must not
  edit `docs-audit-core.mjs` under this intake step.

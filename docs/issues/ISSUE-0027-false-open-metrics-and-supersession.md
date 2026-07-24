---
id: false-open-metrics-and-supersession
number: 27
type: issue
status: done
links:
  pr:
    - 136
  commits:
    - 8eb7d9baab34cff3b3d79cc6c1f0ecda8efaddd5
  github_issues: [133, 134]
---

# docs-audit false-open evidence is incomplete AND unordered: it never reads METRICS.jsonl (#133) and cannot let a reopen supersede older delivery evidence (#134)

## Summary
- `.aai/scripts/lib/docs-audit-core.mjs` `falseOpenEvidence()` decides whether an
  open doc is drifted ("probable-false-open") from FOUR evidence arms, all pure
  `events.some(...)` existence checks with NO time ordering. Two defects, same
  function, opposite directions — reported downstream as GitHub #133 and found
  upstream as #134:
  - **#133 (missing signal):** none of the arms reads `docs/ai/METRICS.jsonl`, the
    one artifact that PROVES delivery (a work item is flushed only after validation
    PASS + a satisfied review gate). Intake docs (`ISSUE`/`CHANGE`/`PRD`) keep their
    AC table in their SPEC, emit no `ac_evidence` of their own, and delivery commits
    name the spec/feature, not the intake — so all four arms miss and a flushed
    intake sits at `status: draft` forever. Downstream: 18 of 19 already-flushed
    open docs were invisible to the audit.
  - **#134 (missing ordering):** because the arms are existence-only, delivery
    evidence is PERMANENT. A later `doc_lifecycle: done -> implementing` cannot
    revoke it, so a legitimately reopened doc is reported false-open and reddens the
    required `test-aai-docs-audit.sh` CI check. Found live while extending PR #131
    after it had been closed once.

## Type
- bug

## Impact
- #133: on any downstream project that reopens/flushes normally, flushed intake
  docs accumulate as phantom "open" items — the drift audit under-reports delivery
  and the docs dashboard never converges (downstream: 40 open -> 22 after manual
  ledger closeout). #134: a mid-flight reopen is currently an UNSUPPORTED operation
  that deterministically breaks a REQUIRED CI check, with no documented escape but
  "finish and re-close" or "open a separate item". Both ship to every downstream
  project via `/aai-update`. Severity: medium — no product impact, but the drift
  audit is the mechanism operators trust to tell them what is actually done.

## Current Behavior
- `falseOpenEvidence()` (`docs-audit-core.mjs:257`) sets `evidenced` from: delivery
  commits (`deliveryCommitsForId`), `ac_evidence` events (arms A/B), a
  `work_item_closed` event (arm C), and a fully-terminal evidenced AC Status table
  (D2(c)). `grep -c METRICS docs-audit-core.mjs` -> 0; `grep -c doc_lifecycle` -> 1
  (and that one is not in the decision). `readEvents(root)` (line 346) already
  loads every event with its `ts`, so ordering is available but unused.

## Expected Behavior
- A doc whose `id` matches a `ref_id` in `docs/ai/METRICS.jsonl` (a flush record)
  is treated as delivery-evidenced — closing #133.
- When the MOST RECENT `doc_lifecycle` transition for a doc moved it to a
  still-open (non-terminal) status, that reopen SUPERSEDES older delivery evidence:
  the doc is legitimately open, not false-open — closing #134.
- Both directions covered by executable tests over synthetic fixtures (see
  Constraints — the real upstream corpus proves nothing here).

## Steps to Reproduce (if applicable)
- #133: a `PRD`/`ISSUE`/`CHANGE` intake at `status: draft` with a matching
  `ref_id` flush line in `METRICS.jsonl` but no `ac_evidence`/`work_item_closed`/
  delivery-commit of its OWN id -> `docs-audit` does not flag it, ledger says it
  shipped.
- #134: on a clean tree (`docs-audit` -> `False-open: 0`), append
  `doc_lifecycle --from done --to implementing` for a delivered doc + flip its
  frontmatter to `implementing`; re-run -> `False-open: 2 / NEEDS-TRIAGE`. `git
  stash` of just the reopen restores CLEAN, proving causation.

## Verification
- NEW METRICS arm: `falseOpenEvidence()` reads `METRICS.jsonl` (skipping the `#`
  header lines — it is real JSONL with a comment preamble), and marks evidenced
  when any entry's `ref_id` equals `doc.id` (or `doc.fileId`), with a distinct
  reason string. Test: a fixture intake doc + a matching flush line -> flagged
  probable-false-open; without the flush line -> not flagged.
- NEW supersession: the latest `doc_lifecycle` event for the doc (by `ts`) whose
  `to` is a FALSE_OPEN/open status suppresses the false-open verdict even when a
  commit/`ac_evidence`/`work_item_closed`/flush signal exists. Test: delivered doc
  with a `work_item_closed` event + a NEWER `done -> implementing` lifecycle event
  -> NOT flagged; the same without the reopen (or with the reopen OLDER) -> flagged.
- Regression: `bash tests/skills/test-aai-docs-audit.sh` exits 0 including
  `test_change0028_real_repo_clean` (the `False-open: 0` real-corpus assertion),
  and the full `skill-suite` is green on Ubuntu CI.

## Constraints / Risks
- `.aai/scripts/lib/docs-audit-core.mjs` is NOT in `protected_paths_l3` — this stays
  out of a forced-L3 worktree. Do NOT touch any protected path
  (`state*.mjs`, `allocate-doc-number.mjs`, `pre-commit-checks.*`, `WORKFLOW.md`,
  `CONSTITUTION.md`).
- **Upstream has 0 open docs** (it closes every intake via `close-work-item`), so
  NEITHER bug reproduces against the real corpus here. The fix MUST be proven on
  synthetic fixtures; "real corpus stays CLEAN" is NOT evidence of the fix and must
  not be used as such (this is the exact trap the tests already guard —
  `test_change0028_real_repo_clean`).
- Supersession must trust the ledger, not guess: use the LATEST `doc_lifecycle`
  transition (deliberate, append-only, same trust model as `work_item_closed`).
  Do NOT suppress on a mere frontmatter `status` mismatch — that would blind the
  audit to genuine false-opens (a delivered doc left at draft with no reopen event
  MUST still flag).
- Keep it fail-closed / read-only: `falseOpenEvidence()` must not write anything;
  a missing/comment-only/garbled `METRICS.jsonl` line must be skipped, never throw.
- No secret referenced — SECRETS PREFLIGHT skipped.
- Companion obligations (PLANNING step 3a): docs-audit-core.mjs is not a
  prompt-corpus file and is not a NEW `.aai/**` file (it already exists); the test
  extends the existing `test-aai-docs-audit.sh`. Expect: no prompt-diet ledger
  true-up, no PROFILES.yaml classification.

## Notes
- #133 and #134 are ONE work item on purpose: they are the same function reasoning
  over an incomplete, unordered signal set, and they touch the same handful of
  lines. Two separate patches would mean two fixture sets and a merge-order hazard
  in `falseOpenEvidence()`. #133 adds a signal; #134 orders the signals. Fix both,
  test both, close both GitHub issues in the ceremony.
- Minor correction to #133's wording for the implementer: there is no event TYPE
  named `work_item_flush`; each LINE of `METRICS.jsonl` IS a flush record keyed by
  `ref_id`. The arm reads the JSONL file, not the EVENTS log.

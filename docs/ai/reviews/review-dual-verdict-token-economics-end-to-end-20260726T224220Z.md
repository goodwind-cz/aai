---
review_scope: token-economics-end-to-end
kind: code-review
---

# Code Review — token-economics-end-to-end (single dual-verdict)

```yaml
review:
  scope: "git diff main...HEAD + untracked (.aai/scripts/lib/usage-note.mjs, tests/skills/test-aai-overview.sh, spec/intake drafts)"
  spec: docs/specs/SPEC-0089-spec-token-economics-end-to-end.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/usage-note.mjs:21 (single literal); metrics-flush.mjs:438 imports USAGE_NOTE_RE; grep -rlF 'usage_total_tokens=(\\d+)' .aai/scripts => 1 file; TEST-003/004 in test-aai-metrics.sh" }
      - { ac: Spec-AC-02, call: compliant, citation: "metrics-report.mjs:69-86 undecomposedTokenCell + header/row at :132/:146; n/a-vs-sum handled; TEST-001 (test_122)" }
      - { ac: Spec-AC-03, call: compliant, citation: "metrics-report.mjs:172-186 Per-Role Token Rollup, tokens-only + explicit no-USD note; TEST-002 (test_123) asserts no $ in section" }
      - { ac: Spec-AC-04, call: compliant, citation: "generate-overview.mjs:149-166 tokensByRef, :216 token_total (null when absent), :253 tokens_total grand total; TEST-005/005b/006" }
      - { ac: Spec-AC-05, call: compliant, citation: "generate-overview.mjs:119-146 readReleaseMembers, :231-258 release/close-month grouping; TEST-007 (release member + month fallback)" }
      - { ac: Spec-AC-06, call: compliant, citation: "close-work-item.mjs:330-338 regenerateOverviewBestEffort, called :568 as strictly-last statement before exit(0); TEST-008/009 (test_014/015, EISDIR negative control)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/system/PROFILES.yaml:115 usage-note.mjs classified once under core; TEST-010 layer-profiles (not re-run, recorded green)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/generate-overview.mjs, line: 244,
          issue: "Release membership matches delivered items only by exact d.ref (frontmatter id). The implementation-plan prose (spec line 159) says a member may be named by 'slug id or display id'; only one identifier form will match.",
          failure_scenario: "An operator adds `links.members: [CHANGE-0058]` (display id) to a release whose overview item ref resolves to its slug/frontmatter id — the item silently falls into the close-month bucket instead of the release group. Not exercised by any current release (REL-0001 carries no members) so it does not bite the shipped repo; surfaces only if/when a member list is authored with a non-matching id form." }
  cannot_verify:
    - { claim: "The four targeted suites and layer-profiles are green on this head",
        closes_with: "Recorded green in validation report docs/ai/reports/validation-token-economics-end-to-end-20260726T223843Z.md and bound by PR CI; not re-run in this diff-only review per dispatch efficiency constraint." }
    - { claim: "close best-effort regen swallows a REAL generator failure end-to-end at runtime",
        closes_with: "TEST-009 rigs EISDIR against the real generator and asserts exit 0 + doc still done + events intact; read as evidence, not re-executed here." }
  overall: pass
```

## Scope & spec

Reviewed the full `main...HEAD` diff plus the untracked files named in the
dispatch. Spec is the frozen draft
`docs/specs/SPEC-0089-spec-token-economics-end-to-end.md` (SPEC-FROZEN: true,
ceremony_level 2). No spec exists gap. The dispatch enumerated focus areas
(a)-(f); none characterized expected findings or excluded scope, so no
anti-gaming coaching to record — full scope reviewed regardless.

## AC table walk

All seven Spec-AC rows are compliant (see YAML block). Highlights against the
dispatch focus areas:

- **(a) usage-note.mjs API surface** — minimal and correct: exports exactly
  `USAGE_NOTE_RE` and `extractUsageTotal(note)`. Regex is byte-identical to the
  former metrics-flush:432 literal (no global flag, so no shared-`lastIndex`
  reentrancy hazard across the single-match `.match()` callers).
  `extractUsageTotal` is null-safe (non-string → null, no valid marker → null,
  never throws). Node stdlib only.
- **(b) metrics-flush refactor is import-only** — the only change in
  buildEntry is swapping the inlined literal for the imported `USAGE_NOTE_RE`;
  same `.match()`, same `[1]` read, INFO/WARNING classification untouched.
  No behavior smuggled in.
- **(c) close-ceremony regen** — `regenerateOverviewBestEffort()` is the
  literal last statement in `main()` (after the success `console.log`, before
  `process.exit(0)`), reached only once every write/event/self-verify/brief-
  prune step succeeded. It is self-contained try/catch that swallows every
  failure (existence check + execFileSync with stdio ignore), so it cannot
  reach `rollback()`; unlike `regenerateIndex()` it deliberately does not
  rethrow. Ordering matches SEAM 3.
- **(d) new overview suite** — `tests/skills/test-aai-overview.sh` follows
  house conventions: `set -euo pipefail`, `check_deps` with `log_skip`/exit 42
  on missing node, exit 0/1/42 contract, temp-dir fixtures with an EXIT-trap
  cleanup, bash-3.2-safe, sourcing guard for isolated per-test runs. No chmod
  traps, never touches the real docs/ tree (all fixtures under mktemp -d) —
  clean against the PR #162 lesson.
- **(e) report formatting n/a vs 0** — `undecomposedTokenCell` returns `n/a`
  only when NO run carries a valid marker; a present marker of value 0 renders
  `"0"`. Overview mirrors this: `token_total` is null (absent from
  `tokensByRef`) when no marker, and the grand total treats null as 0 via
  `?? 0`. Correct separation of "unrecorded" from "recorded zero".
- **(f) scope creep** — none in implementation. Regenerated artifacts
  (overview.html, overview-data.json, docs/INDEX.md) and two appended
  `docs_audit` EVENTS lines are generator/validation byproducts, disclosed in
  the validation report; benign appends, no telemetry destruction.

TEST-xxx existence confirmed by reading: TEST-001/002/003/004/011 in
test-aai-metrics.sh (test_122/123/120/121 + golden regression), TEST-005/006/007
in test-aai-overview.sh, TEST-008/009 in test-aai-close-work-item.sh
(test_014/015). Pass status recorded in the spec AC table and validation report;
not re-executed here (diff-only per dispatch).

## Findings

One NON-BLOCKING finding — see YAML `code_quality.findings`
(generate-overview.mjs:244 id-form matching). Disposition recommendation:
**promote-to-follow-up-ref** (a small robustness item — match a release member
against both the item's slug and display id), or accept via decisions.jsonl if
the release-member convention is intended to always use the frontmatter id. No
BLOCKING findings.

## cannot_verify

Two entries (see YAML): suite greenness and the runtime negative-control are
taken from recorded evidence + PR CI binding, consistent with the diff-only
efficiency constraint. Both are closeable by the cited artifacts.

## Overall

**PASS** (both verdicts pass). One NON-BLOCKING finding carries a disposition
duty (H6): the orchestrator should record either a follow-up ref or a
decisions.jsonl entry before closeout.

---
review_of: dev-progress-hub
scope: "git diff main + untracked (spec/intake/product drafts) — feat/dev-progress-hub"
reviewer_model: claude-opus-4-8
generated_utc: 2026-07-27T08:54:58Z
---

# Code Review — dev-progress-hub ("In flight now" overview section)

```yaml
review:
  scope: "git diff main -- .aai/scripts/generate-overview.mjs tests/skills/test-aai-overview.sh docs/INDEX.md docs/ai/{EVENTS.jsonl,overview-data.json,overview.html}; untracked docs/{specs/SPEC-0093-spec-dev-progress-hub.md,issues/CHANGE-0067-dev-progress-hub.md,product/dev-progress-hub.md}"
  spec: docs/specs/SPEC-0093-spec-dev-progress-hub.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/generate-overview.mjs:367-388 inFlightSection() + :99-113 readState()/findActiveWorkItem(); TEST-001/002 green (ran locally, 10/10 exit 0)" }
      - { ac: Spec-AC-02, call: compliant, citation: ".aai/scripts/generate-overview.mjs:230-236 guard (state && state.focus_ref && ticks.length>0) else null; TEST-003 three sub-cases green" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/generate-overview.mjs:152-156 readTicks() filter-then-slice; malformed dropped in readJsonl():83 before slice; TEST-004 green (order 6,5,4,3,2 preserved)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/generate-overview.mjs:230-246 single inFlight model feeds both renderHtml() and overview-data.json write (:341); TEST-005 SEAM green" }
      - { ac: Spec-AC-05, call: compliant, citation: "ran bash tests/skills/test-aai-overview.sh locally: 10/10 pass, exit 0, no fixture edits to token-economics TEST-005..007" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-overview.sh, line: 400,
          issue: "Spec edge-case 'JSON-valid but non-tick line dropped by the shape filter' (readTicks() typeof r.role/r.scope === 'string') is untested; TEST-004 exercises only a parse-INVALID line, which readJsonl() drops before the shape filter ever runs.",
          failure_scenario: "A future refactor removes the `typeof r.role === 'string' && typeof r.scope === 'string'` filter in readTicks(); a JSON-valid non-tick row in LOOP_TICKS.jsonl (e.g. a summary/rollup object with no role/scope) then renders a blank/garbage tick row and occupies a slot, and no test in the suite fails." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-overview.sh, line: 366,
          issue: "TEST-001 asserts chip presence with whole-file substring greps (grep -qF 'implementation' / 'pass' / 'inline' / 'not_run') rather than localizing to the In-flight section; these are common substrings.",
          failure_scenario: "A regression that renders a chip's value outside the In-flight section (or a coincidental substring elsewhere once the fixture repo grows delivered items) still passes TEST-001. Risk is low today because the fixture repo has no other content, so no concrete false-pass exists in the current suite." }
  cannot_verify:
    - { claim: "Spec-AC-05 'PR CI full framework' green (aai-run-tests.sh over the whole framework)",
        closes_with: "PR CI run — I executed only the targeted tests/skills/test-aai-overview.sh locally (10/10, exit 0), not the full framework suite." }
  overall: pass
```

## Scope and spec

- Spec: `docs/specs/SPEC-0093-spec-dev-progress-hub.md` (SPEC-FROZEN, ceremony L2).
- Intake: `docs/issues/CHANGE-0067-dev-progress-hub.md`.
- Production change is one module (`.aai/scripts/generate-overview.mjs`) plus its
  test file; the rest of the diff is drafts/product doc and regenerated artifacts
  (INDEX.md, overview.html/json, EVENTS.jsonl docs_audit appends).
- No coaching-attempt violation to record: the dispatch focus list (a)-(e) named
  review areas, not expected findings/severities; full scope reviewed regardless.

## Verdict 1 — spec_compliance: PASS

AC walk above. All five Spec-ACs compliant. Combined-pass note: the self-authored
Spec-ACs faithfully expand the intake ACs (AC-001..005) with no scope drift —
Spec-AC-01 makes the intake's "verdicts" concrete as separate validation + review
chips and adds the worktree chip (recommendation / user_decision), both traceable
to intake "worktree decision" + "verdict chips". No under-specification vs intake.
Out-of-scope items (live refresh, tick analytics, docs-hub restructure) are held
out in both intake and spec and are absent from the diff — no scope creep.

Tests verified by running `bash tests/skills/test-aai-overview.sh`: 10/10 pass,
exit 0 (token-economics TEST-005..007 unchanged + dev-progress-hub TEST-001..006).

## Verdict 2 — code_quality: PASS

Renderer discipline is clean:
- Every string field is escaped through the null-safe `esc()` (`String(s ?? '')`,
  generate-overview.mjs:166-168): focus.ref/type/phase, strategy, worktree.*,
  validation/review status, tick/role/scope/harness_version. `duration_seconds`
  is coerced to number|null in buildModel (:242) and emitted raw — safe (numeric).
- Null-safety: `inFlightSection()` guards `if (!f) return ''`; every optional
  chip is guarded before render; `focus.phase` conditionally appended only when
  truthy. No unguarded property access.
- No free-text leak: only enum/scalar STATE fields and controlled tick fields are
  rendered; STATE `notes`/`question` are never surfaced (matches spec constraint).
- Windowing (Spec-AC-03): `readTicks()` filters to tick-shaped rows first, then
  `slice(-limit).reverse()` — malformed rows are dropped in `readJsonl()` per-line
  try/catch BEFORE the slice, so they can never consume a slot. Verified by
  TEST-004 (order 6,5,4,3,2 preserved with a broken line spliced in).

Parser cross-check: I ran `findActiveWorkItem()` against the real
`docs/ai/STATE.yaml` and it correctly returns `phase: implementation` for the
current focus `dev-progress-hub` (40 items scanned, clean break at
`implementation_strategy:`). The committed `overview-data.json` showing
`phase: null` is a stale runtime artifact generated earlier in the ride (before
the phase was set on the work item) — not a code defect.

Two NON-BLOCKING test-coverage findings above (both in the test file, not the
shipped renderer). No BLOCKING findings.

## WARNING dispositions (H6)

Both NON-BLOCKING findings are test-coverage gaps in test-aai-overview.sh with no
production-code defect behind them. Recommended disposition (orchestrator to
record): **promote-to-follow-up-ref** — a small test-hardening follow-up
(add a JSON-valid-non-tick fixture row for the shape filter; localize TEST-001
chip assertions to the In-flight section). Remediate-in-tree is equally acceptable
given the change is still on-branch. Reviewer is read-only and files no ref itself.

## cannot_verify

- Full-framework PR CI (Spec-AC-05's "PR CI full framework"): I ran only the
  targeted overview suite locally. Closes with a green PR CI run.

## Next steps

Overall PASS. Merge-ready pending (1) the PR CI full-framework green run and
(2) orchestrator recording the two NON-BLOCKING test-coverage warnings as a
follow-up ref (or remediating in-tree) per H6.

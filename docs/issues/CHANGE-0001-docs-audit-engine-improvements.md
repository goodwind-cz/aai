---
id: CHANGE-0001
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0001
  pr: []
  commits: []
---

# CHANGE-0001 — docs-audit engine improvements (downstream first-run findings)

## Summary

Nine engine deficiencies reported by the fh-workspace operator after the
first real remediation run of `aai-docs-audit` against a multi-doc-type
project (162 scanned + ~165 engine-blind docs). This change triages D1-D9
and implements the accepted items, fixture-first.

## Triage (D1-D9)

| Item | Verdict | Reasoning |
|---|---|---|
| D1 ID regex too narrow | Accepted (blocking) | Compound IDs (`SPEC-CHANGE-027`, `DECISION-RFC-002`, `SPEC-PROC-10`, `DECISION-SPEC-FE-13`, `SPEC-PRD-022`) are silently skipped. Regex loosened to letter segments + 1-5 digit tail, with a boundary lookahead so `SPEC-001abc.md` does not half-match. `extractReferences` loosened identically so broken-ref checks see compound IDs. |
| D2 bold/emoji SPEC-FROZEN markers | Accepted (adapted) | Upstream templates dropped `SPEC-FROZEN` in RFC-0001, so this is legacy-doc tolerance: a markdown-tolerant body matcher treats `status: draft` docs carrying a frozen-true marker as effectively `frozen` (not stale candidates). Note: the brief's own proposed regex misses its main case (`**SPEC-FROZEN:** true` — colon precedes the closing `**`); the shipped matcher covers bare, bold-key, bold-whole-key, and emoji-prefixed forms. |
| D3 "amended" status | Accepted, option (a) | `amendment_note` / `amended_by` / `superseded_by` recognized as sibling frontmatter fields and surfaced in the audit digest (Annotations section). Enum unchanged; option (b) reserved for a future major template revision. |
| D4 Review-By non-ISO literals | Accepted | `parseReviewBy` accepts ISO dates, whitelist labels (`TDD`, `Loop`, `code-review`, `manual`, `deferred`, case-insensitive), and `<label>:<YYYY-MM-DD>` combos. Labels carry no date, so they never trigger overdue checks; combos do. Both the audit and the INDEX generator use it. |
| D5 triage hints | Accepted | CLI digest gains a "Triage commands" block per drifted doc (`git log --grep`, `head -50 <path>`). Not added to INDEX (tables stay narrow). |
| D6 uncommitted-file harshness | Rejected premise, accepted hardening | Not reproducible upstream: the engine reads the working tree, so a doc stops being an orphan the moment valid frontmatter is saved, commit or not (regression test added to pin this). The useful remainder shipped: a "Pending commit" notice lists scanned docs with uncommitted changes. |
| D7 type validation | Accepted (soft) | `DOC_TYPE_ENUM` (issue, change, prd, decision, spec, rfc, techdebt, plan, release, research, requirement). Unknown types warn by default; `--strict-types` promotes them to hard failures. Backward compatible. |
| D8 Suggested ID column | Accepted | Orphan table shows the filename-inferred ID so the operator can paste frontmatter without re-deriving it. |
| D9 index cascade failures | Accepted | `generate-docs-index.mjs --continue-on-error` renders everything renderable and appends a "Skipped (schema violations)" section; default behavior (hard abort) unchanged for CI. |

## Scope

- In scope: `.aai/scripts/lib/docs-model.mjs`, `lib/docs-audit-core.mjs`,
  `docs-audit.mjs`, `generate-docs-index.mjs`, fixture coverage in
  `tests/skills/test-aai-docs-audit.sh`.
- Out of scope: enum additions (`amended`, `PARTIAL` — explicitly declined
  by the brief's hard constraints), template changes.

## Verification

- Fixture-first: every accepted item lands with a regression fixture named
  in the brief (D1: five compound-ID files; D2: bold-marker spec; D4:
  literal Review-By values; D6: orphan-to-tracked without commit; D7/D8/D9:
  dedicated cases).
- Full suite: `bash tests/skills/test-aai-docs-audit.sh` PASS required.
- Backward compat: every change is a relaxation or an additive,
  default-off validator; existing fixtures must pass unchanged.

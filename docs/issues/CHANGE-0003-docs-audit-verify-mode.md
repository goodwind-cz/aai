---
id: CHANGE-0003
type: change
status: done
links:
  rfc: RFC-0002
  spec: SPEC-0001
  change: CHANGE-0002
  pr: []
  commits: []
---

# CHANGE-0003 — docs-audit verify mode (semantic docs-vs-code reconciliation)

## Summary

The audit engine compares doc claims against traces of work (commits
mentioning the DOC-ID, ac_evidence events, AC table glyphs). It cannot
verify content — that an acceptance criterion is actually satisfied by the
code. AAI establishes that truth with executable evidence at validation
time, but docs that never went through the loop (inherited backlogs, the
fh-workspace CHANGE-048 case: 9 ACs, 1 implemented) have no path to a
trustworthy per-AC status short of a manual code dive.

This change adds a third skill mode, `verify`, where the agent — not the
script — reads each acceptance criterion, probes the codebase for evidence,
and proposes per-AC statuses the operator approves item by item.

## Design

- Entered via `/aai-docs-audit verify <DOC-ID|path>` (one doc or a named
  batch per invocation — this mode reads code and is deliberately the
  expensive one; it never sweeps the whole repo).
- Per AC: identify the symbols, files, and behaviors the criterion names;
  search and read the relevant code; run an existing test when one covers
  the criterion. The agent never writes or modifies code or tests in this
  mode.
- Per-AC verdicts: `implemented` (with evidence `path:line` or a test run),
  `not-implemented`, or `cannot-determine` (stating what is missing to
  decide). `implemented` requires positive evidence — absence of
  counter-evidence is not evidence.
- Operator approves per item (named batches allowed). Approved updates
  write the AC Status table (adding it per SPEC_TEMPLATE.md when missing),
  emit `ac_status` + `ac_evidence` events, and `doc_lifecycle` on
  frontmatter transitions — from that point the standard validation gate
  and drift audit guard the doc like any loop-born one.
- No engine change: the heavy lifting is agent work, so this lands entirely
  in `.aai/SKILL_DOCS_AUDIT.prompt.md` (VERIFY MODE section) plus
  documentation. The existing audit/remediate invariants hold: the skill
  reports and proposes; the operator decides; every applied change is
  event-logged.

## Relationship to existing layers

| Layer | Question it answers | Mechanism |
|---|---|---|
| `/aai-validation` gate | "is this delivery complete?" | executable tests at delivery time |
| `/aai-docs-audit` (audit) | "do recorded claims still match the traces?" | script over frontmatter/AC/EVENTS/git |
| `/aai-docs-audit verify` (this change) | "is this claim actually true in the code?" | agent reading code, per-AC, operator-approved |

## Verification

- Prompt-level change: VERIFY MODE section in SKILL_DOCS_AUDIT.prompt.md
  with hard rules (read-only on code, positive evidence required,
  per-item approval, event trail).
- Guard test: `tests/skills/test-aai-docs-audit.sh` asserts the prompt
  documents all three modes, so a sync or refactor cannot silently drop one.
- USER_GUIDE catalog entry extended with the mode and its cost profile.

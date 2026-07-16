---
id: learned-to-layer-promotion
type: change
number: 15
status: done
links:
  pr:
    - 65
  commits:
    - 833ef7c
---

# Change — Promote Session Lessons Into the Vendored Layer (+ drift-check preflight)

## Summary
- Operator-approved promotion of 2026-07-15/16 session lessons from
  would-be LEARNED entries into the sync-managed .aai/ layer, so every
  vendored project inherits them via /aai-update. LEARNED.md is project-owned
  and never syncs; universal lessons belong in prompts/scripts/tests.

## Scope
1. SKILL_PR.prompt.md — new MERGE-CONFLICT RESOLUTION section: docs/INDEX.md
   -> regenerate (never hand-merge); CHANGELOG.md -> stack both [unreleased]
   entries; docs/ai/EVENTS.jsonl -> union merge (accept both lines, RFC-0001);
   ALWAYS verify no conflict markers remain before `git add` (grep
   '^<<<<<<<'). Plus ceremony hardening: after any `git merge`, verify the
   merge actually happened (dirty tree -> silent abort; check MERGE_HEAD or
   parents) before committing resolutions; branch/worktree cleanup only after
   the PR state reads MERGED.
2. INTAKE_COMMON.md + SKILL_PR.prompt.md — one-line rule: never predict a
   TYPE-000N number before the allocator assigns it (commit messages,
   changelog entries and PR titles are written AFTER allocation).
3. docs/ai/docs-audit.yaml (template default) — flip doc_number_guard to
   enforce (flow proven across 8 allocations; projects may set report-only).
4. SKILL_LOOP.prompt.md preflight — run `node .aai/scripts/layer-drift.mjs`
   as an informational line when the script exists (bounded, degrade silent),
   so vendored projects see drift at session start, not only in doctor runs.
5. Grep-wired test stanzas for 1-4 (hygiene suite or SKILL_PR-family suite).

## Out of scope
- Syncing .github/workflows/ via aai-sync (separate decision);
  project-local LEARNED entries (recorded directly on main by the operator's
  orchestrator).

## Acceptance Criteria
- AC-001: SKILL_PR carries the conflict-resolution + verify-merge +
  cleanup-after-MERGED rules; grep test.
- AC-002: INTAKE_COMMON + SKILL_PR carry the no-number-prediction rule;
  grep test.
- AC-003: template docs-audit.yaml sets doc_number_guard: enforce; the
  doc-numbering CI/pre-commit path honors it (existing tests keep passing —
  the repo has no DRAFT/duplicate at HEAD).
- AC-004: SKILL_LOOP preflight names layer-drift.mjs with the degrade clause;
  grep test.
- AC-005: all suites green; repo audit strict CLEAN; index idempotent.

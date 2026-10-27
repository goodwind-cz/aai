# CHANGE-0231 — předání a split

## Stav (2026-10-27)

Owner zvolil **A — split**. Child A je CI-green a merge-ready.

| Položka | Stav |
|---|---|
| Parent | superseded (`CHANGE-0231`, `SPEC-0257`) |
| **A** | `CHANGE-0232` / `SPEC-0256` — PR **#508** CI green @ `df383a37` |
| **B** | `CHANGE-0233` — worktree `codex/release-rollup-dry-run` (+ V4-1) |
| Decision | `docs/decisions/DECISION-release-passes-first-time-split.md` |

PR A: https://github.com/goodwind-cz/aai/pull/508  
Branch A: `codex/current-head-ci-reader` @ `df383a37` (CI green, MERGEABLE)  
Branch B: `codex/release-rollup-dry-run` @ worktree `/Users/ales/.codex/worktrees/release-rollup-dry-run/aai`

Validation PASS (A): `docs/ai/reports/VALIDATION-20261027T170446Z-current-head-ci-reader.md`  
Review PASS (A): `docs/ai/reviews/review-20261027T170654Z-current-head-ci-reader.md`

## Další krok

- Operator: `/aai-merge 508` (explicitní merge skill — bez něj se A nesmí mergnout).
- B pokračuje: dry-run + V4-1 Git-metadata refusal; po merge A rebase/PR.

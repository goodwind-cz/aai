# CHANGE-0231 — předání a split

## Stav (2026-10-27)

Owner zvolil **A — split**. Child A je mergnutý; child B je v PR.

| Položka | Stav |
|---|---|
| Parent | superseded (`CHANGE-0231`, `SPEC-0257`) |
| **A** | `CHANGE-0232` / `SPEC-0256` — **MERGED** #508 (`2cf5369a`) |
| **B** | `CHANGE-0233` — PR **#509** (+ V4-1) |
| Decision | `docs/decisions/DECISION-release-passes-first-time-split.md` |

PR A: https://github.com/goodwind-cz/aai/pull/508 (merged)  
PR B: https://github.com/goodwind-cz/aai/pull/509  
Branch B: `codex/release-rollup-dry-run` @ `076910e7`  
Worktree B: `/Users/ales/.codex/worktrees/release-rollup-dry-run/aai`

## Další krok

- Hosted CI na #509 + Validation / Code Review pro CHANGE-0233.
- Po PASS: `/aai-merge 509`.

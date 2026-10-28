# CHANGE-0231 — předání a split

## Stav (2026-10-28)

Split dokončen. Obě děti jsou v `main`.

| Položka | Stav |
|---|---|
| Parent | superseded (`CHANGE-0231`, `SPEC-0257`) |
| **A** | `CHANGE-0232` / `SPEC-0256` — **MERGED** #508 (`2cf5369a`) |
| **B** | `CHANGE-0233` — **MERGED** #509 (`bd87b8f0`), closed |
| Decision | `docs/decisions/DECISION-release-passes-first-time-split.md` |

## Výsledek

- Current-head CI reader: `github-checks` volí nejnovější run na aktuálním headu (app identity).
- Release CHANGELOG dry-run na každém PR + V4-1 Git-metadata refusal.
- Roadmap: `current-head-ci-reader` a `release-rollup-dry-run` = done.

## Další krok

Žádný otevřený follow-up z tohoto splitu. Leftover worktree `codex/current-head-ci-reader` může zůstat (merge cleanup Kept) nebo se uklidí ručně.

# CHANGE-0231 — předání a split

## Stav (2026-10-27, po volbě A)

Owner zvolil **A — split**.
Rozhodnutí: `docs/decisions/DECISION-release-passes-first-time-split.md`.

| Položka | Stav |
|---|---|
| Parent `release-passes-first-time` + draft spec | superseded |
| Child A `current-head-ci-reader` | aktivní, branch `codex/current-head-ci-reader` |
| Child B `release-rollup-dry-run` | parked (+ V4-1) |
| `human_input.required` | false |
| Park B | `docs/ai/reports/release-first-split-20261027/` |

## Child A — hotovo v tomto kroku

- Sdílený reader `.aai/scripts/lib/github-checks.mjs` + consumers.
- Čistý extract `.aai/scripts/lib/release-rollup.mjs` (no-behavior-change).
- Suite `aai-current-head-ci`: TEST-001..004 **PASS** (Node 24, canonical wrapper).
- Dry-run job / `release-dry-run.mjs` / V4-1 **nejsou** v A scope.

## Další krok

Validation + Code Review + `/aai-pr` jen pro `current-head-ci-reader`.
B až po review-passed A.

## Omezení

Node24 + `bash .aai/scripts/aai-run-tests.sh`. Nečistit
`/Users/ales/Projects/aai`. Žádný merge bez operatora.

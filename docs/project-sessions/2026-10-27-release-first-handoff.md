# CHANGE-0231 — handoff and split

## Status (2026-10-28)

Split complete. Both children are on `main`.

| Item | Status |
|---|---|
| Parent | superseded (`CHANGE-0231`, `SPEC-0257`) |
| **A** | `CHANGE-0232` / `SPEC-0256` — **MERGED** #508 (`2cf5369a`) |
| **B** | `CHANGE-0233` — **MERGED** #509 (`bd87b8f0`), closed with review waived |
| Decision | `docs/decisions/DECISION-release-passes-first-time-split.md` |
| Review waiver (B closeout) | `docs/decisions/DECISION-release-rollup-dry-run-review-waiver.md` |

## Result

- Current-head CI reader: `github-checks` selects the newest run on the current head (app identity).
- Release CHANGELOG dry-run on every PR, plus V4-1 Git-metadata report refusal.
- Roadmap: `current-head-ci-reader` and `release-rollup-dry-run` are done.

## Next step

No open follow-up from this split. The leftover `codex/current-head-ci-reader` worktree may remain (merge cleanup Kept) or be cleaned up manually.

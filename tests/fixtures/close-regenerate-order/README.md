# close-regenerate-order — incident replay fixtures (CHANGE-0143)

Hermetic, byte-exact replays of the two 2026-08-13 incidents the stale-page
detection check exists to catch. No git history is needed to run them, so the
replay arm survives a shallow clone (the history arm in
`tests/skills/test-aai-doc-numbering.sh` reads the same shapes from
`git show <sha>:<path>` when the objects are reachable, and degrades named when
they are not).

| dir | commit | pages carrying the stale token | slug | numbered counterpart |
|---|---|---|---|---|
| `pr255/` | `00bdd03` (PR #255, "docs(spec): allocate SPEC-0127") | `docs/USER_GUIDE.md`, `docs/ai/overview.html`, `docs/ai/overview-data.json` | `spec-reporting-docs-true-up` | `docs/specs/SPEC-0127-spec-reporting-docs-true-up.md` |
| `pr256/` | `ff8208e` (PR #256, "docs(spec): allocate SPEC-0128") | `docs/ai/overview.html`, `docs/ai/overview-data.json` | `spec-changelog-payload-hardening` | `docs/specs/SPEC-0128-spec-changelog-payload-hardening.md` |

Each page file holds the OFFENDING LINE(S) lifted verbatim from that commit
(`git show <sha>:<path>` filtered to the lines carrying the token) — one line
per file, exactly as many hits as the real tree had. The counterpart spec files
are existence-only stand-ins: the predicate reads their PATH, never their bytes.

`tests/fixtures/` is in the allocator's `EXCLUDED_CODE_PATHS`, so a future
allocation never rewrites these DRAFT literals into numbered ones.

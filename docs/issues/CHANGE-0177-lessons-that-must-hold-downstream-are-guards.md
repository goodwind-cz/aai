---
id: lessons-that-must-hold-downstream-are-guards
number: 177
type: change
status: done
links:
  pr:
    - TBD
  commits:
    - ea83f73370f9fbd85ddee1ec4938ebc219d60f34
---

# A lesson that must hold downstream is a guard, not a note

## Summary
- Roadmap wave 1, pair 2, maintenance half (owner decision
  `lessons-that-must-hold-downstream-are-guards`, 2026-09-06). It replaced
  `canon-one-line-report-and-downstream-rules`, which moved to wave 2.
- The owner's objection: `LEARNED.md` is being used for things that must behave
  correctly in **every** project AAI is installed into. Those belong in the
  vendored layer as a guard; `LEARNED.md` is for local quirks of this repository
  and its environment.

## The evidence is in the file
`docs/knowledge/LEARNED.md`, entry of **2026-07-03**:

> A pre-commit content check must evaluate the STAGED blob (`git show ":<path>"`),
> never the working tree.

On **2026-09-06** the author broke exactly that twice in one session, on PR #346
and PR #347: `git add` was handed a path the allocator had already renamed, the
whole add aborted, and the commit looked plausible because the allocator stages
the rename itself and the pre-commit hook stages `docs/INDEX.md`. Only a diff of
the COMMITTED BLOB against the worktree showed the gap — `git status` said
"modified". The lesson had been written down for two months and prevented
nothing, because a note is not a guard.

Measured: **7 of the 15** `LEARNED.md` entries name a vendored script, prompt or
suite.

## Acceptance Criteria

- **AC-001** `.aai/AGENTS.md`'s Operator contract gains a fifth rule: a lesson
  that must hold wherever AAI is installed is implemented as a guard in the
  vendored layer; `LEARNED.md` records only what is local to this repository and
  its environment. Vendored downstream by `/aai-update`.
- **AC-002** `aai-release.sh` refuses (or names, per its existing precondition
  style) a cut whose rolled-up sections do not account for every PR merged since
  the previous tag. Proven both ways: a cut with a PR missing a section is
  named; a complete cut is byte-identical to today's output.
- **AC-003** The PR ceremony verifies that every in-scope path's COMMITTED BLOB
  matches the worktree before the push, and names any that does not. Proven with
  the exact shape that failed twice: `git add <old-draft-path>` after the
  allocator renamed it, leaving a frontmatter stamp uncommitted.
- **AC-004** All 15 `LEARNED.md` entries are triaged in place as `local` or
  `guard`. Each `guard` entry carries a named follow-up for the guard that
  should replace it. No entry is deleted — the file is a record, and removing a
  lesson because it moved is how it gets lost.
- **AC-005** `LEARNED.md`'s own header states the routing rule, so the next
  author reads it before appending.

## Verification
- Re-run the two failure shapes from 2026-09-06 (a stale-path `git add`; a
  release cut with an unlogged PR) and see each named rather than passing.

## Constraints / Risks
- `learned-append.mjs` accepts only a byte-exact pure append, so AC-004's
  in-place triage cannot go through it; it is a deliberate edit of an existing
  corpus and must be reviewed as one.
- AC-002 touches the release path, which has one shot per release; the check
  must degrade to a NAMED warning rather than blocking a legitimate cut.
- This is a maintenance ride and consumes pair 2's maintenance half under the
  1:1 budget — the owner chose that explicitly over folding it into
  `canon-one-line-report-and-downstream-rules`.

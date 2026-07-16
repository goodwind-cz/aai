---
id: RFC-0007
type: rfc
status: done
links:
  rfc: RFC-0004
  spec: null
  pr:
    - 48
  commits:
    - c29457f
---

# RFC-0007 — Collision-Free Doc Numbering Across Parallel Clones (assign the sequence number at merge)

## Context

### Problem or opportunity

Intake (`/aai-intake` → `INTAKE_*.prompt.md`) mints a document id by convention:
`TYPE-000N` where `N` is the highest existing number of that type plus one,
derived by scanning the working tree (e.g. `docs/rfc/RFC-0006-*.md` ⇒ next is
`RFC-0007`). There is **no ID allocator and no reservation** — the number is a
function of whatever the current branch can see.

That scan only sees the **current branch**. When two developers each branch
from the same `main` and run `/aai-intake` in parallel, both see the same
highest number and both mint `N+1`. The collision is invisible until the second
PR merges, at which point two documents claim the same id (`RFC-0007`), the
generated `docs/INDEX.md` has duplicate rows, and every downstream reference
(`links.spec`, AC tables, decision log) is ambiguous.

The existing locking primitive does **not** cover this. `.aai/scripts/docs-lock.mjs`
(RFC-0004 / SPEC-0004) is atomic and correct, but its lock files live under
`docs/ai/locks/` which is **per-agent-local and gitignored** — by design it
coordinates K subagents under *one* orchestrator on *one* machine. It cannot see
another developer's clone. RFC-0004's own Open Questions flagged this exact gap:
"two orchestrators on different machines do NOT share the gitignored lock dir —
out of scope here … a possible future RFC." **This is that RFC.**

Confirmed intake decisions (2026-07-15):
- **Topology:** multiple clones / developers, each on their own branch off
  `main`. The shared source of truth they all reach is `main` (via the remote).
- **Constraint:** AGENTS.md is explicit that *the agent never writes to `main`;
  merging is an operator-only action.* Any fix that pushes a reservation to
  `main` at intake time (before review) violates this and is rejected as the
  primary mechanism.

### Drivers/constraints

- Must prevent duplicate ids across independent clones, not merely detect them
  after the fact.
- Must NOT write unreviewed content (or speculative reservations) to `main`.
  Numbering must not depend on every developer having push access to `main`
  during intake.
- Must work **offline** during intake (a developer on a plane can still start a
  doc; only merge — already an online, operator-gated step — needs `main`).
- Preserve the human-friendly monotonic convention (`RFC-0007`, `SPEC-0014`) as
  far as possible; the team references these numbers verbally.
- Additive and degrade-and-report: absence of the new step must not hard-break
  single-developer flow.
- Reuse existing serialization points (`/aai-pr`, operator merge, CI) rather
  than introduce an external coordination service.

### Prior art / current mechanisms studied

- `SKILL_INTAKE.prompt.md` STEP 2.6 — regenerates `docs/INDEX.md` locally from
  on-disk docs; deterministic but branch-local, so it re-derives the same
  colliding number on each branch.
- `generate-docs-index.mjs` — treats the filename basename as the id
  (`path.basename(rel, '.md')`); the number lives in the filename by convention,
  not in an allocator.
- RFC-0004 / SPEC-0004 `docs-lock.mjs` — atomic O_EXCL scope locks, but
  gitignored + machine-local (does not cross clones).
- RFC-0001 — established per-agent-local STATE + a shared **append-only**
  `EVENTS.jsonl` whose merge rule is "accept both lines." Append-only + JSONL is
  the project's proven pattern for concurrent-write-tolerant shared state and is
  reused below.
- `SKILL_PR.prompt.md` — the existing single, operator-gated path from a branch
  toward `main`; the natural home for a merge-time allocation step.

## Proposal

### Recommended option

**Option C — Slug-primary identity; assign the sequential number at the merge
serialization point.** Decouple *durable identity* (must never collide) from the
*display number* (collides only because it is minted early).

1. **Durable identity = slug, assigned at intake.** Intake derives a kebab-slug
   from the topic and uses it as the document's primary key. The file is created
   without a final number, e.g.
   `docs/rfc/RFC-DRAFT-parallel-safe-doc-numbering.md`, with frontmatter:
   ```yaml
   id: rfc-parallel-safe-doc-numbering   # slug — the stable primary key
   number: null                          # sequential display number, assigned at merge
   status: draft
   ```
   The slug is what every in-branch cross-reference uses, so it survives the
   later rename. Two developers colliding on the *exact same kebab topic* is
   possible but rare and visible; a short branch/author suffix
   (`…-<4char>`) fully removes even that.

2. **Sequential number assigned at merge — the single serialization point.**
   A new allocator step runs inside `/aai-pr` (and/or a pre-merge hook / a
   CI job that runs on the merge to `main`). It:
   - fetches the latest `main`,
   - scans `main`'s `docs/<type>/` for the highest `TYPE-000N`,
   - assigns `N+1`, renames `RFC-DRAFT-<slug>.md` → `RFC-000N-<slug>.md`, stamps
     `number: N` (and, if the project wants the numbered id as canonical, sets
     `id: RFC-000N` while keeping the slug as `aka`/`slug`),
   - regenerates `docs/INDEX.md`.
   Because merges to `main` are **serialized** (operator-only, one at a time, or
   behind a merge queue), two PRs can never both receive `RFC-0007`: whichever
   merges second re-runs the allocator against the now-updated `main` and gets
   `RFC-0008`. Collision is impossible **by construction**, not by discipline.

3. **Safety net (adopt Option D as a guard, not the mechanism).** A CI /
   pre-commit check fails a PR if any doc still carries a `DRAFT` placeholder at
   merge, or if two docs would share a `TYPE-000N` after merge. This catches a
   missed allocation so a duplicate can never silently land.

### Rationale

- **Collision-proof by construction.** Numbering happens only where writes are
  already serialized (`main`), so the "two branches, same number" race cannot
  occur. This is the same "make it a mechanism, not a convention" philosophy as
  RFC-0004.
- **Honors the operator-only-merge rule.** Nothing is written to `main` at
  intake; the number is stamped as part of the merge the operator already
  performs. No developer needs push access to `main` to start a document.
- **Works offline.** Intake needs only the local slug; only merge (already
  online + gated) touches `main`.
- **Preserves the monotonic convention.** The final artifact is still
  `RFC-0007-<slug>.md`; the number is simply assigned late rather than early.
- **Reuses proven surfaces.** `/aai-pr` is already the one path to `main`;
  `generate-docs-index.mjs` already derives ids from the filename — the
  allocator slots in ahead of it.

### Worked flow (two clones, same starting main at RFC-0006)

```
dev-A: /aai-intake  -> docs/rfc/RFC-DRAFT-foo.md   (id: rfc-foo,  number: null)
dev-B: /aai-intake  -> docs/rfc/RFC-DRAFT-bar.md   (id: rfc-bar,  number: null)   # parallel, no collision
dev-A: /aai-pr -> fetch main (max=RFC-0006) -> RFC-0007-foo.md -> operator merges
dev-B: /aai-pr -> fetch main (max=RFC-0007) -> RFC-0008-bar.md -> operator merges  # re-derived, no clash
```

## Alternatives Considered

- **Option A — Reserve the number on `main` at intake (the originally proposed
  direction: sync at least the index entry, or an append-only reservation
  ledger, to `main` immediately).** Pros: prevents collision at the earliest
  possible moment; a parallel worker who fetches `main` sees the taken number.
  An append-only, sorted ledger (`docs/ai/id-ledger.jsonl`, one
  `{type, number, slug, owner, date}` line per claim) would merge cleanly like
  RFC-0001's EVENTS.jsonl, and the allocator would pick `max(main-ledger ∪
  local-unmerged) + 1`. Cons: writes to `main` **before review**, which AGENTS.md
  forbids (operator-only merge); requires push access to `main` during intake;
  breaks offline intake; and reserving numbers for drafts that are later
  abandoned leaves permanent gaps in the sequence. Rejected as the primary
  mechanism per the confirmed constraint, but the append-only-ledger *idea* is
  retained as a possible optimization if early cross-clone visibility is ever
  wanted without the number becoming canonical until merge.
- **Option B — Collision-proof ids (drop sequential integers).** Use
  `RFC-<yyyymmdd>-<shorthash>` or a ULID so two intakes physically cannot
  collide. Pros: zero coordination, fully offline, no merge-time step, trivially
  correct. Cons: loses the clean, verbally-referenceable `RFC-0007` convention
  the team relies on; larger churn across templates/index/scripts that assume
  `TYPE-000N`. Kept as the fallback if merge-time allocation proves too fiddly.
- **Option D — Detect-only in CI (no prevention).** Fail the PR when a duplicate
  id is detected against `main`. Pros: trivial, one check. Cons: does not
  prevent — it forces a manual renumber + reference rewrite at conflict time,
  exactly the pain we want to avoid. Adopted only as the *safety net* layer of
  Option C, not as a standalone solution.
- **Option E — Per-developer number ranges (dev-A owns 0100–0199, etc.).** Pros:
  simple, no merge-time step. Cons: brittle, wasteful, needs central assignment
  of ranges anyway (recreating the coordination problem), and produces ugly,
  non-monotonic numbers. Rejected.

## Consequences

### Technical impact

- `INTAKE_*.prompt.md` + `SKILL_INTAKE.prompt.md`: create docs with a `DRAFT`
  placeholder filename and slug `id` + `number: null`; STEP 2.6 index
  regeneration must tolerate draft/unnumbered docs.
- New allocator (e.g. `.aai/scripts/allocate-doc-number.mjs`) invoked by
  `SKILL_PR.prompt.md`: fetch main, compute next `TYPE-000N`, rename + stamp,
  regenerate index.
- Templates (`RFC_TEMPLATE.md`, spec/change/etc.): add `number` field; document
  slug-as-primary-key.
- `generate-docs-index.mjs`: resolve the display id from `number` when present,
  else show the slug; surface unnumbered drafts distinctly.
- CI / pre-commit: add the duplicate-number + no-DRAFT-at-merge guard.

### Operational impact

- Intake stays fully local and offline-capable; the only new online step is at
  merge, which is already online and operator-gated.
- A doc's *display* id is not final until merge. Anything referencing it in-branch
  must use the stable slug (this is the main behavioral change to internalize).

### Migration/compatibility notes

- Additive. Existing numbered docs keep their numbers (backfill `number:` from
  the filename, or leave legacy docs untouched and only apply the new flow to
  new intakes).
- If the allocator is absent (older AAI layer), intake falls back to the current
  scan-and-mint behavior and the CI duplicate-guard catches collisions — degrade
  and report, never hard-break.

## Risks

- **Two developers pick the identical kebab slug.** Mitigation: derive the slug
  with a short author/branch suffix, and the duplicate-slug case is visible and
  rare (unlike duplicate numbers, which are currently invisible until merge).
- **In-branch references to the not-yet-numbered doc.** Mitigation: slug is the
  canonical `id`; the number is a late-bound display alias, so references do not
  break on rename. Where a numbered filename must be referenced, the allocator
  rewrites references as part of the rename.
- **Operator forgets to run `/aai-pr` / merges by hand.** Mitigation: the CI
  duplicate-number guard is the backstop; a pre-merge hook can also run the
  allocator automatically.
- **Merges to `main` are NOT actually serialized** (e.g. direct pushes bypass the
  queue). Mitigation: the guard fails the second colliding merge; document that
  merge must go through the gated path for the guarantee to hold.

## Open Questions

- Which id is canonical after merge: keep the slug as `id` with `number` as an
  alias, or promote `RFC-000N` to `id` and demote the slug to `aka`? (Affects how
  much of the codebase's "basename == id" assumption must change.)
- Where does the allocator run: inside `/aai-pr` only, a git pre-merge hook, or a
  CI job on merge-to-`main` (or all three, defense in depth)?
- Should the append-only ledger (Option A idea, minus the pre-review write) be
  adopted for early cross-clone *visibility* while numbers stay non-canonical
  until merge, or is merge-time allocation alone sufficient?
- Backfill policy for existing docs: stamp `number:` retroactively, or apply the
  new flow to new intakes only?
- Should this generalize identically to all id-bearing types (PRD/CHANGE/ISSUE/
  SPEC/RELEASE/RFC), or start with RFC/SPEC and extend once proven?

## Approvals

- Required approvers (roles/names): Project owner (ales@holubec.net); AAI
  maintainer.

## Notes

- Decisions captured during intake (2026-07-15): topology = multiple clones /
  developers; constraint = agent never writes to `main` (operator-only merge),
  so reserve-on-main is rejected as the primary mechanism; chosen direction =
  slug-primary identity with the sequential number assigned at the merge
  serialization point (Option C), backed by a CI duplicate-number guard
  (Option D as safety net).
- This RFC realizes the cross-developer coordination that RFC-0004 explicitly
  deferred. It is complementary to `docs-lock.mjs` (which stays the
  within-machine, subagent-level primitive) — different scope, not a replacement.
- Follow-on: a SPEC must define the slug derivation rule, the `number`/`id`
  frontmatter contract, the allocator CLI + `/aai-pr` wiring, the index-generator
  changes, and the CI guard — including a test that two branches minted from the
  same `main` cannot both merge with the same number.

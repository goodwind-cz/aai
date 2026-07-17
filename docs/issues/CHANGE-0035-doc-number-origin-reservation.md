---
id: doc-number-origin-reservation
type: change
number: 35
status: draft
links:
  pr: []
  commits: []
---

# Change — Atomic Doc-Number Reservation in Origin (Collision Guard + Slug Discipline + Coupled Families)

## Summary
Make "the display number is confirmed at PR/merge time" mechanically true
across parallel clones and branches: `allocate-doc-number.mjs` (or a
dedicated reserve step it calls) reserves the candidate `TYPE-NNNN` by
atomically creating a ref in origin BEFORE the local rename, a merge-time
guard blocks any doc whose number was never confirmed reserved, a lint warns
when a session artifact filename embeds a number with no corresponding
merged doc, and an allocator config lets number-paired doc families (e.g.
change + spec-change) share one counter so the union of taken numbers, not
each family in isolation, is what "next free" is computed against.

## Motivation / Business Value
Two live incidents motivate this change:

- **Downstream project incident**: a provisional handle `CHANGE-036` was
  used in-flight (baked into test filenames, a review report, and prose)
  while, independently, another branch merged its own `CHANGE-036` to
  `develop` first. The collision was discovered late, after the number was
  already load-bearing across multiple files, forcing a manual renumber tax
  across every place the stale number had propagated. Compounding this, the
  project's allocator pairs `SPEC-CHANGE-NNN` by number (spec and change
  share a display number), and when it re-allocated it proposed an
  inconsistent pair (doc `037` / spec `036`) because it does not treat the
  two families as one counter.
- **This repo, 2026-07-17**: the allocator granted `SPEC-0042`, a number
  already taken on an unmerged origin branch (PR #94) that had not yet been
  fetched/merged locally. This required a manual renumber to `SPEC-0043` and
  was only caught because code review separately noticed a stale
  `SPEC-0042` body reference left over from the original allocation
  (`docs/ai/reviews/review-20260717T134629Z.md`, NON-BLOCKING finding, line
  126).

Both incidents share the same root causes: (1) allocation only scans the
local working tree (plus, at best, a base ref), never a shared reservation
medium that all clones observe; (2) nothing enforces slug-only handles
during the window between intake and merge, so numbers get baked into
artifacts before they are confirmed; (3) number-paired doc families (this
repo's spec+change pairing convention, and the downstream project's
SPEC-CHANGE pairing) couple two independently-scanned counters, so
allocating for one family without accounting for the other produces
inconsistent pairs. This change closes all three gaps with a reservation
protocol, a fallback for offline/no-permission allocation, a merge-time
guard plus a slug-discipline lint, and a coupled-family union counter.

## Scope
- In scope:
  - `.aai/scripts/allocate-doc-number.mjs` (**protected_paths_l3** — planning
    for this change must apply full L3 ceremony: mandatory worktree,
    Constitution walk, and the tightened L3 rule set per
    `docs/ai/docs-audit.yaml`).
  - New reserve/guard/lint code: an atomic ref-reservation step invoked by
    (or folded into) the allocator; a merge-time/CI collision guard; a
    slug-only-handle lint (new script or a stanza added to `spec-lint`).
  - CI wiring for the new guard and lint.
  - Tests: allocator suite additions plus new reservation-specific tests
    using a mocked remote (local bare-repo fixture).
  - `docs/TECHNOLOGY.md` and the project USER_GUIDE (or equivalent) doc rows
    documenting the reservation protocol, the `number_reserved` marker, the
    coupled-family config, and the new guard/lint.
- Out of scope:
  - Renumbering any historical/already-merged docs.
  - Changing the existing links-based pairing model (spec<->change linkage
    via frontmatter `links`, not by number) — the coupled-family union
    counter is additive to, not a replacement for, links-based pairing.

## Affected Area
- `.aai/scripts/allocate-doc-number.mjs` (L3-protected allocator).
- New reservation/guard/lint script(s) under `.aai/scripts/`.
- CI configuration wiring the new merge-time guard and lint.
- `docs/TECHNOLOGY.md`, project USER_GUIDE doc(s).

## Desired Behavior (To-Be)
- The allocator reserves a candidate number in a shared medium (origin)
  before renaming the local DRAFT file, so two clones racing to allocate the
  same number cannot both win.
- When reservation is impossible (offline, no push permission), allocation
  still proceeds but is visibly marked unconfirmed, and merge is blocked
  until the reservation is completed — never a silent collision.
- A deterministic pre-merge/CI check independently re-verifies no collision
  exists on the target branch, and a lint flags numbered handles appearing
  in artifacts (filenames, prose) with no corresponding merged doc,
  reinforcing slug-only handle discipline before confirmation.
- Doc families declared as coupled (e.g. change + spec-change) allocate
  against one shared counter and reserve atomically as a set, so a
  successful allocation can never leave one family's number taken and the
  paired family's number free (or vice versa).

## Acceptance Criteria
- AC-001 (reservation): `allocate-doc-number.mjs` (or a dedicated reserve
  step it calls) reserves the candidate number by atomically creating a ref
  in origin (e.g. `refs/aai/docnums/<TYPE>-<NNNN>`) BEFORE the local rename;
  on push rejection (ref already exists) it retries with the next free
  number. Candidate selection scans the local tree + fetched `origin/*` +
  existing reservation refs.
- AC-002 (offline/fork fallback): when push is impossible (offline, no
  permission), allocation proceeds provisionally with a machine-readable
  marker (e.g. frontmatter `number_reserved: false`); the merge-time guard
  blocks such docs until the reservation is completed. Fail-open with a
  visible tax, never a silent collision.
- AC-003 (merge guard + slug lint): a deterministic pre-merge/CI check fails
  when the target branch already contains a doc with the same `TYPE-NNNN`;
  spec-lint (or a sibling lint) warns when a session artifact filename
  embeds a `TYPE-NNN` number that has no corresponding merged doc
  (slug-only handles enforced).
- AC-004 (coupled families union): allocator config may declare coupled doc
  families sharing one counter (e.g. change + spec-change); next-free is
  computed over the UNION of taken numbers across the coupled families, and
  the reservation push covers all coupled refs in one `git push --atomic`
  (all-or-nothing). Historical mismatched pairs are left as-is
  (links-based pairing remains authoritative).

## Verification
- Allocator test suite plus new reservation tests, using a mocked remote
  (local bare-repo fixture) to exercise the atomic-ref race, offline
  fallback, and coupled-family union paths.
- New guard/lint test stanzas (collision-on-target-branch case; unconfirmed
  numbered-handle-in-artifact case).
- `node .aai/scripts/docs-audit.mjs --check --strict --no-event` -> CLEAN.

## Constraints / Risks
- The allocator is L3-protected (`protected_paths_l3` in
  `docs/ai/docs-audit.yaml`): planning must apply the full L3 ceremony
  (mandatory worktree, Constitution walk, tightened rule set) before
  implementation starts.
- Network dependency introduced at allocation time (mitigated by the AC-002
  offline/fork fallback + merge-time guard).
- Ref-namespace hygiene: one reservation ref per number; holes (abandoned
  reservations) are acceptable and require no cleanup.
- Assumes server-side support for `git push --atomic` (confirmed available
  on GitHub, this project's remote).
- No secret is referenced by this change's scope. SECRETS PREFLIGHT: skipped
  (no local secret reference).

## Notes
- Motivating incidents: downstream project `CHANGE-036` collision
  (provisional handle baked into test filenames/review report/prose before
  confirmation, plus an inconsistent SPEC-CHANGE re-allocation pair caused
  by uncoupled counters); this repo's 2026-07-17 `SPEC-0042` grant collision
  against unmerged PR #94, manually renumbered to `SPEC-0043`, with a stale
  `SPEC-0042` body reference caught in
  `docs/ai/reviews/review-20260717T134629Z.md`.
- Design captured here reflects an operator-approved design from the
  2026-07-17 discussion following both incidents.

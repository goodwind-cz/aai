---
id: docs-close-gate
type: product
capability: docs-close-gate
status: current
delivered_by:
  - issue-gate-via-spec
spec: docs/specs/SPEC-DRAFT-issue-gate-via-spec.md
updated: 2026-11-16
---

# Docs close gate

## What it does

Before a governed doc (an issue, change, debt, requirement, RFC, release or
spec) is flipped to `status: done`, the close gate checks that its
acceptance criteria are reconciled: every row terminal, every done row
evidenced, every Review-By valid. A spec is checked against its own
`## Acceptance Criteria Status` table. An intake doc (an issue, change or
other non-spec doc) that has no AC table of its own is checked through its
linked spec instead, because that is where its acceptance table lives: every
linked spec must pass, and the output names the spec that decided. An intake
doc with neither its own table nor a linked spec fails and says what is
missing.

## How to use it

- Check one doc: `node .aai/scripts/docs-audit.mjs --gate <DOC-ID>`, for
  example `--gate ISSUE-0118`. A pass through a linked spec prints
  `GATE PASS via linked spec(s) SPEC-0295 (docs/specs/...)`.
- Check a file by path (for example a staged copy):
  `node .aai/scripts/docs-audit.mjs --gate-file <path>`.
- The opt-in pre-commit hook (`.aai/scripts/install-pre-commit-hook.sh`)
  runs the same gate on every staged done-flip under `docs/issues/`,
  `docs/rfc/`, `docs/specs/` and `docs/requirements/`. It
  warns by default; set `close_gate: enforce` in `docs/ai/docs-audit.yaml` to
  block the commit instead.

## Data model

A spec is linked to an intake doc when the intake's `links.spec` names it
(by id or by its repository path), or when the spec's `links.requirement` (or `links.rfc`) names the intake by
its frontmatter id or its display id (for example `ISSUE-0118`). No new
fields; these are the links intake and planning already write.

## Interfaces and contracts

- `docs-audit.mjs --gate <DOC-ID>` and `--gate-file <path>`: exit 0 pass, 1
  fail, 2 unresolvable id or file (unchanged). New output lines:
  `GATE PASS via linked spec(s) <ID> (<path>)`, reasons prefixed with the
  deciding spec's id, `Decided by linked spec(s): <ID> pass|fail (<path>)`,
  and a `no linked spec: ...` reason.
- Pre-commit hook close-gate block: gates staged done-flips under
  `docs/issues/`, `docs/rfc/` and `docs/requirements/` as well as
  `docs/specs/`. Under `close_gate:
  enforce` an intake doc with no table and no linked spec now blocks its
  done-flip commit.

## Limits and non-goals

- A spec never gates through another spec; a doc that carries its own AC
  table is gated on that table only. A table counts as its own as soon as a
  `Spec-AC-NN` row sits under an `## Acceptance Criteria` or
  `## Acceptance Criteria Status` heading, even when that table is
  malformed.
- An umbrella RFC or PRD whose own `## Rollout Status` still lists an
  unfinished phase does not pass because the specs written so far pass.
- Release plans (`docs/releases/`) carry no acceptance table; the hook does
  not gate them.
- A gated file with no frontmatter `id` can only be linked through its own
  `links.spec`.
- The hook reads the linked spec from the working tree; the spec's own
  staged copy is gated separately in the same commit.
- `close-work-item.mjs` does not run the close gate itself.

## Links

- Request: docs/issues/ISSUE-DRAFT-issue-gate-via-spec.md
- Spec: docs/specs/SPEC-DRAFT-issue-gate-via-spec.md
- Validation evidence (local, gitignored): docs/ai/validation/VALIDATION-issue-gate-via-spec-r4.md (final round)

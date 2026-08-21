---
id: intake-numbers-some-doc-types-immediately
number: 32
type: issue
status: done
user_visible: false
ceremony_level: 1
capability: aai-intake
links:
  pr:
    - 269
  commits:
    - c5241d5
---

# Issue — intake numbers some document types immediately

## Summary
- Intake is supposed to produce an **unnumbered** `TYPE-DRAFT-<slug>.md`; the display
  number is assigned at merge by `allocate-doc-number.mjs`. That holds for `change`,
  `issue` and `spec`. It does **not** hold for `techdebt`, `research` or `release`,
  which have historically been created already numbered.
- Reported by the owner for `techdebt`, with a request to check the other types. The
  check found a second, related defect: `research` documents carry **two different
  prefixes** in the same repository.

## Steps to Reproduce
1. Run `/aai-intake` with a description that routes to `techdebt` (or `research`).
2. Observe the saved artifact's filename.

**Expected:** `docs/issues/DEBT-DRAFT-<slug>.md`, frontmatter `number: null`,
`status: draft`, number assigned later by the allocator at PR.
**Actual:** a numbered file, e.g. `DEBT-0002-<slug>.md`, created that way from the start.

## Evidence
Measured on `main` at `778b0a7`, 2026-08-21. Every one of these appeared in history
**already numbered** — `git log --diff-filter=A` shows no DRAFT predecessor for any:

- `docs/issues/DEBT-0001-index-deferred-gap-and-done-with-live-decisions.md`
- `docs/issues/DEBT-0002-prompt-diet-byte-budget-true-up.md`
- `docs/specs/RES-0001-aai-competitive-gap-and-model-efficiency.md`
- `docs/specs/RESEARCH-0001-spec-kit-comparative.md`

By contrast `CHANGE`, `ISSUE` and `SPEC` documents do go through a DRAFT stage — the
four rides completed on 2026-08-19/20 each produced `*-DRAFT-*` and were numbered by
the allocator at the PR step.

**Second defect, not reported but found by the same check:** `RES-0001` and
`RESEARCH-0001` are both research documents with different prefixes. Nothing states
the prefix per type, so whichever the router improvised became precedent.

## Suspected Cause
The DRAFT rule lives **only** in `.aai/INTAKE_COMMON.md` under
`DURABLE DOC IDENTITY (SPEC-0015 / RFC-0007)`, applied by `.aai/SKILL_INTAKE.prompt.md`
STEP 2.4. Measured: **none of the eight `.aai/INTAKE_*.prompt.md` files contains the
string `DRAFT` or `DURABLE DOC IDENTITY`** — zero hits in all eight. Each instead says
only "save it under `docs/<dir>/`" and "Output summary + completed markdown +
**suggested filename**".

So the naming outcome depends on the router applying a step the per-type prompt neither
states nor reinforces. For the frequently exercised types the step is applied; for the
rare ones the per-type prompt's own "suggested filename" wins, and nothing catches it —
the naming convention has no gate.

This is the same shape as several defects already in the registry: a rule that exists in
one document and is enforced nowhere.

## Impact
- A numbered-at-intake document claims a number before the work lands. If the intake is
  abandoned or the number is taken meanwhile, the sequence has a hole or a collision —
  which is exactly what `SPEC-0015` / `RFC-0007` introduced the DRAFT stage to prevent.
- Inconsistent prefixes for one type break any tooling that maps prefix to type, and
  make the corpus harder to read.
- Low frequency, so it stays invisible: it only bites on the rare intake types.

## Desired Behavior
- Every intake type produces an unnumbered `TYPE-DRAFT-<slug>.md` with `number: null`.
- One prefix per type, stated where the router will actually read it.
- Something **fails** when a numbered document appears at intake, rather than the rule
  living only in prose.

## Acceptance Criteria
- AC-001: an intake of each of the eight types produces `TYPE-DRAFT-<slug>.md` with
  `number: null` and `status: draft`, demonstrated by running each.
- AC-002: the prefix used for each type is stated in one place and matches what the
  index generator and the allocator expect, `research` included; the `RES` / `RESEARCH`
  split is resolved deliberately with the choice recorded.
- AC-003: a test fails when an intake artifact is created already numbered. Prove it
  bites by creating one.
- AC-004: existing numbered documents are not renamed. Their ids are durable primary
  keys and history references them; this scope fixes the intake path, not the past.

## Verification
- run each of the eight intake types and inspect the resulting filename and frontmatter
- run whatever `node .aai/scripts/select-suites.mjs --files-from <changed files>` returns
- prove each new assertion **bites** by mutation, with an unmutated green control

## Constraints / Risks
- `.aai/` prompt edits carry the prompt-diet ledger, the TEST-012 byte budget and the
  PROFILES classification obligations, and touching `.aai/` paths adds a line to the
  branch-diff allowlist in `test-aai-spec-lint.sh` — a tax already paid seven times.
- Do not renumber or rename anything that exists. AC-004 is a boundary, not a nicety.
- `.aai/scripts/allocate-doc-number.mjs` is `protected_paths_l3`. If the fix needs it,
  the scope becomes ceremony 3 and needs the operator's sign-off.

## Notes
- Reported by the owner 2026-08-21 during the `cli-output-survives-a-pipe` ride; the
  document was held until that ride's PR ceremony finished so it would not be swept
  into an unrelated PR.
- The second finding (prefix split) is in scope because it has the same cause. If it
  turns out to need `allocate-doc-number.mjs`, split it out rather than escalating the
  whole scope to L3.

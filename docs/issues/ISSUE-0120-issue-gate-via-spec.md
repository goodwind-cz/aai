---
id: issue-gate-via-spec
type: issue
number: 120
status: done
links:
  pr:
    - TBD
  commits: []
---

# The docs close gate fails every intake doc whose acceptance table lives in its spec

## Summary
`.aai/AGENTS.md` (Quality Gates, "Docs close gate") says: before flipping a
governed doc to `status: done`, run `node .aai/scripts/docs-audit.mjs --gate
<DOC-ID>`. The gate only knows one shape of evidence: an `## Acceptance
Criteria Status` table in the gated doc itself. Intake docs (ISSUE, CHANGE,
DEBT, PRD, RFC) carry no such table — the acceptance table lives in the spec
that names the intake in its `links.requirement` (or that the intake names in
its own `links.spec`). So the gate fails every closed intake doc, while the
spec that actually carries the evidence passes.

## Type
- bug

## Impact
- Every project that sets `close_gate: enforce` in `docs/ai/docs-audit.yaml`
  cannot close an issue through the documented gate: the predicate is red for
  a correctly delivered intake doc.
- In this repository the gate is report-only, so nothing enforced it, and the
  red verdict became noise: 344 of 349 `status: done` docs under
  `docs/issues/` report `GATE FAIL` today (measured on origin/main
  `c1034b24`).
- Raised as P1 by Codex on PR #563 (review thread `discussion_r4588285498`).
- Severity/priority: P1 (a documented gate that cannot pass for its main
  input class).

## Current Behavior
- `node .aai/scripts/docs-audit.mjs --gate ISSUE-0115` (and 0116, 0117, 0118)
  prints `GATE FAIL — the AC Status table is not reconciled:` /
  `- missing AC Status table` and exits 1.
- Their specs (for example `--gate SPEC-0295`) print `GATE PASS` and exit 0.
- The pre-commit close-gate block (`.aai/templates/git-hooks/pre-commit-index.sh`)
  gates only staged `docs/specs/*.md` done-flips; the intake doc that
  `close-work-item.mjs --ref` flips in the same close commit is never gated
  there, so the hook and the documented `--gate` disagree about which docs the
  gate covers.

## Expected Behavior
- An intake doc (any non-spec type) with no AC table of its own that is
  linked to one or more specs gates through those specs: every linked spec
  must pass, and the output names the spec(s) that decided the verdict.
- An intake doc with neither its own table nor a linked spec keeps failing,
  with a message naming both missing things.
- Specs, and any doc that carries its own table, gate exactly as before.
- The pre-commit close-gate block gates the intake doc's done-flip with the
  same predicate as `--gate`, so the hook and the documented gate cover the
  same docs.

## Steps to Reproduce (if applicable)
1) On origin/main `c1034b24`: `node .aai/scripts/docs-audit.mjs --gate ISSUE-0118`
2) Observe exit 1, `missing AC Status table`.
3) `node .aai/scripts/docs-audit.mjs --gate SPEC-0295` — exit 0, `GATE PASS`.

## Verification
- `node .aai/scripts/docs-audit.mjs --gate ISSUE-0115` .. `ISSUE-0118` exit 0
  and name their spec (SPEC-0292 .. SPEC-0295) in the PASS line.
- A fixture intake doc with no table and no linked spec exits 1 naming the
  missing table and the missing spec link.
- A fixture intake doc linked to a spec with a non-terminal row exits 1 and
  names that spec and the row.
- Spec gating and own-table gating are unchanged (existing docs-audit suite
  green).
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash
  tests/skills/test-aai-docs-audit.sh` passes.

## Constraints / Risks
- Known risks or constraints:
  - Do not weaken the gate for specs or for docs with their own table.
  - Reuse docs-audit's existing link resolution (forward `links.spec` plus
    reverse `links.requirement` / `links.rfc`, matched on slug or display id)
    and its two-pass id resolver; no second resolver.
  - Widening the pre-commit hook to intake docs adds enforcement in projects
    that set `close_gate: enforce`; that is the intended consistency, and the
    default stays report-only.
  - Do not edit the files of open PR #563 (`allocate-doc-number.mjs`,
    `tests/skills/test-aai-intake.sh`, the `test-aai-doctor.sh` TEST-439 area).
- Secrets preflight results (if any secret referenced): none referenced.

## Notes
- Implementation mode: not chosen at intake (autopilot); Planning decides.
- Assumption: "intake doc" means any doc whose frontmatter `type` is not
  `spec`; close-work-item.mjs flips any resolved doc type, so the gate keys on
  the absence of `type: spec`, not on a list of intake types.

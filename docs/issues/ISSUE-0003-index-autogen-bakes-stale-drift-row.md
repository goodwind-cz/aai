---
id: ISSUE-0003
type: issue
status: done
links:
  pr: []
  commits: []
---

# Issue: committed docs/INDEX.md is non-idempotent — the pre-commit hook bakes a stale probable-false-done drift row

## Summary
`generate-docs-index.mjs` embeds the git-history-dependent docs-audit **Drift
report** into `docs/INDEX.md` (line ~365, `section('Drift report', audit.drift, …)`).
The `AAI:INDEX-AUTOGEN` pre-commit hook regenerates and stages `docs/INDEX.md`
*before* the commit object exists. So when a doc is set `status: done` in the
same commit that first references its ID, the drift heuristic (which keys on
"is there a commit / ac_evidence event referencing this doc") sees none yet and
bakes a `probable-false-done` **Drift report (1)** row into the committed index.
The instant that commit exists, a fresh `generate-docs-index.mjs` clears the row
(`Drift report (0)`), so the committed artifact **does not match a fresh
regenerate** — it is non-idempotent and immediately stale.

## Type
- bug

## Impact
- Who/what is affected? Every close commit that transitions a doc to `done` and
  first mentions its ID in the same commit. Observed **4 times** in one session
  (PRs #20, #21, #22, #23) — each needed a manual follow-up "regenerate INDEX in
  committed state" commit to fix.
- Severity/priority: **Medium** — not data loss, but: (a) the committed
  `docs/INDEX.md` is wrong/stale on every close, (b) it fails an idempotence
  check (a fresh regen produces a diff), (c) it creates churn / a second commit
  per close, and (d) it undermines trust in the auto-generated index. Codex
  flagged the same artifact as a P1 on a PR.

## Current Behavior
Pre-commit hook runs `generate-docs-index.mjs` on staged docs BEFORE the commit
exists → the just-closed doc has no commit referencing it → drift = probable-
false-done → that row is committed into `docs/INDEX.md`. After the commit,
`git show HEAD:docs/INDEX.md` differs from a fresh regenerate (modulo the
`Generated:` line): the committed one still has the drift row, the fresh one
does not.

## Expected Behavior
The committed `docs/INDEX.md` is idempotent: `git show HEAD:docs/INDEX.md` equals
a fresh `generate-docs-index.mjs` run (modulo the `Generated:` timestamp) with no
manual follow-up commit. A doc closed in a commit is not reported as
probable-false-done *by that same commit's* index.

## Steps to Reproduce (if applicable)
1) On a branch, set some `docs/**/DOC-ID.md` to `status: done` and `git commit`
   it (with the AAI:INDEX-AUTOGEN hook installed) using a message that references
   DOC-ID for the first time.
2) `diff <(git show HEAD:docs/INDEX.md | grep -v '^Generated:') <(node .aai/scripts/generate-docs-index.mjs; grep -v '^Generated:' docs/INDEX.md)`
   → non-empty: the committed index has a `Drift report (1) … probable-false-done`
   row that the fresh regenerate has dropped.

## Verification
- After the fix, the repro's `diff` is empty (committed index == fresh regen,
  modulo `Generated:`) with no second "regenerate INDEX" commit.
- A regression test: a fixture repo that closes a doc in a commit, then asserts
  the committed index is byte-idempotent to a fresh regen.
- `docs-audit --check --strict` stays CLEAN; the standalone drift report (if kept
  elsewhere) is unaffected.

## Constraints / Risks
- The drift report is genuinely useful; the fix should not lose drift visibility
  — options: (a) stop embedding the git-history-dependent drift section in the
  committed `docs/INDEX.md` (keep drift in `docs-audit` output / a separate
  non-committed report), (b) make the drift heuristic treat the doc being closed
  in the staged/pending commit as evidenced (harder — the commit doesn't exist
  yet at hook time), or (c) have the hook amend/second-pass so the committed
  index reflects post-commit state. Option (a) is the cleanest: the committed
  index should be a pure function of the docs, not of volatile git history.
- Must preserve degrade-and-report and the existing index sections.

## Notes
Recurring workaround applied this session: a manual `node .aai/scripts/generate-docs-index.mjs`
+ commit "regenerate INDEX in committed state" after each close. That is a
band-aid; this issue tracks the real fix. Related: RFC-0002 (docs hygiene/drift),
SPEC-0006 (index sections), DEBT-0001. Component: `.aai/scripts/generate-docs-index.mjs`
(drift-section embedding) + `.aai/scripts/install-pre-commit-hook.sh` (pre-commit
regenerate timing).

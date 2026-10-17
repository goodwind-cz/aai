# Code Review r3 — release-changelog-eol (PR #475)

```yaml
review:
  scope: "git diff 5fcc9d6a..0323af4f (branch fix/release-changelog-eol, HEAD 0323af4f verified) — .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/specs/SPEC-0235-spec-release-changelog-eol.md docs/product/release-command-finish.md docs/ai/decisions.jsonl docs/ai/EVENTS.jsonl"
  spec: docs/specs/SPEC-0235-spec-release-changelog-eol.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "untouched in r3; TEST-067 (r2 + VALIDATION-20261017T203450Z)" }
      - { ac: Spec-AC-02, call: compliant, citation: "untouched in r3; TEST-068" }
      - { ac: Spec-AC-03, call: compliant, citation: "untouched in r3; TEST-069 (CRLF base without attributes still adopted: new check compares equal)" }
      - { ac: Spec-AC-04, call: compliant, citation: "untouched in r3 (release-finish.mjs:416); TEST-070" }
      - { ac: Spec-AC-05, call: compliant, citation: "untouched in r3 (release-finish.mjs:397); TEST-071" }
      - { ac: Spec-AC-06, call: compliant, citation: "untouched in r3; TEST-072" }
      - { ac: Spec-AC-07, call: compliant, citation: "release-finish.mjs:433-437 check after commit, before record.head/atomicSave, worktree removal, push and pr create; TEST-073 (tests/skills/test-aai-release.sh:1774-1780, selector test_717); mutation-TEST-073 RED; mutation-gate GATE PASS 7 rows" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/release-finish.mjs, line: 436,
          issue: "Refusal after the local commit leaves a journal (stage=payload, head=null, worktree set), a registered temp worktree and local branch chore/release-<v> at the normalized commit; the printed Resume command can never succeed and the re-run refuses with a DIFFERENT cause (identity — Unbound prepared release branch, via :416). No recovery is documented (SKILL_RELEASE, product doc, refusal text).",
          failure_scenario: "Reproduced in a scratch clone (TEST-073 fixture + second invoke): run 1 'REFUSED: changelog-normalized … Completed: stage=payload; release-head=pending'; run 2 rc=20 'REFUSED: identity — Unbound prepared release branch'. If the operator instead renormalizes CHANGELOG on main, the journal's baseHead no longer matches and the run refuses base-moved; the same version stays blocked until the journal under .git/aai/releases/, the worktree and the local branch are removed by hand." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-release.sh, line: 1777,
          issue: "TEST-073 does not assert the AC's 'before the head is journaled' clause (journal head null) nor the state left behind / re-run cause.",
          failure_scenario: "A refactor that moves record.head=made;atomicSave() above the check (journaling a head whose blob is wrong) keeps TEST-073 green: refusal count, cause, zero pr create and no remote branch all still hold." }
      - { rank: NON-BLOCKING, file: CHANGELOG.md, line: 25,
          issue: "The branch's [unreleased] entry does not mention the new user-visible refusal changelog-normalized.",
          failure_scenario: "A downstream operator hitting REFUSED: changelog-normalized after upgrading finds no release note describing it or the fix (renormalize CHANGELOG.md on the base)." }
  cannot_verify:
    - { claim: "Behavior with a clean filter (filter=…/LFS) or a pre-commit hook that rewrites CHANGELOG.md — the refusal text attributes any mismatch to git attributes", closes_with: "a fixture with a filter driver and one with a re-staging pre-commit hook; reasoned: the byte comparison catches both, only the wording is attribute-specific" }
    - { claim: "Windows/autocrlf runner behavior of the new check", closes_with: "finish fixture on a Windows runner; reasoned: autocrlf does not convert when the index blob already holds CRLF, and LF blobs stay LF, so only explicit attributes trip it (same reasoning as r1 cannot_verify)" }
  overall: pass
```

## Scope and preflight

- Worktree `/Users/ales/Projects/aai-fix-release-changelog-eol`, branch `fix/release-changelog-eol`, HEAD `0323af4f` verified; one commit in range (0323af4f). Review done read-only; all execution in a scratch clone at `.../scratchpad/cr3-eol/clone` (spec-amend, spec-lint, mutation-gate, docs-audit, one probe run of a modified TEST-073 there only). No suite was run in the worktree.
- No coaching detected in the dispatch: it lists questions to judge, not expected findings or severities.

## Placement and correctness of the check (release-finish.mjs:433-437)

- The comparison reads the committed blob of `made` and compares it with `record.content` — the same raw `cat-file blob` helper as the resume adoption check (:416), so the normal and recovery paths now apply one rule. A CRLF base without attributes still compares equal (TEST-069 path unchanged).
- It runs after `git commit` in the private worktree and before `record.head` is saved, before worktree removal, before `stage('prepared')`, the push (:455) and `pr create` (:457). Every irreversible/remote step comes after it. Correct and fail-closed.
- What it leaves behind (verified in the probe): journal at stage `payload` with `head=null` and `worktree=<tmp>`; the registered temp worktree; local branch `chore/release-v1` at the normalized commit; nothing on the remote. See NB-1.

## Rejection of exact-bytes staging — sound

Staging the intended bytes past the attributes (`hash-object --no-filters` + `update-index --cacheinfo`) would commit content that contradicts the repo's declared policy. For `text eol=lf` that preserves a phantom-dirty state the base already has. For `filter=` drivers (LFS, custom clean filters) it would commit raw content where the repo expects the filtered form, which is real corruption. A byte-exact guarantee that silently overrides the owner's attributes is a policy decision, not a mechanical fix. Refusing is the right default. The actual remedy belongs on the base: `git add --renormalize CHANGELOG.md` and commit. The refusal text and docs do not say so (part of NB-1).

## Operator message / resume story — NB-1 (P3)

The refusal prints the generic `Resume: … --confirm` line. Re-running it hits the crash-recovery branch (:410-417), sees a prepared commit whose blob differs from the journal, and refuses `identity — Unbound prepared release branch`. That is a different cause and reads like tampering. Fixing the base moves `baseHead` and gives `base-moved`. Either way the same version stays blocked until the journal (`.git/aai/releases/<sha256(version)>.json`), the worktree and the local branch are removed by hand, and nothing documents that. r1 noted the generic hint as INFO for the existing identity refusals. This case is worse in two ways: it fires deterministically on the first cut in an affected repo, and the second run names the wrong cause.
Recommended disposition: (b) follow-up, P3, e.g. `fu-release-normalized-refusal-recovery`. The follow-up should cover a preflight probe before the journal/branch/worktree exist (compare `git hash-object --path CHANGELOG.md` against `--no-filters` for the rollup, with attributes from baseHead where the git version allows; keep the post-commit check as the backstop) and should document the recovery: renormalize on the base, then discard journal + worktree + branch. A cheaper in-tree option is to compare the index blob (`:CHANGELOG.md`) after `git add` and before `git commit`. The branch then stays at baseHead, and re-runs repeat `changelog-normalized` instead of switching to `identity`.

## Refusal name vs SKILL_RELEASE exit-code docs — INFO

SKILL_RELEASE documents `exit 20 = finish refused; relay one named cause` and lists no individual causes anywhere. `identity`, `preparation-dirty`, `head-moved` and the others appear only in the engine. TEST-034 checks exit codes, not cause names. So leaving `changelog-normalized` out of SKILL_RELEASE matches the existing convention, and the product doc (release-command-finish.md:42) names it. No prompt-corpus change needed.

## Test quality

- TEST-073 builds the right shape: a CRLF base blob committed before `.gitattributes` `CHANGELOG.md text eol=lf`. It asserts exactly one refusal, the cause, the detail text, zero pr create calls and no remote branch. The mutation record (if(false)) is RED, and its first_fail shows that without the check the normalized commit gets as far as the merge step. So the test bites.
- Gap (NB-2, P3): it does not assert `journal.head === null` (the "before the head is journaled" clause of AC-07) or the re-run behavior. Recommended disposition: (a) remediate in tree. One line: `assert.equal(journalOf(f).data.head,null)`. A second-invoke assertion could follow once NB-1 settles the intended cause.
- test_717 is wired into `main()` and dispatches through RELEASE_FINISH_CASE like its neighbors.

## Amendment record vs diff

- The decisions.jsonl record at 2026-10-17T20:51:59Z (actor remediation, class contract, owner_signoff false, tracked_by fu-amend-spec-release-changelog-eol) matches the diff: the AC-07 status row, the mapping row, the TEST-073 Test Plan row, the engine check before head journaling/push, and one product-doc sentence. `frozen_sha256` was re-stamped 422c…→8d00…, which is consistent with `spec-amend add` re-stamping in the same call. `spec-amend list --strict` exits 0 and lists the record as unsigned-tracked.
- INFO: the reused tracker fu-amend-spec-release-changelog-eol still carries only the first (editorial) amendment's text. An owner reading `follow-ups list` does not see that a contract-class AC was added. The orchestrator may want to note it in the sign-off request.

## Closed-spec AC addition vs docs tooling

- spec-lint `--path SPEC-0235`: LINT PASS, 0 findings. Note that the lint reports `Mutation gate: exempt (terminal spec)`, so the lint does not enforce mutation evidence for a row added after close.
- An explicit `mutation-gate --spec` run with the gitignored evidence copied in: GATE PASS, 7 rows (TEST-073 record base_commit 5fcc9d6a).
- docs-audit `--strict`: CLEAN. SPEC-0235 is not among the 8 unreadable AC tables and is not false-open or false-done.
- AC-07's Evidence cell says `TEST-073 PASS (post-freeze amendment, see decisions.jsonl)` with no validation report path, while rows 01-06 cite VALIDATION-20261017T203450Z. NB-4 (P3): (a) update the cell to cite the r3 validation report once it exists.

## Non-blocking findings and recommended dispositions

| # | Sev | Where | Disposition |
|---|---|---|---|
| NB-1 | P3 | release-finish.mjs:436 (resume/recovery after changelog-normalized) | (b) follow-up `fu-release-normalized-refusal-recovery` |
| NB-2 | P3 | tests/skills/test-aai-release.sh:1777 (journal head not asserted) | (a) remediate in tree |
| NB-3 | P3 | CHANGELOG.md:25 entry omits the new refusal | (a) remediate in tree (one bullet) |
| NB-4 | P3 | SPEC-0235 AC-07 Evidence cell lacks a validation report | (a) after r3 validation |

INFO: the refusal detail attributes every mismatch to git attributes, but a pre-commit hook that rewrites and re-stages CHANGELOG.md is caught by the same check. Wording only.

## Verdict

spec_compliance PASS, code_quality PASS (0 BLOCKING, 4 NON-BLOCKING), overall PASS, conditional on recording the NB dispositions above.

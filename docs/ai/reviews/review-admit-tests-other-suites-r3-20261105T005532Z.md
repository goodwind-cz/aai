# Code review — admit-tests-other-suites (round 3, re-review after F2 remediation)

security_relevant: false

```yaml
review:
  scope: origin/main...HEAD (f8297dbc...ff4be16b) on fix/admit-tests-other-suites
  spec: docs/specs/SPEC-0272-spec-admit-tests-other-suites.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1059-1063 (verdict-line guard + not-admitted pass); TEST-3370 :1366-1373; test bytes identical to the r2-validated 32d39fc2 (blob 51bc105d)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1345-1350; TEST-3371 :1375-1382" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-3372 :1384-1424 (own ADMIT-FAIL, missing probe, no-verdict output fail; ADMIT-OFF and a good own admission beside another suite pass; corpus half without probe fails 3337); RED reproduced in validation r2" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-3341 :669-678 (real out-of-root file, ../x and tests/../../x, rc 1 + no-source-file, edit-applied guard)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1396,
          issue: "the TEST-3337 bad_noprobe reason needle is the bare 'poisoned=0'",
          failure_scenario: "a future 3337 failure path that echoes the admission lines would also contain poisoned=0 and keep the case green for a different reason; today only the poisoned log_fail prints it" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1329,
          issue: "TEST-3337's own-suite list is a literal, not a shared variable",
          failure_scenario: "a split-suite rename that misses this line reads as not admitted; TEST-3336 pins the manifest names, so it needs a coordinated half-rename" }
  cannot_verify:
    - { claim: "CI full-suite proof for the lightweight lane",
        closes_with: "the PR carries the ci-full label and the full run is green; one local full test-framework sweep before the close ceremony" }
    - { claim: "owner acceptance of the post-freeze mutation_uncomparable: 6 amendment",
        closes_with: "owner signs or reverses fu-amend-spec-admit-tests-other-suites (P2, open; does not gate close or push)" }
  overall: pass
```

## Preflight
- STATE: `worktree.user_decision: worktree`, base main.
- `git status --porcelain` at review time: `M docs/ai/EVENTS.jsonl` (append-only lines from the validation r3 STATE and dispatch commands) and this untracked review. Both are outside the code scope. The r3 validation report and STATE.yaml are gitignored.
- Scope is `git diff origin/main...HEAD` (merge-base f8297dbc = origin/main). It covers docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, the r1 and r2 reviews, the intake and spec drafts, and tests/skills/test-aai-suite-reuse.sh. No product or `.aai/` file is touched.

Dispatch note (anti-gaming): the brief named the delta's content and said up front that r2's two NBs are "accepted residuals (P3)". That pre-rates severity. I recorded it here and reviewed the full scope independently. The re-ranking below is my own, and it agrees with the brief.

## Delta since r2 (32d39fc2..ff4be16b)
- The spec frontmatter now carries `+mutation_uncomparable: 6`, and that is its only line change. The six Test Plan rows all declare Mutation `none`.
  - `mutation-gate --spec` gives rc 0.
  - On scratch copies, a baseline of 5 gives rc 5 and 6 gives rc 0.
  - r2's BLOCKING finding is therefore closed.
- decisions.jsonl gained 2 appended lines: a spec_amendment of class contract, unsigned and tracked, plus its fu-amend follow_up. The origin/main bytes are a byte-exact prefix of HEAD for both decisions.jsonl and EVENTS.jsonl.
- The r2 review is committed as tracked evidence, which is the repo convention.
- Amendment class: contract is the honest lane. The key raises the close gate's uncomparable tolerance, which waives enforcement rather than re-spelling how a claim is measured. SPEC-0269 used contract for the same key. The r2 suggestion of measurement would have discharged the change without a signature.
- `frozen_sha256` is unchanged, and correctly so. The contract projection (lib/spec-contract-hash.mjs) drops the frontmatter, and `spec-amend list --strict` gives rc 0.
- docs/INDEX.md: regenerating it gives bytes identical to the commit.

## Full-scope re-read (test file)
- TEST-3341: the escape loop applies both sed forms in sequence. The second iteration rewrites the list form the first one left. An edit-applied guard prevents a silent no-op, and the `.bak` is removed. Both seds are portable between BSD and GNU (`-i.bak`).
- TEST-3307 and TEST-3337: in the not-admitted branch, the verdict-line guard sits before the early `return 0`. Because a newline is prepended, the regex matches only at line start, and it requires a trailing space.
- `judge_admission` runs each test in a subshell, so `LIVE_ADMIT_OUT` does not leak. `log_fail` exits the subshell, and the probe matrix in validation r2 confirms that rc propagates.
- I found no new defect with a failure scenario.

## Findings and dispositions (H6)
1. NON-BLOCKING `tests/skills/test-aai-suite-reuse.sh:1396`: loose needle. Disposition (d), accepted residual: P3 assurance-strength. Only the poisoned log_fail prints the needle today, there is no observed bite, and it leaves no false record.
2. NON-BLOCKING `tests/skills/test-aai-suite-reuse.sh:1329`: literal own-suite list. Disposition (d), accepted residual: P3 maintenance. TEST-3336 fails on a manifest-side rename, so a silent miss needs a coordinated half-rename.

## Checks run (shared with validation r3)
- mutation-gate --spec: 0
- ratchet probe at 32d39fc2 / 5 / 6 / 7: 5 / 5 / 0 / 0
- mutation-run --replay: 0
- spec-amend list --strict: 0
- spec-lint --path: 0
- close-work-item --dry-run: 0 (mutationGate warn; no bytes written)
- docs-audit --gate: 1 (only the four non-terminal AC rows; AC-flip deferral)
- nothing-left-behind: 1 (only docs_open)
- git diff --quiet 32d39fc2 ff4be16b -- tests/ .aai/: 0
- git ls-files -ci: empty

## Next steps
Before the close ceremony, run one full `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` sweep with AAI_TEST_TIMEOUT=3600. The PR must carry the `ci-full` label, and the owner sign-off on `fu-amend-spec-admit-tests-other-suites` is owed.

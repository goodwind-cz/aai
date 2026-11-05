# Code review — admit-tests-other-suites (round 2, re-review after remediation)

security_relevant: false

```yaml
review:
  scope: origin/main...HEAD (f8297dbc...32d39fc2) on fix/admit-tests-other-suites
  spec: docs/specs/SPEC-DRAFT-admit-tests-other-suites.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1059-1063; TEST-3370; an other-suite-only admission passes with the not-admitted line (r2-probe-matrix.log)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-suite-reuse.sh:1346-1350; TEST-3371" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "verdict-line guard :1061 and :1348; TEST-3372 :1381-1421 covers ADMIT-FAIL, missing probe, poisoned=0, corpus half without probe, no-verdict output, ADMIT-OFF; RED reproduced against the dc1fab50 bodies (rc 1, each half separately)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-3341 unchanged by the delta, green in the suite run" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: docs/specs/SPEC-DRAFT-admit-tests-other-suites.md, line: 6,
          issue: "mutation_gate: v1 with six Mutation 'none' Test Plan rows and no mutation_uncomparable baseline; mutation-gate.mjs --spec exits 5 (ratchet exceeded, uncomparable=6, baseline 0)",
          failure_scenario: "close-work-item.mjs runs the real mutation-gate as a close gate and docs/ai/docs-audit.yaml:77 dials it enforce, so the close ceremony refuses this spec; present since planning (rc 5 at dc1fab50 too), not caught in r1" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1396,
          issue: "the TEST-3337 bad_noprobe reason needle is the bare 'poisoned=0'",
          failure_scenario: "a future 3337 failure path that echoes the admission lines would also contain poisoned=0 and keep the case green for a different reason; today only the poisoned log_fail prints it" }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-suite-reuse.sh, line: 1329,
          issue: "carried from r1: TEST-3337's own-suite list is a literal, not a shared variable",
          failure_scenario: "a split-suite rename that misses this line reads as not admitted; TEST-3336 pins the manifest names, so it needs a coordinated half-rename" }
  cannot_verify:
    - { claim: "CI full-suite proof for the lightweight lane",
        closes_with: "the PR carries the ci-full label and the full run is green" }
    - { claim: "the close ceremony passes once F2 is remediated",
        closes_with: "mutation-gate --spec rc 0 and spec-amend list --strict rc 0 after the frontmatter baseline and its disclosure land" }
  overall: fail
```

## Preflight
STATE: `worktree.user_decision: worktree`, base main. `git status --porcelain` shows only the untracked validation r2 report and this review, both outside the code scope. Scope is `git diff origin/main...HEAD`: docs/INDEX.md, docs/ai/EVENTS.jsonl, docs/ai/decisions.jsonl, the r1 review, the intake and spec drafts, and tests/skills/test-aai-suite-reuse.sh. No product file is touched.

Dispatch note: the brief summarized the remediation content but did not pre-rate severity or exclude any area. The full scope was reviewed.

## Delta since r1 (dc1fab50..32d39fc2)
- F1 is fixed as recommended: the verdict-line guard sits inside `n -eq 0`, before the not-admitted pass, in both tests.
  - The regex anchors on line start via the prepended newline and requires a trailing space.
  - Checked under /bin/bash 3.2: it rejects a mid-line verdict and `ADMIT-PASSX`.
  - Real crash and lint-refusal captures now fail both tests, while ADMIT-OFF, ADMIT-NONE and other-suite-only still pass.
- r1 NB-2 (reason not asserted) is remediated: both bad_noprobe cases now `expect` the reason.
- The NB-4 corpus case was added.
- Amendment record 2026-11-05T00:26:00Z is classed measurement. It is acceptable: the predicate text is unchanged, and the newly measured behaviour was already a frozen Scope line ("Standalone mode … is unchanged").
  - INFO: the claim now lives only in the Observable column, not the AC-03 predicate.
- The r1 review is committed as tracked evidence, which is the repo convention (435 tracked reviews). No ignored artifact was force-added (`git ls-files -ci` is empty).

## Findings and dispositions
1. **BLOCKING** `docs/specs/SPEC-DRAFT-admit-tests-other-suites.md:6`: the mutation baseline is missing.
   - Disposition: (a) remediate in this ride. Add `mutation_uncomparable: 6` to the frontmatter, disclose it with `spec-amend.mjs add --class measurement`, then re-run `mutation-gate --spec` and `spec-amend list --strict`.
   - Precedent: SPEC-0269 has the same shape and carries `mutation_uncomparable: 3`.
   - The hazard was introduced by this ride, so standing decision (a) applies: one more round, no question.
2. NON-BLOCKING `tests/skills/test-aai-suite-reuse.sh:1396`: loose needle.
   - Disposition: (a) fold into the same remediation if cheap (needle `want above zero`); otherwise (d).
   - accepted residual: P3 assurance-strength; only the poisoned log_fail prints the needle today, no observed bite, no false record.
3. NON-BLOCKING `tests/skills/test-aai-suite-reuse.sh:1329`: literal list.
   - Disposition: (d).
   - accepted residual: P3 maintenance; TEST-3336 fails on a manifest-side rename, so a silent miss needs a coordinated half-rename.

## Checks run (shared with validation r2)
bash -n 0; suite-reuse 0; hygiene-pack 0; hygiene-corpus 0; selected+CORE (spec-amend, follow-ups, doc-numbering, factory-report, overview, check-state, docs-content, spec-lint, prompt-diet) all 0; spec-lint --path 0; spec-amend list --strict 0; docs-audit --gate 1 (only the four non-terminal AC rows); mutation-gate --spec 5 (finding 1).

---
review_of: test-infra-reds-and-ci-gate
spec: docs/specs/SPEC-DRAFT-spec-test-infra-reds-and-ci-gate.md
reviewer_model: claude-opus-4-8[1m]
generated_utc: 2026-07-19T11:26:08Z
---

# Code Review — test-infra-reds-and-ci-gate (dual-verdict)

```yaml
review:
  scope: "git diff main...HEAD — .aai/system/PROFILES.yaml, tests/skills/test-aai-worktree.sh, .aai/scripts/aai-sync.sh (mode), .aai/scripts/validate-skills.sh (mode), .github/workflows/skill-suite.yml (new)"
  spec: docs/specs/SPEC-DRAFT-spec-test-infra-reds-and-ci-gate.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/system/PROFILES.yaml:80,82,94,118,119,122 (6 files added to core); disjoint check intersection=∅, both lists sorted; bash tests/skills/test-aai-layer-profiles.sh exit 0 (TEST-001+TEST-003)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "tests/skills/test-aai-worktree.sh:237-241 (present-in-feature) & 252-256 (absent-in-main) — captured-var + here-string, both senses preserved, no `|| true`; bash test-aai-worktree.sh exit 0 x3 (TEST-002/003)" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "git ls-files -s .aai/scripts/aai-sync.sh = 100755, diff = pure mode (0 content lines); smoke invokes it at test-self-hosting-smoke.sh:28 (TEST-004/005)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".github/workflows/skill-suite.yml — parses; on.push(branches:[main])+pull_request+workflow_dispatch; fetch-depth:0; node20; skills job runs `bash tests/skills/test-framework.sh` (never sh); separate self-hosting-smoke job timeout-minutes:10 (TEST-006)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/validate-skills.sh, line: 1,
          issue: "Mode change 100644->100755 is outside the frozen spec AC-003's named scope (spec lists only aai-sync.sh), but is REQUIRED for AC-003's own verification to pass.",
          failure_scenario: "test-self-hosting-smoke.sh executes validate-skills.sh directly at line 24 (BEFORE aai-sync.sh at line 28); without +x the smoke fails with Permission denied at line 24, so AC-003's `smoke → exit 0` verification could not have passed with aai-sync.sh alone. Necessary, correct, and documented in the Spec-AC-03 Notes column — record the scope expansion, do not remediate." }
  cannot_verify:
    - { claim: "The workflow actually goes green in GitHub Actions on push/PR and the job fails red on a failing suite.",
        closes_with: "An observed Actions run on this branch/PR (workflow parse + `exit 1` on failure in test-framework.sh:316 verified locally; the Actions execution itself is not observable from the diff)." }
    - { claim: "self-hosting-smoke completes within timeout-minutes:10 on ubuntu-latest.",
        closes_with: "A real CI run's job duration (locally the suite is cited ~2-3 min; runner speed not observable from the diff)." }
  overall: pass
```

## Scope & spec

Reviewed the branch diff of `feat/test-infra-reds-and-ci-gate` vs `main`
against the frozen spec `SPEC-DRAFT-spec-test-infra-reds-and-ci-gate.md`
(SPEC-FROZEN: true, ceremony_level 2). Five changed surfaces: PROFILES.yaml
(+6 core entries), the worktree test (SIGPIPE fix), two script mode bits
(aai-sync.sh, validate-skills.sh), and the new CI workflow. Docs (spec/issue)
are the intake/spec artifacts, not implementation.

No orchestrator coaching to record — the dispatch named focus areas
("does it actually fail on red", "both assertions meaningful", etc.) which are
legitimate review-scope pointers, not severity pre-rating or scope exclusions.

## AC table walk (evidence)

- **Spec-AC-01 — compliant.** The six unclassified files
  (`close-work-item.mjs`, `reconcile-telemetry.mjs`, `secrets-preflight.mjs`,
  `tdd-evidence-check.mjs`, `aai-reap-tests.ps1`, `aai-run-tests.ps1`) are each
  added to `core:` in sorted position with the exact two-space-dash indent.
  Independently verified: core=115 / extended=44, **intersection empty**
  (disjoint), both lists sorted. Classification is correct per the file's own
  CLASSIFICATION RULE — all six are workflow-engine scripts (close ceremony,
  events/flush reconciler, intake+TDD gates, and two `.ps1` mirrors whose `.sh`
  siblings are already core); none is consumed by an extended-only prompt.
  `bash tests/skills/test-aai-layer-profiles.sh` → **exit 0** (re-run by me).

- **Spec-AC-02 — compliant.** Both isolation assertions were rewritten to
  capture `git log --oneline` into a local (`feature_log`, `main_log`) and then
  `grep -q ... <<<"$var"`, so `grep`'s early exit can never SIGPIPE the
  producer under `set -o pipefail`. **Both senses preserved**: present-in-feature
  keeps `if ! grep -q` → `log_fail` (line 239), absent-in-main keeps
  `if grep -q` → `log_fail` (line 254). No `|| true`, no neutralised assertion.
  `<<<` here-string is bash-3.2 safe. `bash tests/skills/test-aai-worktree.sh`
  → **exit 0 on 3 consecutive runs** (reliability, TEST-002).

- **Spec-AC-03 — compliant.** `git ls-files -s .aai/scripts/aai-sync.sh` →
  `100755`; the diff is a pure `old mode 100644 / new mode 100755` with **zero
  content/line-ending churn**. The smoke test executes it directly
  (`test-self-hosting-smoke.sh:28`). See the NON-BLOCKING note on the companion
  validate-skills.sh mode fix (also required — invoked at smoke line 24).

- **Spec-AC-04 — compliant.** `.github/workflows/skill-suite.yml` parses as
  valid YAML; triggers `push:{branches:[main]}`, `pull_request:{}`,
  `workflow_dispatch:{}`; `permissions: contents: read`; `checkout@v4` with
  `fetch-depth: 0` (required by the layer-profiles history probe); `setup-node@v4`
  node 20. The `skills` job runs `bash tests/skills/test-framework.sh` — the
  repo's aggregate runner, which invokes each suite via `bash "$test_file"`
  (**never forced `sh`**), treats exit 42 as SKIP, and `exit 1` on any failure
  (test-framework.sh:195,316) — the gate has teeth. The slow
  `self-hosting-smoke` runs as a SEPARATE job with its own
  `timeout-minutes: 10`; `skills` has `timeout-minutes: 30`. The only `sh`
  tokens in the file are inside comments.

TEST-xxx evidence: TEST-001..007 all re-exercised or inspected — layer-profiles
exit 0, worktree exit 0 x3, aai-sync mode 100755, smoke script invokes both
scripts directly, workflow parses + no forced sh, and both named regression
suites (`test-aai-prompt-diet.sh`, `test-aai-verify-gate.sh`) → **exit 0**.

## Code-quality findings

1. **NON-BLOCKING — validate-skills.sh mode change is a spec-scope expansion,
   but a necessary and correct one.** The frozen spec AC-003 names only
   `aai-sync.sh`; the implementation also flipped `validate-skills.sh` to
   100755. This is not gold-plating: the smoke test invokes validate-skills.sh
   at line 24, *before* aai-sync.sh at line 28, so without its +x the smoke
   fails first with Permission denied and AC-003's `smoke → exit 0` verification
   cannot pass. Documented in the Spec-AC-03 Notes column. **Disposition:**
   record as a spec deviation / decision (the reviewer names it; orchestrator
   records) — no remediation.

## INFO (non-gating)

- The Spec-AC-03 Notes claim validate-skills.sh was "invoked … one line later"
  and "hidden behind the aai-sync.sh Permission denied". In the actual smoke
  script validate-skills.sh (line 24) runs *before* aai-sync.sh (line 28), so it
  would have failed *first*, not been hidden behind it. Doc-note inaccuracy only;
  the code fix (both scripts +x) is correct regardless.
- `push:` is filtered to `branches: [main]`, matching the spec plan and the
  house style of ps1-quality/docs-numbering. Consequence: a push to a feature
  branch with no open PR won't run the suite. This is the intended
  no-double-run pattern (PRs are covered by `pull_request`), not a defect.

## cannot_verify

- Actions execution: the workflow parses and the runner has correct exit
  semantics locally, but that it goes green on push/PR and fails red on a broken
  suite is only observable from a real Actions run.
- self-hosting-smoke fitting inside `timeout-minutes: 10` on the GitHub runner
  (locally cited ~2-3 min; runner speed unknown from the diff).

## Next steps

Overall verdict **PASS** (both verdicts pass). One NON-BLOCKING finding: the
orchestrator should record the validate-skills.sh mode change as a spec
deviation/decision (per WARNINGS policy H6) since it extends AC-003's literal
file scope — the fix itself is correct and required, so remediation is not
warranted. The two cannot_verify items close naturally on the first CI run of
this branch/PR.

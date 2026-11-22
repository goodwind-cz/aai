# Code review: installer-l3-protected (round 2, re-review)

```yaml
review:
  scope: "git diff 97b53e25..HEAD (0fd3e406, b3cf8b81) on branch chore/installer-l3-protected; AC walk over the whole ride 077ee649..HEAD"
  spec: docs/specs/SPEC-DRAFT-spec-installer-l3-protected.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "docs/ai/docs-audit.yaml and .aai/templates/docs-audit.template.yaml unchanged since r1 (97b53e25); TEST-4001 green r1; TEST-3511 (hook-gate) re-run green this round" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-4000 tests/skills/test-aai-suite-select.sh:1193-1196 unchanged since r1; the selector answers FULL_RUN protected-l3 for the seven, also asserted by TEST-3997/3443/3571 re-run this round" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "WORKFLOW.md unchanged since r1; TEST-4002 green r1; hitl-propagation TEST-014 re-run green (authorized by this frozen L3 spec)" }
      - { ac: Spec-AC-04, call: compliant,
          citation: "tests/skills/test-aai-hook-installer-node.sh:814-824, test-aai-git-hook-templates.sh:551-566, test-aai-install-parity.sh:431-442; all three suites rc=0 under aai-run-tests.sh this round; mutation-gate GATE PASS 6 rows" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hook-installer-node.sh, line: 904,
          issue: "log_pass text still says 'select-suites routes every installer file to the suite'; after D7 the three installer files are asserted FULL_RUN protected-l3, not routed to aai-hook-installer-node",
          failure_scenario: "a reader of a green sweep log (or a validator quoting it as evidence) records that the installer routes to the named suite, which the selector no longer does; the record is false although the assertion is right" }
  cannot_verify:
    - { claim: "No suite outside the ones re-run here asserts a non-FULL_RUN selection for one of the seven paths",
        closes_with: "CI full run on the PR (the PR is FULL_RUN); this reviewer did not run the full sweep, by instruction. Grep found no other selector call on the seven paths" }
    - { claim: "The owner accepts the unsigned D7 amendment (fu-amend-spec-installer-l3-protected, open, P2)",
        closes_with: "the owner's sign-off or merge direction recorded against the follow-up" }
    - { claim: "Downstream projects that hand-add the seven lines see the same selector/recheck behaviour (carried from r1)",
        closes_with: "a scratch aai-sync install with the lines added, running select-suites on one path" }
  overall: pass
```

security_relevant: false

## Scope and spec

Scope: `git diff 97b53e25..HEAD` in /Users/ales/Projects/aai-worktrees/installer-l3-protected:
0fd3e406 (three wiring tests, spec amendment, decisions/EVENTS), b3cf8b81 (r1
report, follow-up fu-guard-config-not-l3-protected). The AC table is walked over
the whole ride. Spec: the frozen docs/specs/SPEC-DRAFT-spec-installer-l3-protected.md,
amended additively (D7, Spec-AC-04, three Test Plan rows). Dispatch prompt: it
summarised the remediation and named the questions to judge. It did not rate
expected findings or exclude any area. I reviewed the full delta anyway.

## B1 (r1 BLOCKING): resolved

I re-ran the suites myself (`env -u AAI_ROLE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-<suite>.sh`):

- aai-hook-installer-node: rc=0. TEST-3997 PASS.
- aai-git-hook-templates: rc=0. TEST-3443 PASS.
- aai-install-parity: rc=0. TEST-3571 PASS.
- hook-gate test_3511_protected_lists: PASS. Its 3-line window after the retired
  pre-commit-checks entry still holds, because the seven entries are appended
  after hook-gate.mjs.
- hitl-propagation test_014_no_protected_path_touched: PASS. It is authorized by this spec.

## Are the edited assertions still as strong?

- TEST-3997: the reference twins, the test helpers, the Pester file and
  vendor-hook-installer.sh still assert `^SELECTED aai-hook-installer-node`. The
  three installer files moved to `^FULL_RUN reason=protected-l3 path=<f>`. The
  guard-config shared-lib check and the suite-map/weights/PROFILES checks are
  untouched.
- TEST-3443: the vendoring helper and the Pester file still assert SELECTED
  aai-git-hook-templates. The helper still reaches all five helper suites. The
  four templates and both launchers moved to FULL_RUN protected-l3. pre-push.sh
  left the helper-suites loop. That loses nothing, because FULL_RUN runs every
  suite, which includes the five.
- TEST-3571: the sync, update and parity files still assert SELECTED
  aai-install-parity. The two installer launchers moved to FULL_RUN.
- The routing check is not weakened for any path that is not protected. Each
  moved path is now pinned more strictly: if its list entry is dropped, the
  test goes red (the mutation rows prove it, and the gate shows 6 rows satisfied).
- This is the same pattern TEST-3458 uses for pre-commit-checks
  (tests/skills/test-aai-pre-commit-checks.sh:425-428), as D7 says.

## Other pins of selector routing (grep over tests/, .github/, suite-map.yaml)

- I listed the files that name the installer or the templates and also call the
  selector. They are: suite-select (TEST-4000), pre-commit-checks (TEST-3458,
  its own scripts), hygiene-pack (TEST-487 mutation-gate and TEST-815, a
  suite-map glob check, not the selector), docs-audit (copies select-suites.mjs
  into fixtures only), git-ref-guard and release (fixture or content use only),
  and the three amended suites. None of them pins a non-FULL_RUN answer for the
  seven paths.
- .github/workflows/ps1-quality.yml path filters name the installer and the
  templates. These are trigger lists, not selector routing, and nothing here
  changes them.
- tests/skills/suite-map.yaml still globs the seven paths into their suites. In
  this repository those rows are dead, because the protected list wins. They
  stay harmless and keep routing correct for a reader without the list entries.
  INFO only.

## Amendment disclosure

- The decisions.jsonl spec_amendment record (ts 2026-11-22T11:20:28Z) has
  owner_signoff false and class contract. It is tracked_by
  fu-amend-spec-installer-l3-protected (open, P2).
- `spec-amend list --strict` lists it as unsigned-tracked, with 0 untracked.
- The spec carries D7, a D5 amendment note, Spec-AC-04 and three Test Plan rows.
  It also adds the three test files to the review scope, marked "added by the D7
  amendment".
- frozen_sha256 was re-anchored b2f5e086... -> f33dc488..., and
  mutation-gate shows GATE PASS 6 rows.
- The disclosure is honest. The spec's phrase "the owner's merge direction signs
  it" describes the expected closure, not something already done. The record
  and the follow-up state correctly that it is unsigned.
- Cosmetic issues, which the validator also noted:
  - The three D7 Test Plan rows sit after a blank line.
  - Spec-AC-04 is listed before Spec-AC-03.
  - The "RED observations: all three tests" sentence now sits beside six rows.
  - spec-lint passes and the mutation gate reads all six rows, so no parser is
    misled. accepted residual: cosmetic spec layout, no reader misparses it
    (P3, no false record).

## Findings

- NON-BLOCKING NB1 (P3): tests/skills/test-aai-hook-installer-node.sh:904. The
  TEST-3997 pass message still says the installer files "route to the suite".
  Recommended disposition: (a) remediate in tree. This is a one-line text edit:
  for example, "routes the twins and helpers to the suite, escalates the three
  installer files to FULL_RUN protected-l3". Do it before the PR, or (b) as a
  typed follow-up if the ride is not reopened.
- r1 NB1 (guard-config.mjs not L3-protected) is recorded as follow-up
  fu-guard-config-not-l3-protected (P3). That disposition is valid.

## cannot_verify

See the YAML block: the full sweep or CI, the owner's sign-off of D7, and
downstream behaviour.

## Warning dispositions

- NB1: remediate-in-tree (recommended) or follow-up. The orchestrator records the choice.
- Spec layout: accepted residual (quoted above).

## Next steps

The orchestrator records the NB1 disposition and updates STATE. Then it runs
PR or close per the L3 ceremony, and CI runs the full run.

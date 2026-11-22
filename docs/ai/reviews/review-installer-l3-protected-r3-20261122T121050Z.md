# Code review: installer-l3-protected (round 3, delta re-review)

```yaml
review:
  scope: "git diff 4c00c39b..f988ac95 (branch chore/installer-l3-protected); AC walk over the whole spec"
  spec: docs/specs/SPEC-0309-spec-installer-l3-protected.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "lists unchanged in the delta; TEST-4001 evidence rows as in r2; mutation-gate row satisfied" }
      - { ac: Spec-AC-02, call: compliant, citation: "selector and lists unchanged in the delta; TEST-4000; mutation-gate row satisfied" }
      - { ac: Spec-AC-03, call: compliant, citation: "WORKFLOW.md unchanged in the delta; TEST-4002; mutation-gate row satisfied" }
      - { ac: Spec-AC-04, call: compliant, citation: "wiring tests unchanged in the delta (rc=0 in r2); r2 NB1 fixed in 4c00c39b at tests/skills/test-aai-hook-installer-node.sh:904" }
      - { ac: Spec-AC-05, call: compliant, citation: "tests/skills/test-aai-hook-installer-docs.sh:233; TEST-3999 PASS and the full aai-hook-installer-docs suite rc=0 this round; mutation-TEST-3999.txt verdict RED (self-close by pre-commit-installer-on-node fails); CI red docs/ai/tdd/installer-l3-protected/red-test_3999_follow_ups.log" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hook-installer-docs.sh, line: 233,
          issue: "the relaxation accepts any non-empty resolved_by other than the literal ride slug, so a later ride is not checked to exist, and the port's own other names (SPEC-0308, spec-pre-commit-installer-on-node) are not treated as self-close",
          failure_scenario: "someone appends a follow_up_status done for fu-guard-dials-ignore-bom with resolved_by SPEC-0308 or a typo ref. The item is attributed to the installer port, or to no real ride, and TEST-3999 still passes. No such record exists today; the port's own closes are fixed history" }
  cannot_verify:
    - { claim: "No suite other than hook-installer-docs pins the open status of the four filed follow-ups in the real ledger",
        closes_with: "CI full run on PR #580. Grep over tests/ finds the id only in test-aai-hook-installer-docs.sh:188,232. 'is not open'-style checks appear only there and in a fixture-only spec-amend TEST-004" }
    - { claim: "The owner accepts the three unsigned contract amendments (D7, D8, and the unverified-cause restamp), all tracked by fu-amend-spec-installer-l3-protected (open, P2)",
        closes_with: "the owner's sign-off or merge direction recorded against the follow-up" }
    - { claim: "Downstream installs that add the seven lines by hand behave the same (carried from r1/r2)",
        closes_with: "a scratch aai-sync install running select-suites on one path" }
  overall: pass
```

security_relevant: false

## Scope and spec

Scope: `git diff 4c00c39b..f988ac95` in the worktree
/Users/ales/Projects/aai-worktrees/installer-l3-protected. That is one commit,
f988ac95:

- the allocator renames CHANGE-0264 and SPEC-0309 and restamps
- TEST-3999 is relaxed
- the D8 amendment and two decisions.jsonl records
- INDEX, overview and links in the review reports

4c00c39b, the close commit, carries the r2 NB1 fix. Its pass text at :904 now
says the installer module and both launchers escalate to FULL_RUN protected-l3.
I verified that line.

Dispatch prompt: it named the questions to judge. It did not pre-rate findings
or exclude any area.

## Checks run this round

- `aai-run-tests.sh bash tests/skills/test-aai-hook-installer-docs.sh test_3999_follow_ups`: PASS.
- The full aai-hook-installer-docs suite: rc=0. This also covers TEST-3998.
- `mutation-gate.mjs --spec SPEC-0309`: GATE PASS, 7 rows.
- `spec-lint --path SPEC-0309`: LINT PASS.
- `spec-amend list --strict`: rc=0. Three unsigned-tracked records, 0 untracked.
- Grep for leftover DRAFT paths of this ride in tests/, .aai/, docs/specs,
  docs/issues, INDEX and docs-audit.yaml: none.

## Does the TEST-3999 relaxation keep the original claim?

The original claim (SPEC-0308 Spec-AC-20) was that the port filed four
follow-ups under its ref and did not close them itself.

The new condition at :233 fails when a filed item is closed and either:
- resolved_by is `pre-commit-installer-on-node`, or
- resolved_by is empty.

The `ref_id` check is unchanged.

- **The self-close case still fails.** The mutation record rewrites this ride's
  resolver to the port's slug, and TEST-3999 goes RED.
- **A close with no resolver still fails.** Reopen records carry a reason and
  no resolver, but the item is then open, so they are unaffected
  (follow-ups.mjs:290-297).
- **The "is not filed" and ref checks are unchanged.**
- **The gap (NON-BLOCKING, P3).** "Later ride" is not verified. Any non-empty
  resolver other than the port's slug passes, including the port's doc ids or
  a ref that does not exist.
  - The tighter fix would be an explicit id-to-resolver allowlist. It would
    trip again on every legitimate future close, which is the same class as
    this CI red.
  - The generic rule is the better trade-off. Rejecting the port's alternate
    names (`SPEC-0308`, `spec-pre-commit-installer-on-node`) would close most
    of the gap cheaply.
  - Recommended disposition: (d) accepted residual. Quoted line:
    "accepted residual: TEST-3999 trusts any non-port resolver; P3
    assurance-strength, no record bites today, the port's closes are fixed
    history". The alternative is (a), adding the two alternate names to the
    self-close test.

## Other pins of this follow-up's status

- `fu-installer-not-in-l3-protected-paths` appears in tests/ only at
  test-aai-hook-installer-docs.sh:188 and :232.
- The other three filed ids appear only in that file.
- "is not open", "must stay open" and "stays open" checks appear only in that
  file and in test-aai-spec-amend.sh:561. The spec-amend one is TEST-004 on a
  fixture ledger, not the real one.
- None of the suites that read the real decisions.jsonl names these ids.

## Amendment and restamp disclosure

- **D8.** It is in the spec with Spec-AC-05 and a Test Plan row whose mutation
  is recorded. Scope gains test-aai-hook-installer-docs.sh. The decisions
  record (12:07:00Z, contract, signoff false) is tracked by
  fu-amend-spec-installer-l3-protected.
- **Restamp (12:07:48Z).** It is disclosed as an UNVERIFIED cause in the
  contract lane, not as a mechanical rename, and is tracked. This is honest:
  the D8 content edit and the allocator rename landed in one anchor move, so
  the tool cannot prove a mechanical cause. From fb116f19... to 9c7c91e3...;
  the mutation gate is green on the new anchor.
- The D8 record names the pre-rename SPEC-DRAFT path. That is correct as
  history. INFO.

## Warning dispositions

- NB1 (TEST-3999 accepts any non-port resolver): recommended (d) accepted
  residual, line quoted above. The orchestrator may choose (a) instead.
- r2 NB1: remediated in 4c00c39b.

## Next steps

The orchestrator records the NB1 disposition and updates STATE. Then CI on
PR #580 re-runs the full run.

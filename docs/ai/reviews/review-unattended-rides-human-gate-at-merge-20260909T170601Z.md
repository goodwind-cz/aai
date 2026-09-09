```yaml
review:
  scope: origin/main...HEAD (feat/unattended-rides-human-gate-at-merge)
  spec: docs/specs/SPEC-0174-spec-unattended-rides-human-gate-at-merge.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "unattended-gate.mjs:43-56 D1_TABLE + TEST-001/002; aai-unattended PASS 2026-09-09T17:02:36Z" }
      - { ac: Spec-AC-02, call: compliant, citation: "classifyTrigger HITL-9 answer=fail (unattended-gate.mjs:190-193); waived unreachable; TEST-003/004" }
      - { ac: Spec-AC-03, call: compliant, citation: "runClassify append-before-verdict unattended-gate.mjs:246-249; TEST-005/006/007" }
      - { ac: Spec-AC-04, call: compliant, citation: "runPreflight refusals unattended-gate.mjs:264-283; TEST-008/009" }
      - { ac: Spec-AC-05, call: compliant, citation: "preflight --intake required; SKILL_SHIP unattended branch; TEST-010/011" }
      - { ac: Spec-AC-06, call: compliant, citation: "SKILL_SHIP.prompt.md:80-93 merge checkpoint; SKILL_PR.prompt.md:30-35; AGENTS.md:350-355; CONSTITUTION.md:26 Article 7 unchanged; TEST-012; aai-golden-flow suite exit 0 (TEST-017)" }
      - { ac: Spec-AC-07, call: compliant, citation: "SKILL_LOOP.prompt.md unattended branch + max_prs; TEST-013/014" }
      - { ac: Spec-AC-08, call: compliant, citation: "runSummary unattended-gate.mjs:305+; TEST-015" }
      - { ac: Spec-AC-09, call: compliant, citation: "PROFILES.yaml unattended-gate.mjs; suite-map aai-unattended; prompt-diet JUSTIFIED_ADDITIONS 5618; harness SKILL.md copies; USER_GUIDE.md:681; sync-harness-skills --check 0; aai-prompt-diet suite exit 0 (TEST-016)" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/unattended-gate.mjs, line: 197, issue: "HITL-8 interpolates --answer into a shell command string", failure_scenario: "if the loop passes an --answer containing quotes or shell metacharacters, target_command becomes a broken or injectable argv when executed as a shell line", disposition: promote-to-follow-up-ref }
  cannot_verify:
    - { claim: "overnight ride chaining against a live roadmap and GitHub", closes_with: "an opted-in unattended /aai-ship run with a declared budget and two on-disk intakes" }
    - { claim: "PowerShell parity of unattended-gate.mjs", closes_with: "out of scope (named residual; no ps1 mirror for ride-select.mjs either)" }
  overall: pass
```

# Code review — unattended-rides-human-gate-at-merge

Scope: `git diff origin/main...HEAD` on `feat/unattended-rides-human-gate-at-merge`.
Spec: `docs/specs/SPEC-0174-spec-unattended-rides-human-gate-at-merge.md` (SPEC-FROZEN).

## spec_compliance: pass

Every Spec-AC row is implemented and gated by the named TEST. Fresh 2026-09-09 runs: `aai-unattended` PASS (3s, attested clean), `aai-prompt-diet` suite exit 0, `aai-golden-flow` suite exit 0, `aai-layer-profiles` PASS, `aai-hygiene-pack` PASS, `sync-harness-skills.mjs --check` exit 0. CONSTITUTION Article 7 is unchanged (`the agent never merges`).

## code_quality: pass

No BLOCKING findings. One NON-BLOCKING: HITL-8 `target_command` interpolates free-text `--answer` into a double-quoted shell string. Disposition: follow-up, not in-tree for this ride — the default answer has no metacharacters and HITL-7/9 use closed literals.

## cannot_verify

Live overnight chaining and a PowerShell mirror are named residuals in the spec, not claimed by this diff.

## Next steps

PR ceremony. Merging stays operator-only.

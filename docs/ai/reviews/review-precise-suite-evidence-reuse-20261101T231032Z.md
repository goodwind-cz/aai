# Code Review r8: precise-suite-evidence-reuse (delta re-check, PR #523)

- Scope: `git diff 5e21ea71..14c6e893` (commits 16df0946, 14c6e893), worktree branch feat/precise-suite-evidence-reuse, head 14c6e893 (pushed; PR head confirmed 14c6e89345645ab0afe62c43af33b783dac583c6).
- Spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md (D5 and Test Plan rows amended in this delta); also the SPEC-0249 Spec-AC-13 and SPEC-0250 Spec-AC-09 amendments.
- Prior: r7 PASS at 891af2ee (docs/ai/reviews/review-precise-suite-evidence-reuse-20261101T214817Z.md). Validation r13 FAIL (B1 closed by 14c6e893) and r14 PASS in docs/ai/reports/.
- Final-round rule (owner, 2026-11-01): new latent shapes outside this delta are NON-BLOCKING follow-ups.
- Dispatch prompt: it named the two bot threads to re-check. I took that as a scope pointer, not as coaching. I reviewed the whole delta anyway.

security_relevant: false

```yaml
review:
  scope: git diff 5e21ea71..14c6e893
  spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: SPEC-0266 Spec-AC-03 (D5 check decision), call: compliant,
          citation: ".aai/scripts/suite-reuse.mjs:44-51 shellStartupHazard, :361 decide first condition; TEST-3195 green" }
      - { ac: SPEC-0266 Spec-AC-05 (record contract), call: compliant,
          citation: ".aai/scripts/suite-reuse.mjs:391 hazard refuse+forget, :400-403 no-identity before loadContext; TEST-3195, TEST-3196 green" }
      - { ac: SPEC-0266 other ACs, call: compliant,
          citation: "untouched by delta; r7 walk stands; r14 INTERMEDIATE scope green" }
      - { ac: SPEC-0249 Spec-AC-13, call: compliant,
          citation: "tests/skills/test-aai-expert-fetch.sh:590 row 5 'in progress'; RFC-0017:308 row 5 'in progress'; test_2623 PASS" }
      - { ac: SPEC-0250 Spec-AC-09, call: compliant,
          citation: "tests/skills/lib/recheck.test.mjs:919,2746; TEST-2716 and TEST-2825 green" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 49,
          issue: "Any non-empty BASH_FUNC_* turns reuse off. Some distros export a function in every login shell by default.",
          failure_scenario: "On RHEL/Fedora, /etc/profile.d/which2.sh exports BASH_FUNC_which%%. Every check prints RUN reason=bash-startup-hook, so the feature is silently off for that user. It fails closed, so no false reuse. The product doc says reuse works in a normal Linux run, which is not true there." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 346,
          issue: "checkSuites still computes and writes <suite>.reuse-identity.json when the hazard is present. Only decide() fails closed.",
          failure_scenario: "Nothing exploits it today. The framework calls check and record from one process with the same env, and record refuses under the hook. A future caller that changes env between check and record (hook at check, clean at record) would record a pass produced under the hook. That is a latent shape, not reachable now." }
  cannot_verify:
    - { claim: "In Windows Git Bash degraded mode reuse is off because the framework inherits BASH_ENV from aai-run-tests.sh:807",
        closes_with: "a Windows degraded-mode run of test-framework.sh under aai-run-tests.sh showing RUN reason=bash-startup-hook" }
    - { claim: "The RFC-0017 row 5 'in progress' pins pass in the full CI sweep",
        closes_with: "green CI on 14c6e893 (local targeted runs are green)" }
  overall: pass
```

## Delta reviewed

1. `.aai/scripts/suite-reuse.mjs`
   - New `shellStartupHazard(env)`. It covers BASH_ENV, ENV, SHELLOPTS, BASHOPTS and non-empty BASH_FUNC_*. An empty value is not a hazard.
   - `decide()` checks it first: RUN reason=bash-startup-hook.
   - `recordSuite` checks it after the ci/opt-out exits: it forgets the stored record and returns bash-startup-hook.
   - `recordSuite` now rejects a missing, unparseable, null or args-less identity file with no-identity, before `loadContext`. The old path did `JSON.parse(null)`, got `before === null`, and threw a TypeError in `computeIdentity`.
2. TEST-3195 and TEST-3196 are new (suite-reuse.test.mjs:753-799) and wired into test-aai-suite-reuse.sh (both the function definitions and `main`).
3. SPEC-0266 D5 and the Test Plan rows match the code. The product doc Limits bullet matches the code. On the Windows degraded path, aai-run-tests.sh:807 exports BASH_ENV in the wrapper process, and the framework runs as its child, so the helper sees it.
4. The RFC-0017 row-5 pins moved from 'not started' to 'in progress' in test-aai-expert-fetch.sh and recheck.test.mjs (TEST-2716/2825). The SPEC-0249 and SPEC-0250 ACs were amended to accept 'not started or in progress'. The RFC file already reads 'in progress' at line 308.
5. Amendments: five contract records with `owner_signoff: false`. They are tracked by fu-amend-node-first-third-slice-2-3c0cc6, fu-amend-cheap-transitions-slice-83e968 and the existing fu-amend for this ref. `spec-amend list --strict` gives rc 0. The owner still owes sign-off; that is HITL and not a review defect.

## Evidence (fresh, this round)

- `node --test --test-name-pattern='TEST-3195|TEST-3196|TEST-3176|TEST-3174' tests/skills/lib/suite-reuse.test.mjs`: 6/6 pass.
- `node --test --test-name-pattern='TEST-2716|TEST-2825' tests/skills/lib/recheck.test.mjs`: 2/2 pass.
- `bash tests/skills/test-aai-expert-fetch.sh test_2623_rfc_phase3_done`: PASS.
- Mutation replay in a scratch `git archive` copy, so the worktree was not touched:
  - the TEST-3195 cell (`return hit ? 'bash-startup-hook' : null` changed to `return null`) turns TEST-3195 red;
  - the TEST-3196 cell (`!Array.isArray(before.args)` changed to `false`) turns TEST-3196 red.
- No startup-hook variables are exported by this harness, `test-framework.sh` or `.aai/scripts/*.sh` (`export -f` and `export SHELLOPTS` are absent), so reuse stays on in the normal macOS/Linux path.
- The worktree is clean after the runs. `docs/ai/tests/test-runs.jsonl` was not modified.

## Bot threads: substance

- Codex P2 (suite-reuse.mjs:43, "Include Bash startup hooks in the reuse identity"): genuinely closed.
  - The fix fails closed instead of hashing the hook. That is a valid answer to the finding, because the hook can no longer feed a reuse.
  - 16df0946 covered only the check half. r13 found that a pass recorded under BASH_ENV was reused after BASH_ENV was unset (r13 B1).
  - 14c6e893 closes the record half: refuse plus forget. It also widens coverage to SHELLOPTS, BASHOPTS and BASH_FUNC_*.
  - TEST-3195 covers both halves for all five variables, plus the hook-record-then-clean-check sequence.
  - The thread is resolved and not outdated. The reply cites only 16df0946 and BASH_ENV/ENV. It is stale against 14c6e893 but not wrong; optionally add a one-line reply naming 14c6e893.
- Copilot (recordSuite null identity): genuinely closed.
  - `pre === null`, an unparseable file, JSON `null`, a non-object, and a non-array `args` all return no-identity before `loadContext`/`computeIdentity`, so no TypeError path is left.
  - TEST-3196 covers all five bodies, and its mutation kills.
  - The thread is resolved (outdated).

## Findings and dispositions (H6)

- BLOCKING: none.
- NB-1 (P3), BASH_FUNC_which%% on RHEL/Fedora silently disables reuse. Recommended disposition: promote to a follow-up ref (product-doc wording plus an optional allowlist decision), e.g. `fu-reuse-distro-exported-functions`. It is outside the final-round blocking scope.
- NB-2 (P3), the identity file is written under the hazard at check. Recommended disposition: `accepted residual: not reachable. check and record share one process env in test-framework.sh:1031/1079, and record refuses under the hook; no false record is left.`
- INFO: the Codex thread reply predates 14c6e893. Optional follow-up comment.

## Next steps

Overall pass. Merge readiness depends on green CI on 14c6e893 and the owner's sign-off on the unsigned contract amendments, which are tracked in fu-amend-*.

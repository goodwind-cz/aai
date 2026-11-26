# Code review: test-infra-p2-fixes (round 3, re-review after remediation round 4)

- ref: test-infra-p2-fixes
- reviewer: dispatched Code Review role (claude-opus-5-5), SKILL_CODE_REVIEW prompt hash 8e6aae0d5197, fresh context
- worktree: /Users/ales/Projects/aai-worktrees/p2-test-infra, branch chore/p2-test-infra, HEAD 22d27a30
- scope: `git diff d80b73a8..HEAD` (commits 4e22f20d review report and repro, 04a6db2a remediation, 22d27a30 telemetry). The code and spec delta is in 04a6db2a: tests/skills/test-aai-run-tests.sh (2 lines), docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md (frozen_sha256 restamp and the TEST-4133 row), and docs/ai/decisions.jsonl (2 appended lines).
- spec: docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md (frozen, amended)
- previous review: docs/ai/reviews/review-test-infra-p2-fixes-20261126T143354Z.md (round 2, FAIL on B-2)
- validation input: docs/ai/reports/VALIDATION-20261126T145544Z-test-infra-p2-fixes.md (PASS at 04a6db2a)
- reviewed: 2026-11-26T15:33:27Z

security_relevant: false

(No finding of this ride, open or fixed, touches a security guard, a secret, auth, input sanitisation or a sandbox boundary.)

```yaml
review:
  scope: "d80b73a8..22d27a30 (round-4 remediation delta; code change = tests/skills/test-aai-run-tests.sh:1357,1359; spec row TEST-4133)"
  spec: docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-run-tests.sh:1357,1359 (-u PLAYWRIGHT_BROWSERS_PATH on pw_xdg and pw_home); TEST-4130 rc 0 under an inherited value (B-2 repro exit 0); declared mutant still RED on the owned arm (reviewer replay)" }
      - { ac: Spec-AC-02, call: compliant, citation: "unchanged since round 2; tests/skills/test-framework.sh:1299-1306; TEST-4131" }
      - { ac: Spec-AC-03, call: compliant, citation: "unchanged since round 2; tests/skills/test-framework.sh:2232-2236; TEST-4132" }
      - { ac: Spec-AC-04, call: compliant, citation: "spec row TEST-4133 (line 494) now injects aai_capture_friction \"$STATUS\"; reviewer replay RED on the spool assertion; HEAD single run rc 0" }
      - { ac: Spec-AC-05, call: compliant, citation: "unchanged since round 2; aai-run-tests.sh:1165; TEST-4134" }
      - { ac: Spec-AC-06, call: compliant, citation: "unchanged since round 2; tests/skills/test-aai-prompt-diet.sh:263 TEST-4135" }
      - { ac: Spec-AC-07, call: compliant, citation: "unchanged since round 2; docs-audit-core.mjs:1169; TEST-4136" }
      - { ac: Spec-AC-08, call: compliant, citation: "unchanged since round 2; test-aai-docs-audit.sh:10154 TEST-4137" }
      - { ac: Spec-AC-09, call: compliant, citation: "unchanged since round 2; test-aai-mutation-gate.sh:3723-3790 TEST-4138" }
      - { ac: Spec-AC-10, call: compliant, citation: "unchanged since round 2; test-aai-hygiene-pack.sh:6349-6370 TEST-4139, TEST-4140" }
      - { ac: Spec-AC-11, call: compliant, citation: "spec-lint --path PASS, spec-amend list --strict rc 0, mutation-gate --require-evidence GATE PASS 12 rows (reviewer re-run)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "TEST-4130 is green on a real Linux host through the wrapper (verified here only with the AAI_UNAME=Linux override and an exported value, on macOS)",
        closes_with: "the hosted ubuntu skill-suite run on the PR head with aai-run-tests selected, or a Linux run of the B-2 repro" }
    - { claim: "The ubuntu-latest runner image does not preset PLAYWRIGHT_BROWSERS_PATH in a way that affects arms other than pw_xdg/pw_home (carried from round 2; the set/unset/keep/owned arms do not assert it)",
        closes_with: "the hosted skill-suite run on the PR head" }
    - { claim: "one_world_scan awk string escapes behave the same under mawk/gawk (carried from round 2; untouched by this delta)",
        closes_with: "hosted TEST-4139 and TEST-4140 green on ubuntu" }
    - { claim: "No Windows WSL leg regresses on test-aai-run-tests.sh (carried from round 2)",
        closes_with: "the hosted Windows Pester and WSL legs on the PR head" }
  overall: pass
```

## Scope and preflight

- `worktree.user_decision: worktree`. `git status --porcelain` at start and end: only `docs/ai/EVENTS.jsonl` modified (ledger, outside the scope). The scope is clean.
- `git diff --stat d80b73a8..HEAD`: EVENTS.jsonl +11 (append only, 0 removed lines), decisions.jsonl +2, the round-2 report and repro (new files), the spec (2 lines), tests/skills/test-aai-run-tests.sh (2 lines). 22d27a30 touches only EVENTS.jsonl.
- Dispatch note (anti-gaming contract): the dispatch asked to confirm B-2 and NB-7 closed and said not to re-open the accepted residuals NB-4, NB-6, NB-8 or the tracked P3s. That is a scope exclusion, recorded here. The delta does not touch the code behind NB-4, NB-6 or NB-8 (the only code change is the two `env` lines), so there was nothing in those areas for this round to re-examine. The full delta was reviewed.

## Round-2 findings: closure check

| Round 2 | State at HEAD | Evidence (reviewer re-run) |
|---|---|---|
| B-2 (TEST-4130 pw_xdg/pw_home red with an inherited PLAYWRIGHT_BROWSERS_PATH) | **closed** | `bash docs/ai/reviews/repro-test-infra-p2-fixes-pw-inherited.sh` exits 0: `linux-outer-wrapper` rc 0, `user-exported-value` rc 0. Negative control: a scratch export of HEAD with only the pw_home `-u PLAYWRIGHT_BROWSERS_PATH` removed, run under an outer `AAI_UNAME=Linux`, gives rc 1 `FAIL: TEST-4130 (pw_home): PLAYWRIGHT_BROWSERS_PATH was '<outer xdg>/ms-playwright', expected '<fixture>/home/.cache/ms-playwright'`. The added unset carries weight and the conditions exercise the arm. pw_darwin already unset it; pw_caller sets its own value. |
| NB-7 (TEST-4133 mutation cell named the removed AAI_CMD_REAL_STATUS) | **closed** | The spec row now injects `aai_capture_friction "$STATUS" deterministic_script_failure low low`. Applied to a scratch export of HEAD, the mutant gives TEST-4133 rc 1 with first FAIL `ordinary failures must leave the spool empty (got 2)`, the spool assertion, not a `set -u` abort. HEAD unmutated: rc 0. The stored record `docs/ai/tdd/spec-test-infra-p2-fixes/mutation-TEST-4133.txt` carries the new cell, base 4e22f20d, the same first_fail, and target_sha256 3c8b3936..., which equals the current `.aai/scripts/aai-run-tests.sh`. The decisions.jsonl `spec_amendment` (14:38:28Z) describes exactly this change and is tracked by `fu-amend-spec-test-infra-p2-fixes`. `spec-amend list --strict` rc 0. |
| NB-8 | accepted residual (round 2), not re-opened | The round-2 `accepted residual:` line stands. |

The TEST-4130 declared mutant (owned branch keeps the caller's XDG) was also replayed against the changed test file: rc 1, `FAIL: TEST-4130 (owned): the command saw the caller's XDG_CACHE_HOME`. The 04a6db2a test edit did not weaken the row's mutation. The stored record's base predates the edit, but the target hash is unchanged and the replay matches its first_fail.

## Findings

### BLOCKING

None.

### NON-BLOCKING

None new. The delta is two `env -u` additions and a spec cell with its amendment; I found no failure scenario in it.

### INFO (never gates)

- The B-2 fix covers only the arms that assert PLAYWRIGHT_BROWSERS_PATH. The set/unset/keep/owned arms still inherit it, but they do not assert it, so this is not a defect. Round 2 named the extra unset as optional.

## Reviewer verification (bounded; fake HOME, XDG and TMPDIR under the session scratchpad; scratch `git archive` exports for mutants; no real caches, docker or remotes)

- B-2 repro at HEAD: exit 0.
- Negative control (pw_home unset removed, outer AAI_UNAME=Linux): rc 1 on pw_home.
- TEST-4130 declared mutant on a HEAD export: rc 1 on the owned arm.
- TEST-4133 new declared mutant on a HEAD export: rc 1 on the spool assertion. HEAD single run: rc 0.
- `node .aai/scripts/spec-lint.mjs --path docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md`: LINT PASS. `node .aai/scripts/spec-amend.mjs list --strict`: rc 0. `node .aai/scripts/mutation-gate.mjs --spec ... --require-evidence`: GATE PASS, 12 rows, degraded 0. (The gate is local-only; the replays above are the independent check.)
- No full sweep (per dispatch). The scratch exports were removed, and no process is left running.

## Warning dispositions (H6)

No open WARNINGs from this round. Earlier rounds: NB-4, NB-6 and NB-8 are accepted residuals with their (d) lines in the round-1 and round-2 reports. NB-7 is remediated (a). The P3 follow-ups `fu-fail-wrapper-guard-not-selected`, `fu-runner-xdg-hides-other-tool-caches`, `fu-one-world-dual-form-needs-version` and the P2 `fu-amend-spec-test-infra-p2-fixes` stay open as tracked.

## Next steps

1. Orchestrator: record code_review pass (command in the return block). Stage this report with the next commit (SPEC-0013 H4).
2. The hosted CI run on the PR head closes the four cannot_verify items, chiefly TEST-4130 on a real Linux host.
3. The unsigned amendments remain under `fu-amend-spec-test-infra-p2-fixes` for owner sign-off.

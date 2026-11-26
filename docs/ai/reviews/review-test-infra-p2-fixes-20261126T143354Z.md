# Code review: test-infra-p2-fixes (round 2, re-review)

- ref: test-infra-p2-fixes
- reviewer: dispatched Code Review role (claude-opus-5-5), SKILL_CODE_REVIEW prompt hash 8e6aae0d5197, fresh context
- worktree: /Users/ales/Projects/aai-worktrees/p2-test-infra, branch chore/p2-test-infra, HEAD d80b73a8
- scope: the ride's own changes, `git diff d636a218^2 d80b73a8` (origin/main as merged at d636a218 → HEAD), restricted to the STATE `code_review.scope` path list (23 paths plus docs/INDEX.md). The round-1 delta is b3c245b7, ff243a5b and d80b73a8. The merge resolution in d636a218 (CHANGELOG, ledgers, roadmap, the prompt-diet case list) was checked for correctness.
- spec: docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md (frozen; amended in b3c245b7 and d80b73a8)
- validation input: docs/ai/reports/VALIDATION-20261126T132504Z-test-infra-p2-fixes.md (PASS, full sweep test-20261126-140124 rc 0, run on macOS)
- round 1: docs/ai/reviews/review-test-infra-p2-fixes-20261126T004743Z.md
- reviewed: 2026-11-26T14:33:54Z

security_relevant: false

(As in round 1, no finding touches a security guard, a secret, auth, input sanitisation or a sandbox boundary.)

```yaml
review:
  scope: "d636a218^2..d80b73a8 (ride-only; STATE code_review.scope path list; merge resolution of d636a218 checked)"
  spec: docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:916-950 (owned, mktemp and nonexistent branches; Linux PLAYWRIGHT_BROWSERS_PATH pass-through at 934-947, before the override); TEST-4130 green on macOS; the round-1 B-1 repro exits 0. TEST-4130 is red on Linux under the wrapper, see B-2." }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/test-framework.sh:1299-1306; TEST-4131" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-framework.sh:2232-2236; TEST-4132; the D3 prose now names the argument-parser refusal (spec 162-168)" }
      - { ac: Spec-AC-04, call: compliant, citation: "aai-run-tests.sh:1168 (plain exit, no capture); TEST-4133 green. Its declared mutation no longer exercises the spool assertion, see NB-7." }
      - { ac: Spec-AC-05, call: compliant, citation: "aai-run-tests.sh:1165 (stalled_progress medium low); TEST-4134" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/test-aai-prompt-diet.sh:66 e2e_fixture_root, :263 TEST-4135; the D5 prose amended to match the global E2E_ROOT (spec 197-206)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/lib/docs-audit-core.mjs:1169; tests/skills/test-aai-docs-audit.sh:10112 TEST-4136" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/test-aai-docs-audit.sh:10154 TEST-4137, DA_MAIN_STEPS at :10189" }
      - { ac: Spec-AC-09, call: compliant, citation: "tests/skills/test-aai-mutation-gate.sh:3723-3790; TEST-4138 rc 0 (reviewer re-run), now with a FAILED-word control" }
      - { ac: Spec-AC-10, call: compliant, citation: "tests/skills/test-aai-hygiene-pack.sh:6349-6368, 6370 TEST-4139 rc 0 (reviewer re-run, six controls), 6406 TEST-4140; AC text amended to six controls in d80b73a8" }
      - { ac: Spec-AC-11, call: compliant, citation: "CHANGELOG.md:33; docs/TECHNOLOGY.md:177-187; TEST-4141 (full sweep test-20261126-140124); spec-amend list --strict rc 0, spec-lint --path PASS (reviewer re-run)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 1357,
          issue: "The pw_xdg (1357) and pw_home (1359) arms of TEST-4130 do not unset an inherited PLAYWRIGHT_BROWSERS_PATH. Only pw_darwin does. The b3c245b7 pass-through makes every Linux outer wrapper export that variable, so the nested wrapper keeps it as a caller value and both arms fail.",
          failure_scenario: "On any Linux host (including WSL, and the WSL route of aai-run-tests.ps1), the canonical `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh`, or the single-suite form, fails with `FAIL: TEST-4130 (pw_xdg): PLAYWRIGHT_BROWSERS_PATH was '<caller XDG>/ms-playwright', expected '<fixture>/xdg/ms-playwright'`. The same happens to a Linux user who has PLAYWRIGHT_BROWSERS_PATH exported. Validation ran on macOS and CI runs test-framework.sh without the wrapper, so neither saw it. backed-by: docs/ai/reviews/repro-test-infra-p2-fixes-pw-inherited.sh (exit 1 on HEAD; exit 0 on a scratch clone with `-u PLAYWRIGHT_BROWSERS_PATH` added to both arms)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md, line: 494,
          issue: "TEST-4133's Mutation cell still injects `aai_capture_friction \"$AAI_CMD_REAL_STATUS\" ...`. b3c245b7 removed that variable, and the wrapper runs under `set -u` (line 119), so the mutant now aborts with `AAI_CMD_REAL_STATUS: unbound variable` (exit 1) and writes no friction. TEST-4133 goes RED on its exit-code assertion, not on the spool assertion that the record's first_fail names.",
          failure_scenario: "Replaying the mutation gives RED for a different reason (reviewer probe: rc 1, spool empty). A later edit that drops TEST-4133's spool_count assertion, or routes ordinary failures into the spool another way, keeps the declared mutant RED. The gate passes while Spec-AC-04's zero-observations half has no working mutant. The stored record (base 0463de47, first_fail 'ordinary failures must leave the spool empty (got 2)') no longer describes what the mutant does at HEAD, which is a false record." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 6364,
          issue: "The new escaped-dual exemption (`unreleased\\]|`, `unreleased\\\\]|`) accepts any alternation after the escaped token, not only one with a version or date branch. The same weakness already existed for the plain `unreleased|` form; ff243a5b extends it to the escaped spelling.",
          failure_scenario: "`grep -qE '^## (\\[unreleased\\]|\\[Unreleased\\])' \"$PROJECT_ROOT/CHANGELOG.md\"` asserts only the unreleased heading and goes red after a release cut, but one_world_scan prints nothing for it (reviewer probe: that line and the plain `\\[(unreleased|Unreleased)\\]` form are not named; the true unreleased-only shapes still are). No live instance exists." }
  cannot_verify:
    - { claim: "On Linux, Playwright resolves browsers under $XDG_CACHE_HOME/ms-playwright, else ~/.cache/ms-playwright (the basis of the pass-through; the spec states it as an assumption)",
        closes_with: "playwright-core registry source (defaultCacheDirectory), or a Linux throwaway project: npx playwright install, then bash .aai/scripts/aai-run-tests.sh npx playwright test" }
    - { claim: "The ubuntu-latest runner image does not preset PLAYWRIGHT_BROWSERS_PATH (if it does, B-2 also bites the CI skill-suite jobs that run test-framework.sh without the wrapper)",
        closes_with: "the hosted skill-suite run on the PR head with aai-run-tests selected (TEST-4130 green), or `env` from a runner step" }
    - { claim: "one_world_scan's new awk string escapes (\"unreleased\\\\]|\", \"unreleased\\\\\\\\]|\") give the same literals under mawk/gawk as under the BSD awk the suites ran on",
        closes_with: "the hosted run on the PR head: aai-hygiene-pack TEST-4139 (c-dual-esc control) and aai-hygiene-corpus TEST-4140 green on ubuntu" }
    - { claim: "No Windows leg runs test-aai-run-tests.sh through the WSL route of aai-run-tests.ps1 (where UNAME_S is Linux and B-2 would bite)",
        closes_with: "the hosted Windows Pester and WSL legs on the PR head" }
    - { claim: "D2/D3 behave the same on the CI runner (no wrapper, Linux mktemp, bash 5), carried from round 1",
        closes_with: "the hosted skill-suite run on the PR head" }
  overall: fail
```

## Scope and preflight

- `worktree.user_decision: worktree`. `git status --porcelain` at start: only `docs/ai/EVENTS.jsonl` modified (ledger, out of scope). The scope is clean.
- Ride-only diff: `git diff d636a218^2 d80b73a8 --stat -- . ':!docs/ai'` lists the same 23 paths as the STATE scope plus docs/INDEX.md.
- Dispatch note (anti-gaming contract): the dispatch named focus areas ("especially ...") and the dispositions already taken for NB-2, NB-4 and NB-6. It did not pre-rate a severity or exclude anything from scope. This is recorded here, and the full scope was reviewed.

## Round-1 findings: closure check

| Round 1 | State at d80b73a8 | Evidence |
|---|---|---|
| B-1 (TEST-4130 missed the owned branch) | **closed** | `bash docs/ai/reviews/repro-test-infra-p2-fixes-owned-xdg-mutant.sh` exits 0. TEST-4130 now fails on the mutant with `(owned): the command saw the caller's XDG_CACHE_HOME`. The owned arms assert `*/aai-tr-*/xdg-cache` and an empty sandbox afterwards. On failure, `rm -rf "$root"` covers the sandbox, because `$tmpd` is under `$root`. The amended Mutation cell for TEST-4130 targets the owned branch. |
| NB-1 (Playwright browsers hidden on Linux) | **closed in tree; it introduced B-2** | aai-run-tests.sh:934-947. It runs before `XDG_CACHE_HOME="$AAI_XDG_CACHE_DIR"`, so it reads the caller's value, not the private one. It is `set -u`-safe: all three reads use `:-`, and `UNAME_S` is set at line 136. A caller value (including Playwright's `0`) is kept. Nothing is exported off Linux, and no directory is created. A nested wrapper inherits the outer export, so the real path survives nesting. The residual for other tools is tracked as `fu-runner-xdg-hides-other-tool-caches` (P3, open, verified). B-2 is the test arms' failure to isolate from that export. |
| NB-2 (guard not selected) | **promoted** | `fu-fail-wrapper-guard-not-selected` P3 is open (verified with `follow-ups.mjs list`). |
| NB-3 (D3/D5 prose) | **closed** | Spec lines 162-168 (D3) and 197-206 (D5) are amended additively. spec-lint `--path` PASS; `spec-amend list --strict` rc 0. The amendment is unsigned and tracked by `fu-amend-spec-test-infra-p2-fixes` (P2, open). |
| NB-4, NB-6 | **accepted residual** | The (d) lines are in the round-1 report and STATE notes. They are unchanged by the delta. |
| NB-5 (`includes("FAIL")`) | **closed** | mutation-gate.sh:3747 now uses `/\bFAIL\b/`. The new `bad-word.sh` control (`FAILED=1; echo "✗ FAILED $*"`) is named. TEST-4138 rc 0 on a reviewer re-run. |
| INFO (unused AAI_CMD_REAL_STATUS) | removed | The removal left TEST-4133's Mutation cell pointing at the deleted variable (NB-7). |

## Merge resolution (d636a218)

- CHANGELOG.md: keep-both is correct. The ride's `## [unreleased] — Test infrastructure: the nine P2 follow-ups` sits under the `## [unreleased]` scaffold, above main's three per-entry headings. Every entry is its own `## [unreleased] — <title>` heading, which is what aai-release requires.
- docs/ai/EVENTS.jsonl and docs/ai/decisions.jsonl: base-first is confirmed. Against main's blob (`d636a218^2`), `git diff` removes 0 lines and both hunks sit at the tail (4639+, 3622+). `d636a218^2..HEAD` also removes 0 lines. Every non-comment line parses as JSON; the 15 non-JSON lines in decisions.jsonl are the header comments, the same as on main.
- docs/ai/roadmap.yaml: both rows are kept.
- tests/skills/test-aai-prompt-diet.sh `main()`: both `test_4135_dry_run_never_writes_project_root` (ride, defined at :263) and `test_4134_onboarding_ledger_entry` (main, :2944) are called once each.
- The merge brought tests/skills/test-aai-harness-shims.sh:1348, a correct escaped dual-form assertion. That line is what made ff243a5b necessary. It is now exempt, and TEST-4140 was green in the full sweep.

## Findings

### BLOCKING

**B-2. tests/skills/test-aai-run-tests.sh:1357 and :1359. TEST-4130's pw_xdg and pw_home arms are red whenever PLAYWRIGHT_BROWSERS_PATH is inherited, which covers every Linux run through the wrapper.**
The pass-through added in b3c245b7 runs in the outer wrapper too. On Linux, the outer `aai-run-tests.sh` exports `PLAYWRIGHT_BROWSERS_PATH=<caller XDG or HOME>/.cache/ms-playwright` into the framework and the suite. The pw_xdg and pw_home arms expect the nested wrapper to derive the path from the fixture's XDG/HOME, but the nested wrapper sees a non-empty caller value and keeps it, as designed. Only pw_darwin passes `-u PLAYWRIGHT_BROWSERS_PATH`.
- Failure scenario: a Linux or WSL contributor, a Linux-hosted validator, or the WSL route of `aai-run-tests.ps1` runs the canonical `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh` (SKILL_TEST_SKILLS) or the single-suite form, and aai-run-tests fails deterministically. The macOS sweep cannot see this because Darwin never exports the variable. Hosted CI ubuntu runs `test-framework.sh` without the wrapper, so it does not see it either, unless the runner image presets the variable (see cannot_verify).
- backed-by: `bash docs/ai/reviews/repro-test-infra-p2-fixes-pw-inherited.sh` exits 1 on HEAD d80b73a8. Both an outer wrapper with `AAI_UNAME=Linux` and a user-exported value give `FAIL: TEST-4130 (pw_xdg)`.
- Fix direction (the implementer's call; verified): add `-u PLAYWRIGHT_BROWSERS_PATH` to the pw_xdg and pw_home `env` lines. On a scratch clone with exactly that two-line change, the repro exits 0. Optionally also unset it for the set/unset/keep/owned arms, which do not assert it today. Re-record the TEST-4130 mutation only if the row changes.

### NON-BLOCKING (WARNINGs; H6 dispositions recommended, the orchestrator records them)

**NB-7 (P2, leaves a false record). docs/specs/SPEC-DRAFT-spec-test-infra-p2-fixes.md:494. TEST-4133's declared mutant now dies on `set -u` instead of recording friction.**
Reviewer probe on a scratch clone at HEAD, with the cell applied: `sh .aai/scripts/aai-run-tests.sh sh -c 'exit 7'` exits 1 with `line 1168: AAI_CMD_REAL_STATUS: unbound variable`, and the fixture spool stays empty. TEST-4133 is still RED, but through `exit 7 must pass through (got 1)`. The stored record (`mutation-TEST-4133.txt`, base 0463de47) names the spool assertion as first_fail.
- Recommended disposition: (a) remediate in tree in the same round as B-2. Change the cell to `sed:s/^exit "\$STATUS"$/aai_capture_friction "$STATUS" deterministic_script_failure low low; exit "$STATUS"/m` with an additive amendment sentence under `fu-amend-spec-test-infra-p2-fixes`, then re-record TEST-4133 and check that first_fail is the spool assertion again. (d) is not available because the finding leaves a false record.

**NB-8 (P3). tests/skills/test-aai-hygiene-pack.sh:6364. The escaped dual-form exemption accepts any alternation.**
`(\[unreleased\]|\[Unreleased\])` against the real CHANGELOG is not flagged. The plain-form equivalent has had the same gap since round 1.
- Recommended disposition: (d) accepted residual. This is a P3 assurance-strength gap with no live instance, it has not bitten, and it leaves no false record. Alternative: (a) also require a version or date token on the line (`v[0-9`, `[0-9]{4}`, `[0-9.]`) for both the plain and escaped exemptions.
- accepted residual: NB-8 one_world_scan's dual-form exemption (plain and escaped) accepts any alternation after the unreleased token, not only a version or date branch (P3, no live instance)

### INFO (never gates)

- TEST-4130 to TEST-4141 overlap with ids used by SPEC-0317 and SPEC-0318, which were merged from main. 175 TEST ids are already shared across specs in docs/specs, so ids are spec-local by convention. Every overlapping pair lives in a different suite, or as a different function in the same suite (prompt-diet: ride TEST-4135 and main TEST-4134). Selector-based mutation attribution is unaffected.
- The TEST-4130 pass text ("PLAYWRIGHT_BROWSERS_PATH points at the caller's own cache on Linux only") is accurate only once B-2 is fixed. Before that, it holds only where no value is inherited.

## Reviewer verification (bounded; fake HOME, XDG and TMPDIR under the session scratchpad; friction capture off; no real caches, docker or remotes)

- TEST-4130 single run through the wrapper on macOS: rc 0. With `PLAYWRIGHT_BROWSERS_PATH` inherited: rc 1. With an outer `AAI_UNAME=Linux`: rc 1. The scratch TMPDIR and XDG were empty afterwards.
- B-1 repro (round 1): exit 0.
- B-2 repro: exit 1 on HEAD, exit 0 on a scratch clone with the two-arm fix.
- TEST-4138 (`test_4138_fail_wrappers_print_fail`) and TEST-4139 (`test_4139_one_world_scan_bites`), single runs through the wrapper: rc 0 and rc 0.
- one_world_scan probe (six shapes): it names the bare `\[unreleased\] ... CHANGELOG.md || fail` and a `| head` form. It does not name the correct dual forms (escaped regex, node `\\[unreleased\\]|^## \\[v`, version alternation). It also does not name the two case-alternation unreleased-only shapes (NB-8).
- TEST-4133 mutant probe: see NB-7.
- spec-lint `--path` on the spec: PASS. `spec-amend list --strict`: rc 0.
- Follow-ups `fu-fail-wrapper-guard-not-selected`, `fu-runner-xdg-hides-other-tool-caches` and `fu-amend-spec-test-infra-p2-fixes` are open.
- No full sweep was run (per dispatch). All scratch clones and probes were removed, and no process is left running.

## Next steps

1. Remediation: fix B-2 (two `env -u` additions) and NB-7 (Mutation cell, amendment and re-record) in one round. Re-run TEST-4130 under the B-2 repro, which should exit 0, and replay TEST-4133's mutation.
2. Orchestrator: record NB-8 (adopt the accepted-residual line above, or choose (a)).
3. Re-review (round 3) on the remediation delta. The hosted CI run on the PR head closes the awk, runner-image and Windows cannot_verify items.
4. Stage this report and `repro-test-infra-p2-fixes-pw-inherited.sh` with the review-response commit (SPEC-0013 H4).

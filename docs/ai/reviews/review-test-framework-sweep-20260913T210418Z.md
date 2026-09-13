# Code Review — spec-test-framework-sweep (ceremony 2, rule 13 dual verdict)

Reviewer: independent Code Review role (claude-opus-5), unattended ride.
Implementer: claude-sonnet-5 (10 TDD runs + 2 remediation rounds). Validator:
claude-opus-5 (3 rounds). Neither report was trusted; every claim below was
re-derived from the tree, the diff, or a mutation I ran myself.

```yaml
review:
  scope: "origin/main...HEAD (d184ec04) plus the uncommitted working tree (19 tracked files) — 91 files, +7632/-932"
  spec: docs/specs/SPEC-DRAFT-spec-test-framework-sweep.md (FROZEN, 28 AC, 49 TEST, 2 Amendment rounds)
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "tests/skills/test-aai-layer-profiles.sh copy_fixture_item/verify_fixture_copy_completeness (diff +73/+94); TEST-401, red-401.txt" }
      - { ac: Spec-AC-02, call: compliant, citation: "test-aai-layer-profiles.sh run_sync_or_fail (+49, fails on 'missing in source') and assert_list_empty (+25, byte dump); TEST-402/403, red-402/403.txt" }
      - { ac: Spec-AC-03, call: compliant, citation: ".aai/scripts/branch-guard.mjs:409-441 (codes 5/6/7 distinct); check-committed-scope.mjs:79-85, close-before-push-guard.mjs:76-82, close-work-item.mjs:1606-1612; TEST-405/406/407 + my mutation M4 reddened the detached-HEAD arm" }
      - { ac: Spec-AC-04, call: compliant, citation: "branch-guard.mjs:309-343 pinDirFast (stat-only); no-pin -> exit 0; TEST-408 (blob-pinned pre-change baseline, test-aai-branch-guard.sh:51-64)" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/lib/session-lock.mjs:111-181 (O_EXCL CAS + process.kill(pid,0) + sentinel reclaim); TEST-409/410; my M6 and M7 both reddened TEST-409" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/test-framework.sh:1717-1870 run_queue; I re-derived the gate from docs/ai/tests/test-runs.jsonl myself: test-20260913-185949 = 93/93, width 8, 18:59:49Z->19:14:46Z = 897 s; 897/1632 = 55.0% <= 65%. TEST-411/412" }
      - { ac: Spec-AC-07, call: compliant, citation: "test-framework.sh:1776-1853 rolling window, :1798-1802 2x-width truncation; TEST-413/414; my M1 (drain removed) and M3 (truncation removed) both reddened" }
      - { ac: Spec-AC-08, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:87 TIMEOUT default 3000 + named line :903; aai-run-tests.ps1 Get-EffectiveTimeout 3000; tests/skills/test-ps1-quality.sh:51-71 pwsh-free parity pin; TEST-415 (in test-aai-run-tests.sh, which IS in the sweep) carries the AC itself. See NB-9 (CI ceiling) and NB-15 (the extra parity pin is CI-only)" }
      - { ac: Spec-AC-09, call: compliant, citation: "test-framework.sh:1163-1180 heartbeat_pulse, called per finished suite at :1513; TEST-416" }
      - { ac: Spec-AC-10, call: compliant, citation: ".aai/scripts/golden-flow.mjs:390-412 withAppendLock; new .aai/scripts/lib/append-lock.mjs; TEST-417; my M8 (lock bypassed) reddened it" }
      - { ac: Spec-AC-11, call: compliant, citation: "tests/skills/lib/pipe-grep-q-baseline.tsv now carries zero data rows; tests/skills/lib/assert-payload.sh:115/135/153 three helpers; TEST-418/419/420" }
      - { ac: Spec-AC-12, call: compliant, citation: "nine guards + controls: test-aai-release.sh:74 RELEASE_ENGINE_PIN_SHA=6adfe840 (verified a genuinely different blob) + test_031 control; TEST-421/445/446/447/448/422 all exist as real arms" }
      - { ac: Spec-AC-13, call: compliant, citation: "ceremony TEST-016 byte pin deleted; spec-lint whole-line usage pins; follow-ups -le 3 + subset; tripwire TEST-013 premise; TEST-423/424/425" }
      - { ac: Spec-AC-14, call: compliant, citation: "tests/skills/lib/degenerate-pass-ratchet.sh + degenerate-pass-baseline.tsv; I measured the corpus myself: 26 live (case-sensitive), 31 on origin/main — baseline sum is exactly 26. TEST-426; my M10 (27th site planted) reddened it naming the RISE" }
      - { ac: Spec-AC-15, call: compliant, citation: "tests/skills/lib/learned-guard-lints.mjs six RULES; docs/knowledge/LEARNED.md markers name the shipped guard; TEST-427/428; my M11 (one lint deleted) reddened. See NB-11 on the 'indirect' marker" }
      - { ac: Spec-AC-16, call: compliant, citation: ".aai/SKILL_TDD.prompt.md:246-249 names select-suites.mjs (VALIDATION.prompt.md:173-184 already did, established fact 6); suite-map.yaml:848+ aai-state gains ROLE_COMMON.md; ledger +197 B, pin re-summed to 26928; TEST-429/430" }
      - { ac: Spec-AC-17, call: compliant, citation: "test-aai-suite-isolation.sh:2450-2480 per-entry base removal; .aai/scripts/aai-run-tests.sh:719 aai_reap_group, :745-747 traps reap before cleanup; TEST-431/432; my M12 reddened" }
      - { ac: Spec-AC-18, call: compliant, citation: "test-framework.sh:553-560 and :576-579 iso_seed_fail on each failure; aai-run-tests.sh:573-583 marker fallback; TEST-433. CODE is compliant; the TEST evidence for the enumeration half is incomplete — see NB-5 (mutation M13 survived)" }
      - { ac: Spec-AC-19, call: compliant, citation: "~20 explicit AAI_TEST_ISOLATION=1 call sites in test-aai-suite-isolation.sh (e.g. :220, :284, :332); wrapper hidden-suite isolation line; TEST-434/435" }
      - { ac: Spec-AC-20, call: compliant, citation: "test-framework.sh:1270-1296 folds pre-dirty out-of-list paths into tw_unlisted using the before-snapshot it already holds; TEST-436/437. See NB-6 for the now-stale library comment" }
      - { ac: Spec-AC-21, call: compliant, citation: "four withdrawn phrases corrected, grep returns 0 over tests/skills, .aai/ and docs/specs; TEST-438" }
      - { ac: Spec-AC-22, call: compliant, citation: "22 of 23 real main guards resolve both sides through realpath; allocate-doc-number.mjs:1255 is the disclosed protected_paths_l3 exclusion, tracked by fu-realpath-allocate-doc-number-l3; TEST-439; my M9 reddened it AND proved the symlink behaviour difference (direct rc=2 vs symlink rc=0)" }
      - { ac: Spec-AC-23, call: compliant, citation: "test-aai-run-tests.sh:274/312 pin the reaper mode explicitly; TEST-440, 5 consecutive green recorded" }
      - { ac: Spec-AC-24, call: compliant, citation: "test-aai-docs-audit.sh / test-aai-delta-stage3.sh tolerate an unlisted working-tree doc; TEST-441 + mutation-441.txt (cannot-go-RED, control restores the hard check)" }
      - { ac: Spec-AC-25, call: compliant, citation: "test-aai-orchestration-dispatch.sh:3906-3999 imports loadModelRouting from the shipped engine; TEST-442" }
      - { ac: Spec-AC-26, call: compliant, citation: "84/84 bucket ids terminal (48 done + 36 dropped), all carrying resolved_by=test-framework-sweep; verify-closures --strict rc=0, claims=48 miss=0; suite-map row-count pin = 93; prompt-diet ledger entry present; TEST-443" }
      - { ac: Spec-AC-27, call: compliant, citation: "docs/issues/CHANGE-0166-*.md frontmatter status: done, links.pr [307], commits [12112e4f], before/after wall-clock recorded; TEST-444" }
      - { ac: Spec-AC-28, call: compliant, citation: "test-aai-feedback-upsert.sh nested_suite_fail (+21) writes the nested log to a file and names it with its line count; test-aai-friction-wiring.sh twin; TEST-404/449" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/close-before-push-guard.mjs, line: 66,
          issue: "the new --expect-branch guard FAILS OPEN on a missing value: `args.expectBranch = argv[++i]` with no validation, so `--expect-branch` as the last token (or with an unset shell variable) sets undefined/'' and verifyExpectedBranch's `if (!expectBranch) return` silently disables the guard. close-work-item.mjs:256 is identical; the sibling check-committed-scope.mjs:64 does it correctly via the validating need().",
          failure_scenario: "REPRODUCED on a fixture repo: pinned on feat/right, HEAD moved to feat/other. `close-before-push-guard.mjs --ref zzz --expect-branch feat/right` -> rc 3, REFUSED (correct). The same command with a trailing bare `--expect-branch` -> the pin check never runs and the script proceeds. Once the flag is wired into SKILL_PR and a prompt passes an unset ${BRANCH}, the ceremony pushes onto the branch a concurrent session moved it to — the exact CHANGE-0180 incident the flag exists to prevent." }
      - { rank: NON-BLOCKING, file: .aai/scripts/branch-guard.mjs, line: 348,
          issue: "--verify-pin / --expect-branch throw an UNCAUGHT exception outside a git work tree. --pin/--verify-pin are dispatched at :458-459, before the workTreeProbe at :482 that gives guard mode its clean exit-4-with-message, and readPin's try/catch covers only the JSON read, not pinFilePath -> pinDir -> git() above it.",
          failure_scenario: "REPRODUCED: `node branch-guard.mjs --verify-pin` in a non-repo directory prints a raw Node stack trace (`Error: Command failed: git rev-parse --git-dir`, status 128) and exits 1 — a code outside the documented closed set for this mode (0/5/6/7), and exit 1 already means 'branch equals base' in guard mode. Same for check-committed-scope.mjs --expect-branch, close-before-push-guard.mjs --expect-branch and close-work-item.mjs. session-lock.mjs:76 (lockDir -> gitDir) carries the identical latent shape." }
      - { rank: NON-BLOCKING, file: .aai/scripts/check-committed-scope.mjs, line: 79,
          issue: "--expect-branch never compares its own argument. All three verifyExpectedBranch implementations use the flag as a boolean opt-in and then compare against the PIN FILE, ignoring the branch name passed.",
          failure_scenario: "REPRODUCED: with a valid pin on feat/right and HEAD unmoved, `--expect-branch feat/TOTALLY-WRONG` passes the check. A caller who believes the flag asserts what it names gets no such assertion; the real (and correct) check is the pin, so the flag name and its usage string `[--expect-branch <branch>]` overstate the contract." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 557,
          issue: "Spec-AC-18's 'partly seeded, never seeded' verdict for the step-2 enumeration case is asserted by nothing. TEST-433(b) (test-aai-suite-isolation.sh:2564) greps only for the log_warn TEXT; the iso_seed_fail call at :558 that turns the observation into the PARTIAL verdict is unasserted.",
          failure_scenario: "MUTATION M13, RUN: deleting `iso_seed_fail \"the untracked-file enumeration could not read part of the working tree\"` at :558 (keeping the log_warn) leaves test-aai-suite-isolation.sh rc=0 with TEST-433 PASS. A future refactor that separates the warn from the verdict ships silently, and a sweep whose enumeration was partial reports every suite `seeded` — the defect fu-seed-step2-enumeration-silent was closed for." }
      - { rank: NON-BLOCKING, file: .aai/scripts/branch-guard.mjs, line: 319,
          issue: "the GIT_DIR deference in pinDirFast (added for validation round-2 NB-1) has no test a mutation reddens.",
          failure_scenario: "MUTATION M5, RUN: deleting `if (process.env.GIT_DIR) return null;` leaves test-aai-branch-guard.sh rc=0, 20 PASS. With GIT_DIR set and a cwd that also carries its own .git, the fast path would resolve the pin under the LOCAL .git, find no pin, and exit 0 — the guard silently stops guarding, the class this whole ride exists to remove." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/repo-tripwire.sh, line: 97,
          issue: "a KNOWN LIMIT block still states that in tests/skills/test-framework.sh an allowlisted suite writing an already-dirty non-ratchet path 'reads tripwire ALLOWED ... at exit 0', and closes with 'Tracked as fu-tripwire-allowed-ignores-pre-dirty' — a follow-up THIS RIDE closed as done by fixing exactly that in the caller (test-framework.sh:1282-1296).",
          failure_scenario: "A reader of the library believes the bound is open and re-files it, or a future caller declines to close it 'because the library says it cannot be closed'. This is the Spec-AC-21 withdrawn-claim class, in a file Spec-AC-21's four-phrase grep does not cover, introduced by this ride's own AC-20 fix." }
      - { rank: NON-BLOCKING, file: tests/skills/lib/degenerate-pass-ratchet.sh, line: 37,
          issue: "the corrected provenance comment carries a wrong digit: it says `grep -i` over the same corpus reads '35/31'.",
          failure_scenario: "MEASURED by me under bash with /usr/bin/grep: pre-scope 31 (case-sensitive) / 35 (-i); post-scope 26 / 30. The post-scope -i figure is 30, not 31. The substantive claim (the gap is entirely qualifier casing, 4 in both directions) holds; the number does not. A future author recomputing from this comment reads a false baseline. (= validator R3-NB-4, independently confirmed.)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/close-before-push-guard.mjs, line: 28,
          issue: "the header's `Exit codes:` contract block documents 0/1/2 and was not extended with the new exit 3 (HEAD pin refused), although the usage string at :56 does advertise the flag. check-committed-scope.mjs gained exit 3 with no exit-contract block at all. close-work-item.mjs documents exit 7 in its header but its usage string at :226 omits --expect-branch.",
          failure_scenario: "A consumer or wrapper script that branches on this CLI's documented exit set treats 3 as unknown; the ride's own AC-04 claim of a byte-identical contract is checked by TEST-408 only for the no-pin path, so no test notices the undocumented code." }
      - { rank: NON-BLOCKING, file: .github/workflows/skill-suite.yml, line: 161,
          issue: "raising the wrapper's default AAI_TEST_TIMEOUT from 300 s to 3000 s puts the inner watchdog ABOVE both CI job ceilings (skills-selected timeout-minutes: 15 = 900 s at :123, skills-full timeout-minutes: 30 = 1800 s at :161). The workflows are unchanged on this branch. 24 suites invoke aai-run-tests.sh inside their own fixtures.",
          failure_scenario: "A fixture command inside e.g. test-aai-close-work-item.sh deadlocks on CI. Before: at 300 s the wrapper printed its named line (aai-run-tests.sh:903) and exited 124, the suite reported a named failure and the log named the suite. After: the wrapper waits 3000 s, GitHub kills the JOB at 30 min with 'exceeded the maximum execution time' — no suite attribution, no wrapper line. That inverts Spec-AC-08's own stated purpose (aai-run-tests.sh:29-32, '124 alone never said what ceiling was hit'). The same applies to any harness whose own tool timeout is below 3000 s (Claude Code's Bash tool caps at 600 s), where the named line is unreachable by construction." }
      - { rank: NON-BLOCKING, file: .aai/scripts/lib/session-lock.mjs, line: 36,
          issue: "CHANGE-0180's D4/D5 mechanism is INERT in the shipped flow. Nothing pins and nothing locks: grep over .aai/*.md and .aai/system/ for `--pin`, `--verify-pin`, `--expect-branch` or `session-lock` returns exactly one hit — the PROFILES.yaml classification line. .aai/SKILL_PR.prompt.md is byte-unchanged on this branch despite being named in the spec's Implementation plan (:433) as a component changed, and still runs only `branch-guard.mjs --base`. Nothing imports session-lock.mjs (its own header says 'used by tests and, eventually, the ceremony scripts'), contradicting the spec's ':432 consumed by the ceremony scripts'.",
          failure_scenario: "CHANGE-0180 AC-001's premise ('a ceremony step that recorded branch B') is never created, so exits 5/6/7 are unreachable in the live flow and the 2026-09-06 P1 remains undetected in practice. Spec-AC-03/04 are written conditionally and ARE satisfied by the fixture tests, so this is a delivery-scope gap rather than an AC failure — but fu-head-moved-between-commands (the bucket's only P1) is closed `done` against a guard nothing arms." }
      - { rank: NON-BLOCKING, file: docs/knowledge/LEARNED.md, line: 48,
          issue: "fu-learned-worktree-seeded-copies is closed `done` under Spec-AC-05 against a mechanism that addresses a different shape and has no caller. The marker itself concedes it: 'guard shipped: indirectly ... the pre-pull stale-untracked-copy cleanup habit itself remains an operator action, not automated.' fu-learned-framework-owns-how's marker names no guard at all ('routed to canon, not shipped as a guard here') while that id is in the DROPPED table.",
          failure_scenario: "The registry reads as 'this lesson is now enforced' when it is not; the next author who hits the stale-untracked-copy pull abort finds a closed item and no guard. Honest in the marker text, misleading in the ledger." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-hygiene-pack.sh, line: 1789,
          issue: "TEST-427's per-rule arm aborts SILENTLY when a lint is missing from learned-guard-lints.mjs RULES — rc is non-zero (so the mutation IS caught) but no FAIL line, no named reason is printed under `set -euo pipefail`.",
          failure_scenario: "MUTATION M11, RUN: deleting the `immutable-pin` rule gives rc=1 with the last output line being `INFO: test_125: ...` and nothing after it. A CI reader sees a red suite with no statement of what failed — the same 'a red that does not say why' shape the ride's D-decisions target." }
      - { rank: NON-BLOCKING, file: docs/ai/tdd/spec-test-framework-sweep/sweep-after.txt, line: 130,
          issue: "the 93/93 UPDATE block was inserted ABOVE the pre-existing section headed 'THE FOUR FAILURES IN THIS RUN, individually explained', which describes run test-20260913-180339 (89/93).",
          failure_scenario: "A reader of the evidence file reads 'THIS RUN' as the zero-failure run it now directly follows and concludes the 93/93 sweep had four explained failures. Content correct, placement misleading. (= validator R3-NB-5, confirmed by reading the file.)" }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-DRAFT-spec-test-framework-sweep.md, line: 685,
          issue: "the drop reason for fu-spec-evidence-cites-gitignored-path over-claims: 'no spec in the repository cites a gitignored evidence path today'. Measured twice, independently, over every docs/specs/*.md AC Status table with git check-ignore: 470 of 575 unique cited paths are gitignored, 842 of 1,193 individual AC-row citations, across 120 spec documents — root cause .gitignore:35 `docs/ai/tdd/**`, which is the HOUSE STYLE for AC evidence. It is not a residue, it is the dominant convention, and the two most recently merged specs do it (SPEC-0177:528 `docs/ai/tdd/spec-harness-universal-routing/red-050.txt`; SPEC-0178 Spec-AC-01) — as does THIS ride's own Evidence contract. The narrower half ('the one spec doing it is no longer the shape described') is defensible.",
          failure_scenario: "The item is closed `dropped` on a claim that is measurably false, so the append-only ledger records a withdrawal that a later reader cannot reproduce. Nothing in the tree breaks; the record does." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 948,
          issue: "Spec-AC-08's own new guard lives in a suite the local evidence chain never runs. discover_tests()'s full-run branch is `find \"$SCRIPT_DIR\" -name \"test-aai-*.sh\"`; tests/skills/test-ps1-quality.sh has no `aai-` prefix, so it is NOT one of the 93 suites (95 test-*.sh files minus test-framework.sh minus test-ps1-quality.sh = 93, exactly the cited sweep's count), and it has no suite-map.yaml suite row, so select-suites.mjs cannot select it either. Pre-existing glob/mapping gap — newly load-bearing because remediation put AC-08's parity pin there.",
          failure_scenario: "The spec says the new grep-based check 'pins the two defaults equal going forward'. Locally it pins nothing: neither the full sweep cited as AC-06/AC-08 evidence nor the selector will ever schedule it. Its only real exercise is .github/workflows/ps1-quality.yml's `gate` job (:135, `bash tests/skills/test-ps1-quality.sh`, ubuntu-latest with Pester 5 installed), which this PR's paths filter does match — so the guard IS gated, by CI alone. If that workflow's paths filter ever stops matching a future .ps1/.sh timeout edit, the defaults can drift again with every local gate green." }
      - { rank: NON-BLOCKING, file: tests/skills/test-ps1-quality.sh, line: 64,
          issue: "NEW, uncommitted code: `ps1_fallback_count=\"$(grep -cE '^\\s*return [0-9]+\\s*$' \"$RUN_PS1\")\"` is assigned and never read (one hit in the whole file), and `grep -c` exits 1 on zero matches under this suite's `set -euo pipefail` (:24).",
          failure_scenario: "A future aai-run-tests.ps1 that expresses its fallback without a bare `return <n>` line, or a host grep whose ERE does not honour `\\s`, makes the assignment exit 1 and kills the suite at a dead statement — no assertion, no message, an unexplained red in the one gate that protects the .ps1/.sh timeout parity. Delete the line. (= validator round-2 NB-4, still unfixed; the adjacent `:53-54`/`:71` prose claiming the Pester leg 'cannot be exercised on this machine at all' is also false — I ran it, 150 cases.)" }
      - { rank: NON-BLOCKING, file: tests/skills/test-ps1-quality.sh, line: 1,
          issue: "PRE-EXISTING, not introduced here and NOT reachable in CI: run through the framework's isolation clone on a host with Pester 5, ps1-quality fails 1 of 150 Pester cases — aai-update.Tests.ps1:77 'refuses (exit 2) when run inside the canonical AAI repo without -Force', Expected 2 but got 0, because test-framework.sh:490 rewrites the clone's origin to ORIGIN-DISABLED-BY-ISOLATION and aai-update.ps1:57-61 decides canonical-repo membership from exactly that URL.",
          failure_scenario: "I reproduced it identically on a clean clone of origin/main (082ad4aa): `Tests Passed: 149, Failed: 1`, rc=1 on BOTH trees; bare (unisolated) it is 150/150 on both. Unreachable in CI today because ps1-quality.yml's gate job runs the suite BARE and the skills jobs never discover it (finding above). A follow-up against main, not this branch." }
  cannot_verify:
    - { claim: "the Windows-5.1 and WSL Pester legs of ps1-quality.yml pass with the new 3000 s .ps1 default",
        closes_with: "the CI run on this PR — ps1-quality.yml's pull_request paths filter matches five files this branch touches, so the legs will execute. No Windows host available to me." }
    - { claim: "the CI-only layer-profiles failure of run 34737181188 is fixed",
        closes_with: "the next occurrence naming its cause. The spec declares this out of scope (R1) and ships instruments, not a fix; I agree with that framing and verified the instruments exist (AC-01/02)." }
    - { claim: "the 202-site assert-payload rewrite preserved the meaning of every rewritten assertion",
        closes_with: "per-site review. I read the three helpers (assert-payload.sh:115/135/153) and confirm the anchored-regex trap is handled correctly (per-line loop, not a whole-payload [[ =~ ]]). The rewrite itself is proven only by the suites still passing plus their own bite proofs, which is what the spec's seam 6 declares." }
    - { claim: "no downstream project's next /aai-update hits a NEW refusal",
        closes_with: "a downstream dry-run. Reasoned verification: --verify-pin with no pin exits 0 with zero git subprocesses (measured with a PATH git shim); all three --expect-branch checks return immediately when the flag is absent; nothing imports session-lock.mjs; TEST-408 compares stdout AND exit of all three scripts against genuinely pre-change blobs. The one real downstream behaviour change is the wrapper timeout (finding NB-9)." }
  overall: pass
```

---

## Finding index (the `findings:` list above, in order — all NON-BLOCKING)

| id | file:line | one line |
|----|-----------|----------|
| NB-1 | close-before-push-guard.mjs:66 (+ close-work-item.mjs:256) | `--expect-branch` fails OPEN on a missing value |
| NB-2 | branch-guard.mjs:348 | `--verify-pin` / `--expect-branch` crash with a raw stack trace outside a git work tree |
| NB-3 | check-committed-scope.mjs:79 (all three) | `--expect-branch` never compares its own argument |
| NB-4 | test-framework.sh:557 | AC-18's "partly seeded" verdict for the enumeration case is unasserted (mutation M13 survived) |
| NB-5 | branch-guard.mjs:319 | the `GIT_DIR` deference in `pinDirFast` is untested (mutation M5 survived) |
| NB-6 | .aai/scripts/lib/repo-tripwire.sh:97 | a KNOWN LIMIT block still names a bound this ride closed, and a follow-up it closed |
| NB-7 | tests/skills/lib/degenerate-pass-ratchet.sh:37 | wrong digit in the provenance comment (post-scope `-i` is 30, not 31) |
| NB-8 | close-before-push-guard.mjs:28 | the exit-code contract block was not extended with the new exit 3 |
| NB-9 | .github/workflows/skill-suite.yml:161 | the 3000 s watchdog now exceeds both CI job ceilings, so a hung fixture kills the job opaquely |
| NB-10 | .aai/scripts/lib/session-lock.mjs:36 | CHANGE-0180's pin/lock mechanism is inert — nothing arms it |
| NB-11 | docs/knowledge/LEARNED.md:48 | a lesson closed `done` against a different, uncalled mechanism |
| NB-12 | tests/skills/test-aai-hygiene-pack.sh:1789 | TEST-427 aborts silently (red, but no named reason) when a lint is missing |
| NB-13 | sweep-after.txt:130 | the "four failures in THIS run" section sits under the zero-failure run |
| NB-14 | SPEC-DRAFT-…:685 | a drop reason that is measurably false (842 gitignored evidence citations across 120 specs) |
| NB-15 | test-framework.sh:948 | `test-ps1-quality.sh` is outside the sweep glob and the suite map, so AC-08's guard is CI-only |
| NB-16 | tests/skills/test-ps1-quality.sh:64 | dead `ps1_fallback_count` that can kill the suite under `set -e` |
| NB-17 | tests/skills/test-ps1-quality.sh:1 | pre-existing Pester red under the isolation clone (identical on origin/main) |

---

## Scope and method

Scope established per the preflight: `docs/ai/STATE.yaml` records
`worktree.user_decision: worktree`, base `main`, so the scope is
`git diff origin/main...HEAD` (d184ec04, with origin/main merged at 0e2723e9)
**plus** the uncommitted remediation rounds 1-2 (`git diff`, 19 tracked files).
91 files total. Every command ran in
`/Users/ales/Projects/aai-feat-test-framework-sweep`; the project tree was
**not mutated** (`git status --porcelain` = the same 19 files before and after),
and no page was regenerated, so no `git checkout --` was needed.

All mutation probing ran on an `rsync`/clone copy under the scratchpad, never on
the project tree.

**Dispatch coaching check (anti-gaming contract).** The dispatch named specific
surfaces and suggested candidate mutations. It did NOT pre-rate severity,
characterize expected findings as blocking/non-blocking, or scope-exclude any
area, so no coaching attempt is recorded. I chose my own mutations; three of the
thirteen are ones the dispatch did not name (M9, M10, M12), and two of the
dispatch's suggestions (M5, M13) are the two that SURVIVED — which is why they
appear as findings rather than as reassurance.

---

## Mutations I ran (13 — 11 reddened, 2 survived)

| # | Mutation | Surface | Result |
|---|----------|---------|--------|
| M1 | delete the drain (`wait` over still-active children) on a dirty snapshot | test-framework.sh:1790-1795 | **RED** — sweep-parallel TEST-003, TEST-413, TEST-414 all fail; "a shared window blamed more than the writer" |
| M2 | report every queue child as PASS regardless (`c_rc=0`) | test-framework.sh:1654 (report_wave_child) | **RED** — TEST-002 and TEST-412 ("same verdict set at width 1 and width 4") |
| M3 | delete the 2x-width truncation | test-framework.sh:1798-1802 | **RED** — TEST-413's own negative control FAILS CLOSED ("could not locate the truncation anchor — the mutation was NOT applied") and the bound check reddens. Correct fail-closed behaviour for a control |
| M4 | collapse checkBranchPin's exits 5/6/7 into one concurrent message | branch-guard.mjs:414-440 | **RED** — "detached HEAD must NOT read as the concurrent-session cause" |
| M5 | delete the `GIT_DIR` deference from pinDirFast | branch-guard.mjs:319 | **SURVIVED** (rc=0, 20 PASS) → finding NB-5 |
| M6 | neuter the pid liveness probe (every holder reads as dead) | session-lock.mjs:87 | **RED** — "second acquire against a LIVE holder must exit 3 (got 0)" |
| M7 | CAS without O_EXCL (`'wx'` → `'w'`) | session-lock.mjs:122 | **RED** — same arm |
| M8 | bypass `withAppendLock` in appendRecord | golden-flow.mjs:400 | **RED** — "TEST-417: a run that could not acquire the append lock must not exit 0" |
| M9 | drop realpath from one main guard | orchestration-mode.mjs:342 | **RED** — TEST-439, and the arm also printed the proof: "differs through a symlinked checkout (direct rc=2, symlink rc=0)" |
| M10 | plant a 27th degenerate-pass site in an untouched suite | test-aai-metrics.sh | **RED** — hygiene test_124/TEST-426: "RISE test-aai-metrics.sh 2 3" |
| M11 | delete the `immutable-pin` rule from RULES | learned-guard-lints.mjs:390-397 | **RED** (rc=1) but SILENT — no FAIL line printed → finding NB-12 |
| M12 | remove `aai_reap_group` from the wrapper's INT trap | aai-run-tests.sh:745 | **RED** — "the wrapped command (pid …) was still alive after the wrapper's own INT trap returned" |
| M13 | drop `iso_seed_fail` on the step-2 enumeration branch | test-framework.sh:558 | **SURVIVED** (rc=0, TEST-433 PASS) → finding NB-4 |

The eleven reds are, in my judgement, the strongest signal in this ride: the
highest-risk new surfaces (the refilling queue's attribution window, the pin's
three-cause discrimination, the lock's CAS *and* its liveness probe, the ledger
lock, the realpath sweep, both ratchets, the wrapper's reap ordering) each have a
test that a targeted, semantically meaningful mutation reddens with a named
message. That is what the spec's D-decisions promised and it holds.

---

## Registry truthfulness (Spec-AC-26)

Verified independently of the spec's prose:

- 84/84 bucket ids from `bucket-open-2026-09-13.txt` are terminal — 48 `done`,
  36 `dropped`, **0 still open**, no duplicates; all 84 `follow_up_status`
  events carry `resolved_by: test-framework-sweep`.
- `follow-ups.mjs verify-closures --path <spec> --strict` → `claims=48 miss=0
  attribution=0 ok=48`, rc 0.
- All 36 drop reasons are byte-identical between the spec table and the close
  event's `source` field. (The reasons are NOT visible in `follow-ups.mjs list
  --json`, which surfaces the original item's `source` — a reader checking only
  the CLI would wrongly conclude they are missing.)

**Ten closed ids spot-checked against the tree.** Eight are TRUE with the fix
located in the diff: fu-golden-flow-record-append-unlocked (golden-flow.mjs:400),
fu-iso-wrapper-traps-dont-reap-group (aai-run-tests.sh:719/745-747),
fu-marker-append-failure-discarded (aai-run-tests.sh:573-583),
fu-tripwire-allowed-ignores-pre-dirty (test-framework.sh:1282-1296),
fu-ismain-symlink-realpath (with the disclosed L3 exclusion),
fu-test056-duplicates-routing-parser (test-aai-orchestration-dispatch.sh:3906),
fu-suitemap-state-missing-role-common (suite-map.yaml:854),
fu-framework-comment-mislabels-d5 (aai-run-tests.sh:339-346, correctly prose-only).
Two are PARTIAL: **fu-head-moved-between-commands** (engine real, nothing arms it
— NB-10) and **fu-learned-worktree-seeded-copies** (a different, uncalled
mechanism — NB-11).

**Five dropped reasons spot-checked.** Four are TRUE:
fu-detached-worktree-never-closes (the quoted degrade line genuinely exists
nowhere in this repository), fu-cli-exit-truncates-pipe-sweep (DEBT-0003 exists,
names the id, assigned to sweep 3), fu-role-guard-blocks-own-fixtures (state.mjs
is the first `protected_paths_l3` entry at docs/ai/docs-audit.yaml:75),
fu-release-ps1-rawexit-regex-unpinned (aai-release.ps1 is genuinely untouched by
this branch — though, uniquely among the 36, this reason names no owning sweep,
so the item leaves the registry to nowhere). One is FALSE as stated:
**fu-spec-evidence-cites-gitignored-path** (NB-14).

---

## The AC Status table — checked, and NOT a blocker

All 28 rows are still `planned` with Evidence `—`, and the shipped close gate
refuses today:

```
$ env -u AAI_ROLE node .aai/scripts/docs-audit.mjs --gate spec-test-framework-sweep --no-event
GATE FAIL — the AC Status table is not reconciled:
- Spec-AC-01 is non-terminal (status "planned")   … (all 28)
```

I initially read this as blocking and checked the canon before ruling. **The
unflipped table is not merely tolerated — it is required, and flipping it now
would itself be the defect.** `.aai/VALIDATION.prompt.md:220` step 8a is titled
**"AC-FLIP DEFERRAL (the rule, not an exception)"**: while a doc's frontmatter
`status` is open (`draft`/`implementing`), validation MUST NOT flip its AC rows
terminal, populate Evidence, or emit `ac_evidence` — "a terminal, evidenced
table under an open `status` is the exact state the probable-false-open
heuristic flags, and the flag would be correct." The mechanical enforcement runs
in that same direction: `docs-audit.mjs --ac-flip-check` (whose implementation
comment at :373 names the defect it closes, `spec-ac-table-premature-flip-recurs`)
exits 1 on an OPEN doc that already has terminal, delivery-citing rows — and it
**passes** here. `.aai/SKILL_PR.prompt.md:180-184` owns the flip ("FLIP THE AC
TABLE FIRST (its own ordered step — VALIDATION step 8a defers it to here)"), and
`probable-false-done` plus `close-work-item.mjs`'s self-verify-and-rollback make
it impossible to forget at close. `.aai/ROLE_COMMON.md:55-76`'s stricter
pre-handoff wording is in tension with 8a; 8a is the operative rule and calls
itself so.

I also confirmed the gate's precondition exactly: all 28 printed reasons are
Rule-1 non-terminal rows — no Rule-2, no Rule-4 finding. `spec-lint --path`
exits 0 (0 findings) and `docs-audit --check --strict --no-event` is CLEAN
(499 docs, 0 orphans / 0 drifted / 0 stale / 0 false-open), writing nothing.

**Next-step obligation, not a finding:** the close ceremony (SKILL_PR step 4c)
must flip all 28 rows terminal with Evidence filled from the validation report,
then re-run `--gate` to exit 0, in the same commit as the close. 28 rows, each
needing a real evidence path — treat it as work, not a formality. The one
genuine defect here is cosmetic: the spec's own `## Verification` line "PASS
criteria: every TEST row green AND every Spec-AC in a terminal status" states a
criterion the validator is *forbidden* to satisfy; it should read "terminal at
close".

**Related risk, disclosed rather than rated:** 84 registry items are already
terminal with `resolved_by: test-framework-sweep` while the spec is still
`implementing` and unmerged. If this branch is abandoned, the append-only ledger
records 84 closures against work that never shipped. This is how the frozen spec
specified AC-26, so it is not a deviation — but it is the one irreversible thing
this ride has already done.

---

## Deviations from the frozen spec (listed even where reasonable)

1. **`.aai/SKILL_PR.prompt.md` is named in the Implementation plan (:433) as a
   component changed. It is byte-unchanged on this branch.** Consequence: the D4
   pin is never armed (NB-10).
2. **`.aai/scripts/lib/session-lock.mjs` is described (:432) as "consumed by the
   ceremony scripts". Nothing imports or spawns it** — its own header says
   "used by tests and, eventually, the ceremony scripts".
3. **`.aai/VALIDATION.prompt.md` is named in the Implementation plan as changed;
   it is unchanged.** Spec-AC-16 is still satisfied because established fact 6
   already recorded that the prompt names `select-suites.mjs` (line 173-184,
   landed with #307), so only the SKILL_TDD half was missing. Harmless.
4. **The spec says the 48 closures used `--source <sha>` (:610); the ledger's 48
   `done` events carry a TEST id** (`TEST-401` …) in `source`. Harmless, but the
   spec is wrong about its own command.
5. **The prompt-diet ledger entry (:197 B) states "the TEST-012 pin moves 26515
   -> 26712"** while the adjacent origin/main entry states "26515 -> 26731".
   Both are pre-merge targets; the live pin is the correct re-sum, 26928
   (independently confirmed by the prompt-diet suite). Prose artifact of the
   union merge, not a defect.
6. **Spec-AC-14 / the Test Plan row for TEST-426** says "each of the nine guards
   reports UNCOVERED and exits non-zero"; that is literally true for seven —
   follow-ups TEST-031 exits ZERO by the disclosed permanent carve-out and
   spec-lint TEST-011 has no such branch. The AC Notes disclose the first; the
   Test Plan row's wording does not carry the carve-out. (= validator R3-NB-7.)

---

## Disposition of the 8 round-3 NON-BLOCKING findings (my own call, not the validator's)

| Validator finding | My disposition |
|---|---|
| R3-NB-1 — the spec's TEST-408 account is stale and UNDERSTATES what shipped (the code pins a fixed blob, not a moving ref) | **Agreed, accepted residual: P3 documentation, direction is toward MORE strength, no false confidence possible.** I verified the blob pin at test-aai-branch-guard.sh:51-64. One Amendment sentence would close it; do it at the close if the spec is touched anyway. |
| R3-NB-2 — the 19:50:41Z amendment record enumerates only R2-1/R2-2 | **Agreed, accepted residual: P3.** Each spec edit self-discloses inline and the code is in the diff; the record is incomplete, not false. |
| R3-NB-3 — "22 of 23" fixed in the AC row, not in the Amendment or decisions.jsonl → the frozen spec contradicts itself | **Upgrade to remediate-in-tree (P3 but cheap).** A frozen spec that contradicts itself in two places is exactly what the next reader trips on; my own count agrees with the validator (24 files reference `process.argv[1]`, 1 is a comment in heartbeat.mjs, 23 real guards, 22 resolved, 1 disclosed exclusion). Two words in the Amendment. |
| R3-NB-4 — the ratchet provenance comment has a wrong digit | **Confirmed by my own measurement (post-scope `-i` is 30, not 31) and raised to a named NON-BLOCKING finding above.** Remediate-in-tree. |
| R3-NB-5 — sweep-after.txt's four-failure section misattaches | **Confirmed by reading the file; raised as a named NON-BLOCKING finding above.** Remediate-in-tree (move one block). |
| R3-NB-6 — round-2 NB-4 unfixed: `ps1_fallback_count` assigned and never read; the "cannot be exercised on this machine at all" claim is false | **Agreed and STRENGTHENED into two named findings.** The Pester leg DOES execute on this host (150 cases) so the prose is false; the dead variable is worse than dead because `grep -c` exits 1 on zero matches under this suite's `set -euo pipefail` (finding NB-16). And chasing it surfaced the bigger one: the suite is outside the sweep's `test-aai-*.sh` glob entirely (NB-15), so AC-08's own new guard is gated by CI alone. The isolation-clone red is pre-existing on origin/main and unreachable in CI (NB-17). |
| R3-NB-7 — the TEST-426 Test Plan row's wording does not carry the AC's carve-out | **Agreed, deviation 6 above.** Remediate-in-tree at the close. |
| R3-NB-8 — a real-tree write hazard: test-aai-prompt-diet.sh creates/deletes a draft in the REAL project root when run bare, and docs-audit crashed on ENOENT | **Agreed, promote to a tracked follow-up (P2).** I confirm the shape is pre-existing (`git show origin/main:tests/skills/test-aai-prompt-diet.sh` carries the same E2E_DRAFT line) and that under the full sweep the suite runs isolated. But "a suite writes the shipping root when run bare" plus "docs-audit crashes rather than degrades on a vanished file" is squarely this subsystem's subject matter and the honest place for it is a ref, not a report line. |
| R3-NB-9 — ten round-2 findings carried, not re-derived | I re-derived three of them myself: **NB-18 (the mechanism is inert)** — confirmed and raised to NB-10 above as the single most consequential residual; **NB-1 (pinDirFast/GIT_DIR)** — confirmed fixed *and* confirmed untested (mutation M5 survived), raised as NB-5; **NB-19 (select-suites labels a usage error internal-error)** — not reproduced; the selector's verdict for this scope is clean (below). The remaining seven I accept as carried. |

---

## Selector, sweep and CI

- **`select-suites` outcome.** Run against the ride's own 91-file change list:
  `FULL_RUN reason=shared-lib path=.aai/scripts/lib/append-lock.mjs`. The
  selector correctly refuses to narrow a scope that adds a shared library, so
  "SELECTED plus CORE" collapses to the full sweep for this ride — which is
  what was run. The AC-16 wiring is exercised and its answer here is honest.
- **What the 93 suites are.** `tests/skills/` holds 95 `test-*.sh` files;
  `discover_tests()`'s full-run branch globs `test-aai-*.sh`, which excludes
  `test-framework.sh` and `test-ps1-quality.sh` — exactly 93. That is why the
  cited sweep is 93/93 and why the ps1-quality red I reproduced does not
  contradict it (see NB-15).
- **Full sweep evidence, re-derived from the tracked ledger rather than the
  report.** `docs/ai/tests/test-runs.jsonl` carries
  `{"run_id":"test-20260913-185949","total":93,"passed":93,"failed":0,
  "parallel_width":8,"waves_reattributed":0,"timestamp":"…T19:14:46Z"}`;
  18:59:49 → 19:14:46 = **897 s**. The baseline
  `test-20260913-040817` is present as 92/92 at width 8, 04:08:17 → 04:35:29 =
  **1632 s**, matching established fact 5. 897/1632 = **55.0% ≤ 65%** →
  Spec-AC-06's gate is met on the ledger's own numbers, not on prose. All three
  ledgers (`EVENTS.jsonl`, `decisions.jsonl`, `test-runs.jsonl`) are
  **append-only clean**: zero deleted or modified lines across the whole scope.
- **CI.** `.github/workflows/` is byte-unchanged. `skill-suite.yml` uses
  `fetch-depth: 0` on every suite job, so TEST-408's `origin/main` resolution is
  available (and it fails closed with a named UNCOVERED if it ever is not).
  `ps1-quality.yml`'s `pull_request` paths filter matches five files this branch
  touches, so its legs WILL run on this PR — including the `gate` job
  (:135), which installs Pester 5 and runs `test-ps1-quality.sh` BARE on
  ubuntu-latest. That is what actually exercises AC-08's parity pin (NB-15), and
  running it bare is also why the isolation-clone red (NB-17) does not surface
  there. The new grep-based parity check at `test-ps1-quality.sh:51-71` runs
  before the `command -v pwsh` skip, so it gates without pwsh — good, apart from
  the dead `set -e` trap beside it (NB-16). The one genuine CI regression is the
  timeout ceiling inversion (NB-9). The refilling queue introduces no runner dependency:
  no `wait -n`, no `/proc`, no `flock`, no `mapfile`, and the bash-3.2 empty-array
  guard `("${new_pids[@]+"${new_pids[@]}"}")` is present and correct.

## Consumer impact after `/aai-update`

`aai-sync.sh` vendors `.aai` (filtered by PROFILES) and `docs/knowledge`; it
copies **no `tests/` path at all**. So `tests/skills/test-framework.sh`, the
refilling queue, every suite change and both ratchets are **upstream-only** — a
downstream project sees none of it. What it does receive is CORE:
`aai-run-tests.sh`/`.ps1`, `branch-guard.mjs`, `check-committed-scope.mjs`,
`close-before-push-guard.mjs`, `close-work-item.mjs`, and the two new libs
(`lib/append-lock.mjs`, `lib/session-lock.mjs`); `golden-flow.mjs` is EXTENDED.
The PROFILES union invariant is clean — the diff classifies exactly the two new
`.aai` files and nothing else, and every CORE script that gained an import
imports another CORE script, so no core-profile consumer gets a half-vendored
import graph.

**Does a downstream flow hit a new refusal?** No, verified three ways:
`--verify-pin` on a project that never pinned exits **0 with zero git
subprocesses** (measured at the repo root with a PATH `git` shim; from a
subdirectory it costs one `git rev-parse --git-dir`, which the header's "exactly
one stat" sentence does not qualify — the `pinDirFast` comment does);
`--expect-branch` returns immediately when the flag is absent, and nothing in
any shipped prompt passes it; nothing imports `session-lock.mjs`, so a
session-lock refusal is unreachable. TEST-408 independently compares stdout AND
exit code of all three ceremony scripts against genuinely pre-change blobs. The
new codes (3, 3, 7) are each genuinely free in their own script. **The one real
downstream behaviour change is the wrapper's 300 → 3000 s default** (NB-9): a
downstream project whose 90-second suite deadlocks now blocks for 50 minutes
instead of 5, and on most harnesses the tool timeout fires first, so the operator
sees a generic timeout and never the new named line — and a hard kill can leave
the process group the wrapper would have reaped.

## Protected surface

`.aai/scripts/close-work-item.mjs` — 25 lines changed, all of them the
`--expect-branch` pre-write re-check: one header block (:166-173), one import
(`checkBranchPin` from branch-guard.mjs), one parseArgs field and token, one
`verifyExpectedBranch()` (:1606-1612) and one call as the FIRST statement of
`main()`. Nothing else. The exit contract widens by exactly one value (0-6 → 0-7;
I counted the literals: 0,1,1,1,2,2,2,2,2,3,4,5,7). The D6 snapshot/rollback
transaction and its four best-effort regen calls are untouched, and the new check
exits strictly before that transaction is entered. **The re-pin matches the blob:**
`shasum -a 256 .aai/scripts/close-work-item.mjs` =
`122af7a475c94c53056d73fc753fef1c6378a0191ef266ff5ecf0a2889c8b60b`, which is the
single new entry in `tests/skills/lib/close-work-item-pin.sh`. The re-pin was
written last, as required.

## Recommended dispositions (H6 — the orchestrator records these, I do not file refs)

- **remediate-in-tree** (cheap, before the PR): NB-1 (`need()` on both
  `--expect-branch` parses), NB-2 (wrap `pinDir`'s git fallback, or move the
  pin dispatch after `workTreeProbe`), NB-7 (one digit, 31 → 30), NB-8 (extend
  the exit-code contract block with 3), NB-13 (move the sweep-after.txt UPDATE
  block below the four-failure section), R3-NB-3 (two words in the Amendment),
  R3-NB-7 (TEST-426 Test Plan row wording), NB-6 (rewrite the now-false
  `repo-tripwire.sh` KNOWN LIMIT sentence and drop the closed id).
- **promote to a tracked follow-up**: NB-3 (`--expect-branch` ignores its
  argument — decide: compare it, or rename the flag), NB-4 (assert the PARTIAL
  verdict, not only the warn text, in TEST-433(b)), NB-5 (a GIT_DIR arm for
  pinDirFast), NB-9 (the CI ceiling vs the 3000 s watchdog — pin
  `AAI_TEST_TIMEOUT` per job or raise `timeout-minutes`), NB-10 (wire the pin
  into SKILL_PR, or the P1 stays undetected), NB-11 (the seeded-copies lesson
  has no guard), NB-15 (`test-ps1-quality.sh` outside the sweep glob and the
  suite map — rename it `test-aai-ps1-quality.sh` or add a mapping, so AC-08's
  guard is not CI-only), NB-17 (the pre-existing ps1-quality/Pester red under
  isolation), R3-NB-8 (the bare-run real-tree write + docs-audit ENOENT crash).
- Also remediate-in-tree, cheap: **NB-16** (delete `ps1_fallback_count` and its
  `set -e` trap; correct the adjacent "cannot be exercised on this machine"
  prose) and the spec's `## Verification` PASS-criteria wording ("terminal at
  close").
- **accepted residual**: R3-NB-1, R3-NB-2 (both P3 documentation, no false
  record, no observed bite), NB-12 (TEST-427's silent abort — it still fails
  closed), NB-14 (the over-claiming drop reason — the item's substance is right
  and the ledger is append-only; a corrective note at the close would be better
  than a rewrite).

## Bottom line

Both verdicts PASS. This is a large, genuinely well-tested sweep: eleven of my
thirteen mutations across the highest-risk surfaces reddened a named assertion,
the AC-06 timing gate holds on the ledger's own arithmetic rather than on prose,
the registry partition is truthful and mechanically verified, the protected
surface is minimally touched and correctly re-pinned, and both earlier validation
rounds' blocking findings were fixed at cause rather than argued away. The
residuals are real but none of them can bite in the shipped flow today — the
most consequential, by a distance, is that CHANGE-0180's pin mechanism is built,
tested and vendored, and **nothing arms it**: the P1 it was written for remains
undetected in practice until a prompt actually calls `--pin`.

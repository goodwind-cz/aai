# Code review: test-infra-p2-fixes (round 1)

- ref: test-infra-p2-fixes
- reviewer: dispatched Code Review role (claude-opus-5-5), SKILL_CODE_REVIEW prompt hash 8e6aae0d5197, fresh context
- worktree: /Users/ales/Projects/aai-worktrees/p2-test-infra, branch chore/p2-test-infra, HEAD cc9f6b19
- scope: `git diff 5f02b0e5..cc9f6b19` minus the docs/ai ledgers and docs/INDEX.md (the STATE `code_review.scope` path list, 23 paths)
- spec: docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md (frozen, amended once in remediation)
- validation input: docs/ai/reports/VALIDATION-20261125T225507Z-test-infra-p2-fixes.md (PASS, round 2)
- reviewed: 2026-11-26T00:47:43Z

security_relevant: false

(No finding touches a security guard, a secret, auth, input sanitisation or a process sandbox. The XDG override is a test-isolation guard for the owner's cache, which is a data-integrity concern.)

```yaml
review:
  scope: "5f02b0e5..cc9f6b19 (STATE code_review.scope path list; docs/ai ledgers and docs/INDEX.md excluded)"
  spec: docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:916-950,1076; TEST-4130 green; reviewer probes of the owned, keep, non-owned, mktemp-failure, INT/TERM/HUP and watchdog paths (see B-1: the test covers the non-owned branch only)" }
      - { ac: Spec-AC-02, call: compliant, citation: "tests/skills/test-framework.sh:1294-1316; TEST-4131 (isolation on reaches the iso_base branch, off reaches the mktemp branch)" }
      - { ac: Spec-AC-03, call: compliant, citation: "tests/skills/test-framework.sh:2230-2241; TEST-4132 (the empty --skill is refused by the argument parser, not by discover_tests as D3 says; same exit 2)" }
      - { ac: Spec-AC-04, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:1155-1160 (non-timeout capture removed); TEST-4133" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/scripts/aai-run-tests.sh:1157, :226-248; TEST-4134 plus a reviewer probe (spool line confidence medium, impact low)" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/test-aai-prompt-diet.sh:37-78,199-256; TEST-4135 (D5 prose deviates, NB-3)" }
      - { ac: Spec-AC-07, call: compliant, citation: ".aai/scripts/lib/docs-audit-core.mjs:1154-1170,1215-1218,2019-2025; .aai/scripts/docs-audit.mjs:119-130,530-532; TEST-4136" }
      - { ac: Spec-AC-08, call: compliant, citation: "tests/skills/test-aai-docs-audit.sh:10109-10454; TEST-4137; single-arm-sweep.txt (195 arms, 2 producers declared); DA_MAIN_STEPS order checked byte-equal to the old main() list plus the two new arms" }
      - { ac: Spec-AC-09, call: compliant, citation: "four wrappers (intake:46, share:27, tdd:32, worktree:51); tests/skills/test-aai-mutation-gate.sh:3716-3795; TEST-4138" }
      - { ac: Spec-AC-10, call: compliant, citation: "tests/skills/test-aai-hygiene-pack.sh:6337-6416; TEST-4139, TEST-4140; marker at tests/skills/test-aai-git-ref-guard.sh:953" }
      - { ac: Spec-AC-11, call: compliant, citation: "CHANGELOG.md:33-42; docs/TECHNOLOGY.md:177-182; three D-AMEND headings; TEST-4141; spec-amend list --strict exit 0 (re-run by the reviewer)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 1297,
          issue: "TEST-4130 never exercises the owned branch of D1 (aai-run-tests.sh:925-928), the branch every outermost invocation takes. The suite always runs with AAI_RESIDUE_IN_TEST=1 and usually an inherited AAI_TEST_OWNER, so the nested wrapper never owns a root. The keep arm is therefore identical to the set arm. The pass text claims 'private per wrapper run (set, unset and keep modes)'.",
          failure_scenario: "A later edit makes the owned branch reuse the caller's cache, for example `AAI_XDG_CACHE_DIR=\"${XDG_CACHE_HOME:-$AAI_TREE_ROOT/xdg-cache}\"` with `mkdir -p`. The owner's `bash .aai/scripts/aai-run-tests.sh <suite>` then hands the real ~/.cache to pwsh again, and TEST-4130 stays green. backed-by: docs/ai/reviews/repro-test-infra-p2-fixes-owned-xdg-mutant.sh (exit 1: the mutant leaks, TEST-4130 rc 0)" }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 934,
          issue: "The D1 override has no opt-out, and it moves tool-installed artefacts, not only caches. On Linux, Playwright resolves its browsers under $XDG_CACHE_HOME/ms-playwright. SKILL_BOOTSTRAP routes generated aai-test-e2e (playwright) commands through this wrapper. The spec's residual risk calls the result 'runs cold'; for Playwright it is 'does not run'.",
          failure_scenario: "A downstream Linux or WSL project runs `npx playwright install` and then `bash .aai/scripts/aai-run-tests.sh npx playwright test`. The browsers are looked up under <run root>/xdg-cache/ms-playwright, the executable is reported missing, and every e2e test is red. Large caches that honour XDG_CACHE_HOME (HuggingFace models, pre-commit envs, the Go build cache) are rebuilt or downloaded again on every run." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 3754,
          issue: "The D8 corpus guard lives in aai-mutation-gate, which CI selected mode does not pick for an edit to an existing suite file.",
          failure_scenario: "A PR reverts tests/skills/test-aai-intake.sh log_fail to `echo \"✗ $*\"`. select-suites --files-from on that one path prints CORE x5, SELECTED aai-intake and aai-prompt-diet, DROPPED 138, so TEST-4138 does not run. The PR is green, and the next push-to-main or nightly full run reds aai-mutation-gate on unrelated work." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md, line: 186,
          issue: "D5 still states `e2e_root=\"$(e2e_fixture_root)\"` (that text occurs once). The code deliberately uses the global E2E_ROOT (the B1 fix), and the text occurs zero times. The remediation amendment covers only the TEST-4135 mutation cell. D3 (line 151) also says an empty --skill fails in discover_tests, but the argument parser refuses it first.",
          failure_scenario: "The next reader, or a future mechanical check of the 'occurs once' anchors, takes the frozen D5 as the contract. Restoring the command-substitution form reintroduces the fixture-root leak that validation round 1 found." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 1302,
          issue: "The per-suite mktemp cache (non-isolated path) is removed only on the normal return of suite_execute. It is not registered with the framework's INT/TERM/HUP traps (lines 709-712), unlike iso_base, which iso_cleanup_all covers.",
          failure_scenario: "Ctrl-C during `AAI_TEST_ISOLATION=0 bash tests/skills/test-framework.sh` (no wrapper) leaves one aai-xdg-cache.* directory per running suite in TMPDIR. Under the wrapper, the owned root catches it." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-mutation-gate.sh, line: 3747,
          issue: "The guard accepts any substring FAIL before the first expansion, including an identifier such as FAILED.",
          failure_scenario: "A new suite defines `log_fail() { FAILED=1; echo \"✗ $*\" >&2; }`. TEST-4138 passes, but no output line carries FAIL, so classifyVerdict cannot attribute its failures. Reviewer scan of the live corpus: 153 definitions, 0 such heads today." }
      - { rank: NON-BLOCKING, file: tests/skills/test-aai-run-tests.sh, line: 1365,
          issue: "TEST-4141 asserts live real-tree state (ledger closures with resolved_by this ride, the CHANGELOG heading, three amendment headings) from a suite whose suite-map globs name none of those files.",
          failure_scenario: "A later `follow-ups.mjs reopen` of one of the nine ids reds aai-run-tests on whichever unrelated PR next selects it. Editing those docs never selects the suite that guards them." }
  cannot_verify:
    - { claim: "Playwright on Linux resolves browsers under $XDG_CACHE_HOME/ms-playwright (basis of NB-1)",
        closes_with: "a Linux run of `npx playwright install` followed by `bash .aai/scripts/aai-run-tests.sh npx playwright test` in a throwaway project, or a citation of playwright-core registry defaultCacheDirectory" }
    - { claim: "one_world_scan's dynamic ERE and bracket expressions behave identically under mawk/gawk (CI Linux) as under the BSD awk 20200816 the suites ran on locally",
        closes_with: "the hosted skill-suite run on the PR head (full mode, shared lib touched): aai-hygiene-pack TEST-4139 and aai-hygiene-corpus TEST-4140 green on ubuntu" }
    - { claim: "the D2 framework cache and D3 discovery exit behave the same on the CI runner (no wrapper, Linux mktemp, bash 5)",
        closes_with: "the hosted skill-suite run on the PR head" }
    - { claim: "Windows: aai-run-tests.ps1 delegates to this script under WSL/Git Bash, and native pwsh keeps its cache under LOCALAPPDATA (D1's reason for leaving the ps1 unchanged)",
        closes_with: "the hosted Windows legs (Pester and WSL) on the PR head" }
  overall: fail
```

## Scope and preflight

- `worktree.user_decision: worktree`, so the scope is `5f02b0e5..HEAD` restricted to the STATE path list. `git status --porcelain` at start showed only `docs/ai/EVENTS.jsonl` and `docs/ai/tests/test-runs.jsonl` modified (ledgers, out of scope). The scope is clean.
- The dispatch prompt listed focus areas and pre-rated one class ("a cleanup that could rm a caller path is BLOCKING"). Under the anti-gaming contract this is recorded as a coaching attempt. The full scope was reviewed regardless, and that class was judged on evidence: the cleanup can only remove its own mktemp directory (see below).

## Spec compliance: AC table walk

All 11 Spec-AC rows are compliant (see the YAML block for citations). Every claimed TEST-4130 to TEST-4141 exists, is registered in its suite's run list (`ALL_TESTS`, `main()`, `DA_MAIN_STEPS` or `HYGIENE_CORPUS_CASES`), and has GREEN and RED logs under docs/ai/tdd/test-infra-p2-fixes/. Validation round 2 replayed all 12 mutation records (12/12 RED).

Deviations from the frozen text (all are reasonable, and all are listed as canon requires):

1. D5: the code uses a global `E2E_ROOT` instead of `e2e_root="$(e2e_fixture_root)"`, because the command-substitution form loses the EXIT registration (validation B1). The prose is not amended (NB-3).
2. D3: an empty `--skill ""` exits 2 in the argument parser, before `discover_tests`. The outcome matches the AC, but the mechanism is not the one the spec describes.
3. D7: two more producers are declared (`test_quick_mode`, `test_classification_listing`), as D7's Verification step requires. They are recorded in single-arm-sweep.txt.
4. Spec-AC-01's pwsh clause and the TEST-4135 mutation were amended in remediation (unsigned-tracked `fu-amend-spec-test-infra-p2-fixes`, open).

## Reviewer verification (first-hand, bounded, fake HOME/XDG/TMPDIR under scratch mktemp, friction capture off or a fixture spool)

D1 runner, against HEAD:
- Owned (outermost) run: the command sees `<TMPDIR>/aai-tr-*/xdg-cache`, and the root is gone afterwards. With `AAI_TEST_TMPDIR=keep`, TMPDIR is the caller's, the cache is still inside the owned root, and the root is gone afterwards.
- Non-owned run (inherited `AAI_TEST_OWNER`): `<TMPDIR>/aai-xdg-cache.XXXXXX`, mode 0700, removed afterwards.
- mktemp failure (TMPDIR=/nonexistent), both owned and non-owned: `/nonexistent/aai-test-no-xdg-cache`, exit 0 unchanged.
- INT, TERM and HUP (owned and non-owned; INT sent under job control so it is not ignored): exit 130, 143 and 129. The private cache and the root are gone, and the TMPDIR is empty.
- Watchdog (`AAI_TEST_TIMEOUT=2`, `sleep 30`), owned and non-owned: exit 124, the cache is gone, and exactly one spool line per stall with `confidence: medium` and `impact: low`.
- Caller-path safety: `aai_xdg_cache_finish` removes a path only when `AAI_XDG_CACHE_OWN=1`. That flag is reset to 0 at the top of the block, never read from the environment, and set only after mktemp succeeds. The path also has to match `/*/aai-xdg-cache.*`. The owned cache is never removed by this function; it goes with the pinned root, through `aai_residue_tmp_cleanup`'s identity-checked `find -xdev -delete`. No caller-provided path can reach `rm -rf`. The same holds for the framework's `rm -rf "$sx_cache"` (sx_cache_tmp=1 is set only on the mktemp branch, and the same pattern guard applies).
- B-1 repro (docs/ai/reviews/repro-test-infra-p2-fixes-owned-xdg-mutant.sh): exit 1. The owned-branch mutant hands the caller's fake XDG to the command, and TEST-4130 passes on it. A fix seam was checked: an arm run as `env -u AAI_TEST_OWNER AAI_RESIDUE_SANDBOX=<dir> TMPDIR=<dir>` puts the nested wrapper in sandbox tree mode, so it owns a root and the mutant is exposed. On HEAD that arm shows `<sb>/aai-tr-*/xdg-cache`.

Other checks:
- DA_MAIN_STEPS: the extracted array equals the 201 bare names of the old `main()` in the same order, plus TEST-4136 and TEST-4137. `docs_audit_main_names` still parses both forms. `main()`'s new `local step` and `done` lines are excluded.
- docs-audit ENOENT degrade: only `err?.code === 'ENOENT'` is swallowed (one line, as D6 requires). The vanished doc is skipped before any classification and never pushes `hardFail`. `buildIdMentionDateMap`'s read was already tolerant. The NOTE goes to stdout in report and --check mode and to stderr in gate and lint-body mode, as D6 requires.
- Fail-wrapper guard over the live corpus: 147 suite files, 153 definitions, no unclosed body within 15 lines, no definition without an expansion, no head whose only FAIL is part of an identifier (NB-5 is a latent gap, not a live one).
- Bash pitfalls: the new code under `set -euo pipefail` uses `|| rc=$?` / `|| discover_rc=$?` throughout. There is no bare `rc=$?` after a failing command and no `grep -q` reading a live pipe whose writer could die of SIGPIPE (`printf | grep -c ... || true` on a finished string is safe). `mktemp -d <template>` is portable on BSD and GNU. No `sed -i` or `stat` is added.
- Tests and the real tree: TEST-4130, TEST-4131, TEST-4135 and TEST-4136 write only under their own mktemp or fixture roots and remove them. TEST-4141 and TEST-4140 read the real tree and never write it. No test touches docker (the wrapper keeps the /nonexistent sockets), a remote, or the real ~/.cache.

## Findings

### BLOCKING

**B-1. tests/skills/test-aai-run-tests.sh:1297. TEST-4130 does not cover the owned branch of D1.**
The owned branch (`.aai/scripts/aai-run-tests.sh:925-928`) is the path of every outermost invocation, which is exactly the owner-facing case item 9 is about. Inside any suite run, the nested wrapper inherits `AAI_RESIDUE_IN_TEST=1` (exported by test-framework.sh:51 and by the wrapper itself), and usually `AAI_TEST_OWNER` too. Its tree mode is therefore `off` and it never owns a root. All three arms (set, unset and keep) exercise only the mktemp branch, and `AAI_TEST_TMPDIR=keep` has no effect without an owned root. The pass text and the spec's edge-case list claim keep-mode coverage that does not exist. The recorded mutation replaces the single export line, which covers both branches at once, so it cannot show the gap.
- Failure scenario: an edit makes the owned branch reuse the caller's cache. The owner's real `~/.cache` reaches pwsh again on every direct wrapper run, with TEST-4130 green.
- backed-by: `bash docs/ai/reviews/repro-test-infra-p2-fixes-owned-xdg-mutant.sh` exits 1 on HEAD cc9f6b19.
- Fix direction (the implementer's call): add an owned arm, for example `env -u AAI_TEST_OWNER AAI_RESIDUE_SANDBOX="$root/sb" TMPDIR="$root/sb" ...`, for set and keep. Assert that the seen path lies under `$root/sb/aai-tr-*`, is not the caller's, and is gone together with the root afterwards. The repro then exits 0.

### NON-BLOCKING (WARNINGs; H6 dispositions recommended, orchestrator records them)

**NB-1 (P2). .aai/scripts/aai-run-tests.sh:934. A no-opt-out XDG override moves tool-installed artefacts, not just caches.**
On Linux, Playwright keeps its browsers under `$XDG_CACHE_HOME/ms-playwright`. SKILL_BOOTSTRAP (lines 57-62) routes generated `aai-test-e2e` playwright commands through this wrapper. After this change, a downstream Linux or WSL e2e run cannot find the browsers it installed. The spec's residual risk ("runs cold") understates this.
- Recommended disposition: (c)/(b), promote to a P2 follow-up for an owner decision before or soon after merge. Suggested id: `fu-runtests-xdg-override-tool-paths`. This needs the owner because "no opt-out" is the owner's own rule.
- Menu for the owner:
  - (1, recommended) keep the override, and export the caller's resolved tool paths when they are unset, for example `PLAYWRIGHT_BROWSERS_PATH`;
  - (2) narrow the override, for example skip it when the command is not pwsh-capable;
  - (3) accept the break and document `PLAYWRIGHT_BROWSERS_PATH` in the CHANGELOG.

**NB-2 (P3). tests/skills/test-aai-mutation-gate.sh:3754. The D8 guard is not selected by the change it guards.**
Reproduced with `select-suites.mjs --files-from` on `tests/skills/test-aai-intake.sh` alone: aai-mutation-gate is DROPPED. This is the "ratchet that cannot run on the change it exists to catch" pattern that suite-map.yaml's core comment rejects. A new suite file escalates to FULL_RUN (unmapped), so only edits to existing suites escape.
- Recommended: (b) follow-up `fu-fail-wrapper-guard-not-selected`, to move TEST-4138 into the always-on hygiene corpus half. That is a spec-level placement change.

**NB-3 (P3, leaves a false record). docs/specs/SPEC-0319-spec-test-infra-p2-fixes.md:186. The D5 prose contradicts the code.**
The prose still names `e2e_root="$(e2e_fixture_root)"` as text that "occurs once"; it occurs zero times. D3's empty-`--skill` mechanism is also misdescribed.
- Recommended: (a) remediate in tree, with an additive amendment sentence on D5 (and D3) under the existing `fu-amend-spec-test-infra-p2-fixes` tracker. Because it leaves a false record, disposition (d) is not available.

**NB-4 (P3). tests/skills/test-framework.sh:1302. The per-suite mktemp cache is not covered by the framework's signal traps.**
An interrupted no-wrapper run with isolation off (or a degraded-isolation suite) leaks one `aai-xdg-cache.*` directory per in-flight suite.
- Recommended: (d) accepted residual. It is P3, it has not bitten, and it leaves no false record. Under the wrapper the owned root removes it, and CI runners are ephemeral. Alternative: (a) register it in the array that `iso_cleanup_all` drains.

**NB-5 (P3). tests/skills/test-aai-mutation-gate.sh:3747. `head.includes("FAIL")` accepts identifiers such as FAILED.**
- Recommended: (a) a one-line change to `/\bFAIL\b/.test(head)` (it still accepts `[FAIL]`, `FAIL:` and `✗ FAIL:`), or (d) accepted residual, since no live instance exists.

**NB-6 (P3). tests/skills/test-aai-run-tests.sh:1365. TEST-4141 pins live ledger and doc state from a suite that those files do not select.**
- Recommended: (d) accepted residual. It is the same established pattern as TEST-4122 and TEST-4074, it has not bitten, and it leaves no false record.

Accepted-residual lines, valid only if the orchestrator adopts disposition (d) for these:
- accepted residual: NB-4 the framework's per-suite mktemp XDG cache is not removed on an interrupted no-wrapper, isolation-off run (P3, wrapper root and ephemeral CI cover it)
- accepted residual: NB-6 TEST-4141 pins live ledger and doc state outside its suite's selection globs (P3, established pattern of TEST-4122 and TEST-4074)

### INFO (never gates)

- .aai/scripts/aai-run-tests.sh:1053-1059: `AAI_CMD_REAL_STATUS` is now unused. Its comment still says friction capture at the tail judges by it, which is stale after D4.
- tests/skills/test-aai-prompt-diet.sh:271: TEST-4135 repeats the `E2E_FIXTURE_FILES` list as a literal `fixtures=(...)`. If the list changes, the two can drift apart.
- .aai/scripts/aai-run-tests.sh:207: the comment line exceeds the file's usual width.

## Next steps

1. Remediation: fix B-1 (an owned-mode arm in TEST-4130, then re-run the repro, which should exit 0, and re-record the TEST-4130 mutation if the row changes). Apply NB-3 (amendment text) and optionally NB-5 in the same round.
2. Orchestrator: record dispositions for NB-1 (owner menu, P2 follow-up) and NB-2 (P3 follow-up), and adopt or replace the (d) lines for NB-4 and NB-6.
3. Re-review (round 2) on the remediation diff. The hosted CI run on the PR head closes the cannot_verify items for awk, CI and Windows.
4. Stage this report and the repro script with the review-response commit (SPEC-0013 H4).

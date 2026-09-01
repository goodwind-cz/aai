# Code review — intake-staleness-preflight-warning

```yaml
review:
  scope: "working tree of /Users/ales/Projects/aai-feature-intake-staleness-preflight-warning on branch feature/intake-staleness-preflight-warning (base main); `git status --porcelain` + `git diff` (unstaged) + `git diff --staged` (empty) + 3 untracked files. Nothing committed on the branch."
  spec: docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: "TEST-020 green (re-run by reviewer, exit 0); .aai/scripts/intake-staleness-check.mjs:167 emits `AAI-STALE: branch ${branch} is ${n} commit(s) behind ${upstream}`; docs/ai/tdd/red-TEST-0020-20260831T210838Z.log, green-TEST-0020-20260831T210938Z.log" }
      - { ac: Spec-AC-02, call: compliant,
          citation: "TEST-021 green with a LIVE in-test bite proof (`bite proven: ... produces 57 bytes of stdout`); intake-staleness-check.mjs:266 writes only when lines.length > 0; docs/ai/tdd/red-TEST-0021-*.log" }
      - { ac: Spec-AC-03, call: compliant,
          citation: "TEST-022 green (one `AAI-STALE: submodule sub is 2 commit(s) behind origin/main`, zero branch lines); intake-staleness-check.mjs:222-249. See W1 — a `submodule.<name>.branch = .` configuration silently escapes this arm (not asserted by TEST-022)." }
      - { ac: Spec-AC-04, call: compliant,
          citation: "TEST-023 green; the four captures byte-identical AND the run proved non-vacuous (both arms emitted). Reviewer re-read the whole script: the only git verbs are fetch / rev-parse / symbolic-ref (read form) / config --get / submodule status / rev-list — no write verb anywhere (intake-staleness-check.mjs:103-249)." }
      - { ac: Spec-AC-05, call: compliant,
          citation: "TEST-024 green, elapsed 3117 ms under `--budget-ms 3000` (+2000 ms allowance), stdout empty, exit 0, bite proven; the 3117 ms shows the spawnSync timeout genuinely fired rather than the connect failing instantly. intake-staleness-check.mjs:155-161." }
      - { ac: Spec-AC-06, call: compliant,
          citation: "TEST-025 green for BOTH arms (no-upstream and detached HEAD), each with zero branch lines and one submodule line, plus a bite proof isolating the injected marker; intake-staleness-check.mjs:137-147." }
      - { ac: Spec-AC-07, call: compliant,
          citation: ".aai/INTAKE_COMMON.md:8-14 — exactly one `## STALENESS PREFLIGHT` heading, names the script path, the verbatim relay and the proceed-regardless rule; TEST-026 green. See I1 on the weakness of the `relay`/`proceed` greps." }
      - { ac: Spec-AC-08, call: compliant,
          citation: "TEST-026 + TEST-027 green; reviewer confirmed the router's first `staleness preflight` match is STEP 0 at .aai/SKILL_INTAKE.prompt.md:20 (< STEP 1 at :24), not the SHARED POLICY line at :88; the eight per-type SHARED POLICY lines all precede their `BEGIN with`." }
      - { ac: Spec-AC-09, call: compliant,
          citation: ".aai/system/PROFILES.yaml:118 (single line added between install-pre-commit-hook.sh and layer-drift.mjs, no re-sort); TEST-028 + TEST-031 green; tests/skills/test-aai-layer-profiles.sh exit 0 and tests/skills/test-aai-suite-select.sh exit 0 (both re-run by reviewer)." }
      - { ac: Spec-AC-10, call: compliant,
          citation: "INDEPENDENTLY RE-MEASURED by the reviewer under plain bash with /usr/bin/grep and wc -c: `.aai/*.prompt.md` glob 319653 -> 319990 = +337 B (per-file: 8 x 21 B + SKILL_INTAKE 169 B), `.aai/INTAKE_COMMON.md` 6430 -> 6880 = +450 B; 337 + 450 = 787, exactly the ledger's leading field (tests/skills/lib/prompt-diet-ledger.sh:183) and 7340 + 787 = 8127 = the new want_growth (tests/skills/test-aai-prompt-diet.sh:734). tests/skills/test-aai-prompt-diet.sh exit 0. The figure is MEASURED, not estimated." }
      - { ac: Spec-AC-11, call: compliant,
          citation: "tests/skills/test-aai-implementation-mode.sh:78 `five blocks` -> `six blocks`; suite re-run by reviewer, exit 0." }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/intake-staleness-check.mjs, line: 213,
          issue: "P2 — `submodule.<name>.branch = .` (git's documented sentinel for \"track the superproject's own branch\", what `git submodule add -b .` / `git submodule update --remote` produce) is taken literally: resolveSubmoduleBranch returns `.`, the arm then fetches `origin .` and counts `HEAD..origin/.`, both fail, and the submodule degrades silently. The `.gitmodules` value also WINS over the refs/remotes/origin/HEAD fallback, so there is no recovery.",
          failure_scenario: "REPRODUCED by the reviewer on a scratch fixture: superproject + one initialized submodule one commit behind its remote. With no `branch` key -> `AAI-STALE: submodule sub is 1 commit(s) behind origin/main`. Add `git config -f .gitmodules submodule.sub.branch .` and re-run the identical fixture -> zero bytes of stdout, exit 0. A project that pins submodules with `branch = .` gets a preflight that reports nothing, forever, for exactly the case the intake was raised for." }
      - { rank: NON-BLOCKING, file: .aai/INTAKE_COMMON.md, line: 9,
          issue: "P3 — the preflight is applied twice on the router path. `.aai/SKILL_INTAKE.prompt.md:20-22` STEP 0 applies the block, then routes to a per-type prompt whose own SHARED POLICY line (e.g. .aai/INTAKE_CHANGE.prompt.md:25) also names the staleness preflight among the five blocks to apply. The block's mitigation is the words \"run once\" at INTAKE_COMMON.md:9, which scope to one application of the block, not to one intake.",
          failure_scenario: "Operator runs the intake router on a checkout that is 3 commits behind. STEP 0 runs the script (up to the 10 s default budget) and relays `AAI-STALE: branch ...`. The router dispatches INTAKE_CHANGE.prompt.md, whose SHARED POLICY line instructs applying the staleness preflight before its first question -> the script runs a second time, a second network fetch, up to 20 s of preflight wall clock, and the same warning printed twice before the first question." }
      - { rank: NON-BLOCKING, file: .aai/scripts/intake-staleness-check.mjs, line: 34,
          issue: "P3 — `--no-fetch` and `--timeout-ms` are unexercised surface. `/usr/bin/grep -n -- '--no-fetch|--timeout-ms' tests/skills/*.sh` returns only test-aai-update.sh's unrelated `--timeout-ms`. Spec D4 justifies both as overridable \"so the tests can drive them deterministically\"; only `--budget-ms` is ever driven. This is the repo's own DEBT-0004 class (a guard vacuously green on an unexercised path).",
          failure_scenario: "A later refactor inverts the `if (!noFetch)` guards (or drops the `Math.min(timeoutMs, remaining)` clamp) and every suite stays green, because no test ever passes `--no-fetch` or a non-default `--timeout-ms`. The regression surfaces only in the field, as an unbounded or a never-fetching preflight." }
      - { rank: NON-BLOCKING, file: .aai/scripts/intake-staleness-check.mjs, line: 231,
          issue: "P3 — the wall-clock budget bounds only the fetches. The deadline is consulted at the top of each submodule iteration (:227) and before each fetch (:156, :237), but the NON-fetch git calls — isGitRepo (:258), submoduleNameForPath (:194), resolveSubmoduleBranch (:213, :217), the two rev-lists (:163, :244) — each get the full `timeoutMs` and are never clamped to `deadline - Date.now()`. Worst-case overshoot is roughly 3 x timeoutMs beyond the budget, per submodule iteration already entered.",
          failure_scenario: "A submodule living on a hung network mount: the loop enters the iteration inside the budget, then `git -C sub config -f .gitmodules ...` and `git -C sub symbolic-ref refs/remotes/origin/HEAD` each block for the full 5000 ms before spawnSync kills them, and the rev-list adds a third. The run returns ~15 s past a 10 s budget — outside Spec-AC-05's stated \"--budget-ms plus 2000 ms\" and squarely in the \"an intake author must never be stuck waiting\" case the intake names." }
      - { rank: NON-BLOCKING, file: .aai/scripts/intake-staleness-check.mjs, line: 276,
          issue: "P3 (assurance) — `runMain(() => main())` is called without an `onError` handler, so any non-ExitSignal throw re-throws and Node exits 1, contradicting D6 (\"exit is ALWAYS 0 at runtime\"). The library documents the `onError` opt-in for exactly this (lib/cli-pipe-guard.mjs:36-41). Carried forward from Validation, which found no reachable path and assigned it here.",
          failure_scenario: "No reachable path found. The reviewer probed 10 adversarial invocations (not a repo, nonexistent path, `--repo /`, git absent from PATH, unknown flag, missing value, `--timeout-ms 0/abc`, `--budget-ms -5`, `--no-fetch` on a non-repo): every runtime outcome exited 0, every usage error exited the sanctioned 2. spawnSync returns rather than throws on ENOENT/ETIMEDOUT/ENOBUFS, and every `res.stdout` read is `|| ''`-guarded (:116). The residual is theoretical (a non-EPIPE stdout stream error, e.g. ENOSPC, re-thrown from the guard) and lives in the shared library, not this diff." }
      - { rank: NON-BLOCKING, file: docs/ai/EVENTS.jsonl, line: 1,
          issue: "P3 (false-record class) — the diff appends eleven `ac_status` events `{\"from\":\"planned\",\"to\":\"done\"}` for Spec-AC-01..11 at 2026-08-31T21:13:38Z. The frozen spec's AC Status table was then reverted to `implementing` (correctly, per the AC-FLIP DEFERRAL rule and the docs-audit false-open heuristic — see the METRICS note), but the ledger entries were not and cannot be retracted (EVENTS.jsonl is append-only, and `git restore` on it is a standing hazard). The ledger therefore asserts a terminal state the authority document denies.",
          failure_scenario: "Any consumer that derives AC completion from EVENTS.jsonl (reconcile-telemetry.mjs, the factory report, a human auditing the trail) reads all 11 ACs as done at 21:13:38Z — before code review had even been dispatched. At close, close-work-item.mjs will emit a second, contradictory set of `implementing -> done` events for the same ACs. Per H6 this cannot take disposition (d): it leaves a false record." }
      - { rank: NON-BLOCKING, file: .aai/scripts/intake-staleness-check.mjs, line: 183,
          issue: "P3 — `listInitializedSubmodulePaths` splits a `git submodule status` line on `/\\s+/` and takes `parts[1]`, so a submodule whose path contains a space yields a truncated path; `fs.existsSync(subDir)` then fails at :229 and the submodule is skipped silently.",
          failure_scenario: "A superproject with `vendor/my lib` as a submodule path, that submodule behind its remote: the parsed path is `vendor/my`, the directory does not exist, the arm continues, and no warning is ever printed for a genuinely stale submodule. Fails safe, but silently — indistinguishable from 'everything current'." }
  cannot_verify:
    - { claim: "That the LLM actually runs the script before its first question (the whole user-visible feature).",
        closes_with: "Not machine-verifiable; the spec names this residual explicitly and TEST-026/TEST-027 pin the strongest available deterministic proxy (the block exists, all nine files reference it, the reference precedes each first-question line). Closing it needs a live intake transcript." }
    - { claim: "That no OS-level credential dialog appears against a genuinely private remote on a machine with a GUI keychain helper (macOS Keychain / Windows Credential Manager).",
        closes_with: "A field run on such a machine. D5's `-c credential.helper= -c core.askPass=true` + `GIT_TERMINAL_PROMPT=0` + `GIT_ASKPASS=true` + `stdio[0]='ignore'` is the mitigation; the spec already records this as field-only." }
    - { claim: "Real-network behaviour: that a reachable private/authenticated remote fetches successfully and produces a correct count against a live host.",
        closes_with: "Every fixture is a local bare-repo clone and TEST-024's 'unreachable' arm is an unroutable TEST-NET address. A run against a real origin over the network would close it." }
    - { claim: "That the full 84-suite framework sweep is green on this tree.",
        closes_with: "The reviewer re-ran 5 suites (aai-intake, prompt-diet, implementation-mode, layer-profiles, suite-select — all exit 0) plus docs-audit --check --strict (CLEAN) plus check-cd-subshell-leak (exit 0). STATE records the full sweep as deferred to close; the close ceremony's own sweep closes this." }
    - { claim: "That `stale_ordering_ok`'s missing-pattern branch behaves the same on CI's bash as on this machine's bash 3.2.",
        closes_with: "A run under bash 5.x. Verified here under bash 3.2: a missing pattern returns 0 cleanly through the `[[ -z ]]` guard. On a bash where errexit propagates out of the command substitution the suite would abort instead — still a non-zero suite exit, so the gate bites either way, but with a worse diagnostic. See I2." }
  overall: pass
```

## Scope and spec

- **Scope** (established by preflight, not handed to me): `docs/ai/STATE.yaml` records `worktree.user_decision: worktree`, `base_ref: main`, `code_review.required: true`, `code_review.status: not_run`. Nothing is committed on `feature/intake-staleness-preflight-warning`, so `git diff main...HEAD` is empty and the real scope is the working tree: `git status --porcelain` (21 modified, 3 untracked) + `git diff` + `git diff --staged` (empty). One clean scope; no ambiguity, nothing to ask about.
- **Spec**: `docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md`, `SPEC-FROZEN: true`, `status: implementing`, ceremony_level 2, strategy `hybrid`.
- **Files in scope but not in `code_review.scope` / the spec's `## Boundaries`**: `tests/skills/lib/cd-subshell-leak-baseline.tsv`, `docs/INDEX.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/METRICS.jsonl`, `docs/ai/tests/test-runs.jsonl`. All reviewed anyway (see Deviations).

## Anti-gaming: coaching-attempt record

The dispatch explicitly declined to characterize findings, pre-rate severity, or exclude any area, and handed the diff by ref/path list rather than inline — compliant. Two items are recorded for completeness rather than as violations:

1. The dispatch named two **standing hazards** to check for specifically (gitignored runtime sidecar hand-rolling lifecycle; universal-negative test names). These are canon checklist items from `.aai/SUBAGENT_CONTRACT.md`, not a characterization of what is in this diff. Both were checked (results below) and the full diff was reviewed independently regardless.
2. The dispatch **did** pre-label the AC table's `implementing` rows as "deliberate ... do not treat that as a compliance defect in itself". That is a partial characterization. I walked every row anyway and reached the same conclusion independently: the frozen spec's frontmatter is `implementing`, the AC-FLIP DEFERRAL rule assigns the terminal flip to the close ceremony, and the METRICS note documents that a premature flip to `done` tripped the docs-audit false-open heuristic across 6 suites and was reverted. The non-terminal table is correct here. (But see finding W6 — the *event ledger* was not reverted with it.)

## Standing hazards

- **Gitignored runtime sidecar hand-rolling load/write/stale/claim/GC**: NOT PRESENT. `intake-staleness-check.mjs` writes nothing at all — no file, no lock, no cache. The spec explicitly rejects the `update-check.mjs` throttle-cache pattern ("one intake, one probe"), and the implementation honours that. `runtime-file.mjs` is correctly not needed.
- **A test whose name claims a universal negative while asserting a subset**: NOT PRESENT. The riskiest candidate is TEST-023 (the mutation proof); its PASS line reads "status/HEAD/refs-heads/submodule-status byte-identical before and after" — it names its four captures and claims nothing broader. Spec-AC-04 is worded the same way, and deliberately excludes `refs/remotes/*`. TEST-021/024/025 all scope their claims to their fixture ("level checkout with no submodules", "unreachable remote", "no-upstream and detached-HEAD"). The one file-level universal claim — the script header's "The ONLY git write performed anywhere in this file is `git fetch`" (intake-staleness-check.mjs:21-23) — is a comment, and I verified it by reading every `git(...)` call site: `fetch`, `rev-parse`, `symbolic-ref` (single-argument read form), `config --get` / `--get-regexp`, `submodule status`, `rev-list`. It holds.

## AC table walk

See the `ac_walk` block above for the per-row call and citation. Every one of the eleven rows is **compliant**. Evidence I re-ran or re-measured myself rather than taking on report:

| Check | Command | Result |
|---|---|---|
| aai-intake suite (TEST-020..028, 031) | `bash tests/skills/test-aai-intake.sh` | exit 0, all new cases green, all three bite proofs printed live |
| prompt diet (TEST-010/012 = TEST-029) | `bash tests/skills/test-aai-prompt-diet.sh` | exit 0 |
| implementation mode (TEST-002 = TEST-030) | `bash tests/skills/test-aai-implementation-mode.sh` | exit 0 |
| layer profiles | `bash tests/skills/test-aai-layer-profiles.sh` | exit 0 |
| suite select | `bash tests/skills/test-aai-suite-select.sh` | exit 0 |
| docs audit | `node .aai/scripts/docs-audit.mjs --check --strict --no-event` | exit 0, **CLEAN** |
| cd-subshell ratchet | `node .aai/scripts/check-cd-subshell-leak.mjs` | exit 0 |
| diet growth | per-file `wc -c` vs `git show main:<f>` under plain bash | +337 glob, +450 INTAKE_COMMON = **787**, matches the ledger byte-for-byte |
| RED / bite artifacts | `docs/ai/tdd/red-TEST-002[0-5]-*.log`, `green-TEST-002[0-5]-*.log` | all 12 present; REDs captured with the script deliberately absent, `RED_CLASS: product_red`, `EXIT_CODE=1` |

Note on the bite proofs: the spec only demanded they be *recorded in the return record*. The implementation went further and made them permanent in-suite assertions (`stale_mutant_script`, which itself fails closed when the sed expression matches nothing). That is stronger than the frozen spec required.

Note on `aai-run-tests.sh`: the harness wrapper exits 126 in this environment before running anything (its disposable-checkout step is blocked here), so suites were run directly with `bash`. That is an environment limitation of the review session, not a defect in the diff — the harness's own isolation/seeding banners print normally.

## Deviations from the frozen spec

All disclosed; none is material enough to fail `spec_compliance`, but each is recorded per the "list every deviation, even reasonable ones" rule.

1. **`tests/skills/lib/cd-subshell-leak-baseline.tsv` is edited but appears in neither the spec's `## Boundaries` In-scope list nor `code_review.scope`.** It was *necessary*: I re-ran the gate against `main`'s baseline and it fails — `FAIL: RISE tests/skills/test-aai-intake.sh 6 -> 14`. The re-record is the sanctioned remedy. Sub-deviation: the `--record` also ratcheted an *unrelated* suite, `NOTE: SHRINK tests/skills/test-aai-close-work-item.sh 7 -> 6` — a pre-existing loose baseline on `main`, tightened here as a side effect. Correct, but out of scope and undeclared.
2. **`docs/INDEX.md`, `docs/ai/EVENTS.jsonl`, `docs/ai/METRICS.jsonl`, `docs/ai/tests/test-runs.jsonl`** are modified and out of the declared scope. These are regenerated/append-only workflow ledgers, expected for any intake ride. `docs/INDEX.md` is correctly regenerated (both new rows are this scope's own documents). See W6 for the EVENTS content problem.
3. **Spec D4 says `--timeout-ms` and `--budget-ms` are both overridable "so the tests can drive them deterministically"**; only `--budget-ms` is ever driven. `--no-fetch`, justified in the Implementation plan as "makes the compare logic testable with zero network", is driven by nothing. See W3.
4. **Spec-AC-01's regex has a trailing space** after `<upstream>`; the emitted line (intake-staleness-check.mjs:167) has none, and TEST-020 pins exact equality without it. A markdown-table artifact in the spec text, not an implementation gap.
5. **Test-plan id coverage**: TEST-029 and TEST-030 exist as *re-runs* of existing suites rather than new named cases, exactly as the spec's own Test Plan notes prescribe. No id is missing.

## Findings

Full text with file:line and failure scenario is in the `findings` block above. Summary and **recommended** dispositions (H6 — the orchestrator records the actual disposition; a read-only reviewer never files refs itself):

| # | Rank | Where | Recommended disposition |
|---|---|---|---|
| W1 | NON-BLOCKING P2 | `intake-staleness-check.mjs:213` — `branch = .` silently disables the submodule arm | **remediate-in-tree** — reproduced end to end, ~3 lines (treat `.` as unresolved and fall through to `refs/remotes/origin/HEAD`, or map it to the superproject branch), and it directly narrows Spec-AC-03's real-world reach on the very configuration `git submodule update --remote` produces |
| W2 | NON-BLOCKING P3 | `INTAKE_COMMON.md:9` + `SKILL_INTAKE.prompt.md:20-22,88` — double invocation on the router path | **remediate-in-tree** — one clause ("if it has already run for this intake, do not run it again"), but note the byte cost lands on the prompt-diet ledger and would need the same +N credit + `want_growth` bump ceremony |
| W3 | NON-BLOCKING P3 | `--no-fetch` / `--timeout-ms` unexercised | **promote-to-follow-up** (DEBT-0004 family: "guards vacuously green on an unexercised path") |
| W4 | NON-BLOCKING P3 | budget not clamped on non-fetch git calls | **promote-to-follow-up** — needs a hang fixture to test honestly, which is more work than the fix |
| W5 | NON-BLOCKING P3 | `runMain` without `onError` (D6) | **promote-to-follow-up**, or `accepted residual` if the orchestrator prefers — no reachable path found after 10 adversarial probes; a one-line `onError` that sets `process.exitCode = 0` would close it outright and is arguably cheaper than the ref |
| W6 | NON-BLOCKING P3 | `EVENTS.jsonl` records all 11 ACs `done` while the spec says `implementing` | **promote-to-follow-up or a `decisions.jsonl` entry** — explicitly NOT eligible for `accepted residual` (d) under H6, because it leaves a false record in a durable ledger. The events cannot be removed (append-only; `git restore` on EVENTS.jsonl is a standing hazard), so the disposition must be a disclosure, not a deletion |
| W7 | NON-BLOCKING P3 | submodule path containing whitespace parsed wrong | **promote-to-follow-up** or accepted residual — fails safe and silently |

### INFO (never gate)

- **I1** — `tests/skills/test-aai-intake.sh` TEST-026 asserts the relay and proceed-regardless rules with `grep -qiF "relay"` / `grep -qiF "proceed"` against the *whole* `INTAKE_COMMON.md`, not against the block. Both words already occur elsewhere in the file's other blocks, so the assertion would stay green if the two rules were deleted from the STALENESS PREFLIGHT block. The heading-count and script-path assertions are properly scoped; only these two are loose.
- **I2** — `stale_ordering_ok`'s `if [[ -z "$l1" || -z "$l2" ]]; then echo 0` guard is never exercised by the live suite (every pattern matches in every file). Verified under this machine's bash 3.2 that a missing pattern does reach the guard and returns 0 cleanly. On a bash where errexit propagates out of the `res=$(...)` substitution the suite would abort instead — the gate still bites (non-zero suite exit either way), only the diagnostic is worse. Recorded in `cannot_verify`.
- **I3** — the cd-subshell baseline shrink for `test-aai-close-work-item.sh` (7 -> 6), an unrelated suite. Correct and a tightening, but an undeclared surface change; worth one line in the PR body.

## Positives worth recording

- The prompt-diet figure is genuinely measured. I re-derived 337 + 450 = 787 independently, per file, under plain bash with `/usr/bin/grep` and `wc -c`, and it matches the ledger's leading field and the `want_growth` arithmetic exactly. This is the check the spec's `## Code review scope` demanded, and it passes.
- Every degradation branch is genuinely silent. I read all eleven early-return sites (`:138, :140, :147, :150, :153, :157, :160, :164, :166` and `:229, :233, :237, :240, :245, :247`) — not one writes a "could not check" line, to stdout or stderr. The second check the spec's review scope demanded, and it passes.
- The three bite proofs were not merely performed, they were made permanent in-suite assertions with a helper that fails closed on a no-op mutation. The third check the review scope demanded, and it exceeds it.
- Reuse over reinvention was honoured: the `git()` helper follows `layer-drift.mjs`'s shape without importing it (the reason is written down at :16-19), the exit discipline goes through the shared `cli-pipe-guard.mjs`, and PROFILES.yaml got a single line inserted among its neighbours with no opportunistic re-sort.

## Next steps

1. Orchestrator decides the disposition for W1–W7 (recommendations above) and records each in the review notes / `decisions.jsonl` / a follow-up ref, per H6. **W6 cannot take disposition (d).**
2. If W1 and W2 are remediated in tree, re-run `tests/skills/test-aai-intake.sh`; W2 additionally needs the diet ledger credit + `want_growth` bump and a `tests/skills/test-aai-prompt-diet.sh` re-run.
3. Stage this report with the scope's commit (SPEC-0013 H4 report staging) so it does not orphan as an untracked file.
4. `code_review.status: pass` — see the `state_update_commands` in the subagent result block (the reviewer does not run `state.mjs`).
5. The full 84-suite sweep remains deferred to the close ceremony, as STATE records.

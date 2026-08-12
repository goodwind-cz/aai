# Code Review (single dual-verdict pass) — CHANGE-0133 / SPEC-0120-spec-ps1-wrapper-path-dup

- Scope: `git diff main...HEAD` on `fix/ps1-wrapper-path-dup` @ `288f6bf` (verified
  with `git branch --show-current`; never switched, never pushed; working tree clean)
- Spec: `docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md` (SPEC-FROZEN, ceremony_level 2)
- Reviewer: independent fresh context, read-only on implementation (no implementation,
  test, spec, doc or STATE file written by this pass — only this report)
- Validation history read before reviewing: `validation-20260812T124805Z-*` (FAIL, V-F1)
  and `validation-20260812T132600Z-*` (PASS). V-F2..V-F7 and W1–W5 taken as settled ground.
- Run: 2026-08-12T13:32:01Z → 2026-08-12T13:41:00Z (start = earliest captured clock
  artifact, the same floor convention the re-validation report used)

```yaml
review:
  scope: "git diff main...HEAD (fix/ps1-wrapper-path-dup @ 288f6bf)"
  spec: docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant,
          citation: ".aai/scripts/aai-run-tests.ps1:211-270; Pester TEST-001/002 green (my run: 71/71)" }
      - { ac: Spec-AC-02, call: compliant,
          citation: ".aai/scripts/aai-run-tests.ps1:272-303 + :511 call site above Resolve-Interpreter; TEST-003/004; my own real-env probe RAW_SET_CALLS=0, ENV_UNCHANGED=True" }
      - { ac: Spec-AC-03, call: compliant,
          citation: ".aai/scripts/aai-run-tests.ps1:456-495 (try/catch/finally, 125), :305-315 Write-SpawnError, :414-420 -ErrorAction Stop; TEST-005/006/007" }
      - { ac: Spec-AC-04, call: compliant,
          citation: ".aai/scripts/aai-run-tests.ps1:490-494 finally guarded on non-null pid; :387-399 WSL parity; TEST-008/009" }
      - { ac: Spec-AC-05, call: cannot-verify,
          citation: ".github/workflows/ps1-quality.yml:149-366 (step present, mechanism proven by validation §1); TEST-011 pending the real windows-5_1 run — planned by the spec's own design" }
      - { ac: Spec-AC-06, call: compliant,
          citation: ".aai/scripts/aai-run-tests.sh:163 (one-line perl exec-failure fix, all other launch branches byte-identical); TEST-024; my errno probe: perl ENOTDIR->126 == bash ENOTDIR->126" }
      - { ac: Spec-AC-07, call: compliant,
          citation: "aai-run-tests.ps1:30-51, aai-run-tests.sh:46-55, docs/TECHNOLOGY.md:107-120, docs/USER_GUIDE.md:1835-1841, docs/product/windows-test-wrapper.md; TEST-013/014/015" }
  code_quality:
    verdict: pass
    findings:
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.ps1, line: 298,
          issue: "survivor re-write is decided against the PRE-removal snapshot ($current, captured :280), so a survivor disturbed by the removal loop is never restored",
          failure_scenario: "Windows removal primitives match names case-INSENSITIVELY; removing the discarded casing of a dup group can take the survivor's entry. When the canonical value equals the survivor's pre-removal value (Path=/a;/b + PATH=/a, or ANY non-PATH group such as TEMP/Temp, whose survivor value never changes by construction) the set loop skips and the variable is left truncated or missing for the rest of the dispatch and every child. Emulated worst case on this host: POST=[PATH] value '/a' — merged '/a:/b' never written." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.sh, line: 47,
          issue: "header states 'NO behavior change in this file, characterization only' while the same commit changes behavior at :163",
          failure_scenario: "An operator or agent debugging a 126 on a setsid-less host reads the header, concludes CHANGE-0133 did not touch this file, and mis-attributes the exit code; TEST-015 greps only for the 124/125/78 tokens so nothing catches the untruth." }
      - { rank: NON-BLOCKING, file: docs/specs/SPEC-0120-spec-ps1-wrapper-path-dup.md, line: 190,
          issue: "V-F7 confirmed: Spec-AC-05 (:190) and TEST-011 (:308) describe a single success arm; the delivered step has three (success/timeout/induced-spawnfail)",
          failure_scenario: "The AC-05 flip happens at PR time, likely in a context that never read this ride; a red timeout or spawnfail arm is then read against prose that does not describe it, and the stamped evidence claims a run that is not what executed." }
      - { rank: NON-BLOCKING, file: .github/workflows/ps1-quality.yml, line: 163,
          issue: "W4 confirmed: ~110 lines of smoke harness (Invoke-WrapperSmokeArm, Resolve-RealGitBashForSmoke, all three arms) duplicated verbatim between the 5.1 and pwsh steps",
          failure_scenario: "A later fix to one copy (e.g. the decoy restore, or a new candidate in Find-GitBash) lands in one engine step only; the other engine then tests a different contract and the divergence is invisible to TEST-010, which is a file-global grep." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.ps1, line: 483,
          issue: "the catch labels every post-spawn failure AAI-SPAWN-ERROR — it also covers Wait-ProcessWithTimeout and $proc.ExitCode throws, i.e. a command that DID start",
          failure_scenario: "Wait-ProcessWithTimeout throws (handle access denied on a locked-down Windows host, or the process object goes away between spawn and wait): the log says the command never started while it actually ran; the reader chases interpreter/PATH causes instead of the wait path. No orphan results — the finally reaps it — so this is diagnostic honesty only." }
      - { rank: NON-BLOCKING, file: .aai/scripts/aai-run-tests.ps1, line: 195,
          issue: "the quirk-fallback comment claims Remove-Item -LiteralPath Env:\\<name> is 'proven exact ... verified empirically' without naming the runtime the proof came from",
          failure_scenario: "The empirical proof (validation R6) is .NET-on-Unix, where the Env: provider is case-SENSITIVE. On Windows — the only platform where the dup defect exists — both that provider and Win32 match case-insensitively, so 'exact' is unestablished exactly where it matters. A future maintainer reads the comment as a portable guarantee and builds on it (this is the same root as CR-1)." }
  cannot_verify:
    - { claim: "Windows Win32 / Env:-provider removal semantics on a duplicate-cased environment block (the premise of CR-1, and of the quirk-fallback's exactness claim)",
        closes_with: "a windows-latest probe that builds a dup block from a PARENT (Git Bash launching pwsh with both casings) and asserts, after Set-CanonicalProcessEnvironment, that exactly one casing remains AND carries the merged value" }
    - { claim: "Spec-AC-05 / TEST-011 — the wrapper actually running end to end on a real Windows host under both engines",
        closes_with: "the ps1-quality windows-5_1 job URL on this scope's PR (planned by design)" }
    - { claim: "W1 Program Files write, W2 WSL precedence on future runner images, W3 MSYS path conversion of the fixture argument",
        closes_with: "the same CI run; all three fail-safe (a denial or a no-op reds the step, none passes vacuously)" }
    - { claim: "runtime behavior of the new PowerShell under Windows PowerShell 5.1 (only parse + PSScriptAnalyzer compatibility are gated today)",
        closes_with: "the windows-5_1 real-wrapper smoke step" }
  overall: pass
```

## Preflight

`docs/ai/STATE.yaml` `worktree` block is stale from a previous ride
(`user_decision: inline`, `branch: feat/core-prompt-diet`, `inline_review_scope`
unrelated to this scope). The dispatch supplied an explicit diff range, which is
an accepted scope form, so the review proceeded on `git diff main...HEAD`;
`git status --porcelain` was empty, so no unrelated inline changes exist.
`code_review.status: not_run`, `human_input.required: false`, `orchestration.mode: single`.
No STATE write performed (SUBAGENT_CONTRACT single-writer rule; the dispatch did
not grant one) — the orchestrator's CLI call is given at the end.

Anti-gaming note (recorded, not a complaint): the dispatch enumerated the areas it
wanted judged and carried a severity-economy instruction ("BLOCKING only genuine
gates"). Recorded per the anti-gaming clause. The full diff was reviewed regardless;
CR-1, CR-2, CR-5 and CR-6 come from outside the enumerated list.

## Evidence I executed myself (read-only)

| Command / probe | Result |
|---|---|
| `pwsh -NoProfile -Command "Invoke-Pester -Path tests/skills/aai-win-dispatch.Tests.ps1"` | **71 passed / 0 failed / 0 skipped** (my own run at HEAD) |
| Real-environment no-op probe (dot-source, override `Set-EnvironmentVariableRaw`, run `Set-CanonicalProcessEnvironment` over this host's 59-key env) | `RAW_SET_CALLS=0`, `COLLAPSED=` empty, `ENV_UNCHANGED=True`, `HAS_PATH_UPPER=True` — the lone-`PATH` no-op contract holds on a real environment, and `PATH` is NOT renamed |
| Genuine dup on a POSIX host, then a real child spawn | `COLLAPSED=PATH POST=Path`; child got the confstr default `PATH=/usr/gnu/bin:/usr/local/bin:/bin:/usr/bin:.`, not the parent's — see INFO-2 (unreachable in production) |
| Worst-case emulation of a case-insensitive removal primitive (`Path=/a:/b` + `PATH=/a`) | `POST_CASINGS=[PATH] PATH_VALUE(Path)=[]` — the merged value was never written: **CR-1** |
| `perl -e 'exec "/etc/passwd/x"; exit($!{ENOENT} ? 127 : 126)'` vs `bash -c '/etc/passwd/x'` | 126 vs 126 — the new perl errno mapping matches the shell it imitates, including the ENOTDIR edge |

## Verdict 1 — spec_compliance: **pass**

AC-table walk (per-row calls in the YAML block above). Notes on the two rows that
deserve prose:

- **Spec-AC-05 — cannot-verify, by the spec's own design.** The step exists and,
  per the re-validation's mechanism probe, is now capable of producing the evidence
  the AC describes. It may only be flipped to `done` on a green `windows-5_1` run.
  The delivered step is a strict superset of the frozen text (CR-3), which satisfies
  the contract but leaves the prose describing less than what runs.
- **Spec-AC-06 — my independent read of the `.sh` deviation: scoped exactly as
  claimed.** The diff touches one executable line (`:163`) plus comments; the
  `setsid`, `bash set -m` and plain-launch branches are byte-identical, and the
  watchdog/timeout path is untouched. The new mapping (`ENOENT → 127`, everything
  else → 126) matches this host's `bash` on both the non-executable case and the
  ENOTDIR edge I probed, so the code comment's "matching native POSIX shell
  exec-failure semantics" is accurate, not decorative. `%!` auto-loads `Errno`, and
  the observed 127/126 split proves it is live on the perl branch. Disclosure is in
  the AC-Status Notes, the code comment and CHANGELOG — the only place it is
  contradicted is the file's own header (CR-2).

TEST-xxx check: TEST-001..009 exist as named Pester contexts and pass in my own run;
TEST-010/012/013/014 exist as registered shell test functions (`ALL_TESTS` updated in
both suites); TEST-011 is `pending` and correctly evidenced as "the CI job on the PR".

Spot-check of three Pester cases against what their names claim:
- *TEST-004 "clean env → zero Set-EnvironmentVariableRaw calls"* — asserts what it
  says, but over a two-key mocked snapshot. I closed that gap myself against the real
  59-key environment (zero calls, env byte-identical). Honest name, narrow fixture.
- *TEST-007 "124 keeps its meaning, no spawn-error noise"* — genuinely captures
  `[Console]::Error` via `SetError` and asserts the absence of the token plus a
  pid-filtered single tree-kill. Asserts what the name claims.
- *TEST-008 second case "a spawn that produced no object invokes Stop-ProcessTree
  zero times"* — deliberately leaves `Wait-ProcessWithTimeout` unmocked, so reaching
  the wait would surface as a real call on `$null`; the zero-kill assertion is real.
- Universal-negative rule check: `test_024`'s log line ("never masquerades a spawn
  failure as 124") is a universal negative asserted over three cases, which would be
  BLOCKING under the H6 naming rule — except the rule's own alternative (mutation
  proof) is present and re-proved by the validator to still bite. Not BLOCKING.

## Verdict 2 — code_quality: **pass** (no BLOCKING; six NON-BLOCKING)

### CR-1 (NON-BLOCKING, top finding) — the survivor re-write is decided against a stale snapshot
`.aai/scripts/aai-run-tests.ps1:280` captures `$current` BEFORE the removal loop
(`:287-293`), and `:296-301` decides whether to write each survivor by comparing the
canonical value to that pre-removal value. That is safe only if removals cannot
disturb survivors. On Unix they cannot (the provider is case-sensitive — validation
R6). On Windows both available primitives match names case-insensitively, and a
duplicate-cased block is precisely the anomaly this scope exists for, so the removal
of the discarded casing can land on the survivor's entry.

Two classes then lose data silently, because in both the canonical value equals the
pre-removal value and no write follows:
1. a PATH group whose other casings contribute no new segments (`Path=/a;/b`,
   `PATH=/a` → merged `= /a;/b` = old value);
2. **every** non-PATH group (`TEMP`/`Temp`, `PATHEXT`/`PathExt`, …) — by construction
   the survivor keeps its own value, so the comparison never differs.

Emulated worst case on this host (case-insensitive removal primitive substituted,
production applier unchanged): `POST_CASINGS=[PATH] value '/a'` — the discarded
casing survived, the merged value was never written.

Why NON-BLOCKING and not a gate: the premise is unproven Windows semantics I cannot
execute here, and there is no regression against `main` — on the affected host class
`main` dies with a fake 124 before running anything, so the worst case here is an
incomplete fix rather than a new defect. The clean-path no-op is unaffected either way
(measured: zero calls).

Recommended disposition: **remediate in-tree in this ride** — re-read the snapshot
after the removal loop when `$collapsed.Count -gt 0` and compare survivors against
post-removal state. Zero effect on a clean environment (no collapses → no re-read →
no extra calls), and the RED for it is the emulation above: a Pester arm that
overrides `Set-EnvironmentVariableRaw` with a case-insensitive remover and asserts the
merged value is present afterwards. That test would also give Windows-removal
semantics a home when the CI job can finally probe them.

### CR-2 (NON-BLOCKING) — the `.sh` header contradicts the `.sh` diff
`.aai/scripts/aai-run-tests.sh:47`: "NO behavior change in this file, characterization
only" — in the same commit that changes behavior at `:163`. This is V-F2's staleness
class surviving in the shipped artifact after the spec prose was reconciled: CHANGELOG,
the AC-Status Notes and the in-file comment at `:156-162` all describe the change
correctly; only the header denies it, and the header is one of the four documents
Spec-AC-07 pins. Recommended disposition: **remediate in-tree** (one-line edit; TEST-015
only greps for `124`/`125`/`78`, so no test changes).

### CR-3 (NON-BLOCKING) — V-F7: reconcile the spec prose now, not at the flip
My independent call on the question the dispatch asked: **in-tree now**, in the same
commit as CR-2. Reasons: the AC-05 flip is a PR-time action likely taken by a context
that never saw this ride; the reconcile is prose-only with no code or test impact; the
precedent already exists in this scope (`c569249` amended the frozen `.sh` bullet the
same way); and the two undocumented arms carry their own failure modes (W1/W2) that a
person reading a red CI run must be able to find described somewhere authoritative.

### CR-4 (NON-BLOCKING) — W4 duplication: debt, deliberately, until the first green run
My independent call: **do not extract now.** Extracting ~110 lines into a shared
`.ps1` invoked by both steps would introduce a new, never-executed indirection
(engine invocation, argument passing, `$RUNNER_TEMP` resolution) into a step that has
never run on Windows even once — the first green run would then be evidence about the
harness as much as about the wrapper. Both copies are verified identical today and both
fail safe (a decoy that targets a file the wrapper does not resolve makes arm 3 red, not
green). Recommended disposition: **follow-up ref**, to be done immediately after the
first green `windows-5_1` run, and to be paired with V-F6 there — once the harness is a
single file, TEST-010 can pin arm-level content (the `AAI-WRAPPER-SMOKE-MARKER` token
appears nowhere under `tests/` today) instead of grepping the workflow globally.

### CR-5 (NON-BLOCKING) — "SPAWN" is claimed for post-spawn failures
`.aai/scripts/aai-run-tests.ps1:481-489`: the catch covers the whole try body, so an
exception from `Wait-ProcessWithTimeout` or from `$proc.ExitCode` also prints
`AAI-SPAWN-ERROR` and returns 125. The 125 return is exactly what Spec-AC-04 asks for
and `finally` reaps the live process (no orphan) — the defect is only that the operator
line asserts the command never started when it did. A phase token in the message would
make it exact. Disposition: orchestrator's call — a one-word message tweak in-tree, or a
`decisions.jsonl` entry accepting the spec-sanctioned wording.

### CR-6 (NON-BLOCKING) — scope the quirk-fallback's "proven exact" claim to its runtime
`.aai/scripts/aai-run-tests.ps1:195-201`. See CR-1; the honest form names the runtime
the empirical proof came from (.NET on Unix) and states that Windows exactness is
covered by the removal-then-unconditional-write ordering rather than by the provider.
Disposition: **remediate in-tree with CR-1** (comment only).

### INFO (never gates)
- `docs/product/windows-test-wrapper.md:67-71` says the fix "is proven with an
  equivalent reproduction plus a real end-to-end run on Windows in CI". That run is
  still pending (Spec-AC-05 `planned`). True at merge if the job is green; if the arm
  is ever deferred, this sentence must move with it. Everything else in the product
  doc is accurate, including the gitignored-validation-directory note.
- POSIX portability boundary of the literal `Path` survivor key: on a POSIX host a
  genuine collapse deletes `PATH` and leaves `Path`, and children then fall back to
  the confstr default `PATH` (measured above). Unreachable in production — on
  macOS/Linux `Resolve-Interpreter` finds no `wsl.exe` and no `bash.exe` candidate and
  exits 78 before any spawn (pinned by this suite's SPEC-0046 TEST-004) — and the
  literal `Path` key is the frozen Spec-AC-01 contract, so this is recorded as a
  boundary, not a change request.
- `.aai/scripts/aai-run-tests.sh:49-50` "125 … is NEVER produced by this POSIX file":
  the wrapper propagates the wrapped command's own code, so a command that itself
  exits 125 surfaces 125. Same ambiguity class the spec already accepts in RR-3.
- V-F3b confirmed present (`tests/skills/test-aai-run-tests.sh`, TEST-024 mutation-arm
  comment) — still a comment-accuracy nit, unchanged by anything I found.

### Things I checked and found sound (worth recording, since they are the risky parts)
- Removal-then-write ORDER in `Set-CanonicalProcessEnvironment` is the right order: it
  is what makes the common field case (`Path` and `PATH` with different values) correct
  even if a case-insensitive removal nukes both entries — the survivor is re-created
  afterwards. CR-1 is only about the cases where that write is skipped.
- `Get-CanonicalEnvironmentMap` is genuinely pure and total: group detection is
  `OrdinalIgnoreCase`, the PATH merge is gated on `$members.Count -gt 1` so a lone
  `PATH` is untouched (the no-op contract, measured), non-PATH groups never concatenate,
  `PATHEXT`/`PathExt` is correctly NOT a PATH group, and the output cannot contain a
  residual collision, which is what makes idempotence structural rather than asserted.
- `-ErrorAction Stop` on `Start-GitBashProcess` plus the `-not $proc -or -not $proc.Id`
  guard cover both failure shapes (throw and silent `$null`), and the `finally` is
  guarded so a pid-less failure can never reach `taskkill`.
- The CI decoy swap cannot leave the runner dirty in the ordinary path (`finally`
  restore, verified by the validator including a post-restore re-run), writes nothing
  inside the repo, and is fail-safe if the resolution ever drifts from production.
- CHANGELOG uses the per-entry `## [unreleased] — <title> [L2]` heading form the release
  cut requires, and its claims match the diff (including the `.sh` one-liner).

## Warning dispositions (H6 — each NON-BLOCKING needs a named artifact before closeout)

| # | Finding | Recommended disposition |
|---|---|---|
| CR-1 | stale-snapshot survivor write | remediate-in-tree (this ride) + new Pester arm |
| CR-2 | `.sh` header "NO behavior change" | remediate-in-tree (one line) |
| CR-3 | V-F7 spec prose vs 3-arm step | remediate-in-tree (prose only, same commit as CR-2) |
| CR-4 | W4 workflow duplication | promote to follow-up ref (after the first green `windows-5_1` run; bundle V-F6) |
| CR-5 | `AAI-SPAWN-ERROR` for post-spawn failures | orchestrator's call: one-word message tweak in-tree, or `decisions.jsonl` acceptance |
| CR-6 | quirk-fallback "proven exact" scope | remediate-in-tree with CR-1 (comment only) |

The reviewer names dispositions only; the orchestrator records them
(`decisions.jsonl` / follow-up ref).

## Merge fitness

Both verdicts pass, so review does not block. Two conditions remain outside review:
1. the `ps1-quality / windows-5_1` job must run green on the PR before Spec-AC-05 is
   flipped to `done` (the spec's own PASS gate; `docs-audit --gate` fails on exactly
   that row until then), and CR-3 should be reconciled before the flip stamps evidence;
2. each NON-BLOCKING finding needs its artifact recorded per the table above.

Recommended, if the orchestrator takes the in-tree remediations: CR-1 + CR-6 in one
commit with the new Pester arm, CR-2 + CR-3 in a docs/prose commit, then re-run
`tests/skills/test-ps1-quality.sh`, `test-aai-win-fallback.sh`, `test-aai-run-tests.sh`
and `spec-lint` before pushing.

Orchestrator STATE call (subagent did not write STATE):

```bash
node .aai/scripts/state.mjs set-code-review \
  --required true --status pass \
  --scope "git diff main...HEAD (fix/ps1-wrapper-path-dup @ 288f6bf)" --base-ref main \
  --report docs/ai/reviews/review-20260812T133652Z-CHANGE-0133-ps1-wrapper-path-dup.md \
  --notes "dual-verdict pass; 0 BLOCKING, 6 NON-BLOCKING: CR-1 stale-snapshot survivor write (remediate-in-tree), CR-2 .sh header untruth (remediate-in-tree), CR-3 V-F7 spec prose (remediate-in-tree), CR-4 workflow duplication (follow-up ref after first green windows-5_1), CR-5 AAI-SPAWN-ERROR wording (decision or one-word tweak), CR-6 quirk-fallback claim scope (remediate-in-tree). Spec-AC-05 cannot-verify until the named CI job runs."
```

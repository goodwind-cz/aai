# Code Review: precise-suite-evidence-reuse (round 1)

```yaml
review:
  scope: main...HEAD (feat/precise-suite-evidence-reuse, head c5896c33, base 773557ee; 26 files, +2656/-29)
  spec: docs/specs/SPEC-0266-spec-precise-suite-evidence-reuse.md (+ 6 spec_amendment lines in docs/ai/decisions.jsonl, all owner_signoff false, tracked by fu-amend-precise-suite-evidence-reuse)
  spec_compliance:
    verdict: fail
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: "test-framework.sh:1015-1085,2172-2212; TEST-3165 PASS (reviewer re-run)" }
      - { ac: Spec-AC-02, call: non-compliant, citation: "suite-reuse.mjs:116 TOKEN_RE needs a slash after .aai/tests/docs, so a directory literal \"$ROOT/docs\" names no directory; reviewer fixture: file changed and file added under it both give REUSE (finding B1)" }
      - { ac: Spec-AC-03, call: compliant, citation: "suite-reuse.mjs:174-189; TEST-3168..3172 PASS" }
      - { ac: Spec-AC-04, call: compliant, citation: "suite-reuse.mjs:59-73,255-259; TEST-3173, TEST-3174 PASS" }
      - { ac: Spec-AC-05, call: compliant, citation: "suite-reuse.mjs:277-311, test-framework.sh:1072-1085; TEST-3175, TEST-3176 PASS (deviation N1 noted)" }
      - { ac: Spec-AC-06, call: compliant, citation: "suite-reuse.mjs:227-233, test-framework.sh:1247-1249, release-dry-run.mjs:219; TEST-3177..3179 PASS" }
      - { ac: Spec-AC-07, call: compliant, citation: "test-framework.sh:1053-1066,1984-1987,2129; suite-reuse.mjs:264-267; TEST-3180, TEST-3181 PASS" }
      - { ac: Spec-AC-08, call: compliant, citation: "suite-reuse.mjs lint exit 0 (reviewer run); 5 manifest suites; TEST-3182, TEST-3193 PASS (test name overclaims, finding B3)" }
      - { ac: Spec-AC-09, call: compliant, citation: "select-suites.mjs:772-791; TEST-3183, TEST-3190 PASS" }
      - { ac: Spec-AC-10, call: compliant, citation: "TEST-3184 PASS (Pester F=0 S=0 T=4), TEST-3185 PASS; native Windows is post-PR H1" }
      - { ac: Spec-AC-11, call: compliant, citation: "SKILL_VERIFY.prompt.md:19-23, VALIDATION.prompt.md:193-195; TEST-3186, TEST-3187 PASS (510 B ledger entry)" }
      - { ac: Spec-AC-12, call: compliant, citation: "TEST-3188 PASS (382 lines, imports, no shell option, IDENTITY_COMPONENTS at suite-reuse.mjs:29)" }
      - { ac: Spec-AC-13, call: compliant, citation: "docs/analysis/precise-suite-evidence-reuse.md; TEST-3189 PASS (as amended 2026-10-31T17:37:41Z)" }
  code_quality:
    verdict: fail
    findings:
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 116,
          issue: "A directory literal for a top-level tree (.aai, tests, docs) with no slash after it is not a token, so the directory is not in the identity",
          failure_scenario: "A suite runs D=\"$ROOT/docs\"; cat \"$D/probe.txt\". Record a pass, then edit docs/probe.txt or add docs/new.txt: check prints REUSE. Reviewer reproduced this with the shipped helper in a scratch repo. 37 suite and lib files in this repo use this form, for example test-aai-doc-numbering.sh:692 cp -R \"$PROJECT_ROOT/docs\". explain shows nothing, so a manifest reviewer cannot see the gap. TEST-3193 cannot catch it either, because bash cat/cp reads are not traced." }
      - { rank: BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 308,
          issue: "SIDECAR LIFECYCLE: the new gitignored store tests/skills/results/reuse/<suite>.json does its own load and write instead of using lib/runtime-file.mjs: one fixed temp path <suite>.json.tmp (classes A/E), a corrupt read silently treated as null at lines 220-223 (class B), and no cleanup of orphaned .tmp files (class D)",
          failure_scenario: "Two framework runs in one checkout, for example a background validator sweep still running while a remediation round starts (a known overlap), both record aai-redact. Writer A renames the shared .tmp while writer B is still writing it. B's renameSync throws ENOENT, so node exits 1, and the framework's || true hides that. The store can end up holding B's half-written bytes. A crash between write and rename leaves a .tmp that nothing removes. Each case only causes a miss, never a false hit. The prompt still ranks this BLOCKING by rule. The fix (atomicWrite + loadOrDegrade) needs an additive amendment to the closed import list in Spec-AC-12." }
      - { rank: BLOCKING, file: tests/skills/lib/suite-reuse.test.mjs, line: 296,
          issue: "Test name claims a universal negative ('every live manifest suite reads nothing inside the checkout outside its identity') but only asserts Node fs calls the read-trace.cjs preload wraps",
          failure_scenario: "None of these reads are traced: bash cat/grep/cp, git, fs.promises, fs.copyFileSync/cpSync, and any child whose environment drops NODE_OPTIONS (release-dry-run.mjs:16 cleanEnvironment removes it). Reviewer confirmed that fs/promises readFile and copyFileSync leave no line in the trace. A manifest suite that reads docs/x.md through bash cat passes TEST-3193. The analysis note at lines 146-149 repeats the overclaim ('a manifest entry that reads outside its identity fails the test'). Rename the test (e.g. 'no traced Node fs read ...') and list the untraced channels in the note." }
      - { rank: NON-BLOCKING, file: tests/skills/test-framework.sh, line: 1073,
          issue: "reuse_settle returns before forget whenever the check call failed (REUSE_HELPER_OK=false, 'OFF helper-failed'). D5 says forget runs on FAIL or SKIP in any local run",
          failure_scenario: "check throws once (git index lock, a malformed suite-map line), a recorded suite fails in that run, and its old pass record survives. When the suite failure was nondeterministic or time-dependent and its identity is unchanged, the next run with a working check reports REUSED although the last execution failed." }
      - { rank: NON-BLOCKING, file: .aai/SKILL_VERIFY.prompt.md, line: 19,
          issue: "'matched the complete input identity' claims more than the mechanism compares: static literal closure + globs + a reviewed manifest note (R1). It also links docs/product/precise-suite-evidence-reuse.md, which does not exist on the branch until close-out",
          failure_scenario: "A role reads 'complete' as a guarantee and does not read the cited log or question a REUSED line for a suite that has hole B1 or R1. Before close-out step 1 runs, the link from a core prompt is dead." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 186,
          issue: "The history marker is looked for only in tests/ files, and HISTORY_RE leaves out git branch / symbolic-ref / git status. Production scripts in the closure that read history do not set it (this matches D4 but is a false-hit class)",
          failure_scenario: "A future manifest suite runs node .aai/scripts/x.mjs, which calls git log -1 on the checkout. After a commit whose tree bytes equal the recorded ones (amend message, empty commit), the result is REUSE although the output would differ." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 139,
          issue: "A partial-prefix token such as .aai/scripts/aai-${x}.mjs, which is neither a file nor a directory, is recorded as one absent path instead of widening to a prefix match. Paths relative to SCRIPT_DIR outside lib/ (e.g. $SCRIPT_DIR/fixtures/x) are not followed",
          failure_scenario: "A suite loops over .aai/scripts/aai-${n}.mjs. Editing .aai/scripts/aai-foo.mjs gives REUSE. This is the R1 constructed-path residual, but a prefix fallback would close it cheaply and fail safe toward a miss." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 260,
          issue: "Records have no maximum age and the identity has no clock component",
          failure_scenario: "A suite with a real-clock staleness window or expiry date passes on day 1. Unchanged bytes keep giving REUSE weeks later, after the code would fail. The REUSED line does show finished_at." }
      - { rank: NON-BLOCKING, file: .aai/scripts/suite-reuse.mjs, line: 241,
          issue: "The args component is the helper's own constant default. The framework never passes the vector it actually runs (D4 says 'passed by the caller')",
          failure_scenario: "If the framework later passes a flag to suites (e.g. a filter), records made with and without the flag share one identity and one can be reused for the other." }
  cannot_verify:
    - { claim: "Native Windows parity (Pester under windows-5_1 / windows-wsl1, skip count unchanged)", closes_with: "post-PR H1: ps1-quality run on the PR head" }
    - { claim: "CI prints 'Evidence reuse: off (ci)' in every framework job and never reuses", closes_with: "post-PR H2: skill-suite run log on the PR head" }
    - { claim: "The five manifest notes are true for every read channel (bash, git, external tools such as jq/python versions, HOME dotfiles), not just traced Node fs calls", closes_with: "a syscall-level trace (fs_usage/strace) of each manifest suite, or a review of each suite's bash line by line, recorded per suite" }
    - { claim: "Role conduct: consumers read the cited log and never treat REUSED as the close-time sweep (R3)", closes_with: "observed behavior over future rides; TEST-3186 checks text only" }
    - { claim: "Measured wall times and check seconds in the analysis note", closes_with: "re-running D11 on the reviewed head; the reviewer did not re-measure" }
  overall: fail
```

security_relevant: false

## Scope and method

- Scope: `git diff main...HEAD` in worktree `/Users/ales/Projects/aai-worktrees/precise-suite-evidence-reuse` (STATE `worktree.user_decision: worktree`, base_ref main). The working tree has one unrelated uncommitted change: telemetry lines appended to `docs/ai/tests/test-runs.jsonl` by earlier rounds' runs. It is not part of the reviewed diff.
- Spec: the frozen draft spec plus its six amendments in decisions.jsonl. These cover the D4 glob narrowing (added, then reverted), the reworked measurement for Spec-AC-13, the mutation-cell escaping, and the reworked manifest and read trace for Spec-AC-08 / Spec-AC-02.
- Reviewer evidence: ran `test-aai-suite-reuse.sh` under `env -u AAI_ROLE AAI_SUITE_REUSE=0` once (rc 0, 30 PASS lines, 0 fail/skip, TEST-3184 Pester T=4 F=0 S=0). `suite-reuse.mjs lint` gave rc 0, `spec-lint` rc 0, and `mutation-gate` reported GATE PASS on 28 rows. The full sweep was not re-run; the r2 report cites 120/0/1.
- Reviewer probes, scratch only: (1) a fixture repo with the shipped helper, where suite `fx` reads `"$ROOT/docs"/probe.txt`. After a recorded pass, editing `docs/probe.txt` gave REUSE and adding `docs/new.txt` gave REUSE (B1). (2) `read-trace.cjs` preloaded on an ESM script. Named `import { readFileSync }` was traced (the facade binds the patched function). `fs/promises.readFile` and `copyFileSync` produced no trace line (B3).
- Coaching note (anti-gaming contract): the dispatch prompt told the reviewer where to focus and named "known gaps: fs.promises, stripped NODE_OPTIONS, non-node reads", which describes expected findings in advance. The reviewer recorded this and reviewed the full scope. B1 and B2 are outside the named areas.

## Spec-AC walk

See the `ac_walk` block. Deviations from the frozen spec, listed in full:

1. D4(d): bare directory literals for `.aai`, `tests` and `docs` are not tokens (B1). This makes the Spec-AC-02 clause "a file appears under a directory named by a test-side literal" non-compliant for that literal form.
2. D5: `forget` is skipped when the check call failed (N1).
3. D4 `args`: the framework does not pass the vector. The helper default equals today's vector (N5).
4. All six amendments are unsigned. They carry `owner_signoff: false`, and fu-amend-precise-suite-evidence-reuse is the open owner sign-off item. That is the documented additive-with-disclosure path, recorded here, not a finding.

## BLOCKING findings

- **B1 `.aai/scripts/suite-reuse.mjs:116`**: TOKEN_RE `(?:\.aai|tests|docs)\/...` requires a slash, so `"$ROOT/docs"`, `"$ROOT/.aai"` and `"$ROOT/tests"` name nothing. Proven false hit, see the scenario above. Suggested fix: also accept a bare top-level token when the character before it is `/`, as in `$ROOT/docs` and `"$X"/docs`. Plain prose "docs" stays excluded, and the over-inclusion fails safe toward a miss. Add the literal form to TEST-3167 or TEST-3192.
- **B2 `.aai/scripts/suite-reuse.mjs:308` (with 220-223)**: the store is a new gitignored sidecar with its own load and write code instead of the runtime-file primitives, which the code-review prompt makes BLOCKING. Use `atomicWrite` for the store and `loadOrDegrade`, treating `corrupt` as a miss. This needs an additive amendment of the Spec-AC-12 / TEST-3188 import list to allow `./lib/runtime-file.mjs`, with disclosure.
- **B3 `tests/skills/lib/suite-reuse.test.mjs:296`**: test name with a universal negative while it asserts only traced Node fs calls. The prompt says to rename it or prove the negative. Rename it, and correct `docs/analysis/precise-suite-evidence-reuse.md:146-149` to list the untraced channels: bash and git reads, fs.promises, copyFileSync/cpSync, and children that drop NODE_OPTIONS. Spec-AC-08 already says "a Node read trace", so the AC row itself is honest.

## NON-BLOCKING findings and recommended dispositions (H6)

| id | finding | recommended disposition |
|---|---|---|
| N1 | test-framework.sh:1073 forget skipped on helper-failed | remediate in tree: call forget whenever node and the helper exist (P3, a one-line change) |
| N2 | SKILL_VERIFY "complete input identity" overclaims; product-doc link is dead until close-out | remediate in tree: "matched the declared input identity (static closure, globs, reviewed manifest note)". Close-out step 1 must land the product doc before the PR. Bytes stay within the 600 B credit (P3) |
| N3 | history marker only looked for in tests/ texts and missing git branch/symbolic-ref | promote to follow-up `fu-reuse-history-marker-scope` (P3) |
| N4 | partial-prefix tokens and SCRIPT_DIR-relative non-lib paths not widened | promote to follow-up `fu-reuse-prefix-token-fallback` (P3), or fold into the B1 fix |
| N5 | args component not passed by the caller | accepted residual: today's vector is constant and equals the default; no bite seen and no false record (P3) |
| N6 | no record age bound / clock component | promote to follow-up `fu-reuse-record-max-age` (P3); a time-dependent suite can be reused stale |

INFO (does not gate): the two `[n/m]` numbering sequences (reused, executed) restart separately. `release-dry-run.mjs:219` uses `AAI_SUITE_REUSE: '0'` with a space where its neighbours use `KEY:'v'`. LIB_RE resolves `lib/<x>.mjs` mentions meant for `.aai/scripts/lib/` against `tests/skills/lib/`, which only adds harmless `absent` entries. Integration under `set -euo pipefail` and Bash 3.2 checked: empty arrays are guarded or unreachable (discovery exits 2 on zero suites), the `sed | qhead` pipe is SIGPIPE-safe, the percentage arithmetic is guarded for the all-reused TOTAL_TESTS=0 case, and suite_report (and so record) runs in the parent in both the serial and parallel paths. The REUSED metrics line and the isolation invariants match D7.

## cannot_verify

See the YAML block. The checks left open are the post-PR H1/H2 checks, read channels the Node trace cannot see, role conduct (R3), and the measured timings.

## Next steps

1. Remediation: fix B1 with a regression test (RED first), B2 with the Spec-AC-12 amendment, B3 by renaming the test and correcting the note, plus in-tree N1 and N2.
2. Orchestrator records the N3, N4 and N6 follow-ups and quotes the N5 accepted residual in `code_review.notes`.
3. Re-review after remediation: same single pass, selected suites plus CORE. No full sweep is needed for the review itself.

---
id: spec-release-checks-registration-grace
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 926bd9ee7229b20d9c9ee8330561a5075b81fb2fa2a46847c62d5805e80826f0
ceremony_level: 2
capability: release-command-finish
user_visible: false
links:
  requirement: release-checks-registration-grace
  rfc: null
  pr: []
  commits: []
---

# Release finish waits a bounded grace for required checks to register

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-release-checks-registration-grace.md
- Parent capability spec: docs/specs/SPEC-0233-spec-release-command-finish.md (Spec-AC-02: empty checks SHALL refuse before merge; this scope keeps that, after a bounded grace)
- Technology contract: docs/TECHNOLOGY.md
- Seam partner (read, not changed): .aai/scripts/watch-ci.mjs empty-list handling (an empty array is "not registered yet", polled until its deadline)

## Implementation strategy
- Strategy: tdd
- Rationale: a small behavior change on a fail-closed merge gate. Every new arm (late registration passes, never-registered refuses, terminal-bad refuses at once, post-watch stays strict, bad env refuses) must be observed RED on the pre-change tree first, and a mutation per row proves each assertion bites. The fixture harness in tests/skills/test-aai-release.sh already stubs gh deny-by-default, so RED-first costs little.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: one engine file plus its suite and one product doc; already isolated in its own worktree, decided at intake.
- User decision: worktree (already set: branch fix/release-checks-registration-grace, path /Users/ales/Projects/aai-fix-release-checks-registration-grace, base ac42210e)
- Base ref: main at ac42210e
- Inline review scope: .aai/scripts/release-finish.mjs tests/skills/test-aai-release.sh docs/product/release-command-finish.md CHANGELOG.md docs/specs/SPEC-DRAFT-release-checks-registration-grace.md docs/issues/ISSUE-DRAFT-release-checks-registration-grace.md
- Code review required: true

## Constitution deviations

None.

Article 7 is untouched: this ride changes when the release engine reads required checks; it adds no merge path, and the ride itself merges nothing.

## Measured fact that shapes the design (read by Planning, 2026-10-17)

The intake assumed gh reports "nothing registered yet" as an empty JSON array. Live gh 2.93.0 does not:

- `gh pr checks 1 --repo octocat/Hello-World --required --json name,bucket,link` exits 1, prints NOTHING on stdout and `no checks reported on the 'patch-1' branch` on stderr.
- `gh pr checks 217 --repo sindresorhus/is --required --json name,bucket` (the PR has one non-required check) exits 1, empty stdout, stderr `no required checks reported on the 'tgriesser/fix/is-class-minified' branch`.

So on the real transport the pre-watch read right after `gh pr create` refuses today as `github-checks` (`gh checks returned invalid JSON`), not as `required-checks`. The grace therefore recognizes TWO "not registered yet" shapes, and nothing else:

1. a JSON array of length 0 (the shape watch-ci.mjs and the existing fixture use), under any accepted transport status (0, 1, 8);
2. exit status 1 with stdout empty after trim and stderr, trimmed, matching exactly `^no (required )?checks reported on the '[^']*' branch$`.

Any other non-JSON output, any other exit status, and any non-empty list keep today's handling unchanged (strict, single parse, named refusal).

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable |
|-------------|---------|--------------|------------|
| Expected Behavior: tolerate a bounded registration window | Spec-AC-01 | R TEST-060, TEST-061 | release reaches watch-ci and merges once after 2 not-registered reads, for both transport shapes, with the default grace |
| Expected Behavior: refuse with a named reason if still empty | Spec-AC-02 | R TEST-062 | exactly one `REFUSED: required-checks` naming `No required checks registered within 1s`, at least 2 pre-watch polls, zero watch-ci polls, zero merges |
| Expected Behavior: failed checks still refuse immediately | Spec-AC-03 | R TEST-063 | exactly one pre-watch poll, then the existing named refusal, for a failed check and for an unrecognized non-JSON error |
| Constraints: do not weaken the post-watch settled check | Spec-AC-04 | R TEST-064 | an empty post-watch read refuses after exactly one post-watch poll, zero merges |
| Constraints: grace bounded and overridable | Spec-AC-05 | R TEST-065 | invalid `AAI_RELEASE_CHECKS_GRACE_SECONDS` refuses `arguments` before any PR exists |
| Operator docs | Spec-AC-06 | R TEST-066 | product doc names the variable and its default 60, and no longer lists the fixed gap |

R = `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh <selector>` with the selector named in the Test Plan row; exit 0 and a `PASS: TEST-06x` line decide each row.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the pre-watch required-checks read returns a not-registered shape (an empty JSON array, or gh exit 1 with empty stdout and stderr `no checks reported on the '<branch>' branch` or `no required checks reported on the '<branch>' branch`) the engine SHALL re-poll every AAI_RELEASE_POLL_SECONDS until a non-empty list appears or AAI_RELEASE_CHECKS_GRACE_SECONDS (default 60) elapses; with the variable unset and checks appearing on the third read it SHALL reach watch-ci, merge exactly once and exit 0 | planned | — | — | — |
| Spec-AC-02 | WHEN every pre-watch read inside the grace returns a not-registered shape the engine SHALL refuse exactly once with cause `required-checks` and detail `No required checks registered within <N>s` (N the configured grace), plus the existing resume line, without starting watch-ci and without any merge call | planned | — | — | — |
| Spec-AC-03 | WHEN the first pre-watch read returns a non-empty list holding a fail, cancel or skipping bucket, or a non-JSON output that is not the recognized gh not-registered shape, the engine SHALL refuse on that first read with today's cause (`required-checks` or `github-checks`) and SHALL NOT poll again | planned | — | — | — |
| Spec-AC-04 | WHEN watch-ci has exited 0 the post-watch required-checks read SHALL stay strict: an empty or not-registered result refuses `required-checks` after exactly one post-watch read and no merge call is made | planned | — | — | — |
| Spec-AC-05 | WHEN AAI_RELEASE_CHECKS_GRACE_SECONDS is set to a value that is not a finite number of at least 0 the engine SHALL refuse once with cause `arguments` before any gh pr create call | planned | — | — | — |
| Spec-AC-06 | docs/product/release-command-finish.md SHALL name AAI_RELEASE_CHECKS_GRACE_SECONDS with default 60 in its wait-limits line, and SHALL no longer list fu-release-checks-registration-grace as a known gap | planned | — | — | — |

## Implementation plan

Components: `.aai/scripts/release-finish.mjs` only (engine); `tests/skills/test-aai-release.sh` (fixture modes plus cases); `docs/product/release-command-finish.md`; one CHANGELOG entry at ship time. Both frontends (`aai-release.sh`, `aai-release.ps1`) only forward to the engine and inherit the environment, so no PS1 or bash frontend change and no parity code is needed; the existing TEST-033 PowerShell parity case keeps covering the forward.

1. Configuration. Next to `maxWait`/`interval` add `const checksGrace=Number(process.env.AAI_RELEASE_CHECKS_GRACE_SECONDS??60);` and extend the existing argument guard at the top of `main()` so that `!Number.isFinite(checksGrace)` or `checksGrace<0` refuses `arguments` (same message family as the wait guard). The guard runs before any gh mutation, which is what TEST-065 relies on.
2. Not-registered recognition inside `requiredChecks(allowEmpty=false)`. Before `JSON.parse`, when the transport status is 1, stdout trims to empty and trimmed stderr matches `/^no (required )?checks reported on the '[^']*' branch$/`, treat the result as an empty list. After parsing, an empty array keeps reaching the existing empty branch, which now returns the empty list when `allowEmpty` is true and otherwise refuses `required-checks` `No required checks reported` exactly as today. The status-8 and status-1 consistency checks keep running only on non-empty lists.
3. Grace loop. Add `function registeredChecks()` that computes `end=Date.now()+checksGrace*1000`, calls `requiredChecks(true)`, returns at once on a non-empty list via the literal statement `if(c.length)return c;`, refuses `required-checks` with the detail `No required checks registered within ${checksGrace}s` once `Date.now()>=end`, and otherwise sleeps `interval` seconds with the same `Atomics.wait` idiom `boundedPoll` uses. Grace 0 means exactly one read.
4. Call sites. The pre-watch line becomes `const required=registeredChecks();` and keeps its existing bucket refusal unchanged. The post-watch line stays the literal `const settled=requiredChecks();` (strict).
5. Mutation anchors. The Test Plan mutations below are written against the literal texts named in steps 1 to 4 (`AAI_RELEASE_CHECKS_GRACE_SECONDS??60`, `checksGrace<0`, `if(c.length)return c;`, `no (required )?checks reported`, `const settled=requiredChecks();`). Keep those spellings; renaming one obliges a recorded spec amendment of the matching Mutation cell.
6. Fixture. In `test_700_one_command_finish`'s fixture env add `AAI_RELEASE_CHECKS_GRACE_SECONDS:'0.2'` so the existing SPEC-0233 refusal modes (`missing-checks`, `pending-empty`) refuse quickly instead of polling 60 s. Add gh stub modes, counting only the engine's `--repo` reads (watch-ci's reads carry no `--repo`): `late-empty` (first two `--repo` reads print `[]` exit 0, then pass), `late-gh` (first read: stderr `no checks reported on the 'chore/release-v1' branch` exit 1 with empty stdout; second read: stderr `no required checks reported on the 'chore/release-v1' branch` exit 1; then pass), `never-gh` (always the second gh shape), `odd-error` (stderr `HTTP 502: Bad Gateway` exit 1, empty stdout), `skipped` (one `skipping` bucket, exit 0), `settle-empty` (first `--repo` read pass, every later `--repo` read `[]` exit 0; watch-ci reads pass).
7. Case wiring. Add node `check()` cases TEST-060 to TEST-066 that run ONLY when `RELEASE_FINISH_CASE` equals their id (not on `all`, so nothing runs twice), and bash selectors `test_704_grace_late_empty` (TEST-060), `test_705_grace_late_gh_shape` (TEST-061), `test_706_grace_never_registered` (TEST-062), `test_707_grace_terminal_bad_immediate` (TEST-063), `test_708_post_watch_strict` (TEST-064), `test_709_grace_env_invalid` (TEST-065), `test_710_grace_docs` (TEST-066), each `RELEASE_FINISH_CASE=TEST-06x test_700_one_command_finish`, registered in `main`'s list.
8. Docs. Product doc line 48: real pending waits, and a not-yet-registered list is re-read for a bounded grace before the empty refusal. Line 54: add `AAI_RELEASE_CHECKS_GRACE_SECONDS` defaults to 60. Line 62: drop the `fu-release-checks-registration-grace` clause, keep the heading-multiset gap. SKILL_RELEASE.prompt.md stays byte-identical (its "empty checks refuse" sentence remains true after the grace), so no prompt-diet ledger entry is owed.

Edge cases decided here: an empty array under exit 8 is treated as not registered (it was refused as empty before; it still refuses after the grace, so SPEC-0233 TEST-010 `pending-empty` keeps passing). The grace and poll interval are independent of `AAI_RELEASE_WAIT_SECONDS`; the refusal can come up to one interval after the grace ends (bound: grace + interval + one read).

## Seams

- release-finish to watch-ci: the grace hands over only once a non-empty required list exists; TEST-060 and TEST-061 assert that watch-ci's own reads (the argv without `--repo`) happened and that the merge followed, so the hand-off is crossed with the real watch-ci.mjs process, not mocked.
- release-finish to gh: the not-registered shapes are the live gh 2.93.0 bytes recorded above, replayed by the stub; TEST-063's `odd-error` arm proves that recognition is the exact phrase and not any exit-1 failure.
- SPEC-0233 regression: its TEST-010 modes `missing-checks` and `pending-empty` must still end in one refusal and zero merges with the new fixture grace.
- Residual risk (no automated test can cross it): GitHub's real registration latency and gh's message wording in future gh versions. A changed wording falls back to today's `github-checks` refusal (fail-closed, resume still works). watch-ci.mjs itself degrades on the real gh not-registered shape; this scope does not change watch-ci because the grace guarantees a registered list before watch-ci starts. suggested: fu-watch-ci-gh-no-checks-shape.

Registry items closed by this scope: fu-release-checks-registration-grace.

Registry items with the same capability left open (different subjects, not touched): fu-release-notes-heading-multiset, fu-aai-update-guard-test-isolation, fu-release-ps1-origin-check-ps51-test, fu-amend-spec-release-command-finish, fu-release-ps-liveness-empty-output, fu-release-unnumbered-merge-content, fu-release-nested-merge-test, fu-release-pr-lookup-failure-cause, fu-release-issue-ref-as-pr.

Hash pins: none. A repo-wide search for the sha256 of release-finish.mjs (016d6aee...) found no pin, so no re-pin step is owed.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-060 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | test_704_grace_late_empty: fixture mode late-empty with AAI_RELEASE_CHECKS_GRACE_SECONDS deleted from the env; exit 0, one merge, at least 3 engine --repo reads, at least one watch-ci read, no REFUSED line | sed:s/AAI_RELEASE_CHECKS_GRACE_SECONDS\?\?60/AAI_RELEASE_CHECKS_GRACE_SECONDS??0/ | green |
| TEST-061 | Spec-AC-01 | integration | tests/skills/test-aai-release.sh | test_705_grace_late_gh_shape: fixture mode late-gh (live gh 2.93.0 stderr shapes, empty stdout, exit 1), grace 5 s, poll 0.01 s; exit 0, one merge, at least 3 engine --repo reads, at least one watch-ci read | sed:s/no \(required \)\?checks reported/no required checks reported/ | green |
| TEST-062 | Spec-AC-02 | integration | tests/skills/test-aai-release.sh | test_706_grace_never_registered: modes missing-checks and never-gh, grace 1 s, poll 0.05 s; nonzero exit, exactly one REFUSED line naming required-checks and No required checks registered within 1s, the resume line, at least 2 engine --repo reads, zero watch-ci reads, zero merges | sed:s/if\(c\.length\)return c;/return c;/ | green |
| TEST-063 | Spec-AC-03 | integration | tests/skills/test-aai-release.sh | test_707_grace_terminal_bad_immediate: modes ci (fail), skipped and odd-error, grace 2 s, poll 0.05 s; one REFUSED line each (required-checks naming the bucket, or github-checks for odd-error), exactly one engine --repo read, zero merges | sed:s/if\(c\.length\)return c;/if(c.length&&c.every(x=>x.bucket==='pass'))return c;/ | green |
| TEST-064 | Spec-AC-04 | integration | tests/skills/test-aai-release.sh | test_708_post_watch_strict: mode settle-empty, grace 1 s, poll 0.01 s; one REFUSED required-checks line, exactly 2 engine --repo reads in total, at least one watch-ci read, zero merges | sed:s/const settled=requiredChecks\(\);/const settled=registeredChecks();/ | green |
| TEST-065 | Spec-AC-05 | integration | tests/skills/test-aai-release.sh | test_709_grace_env_invalid: grace values -1 and abc on the default passing fixture; one REFUSED arguments line each, zero pr create calls, no release PR in the transport | sed:s/checksGrace<0/checksGrace<-1/ | green |
| TEST-066 | Spec-AC-06 | contract | tests/skills/test-aai-release.sh | test_710_grace_docs: product doc contains AAI_RELEASE_CHECKS_GRACE_SECONDS and the default 60 on the wait-limits line, and does not contain fu-release-checks-registration-grace | sed:s/AAI_RELEASE_CHECKS_GRACE_SECONDS/AAI_RELEASE_CHECKS_WAIT/ | green |

Mutation targets: TEST-060 to TEST-065 mutate `.aai/scripts/release-finish.mjs`; TEST-066 mutates `docs/product/release-command-finish.md`. Patterns are JavaScript RegExp as `mutation-run.mjs --sed` reads them.

## Verification

- RED first: on the pre-change engine (tests and fixture modes added, engine untouched) run each selector; TEST-060 to TEST-062 and TEST-065 to TEST-066 must fail (TEST-060 refuses `No required checks reported`; TEST-061 refuses `github-checks`; TEST-062 names the wrong detail and polls once; TEST-065 proceeds and creates a PR; TEST-066 finds no variable). TEST-063 and TEST-064 guard existing behavior and may already pass before the change; their RED proof is the mutation record, not the pre-change run. Record each observation in docs/ai/tdd/release-checks-registration-grace-red.log.
- GREEN: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh test_704_grace_late_empty` and the same for test_705 to test_710, each exit 0 with its `PASS: TEST-06x` line, logged to docs/ai/tdd/release-checks-registration-grace-green.log.
- Mutations: `node .aai/scripts/mutation-run.mjs --spec <this spec> --test-id TEST-06x --suite tests/skills/test-aai-release.sh --selector <row selector> --target <row target> --sed '<row pattern>'` per row, each verdict RED; then `node .aai/scripts/mutation-gate.mjs --spec <this spec>` exit 0.
- Regression: `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-release.sh` exit 0 (whole suite, including SPEC-0233 TEST-010 refusal modes and TEST-033 PowerShell parity), plus `bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-framework.sh --skill aai-release --skill aai-learned-routing` exit 0 (the learned-routing suite copies release-finish.mjs into fixtures).
- Docs: `node .aai/scripts/spec-lint.mjs --path <this spec>` exit 0; `node .aai/scripts/docs-audit.mjs --strict` before close.

## Evidence contract

- ref_id release-checks-registration-grace; for each TEST-06x: the exact command, exit code, the `PASS:` line or the failing assertion, and the transport call counts the test asserted.
- RED observations: docs/ai/tdd/release-checks-registration-grace-red.log. GREEN runs: docs/ai/tdd/release-checks-registration-grace-green.log. Mutation records: docs/ai/tdd/spec-release-checks-registration-grace/mutation-TEST-06x.txt (written by mutation-run.mjs).
- The diff range against ac42210e and the head commit SHA at validation.
- Planning claims no PASS; the verdict belongs to Validation.

### Evidence by strategy

tdd: stored RED artifact per AC-gating test (docs/ai/tdd/) plus the verification matrix above.

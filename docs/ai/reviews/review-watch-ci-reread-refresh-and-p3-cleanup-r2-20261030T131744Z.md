# Code Review r2 — watch-ci-reread-refresh-and-p3-cleanup

```yaml
review:
  scope: git diff 7d38415a...HEAD (HEAD d9a9eddf, branch fix/watch-ci-reread-refresh-and-p3-cleanup); delta since r1 659cc859..d9a9eddf
  spec: docs/specs/SPEC-0262-spec-watch-ci-reread-refresh-and-p3-cleanup.md
  spec_compliance:
    verdict: pass
    ac_walk:
      - { ac: Spec-AC-01, call: compliant, citation: ".aai/scripts/lib/github-checks.mjs:169-201 (unchanged since r1); TEST-2931 green locally (r2 run)" }
      - { ac: Spec-AC-02, call: compliant, citation: "github-checks.mjs (unchanged since r1); TEST-2932 three arms green locally" }
      - { ac: Spec-AC-03, call: compliant, citation: "github-checks.mjs:144-176; TEST-2933, TEST-2934, new TEST-2939 green locally; mutation-TEST-2939.txt RED; red-test-2939.log baseline RED" }
      - { ac: Spec-AC-04, call: compliant, citation: "TEST-2711 code unchanged; full test-aai-current-head-ci.sh rc=0 locally with 15 cases" }
      - { ac: Spec-AC-05, call: compliant, citation: ".aai/SKILL_PR.prompt.md unchanged since r1; TEST-2935 (validation r4 PASS)" }
      - { ac: Spec-AC-06, call: compliant, citation: "tests/skills/lib/prompt-diet-ledger.sh unchanged since r1; TEST-2936 (validation r4 PASS)" }
      - { ac: Spec-AC-07, call: compliant, citation: "tests/skills/test-aai-spec-amend.sh:5564-5572 now passes list output by file; TEST-2937 green locally; Linux node:22-slim rc=0 (VALIDATION r3 linux-argv log)" }
      - { ac: Spec-AC-08, call: compliant, citation: "decisions.jsonl follow_up_status closes unchanged since r1; TEST-2938 (validation r4 PASS)" }
  code_quality:
    verdict: pass
    findings: []
  cannot_verify:
    - { claim: "Real GitHub ordering between run cancellation, the check-run conclusion, the run-level conclusion and the run list matches the stub's sequencing", closes_with: "a live observation of a cancel-in-progress pair on a real PR (carried from r1)" }
    - { claim: "A re-run (same run id, new run_attempt) between the two reads produces check-runs whose ids order after attempt 1 under filter=all (the premise TEST-2939 encodes with id 6 > id 2)", closes_with: "a live re-run observation or GitHub API documentation of check-run id monotonicity across attempts (carried from r1)" }
    - { claim: "The branch passes the skill suites in CI on ubuntu/macOS/Windows", closes_with: "green CI on the PR (the B-1 fix is reproduced under node:22-slim only, not on the real runner)" }
  overall: pass
```

security_relevant: false

## Scope

- Diff `git diff 7d38415a...HEAD`, HEAD d9a9eddf; focus on delta `659cc859..d9a9eddf` (c862255c, d9a9eddf).
- STATE `worktree.user_decision: worktree`; working tree carries only telemetry (EVENTS.jsonl, test-runs.jsonl), outside the scope.
- Product code unchanged since r1: `git diff --stat 659cc859..HEAD -- .aai` is empty.
- Delta files: tests/skills/test-aai-spec-amend.sh, tests/skills/lib/current-head-ci.test.mjs, tests/skills/test-aai-current-head-ci.sh, the spec (A3, A4, TEST-2939 row, AC-03 evidence cell, frozen_sha256 restamp), decisions.jsonl (+2 spec_amendment), EVENTS.jsonl (+18), r1 review report (staged per H4).
- Anti-gaming note: the dispatch named focus areas without pre-rating severity or excluding areas. I reviewed the full scope.

## B-1 closure (TEST-2937 argv size)

- :5565-5566 redirect both `spec-amend list --json` outputs to `$scratch/with.json` / `$scratch/without.json`; :5567-5572 `node -e` reads them with `fs.readFileSync`. No large values in argv now. The only argv items are two paths.
- The other `node -e` in the test (:5549-5563) takes `$led` and a path. No large-argv pattern remains.
- Local run `test-aai-spec-amend.sh test_2937_...` rc=0. Validation r3 log `VALIDATION-...-r3-linux-argv.log` shows the c862255c version rc=0 under node:22-slim (Linux 7.0.14).
- Under `set -euo pipefail` (:47), a failing `node list > file` aborts the suite. That is the same behaviour as the r1 `$(...)` assignment, so it is not new. INFO.
- Closed.

## NB-1 closure (D3 test) and TEST-2939 quality

- The test is at current-head-ci.test.mjs:498-521. Run W's workflowSeq goes cancelled to in_progress. Its attempt-2 check (id 6, pending) appears on the re-read. Run Y, completed and newer in workflow 5, carries no build check. If W were treated as cancelled, Y would supersede it and drop its checks.
- It discriminates D3:
  - Mutation `nowCancelled=cancelledRuns` reds it with `required context missing from current head: build` (mutation-TEST-2939.txt, rc 1, selector honoured).
  - Base 7d38415a reds it the same way (red-test-2939.log).
- The assertion that bites is the `/pending/` match plus `build.bucket === 'pending'` in the release reader. `w.status === 3` alone would not discriminate, because degraded is also 3. The test has both, so this is fine.
- It is pipefail-safe. It is a node:test case, wired as `run_case TEST-2939` with a selector and an ALL_TESTS entry. No shell pipes were added.
- INFO, not a finding: midFixture's run list still holds W as `cancelled` (the local `wCancelledRun`), while the refreshed record says in_progress. The reader decides from the refreshed record, so the verdict is unaffected. Real ordering (refresh before list) would show in_progress in the list.

## A3/A4 disclosure vs ledger

- A3 ledger record (12:50:06Z, class measurement, no tracked_by) says it adds the TEST-2939 row and fixes the A1 actor label. The spec text matches: the TEST-2939 row was added and A1 now says `orchestrator`.
- c862255c's A3 prose and RED-plan line said TEST-2939 passes on baseline and has no baseline RED. That was false.
- A4 ledger record (13:03:47Z, measurement) and the A4 prose correct this. The RED-plan line now cites the baseline failure, and the AC-03 Evidence cell cites red-test-2939.log. The A3 prose now reads "its baseline RED is red-test-2939.log (see A4)".
- Disclosure is accurate and consistent with the ledger and the evidence files.
- Measurement-class records need no tracked_by (spec-amend.mjs:67, 189). `spec-amend list --strict` rc=0.

## Pattern checks

- No new argv-size pattern.
- No new early-closing reader (`| head`, `grep -q` on a pipe) in the delta.
- `git ls-files -ci --exclude-standard` is empty, so no gitignored evidence is committed.

## Findings and dispositions

- No BLOCKING or NON-BLOCKING findings this round.
- r1 B-1: remediated in tree (c862255c).
- r1 NB-1: remediated in tree (c862255c TEST-2939, A3/A4).
- INFO from r1: the CHANGELOG entry (D10) is still for the PR ceremony, where release-notes-gate enforces it.

## Next steps

1. The orchestrator records code_review pass (commands returned to the orchestrator).
2. PR ceremony: CHANGELOG entry per D10, then CI green on the PR closes the CI cannot_verify item.

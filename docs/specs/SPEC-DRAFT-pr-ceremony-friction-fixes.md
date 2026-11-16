---
id: spec-pr-ceremony-friction-fixes
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: 5bb1e4af75bb4b628aa36c4976e7ef750c5059a9bc2bbe75a378bf52132583ba
ceremony_level: 3
links:
  requirement: pr-ceremony-friction-fixes
  rfc: null
  pr: []
  commits: []
---

# Evidence files are judged by content, and the base sync refuses an uncommitted tree

SPEC-FROZEN: true

## Links

- Requirement: docs/issues/ISSUE-DRAFT-pr-ceremony-friction-fixes.md
  (GitHub issues #565 and #566, downstream friction reports).
- Prior scopes this one builds on (closed, not edited):
  docs/specs/SPEC-0279-spec-pre-commit-checks-ps1-retire.md (the bash checks
  without early-closing readers, the retired PowerShell launcher, TEST-3454
  baseline parity and TEST-3461 line counts);
  docs/specs/SPEC-0070-spec-branch-per-work-item-hygiene.md (branch-guard.mjs).
- Technology contract: docs/TECHNOLOGY.md (Node stdlib only, bash 3.2 suites
  through `.aai/scripts/aai-run-tests.sh`).

## Implementation strategy

- Strategy: tdd
- Rationale: a guard change on an L3 surface (`pre-commit-checks.sh`) and a
  new deterministic refusal in `branch-guard.mjs`. Every behaviour that
  changes can be seen failing on the unchanged tree (the evidence name is
  blocked, the content scan reads the working tree, `--sync-ready` is an
  unknown flag); the behaviours that must NOT change are pinned by mutation.

## Isolation and review

- Worktree recommendation: required
- Worktree rationale: L3 protected surface (`.aai/scripts/pre-commit-checks.sh`
  is listed in `protected_paths_l3`); the main checkout carries other
  sessions' uncommitted files.
- User decision: worktree (owner directive in the dispatch brief)
- Base ref: main
- Worktree branch/path: fix/pr-ceremony-friction-fixes at
  /Users/ales/Projects/aai-worktrees/pr-ceremony-friction-fixes
- Inline review scope: n/a (worktree); review scope is the branch diff
  against origin/main.

## Decisions

- D1 (CHECK 2 content scan reads the staged blob). The content scan of each
  staged file that still exists in the working tree reads `git show :<path>`
  (the bytes the commit records), not the working-tree file. The evidence
  folders below rely on the content scan alone, so it must judge what is
  committed. The pattern is unchanged. The read consumes the whole stream
  (`grep -c`), never an early-closing reader under pipefail.
- D2 (evidence folders are judged by content). A staged path under
  `docs/ai/reports/`, `docs/ai/tdd/`, `docs/ai/validation/` or
  `docs/ai/reviews/` skips the name check, except a dotenv basename (`.env`
  or `.env.*`), which is blocked in every folder. These four are the AAI
  evidence folders: the first three are the LOCAL EVIDENCE folders named in
  VALIDATION, SKILL_TDD and SKILL_PR, the fourth is the review evidence
  folder (`.aai/system/DOCS_AI_CANON.list`). Every other path keeps the name
  check byte for byte: `*.env*`, `*credentials*`, `*secret*`.
- D3 (sync refusal is a script, not prose). `branch-guard.mjs --sync-ready
  [--pre-commit-head <sha>]` is a read-only mode: exit 9 while
  `git diff --cached` names any path (stderr lists the paths), exit 10 while
  HEAD equals the resolved `--pre-commit-head` commit (the commit step did not
  advance HEAD), exit 4 on a usage error (not a work tree, an unresolvable
  sha), else exit 0. Staged changes are checked first. It never writes.
  Unstaged edits are not refused: `git merge` already refuses when they
  would be overwritten, and tracked telemetry (test-runs.jsonl) is routinely
  dirty during a ride.
- D4 (wiring). SKILL_PR step 4 notes `git rev-parse HEAD` as the
  pre-commit head before committing; step 5b runs `--sync-ready` before any
  `git merge` of base and stops on non-zero. The flag is dropped on a later
  sync where this session ran no commit step. VALIDATION step 6 gains one
  sentence: evidence file names never carry `secret`, `credential` or `.env`.
- D5 (PowerShell). `.aai/scripts/pre-commit-checks.ps1` is a retired
  launcher that checks nothing (SPEC-0279), so there is no twin to change.
  The parity harness that exists for this script is TEST-3454 (baseline
  parity over seven fixtures); its fixtures stay byte-identical with the
  baseline, and only its diff-size pin moves.

## Acceptance Criteria Mapping

- Spec-AC-01 maps to #565 (the reported case): evidence names pass.
- Spec-AC-02 maps to #565 (keep the content scan everywhere) and D1.
- Spec-AC-03 maps to #565 (do not weaken the block elsewhere).
- Spec-AC-04 and Spec-AC-05 map to #566 (deterministic refusal).
- Spec-AC-06 maps to #566 (prompt calls the script) and #565 (evidence names).
- Spec-AC-07 maps to the prompt-corpus governance and the moved pins.

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---|---|---|---|---|---|
| Spec-AC-01 | WHEN a file named worker-env-and-secrets.txt or db-credentials-check.log holding only environment variable names is staged under each of docs/ai/reports, docs/ai/tdd, docs/ai/validation and docs/ai/reviews, bash .aai/scripts/pre-commit-checks.sh SHALL exit 0 and print no Sensitive file staged line, and git commit through the installed hook SHALL create the commit | done | TEST-3831 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3831_evidence_names_pass.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3831_evidence_names_pass.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3831.txt | — | D2; the reported case |
| Spec-AC-02 | WHEN a file under docs/ai/validation is staged holding a line api_key = followed by a quoted 12-character value and its working-tree copy is then rewritten without it, the script SHALL exit 1 and print Potential secret detected in that path; the same holds for app/config.txt outside the evidence folders | done | TEST-3832 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3832_content_scan_reads_staged_blob.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3832_content_scan_reads_staged_blob.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3832.txt | — | D1 |
| Spec-AC-03 | WHEN any of .env, .env.local, config/credentials.json, keys/secret.key, docs/ai/validation/.env or docs/ai/tdd/.env.prod is staged with harmless content, the script SHALL exit 1 and print Sensitive file staged followed by that path | done | TEST-3833 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3833_sensitive_names_still_blocked.log, preservation case green on the base tree, RED by mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3833.txt | — | D2; preservation |
| Spec-AC-04 | WHEN node .aai/scripts/branch-guard.mjs --sync-ready runs in a work tree whose index holds a staged change, it SHALL exit 9, name the staged path on stderr, and leave the index and HEAD unchanged | done | TEST-3834 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3834.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3834.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3834.txt | — | D3 |
| Spec-AC-05 | WHEN --sync-ready runs on a clean index with --pre-commit-head equal to HEAD it SHALL exit 10; after a commit advances HEAD it SHALL exit 0; on a clean index without the flag it SHALL exit 0; with an unresolvable --pre-commit-head it SHALL exit 4 | done | TEST-3835 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3835.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3835.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3835.txt | — | D3 |
| Spec-AC-06 | .aai/SKILL_PR.prompt.md step 4 SHALL note the pre-commit head and step 5b SHALL run branch-guard.mjs --sync-ready before any git merge and stop on non-zero; .aai/VALIDATION.prompt.md step 6 SHALL say evidence file names never carry secret, credential or .env | done | TEST-3836 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3836.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3836.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3836.txt | — | D4 |
| Spec-AC-07 | The prompt growth SHALL be credited 1:1 by one prompt-diet ledger entry with the TEST-012 pin and the pr-preflight SKILL_PR growth sum moved to match, and the pre-commit suite pins (TEST-3454 diff size, TEST-3461 line counts) SHALL name the new measured values; the four suites SHALL exit 0 | done | TEST-3837 green docs/ai/tdd/pr-ceremony-friction-fixes/green-test_3837.log, RED docs/ai/tdd/pr-ceremony-friction-fixes/red-test_3837.log, mutation docs/ai/tdd/spec-pr-ceremony-friction-fixes/mutation-TEST-3837.txt; suites docs/ai/tdd/pr-ceremony-friction-fixes/green-prompt-diet-suite.log, docs/ai/tdd/pr-ceremony-friction-fixes/green-pr-preflight-suite.log, docs/ai/tdd/pr-ceremony-friction-fixes/green-pre-commit-suite.log | — | governance |

## Implementation plan

- `.aai/scripts/pre-commit-checks.sh` CHECK 2: content scan through
  `git show ":$file" | grep -cEi` (D1); a `case` on the path prefix that
  skips the name check for the four evidence folders unless the basename is
  a dotenv file (D2).
- `.aai/scripts/branch-guard.mjs`: `--sync-ready` and `--pre-commit-head
  <sha>` flags, a `checkSyncReady(cwd, preHead)` function, exit codes 9 and
  10 added to the header's closed set (D3).
- `.aai/SKILL_PR.prompt.md` steps 4 and 5b; `.aai/VALIDATION.prompt.md`
  step 6 (D4).
- Pins: `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh` (TEST-012),
  `tests/skills/test-aai-pr-preflight.sh` (TEST-008 growth sum),
  `tests/skills/test-aai-pre-commit-checks.sh` (TEST-3454, TEST-3461).
- `CHANGELOG.md`: one `## [unreleased] — <title>` entry.
- Seams: the installed pre-commit hook runs the changed script on a real
  `git commit` (TEST-3831 commits through it); SKILL_PR is the only caller of
  `--sync-ready` (TEST-3836 pins the wiring).
- Edge cases: a staged deletion is skipped as today (`[ -f ]`); a dotenv
  file inside an evidence folder stays blocked; a path that merely contains
  an evidence folder name deeper down (`src/docs/ai/tdd/secret.txt`) is not
  an evidence path (the prefix is anchored at the repository root).

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---|---|---|---|---|---|---|
| TEST-3831 | Spec-AC-01 | integration | tests/skills/test-aai-pre-commit-checks.sh | fixture repo; for each of the four evidence folders stage worker-env-and-secrets.txt and db-credentials-check.log holding API_BASE_URL and DB_NAME; run the checks: exit 0, zero Sensitive file staged lines; install the hook, commit on a branch: exit 0 and HEAD moves | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/docs\/ai\/reviews\/\*\) name_check=0 ;;/docs\/ai\/reviews\/*) name_check=1 ;;/` removes the evidence exemption and the case must fail | green |
| TEST-3832 | Spec-AC-02 | integration | tests/skills/test-aai-pre-commit-checks.sh | stage docs/ai/validation/run.txt and app/config.txt each holding an assembled api_key assignment, then overwrite both working-tree copies with a clean line: exit 1 and one Potential secret detected line per path | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/git -C "\$PROJECT_ROOT" show ":\$file"/cat "$filepath"/` reads the working tree again and the case must fail | green |
| TEST-3833 | Spec-AC-03 | integration | tests/skills/test-aai-pre-commit-checks.sh | one fixture per path (.env, .env.local, config/credentials.json, keys/secret.key, docs/ai/validation/.env, docs/ai/tdd/.env.prod) staged with the line harmless: exit 1 and Sensitive file staged followed by the path | target `.aai/scripts/pre-commit-checks.sh`; `sed:s/\.env\.\*\) name_check=1 ;;/.NOMATCH) name_check=1 ;;/` lets a dotenv file in an evidence folder through and the case must fail | green |
| TEST-3834 | Spec-AC-04 | integration | tests/skills/test-aai-branch-guard.sh | fixture repo with one commit; stage a.txt; run --sync-ready: exit 9, stderr names a.txt; git diff --cached --name-only and HEAD unchanged | target `.aai/scripts/branch-guard.mjs`; `sed:s/if \(staged\.length > 0\)/if (false)/` lets a staged tree through and the case must fail | green |
| TEST-3835 | Spec-AC-05 | integration | tests/skills/test-aai-branch-guard.sh | clean fixture: --sync-ready --pre-commit-head HEAD sha exits 10; commit a change, same sha exits 0; no flag exits 0; --pre-commit-head deadbeef exits 4 | target `.aai/scripts/branch-guard.mjs`; `sed:s/if \(head === pre\)/if (false)/` lets an unadvanced HEAD through and the case must fail | green |
| TEST-3836 | Spec-AC-06 | unit | tests/skills/test-aai-branch-guard.sh | SKILL_PR step 4 holds the pre-commit head line, step 5b holds branch-guard.mjs --sync-ready before its first git merge mention; VALIDATION step 6 holds the evidence-name sentence | target `.aai/SKILL_PR.prompt.md`; `sed:s/branch-guard.mjs --sync-ready/branch-guard.mjs --sync-skip/` unwires the refusal and the case must fail | green |
| TEST-3837 | Spec-AC-07 | unit | tests/skills/test-aai-prompt-diet.sh | one JUSTIFIED_ADDITIONS entry with ref field pr-ceremony-friction-fixes whose byte count equals the measured growth of SKILL_PR and VALIDATION against the base commit | target `tests/skills/lib/prompt-diet-ledger.sh`; `sed:s/"(\d+) pr-ceremony-friction-fixes /"1$1 pr-ceremony-friction-fixes /` inflates the credit and the case must fail | green |

## Verification

- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pre-commit-checks.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-branch-guard.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-prompt-diet.sh`
- `env -u AAI_ROLE -u AAI_GIT_WRITE bash .aai/scripts/aai-run-tests.sh bash tests/skills/test-aai-pr-preflight.sh`
- `node .aai/scripts/mutation-run.mjs --replay --spec <this spec>`
- One full sweep before close (`tests/skills/test-framework.sh`).
- PASS criteria: all TEST-xxx green and every Spec-AC terminal.

## Evidence contract

Per artifact: ref_id `pr-ceremony-friction-fixes`, Spec-AC and TEST-xxx,
command, exit code, evidence path under `docs/ai/tdd/pr-ceremony-friction-fixes/`
(RED and GREEN logs) and `docs/ai/tdd/spec-pr-ceremony-friction-fixes/`
(mutation records), commit SHA once committed.

Registry items closed by this scope: none

## Residual risks

- A downstream project whose evidence lives outside the four folders keeps
  the name check; the VALIDATION sentence is the only defence there.
- `--sync-ready` is only as good as the agent calling it; SKILL_PR is prose.
  The refusal is deterministic once called.

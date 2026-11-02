---
id: spec-suite-select-sigpipe-fix
type: spec
number: null
status: implementing
mutation_gate: v1
frozen_sha256: d12a90a3c63135283eceb930984991a084eccc21fa3d605ecaf59da561664438
ceremony_level: 1
links:
  requirement: suite-select-sigpipe-fix
  rfc: null
  pr: []
  commits: []
---

# Weights-header readers in the suite-select suite consume all their input

SPEC-FROZEN: true

## Links
- Requirement: docs/issues/ISSUE-DRAFT-suite-select-sigpipe-fix.md
- Technology contract: docs/TECHNOLOGY.md
- Follow-up closed at delivery: `fu-suite-select-sigpipe-test016` (the delivery commit or the close ceremony appends its `follow_up_status` done line, resolved by this ref).
- Follow-up filed by this ride: `fu-pipefail-early-readers-other-suites`.

Ceremony justification: test-only change inside one internal suite (tests/skills/test-aai-suite-select.sh, not shipped downstream); no script, state engine, allocator, guard or workflow canon file is touched and no protected_paths_l3 surface is involved; fully reversible. Independent Validation and code review remain required.

## Implementation strategy
- Strategy: tdd
- Rationale: the defect is a timing race that only a deterministic reproduction shows. The RED is the exact pipeline under pipefail with SIGPIPE ignored (the CI runner's semantics, printf gets EPIPE not signal 141) and a header larger than a pipe buffer.

## Isolation and review
- Worktree recommendation: optional
- Worktree rationale: main checkout is shared with other sessions and carries an unrelated uncommitted change.
- User decision: worktree
- Base ref: main (9717801a)
- Worktree branch/path: fix/suite-select-sigpipe-fix at /Users/ales/Projects/aai-worktrees/suite-select-sigpipe-fix
- Inline review scope: tests/skills/test-aai-suite-select.sh, docs/issues/ISSUE-DRAFT-suite-select-sigpipe-fix.md, docs/specs/SPEC-DRAFT-suite-select-sigpipe-fix.md, docs/ai/decisions.jsonl
- Code review required: true.

## Scope
In scope: the three weights-header extractions in `test_1760_weights_provenance` (TEST-016) move to helpers `_weights_header_run`, `_weights_header_jobs`, `_weights_header_sha`. Each feeds the header by here-string and uses awk with a seen flag instead of `exit`, so no reader closes early; every assertion in TEST-016 and its values are unchanged. Two new tests: TEST-3280 (behavior under ignored SIGPIPE) and TEST-3281 (static guard: no pipeline in the suite feeds an early-exiting awk, head, grep -q or sed q).

Audit of the rest of the file: the other pipes (`grep -c .`, awk over files, `sed -n ...q` over a file, `awk ... END {exit}` which reads all input, `awk 'NR==1 ...'` which reads all input) are safe and unchanged.

Out of scope (listed, not fixed), follow-up `fu-pipefail-early-readers-other-suites`:
- tests/skills/test-aai-ride-select.sh:610-612 (`printf | awk ... exit`)
- tests/skills/test-aai-validator-isolation.sh:119-123 (`printf | awk ... exit`)
- tests/skills/test-aai-merge-cleanup.sh:3254, 3676 (`printf | awk ... exit`)
- tests/skills/test-aai-ci-carry-forward.sh:534, 587, 588, 592 (`job_run_text ... | awk '... { exit } ...'`, no semicolon before exit; follow-up `fu-pipefail-early-readers-carry-fwd`)
- tests/skills/test-aai-sync-seed.sh:903, 905 and tests/skills/lib/assert-payload.sh, test-aai-pipe-safe.sh: `qgrep -q` pipe-safe helper sites, listed for completeness, not defects.

Decisions:
- D1: here-strings over `|| true`, because `|| true` would also mask a real reader failure.
- D2: TEST-3281 matches `;` followed by `exit` inside an awk program, so `END {exit ...}` (reads all input) is not flagged.
- D3 (validation r1 B3): TEST-3281 anchors on a single `|` (not `||`), accepts a path prefix and flag clusters on grep (`-E -q`, `--quiet`), `sed ...q`, `head`, and `exit` in a non-END awk action with or without a semicolon; a here-doc of positive and negative probe lines proves the pattern before the scan.

## Acceptance Criteria Mapping

| Requirement | Spec-AC | Verification | Observable and evidence |
|-------------|---------|--------------|-------------------------|
| Expected: readers survive EPIPE class | Spec-AC-01 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_3280_header_readers_survive_ignored_sigpipe` | exit 0; the three helpers return run, job count and SHA of a 200000-line header under pipefail with SIGPIPE ignored |
| Expected: no early-closing reader remains in the file | Spec-AC-02 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_3281_no_early_closing_reader_in_suite` | exit 0; no pipe-fed early-exiting reader in the suite |
| Assertions keep their meaning | Spec-AC-03 | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_1760_weights_provenance` and the full suite | exit 0 |

## Constitution deviations

None.

## Acceptance Criteria Status

| Spec-AC | Description | Status | Evidence | Review-By | Notes |
|---------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | WHEN the weights header is larger than a pipe buffer and SIGPIPE is ignored under pipefail, THEN the header readers SHALL return the right run id, job count and head SHA. | done | docs/ai/tdd/suite-select-sigpipe-fix-red.log; docs/ai/tdd/suite-select-sigpipe-fix-green.log | — | TEST-3280 |
| Spec-AC-02 | The suite SHALL contain no pipeline feeding an early-exiting awk, head, grep -q or sed q. | done | docs/ai/tdd/suite-select-sigpipe-fix-red.log; docs/ai/tdd/suite-select-sigpipe-fix-green.log | — | TEST-3281 |
| Spec-AC-03 | TEST-016 SHALL assert the same things as before (run id differs from the previous seed, four job ids, a 40-hex head SHA that differs from the previous seed, balance bound). | done | docs/ai/tdd/suite-select-sigpipe-fix-green.log | — | TEST-016 |

## Implementation plan
Write TEST-3280 and TEST-3281, observe RED against the early-exit helper bodies, then the fix, then green; run the full suite and `bash -n`.

## Test Plan

| Test ID | Spec-AC | Type | File path (expected) | Description | Mutation | Status |
|---------|---------|------|----------------------|-------------|----------|--------|
| TEST-3280 | Spec-AC-01 | unit | tests/skills/test-aai-suite-select.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_3280_header_readers_survive_ignored_sigpipe` | none | green |
| TEST-3281 | Spec-AC-02 | unit | tests/skills/test-aai-suite-select.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_3281_no_early_closing_reader_in_suite` | none | green |
| TEST-016 | Spec-AC-03 | regression | tests/skills/test-aai-suite-select.sh | `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh test_1760_weights_provenance` | none | green |

## Verification
Focused commands above, full `env -u AAI_ROLE bash tests/skills/test-aai-suite-select.sh` exit 0, `bash -n`. No full sweep.

## Evidence contract
Record ref_id suite-select-sigpipe-fix, Spec-AC and TEST ids, commands, exit codes and evidence paths under docs/ai/tdd/. Review scope is the inline review scope with base main.

### Evidence by strategy
tdd: stored RED (docs/ai/tdd/suite-select-sigpipe-fix-red.log) and GREEN (docs/ai/tdd/suite-select-sigpipe-fix-green.log) plus the standalone repro docs/ai/tdd/suite-select-sigpipe-fix-repro.sh.

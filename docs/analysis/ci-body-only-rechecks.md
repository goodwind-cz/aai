---
id: ci-body-only-rechecks
type: analysis
status: draft
updated: 2026-10-21
---

# Body-only PR rechecks: evidence and limits

Local implementation and regression checks cover the selector, workflow
dispatch and current-body release-notes verdict. The first matched hosted H1/H2
series below was observed on source `f9d8ebff5819a94350f681aedfb392dc63e89e86`.
Publication of this measured report creates a new head: final-head H1/H2 checks
and independent verification remain PENDING until recorded in PR #489 and the
preserved runtime evidence. This report does not infer completion of those
checks from an earlier source. The parent
[RFC-0017](../rfc/RFC-0017-smaller-node-core-and-faster-feedback.md) remains open.

The body-reuse decision requires a `pull_request` `edited` payload whose sole
change is a changed body, with complete repository and PR identity. It refuses
forks, a `ci-full` label, missing body fields or values other than strings or null, moving merge inputs,
and uncertain evidence. An earlier completed successful run must have the same
source SHA, base SHA, checkout SHA and workflow SHA, plus a successful identity
step and a complete successful source-job set at one attempt. Read-only API
errors and ambiguous pages fall back to normal selection. The current body's
release-notes check and tracked-ignored guard still run and feed the stable
aggregate context. External runner images, services and mutable action tags
are not frozen by this proof.

## Hosted protocol and evidence record

H1 — PENDING. After the candidate PR exists, obtain an ordinary successful
skill-suite run on its final source. Read run metadata and all attempt jobs
through `gh api repos/goodwind-cz/aai/actions/runs/<run-id>` and
`gh api repos/goodwind-cz/aai/actions/runs/<run-id>/attempts/<attempt>/jobs?per_page=100`.
Retain complete pagination and relevant select/source logs. Verify the
workflow-produced identity step, every expected full or selected shard,
Windows seed, smoke, tracked-ignored, release notes and aggregate. Record a
positive executed source-job count.

H2 — PENDING. Make one valid body-only edit, wait for completion, then make a
second harmless body-only edit and wait again. Confirm both run at the same
source/base/checkout/workflow identity as H1, cite H1 directly rather than
chaining reuse, and preserve the `release notes` and
`skill test suite (tests/skills/, via test-framework.sh)` check names. Inspect
all jobs and logs: executed source-job count must be zero in each H2 run,
while select, release notes, tracked-ignored and aggregate succeed. If the
base or checkout moves, repeat H1 at the new identity before measuring.

For each H1/H2 run, fill in: run URL, run ID, attempt, event/action, PR number,
source SHA, base SHA, checkout SHA, workflow SHA, workflow path, run status and
conclusion, job conclusions including every expected shard, executed
source-job count, select decision and cited anchor, sum of job durations and
wall time. Disclose skipped/cancelled jobs, queue time and unavailable billing
fields. Compare only runs at the same identity and report observed work
avoidance, without extrapolating a monetary or token saving.

| Check | Run ID / attempt / URL | Source, base, checkout, workflow SHA | Job conclusions and executed source-job count | Sum of job durations / wall time | Status |
|---|---|---|---|---|---|
| H1 ordinary source | [39657413136](https://github.com/goodwind-cz/aai/actions/runs/39657413136) / 1 | same identity below | all required current jobs success; 4 full shards + Windows seed + smoke success; selected variants skipped; executed 6 | 1012 s / 289 s | OBSERVED success |
| H2 first body edit | [39658253434](https://github.com/goodwind-cz/aai/actions/runs/39658253434) / 1 | same identity below | all required current jobs success; all framework variants + Windows seed + smoke skipped; direct H1 anchor 39657413136; executed 0 | 43 s / 26 s | OBSERVED success |
| H2 second body edit | [39658449756](https://github.com/goodwind-cz/aai/actions/runs/39658449756) / 1 | same identity below | all required current jobs success; all framework variants + Windows seed + smoke skipped; direct H1 anchor 39657413136; executed 0 | 46 s / 30 s | OBSERVED success |

This pre-merge prohibition is explicit: do not merge or describe AC-005's
hosted evidence as fulfilled until H1 and both H2 runs have been observed and
independently checked. Local Validation may accept the implementation and this
pending protocol before PR creation, as the frozen spec's lifecycle boundary
allows; delivery still waits for hosted evidence.


## Observed first matched series (PR #489)

All three runs used attempt 1, event `pull_request`, workflow path
`.github/workflows/skill-suite.yml`, and this exact identity:

- source SHA: `f9d8ebff5819a94350f681aedfb392dc63e89e86`
- base SHA: `b2c00799dac6411e009a554124b12e8515c82363`
- checkout SHA: `fc508d58ca1f82d481facea851dc44c2a5dd519c`
- workflow SHA: `fc508d58ca1f82d481facea851dc44c2a5dd519c`

Both controlled requests changed only the PR body's `body` property and retained
valid content. The action is established by those recorded PATCH requests plus
the production selector's body-only classification; run metadata exposes event,
not the complete webhook payload. Each H2 selection log directly cites H1 run
39657413136/attempt1. The second H2 does not chain the first reused run.

Raw run metadata, complete attempt-job pages, full logs, controlled request/PR
snapshots and per-job duration summaries are preserved under
`docs/ai/tdd/ci-body-rechecks-hosted/` in the worktree and main-checkout archive.
These are runtime evidence, deliberately not force-added to Git. Current checks
were select, release notes, tracked-ignored and the unchanged named aggregate;
all succeeded in both H2 runs. The source jobs skipped in H2 are intentional,
not a claim they executed again. No job was cancelled. Run-start queue time
reported by this API was zero; job durations and run wall time include hosted
scheduling/overhead and differ from billed runner minutes. Billing data was not
queried. These three observations establish work avoidance for this identity,
not a statistical performance guarantee, token saving or monetary estimate.

The protocol's earlier H1/H2 PENDING labels above describe the pre-PR procedure;
the table records actual first-series observations. Final publication-head
verification will be recorded in PR #489/runtime evidence without another
source commit solely to copy the final head SHA into itself.

## External review disposition

Thread 4340788860 questioned whether the attempt-specific jobs response includes
`run_attempt`. Disputed with a reply at
https://github.com/goodwind-cz/aai/pull/489#discussion_r4340796315:
the actual endpoint returned `run_attempt: 1` for every job, and both production
H2 runs accepted that H1 response and reused its source work. No synthetic
fixture claim substitutes for these actual API payloads. The guard was not
relaxed; thread resolution remains with the reviewer. This observation does
not represent another internal review verdict.

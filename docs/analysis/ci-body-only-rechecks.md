---
id: ci-body-only-rechecks
type: analysis
status: draft
updated: 2026-10-21
---

# Body-only PR rechecks: evidence and limits

Local implementation and regression checks cover the selector, workflow
dispatch and current-body release-notes verdict. H1 and H2 are PENDING hosted
delivery checks. No hosted avoidance or speed result is claimed here. This
report must be completed after PR creation and before merge; the parent
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
| H1 ordinary source | pending | pending | pending | pending | PENDING |
| H2 first body edit | pending | pending | pending | pending | PENDING |
| H2 second body edit | pending | pending | pending | pending | PENDING |

This pre-merge prohibition is explicit: do not merge or describe AC-005's
hosted evidence as fulfilled until H1 and both H2 runs have been observed and
independently checked. Local Validation may accept the implementation and this
pending protocol before PR creation, as the frozen spec's lifecycle boundary
allows; delivery still waits for hosted evidence.

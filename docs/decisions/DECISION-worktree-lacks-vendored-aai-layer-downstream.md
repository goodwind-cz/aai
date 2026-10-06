# Decision: Move native Windows proof to the pull-request CI gate

Date: 2026-10-06
Blocking ref: direct blocking reason (`HITL-6`)
Decided by: human

## Question

Provide a native Windows evidence route plus a supported TEST-008 mutation
measurement, or authorize a post-freeze amendment that moves native Windows
proof to post-PR CI and defines an executable local mutation contract.

## Decision

Choose option 1: amend the frozen specification so the already executable Bash
and local pwsh evidence can satisfy the pre-PR validation contract. Make native
Windows PowerShell 5.1 and pwsh 7 mandatory pull-request CI checks before merge.
Move the mutation contract from the unsupported Pester path to the shared Node
seeder behavior that the current mutation runner can execute and measure.

## Assumptions

- The pull request must not be merged unless the required native Windows CI
  checks pass.
- Local pwsh evidence is not relabeled as native Windows evidence.
- The amendment uses the autonomous post-freeze sign-off path; any owed sign-off
  remains visible at the merge checkpoint.

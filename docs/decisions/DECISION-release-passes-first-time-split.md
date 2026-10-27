# Decision: split CHANGE-0231 after Validation4

Date: 2026-10-27T16:55:00Z
Blocking ref: docs/ai/STATE.yaml human_input (release-passes-first-time)
Decided by: human

## Question

V4-1: `--report` into `.git/index` overwrites the source Git index. The sole
standing extension (wave-2-roadmap) is exhausted. Split CHANGE-0231 into two
rides — first current-head CI result selection, then the rollup executor with
Git-metadata protection — or explicitly authorize another remediation round
over the original combined scope?

## Decision

Split. The owner selected option A (recommended):

1. Child A — current-head CI reader (`current-head-ci-reader`): shared
   `github-checks` reader, `watch-ci` and release required-check consumers,
   historical PR #504/#506 current-head replay. Owns intake AC-003 and the
   cancelled-run half of AC-004.
2. Child B — release rollup dry-run (`release-rollup-dry-run`): CHANGELOG
   discovery, disposable rolled execution across Node/shell/Pester, CI job,
   and the V4-1 Git-metadata report-target guard. Owns intake AC-001, AC-002,
   the rollup half of AC-004, and V4-1.

No further combined remediation round. No combined pull request.

## Assumptions

- Parent intake `release-passes-first-time` and its frozen/amended draft spec
  are superseded. Their bytes, Validation4 report, review report, and the
  worktree remain as evidence; nothing is discarded.
- Child A ships first from the existing implemented reader surface. Child B is
  parked until A is review-passed; B then resumes the rollup executor and
  adds the pre-checkpoint Git metadata refusal.
- The pure `release-rollup.mjs` extract already in the worktree may ride with
  A only if it is a no-behavior-change extraction required by the
  release-finish consumer edit; otherwise it stays with B.
- This decision does not waive validation or review for either child and does
  not authorize a second standing extension on the parent ride.

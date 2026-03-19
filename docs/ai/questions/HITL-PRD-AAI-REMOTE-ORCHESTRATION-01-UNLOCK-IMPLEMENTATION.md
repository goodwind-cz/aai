# Human Decision Required: Unlock Implementation

Scope ref: PRD-AAI-REMOTE-ORCHESTRATION-01
Requested by: Implementation role

## Blocking reason
`locks.implementation` is currently set to `true` in `docs/ai/STATE.yaml`.
Implementation cannot proceed while this lock remains enabled.

## Question
Should implementation be unlocked for this scope now?

## Options
- `unlock-now`: set `locks.implementation=false` and continue implementation in this branch.
- `keep-locked`: keep lock enabled and continue planning/documentation only.
- `pause`: set `project_status=paused` and stop the loop.

## Notes
- Unlocking allows code and test file changes for this scope.
- Keeping lock enabled will prevent TDD/implementation progress.

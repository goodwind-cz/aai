---
id: hook-gate-on-node
type: change
number: 253
status: done
capability: hook-gate-on-node
parent: smaller-node-core-and-faster-feedback
links:
  pr:
    - TBD
  commits:
    - TBD
---

# Move the Claude hook gate's decisions to one Node module behind a bash pre-filter, and gate the Azure merge command

## Summary
- Ride 7 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5).
- `.aai/scripts/claude-hook-gate.sh` (632 lines, 341 code lines, no twin)
  decides four Claude Code hook gates in bash: `commit`, `merge` (constitution
  article 7, the merge-policy lane path and the post-open sweep check),
  `state-dump` and `stop-nudge`. Its decisions move to one Node module; the
  script keeps a fast bash pre-filter that answers the common "nothing to
  check" case without starting Node, and delegates every other decision.
- Fix P1 `fu-platform-adapter-hook-gate`: the merge gate does not gate the
  Azure DevOps merge command.
- Owner decision 2026-11-05 (plan section 4, item 3): the hook gate becomes
  an L3 protected surface in this ride.

## Motivation / Business Value
- Every Bash tool call of a project with the hooks overlay runs three
  PreToolUse gates, and each one starts bash and Node. Measured on main
  `c88cf708` (macOS arm64, bash 3.2, Node 22.23.1, n=60 per case): p50 about
  30 ms and p95 about 35 ms per gate for an ordinary command (`ls -la`,
  `git status`), 39 ms p50 and 45 ms p95 for a denied `git merge`. Node's own
  start-up is 20 ms p50 on this host; a bash pre-filter that does not start
  Node is 3.3 ms p50.
- Reproduced at intake (bash, scratch git fixture, the real script):
  - The Azure merge forms are allowed: `node .aai/scripts/platform.mjs merge
    --pr 7 --expect-head abc --operator-merge` and `az repos pr update --id 7
    --status completed` exit 0 with no `AAI_OPERATOR_MERGE`, where
    `gh pr merge 42 --squash` exits 2 (the P1).
  - Early-closing readers: 9 pipe sites by the pipe-safe ratchet's pattern
    (7 `printf | grep -q`, 2 `| head`; the plan said 7). The script runs
    `set -u` without `pipefail`, so the ratchet skips it and the default
    environment does not misfire. With `pipefail` inherited through an
    exported `SHELLOPTS`, a `gh pr merge 42 --squash` or a STATE.yaml
    `yaml.dump` command followed by 8000 more lines is allowed (exit 0, 3 of
    3 runs each); without it both are denied (exit 2).
  - Text that only names a merge is denied: `git commit -m "explain git merge
    handling"` and `echo gh pr merge 5` exit 2 from the merge gate.
  - The operator marker written as a command prefix
    (`AAI_OPERATOR_MERGE=1 gh pr merge 42 --squash`, the line
    `/aai-merge` runs) is denied; only the marker in the hook's own
    environment counts (pinned by TEST-1520 of the hooks-overlay suite).
- `.aai/system/PROFILES.yaml` already calls the adapter "itself
  L3-protected", but no protected-path list names it.

## Scope
- In scope:
  - One Node module holding every gate decision, with the merge-gate PR
    resolution, the lane path, the sweep check call and the deny texts.
  - `claude-hook-gate.sh` becomes a launcher with a bash pre-filter: it
    reads the payload, exits 0 without starting Node when the payload
    cannot concern the gate, keeps the no-Node lane guard, and otherwise
    hands the payload to the module and maps its result (2 blocks,
    anything else allows: fail-open as today).
  - The Azure merge forms are merge commands for the article 7 deny and
    the sweep check.
  - Every behaviour difference found is decided in the spec and pinned by
    one `node:test` case; the remaining decisions stay byte for byte the
    same (stderr and exit code) as the script at the base commit.
  - L3: the launcher and the module join the protected-path lists
    (`.aai/workflow/WORKFLOW.md`, `docs/ai/docs-audit.yaml`,
    `.aai/templates/docs-audit.template.yaml`).
  - A latency bound in the spec, measured before and after.
  - Wiring (suite map, weights, PROFILES, merge-policy guard paths, the
    suites that read the script's source), a scratch `aai-sync` install,
    before and after line counts, RFC-0017 phase 5 sentence, CHANGELOG
    `## [unreleased] — <title>` entry.
- Out of scope:
  - The hooks overlay template and the bootstrap merge (the four hook
    commands stay byte for byte; consumer settings do not change).
  - Accepting the operator marker as a command prefix (a policy change on
    a guard; left to the owner, see Notes).
  - Moving merge-policy.mjs or lane-gate.mjs onto the platform adapter
    (their own follow-ups).
  - pre-commit-checks.sh, which the commit gate keeps calling.

## Affected Area
- `.aai/scripts/claude-hook-gate.sh` (becomes L3), a new module under
  `.aai/scripts/` (L3)
- `.aai/workflow/WORKFLOW.md`, `docs/ai/docs-audit.yaml`,
  `.aai/templates/docs-audit.template.yaml` (L3 lists)
- `.aai/scripts/merge-policy.mjs` (GUARD_PATHS), `.aai/system/PROFILES.yaml`
- `tests/skills/test-aai-hooks-overlay.sh`, `tests/skills/test-aai-merge-policy.sh`,
  wiring files, a new suite
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- The hook gate decides as before on every input except the decided
  differences, and starts no Node process for a command that cannot
  concern the gate.
- `platform.mjs merge` and `az repos pr update ... --status completed` are
  denied by article 7 unless the operator marker is set, and need a valid
  sweep record like `gh pr merge`.
- No decision depends on how a pipe closes.

## Acceptance Criteria
- AC-001: One Node module decides all four gates; the launcher holds no
  decision logic and no pipeline, and a differential run against the
  script at the base commit gives the same exit code and stderr bytes on
  every corpus input except the decided differences.
- AC-002: The Azure merge forms are denied without the operator marker and
  go through the sweep check with it (closes `fu-platform-adapter-hook-gate`).
- AC-003: Every behaviour difference found has a recorded decision and one
  `node:test` case, including the large-input case under an inherited
  `pipefail`.
- AC-004: A command that cannot concern a gate starts no Node process; the
  spec states a latency bound and the measured before and after p50/p95.
- AC-005: The launcher and the module are on all three protected-path lists
  and a scope touching either is ceremony level 3.
- AC-006: The existing hook and merge-policy suites pass; wiring is
  complete; a scratch `aai-sync` install runs the gate; removed code lines
  are measured.

## Verification
- The new suite and the touched suites pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- `node --test` on the module's test file passes.

## Constraints / Risks
- L3 protected surfaces (the protected-path lists and WORKFLOW.md, plus the
  two files this ride adds): ceremony level 3, an explicit recorded
  worktree decision, mandatory code review on the most capable tier, and
  the owner's final-diff sign-off before merge.
- Consumer-visible: projects with the hooks overlay get the Azure merge
  deny and the faster gate. The owner merges.
- The hook gate guards the session that edits it; the live gate of the
  main checkout must keep working while the ride runs (the ride works in
  its own worktree).
- The gate stays fail-open on its own errors (a missing Node or module
  allows), except the lane-path denials that exist today.
- Secrets preflight: no local secret is referenced by this scope.

## Notes
- Source: roadmap item `hook-gate-on-node`; plan ride 7 (owner sign-off:
  yes, given on the plan 2026-11-05).
- Precedents: CHANGE-0248 / SPEC-0276 and CHANGE-0251 / SPEC-0281 (one Node
  module, `node:test` per drift), CHANGE-0250 / SPEC-0279 (an L3 guard ride).
- Count corrections: the follow-up says "30 gh sites"; measured 19 code
  lines name `gh` (60 tokens counting comments). The plan says 7 pipe
  sites "under pipefail"; measured 9 by the ratchet's pattern, and the
  script does not set `pipefail` (bash, `/usr/bin/grep`).
- Operator marker as a command prefix: `/aai-merge` prints
  `AAI_OPERATOR_MERGE=1 gh pr merge ...`, which the hook denies; this ride
  keeps that and leaves `fu-merge-gh-line-powershell` open.
- Worktree: owner decision 2026-11-08 (own worktree for this L3 ride,
  parallel with ride 6 slice b).
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).

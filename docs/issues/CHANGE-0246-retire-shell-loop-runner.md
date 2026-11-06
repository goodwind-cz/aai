---
id: retire-shell-loop-runner
type: change
number: 246
status: done
capability: retire-shell-loop-runner
parent: smaller-node-core-and-faster-feedback
links:
  pr: []
  commits: []
---

# Retire the shell autonomous loop runner in favour of /aai-loop

## Summary
- Ride 2 of the [remaining-scripts plan](../analysis/node-first-remaining-plan.md)
  (RFC-0017 phase 5).
- Retire `.aai/scripts/autonomous-loop.sh` and `.aai/scripts/autonomous-loop.ps1`,
  the external shell loop runner that `/aai-loop` (`.aai/SKILL_LOOP.prompt.md`)
  superseded. Both files stay one release as thin deprecation launchers that
  name `/aai-loop`, change nothing and exit 1; a later release deletes them.
- Update every live caller and reference so no shipped prompt, doc or test
  tells an agent or a user to run the shell runner.

## Motivation / Business Value
- 793 code lines of twin duplication (non-blank, non-comment; 409 in the
  `.sh`, 384 in the `.ps1`; measured on main `8293605d`) leave the shipped
  core profile, which every downstream install receives.
- The plan (section 2) measured 1 commit in 60 days and 0 METRICS or EVENTS
  mentions; only source-shape test pins keep the files alive. `/aai-loop`
  carries the runner's stop conditions, stagnation recovery, run budget and
  wake-up digest in-session, and `/aai-ship` adds the unattended path.
- `.aai/AGENTS.md`, `.aai/SKILL_LOOP.prompt.md`, `.aai/system/AUTONOMOUS_LOOP.md`
  and `docs/USER_GUIDE.md` still describe the runner as a way to drive the
  loop, so an agent or a user can still pick it.

## Scope
- In scope:
  - Owner decision 2026-11-05 (plan section 4, item 2): both runner files
    become launchers of at most 20 lines that print one retirement line naming
    the replacement `/aai-loop`, ignore every argument, change nothing and exit
    1. They stay in the core profile for one release.
  - Live callers and references, each verified by reading: `.aai/AGENTS.md`,
    `.aai/SKILL_LOOP.prompt.md`, `.aai/BOOTSTRAP_DIFF.prompt.md`,
    `.aai/system/AUTONOMOUS_LOOP.md`, `.aai/scripts/generate-overview.mjs`
    (comment), `docs/USER_GUIDE.md`, `README.md` (the two "loop runner"
    lines), `docs/TECHNOLOGY.md` (the "loop runners" shell line).
  - Test pins on the runner's source shape: `tests/skills/test-aai-check-state.sh`
    (single STATE creator pin), `tests/skills/test-aai-live-status.sh`
    (SEAM 5 list), `tests/skills/test-aai-expert-fetch.sh` (RFC-0017
    inventory destination pin) and `tests/skills/test-aai-hygiene-pack.sh`
    (historical comment), each kept, rewritten or left as the reading shows.
  - Wiring as the precedent ride did: suite map (and weights if the selector
    asks), the ps1-quality path filter if it names the files, the prompt-diet
    ledger entry and TEST-012 pin for the measured prompt byte delta.
  - RFC-0017: the phase 5 row gains one sentence for this slice; the
    inventory row's reason cell says retired. Phase 5 stays `in progress`.
  - Before/after code-line measurement with the plan's method.
  - A follow-up `fu-delete-retired-shell-loop-runner` for the deleting release.
  - CHANGELOG `## [unreleased] — <title>` per-entry heading.
- Out of scope:
  - Deleting the launchers (the later release).
  - `.aai/scripts/loop-digest.mjs`: `/aai-loop` reads it every tick and
    `/aai-profile` uses it; it stays.
  - Any change to `/aai-loop` behaviour; any other script pair (ride 3 onward).
  - Historical docs (`docs/issues`, `docs/specs`, `docs/rfc` except the
    RFC-0017 rows named above, `docs/analysis`, archives, CHANGELOG history).

## Affected Area
- `.aai/scripts/autonomous-loop.sh`, `.aai/scripts/autonomous-loop.ps1`
- `.aai/AGENTS.md`, `.aai/SKILL_LOOP.prompt.md`, `.aai/BOOTSTRAP_DIFF.prompt.md`,
  `.aai/system/AUTONOMOUS_LOOP.md`, `.aai/system/PROFILES.yaml`,
  `.aai/scripts/generate-overview.mjs`
- `docs/USER_GUIDE.md`, `README.md`, `docs/TECHNOLOGY.md`
- `tests/skills/test-aai-check-state.sh`, `tests/skills/test-aai-live-status.sh`,
  `tests/skills/test-aai-expert-fetch.sh`, `tests/skills/test-aai-hygiene-pack.sh`,
  `tests/skills/suite-map.yaml`, `tests/skills/lib/prompt-diet-ledger.sh`,
  `tests/skills/test-aai-prompt-diet.sh`
- `docs/rfc/RFC-0017-smaller-node-core-and-faster-feedback.md`, `CHANGELOG.md`

## Desired Behavior (To-Be)
- Running either runner on any platform prints one retirement line on stderr
  naming `/aai-loop`, prints nothing on stdout, exits 1 and leaves the tree
  untouched, whatever arguments it was given.
- No shipped prompt, guide or test tells an agent or a user to run the shell
  runner; the loop guidance names `/aai-loop` only.

## Acceptance Criteria
- AC-001: Both runner files are launchers of at most 20 lines that print one
  retirement line naming `/aai-loop`, change nothing and exit 1, on POSIX
  shells and on PowerShell 5.1 and 7, with no Node, Python or agent CLI needed.
- AC-002: Outside docs history, CHANGELOG and tests, no tracked file except
  the two launchers and `PROFILES.yaml` names `autonomous-loop.sh`,
  `autonomous-loop.ps1` or `autonomous-loop.{sh,ps1}` as something to run;
  every remaining live line that names the runner says it is retired.
- AC-003: The test pins on the runner's source shape are rewritten or kept as
  the reading shows and every touched suite passes; `loop-digest.mjs` stays
  and `/aai-loop` still names it.
- AC-004: Wiring is complete: the suite map knows the launchers, the
  prompt-diet ledger and TEST-012 match the corpus, the RFC-0017 inventory
  test passes, and a scratch `aai-sync` core install ships both launchers and
  they refuse there.
- AC-005: The before and after code lines are measured with the plan's
  method and recorded.

## Verification
- The touched suites and the new retirement suite pass (rc 0), run with
  `env -u AAI_ROLE -u AAI_GIT_WRITE`.
- The Windows CI job passes on the pull request under both engines.
- A scratch `aai-sync --profile core` install holds both launchers and each
  refuses there with exit 1.

## Constraints / Risks
- Changing shipped core scripts is consumer-visible: a downstream cron job or
  script that calls the runner starts failing with exit 1 and the retirement
  line. Merge stays with the owner; the CHANGELOG names the retirement, the
  replacement and the one-release window.
- `/aai-loop` has no `--propose-only` push block; unattended rides go through
  `/aai-ship unattended=true` and its preflight budget instead. Named in the
  CHANGELOG and the user guide.
- Windows parity is proven only by the hosted Windows job.
- No secrets referenced.

## Notes
- Source: roadmap item `retire-shell-loop-runner`; plan
  `docs/analysis/node-first-remaining-plan.md` ride 2; owner decision
  2026-11-05 (one-release deprecation launcher naming the replacement).
- Pattern precedent: ride 1, `retire-legacy-migrations` (CHANGE-0245,
  SPEC-0273, PR #533).
- Assumption (autopilot default): downstream callers were swept; no shipped
  hook, launcher, routine, aai-sync, aai-update or aai-doctor path invokes the
  runner. aai-sync ships it only through the PROFILES `core:` list.
- Autopilot defaults: human_time_minutes null; no implementation-mode menu
  (Planning decides).

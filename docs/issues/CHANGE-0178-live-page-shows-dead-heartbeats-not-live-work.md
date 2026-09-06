---
id: live-page-shows-dead-heartbeats-not-live-work
number: 178
type: change
status: done
links:
  pr:
    - TBD
  commits:
    - 1412b4830e6924ad64506b8a759eed9966238217
---

# The live page shows dead heartbeats as agents and hides the live work

## Summary
- Two defects in the delivered live page (SPEC-0167, extended by SPEC-0169).
- The "Agents" table lists heartbeat slot files whose writing process exited
  days ago, because nothing ever removes a slot when its process dies.
- The per-session detail the page already loads is thrown away: `live_sessions`
  carries harness, project and running/finished state per session, and the page
  renders only the sentence "N active of M sessions".

## Motivation / Business Value
- Owner report, 2026-09-06, on the first real use of `/aai-live`: "je to na nic,
  nevidim tam nic z toho co se ted deje, a nevim kde jsi vzal ty agenty."
- Observed on that run: three rows under "Agents", all from 2026-09-03/04, pids
  7053, 52554 and 95962, none of which was still running. Meanwhile the session
  actually driving the page at that moment (harness claude-code, project aai,
  state running) was visible in the page's own data and not on the page.
- A live page whose headline table is a graveyard is worse than no page: it
  answers "what is running" with three wrong answers.

## Scope
- In scope: dead-process classification and reaping in
  `.aai/scripts/heartbeat.mjs`; rendering the per-session detail already present
  in the live-status payload in `.aai/scripts/aai-live-serve.mjs`; the suites
  `tests/skills/test-aai-live-serve.sh` and the heartbeat suite.
- Out of scope: the decision-menu options parser (already split as
  `decision-menu-options-parser`, wave 2); any non-loopback host; any LLM call;
  writing a tracked file from the served page.

## Affected Area
- `.aai/scripts/heartbeat.mjs` (slot lifecycle), `.aai/scripts/aai-live-serve.mjs`
  (page + `/data.json`), and their suites.

## Desired Behavior (To-Be)
- A slot whose recorded process is gone is not presented as a live agent, and
  does not accumulate on disk forever.
- The page's first answer to "what is happening now" is the list of live
  sessions, not a count.

## Acceptance Criteria
- AC-001: A heartbeat slot older than the page's hide window is not presented
  as a live agent. (AMENDED 2026-09-06 — see Amendment 2 in the spec. As first
  written this asked whether the recorded pid is still running; the recorded pid
  belongs to the short-lived process that WROTE the slot, so it cannot answer
  that. Freshness is the signal a heartbeat actually carries.)
- AC-002: The classification fails open: a slot past the stale mark but inside
  the hide window is still listed and merely marked, and what is withheld is
  counted and dated rather than dropped, so nothing disappears silently.
- AC-003: Withholding is presentation, not deletion. The live page reads every
  five seconds, and a destructive read would make a page refresh delete an
  operator's files; disk growth stays bounded by the existing write-path GC.
  That the GC only runs on write — which is why three-day-old slots survived —
  is tracked as `fu-heartbeat-gc-only-runs-on-write`.
- AC-004: `/data.json` carries the per-session rows the live-status payload
  already holds (harness, project, state), not only the counts.
- AC-005: The served page renders one row per live session with harness, project
  and state, running sessions first, and states the scan time it came from.
- AC-006: With a heartbeat directory holding only dead slots, the page's Agents
  section reads "No agent has a live heartbeat" instead of listing them.
- AC-007: The SPEC-0167 refusals are unchanged and still green: non-loopback
  `--host` exits 2, a busy port exits 1, and `POST /answer` refuses a non-JSON
  content-type, a cross-site Origin, a non-loopback Host, an oversized body, an
  empty answer, a mismatched token or ref, and any answer when nothing pends.
- AC-008: No new dependency, no network beyond loopback, no LLM token, and the
  only file the server writes is still the gitignored answer ledger.

## Verification
- `bash .aai/scripts/aai-run-tests.sh --skill aai-live-serve` — green.
- The heartbeat suite — green, including a new arm that plants a slot with a
  pid that is certainly not running and asserts it is neither listed nor kept.
- Full sweep (`AAI_TEST_TIMEOUT=3000`) — no regression.
- Manual: start the server against a heartbeat directory holding only dead
  slots, fetch `/data.json`, and confirm `roles` is empty and the session rows
  are present.

## Constraints / Risks
- Pid reuse after a reboot can make a dead slot look alive. Accepted: such a
  slot is still shown as stale by age, which is the pre-existing behavior — the
  change never makes the page claim MORE liveness than today.
- The heartbeat directory is per-git-common-dir, so slots from sibling worktrees
  of the same repository share it; their pids are checkable on this host, but a
  slot written inside a container or on another machine is not. AC-002 covers it.
- No secret is referenced by this scope; the secrets preflight does not apply.
- Roadmap: this ride is off-roadmap maintenance on a delivered capability
  (`live-agent-dashboard-served-locally`, pair 1, done). `ride-select.mjs gate`
  refuses it by design; it proceeds under an owner-directed `--override`, logged
  to `docs/ai/EVENTS.jsonl` as `ride_gate_override`.

## Notes
- Depends on PR #349, which is unmerged and touches the same two files. This
  ride branches off `main` only after #349 lands, or is stacked on it.

---
id: spec-live-agent-dashboard-served-locally
type: spec
number: 167
status: done
ceremony_level: 2
links:
  requirement: docs/issues/CHANGE-0173-live-agent-dashboard-served-locally.md
  rfc: null
  pr:
    - TBD
  commits:
    - 129422c6
---

# Spec — a locally served live dashboard of agents, waits and ages

SPEC-FROZEN: true

## Links
- Requirement: `docs/issues/CHANGE-0173-live-agent-dashboard-served-locally.md`
- Roadmap: `docs/project-sessions/2026-09-05-capability-roadmap.md` (wave 1, pair 1, capability half; paired with `roadmap-driven-ride-selection-with-budget`)
- Owner decisions: `hitl_decision` `capability-roadmap-wave-1`, `internal-work-without-asking`
- Reused, never reimplemented: `.aai/scripts/heartbeat.mjs` (`read --json` → `{slots:[{slot,ref_id,role,message,updated_at,age_seconds,pid,worktree}],degraded:[]}`, slot dir `<git-common-dir>/aai/heartbeat`), `.aai/scripts/generate-live-status.mjs` (`--data-only --output <p>` writes `live-status-data.json` beside `<p>`: `harnesses[]`, `live_sessions[{harness,sessionId,project,state}]`, `spend`, `quotas`, `degraded[]`), `docs/ai/STATE.yaml` `human_input:{required,question,blocking_reason}`
- Technology contract: `docs/TECHNOLOGY.md` (Node stdlib only, zero deps, bash 3.2 suites)

Registry items closed by this scope: none. Measured with `follow-ups.mjs list --status open | grep -iE 'dashboard|live|serve'`: no open item names a served page; the owner's request lives in a friction observation (`SKILL_LOOP/operator_observability`), not in the registry.

## Design decisions
- **D1 — loopback or refuse.** `http.createServer` on `127.0.0.1` only. `--host` other than `127.0.0.1`/`localhost` exits 2 with the reason; there is no `--insecure` escape.
- **D2 — one truth per source, by reuse.** `/data.json` is assembled by spawning `heartbeat.mjs read --json` (cheap, every request) and by a cached `generate-live-status.mjs --data-only` run (heavier, refreshed at most every 30 s, written to `os.tmpdir()`), plus a line-level read of STATE.yaml's `human_input` block. No parser is duplicated.
- **D3 — waiting-on-you first.** A pending `human_input` renders above everything with the question and its age; when none, one line says so. Roles come next, stale ones marked (age > 120 s), never hidden. Live sessions and spend are a compact footer.
- **D4 — the server writes nothing under the repository.** Its only writes go to `os.tmpdir()`. The suite proves it with the tripwire.
- **D5 — a page that survives a dead server.** The page polls `/data.json` every 5 s; a failed poll keeps the last data and shows "stale since <time>".

## Implementation strategy
- Strategy: tdd
- Rationale: the two properties that matter most are refusals (non-loopback bind; any repo write) and absences (no slots, no human_input), and a test that only covers the happy render would pass while either failed.

## Acceptance Criteria Status

| Spec-AC    | Description | Status | Evidence | Review-By | Notes |
|------------|-------------|--------|----------|-----------|-------|
| Spec-AC-01 | `node .aai/scripts/aai-live-serve.mjs` binds `127.0.0.1` on `--port` (default 7331), prints exactly one URL line, serves `/` (HTML) and `/data.json`; `--host 0.0.0.0` exits 2 naming the refusal and binds nothing | done | TEST-001, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; RED in docs/ai/tdd/live-agent-dashboard-served-locally-red.log; host refusals 0.0.0.0/::/192.168.1.1/'' and busy port re-verified in docs/ai/validation/live-agent-dashboard-served-locally-round2.md | tdd:2026-09-05 | D1; lsof shows 127.0.0.1 only |
| Spec-AC-02 | `/data.json.roles` lists every heartbeat slot with `role`, `ref_id`, `message`, `age_seconds`, `stale` (true iff age > 120); a fixture with one fresh and one 10-minute-old slot yields both, the old one `stale:true` | done | TEST-002/007, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; fresh-install (no slot dir) renders, per code review | tdd:2026-09-05 | reuse of heartbeat read; stale after 120 s, never hidden |
| Spec-AC-03 | With STATE.yaml `human_input.required: true`, `/data.json.waiting` carries `question`, `blocking_reason`, `since`; the HTML places it before the roles section; with `required: false` it is `null` and the HTML shows the one-line "nothing waits on you" | done | TEST-003, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; the canonical writer's >- block scalar arm added after round 1 F1, re-verified with state.mjs set-human-input in docs/ai/validation/live-agent-dashboard-served-locally-round2.md | tdd:2026-09-05 | D3 both arms; since = STATE mtime, labelled as an upper bound |
| Spec-AC-04 | The served HTML polls `/data.json` every 5 s, shows the last successful refresh time, and on a failed poll keeps the last payload and shows a stale marker — asserted on the page source (poll interval, handlers) and by a request against a stopped server | done | TEST-004, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; failed-poll arm executed under a stub DOM in round 1 | tdd:2026-09-05 | D5 |
| Spec-AC-05 | A full serve+poll cycle against fixtures leaves `git status --porcelain` unchanged and creates files only under `os.tmpdir()`; the suite runs under the tripwire and attests clean | done | TEST-005, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; live-status ENABLED, marker + find; the pre-fix engine (cache under .aai/cache) reddens it — mutation re-run in docs/ai/validation/live-agent-dashboard-served-locally-round2.md | tdd:2026-09-05 | D4; git status is blind to gitignored writes, so the check is a marker + find |
| Spec-AC-06 | `/aai-live` wrapper + `.aai/SKILL_LIVE.prompt.md` start the server; SIGINT exits 0 within 2 s and leaves no child process (`ps` shows none with the server's pid as parent) | done | TEST-006, tests/skills/test-aai-live-serve.sh; docs/ai/tdd/live-agent-dashboard-served-locally-green.log; SIGINT mid-scan 4 ms, orphan-sweep plan empty (round 1) | tdd:2026-09-05 | survivor check by argv, since a re-parented child never matches ppid |
| Spec-AC-07 | Companion obligations: `PROFILES.yaml` entry for the new script, `suite-map.yaml` row, prompt-diet `JUSTIFIED_ADDITIONS` credit equal to the MEASURED byte growth of `.aai/SKILL_LIVE.prompt.md` with the matching TEST-012 pin bump; `test-aai-prompt-diet.sh` green | done | tests/skills/test-aai-prompt-diet.sh and test-aai-layer-profiles.sh green; ledger +702 B = wc -c .aai/SKILL_LIVE.prompt.md; pin 11945 -> 12647; docs/ai/tdd/live-agent-dashboard-served-locally-green.log | tdd:2026-09-05 | closed list; bytes measured, not copied |

## Test Plan

| Test ID  | Spec-AC    | Type | File path (expected)                    | Description | Status |
|----------|------------|------|-----------------------------------------|-------------|--------|
| TEST-001 | Spec-AC-01 | int  | tests/skills/test-aai-live-serve.sh | start on a free port, GET / is 200 text/html, GET /data.json is 200 JSON; `--host 0.0.0.0` exits 2 and no socket opens | pending |
| TEST-002 | Spec-AC-02 | int  | tests/skills/test-aai-live-serve.sh | two fixture slots via `heartbeat.mjs write --dir`, one aged by rewriting `updated_at`; `/data.json.roles` has both, correct `stale` | pending |
| TEST-003 | Spec-AC-03 | int  | tests/skills/test-aai-live-serve.sh | fixture STATE with `required: true` → `waiting` populated and appears before roles in HTML; `required: false` → `null` and the one-line message | pending |
| TEST-004 | Spec-AC-04 | unit | tests/skills/test-aai-live-serve.sh | page source contains the 5 s poll and the stale handler; a poll against a closed port is handled (curl non-zero) without the page needing a reload | pending |
| TEST-005 | Spec-AC-05 | int  | tests/skills/test-aai-live-serve.sh | run under the tripwire: `git status --porcelain` identical before/after; new files only under `$TMPDIR` | pending |
| TEST-006 | Spec-AC-06 | int  | tests/skills/test-aai-live-serve.sh | SIGINT → exit 0 within 2 s, no orphan child | pending |
| TEST-007 | Spec-AC-07 | int  | tests/skills/test-aai-prompt-diet.sh | ledger credit equals measured growth; layer-profiles green | pending |

## Implementation plan
- **NEW** `.aai/scripts/aai-live-serve.mjs` — `node:http`, `node:child_process` (spawnSync for heartbeat read and the cached live-status run), `node:fs`, `node:os`. Flags: `--port`, `--host`, `--heartbeat-dir` (test seam), `--state` (test seam), `--no-live-status` (test seam; skips the transcript scan).
- **NEW** `.aai/SKILL_LIVE.prompt.md` (≤ 25 lines) + `.claude/skills/aai-live/SKILL.md` wrapper.
- **NEW** `tests/skills/test-aai-live-serve.sh`.
- **EDIT** `.aai/system/PROFILES.yaml`, `tests/skills/suite-map.yaml`, prompt-diet ledger + TEST-012 pin.

## Constraints / Risks
- Never bind beyond loopback; refusal, not warning.
- The live-status scan reads harness transcripts — those may hold secrets; the server exposes only the already-aggregated `live-status-data.json` fields, never transcript text.
- Port collision: a busy port exits 1 naming the port; no auto-increment (an operator must know which URL is theirs).

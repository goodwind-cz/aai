---
id: codex-usage-missing-from-run-budgets
type: issue
number: null
status: draft
links:
  pr: []
  commits: []
---

# Codex usage is available but missing from AAI run accounting and budgets

## Summary
AAI records unknown token usage for Codex role runs and cannot enforce token budgets even when authoritative Codex usage events exist. Connect supported Codex usage observations to the same accounting and budget consumers used by other harnesses, with explicit provenance and honest attribution limits.

## Type
- bug

## Impact
- Affected: Codex desktop/in-session orchestration and subagent workflows using AAI run metrics and token-budget checks.
- Severity/priority: high; users can exhaust their account allowance during an autonomous run without an effective AAI token-budget stop.
- Observed incident: CHANGE-0231, release-passes-first-time, 2026-10-27. Ten recorded role runs had null input/output tokens and cost, while the owner reported442 messages and exhausted allowance. This is incident context, not a measured token total or proof that all messages were billable model calls.

## Current Behavior
- SUBAGENT_PROTOCOL.md limits capture to usage exposed in the dispatching parent's completion result. The collaboration tool results in the incident did not include usage; the orchestrator recorded unknown values without checking another authoritative source.
- AAI already has a Codex session-log parser in .aai/scripts/live-parsers/codex.mjs, consumed by generate-live-status.mjs. It reads token_count events with info.total_token_usage; this dashboard path is not connected to state append-run/log-tick accounting and run-budget enforcement.
- Codex App Server also documents thread/tokenUsage/updated notifications. A protocol capability does not by itself prove that the current collaboration integration exposes it; discovery must distinguish supported and actually available sources.
- SKILL_LOOP.prompt.md makes token/cost budget checks a no-op when usage is unavailable. Consequently, a declared budget may be ineffective while the workflow continues.
- Local inspection found token_count events in the incident parent chat's rollout log under ~/.codex/sessions/2026/10/27/. Its initial cwd was /Users/ales/Projects/aai, later work used a managed worktree. Matching only the current cwd would miss the parent. The latest cumulative value includes later conversation and must not be labeled as the original ride's usage.

## Expected Behavior
- Capture authoritative usage through the available Codex integration: supported host events when exposed, or a documented local-log adapter where permitted. Do not make the model estimate its own tokens.
- Resolve stable session/thread/turn identities and parent-child relationships across cwd/worktree changes. Track orchestration usage as well as child usage. Define whether parent totals include descendants and avoid double counting.
- Persist observed input/output/cache/total fields through AAI run and tick accounting with source, identity, observation interval and attribution basis. If only a session total is known, retain it as such; never invent a per-role split.
- Treat cumulative counters, duplicate events, restarts, compaction/reset behavior, delayed updates and partial logs explicitly. Cache/reasoning subtotals must not be added twice to inclusive input/output totals.
- Feed actual observations into the configured token-budget gate during the run and before another dispatch, not only after close. A missing/unreadable source must produce an explicit unavailable/degraded budget state rather than an assertion that a token limit is being enforced or a fabricated zero.
- Preserve working Claude usage capture. Token counts, monetary cost and account quota percentages remain distinct quantities; no dollar charge is inferred solely from ChatGPT subscription token counters.

## Steps to Reproduce (if applicable)
1. Use Codex desktop with AAI orchestration and a subagent completion interface that omits usage fields; enable a finite token budget for the controlled reproduction.
2. Observe an authoritative Codex token event for the identified parent/child session, either via an actually exposed host event or a fixture matching a locally observed rollout token_count schema.
3. Complete a role and inspect its append-run/log-tick records and budget decision.
4. Current defect: usage remains null/absent and the budget check silently does nothing despite an available usage source. The live-status parser can observe usage separately.

## Verification
- A small deterministic adapter/consumer test must show an authoritative Codex observation reaching run/tick accounting and the configured budget decision.
- Fixtures must cover cumulative deltas, duplicates, delayed events, missing fields, reset/compaction discontinuity and cache/reasoning subset semantics without invented component values.
- Parent/child and cwd-change fixtures must prove correct identity binding, orchestration coverage, no double counting, and explicit unknown attribution where session data cannot support a per-role claim.
- With a finite budget crossed by observed usage, the next dispatch is refused. With no accessible usage source, the decision explicitly reports unavailable/degraded enforcement and follows a documented bounded fallback policy; it must not claim active token enforcement.
- Run targeted existing Claude capture regression tests to preserve its current behavior.
- Perform one short opt-in real Codex smoke observation when the required source is accessible; compare the same identity and observation interval, retain only usage metadata, and disclose unsupported host capabilities. Do not repeat the multi-hour incident or the complete115-suite framework merely to reproduce this telemetry defect.

## Constraints / Risks
- Scope: Codex usage acquisition, identity/provenance, integration with existing accounting and budget consumers, and necessary protocol documentation.
- Out of scope: a general review-round cap redesign, global workflow rewrite, billing estimates, model routing changes, or repairs to the already-separated release executor/current-head reader.
- Use authoritative numeric observations only; missing is not zero. Do not sum cumulative snapshots or claim that a later session total belongs to an earlier ride.
- Session logs can contain private conversation and tool payloads. Read only required identity/usage metadata, avoid copying raw logs into the repository, and honor access boundaries and CODEX_HOME configuration.
- No secret or credential is required or referenced by this intake.

## Notes
- User requested only branch alignment and intake on2026-10-28; implementation is not started or authorized by this artifact alone.
- Intake created from discussion and existing evidence, without additional user questions or a token-consumption experiment. Human intake time is unknown; no implementation strategy was selected by the user.
- Relevant sources: .aai/SUBAGENT_PROTOCOL.md; .aai/SKILL_LOOP.prompt.md; .aai/scripts/state.mjs; .aai/scripts/lib/usage-note.mjs; .aai/scripts/live-parsers/codex.mjs; .aai/scripts/live-parsers/claude-code.mjs; .aai/scripts/generate-live-status.mjs.
- Official Codex event documentation: https://learn.chatgpt.com/docs/app-server (thread/tokenUsage/updated).
- Incident analysis: docs/ai/reports/profile-20261028-release-first-run.md (local evidence; not assumed present in a fresh clone).

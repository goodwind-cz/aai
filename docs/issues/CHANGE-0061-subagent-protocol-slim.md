---
id: subagent-protocol-slim
number: 61
type: change
status: done
links:
  pr:
    - 161
  commits:
    - 52cdc55dd25a0515c81486ae75d554873f71988d
---

# Change — Slim the per-dispatch subagent contract (brief-first, result-block-only handoff)

## Summary
- Split .aai/SUBAGENT_PROTOCOL.md (223 lines / ~1850 words) into (a) a compact
  per-dispatch contract every spawned subagent actually needs — result block
  format, single-writer rule, scope discipline, usage-note duty — and (b) the
  orchestrator-side material (merge protocol, review anti-gaming rules,
  validator spawning, platform fallbacks, rationalization tables) that only
  the DISPATCHING side reads. Today the full file is passed as context to
  every subagent (ORCHESTRATION_PARALLEL workstream inputs; SKILL_LOOP role
  dispatches), so every unit pays ~2k words for ~400 words of duty.

## Motivation / Business Value
- Per-unit context cost: with 4-6 subagent spawns per delivered work item
  (measured this session: Planning/Implementation/Validation/Review), the
  non-applicable protocol prose is re-paid on every spawn.
- Brief handoff already exists (BRIEF_TEMPLATE, PLANNING step 11) and is the
  designed context diet; the protocol file should reinforce brief-first, not
  compete with it for context bytes.
- Auditor report roadmap item 3 (2026-07-26); aligned with the
  phase-boundary-compaction principle (artifacts cross boundaries, not
  transcripts).

## Scope
- In scope:
  - New .aai/SUBAGENT_CONTRACT.md (or equivalent): the subagent-facing duty
    sheet — result block YAML, single-writer rule + rationalization rows that
    bind SUBAGENTS, allowed-write list, usage-note duty, timing capture
    rules. Target: <= 60 lines.
  - .aai/SUBAGENT_PROTOCOL.md becomes the orchestrator-side document
    (decomposition criteria, dispatch field contract, review anti-gaming,
    validator spawning, harness usage capture merge duties, merge protocol,
    delivery gate, platform fallback) and POINTS to the contract file as the
    per-dispatch payload; no rule text lost, each rule lives exactly once.
  - Update every reference that passes the protocol to subagents
    (ORCHESTRATION_PARALLEL.prompt.md workstream inputs, SKILL_LOOP.prompt.md
    dispatch context, VALIDATION.prompt.md input list, BRIEF_TEMPLATE.md if
    it names the protocol) to pass the CONTRACT file instead.
  - PROFILES.yaml classification for the new file; prompt-diet accounting
    per ledger rules (SUBAGENT_PROTOCOL.md is outside the TEST-010 glob —
    verify and account accordingly, growth/shrink recorded honestly).
  - Grep-pinned stanza retargeting for any suite pinning protocol prose
    (token-capture TEST-00x pins "Harness-reported usage capture" location;
    enumerate at planning).
- Out of scope:
  - Any semantic change to the rules themselves (pure relocation + pointer).
  - SKILL_TDD/role prompt body changes beyond reference-line updates.
  - BRIEF_TEMPLATE structural changes.

## Affected Area
- .aai/SUBAGENT_PROTOCOL.md, new .aai/SUBAGENT_CONTRACT.md,
  .aai/ORCHESTRATION_PARALLEL.prompt.md, .aai/SKILL_LOOP.prompt.md,
  .aai/VALIDATION.prompt.md (input list), .aai/templates/BRIEF_TEMPLATE.md
  (if referencing), .aai/system/PROFILES.yaml, tests/skills pinned stanzas.

## Desired Behavior (To-Be)
- A dispatched subagent receives ONLY the contract file (+ its brief); the
  orchestrator-side protocol is never injected into unit context.
- Every rule text exists exactly once across the two files; the contract is
  <= 60 lines; the protocol carries a "contract is the per-dispatch payload"
  pointer at its head.

## Acceptance Criteria
- AC-001: contract file exists, <= 60 lines, contains the result block YAML,
  single-writer rule, allowed-write list, usage-note duty, and timing rules
  (grep-verified tokens).
- AC-002: no rule sentence duplicated between the two files (spot-grep of 5
  canonical phrases finds each in exactly one file).
- AC-003: all dispatch-context references (ORCHESTRATION_PARALLEL,
  SKILL_LOOP, VALIDATION input list, BRIEF_TEMPLATE if applicable) name the
  contract file for subagent payloads (grep-verified); no reference passes
  the full protocol to a unit.
- AC-004: prompt-diet suite green with honest accounting; affected pinned
  stanzas retargeted; layer-profiles green with the new file classified.
- AC-005: no regression — targeted suites green locally; binding full-suite
  run on the PR CI.

## Verification
- bash tests/skills/test-aai-prompt-diet.sh
- bash tests/skills/test-aai-token-capture.sh
- bash tests/skills/test-aai-layer-profiles.sh
- grep contracts per AC-001..003; PR CI full framework.

## Constraints / Risks
- No secrets referenced (secrets preflight skipped).
- Risk: a subagent loses a rule it needed (e.g. review anti-gaming rows bind
  the REVIEWER too) — planning must classify each protocol section by WHO it
  binds; sections binding both sides go to the contract.
- Local-run policy (operator direction 2026-07-26): do NOT run the full
  framework locally at any phase; targeted suites only, CI is the binding
  no-regression gate.

## Notes
- Source: auditor roadmap item 3; per-unit token measurements from this
  session's rides (protocol re-paid 4-6x per work item).
- Autopilot intake (/aai-ship): metrics question skipped, human_time_minutes
  intake recorded as null.

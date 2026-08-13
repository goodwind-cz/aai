---
id: update-doctor-field-report
number: 137
type: change
status: done
user_visible: true
ceremony_level: 1
capability: aai-update
links:
  commits:
    - 2a4795c
  pr:
    - 252
---

# Change — aai-update: every downstream update ends with a doctor field report

## Summary
- Owner ask 2026-08-13 (option 5 of the platform-coverage proposal): CI will
  never be "all platforms" — the downstream fleet is. `/aai-doctor` (CHANGE-0135)
  can already diagnose a machine in one command; what is missing is the loop
  that actually RUNS it where the evidence lives. The concrete gap it closes
  first: the WSL-functional-host residual recorded in decisions.jsonl on
  2026-08-13 — one doctor report from such a machine is the real proof CI
  cannot produce.
- Extend the update flow so a downstream machine produces that evidence by
  default: after a successful `/aai-update`, run the doctor and persist a
  paste-able report, so "what exactly does this machine look like" is a file
  the owner can attach, not a debugging session.

## Acceptance Criteria
- AC-001 (post-update doctor run): after a successful update, `aai-update`
  runs the vendored doctor (`--json`) and writes the report to a stable,
  documented location (docs/ai/reports/ pattern, timestamped, machine-tagged);
  the human-visible tail prints the one-line DOCTOR verdict plus where the
  full report landed. A doctor failure or missing prerequisite NEVER fails
  the update itself — degrade to a named SKIP line (resilience-contract
  style).
- AC-002 (config): the behavior is configurable in the project-local AAI
  config (on by default OR off by default — Planning decides against the
  existing config precedent and records why); a config value of off yields
  one line naming that it was skipped by config, never silence.
- AC-003 (zero surprise): no network, no LLM, no new dependencies beyond
  what doctor already needs (node); on hosts where the doctor's Windows
  categories SKIP, the report still lands with those categories honestly
  SKIPped; runtime budget for the doctor step stays bounded (existing
  doctor timeout discipline).
- AC-004 (fleet value): the report content includes the doctor JSON plus a
  minimal provenance header (AAI version stamp, UTC timestamp, platform
  string) so reports from multiple machines are comparable; docs
  (USER_GUIDE + aai-update product doc + aai-doctor product doc pointer)
  state the loop: update → report → attach when filing an issue.
- AC-005: tests per repo conventions, RED-first for the new contract lines
  (report written on success path, SKIP line on induced doctor failure,
  config off path); bash suite for the update script surface.

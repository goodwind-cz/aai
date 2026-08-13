---
id: doctor-win-selftest
number: 135
type: change
status: done
user_visible: true
ceremony_level: 1
capability: aai-doctor
links:
  commits:
    - dbeda70
  pr:
    - 249
---

# Change — aai-doctor: Windows wrapper self-test + agent-CLI capability probe (test reality, not the CI image)

## Summary
- Owner ask 2026-08-12: "mohli bychom ty powershell scripty a chovani na
  windows a v codex nejak lepe testovat?" CI covers GitHub's image; the
  failures that matter surface on DOWNSTREAM machines (owner's Codex
  Windows boxes: sticky escalation CHANGE-0126, Path/PATH dup CHANGE-0133
  — both found by the owner, not by us).
- Extend aai-doctor with a self-test section a downstream machine runs in
  one command after aai-update, producing a paste-able diagnostic report:
  the last two field incidents would have been machine-diagnosed instead
  of hand-reverse-engineered from logs.

## Acceptance Criteria
- AC-001 (Windows wrapper self-test, runs only where pwsh/powershell
  exists; named SKIP elsewhere): doctor invokes the real
  aai-run-tests.ps1 three-arm smoke locally (success marker/exit,
  timeout 124, induced spawn-fail 125 + AAI-SPAWN-ERROR) using the same
  encoding-proof file-marker technique as the CI step; reports each arm
  PASS/FAIL with the AAI-BRANCH / AAI-TIMEOUT diag lines captured.
- AC-002 (environment diagnosis): doctor detects and reports
  case-colliding environment variable groups (Path/PATH class), the
  effective PowerShell engines present (5.1/pwsh + versions), Git Bash
  candidates found, and WSL state (absent / present-no-distro /
  functional) using the wrapper's own probe functions — never a duplicate
  implementation.
- AC-003 (agent-CLI capability probe): doctor reports which agent CLIs
  are present (claude, codex, gemini) with versions, and for codex the
  detected multi-agent capability fields from the SUBAGENT_PROTOCOL
  contract (spawn_agent_available etc.) to the extent detectable
  read-only; absent CLIs are named ABSENT, never fabricated.
- AC-004 (honest output contract): one machine-parsable summary block +
  human text; degraded sections named with reasons (resilience-contract
  style); zero network, zero LLM; exit 0 even on findings (doctor
  diagnoses, never blocks) unless --strict.
- AC-005: tests per repo conventions (Pester for ps1 pieces incl. both
  engines once CHANGE-0134 lands; bash suite for the mjs/sh glue),
  RED-first; product doc + USER_GUIDE updated truthfully.

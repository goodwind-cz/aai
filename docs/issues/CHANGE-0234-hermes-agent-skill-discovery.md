---
id: hermes-agent-skill-discovery
type: change
number: 234
status: done
links:
  pr: []
  commits: []
---

# Show AAI skills in Hermes Agent

## Summary
Make the existing AAI skill catalog discoverable and selectable in Hermes Agent.

## Motivation / Business Value
Users working in Hermes Agent should be able to find and invoke AAI skills from its skill selection interface without manually locating canonical prompt files.

## Scope
- In scope: Hermes-compatible discovery of existing universal AAI skills, installation/update integration where required, and concise usage documentation.
- Out of scope: new workflow roles, changes to skill semantics, a custom Hermes UI, and redesign of other agent integrations.

## Affected Area
- AAI skill wrappers and discovery metadata.
- Installation and synchronization tooling, including POSIX and PowerShell paths if affected.
- Agent integration documentation and targeted regression coverage.

## Desired Behavior (To-Be)
After the documented AAI setup or update procedure, Hermes Agent lists the supported AAI skills with recognizable names and useful descriptions. Selecting a skill invokes its existing canonical AAI prompt in the intended project context. Updates refresh managed entries without deleting unrelated user skills.

## Acceptance Criteria
- AC-001: In a documented supported Hermes Agent version, the native skill listing/selection interface exposes the supported universal AAI skills; any unsupported entries are explicitly listed with reasons.
- AC-002: Selecting `aai-intake` loads the existing intake entrypoint for the current AAI project, rather than a separate workflow implementation.
- AC-003: Repeating setup/update does not duplicate entries; changes to managed skill metadata are reflected after the documented reload procedure.
- AC-004: Setup/update preserves unrelated user skills and existing agent integrations.
- AC-005: Documentation identifies the supported Hermes version, discovery location, setup/update commands, and any reload requirement.

## Verification
- Planning identifies the actual Hermes skill-discovery contract and records the supported version before choosing paths or metadata formats.
- Run a native Hermes smoke check: list skills, select `aai-intake`, and confirm resolution to the current project's canonical prompt. Record version and observed results.
- Add targeted checks for any changed generation/synchronization behavior, including repeated updates and preservation of user entries; run them through the canonical AAI test wrapper.
- Run relevant existing integration checks for affected agent surfaces.

## Constraints / Risks
- Hermes discovery paths, metadata requirements, and reload behavior are not yet verified; do not assume another agent's directories are compatible.
- Reuse canonical `.aai/SKILL_*.prompt.md` files and avoid manually maintained duplicate catalogs.
- Honor the dependency-free tooling contract and cross-platform parity for any changed paired scripts.
- No credentials or secrets are referenced by this request.

## Notes
- User request: show the skill offering in Hermes Agent as well.
- Assumption: Hermes Agent refers to the user's Hermes agent runtime, and the requested offering is the existing universal AAI skill catalog.
- This intake captures the requested behavior; implementation has not started.

---
id: pr-capability-preflight
type: change
number: 204
status: done
links:
  spec: null
  rfc: downstream-pr-ceremony-reliability
  pr:
    - TBD
  commits:
    - 227ca445e2e828cb428d7e537f2cf791fa9c2a91
---

# Noninteractive provider readiness before PR writes

## Summary
Add bounded, noninteractive provider readiness checks before the PR ceremony changes Git or document lifecycle state. This is phase A1 of the downstream PR reliability RFC.

## Motivation / Business Value
The supplied downstream report discovered a missing Azure DevOps extension after push. Detect unavailable prerequisites before numbering, commits and push, with a named remedy. Historical downstream reproduction and live Azure access remain unverified.

## Scope
In scope: explicit repository identity, bounded provider probes, named refusal diagnostics, PR prompt integration, hermetic behavior tests and companion profile/prompt-diet updates.

Out of scope: PR creation, resumption and stamping; reservation transport; scope and waiver representations; global gate policy; live external writes; automatic extension installation.

## Affected Area
Provider platform tooling, PR ceremony prompt, skill regression tests, profile classification and prompt-diet accounting.

## Desired Behavior (To-Be)
Resolve repository, remote, source and base identity before probing. Azure checks verify the client, installed extension and authenticated repository read access without interactive installation or credential disclosure. Bound each operation and distinguish missing prerequisites, authentication, network, timeout and unknown access failures. Successful read verification leaves create permission explicitly unknown. Preserve GitHub and generic routes.

## Acceptance Criteria
- AC-001: Missing or ambiguous repository/remote/source/base identity is refused before provider calls.
- AC-002: Azure client, installed azure-devops extension and authenticated repository read probes are bounded and noninteractive; success reports read verification and unknown create permission.
- AC-003: Missing client/extension, authentication, network, timeout and unclassified access failures produce a named remedy and nonzero refusal.
- AC-004: The PR prompt invokes preflight before numbering, staging, feature/close commit or push; refusal preserves STATE, index, HEAD and reservation refs.
- AC-005: Existing GitHub and generic routes remain supported under their explicit readiness contracts.
- AC-006: New vendored files are classified and added prompt bytes are accounted for in the prompt-diet ledger and checkpoint.

## Verification
Planning defines executable regression commands and evidence paths before freeze. Hermetic CLI/Git fixtures must exercise successful read verification, each refusal class, bounded hung probes, noninteractive extension checks, argument identity and preservation of local state. Capture RED evidence before implementation and independent validation after implementation.

## Constraints / Risks
Read access cannot attest permission for a future PR creation. Never install prerequisites automatically or print credentials. No local secret value is referenced by this intake; existing provider authentication is used. Preserve unrelated drafts and local work. No elapsed-time speedup is promised.

## Notes
The owner invoked aai-ship for the umbrella RFC; this intake records the first bounded ride under that authorization. Planning selects the implementation strategy. Human intake time is not supplied and remains null. Later RFC stages stay separate; inherited/global gate policy stays unchanged pending explicit owner choice.

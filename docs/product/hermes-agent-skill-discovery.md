---
id: hermes-agent-skill-discovery
type: product
capability: hermes-agent-skill-discovery
status: current
delivered_by:
  - hermes-agent-skill-discovery
spec: docs/specs/SPEC-0259-spec-hermes-agent-skill-discovery.md
updated: 2026-10-29
---

# AAI skills in Hermes Agent

## What it does

Hermes Agent can discover and select the shared AAI skills in a trusted Git
project. The existing wrappers load the current project's canonical prompts;
no additional skill catalog or installer is required.

## How to use it

Follow [Hermes setup and refresh](../USER_GUIDE.md#hermes-agent): sync the
extended AAI profile, trust the project in your intended Hermes profile, then
start Hermes inside that project. Select `/aai-intake`. After updating AAI,
use `/reload-skills` or start a fresh session.

## Data model

None. Existing `.agents/skills` files and Hermes profile trust settings apply.

## Interfaces and contracts

Existing AAI extended sync installs the wrappers. Hermes `skills trust`, the
native slash menu and `/reload-skills` provide discovery and refresh. Trust
is an explicit user action, separate from AAI sync.

## Limits and non-goals

Verified baseline: Hermes revision `bf0203a794a07aac3ff764972ab9087baa4e4f4e`
on macOS. Other revisions, Windows-native Hermes and core AAI installations
are unverified. Disabled/quarantined skills and name collisions remain
Hermes-controlled. Deprecated wrappers retain their existing behavior.
Selection evidence does not assert downstream model execution.

## Links

- Request: [Hermes discovery](../issues/CHANGE-0234-hermes-agent-skill-discovery.md)
- Spec: [Discovery contract](../specs/SPEC-0259-spec-hermes-agent-skill-discovery.md)
- Verification: [Review evidence](../ai/reviews/review-hermes-agent-skill-discovery-20261029T000554Z.md)

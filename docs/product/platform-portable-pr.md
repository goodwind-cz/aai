---
id: platform-portable-pr
type: product
capability: platform-portable-pr
status: current
delivered_by:
  - platform-portable-pr
spec: docs/specs/SPEC-0103-spec-platform-portable-pr.md
updated: 2026-07-28
---

# Platform-portable PR ceremony

## What it does

The PR ceremony (`/aai-pr`, `/aai-ship`) now works beyond GitHub. A
deterministic probe classifies the origin remote and the ceremony
branches accordingly; where reviewer bots do not exist, the factory's own
independent code review takes their place — quality is never silently
skipped on any git host.

## How to use it

- Nothing changes on GitHub. On Azure Repos the ceremony uses `az repos`
  commands; on any other host GENERIC MODE runs the internal review and
  hands the merge to you with an explicit message.
- Probe manually: `node .aai/scripts/pr-platform.mjs` (add `--json` for
  machine output; embedded credentials are always masked).

## Data model

- Probe output: `PLATFORM <github|azure|unknown|none> remote=<sanitized>`;
  `--json` = `{platform, remote}` (sanitized only).

## Interfaces and contracts

- Reviewer-fallback: on a platform without reviewer bots, an internal
  SKILL_CODE_REVIEW dispatch on the final PR diff is REQUIRED before any
  merge-readiness claim; findings are published as PR threads with
  closing replies; the PR records "internal review substituted for
  absent bot layer".
- GENERIC MODE ends with: "platform PR API unavailable — internal review
  substituted, merge is yours"; findings live in docs/ai/reports/ + spec
  dispositions. The agent-never-merges boundary is unchanged everywhere.

## Limits

- Azure command forms are doc-verified; the live round trip (incl. thread
  publication via `az devops invoke --resource pullRequestThreads`) is
  the Spec-AC-06 evidence contract at first Azure adoption (Review-By
  2026-08-15). GitLab/Bitbucket adapters are future variants.
- A GitHub repo with reviewer bots disabled keeps the empty-sweep
  shortcut (frozen-spec design; recorded hardening candidate R1).

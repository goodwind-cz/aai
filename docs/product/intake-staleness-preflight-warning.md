---
id: intake-staleness-preflight-warning
type: product
capability: intake-staleness-preflight-warning
status: current
delivered_by:
  - intake-staleness-preflight-warning
spec: docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md
updated: 2026-09-01
---

# Stale-checkout warning before intake

## What it does

Before any AAI intake (change, bug, RFC, hotfix, techdebt, research, PRD, or
release) asks its first question, the factory now checks — read-only — whether
the checkout you're drafting against is behind. It compares your current
branch against its upstream and every initialized submodule against its own
remote, using a real `git fetch` rather than trusting a possibly-stale local
cache. If anything is behind, you see one named line per stale ref (which
branch or submodule, and by how many commits) before the first question is
asked. If nothing is behind — the common case — you see nothing at all: no
extra noise on a clean run. Either way, intake always proceeds to its first
question; this is a heads-up, never a gate. You decide whether to pull first
or keep going.

## How to use it

Nothing to turn on — it runs automatically at the start of every intake type.
A typical stale-branch run looks like:

```
AAI-STALE: branch main is 3 commit(s) behind origin/main
```

A stale submodule looks like:

```
AAI-STALE: submodule vendor/aai is 2 commit(s) behind origin/main
```

Both can appear together, one line each, if both are true. To check it
directly outside of intake: `node .aai/scripts/intake-staleness-check.mjs`
from the repository root — it prints the same lines (or nothing) and always
exits 0. Useful flags: `--no-fetch` (compare against cached remote-tracking
refs only, skip the network call) and `--timeout-ms <n>` /
`--budget-ms <n>` to tune the network bound in constrained environments.

## Data model

None. The check reads git refs and `.gitmodules`; it stores nothing on disk
and updates nothing but git's own `refs/remotes/*` (via `git fetch`, which it
already did before this feature existed whenever a developer or CI ran one).

## Interfaces and contracts

- New file: `.aai/scripts/intake-staleness-check.mjs` (Node, zero dependencies).
  Exit code is always `0` for every runtime outcome, including every
  degradation path — `2` only for a human CLI usage error (unknown flag,
  missing value). Stdout is either empty or one `AAI-STALE: branch ...` /
  `AAI-STALE: submodule ...` line per stale ref; never anything else.
- Flags: `--repo <path>` (default: cwd), `--no-fetch`, `--timeout-ms <n>`
  (default 5000, per `git fetch` call), `--budget-ms <n>` (default 10000,
  total preflight wall-clock cap).
- New shared prompt block: `## STALENESS PREFLIGHT` in
  `.aai/INTAKE_COMMON.md`, referenced by all nine shared intake entry-point
  files (`.aai/SKILL_INTAKE.prompt.md` and the eight
  `.aai/INTAKE_*.prompt.md` per-type prompts) before their first question.
  This is prompt wiring, not a versioned API — it can be reworded without
  a compatibility concern as long as the ordering (before the first
  question) and the silent-degradation behavior hold.
- Degrades silently (no output, no error, exit 0, no hang) when: the network
  fetch fails, times out, or requires credentials that aren't available; the
  current branch has no configured upstream (including a detached HEAD); the
  repository has no submodules; or `git` itself is unavailable.

## Limits and non-goals

- Never mutates the working tree, the index, or any local branch ref — the
  only git write is `git fetch` (refs-only). It never runs `git pull`,
  `git submodule update`, or any other tree-changing command, and it never
  blocks or refuses intake on a stale tree.
- Does not replace or change `/aai-update`'s own sync mechanism — that
  remains a separate, explicit operator action.
- Does not detect a submodule configured with `.gitmodules`'
  `branch = .` (git's "track superproject branch" sentinel): that specific
  configuration currently degrades silently even when the submodule is
  genuinely behind (tracked as a known follow-up,
  `fu-stale-check-submodule-branch-dot`).
- No PowerShell/Windows-native twin script; the Node implementation runs
  the same on every platform AAI already supports.
- Whether an assistant actually reads and relays the warning before its
  first question is a prompt-following behavior, not something this feature
  can enforce mechanically — the wiring guarantees the line is there to
  read, in the right place, before the question.

## Links

- Request: docs/issues/CHANGE-0168-intake-staleness-preflight-warning.md
- Spec: docs/specs/SPEC-0158-spec-intake-staleness-preflight-warning.md
- Validation evidence: docs/ai/tdd/green-TEST-0020-20260831T210938Z.log (and
  the sibling TEST-0021..0025 green logs in the same directory);
  docs/ai/reviews/review-intake-staleness-preflight-warning-20260831T223528Z.md

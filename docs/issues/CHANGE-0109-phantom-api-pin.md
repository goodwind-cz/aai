---
id: phantom-api-pin
number: 109
type: change
status: done
user_visible: false
links:
  pr:
    - 212
  commits:
    - d2c9e7ef503c08034ac31ac7711864df92ad7834
---

# Change — phantom-API pin: plausible-but-nonexistent runtime APIs stop surviving review

## Summary
- Weakness 6 of the 2026-08-01 audit (bot-dependency, 74 % of sidecar defects
  bot-found) got a fresh live instance: `process.getpgrp()` — a POSIX cousin
  that reads as obviously real — shipped inside orphan-sweep's self-kill
  guard, survived the author AND an L3-grade internal review, and was caught
  only by a PR bot (CHANGE-0108). Its try/catch fallback would have silently
  guarded nothing in production.
- Deterministic slice shipped now: hygiene-pack test_092 pins a denylist of
  known-phantom/removed Node APIs (`process.getpgrp/getpgid/setpgrp`,
  callback `fs.exists(`, `require.main.filename` in ESM) across
  `.aai/scripts/**/*.mjs`; docs/knowledge/LEARNED.md records the rule that
  every NEWLY-CALLED runtime API in a diff gets a 10-second existence probe
  (`node -e 'console.log(typeof <api>)'`) before review sign-off.
- Honest scope: the grep pins only APIs that have already bitten or are
  notorious; it is a ratchet (each new phantom found joins the list), not a
  general existence checker — that would need AST + runtime introspection
  and is deliberately NOT built without evidence it pays.

## Acceptance Criteria
- AC-001: test_092 FAILS when a phantom API call site exists in
  .aai/scripts (RED-proven with a planted probe) and PASSES on the clean
  tree.
- AC-002: LEARNED.md carries the existence-probe rule with the incident
  citation.

## Verification
- Isolated RED/GREEN run of test_092 (full hygiene-pack suite locally hits
  the known pre-existing worktree-scan false-fail — memory-recorded class;
  CI, which has no worktrees, is the authority).

## Constraints / Risks
- Ceremony L1, strategy direct (single grep test + knowledge entry).
- Denylist ratchet can lag new phantoms; the LEARNED probe rule is the
  forward guard.

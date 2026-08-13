---
id: changelog-payload-hardening
number: 141
type: change
status: draft
user_visible: false
ceremony_level: 1
capability: aai-release
---

# Change — released-CHANGELOG class pin + dashboard payload-escaping fix

## Summary
- Two proven defects from the CHANGE-0140 ride, dispositioned as one
  follow-up (decisions.jsonl 2026-08-13T18:47):
  1. **CHANGELOG released-region protection is scope-luck, not a class
     guard.** The third glued/damaged-heading incident (bc056cd glued the
     released v2026.08.13.2 heading onto a bullet) was caught only because
     TEST-026 happens to pin the immediately-previous scope's literal.
     The review's survey: every existing CHANGELOG pin is scope-specific;
     glue, deletion, retitle or reorder of ANY OLDER released heading is
     caught by nothing automated.
  2. **generate-dashboard.mjs template embed is corruptible** (proven
     adversarially by review AND flagged independently by Copilot):
     backslash-doubling runs LAST and re-exposes the backtick escape, a
     literal backtick or dollar-brace in any payload string kills the
     whole page (SyntaxError), and String.replace dollar-patterns can
     corrupt the substitution. Latent today only because run notes never
     reach the embedded payload.
  3. Minor fold-in: the userguide-drift forward extractor omits the
     markdown-link form ([text](/aai-x)) — false-negative only.

## Acceptance Criteria
- AC-001 (class pin): a release-suite test byte-compares the CHANGELOG's
  released region (from the newest released heading downward) against
  `git show <latest-release-tag>:CHANGELOG.md` — glue, deletion, retitle
  and reorder of ANY released heading at any age FAIL naming the first
  divergence; unreleased-section edits never trip it; soft-skip with a
  named reason only when no release tag or the tag's file is unreachable;
  RED-proven by replaying the bc056cd glue and by a deep-history mutation.
- AC-002 (escaping fix-at-cause): the dashboard template embed becomes
  corruption-proof — backslash-first ordering, backtick and dollar
  escaping, and a function-replacement (or equivalent non-interpolating)
  substitution for the data payload; RED-proven with hostile payload
  fixtures (backtick, dollar-brace, backslash runs, replacement patterns
  like $&) that kill the pre-change page and render post-change; real
  ledger output byte-stable except where the fix applies.
- AC-003 (drift extractor): markdown-link-form skill mentions are
  extracted by the forward check; RED with a planted link-form bare
  mention.
- AC-004: suites green (release, dashboard, userguide-drift, metrics
  test_120 single-occurrence lib pin untouched), RED_CLASS-stamped logs,
  truthful docs where behavior is described; no exit-contract changes.
